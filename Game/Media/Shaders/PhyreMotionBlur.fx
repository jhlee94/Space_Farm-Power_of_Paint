/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#define NUM_BLUR_TAPS_FORWARD 6
#define NUM_BLUR_TAPS_BACKWARD 3
#define NUM_BLUR_TAPS (NUM_BLUR_TAPS_BACKWARD+NUM_BLUR_TAPS_FORWARD)

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

#ifndef __ORBIS__
// Context switches
bool PhyreContextSwitches 
< 
string ContextSwitchNames[] = {"ORTHO_CAMERA"}; 
>;
#endif //! __ORBIS__

float4 GaussianBlurWeights;
float4 GaussianBlurOffsets[7];

float VelocityScale;
float4x4 ViewToPreviousViewProjection;
float4x4 ObjectViewToPreviousViewProjection;

Texture2D <float> DepthBuffer;
Texture2D <float4> ColorBuffer;
Texture2D <float2> VelocityBuffer;

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
	float4 position		: SV_POSITION;
	float2 centreUv		: TEXCOORD0;
	float4 uvs0			: TEXCOORD1;
	float4 uvs1			: TEXCOORD2;
	float4 uvs2			: TEXCOORD3;
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

FullscreenVertexOut FullscreenVP(FullscreenVertexIn input)
{
	FullscreenVertexOut output;

#ifdef __ORBIS__
	output.position = float4(input.vertex.xy, 1, 1);
#else //! __ORBIS__
	output.position = float4(input.vertex.x,-input.vertex.y, 1, 1);
#endif //! __ORBIS
	output.uv = input.uv;

	return output;
}

GaussianVertexOut GaussianBlurVP(FullscreenVertexIn input)
{
	GaussianVertexOut output;
	
	output.position = float4(input.vertex.x,-input.vertex.y, 1, 1);
	output.centreUv = input.uv + GaussianBlurOffsets[3].xy;
	output.uvs0 = float4(input.uv + GaussianBlurOffsets[0].xy,input.uv + GaussianBlurOffsets[1].xy);
	output.uvs1 = float4(input.uv + GaussianBlurOffsets[2].xy,input.uv + GaussianBlurOffsets[4].xy);
	output.uvs2 = float4(input.uv + GaussianBlurOffsets[5].xy,input.uv + GaussianBlurOffsets[6].xy);
		
	return output;
}

///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

float4 GaussianBlurFP(GaussianVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float4 sampleCentre = ColorBuffer.Sample(LinearClampSampler, input.centreUv);
#ifdef KERNEL_7_SAMPLES
	float4 sample0 = ColorBuffer.Sample(LinearClampSampler, input.uvs0.xy);
	float4 sample1 = ColorBuffer.Sample(LinearClampSampler, input.uvs0.zw);
	float4 sample2 = ColorBuffer.Sample(LinearClampSampler, input.uvs1.xy);
	float4 sample3 = ColorBuffer.Sample(LinearClampSampler, input.uvs1.zw);
	float4 sample4 = ColorBuffer.Sample(LinearClampSampler, input.uvs2.xy);
	float4 sample5 = ColorBuffer.Sample(LinearClampSampler, input.uvs2.zw);

	float4 total = (sampleCentre* GaussianBlurWeights.w) + ((sample0+sample5)*GaussianBlurWeights.x) + ((sample1+sample4)*GaussianBlurWeights.y) + ((sample2+sample3)*GaussianBlurWeights.z);
#else 
	float4 sample0 = ColorBuffer.Sample(LinearClampSampler, input.uvs0.xy);
	float4 sample1 = ColorBuffer.Sample(LinearClampSampler, input.uvs0.zw);
	float4 sample2 = ColorBuffer.Sample(LinearClampSampler, input.uvs1.xy);
	float4 sample3 = ColorBuffer.Sample(LinearClampSampler, input.uvs1.zw);
	
	float4 total = (sampleCentre* GaussianBlurWeights.z) + ((sample0+sample3)*GaussianBlurWeights.x) + ((sample1+sample2)*GaussianBlurWeights.y);
#endif
	return total;
}



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

// Read value from a depth map and convert it to float.
float ReadDepth( float2 uv )
{
	return DepthBuffer.Sample(LinearClampSampler, uv.xy).x;
}

