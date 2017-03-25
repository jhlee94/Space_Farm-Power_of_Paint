/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

float4 GaussianBlurBufferSize;
float4 GaussianOutputScale;
float4 UvScaleBias;
float LuminanceThreshold;
float LuminanceScale;
Texture2D <float4> GlowBuffer;
Texture2D <float4> ColorBuffer;

///////////////////////////////////////////////////////////////
// structures /////////////////////
///////////////////////////////////////////////////////////////

struct FullscreenVertexIn
{
#ifdef __ORBIS__
	float4 vertex	: POSITION;
#else //! __ORBIS__
	float3 vertex	: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct FullscreenVertexOut
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
};

struct GaussianVertexOut
{
	float4 position			: SV_POSITION;
	float2 uv				: TEXCOORD0;
	float4 uvs0				: TEXCOORD1;
	float4 uvs1				: TEXCOORD2;
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

FullscreenVertexOut FullscreenVP(FullscreenVertexIn input)
{
	FullscreenVertexOut output;

	output.position = float4(input.vertex.xy, 1, 1);
	float2 uv = input.uv;

#ifndef __ORBIS__
	uv.y = 1.0f-uv.y;
#endif //! __ORBIS__
	output.uv = uv;

	return output;
}

// Output fullscreen vertex.
GaussianVertexOut GaussianUpscaleXVP(FullscreenVertexIn input)
{
	GaussianVertexOut output;
	output.position = float4(input.vertex.xyz, 1.0f);

	float2 uv = input.uv;
#ifndef __ORBIS__
	uv.y = 1.0f-uv.y;
#endif //! __ORBIS__
	output.uv = uv;

	float2 off1 = float2(1.0f/GaussianBlurBufferSize.x,0);
	float2 off2 = float2(2.0f/GaussianBlurBufferSize.x,0);

	// pack the texcoord attributes
	output.uvs0 = float4( uv - off2, uv - off1 );
	output.uvs1 = float4( uv + off1, uv + off2 );
		
	return output;
}
// Output fullscreen vertex.
GaussianVertexOut GaussianUpscaleYVP(FullscreenVertexIn input)
{
	GaussianVertexOut output;
	output.position = float4(input.vertex.xyz, 1.0f);

	float2 uv = input.uv;
#ifndef __ORBIS__
	uv.y = 1.0f-uv.y;
#endif //! __ORBIS__
	output.uv = uv;
	
	float2 off1 = float2(0,1.0f/GaussianBlurBufferSize.y);
	float2 off2 = float2(0,2.0f/GaussianBlurBufferSize.y);

	// pack the texcoord attributes
	output.uvs0 = float4( uv - off2, uv - off1 );
	output.uvs1 = float4( uv + off1, uv + off2 );

	return output;
}



#define kWeight0 4.0
#define kWeight1 2.0
#define kWeight2 1.0
#define kWeightSum (half)(1.0/(kWeight0+kWeight1+kWeight1+kWeight2+kWeight2))

float4 GaussianBlurUpscaleFP(GaussianVertexOut input) : FRAG_OUTPUT_COLOR
{
	float4 sampleCentre = GlowBuffer.Sample(LinearClampSampler,input.uv);
		
	float4 sample0 = GlowBuffer.Sample(LinearClampSampler,input.uvs0.xy);
	float4 sample1 = GlowBuffer.Sample(LinearClampSampler,input.uvs0.zw);
	float4 sample2 = GlowBuffer.Sample(LinearClampSampler,input.uvs1.xy);
	float4 sample3 = GlowBuffer.Sample(LinearClampSampler,input.uvs1.zw);

	float4 rslt = sampleCentre * (kWeight0 * kWeightSum);
	rslt += sample0 * (kWeight2 * kWeightSum);
	rslt += sample1 * (kWeight1 * kWeightSum);
	rslt += sample2 * (kWeight1 * kWeightSum);
	rslt += sample3 * (kWeight2 * kWeightSum);
	return rslt * GaussianOutputScale;
}

float4 GaussianBlurUpscaleCombineFP(GaussianVertexOut input) : FRAG_OUTPUT_COLOR
{
	float4 colorBufferValue = ColorBuffer.Sample(LinearClampSampler,input.uv);
	float4 sampleCentre = GlowBuffer.Sample(LinearClampSampler,input.uv);
		
	float4 sample0 = GlowBuffer.Sample(LinearClampSampler,input.uvs0.xy);
	float4 sample1 = GlowBuffer.Sample(LinearClampSampler,input.uvs0.zw);
	float4 sample2 = GlowBuffer.Sample(LinearClampSampler,input.uvs1.xy);
	float4 sample3 = GlowBuffer.Sample(LinearClampSampler,input.uvs1.zw);

	float4 rslt = sampleCentre * (kWeight0 * kWeightSum);
	rslt += sample0 * (kWeight2 * kWeightSum);
	rslt += sample1 * (kWeight1 * kWeightSum);
	rslt += sample2 * (kWeight1 * kWeightSum);
	rslt += sample3 * (kWeight2 * kWeightSum);

	return colorBufferValue + rslt * GaussianOutputScale;
}


float4 CopyToScreenFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	float4 sampleCentre = GlowBuffer.Sample(LinearClampSampler,input.uv);
	return sampleCentre;
}

float4 GenerateGlowBufferFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	float4 col =  GlowBuffer.Sample(LinearClampSampler,input.uv);
	float lum = dot(col.xyz,0.333f);
	float glowAmt = saturate((col.w - 0.8)*100.0) * saturate((lum - LuminanceThreshold) * LuminanceScale);

	return float4(col.xyz * glowAmt * 2.5, 1.0);
}

#ifndef __ORBIS__

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
};
BlendState AdditiveBlend 
{
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
DepthStencilState DepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};


technique11 RenderGaussianBlurX
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GaussianUpscaleXVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GaussianBlurUpscaleFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderGaussianBlurY
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GaussianUpscaleYVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GaussianBlurUpscaleFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderGaussianBlurYComposite
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GaussianUpscaleYVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GaussianBlurUpscaleFP() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}


technique11 RenderGaussianBlurYCompositeCombine
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GaussianUpscaleYVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GaussianBlurUpscaleCombineFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 CopyGaussianBlurToScreen
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, CopyToScreenFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}
technique11 GenerateGlowBuffer
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GenerateGlowBufferFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

#endif //! __ORBIS__
