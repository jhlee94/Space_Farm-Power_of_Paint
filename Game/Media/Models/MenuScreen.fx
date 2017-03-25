/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\Shaders\PhyreShaderPlatform.h"

float4x4 WorldViewProjection		: WorldViewProjection;	
float4x4 World;

float3 Colour : COLOUR = float3(1.0f,1.0f,1.0f);
float Alpha : ALPHA = 1.0f;
float CameraAspectRatio;

Texture2D <float4> BitmapFontTexture;
float3 textColor		= { 1.0f, 1.0f, 1.0f };

static const float3 BaseColour = float3(0.75f,1.0f,0.78f);

///////////////////////////////////////////////////////////////
// structures /////////////////////
///////////////////////////////////////////////////////////////

struct VertexIn
{
#ifdef __ORBIS__
	float4 Position	: POSITION;
#else //! __ORBIS__
	float3 Position	: POSITION;
#endif //! __ORBIS__
};

struct VertexOut
{
	float4 Position		: SV_POSITION;
};

struct VPInput
{
#ifdef __ORBIS__
	float4 position		: POSITION;
#else //! __ORBIS__
	float2 position		: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct VPOutput
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
};



sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};


///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

VertexOut RenderVP(VertexIn input)
{
	VertexOut output;
	output.Position = mul(float4(input.Position.xyz, 1.0), WorldViewProjection);
	return output;
}

float4 RenderFP(VertexOut input) : FRAG_OUTPUT_COLOR0
{
	return float4(BaseColour * Colour * Alpha * 0.5f,1.0f);
}

#ifdef __ORBIS__
VertexOut FullscreenVP(float4 vertex : POSITION)
#else //! __ORBIS__
VertexOut FullscreenVP(float3 vertex : POSITION)
#endif //! __ORBIS__
{
	VertexOut output;
	output.Position = float4(vertex.xyz, 1.0);
	return output;
}
float4 DarkenBackgroundFP(VertexOut input) : FRAG_OUTPUT_COLOR0
{
	return float4(0,0,0,0.75f);
}


VPOutput TextVP(VPInput IN)
{
	VPOutput OUT;
	
	OUT.position = mul(float4(IN.position.xy, 0.0f, 1.0f), World);
	OUT.position.x *= CameraAspectRatio;
	OUT.uv = IN.uv;
	
	return OUT;
}

float4 TextFP(VPOutput IN) : FRAG_OUTPUT_COLOR0
{
	float a = BitmapFontTexture.SampleLevel(LinearClampSampler, IN.uv, 0).x;

	return float4(BaseColour * textColor * a, textColor.r * a * 2.0);
}

#ifndef __ORBIS__

BlendState NoBlend 
{
  AlphaToCoverageEnable = FALSE;
  BlendEnable[0] = FALSE;
  RenderTargetWriteMask[0] = 15;
};
BlendState AdditiveBlend 
{
    AlphaToCoverageEnable = FALSE;
	BlendEnable[0] = TRUE;
	SrcBlend[0] = ONE;
	DestBlend[0] = ONE;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	BlendEnable[1] = FALSE;
	RenderTargetWriteMask[0] = 15;
};
BlendState LinearBlend 
{
    AlphaToCoverageEnable = FALSE;
	BlendEnable[0] = TRUE;
	SrcBlend[0] = Src_Alpha;
	DestBlend[0] = Inv_Src_Alpha;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	BlendEnable[1] = FALSE;
	RenderTargetWriteMask[0] = 7;
};
DepthStencilState NoDepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};
RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
	DepthBias = 0;
	ScissorEnable = false;
};


technique11 DrawMenu
<
	string PhyreRenderPass = "Transparent";
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, RenderVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderFP() ) );
		
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_AlphaBlend
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextFP() ) );
		
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

technique11 DarkenBackground
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, DarkenBackgroundFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__
