/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

Texture2D <float4> ColorBuffer;
Texture2D <float4> DepthBuffer;

struct VertexIn
{
#ifdef __ORBIS__
	float4 vertex			:	POSITION;
#else //! __ORBIS__
	float3 vertex			:	POSITION;
#endif //! __ORBIS__
	float2 uv				:	TEXCOORD0;
};

struct VertexOut
{
	float4 position			: SV_POSITION;
	float2 uv				: TEXCOORD0;
};

struct FragIn
{
	float2 uv				: TEXCOORD0;
	float4 screenPosition	: WPOS;
};

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

VertexOut MaterialPostEffectVS(VertexIn input)
{
	VertexOut output;
	output.position = float4(input.vertex.xy, 1, 1);
	float2 uv = input.uv;
#ifndef __ORBIS__
	uv.y = 1.0f - input.uv.y;
#endif //! __ORBIS__
	output.uv = uv;
	return output;
}

float4 MaterialPostEffectPS(VertexOut input) : FRAG_OUTPUT_COLOR
{
	float2 q = input.position.xy / ViewportWidthHeight.xy;
	float4 color = ColorBuffer.SampleLevel(LinearClampSampler, input.uv.xy, 0);
	// Vignette
	return color *= 0.5f + 0.5f * pow(16.0f * q.x * q.y * (1.0f - q.x) * (1.0f - q.y), 0.25f);
}

#ifndef __ORBIS__

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};

BlendState NoBlend
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

DepthStencilState DepthState {
  DepthEnable = FALSE;
  DepthWriteMask = Zero;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

technique11 MaterialPostEffect
{
	pass p0
	{
		SetVertexShader(CompileShader( vs_4_0, MaterialPostEffectVS()));
		SetPixelShader(CompileShader( ps_5_0, MaterialPostEffectPS()));

		SetBlendState(NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__