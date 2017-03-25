/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreShaderCommonD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

// A simple template shader without using Phyre's ubershader approach.

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global shader parameters.

// Un-tweakables
float4x4 World					: World;
float4x4 WorldView				: WorldView;
float4x4 WorldInverse			: WorldInverse;
float4x4 WorldViewProjection	: WorldViewProjection;
float4x4 WorldViewInverse		: WorldViewInverse;

// Material Parameters
float4 MaterialColor : MATERIALCOLOR = float4(1.0f,1.0f,1.0f,1.0f);
float4 MaterialTransparency : MATERIALTRANSPARENCY = float4(1,1,1,1);
float4 MaterialAmbient : MATERIALAMBIENT = float4(0,0,0,0);
float4 MaterialEmission : MATERIALEMISSION = float4(0,0,0,0);
float4 MaterialDiffuse : MATERIALDIFFUSE = float4(1,1,1,1);

// Textures
Texture2D <float4> TextureSampler;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Structures
struct VSInput
{
	float4 Position		: POSITION;
	float4 Normal		: NORMAL;
	float2 Uv			: TEXCOORD0;
};

struct VSOutput
{
	float4 Position		: SV_POSITION;
	float2 Uv			: TEXCOORD0;
};

sampler LinearClampSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Vertex shaders

// Default forward render vertex shader
VSOutput ForwardRenderVS(VSInput IN)
{
	VSOutput Out = (VSOutput)0;
	float3 position = IN.Position.xyz;
	Out.Position = mul(float4(position.xyz,1), WorldViewProjection);
	Out.Uv = IN.Uv;
	return Out;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment shaders.

// Forward render fragment shader
float4 ForwardRenderFP(VSOutput In) : FRAG_OUTPUT_COLOR0
{
	float4 shadingResult = MaterialColor;

	float3 lightResult = 1;
	lightResult *= MaterialDiffuse.xyz;
	lightResult += MaterialAmbient.xyz;

	float4 texValue = TextureSampler.Sample( LinearClampSampler, In.Uv );
	
	float4 result = saturate(shadingResult + texValue);

	result.xyz *= lightResult;
	result.xyz += MaterialEmission.xyz;

	result.a = MaterialTransparency.x;
	
	return result;
}

#ifndef __ORBIS__

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Render states.
BlendState NoBlend
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

BlendState LinearBlend
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = SRC_ALPHA;
	DestBlend[0] = INV_SRC_ALPHA;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ZERO;
	DestBlendAlpha[0] = ZERO;
	BlendOpAlpha[0] = ADD;
	BlendEnable[1] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

DepthStencilState DefaultDepthState
{
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE;
};

RasterizerState DefaultRasterState
{
	CullMode = None;
};

RasterizerState CullBackRasterState
{
	CullMode = Front;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Techniques.
technique11 ForwardRender
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, ForwardRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DefaultDepthState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 ForwardRenderAlpha
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, ForwardRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DefaultDepthState, 0 );
		SetRasterizerState( CullBackRasterState );
	}
}

#endif