// Perform a directional blur in +- the velocity direction.
float4 DirectionalBlurForwardBack(float2 inputUv, float2 velocity)
{
	float4 outCol = 0;
	float2 uv = inputUv;
	const float maxVel = 0.01h;
	velocity = clamp(velocity, -maxVel,maxVel);
	for(int i = 0; i < NUM_BLUR_TAPS_FORWARD; ++i) 
	{
		float4 c = ColorBuffer.Sample(LinearClampSampler, uv);
		outCol += c;
		uv += velocity;		
	}
	uv = inputUv;
	for(int j = 0; j < NUM_BLUR_TAPS_BACKWARD; ++j) 
	{
		float4 c = ColorBuffer.Sample(LinearClampSampler, uv);
		outCol += c;
		uv -= velocity;		
	}
	return outCol * (1.0h/NUM_BLUR_TAPS);
}
float4 DirectionalBlurForwardBackWeighted(float2 inputUv, float2 velocity)
{
	int i;

	const float maxVel = 0.01f;
	velocity = clamp(velocity, -maxVel,maxVel);

	float4 outCol = 0;
	float totalWeight = 0;
	float2 uv = inputUv;

	{
		float4 c = ColorBuffer.Sample(LinearClampSampler, uv);
		float weight = 1 + c.w;
		outCol = c * weight;
		totalWeight = weight;
		uv += velocity;		
	}

	float w = 1;
	for(i = 1; i < NUM_BLUR_TAPS_FORWARD; ++i) 
	{
		float4 c = ColorBuffer.Sample(LinearClampSampler, uv);
		float weight = w + c.w;
		outCol += c * weight;
		totalWeight += weight;
		uv += velocity;		
		w *= 0.95h;
	}
	uv = inputUv;
	w = 1;
	for(i = 0; i < NUM_BLUR_TAPS_BACKWARD; ++i) 
	{
		float4 c = ColorBuffer.Sample(LinearClampSampler, uv);
		float weight = w + c.w;
		outCol += c * weight;
		totalWeight += weight;
		uv -= velocity;		
		w *= 0.95h;
	}
	return outCol * (1.0f/totalWeight);
}

#define MOTION_BLUR_VELOCITY_SCALE 10.0f


// Object motion blur:
// Using the velocity buffer do a directional blur in +- the velocity direction at each pixel.
float4 MotionBlurFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float2 velocityMapVal = VelocityBuffer.Sample(LinearClampSampler, input.uv);
	
	float2 vel = (velocityMapVal.xy * 2.0f - 1.0f) * (1.0f/MOTION_BLUR_VELOCITY_SCALE) * VelocityScale;
	
	const float velScale =  (5.0f/1000.0f);
	vel *= velScale;
	return DirectionalBlurForwardBackWeighted(input.uv, vel);
}


// Camera motion blur:
// Using the depth buffer to reconstruct the projection space 3d position of the pixel, then 
// project back into the previous frame's space and find the velocity in camera space of the pixel. 
// Then do a directional blur in +- the velocity direction.
float4 CameraMotionBlurFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float2 screenPos = input.uv * 2.0f - 1.0f;
#ifndef __ORBIS__
	screenPos.y = -screenPos.y;
#endif //! __ORBIS__
	float depthMapValue = ReadDepth(input.uv);
	float viewSpaceDepth = ConvertDepth(depthMapValue);
#ifdef ORTHO_CAMERA
	float4 projPos = float4(screenPos, viewSpaceDepth, 1);
#else // ! ORTHO_CAMERA
	float4 projPos = float4(screenPos * viewSpaceDepth, viewSpaceDepth, 1);
#endif //! ORTHO_CAMERA
	float4 prevProjPos = mul(projPos, ViewToPreviousViewProjection);
	prevProjPos.xy /= prevProjPos.w;
	float2 vel = (screenPos - prevProjPos.xy) * VelocityScale;
#ifndef __ORBIS__
	vel.y = -vel.y;
#endif //! __ORBIS__
	
	const float velScale =  (5.0f/1000.0f);
	vel *= velScale;
	
	return DirectionalBlurForwardBackWeighted(input.uv, vel);
}



float4 GenerateVelocityBufferFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	float2 screenPos = input.uv * 2.0f - 1.0f;
#ifndef __ORBIS__
	screenPos.y = -screenPos.y;
#endif //! __ORBIS__
	float depthMapValue = ReadDepth(input.uv);
	
	float viewSpaceDepth = ConvertDepth(depthMapValue);
#ifdef ORTHO_CAMERA
	float4 projPos = float4(screenPos, viewSpaceDepth, 1);
#else //! ORTHO_CAMERA
	float4 projPos = float4(screenPos * viewSpaceDepth, viewSpaceDepth, 1);
#endif //! ORTHO_CAMERA
	float4 prevProjPos = mul(projPos, ViewToPreviousViewProjection);
	prevProjPos.xy /= prevProjPos.w;
#ifdef __ORBIS
	float2 vel = (screenPos - prevProjPos.xy) * 0.5f;
#else //! __ORBIS__
	float2 vel = (screenPos - prevProjPos.xy) * MOTION_BLUR_VELOCITY_SCALE;
	vel.y = -vel.y;
#endif //! __ORBIS__
	return float4(vel * 0.5f + 0.5f, 0, 0);
}

#ifndef __ORBIS__

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
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

technique11 GaussianBlur
<
	string IgnoreContextSwitches[] = {"ORTHO_CAMERA"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GaussianBlurVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GaussianBlurFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderMotionBlur
<
	string IgnoreContextSwitches[] = {"ORTHO_CAMERA"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, MotionBlurFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderCameraMotionBlur
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, CameraMotionBlurFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 GenerateVelocityBuffer
<
	string VpIgnoreContextSwitches[] = {"ORTHO_CAMERA"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, GenerateVelocityBufferFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

#endif //! __ORBIS__
