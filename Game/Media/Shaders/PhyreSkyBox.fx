/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Shaders for rendering skyboxes.

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"
#include "PhyreShaderDefsD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

sampler TrilinearFilterSampler
{
	Filter = Min_Mag_Mip_Linear;
    AddressU = Wrap;
    AddressV = Wrap;
};

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
};

DepthStencilState DepthState {
  DepthEnable = TRUE;
  DepthWriteMask = All;
  DepthFunc = Less_equal;
};

RasterizerState NoCullRasterState
{
	CullMode = None;
};

//////////////////////
// SkyBox rendering //
//////////////////////

#ifdef __ORBIS__
	#define POSTYPE float4
#else //! __ORBIS__
	#define POSTYPE float3
#endif //! __ORBIS__

struct SkyBoxIn
{
	POSTYPE	Position			: POSITION;
};

struct SkyBoxOut
{
	float4	Position			: SV_POSITION;
	float3	Direction			: TEXCOORD0;
};

TextureCube <float4> SkyBoxSampler;

SkyBoxOut SkyBoxVS(SkyBoxIn IN)
{
	// Generate 3 verts for triangle covering the screen.
	SkyBoxOut OUT;

	float2 tex = IN.Position.xy;
	OUT.Position = float4(tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 1.0f, 1.0f);

	float3 viewplanePos = float3(OUT.Position.xy, -1);
	float4 p1 = mul(float4(viewplanePos, 1), ProjInverse);
	float4 worldViewDir = mul(float4(p1.xyz, 0), ViewInverse);

	OUT.Direction = worldViewDir.xyz;

	return OUT;
}

float4 SkyBoxPS(SkyBoxOut IN) : FRAG_OUTPUT_COLOR0
{
	// Look up the cubemap.
	float4 lightProbeLookup = SkyBoxSampler.Sample(TrilinearFilterSampler, IN.Direction);

	// Render it.
	return lightProbeLookup;
}

PSDeferredOutput SkyBoxDeferredPS(SkyBoxOut IN) 
{
	// Look up the cubemap.
	float4 lightProbeLookup = SkyBoxSampler.Sample(TrilinearFilterSampler, IN.Direction);

	PSDeferredOutput OUT;
	OUT.Colour = lightProbeLookup;	// Albedo Colour.xyz, Emissiveness
	OUT.NormalDepth = float4(0,0,0,0);	// Normal.xyz, Gloss

	return OUT;
}

technique11 ForwardRender
<
	string PhyreRenderPass = "Opaque";
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, SkyBoxVS() ) );
		SetPixelShader( CompileShader( ps_4_0, SkyBoxPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

technique11 DeferredRender
<
	string PhyreRenderPass = "DeferredRender";
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, SkyBoxVS() ) );
		SetPixelShader( CompileShader( ps_4_0, SkyBoxDeferredPS() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
