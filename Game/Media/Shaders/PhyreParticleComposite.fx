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

struct FullScreenVS_Output 
{  
	float4 Pos : SV_POSITION;              
    float2 Tex : TEXCOORD0; 
};

FullScreenVS_Output FullScreenVS(uint id : SV_VertexID) 
{
    FullScreenVS_Output Output;
    Output.Tex = float2((id << 1) & 2, id & 2);
    Output.Pos = float4(Output.Tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
#ifdef __ORBIS__
	Output.Tex.y = 1.0f-Output.Tex.y;
#endif //! __ORBIS__
    return Output; 
}

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

Texture2D ParticleColorBuffer;
Texture2D ParticleDepthBuffer;

float4 PS_CompositeSimple(FullScreenVS_Output Input, out float depth : FRAG_OUTPUT_DEPTH) : FRAG_OUTPUT_COLOR 
{
	float2 pos = Input.Tex.xy;
	depth = ParticleDepthBuffer.SampleLevel(PointClampSampler, pos, 0).x;
	float4 color = ParticleColorBuffer.SampleLevel(LinearClampSampler, pos, 0);
	return color;
}

Texture2D SceneColorBuffer;
Texture2D SceneDepthBuffer;
float2 InvSceneBufferSize;

// Convert a depth value from post projection space to view space. 
float ConvertDepth(float depth)
{	
#ifdef ORTHO_CAMERA
	float viewSpaceZ = -(depth * cameraFarMinusNear + cameraNearFar.x);
#else //! ORTHO_CAMERA
	float viewSpaceZ = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
#endif //! ORTHO_CAMERA
	return viewSpaceZ;
}

float4 BilateralSample(float2 pos)
{
	const int numBilateralSamples = 9;
	float x = InvSceneBufferSize.x;
	float y = InvSceneBufferSize.y;
	float2 offsets[numBilateralSamples] = 
	{
		float2(-x, -y),
		float2(0, -y),
		float2(x, -y),
		float2(-x, 0),
		float2(0, 0),
		float2(x, 0),
		float2(-x, y),
		float2(0, y),
		float2(x, y)
	};
	
	// Gaussian weights:
	//	1--2--1
	//	|  |  |
	//	2--4--2
	//	|  |  |
	//	1--2--1
	float gaussianWeights[numBilateralSamples] = { 1, 2, 1, 2, 4, 2, 1, 2, 1 };

	float hiResDepth = abs(ConvertDepth(SceneDepthBuffer.Sample(PointClampSampler, pos).x));
	
	float weights = 0.0f;
	float4 rslt0 = 0.0f;
	for(int i = 0; i < numBilateralSamples; ++i)
	{
		float lowResDepth = abs(ConvertDepth(ParticleDepthBuffer.Sample(PointClampSampler, pos + offsets[i]).x));
		float4 particleColour = ParticleColorBuffer.Sample(LinearClampSampler, pos + offsets[i]);
		float depthDiff = lowResDepth - hiResDepth;
		float sampleWeights = 1.0f / (0.00001f + abs(depthDiff));
		sampleWeights *= depthDiff < 0.0f;
		sampleWeights *= gaussianWeights[i];
		weights += sampleWeights;
		rslt0 += particleColour * sampleWeights.x;
	}
	if(weights == 0.0f)
		return float4(0,0,0,1);

	float div = (1.0f / weights);
	rslt0 *= div;
	return rslt0;
}

float4 BilateralSample2x2(float2 pos, float2 position)
{
	int xc = (int)position.x;
	int yc = (int)position.y;
	
	int xo = (xc & 0x1) ? 1 : -1;
	int yo = (yc & 0x1) ? 1 : -1;

	const int numBilateralSamples = 4;
	float x = InvSceneBufferSize.x;
	float y = InvSceneBufferSize.y;
	float2 offsets[numBilateralSamples] = 
	{
		float2(0, 0),
		float2(x, 0),
		float2(0, y),
		float2(x, y)
	};
	
	// Gaussian weights:
	//	1--2--1
	//	|  |  |
	//	2--4--2
	//	|  |  |
	//	1--2--1
	float gaussianWeights[numBilateralSamples] = { 4, 2, 2, 1 };

	float hiResDepth = abs(ConvertDepth(SceneDepthBuffer.Sample(PointClampSampler, pos).x));
	
	float weights = 0.0f;
	float4 rslt0 = 0.0f;
	for(int i = 0; i < numBilateralSamples; ++i)
	{
		float lowResDepth = abs(ConvertDepth(ParticleDepthBuffer.Sample(PointClampSampler, pos + offsets[i]).x));
		float4 particleColour = ParticleColorBuffer.Sample(LinearClampSampler, pos + offsets[i]);
		float depthDiff = lowResDepth - hiResDepth;
		float sampleWeights = 1.0f / (1.0f + abs(depthDiff));
		sampleWeights *= depthDiff < 0.0f;
		sampleWeights *= gaussianWeights[i];
		weights += sampleWeights;
		rslt0 += particleColour * sampleWeights.x;
	}
	if(weights == 0.0f)
		return float4(0,0,0,1);

	float div = (1.0f / weights);
	rslt0 *= div;
	return rslt0;
}

float4 BilateralSample1x1(float2 pos, float2 position)
{
	int xc = (int)position.x;
	int yc = (int)position.y;
	
	int xo = (xc & 0x1) ? 1 : -1;
	int yo = (yc & 0x1) ? 1 : -1;

	const int numBilateralSamples = 1;
	float2 offsets[numBilateralSamples] = 
	{
		float2(0, 0),
	};
	
	// Gaussian weights:
	//	1--2--1
	//	|  |  |
	//	2--4--2
	//	|  |  |
	//	1--2--1
	float gaussianWeights[numBilateralSamples] = { 4 };

	float hiResDepth = abs(ConvertDepth(SceneDepthBuffer.Sample(PointClampSampler, pos).x));
	
	float weights = 0.0f;
	float4 rslt0 = 0.0f;
	for(int i = 0; i < numBilateralSamples; ++i)
	{
		float lowResDepth = abs(ConvertDepth(ParticleDepthBuffer.Sample(PointClampSampler, pos + offsets[i]).x));
		float4 particleColour = ParticleColorBuffer.Sample(LinearClampSampler, pos + offsets[i]);
		float depthDiff = lowResDepth - hiResDepth;
		float sampleWeights = 1.0f / (1.0f + abs(depthDiff));
		sampleWeights *= depthDiff < 0.0f;
		sampleWeights *= gaussianWeights[i];
		weights += sampleWeights;
		rslt0 += particleColour * sampleWeights.x;
	}

	if(weights == 0.0f)
		return float4(0,0,0,1);

	float div = (1.0f / weights);
	rslt0 *= div;
	return rslt0;
}

float4 PS_CompositeOver(FullScreenVS_Output Input) : FRAG_OUTPUT_COLOR 
{
	float2 pos = Input.Tex.xy;
	return BilateralSample1x1(pos, Input.Pos.xy);
}

float4 PS_Composite(FullScreenVS_Output Input) : FRAG_OUTPUT_COLOR 
{
	float2 pos = Input.Tex.xy;
	float4 sceneColor = SceneColorBuffer.Sample(LinearClampSampler, pos);
	//float4 rslt0 = BilateralSample2x2(pos, Input.Pos.xy);
	float4 rslt0 = BilateralSample1x1(pos, Input.Pos.xy);
	return float4(rslt0.xyz + rslt0.w * sceneColor.xyz, rslt0.w);
}

#ifndef __ORBIS__

BlendState SimpleCompositeBlend
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = ONE;
	DestBlend[0] = SRC_ALPHA;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
};

