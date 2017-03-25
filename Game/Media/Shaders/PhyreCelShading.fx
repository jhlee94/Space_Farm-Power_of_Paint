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

float LineThickness;
float Threshold;
float Gamma;
float4 CelColor;
float4 EdgeColor;
float2 InvProjXY;
Texture2D <float4> ColorBuffer;

///////////////////////////////////////////////////////////////
// structures /////////////////////
///////////////////////////////////////////////////////////////

struct VertexIn
{
#ifdef __ORBIS__
	float4 vertex		:	POSITION;
#else
	float3 vertex		:	POSITION;
#endif
	float2 uv			:	TEXCOORD0;
};

struct VertexOut
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
	float3 screenPos	: TEXCOORD3;
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

///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

float Grey( float4 c )
{
	return dot( c.rgb, (0.333).xxx );
}

#define KWeight0	0
#define KWeight1	1
#define KWeight2	2

float4 Sobel( float2 texCoord )
{
	float2 xOffset = float2( LineThickness * screenWidthHeightInv.x, 0 );
	float2 yOffset = float2( 0, LineThickness * screenWidthHeightInv.y );
	float g[9];

	float2 pixel = texCoord - yOffset;
	g[0] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel - xOffset, 0 ) );
	g[1] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel, 0 ) );
	g[2] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel + xOffset, 0 ) );

	pixel = texCoord;
	g[3] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel - xOffset, 0 ) );
	g[5] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel + xOffset, 0 ) );

	pixel = texCoord + yOffset;
	g[6] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel - xOffset, 0 ) );
	g[7] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel, 0 ) );
	g[8] = Grey( ColorBuffer.SampleLevel( LinearClampSampler, pixel + xOffset, 0 ) );

	float2 G = float2( 0.0f, 0.0f );

	// Run horizontal filter
	G.x += g[0]	*	KWeight1;
	G.x += g[2]	*	-KWeight1;
	
	G.x += g[3]	*	KWeight2;
	G.x += g[5]	*	-KWeight2;
	
	G.x += g[6]	*	KWeight1;
	G.x += g[8]	*	-KWeight1;

	// Run vertical filter
	G.y += g[0]	*	KWeight1;
	G.y += g[1]	*	KWeight2;
	G.y += g[2]	*	KWeight1;

	G.y += g[6]	*	-KWeight1;
	G.y += g[7]	*	-KWeight2;
	G.y += g[8]	*	-KWeight1;

	float norm = dot( G, G );

	if( norm > ( Threshold * Threshold ) )
	{
		return EdgeColor;
	}

	return float4(1,1,1,1);
}

#define kNumLevels	4
#define kNumLevelsInv (1.0f/float(kNumLevels))
// Posterize the colour buffer
float4 CalcLightVal( float3 color )
{
#ifdef PHYRE_D3DFX
	#pragma warning (disable : 3571) // Disable pow(f, e) will not work for negative f, use abs(f) or conditionally handle negative values if you expect them
#endif // PHYRE_D3DFX

	float intensity = pow( Grey( color.rgbr ), Gamma );
	intensity *= kNumLevels;
	intensity = floor(intensity) * kNumLevelsInv;
	intensity = pow( intensity, 1.0f / Gamma );

	float3 lightValue = CelColor.xyz * intensity;
	return float4(lightValue, 1.0f);
}

///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

VertexOut CelVS(VertexIn input)
{
	VertexOut output;
	output.position = float4(input.vertex.xy, 1, 1);
	float2 uv = input.uv;

#ifndef __ORBIS__
	uv.y = 1.0f - input.uv.y;
#endif

	output.uv = uv;

	output.screenPos.z = -1.0;
	output.screenPos.xy = output.uv * 2.0 - 1.0;
	output.screenPos.y = -output.screenPos.y;
	output.screenPos.xy *= InvProjXY;

	return output;
}

float4 CelPS(VertexOut input) : FRAG_OUTPUT_COLOR
{
	float4 color = ColorBuffer.SampleLevel( LinearClampSampler, input.uv.xy, 0 );
	float4 lightColor = CalcLightVal( color.xyz );
	color += lightColor;

	// Multiply by Sobel to check for edges
	color *= Sobel(input.uv);
	return color;
}

#ifndef __ORBIS__

///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

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
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

technique11 Cel
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, CelVS() ) );
		SetPixelShader( CompileShader( ps_5_0, CelPS() ) );

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

#endif