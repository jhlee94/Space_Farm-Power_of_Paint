/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

// Context switches
bool PhyreContextSwitches 
< 
string ContextSwitchNames[] = {"ORTHO_CAMERA"}; 
>;

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

Texture2D <float> DepthBuffer;
Texture2D <float> DownsampledDepthBuffer;
Texture2D <float4> NormalDepthBuffer;
Texture2D <float4> ColorBuffer;
Texture2D <float4> ResultBuffer;

float MarchStepFactor;
float EnvmapBrightness;

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};
sampler LinearClampSampler
{
	Filter = Min_Mag_Mip_Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};
sampler LinearSampler
{
	Filter = Min_Mag_Mip_Linear;
    AddressU = Clamp;
    AddressV = Clamp;
    AddressW = Clamp;
};

struct VS_OUTPUT
{
    float4 Position  : SV_POSITION;
	float2 Uv : TEXCOORD0;
};

VS_OUTPUT VS_Fullscreen(
#ifdef __ORBIS__
float4 Position : POSITION
#else //! __ORBIS__
float3 Position : POSITION
#endif //! __ORBIS__
)
{
 	VS_OUTPUT Out = (VS_OUTPUT)0;
 	Out.Position = float4(Position.xy,0,1);
	Out.Uv = Position.xy * 0.5f + 0.5f;

#ifndef __ORBIS__
	Out.Uv.y = 1-Out.Uv.y;
#endif //! __ORBIS__
	
	return Out;    
}

// Convert a depth value from post projection space to view space. 
float GetViewDepth(float depth)
{	
#ifdef __ORBIS__
	// Compensate for scale in PS_DownsampleScreenSpaceReflectionDepth
	depth = depth * 0.5f + 0.5f;
#endif //! __ORBIS__
#ifdef ORTHO_CAMERA
	float viewSpaceZ = -(depth * cameraFarMinusNear + cameraNearFar.x);
#else //! ORTHO_CAMERA
	float viewSpaceZ = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
#endif //! ORTHO_CAMERA
	return viewSpaceZ;
}


#ifdef __ORBIS__
	//! Set the output format for picking to be 32 bit.
	#ifdef PHYRE_ENTRYPOINT_PS_DownsampleScreenSpaceReflectionDepth
		#pragma PSSL_target_output_format(default FMT_32_ABGR)
	#else //! PHYRE_ENTRYPOINT_PS_DownsampleScreenSpaceReflectionDepth
		#pragma PSSL_target_output_format(default FMT_FP16_ABGR)
	#endif //! PHYRE_ENTRYPOINT_PS_DownsampleScreenSpaceReflectionDepth
#endif //! __ORBIS__

float4 PS_DownsampleScreenSpaceReflectionDepth(VS_OUTPUT In) : FRAG_OUTPUT_COLOR0
{
	int2 pixelPosition = int2(In.Position.xy);
	int2 upSampledPixelPosition = pixelPosition * 2;

	float d0 = DepthBuffer.Load(int3(upSampledPixelPosition,0)).x;
	float d1 = DepthBuffer.Load(int3(upSampledPixelPosition + int2(1,0),0)).x;
	float d2 = DepthBuffer.Load(int3(upSampledPixelPosition + int2(0,1),0)).x;
	float d3 = DepthBuffer.Load(int3(upSampledPixelPosition + int2(1,1),0)).x;
			
	float d = min(min(d0,d1),min(d2,d3));

#ifdef __ORBIS__
	// Need to scale to maintain range for direct access to these depth values
	d = d * 2.0f - 1.0f;
#endif //! __ORBIS__

	return d;
}


float4 PS_ScreenSpaceReflectionPrePass(VS_OUTPUT In) : FRAG_OUTPUT_COLOR0
{
	int2 pixelPosition = int2(In.Position.xy);
	int2 upSampledPixelPosition = pixelPosition * 2;

	float4 c0 = ColorBuffer.Load(int3(upSampledPixelPosition, 0));
	float4 c1 = ColorBuffer.Load(int3(upSampledPixelPosition + int2(1,0),0));
	float4 c2 = ColorBuffer.Load(int3(upSampledPixelPosition + int2(0,1),0));
	float4 c3 = ColorBuffer.Load(int3(upSampledPixelPosition + int2(1,1),0));

	float4 c = (c0+c1+c2+c3) * 0.25f;

	return c;
}