BlendState HalfResolutionCompositeBlend
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = ONE;
	DestBlend[0] = SRC_ALPHA;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
};

DepthStencilState TestDepthState {
  DepthEnable = TRUE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

BlendState NoBlend
{
	AlphaToCoverageEnable = FALSE;
	BlendEnable[0] = FALSE;
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
	FillMode = Solid;
	DepthBias = 0;
	ScissorEnable = false;
};

technique11 CompositeParticlesSimple
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_1, FullScreenVS() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_CompositeSimple() ) );
		
		SetBlendState( SimpleCompositeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( TestDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 CompositeParticlesOver
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_1, FullScreenVS() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_CompositeOver() ) );
		
		SetBlendState( HalfResolutionCompositeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 CompositeParticles
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_1, FullScreenVS() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_Composite() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__

#ifdef __ORBIS__
	//! Set the output format for downsampling to be 32 bit.
	#ifdef PHYRE_ENTRYPOINT_PS_DownsampleDepth
		#pragma PSSL_target_output_format(default FMT_32_ABGR)
	#endif //! PHYRE_ENTRYPOINT_PS_DownsampleDepth
#endif //! __ORBIS__

float PS_DownsampleDepth(FullScreenVS_Output Input) : FRAG_OUTPUT_COLOR 
{
	int2 pos = 2 * int2(Input.Pos.xy);
		
	float a = SceneDepthBuffer.Load(int3(pos + int2(0, 0), 0)).x;
	float b = SceneDepthBuffer.Load(int3(pos + int2(1, 0), 0)).x;
	float c = SceneDepthBuffer.Load(int3(pos + int2(0, 1), 0)).x;
	float d = SceneDepthBuffer.Load(int3(pos + int2(1, 1), 0)).x;
	return min(min(a, b), min(c, d));
}

technique11 DownsampleDepth
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_1, FullScreenVS() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_DownsampleDepth() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}