float4 PS_ScreenSpaceReflection(VS_OUTPUT In) : FRAG_OUTPUT_COLOR0
{
	float4 finalResultColor = 0;

	uint ViewportWidth, ViewportHeight;
	DownsampledDepthBuffer.GetDimensions(ViewportWidth, ViewportHeight);
	
	float2 ViewportSize;
	DownsampledDepthBuffer.GetDimensions(ViewportSize.x, ViewportSize.y);
	float2 InvViewportSize = float2(1.0f / ViewportSize.x, 1.0f / ViewportSize.y);

	float2 InvProjXY = float2(1.0f / Projection[0].x, 1.0f / Projection[1].y);

	int2 pixelPosition = int2(In.Position.xy);
	float zvalue = DownsampledDepthBuffer.Load(int3(pixelPosition,0)).x;

	if(zvalue < 1.0f)
	{
		float4 normalBufferValue = NormalDepthBuffer.SampleLevel(LinearClampSampler, In.Uv,0);
		float4 origColour = ColorBuffer.Load(int3(pixelPosition, 0));

#ifdef __ORBIS__
		float screenYScale = 1.0f;
#else //! __ORBIS__
		float screenYScale = -1.0f;
#endif //! __ORBIS__
	 
		float2 screenPos = float2(pixelPosition) * float2(1.0f/(float)(ViewportWidth),1.0f/(float)(ViewportHeight));
		screenPos = (screenPos * 2.0f - 1.0f) * float2(1.0f,screenYScale);
		
		float viewDepth = GetViewDepth(zvalue);

#ifdef ORTHO_CAMERA
		float3 viewPosition = float3(screenPos * InvProjXY.xy, -viewDepth);
#else //! ORTHO_CAMERA
		float3 viewPosition = float3(screenPos * InvProjXY.xy * viewDepth, -viewDepth);
#endif //! ORTHO_CAMERA	
		float3 viewNormal = normalize(normalBufferValue.xyz * 2.0f - 1.0f);

		float zIntersectionThreshold = 0.0005f;
#ifdef __ORBIS__
		zIntersectionThreshold *= 2.0f;
#endif //! __ORBIS__

		float normalBias = 0.1f;
		viewPosition += viewNormal * normalBias;
		float3 screenPosition = mul(float4(viewPosition, 1.0f), Projection).xyz / -viewPosition.z;

		// view space reflection vector
		float3 viewSpaceReflectDir = normalize(reflect(normalize(viewPosition),  viewNormal));
	
		float incidentAngle = 1.0f - abs(dot(viewNormal, normalize(viewPosition)));
		float fresnel = incidentAngle;
		float reflectionAmount = fresnel;
		reflectionAmount = saturate(reflectionAmount);

		// Ray marching in screen space, depth values in depth buffer space.
		float3 viewSpaceReflectOffsetPos = viewPosition + viewSpaceReflectDir;
		float3 screenSpacePosReflect = mul(float4(viewSpaceReflectOffsetPos, 1.0f), Projection).xyz / -viewSpaceReflectOffsetPos.z;
		float3 screenSpaceReflectDir = screenSpacePosReflect - screenPosition;
        
		// Resize screen space reflection dir to catch each pixel of the screen
		float scalefactor = (InvViewportSize.x*2.0f) / length(screenSpaceReflectDir.xy);
		scalefactor *= MarchStepFactor;
		screenSpaceReflectDir *= scalefactor;
   	
		float3 screenSpaceCoord = screenPosition + screenSpaceReflectDir ;
		screenSpaceCoord.xy = float2(screenSpaceCoord.x * 0.5 + 0.5,screenSpaceCoord.y * -0.5 + 0.5);
		screenSpaceReflectDir = float3(screenSpaceReflectDir.x * 0.5 ,screenSpaceReflectDir.y * -0.5, screenSpaceReflectDir.z);
    
		// Determine number of samples required
		int numSamplesRequired = (int)(ViewportSize.x / MarchStepFactor);
		int currentSampleIndex = 0;
		
		// Calculate the number of samples to the edge
		float3 samplestoedge = ((sign(screenSpaceReflectDir.xyz) * 0.5 + 0.5) - screenSpaceCoord.xyz) / screenSpaceReflectDir.xyz;
		samplestoedge.x = min(samplestoedge.x, min(samplestoedge.y, samplestoedge.z));
		numSamplesRequired = min(numSamplesRequired, (int)samplestoedge.x);
        
		const int maxNumSamples = 200;
	
		while (currentSampleIndex < numSamplesRequired && currentSampleIndex < maxNumSamples)
		{
			// Sample from depth buffer
#ifdef __ORBIS__
			float currentDepthSample = DownsampledDepthBuffer.SampleLevel(PointClampSampler, float2(screenSpaceCoord.x, 1.0f-screenSpaceCoord.y), 0).x;
#else //! __ORBIS__
			float currentDepthSample = DownsampledDepthBuffer.SampleLevel(PointClampSampler, screenSpaceCoord.xy, 0).x;
#endif //! __ORBIS__
			if(currentDepthSample < screenSpaceCoord.z && currentDepthSample > screenSpaceCoord.z-zIntersectionThreshold)
			{

				float3 prevScreenSpaceCoord = (screenSpaceCoord - screenSpaceReflectDir);
				prevScreenSpaceCoord.xy = prevScreenSpaceCoord.xy + screenSpaceReflectDir.xy * (currentDepthSample - prevScreenSpaceCoord.z);
#ifdef __ORBIS__
				float3 hitColor = ColorBuffer.SampleLevel(LinearClampSampler, float2(prevScreenSpaceCoord.x, 1.0f - prevScreenSpaceCoord.y), 0).xyz;
#else //! __ORBIS__
				float3 hitColor = ColorBuffer.SampleLevel(LinearClampSampler, prevScreenSpaceCoord.xy, 0).xyz;
#endif //! __ORBIS__
				finalResultColor.xyz = hitColor;
				currentSampleIndex = numSamplesRequired + 1;      
			}
	    
			screenSpaceCoord += screenSpaceReflectDir; 
			++currentSampleIndex;
		}

	}
	
	return finalResultColor;
}



float4 PS_CompositeScreenSpaceReflection(VS_OUTPUT In) : FRAG_OUTPUT_COLOR0
{
	
const float2 SampleOffsets[9] = 
{
	float2(-1.0f,1.0f),float2(0.0f,1.0f),float2(1.0f,1.0f),
	float2(-1.0f,0.0f),float2(0.0f,0.0f),float2(1.0f,0.0f),
	float2(-1.0f,-1.0f),float2(0.0f,-1.0f),float2(1.0f,-1.0f)
};
const float SampleWeights[9] = 
{
	0.05f,0.1f,0.05f,
	0.1f,0.4f,0.1f,
	0.05f,0.1f,0.05f,
};

	int2 pixelPosition = int2(In.Position.xy);	
	float2 InvProjXY = float2(1.0f / Projection[0].x, 1.0f / Projection[1].y);
	float zvalue = DepthBuffer.Load(int3(pixelPosition,0)).x;

	float4 origColor = ColorBuffer.Load(int3(pixelPosition, 0));
	float4 finalColor = origColor;

	if(zvalue < 1.0f)
	{
	float4 normalBufferValue = NormalDepthBuffer.Load(int3(pixelPosition, 0));

#ifdef __ORBIS__
	float screenYScale = 1.0f;
#else //! __ORBIS__
	float screenYScale = -1.0f;
#endif //! __ORBIS__
	float2 screenPos = float2(pixelPosition) * screenWidthHeightInv;
	screenPos = (screenPos * 2.0f - 1.0f) * float2(1.0f,screenYScale);
	float viewDepth = GetViewDepth(zvalue);

#ifdef ORTHO_CAMERA
	float3 viewPosition = float3(screenPos * InvProjXY.xy, -viewDepth);
#else //! ORTHO_CAMERA
	float3 viewPosition = float3(screenPos * InvProjXY.xy * viewDepth, -viewDepth);
#endif //! ORTHO_CAMERA	
	float3 viewNormal = normalize(normalBufferValue.xyz * 2.0f - 1.0f);

	float4 finalResultColor = 0;
		
	// view space reflection vector
	float3 viewSpaceReflectDir = normalize(reflect(normalize(viewPosition),  viewNormal));
	
	float incidentAngle = 1.0f - abs(dot(viewNormal, normalize(viewPosition)));
	float fresnel = incidentAngle;
	// cut out high fresnel angles - normals go weird
	float highAngleFresnel = saturate(((incidentAngle) - 0.6f) * 12.0f);
	float reflectionAmount = fresnel;
	reflectionAmount = saturate(reflectionAmount) * (1.0f-highAngleFresnel);
	
	float2 reflectionBufferSize;
	ResultBuffer.GetDimensions(reflectionBufferSize.x,reflectionBufferSize.y);

	float gloss = normalBufferValue.w * sqrt(reflectionAmount);

	float4 rslt = 0;
	// take a bunch of samples to soften reflection
	[unroll] for(int i = 0; i < 9; ++i)
	{
		float2 off = SampleOffsets[i] * float2(1.0f/reflectionBufferSize.x,1.0f/reflectionBufferSize.y) * 1.0f;// * (1.0f-gloss);
		float4 reflectionValue = ResultBuffer.SampleLevel(LinearClampSampler, In.Uv + off, 0);

		rslt += reflectionValue * SampleWeights[i];
	}

	finalColor = lerp(origColor, rslt, gloss);
	}
	return finalColor;
}



#ifndef __ORBIS__

BlendState NoBlend {
  AlphaToCoverageEnable = FALSE;
  BlendEnable[0] = FALSE;
  BlendEnable[1] = FALSE;
  BlendEnable[2] = FALSE;
  BlendEnable[3] = FALSE;
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
technique11 RenderScreenSpaceReflection
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, VS_Fullscreen() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_ScreenSpaceReflection() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 ScreenSpaceReflectionPrePass
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, VS_Fullscreen() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_ScreenSpaceReflectionPrePass() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}
technique11 DownsampleScreenSpaceReflectionDepth
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, VS_Fullscreen() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_DownsampleScreenSpaceReflectionDepth() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}



technique11 CompositeScreenSpaceReflection
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, VS_Fullscreen() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_CompositeScreenSpaceReflection() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__
