/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"
#include "PhyrePixelFont.h" // For debug view

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center)	// Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

#ifndef __ORBIS__
// Context switches
bool PhyreContextSwitches 
< 
string ContextSwitchNames[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>;
#endif //! __ORBIS__

#if defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)
#define PACK_LIGHT_INDICES  // Extra work to pack down to uint8s to reduce LDS usage
#endif // defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)

#ifdef PHYRE_D3DFX
#pragma warning (disable : 3571) // Disable pow(f, e) will not work for negative f, use abs(f) or conditionally handle negative values if you expect them
#pragma warning (disable : 3557) // Disable loop only executes for 1 iteration(s), forcing loop to unroll - Occurs on some of the larger tiled operations
#endif // PHYRE_D3DFX

// Select the method for sampling fmask in deferred MS lighting.
//#define ALL_SAMPLES
//#define SAMPLE_MASK
#define SAMPLE_LIST

#include "PhyreHTile.h"
#include "PhyreDeferredLightingSharedFx.h"

StructuredBuffer<uint> HTileData;

float4 ScreenPosToView;
float2 InvProjXY;

float DeferredInstantIntensity;
float DeferredInstantScatteringIntensity;

float3 DeferredPos;
float4x4 DeferredWorldTransform;
float4x4 DeferredShadowMatrix;

float4x4 DeferredShadowMatrixSplit0;
float4x4 DeferredShadowMatrixSplit1;
float4x4 DeferredShadowMatrixSplit2;
float4x4 DeferredShadowMatrixSplit3;
float4 DeferredSplitDistances;

float3 DeferredDir;
float4 DeferredColor;
float4 DeferredSpotAngles;
float4 DeferredAttenParams;
float3 DeferredAmbientColor;

float4 DeferredShadowMask;

float2 ViewportWidthHeightInv;							// This is not valid for use in compute shaders.

float4 AlphaGlowThreshold;
float4 FogCoefficients;
float4 FogColor;

Texture2D <float> DepthBuffer;
Texture2D <float4> NormalDepthBuffer;
Texture2D <float4> ShadowBuffer;
Texture2D <float4> ColorBuffer;
Texture2D <float4> LightBuffer;
Texture2D <float> ShadowTexture;

Texture2D <uint2> NormalDepthBufferMSFMASK;
Texture2DMS <float> DepthBufferMS;
Texture2DMS <float4> NormalDepthBufferMS;
Texture2DMS <float4> ColorBufferMS;

cbuffer DeferredSpotLightConstantBuffer
{
	PDeferredLight DeferredSpotLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredPointLightConstantBuffer
{
	PDeferredLight DeferredPointLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredDirectionalLightConstantBuffer
{
	PDeferredDirectionalLight DeferredDirectionalLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
uint NumDeferredSpotLights;
uint NumDeferredPointLights;
uint NumDeferredDirectionalLights;

StructuredBuffer <uint2> LightingOutputBuffer;
RWStructuredBuffer <uint2> RWLightingOutputBuffer;
RWStructuredBuffer <uint2> RWScatteredLightingOutputBuffer;

float4x4 WorldViewInverse;
StructuredBuffer <uint> DeferredLightCount;
StructuredBuffer <PDeferredLight> DeferredInstantLights;

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
	float3 screenPos	: TEXCOORD3;
};
struct LightRenderVertexIn
{
#ifdef __ORBIS__
	float4 vertex	: POSITION;
#else //! __ORBIS__
	float3 vertex	: POSITION;
#endif //! __ORBIS__
};

struct LightRenderVertexOut
{
	float4 Position		: SV_POSITION;
};



sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};
SamplerComparisonState ShadowMapSampler
{
	Filter = Comparison_Min_Mag_Linear_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
	ComparisonFunc = Less;
};


///////////////////////////////////////////////////////////////
// Vertex programs ////////////////////////////////////////////
///////////////////////////////////////////////////////////////


FullscreenVertexOut FullscreenVP(FullscreenVertexIn input)
{
	FullscreenVertexOut output;

#ifdef __ORBIS__
	output.position = float4(input.vertex.xy, 1, 1);
#else //! __ORBIS__
	output.position = float4(input.vertex.x, -input.vertex.y, 1, 1);
#endif //! __ORBIS__
	output.uv = input.uv;

	output.screenPos.z = -1.0;
	output.screenPos.xy = output.uv * 2.0 - 1.0;
	output.screenPos.y = -output.screenPos.y;
	output.screenPos.xy *= InvProjXY;

	return output;
}

FullscreenVertexOut FullscreenVPWithOptionalInvert(FullscreenVertexIn input)
{
	FullscreenVertexOut output = FullscreenVP(input);

#ifdef DEFERRED_INVERT
	output.uv.y = 1 - input.uv.y;
#endif // DEFERRED_INVERT

	return output;
}


LightRenderVertexOut RenderLightVP(LightRenderVertexIn input)
{
	LightRenderVertexOut output;
	
	float4 worldPosition = mul(float4(input.vertex.xyz,1), DeferredWorldTransform);
	output.Position = mul(float4(worldPosition.xyz,1), ViewProjection);
	
	return output;
}

///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

void GetWorldNormalAndPosition(out float3 worldNormal, out float3 worldPosition, float2 uv)
{
	float2 screenPos = GetScreenPosition(uv);
	float4 normalMapValue = NormalDepthBuffer.SampleLevel(PointClampSampler,uv, 0);
	
	float zvalue = DepthBuffer.SampleLevel(PointClampSampler,uv, 0);
	float viewSpaceDepth = ConvertDepth(zvalue);
		
	float2 normalMapNormalXY = normalMapValue.xy * 2.0f - 1.0f;
	float3 viewSpaceNormal = float3(normalMapNormalXY, sqrt( max( 1.0f - dot(normalMapNormalXY.xy, normalMapNormalXY.xy), 0.0f))   );	
	worldNormal = mul(float4(viewSpaceNormal,0), ViewInverse).xyz;
	worldNormal = normalize(worldNormal);
	
#ifdef ORTHO_CAMERA
	float4 viewPos = float4(screenPos * InvProjXY.xy, -viewSpaceDepth, 1);
#else //! ORTHO_CAMERA
	float4 viewPos = float4(screenPos * InvProjXY.xy * viewSpaceDepth, -viewSpaceDepth, 1);
#endif //! ORTHO_CAMERA	
		
	worldPosition = mul(viewPos, ViewInverse).xyz;	
}

float EvaluateSpotFalloff(float dp)
{
	float atten = 1;
	if( dp < DeferredSpotAngles.z)
	{
		atten = 0;
		if( dp > DeferredSpotAngles.w)
		{
			float a = (DeferredSpotAngles.w - dp) / (DeferredSpotAngles.w - DeferredSpotAngles.z);
			a = max(a,0);
			atten = a * a;
		}
	}
	return atten;
}

float calcSpecularLightAmt(float3 normal, float3 eyeDirection, float3 lightDir, float shininess, float specularPower /*, float fresnelPower*/)
{
	// Specular calcs
	float3 floatVec = normalize(eyeDirection + lightDir);
	float nDotH = saturate(dot(normal,floatVec));

	//float fresnel = saturate( 1 - pow(abs(dot(normal, eyeDirection)), fresnelPower) );
	float specularLightAmount = saturate(pow(nDotH, specularPower)) * shininess; // * fresnel

	specularLightAmount = (dot(normal,lightDir) > 0.0f) ? specularLightAmount : 0.0f;
	
	return specularLightAmount;
}

float4 RenderPointLightFP(LightRenderVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float2 uv = input.Position.xy * ViewportWidthHeightInv;
	
	float3 worldPosition;
	float3 worldNormal;
	GetWorldNormalAndPosition(worldNormal, worldPosition, uv);
	float3 eyeDirection = normalize(worldPosition - EyePosition);
	float4 normalMapValue = NormalDepthBuffer.Load(int3(input.Position.xy, 0));
		
	float3 lightDir = DeferredPos - worldPosition;
	float3 lightDirNrm = normalize((float3)lightDir);
	float dist = length(lightDir);
	float dp = dot(lightDirNrm,worldNormal);
		
	float distanceAttenuation = 1-saturate(smoothstep(DeferredAttenParams.x,DeferredAttenParams.y,dist));
	
	float specularValue = calcSpecularLightAmt(worldNormal, eyeDirection, lightDirNrm, normalMapValue.w, 16.0f);
	
	float3 rslt = DeferredColor.xyz * saturate(dp) * distanceAttenuation;
	
	return float4(rslt,1.0f);
}

float4 RenderSpotLightFP(LightRenderVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float2 uv = input.Position.xy * ViewportWidthHeightInv;
	float3 worldPosition;
	float3 worldNormal;
				
	GetWorldNormalAndPosition(worldNormal, worldPosition, uv);
	
	float3 eyeDirection = normalize(EyePosition - worldPosition);
	float4 normalMapValue = NormalDepthBuffer.Load(int3(input.Position.xy, 0));
	
	float3 lightDir = DeferredPos - worldPosition;
	float3 lightDirNrm = normalize((float3)lightDir);
	float dist = length(lightDir);
	float dp = dot(lightDirNrm,worldNormal);
	
	float specularValue = calcSpecularLightAmt(worldNormal, eyeDirection, lightDirNrm, normalMapValue.w, 7.0f);
	dp = saturate(dp);
	
	float spotDp = dot(lightDirNrm,DeferredDir);
	float spotAttenuation = EvaluateSpotFalloff(max(spotDp,0));
			
	float distanceAttenuation = 1-saturate(smoothstep(DeferredAttenParams.x,DeferredAttenParams.y,dist));

	float3 rslt = DeferredColor.xyz * distanceAttenuation * spotAttenuation * (specularValue + dp);

	float shadowBufferValue = CalculateShadow(DeferredShadowMask, ShadowBuffer.Load(int3(input.Position.xy, 0)));
	rslt *= shadowBufferValue;

	return float4(rslt,1.0f);
}


float4 RenderDirectionalLightFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	float3 worldPosition;
	float3 worldNormal;
	
	float4 normalMapValue = NormalDepthBuffer.Sample(PointClampSampler,input.uv.xy);	
	float3 viewSpaceNormal = float3(normalMapValue.xyz * 2.0f - 1.0f);

	worldNormal = mul(float4(viewSpaceNormal,0), ViewInverse).xyz;
	worldNormal = normalize(worldNormal);

	float3 lightValue = DeferredColor.xyz * saturate(dot(DeferredDir, worldNormal));

	return float4(lightValue,1.0f);
}


float4 ShadowSpotLightFP(LightRenderVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float2 uv = input.Position.xy * ViewportWidthHeightInv;
	float2 screenPos = GetScreenPosition(uv);
	
	float zvalue = DepthBuffer.Load(int3(input.Position.xy, 0)).x;  
	float unpackedDepth = abs(ConvertDepth(zvalue));

#ifdef ORTHO_CAMERA
	float4 viewPos = float4(screenPos, unpackedDepth, 1);
#else //! ORTHO_CAMERA
	float4 viewPos = float4(screenPos * unpackedDepth, unpackedDepth, 1);
#endif //! ORTHO_CAMERA
	float4 shadowPosition = mul(viewPos, DeferredShadowMatrix);

	shadowPosition.xyz /= shadowPosition.w;
	
	#define kShadowSize3 (3.0f/4096.0f)
	
	float4 offsets[2] = 
	{
		float4(-kShadowSize3,-kShadowSize3,0,0),
		float4( kShadowSize3, kShadowSize3,0,0),
	};

//	shadowPosition.z = shadowPosition.z * 0.5f + 0.5f;
//	shadowPosition.z -= 0.00001f;

	float shadowValue0 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[0].xy, shadowPosition.z).x;
	float shadowValue1 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[1].xy, shadowPosition.z).x;
	float rslt = (shadowValue0+shadowValue1)*0.5f;
	
	return DeferredShadowMask * rslt;
}



float4 ShadowDirectionalLightFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float2 uv = input.position.xy * ViewportWidthHeightInv;
	float2 screenPos = GetScreenPosition(uv);
	
	float zvalue = DepthBuffer.Load(int3(input.position.xy, 0)).x;  
	float unpackedDepth = abs(ConvertDepth(zvalue));

#ifdef ORTHO_CAMERA
	float4 viewPos = float4(screenPos, unpackedDepth, 1);
#else //! ORTHO_CAMERA
	float4 viewPos = float4(screenPos * unpackedDepth, unpackedDepth, 1);
#endif //! ORTHO_CAMERA
	
	float4 shadowPosition0 = mul(viewPos, DeferredShadowMatrixSplit0);
	float4 shadowPosition1 = mul(viewPos, DeferredShadowMatrixSplit1);
	float4 shadowPosition2 = mul(viewPos, DeferredShadowMatrixSplit2);
	float4 shadowPosition3 = mul(viewPos, DeferredShadowMatrixSplit3);

	float4 shadowPosition = unpackedDepth < DeferredSplitDistances.y ? 
		(unpackedDepth < DeferredSplitDistances.x ? shadowPosition0 : shadowPosition1)
		:
		(unpackedDepth < DeferredSplitDistances.z ? shadowPosition2 : shadowPosition3);

#define kShadowSize2 (2.0f/4096.0f)
	
	float4 offsets[5] = 
	{
		float4( 0.0f, 0.0f,0,0),
		float4(-kShadowSize2,-kShadowSize2,0,0),
		float4( kShadowSize2,-kShadowSize2,0,0),
		float4(-kShadowSize2, kShadowSize2,0,0),
		float4( kShadowSize2, kShadowSize2,0,0),
	};
	
	float rslt = 1.0f;
	if(unpackedDepth < DeferredSplitDistances.w)
	{		
		float shadowValue0 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[0].xy, shadowPosition.z).x;
		float shadowValue1 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[1].xy, shadowPosition.z).x;
		float shadowValue2 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[2].xy, shadowPosition.z).x;
		float shadowValue3 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[3].xy, shadowPosition.z).x;
		float shadowValue4 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[4].xy, shadowPosition.z).x;

		rslt = (shadowValue1+shadowValue2+shadowValue3+shadowValue4)*0.125f + shadowValue0 * 0.5f;
	}
		
	return DeferredShadowMask * rslt;
}

float evaluateSpecular(float3 viewPos, float3 normal, float specularPower, float shininess)
{
	float3 eyeDir = normalize(viewPos); 
	
	// Specular calcs
	float3 floatVec = eyeDir; //eyeDirection + lightDir;
	float nDotH = saturate(dot(normal,floatVec));

	float specularLightAmount = saturate(pow(nDotH, specularPower)) * shininess; 

	return specularLightAmount;
}

float4 CompositeToScreenFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	float4 lightValue = LightBuffer.SampleLevel(PointClampSampler,input.uv.xy,0);
	float4 colValue = ColorBuffer.SampleLevel(PointClampSampler,input.uv.xy,0);	
	float emissiveness = colValue.w; 	
		
	float4 colour = float4((lightValue.xyz + emissiveness) * colValue.xyz, colValue.w);
	return colour;
}

float4 PS_CopyCompositedBufferToScreen(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR0
{
	return NormalDepthBuffer.SampleLevel(PointClampSampler,input.uv.xy,0);	
}

float4 MixLight(float4 colValue, float3 lightRslt, float viewSpaceDepth)
{
	float emissiveness = 0.0f;//colValue.w; 

	float glowAmount = saturate((colValue.w - AlphaGlowThreshold.x) * AlphaGlowThreshold.y);
	float4 lightValue = float4(lightRslt, 1.0f);
	float4 colour = (lightValue + glowAmount) * colValue;

	// Calculate fog
	float fogDepth = saturate((viewSpaceDepth - FogCoefficients.x) * FogCoefficients.z);
	fogDepth = exp2(fogDepth) - 1.0f;
	float fogAmount = saturate(fogDepth * FogCoefficients.w);
	colour.xyz = lerp(colour.xyz, FogColor.xyz, fogAmount);
	return colour;
}

float4 CompositeToScreenTiledFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{	
	uint screenWidth, screenHeight, samples;
#ifdef DEFERRED_MULTISAMPLE
	ColorBufferMS.GetDimensions(screenWidth, screenHeight, samples);
#else // DEFERRED_MULTISAMPLE
	ColorBuffer.GetDimensions(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE

	int2 pixelPosition = int2(input.position.xy);
#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT

	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;
	float4 lightValue = UnpackF16ToF32(LightingOutputBuffer[pixelIndex]);

#ifdef DEFERRED_MULTISAMPLE
	float4 colValue = ColorBufferMS.Load(pixelPosition, 0);
#else // DEFERRED_MULTISAMPLE
	float4 colValue = ColorBuffer.Load(int3(pixelPosition, 0));
#endif // DEFERRED_MULTISAMPLE

	float4 colour = colValue;
#ifdef DEFERRED_MULTISAMPLE
	float zvalue = DepthBufferMS.Load(pixelPosition, 0).x;
#else // DEFERRED_MULTISAMPLE
	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;
#endif // DEFERRED_MULTISAMPLE
	if(IsValidDepth(zvalue))
	{
		float viewSpaceDepth = ConvertDepth(zvalue);
		colour = MixLight(colValue, lightValue.xyz, viewSpaceDepth);
	}
	
	return colour;
}

float4 CopyLitToScreenFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	uint screenWidth, screenHeight, samples;
#ifdef DEFERRED_MULTISAMPLE
	ColorBufferMS.GetDimensions(screenWidth, screenHeight, samples);
#else // DEFERRED_MULTISAMPLE
	ColorBuffer.GetDimensions(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE

	int2 pixelPosition = int2(input.position.xy);
#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT
	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;
	float4 lightValue = UnpackF16ToF32(LightingOutputBuffer[pixelIndex]);

	return lightValue;
}

// Intended for debug only
float4 CompositeToScreenAddTiledFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
	uint screenWidth, screenHeight;
	ColorBuffer.GetDimensions(screenWidth, screenHeight);

	int2 pixelPosition = int2(input.position.xy);
#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT

	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;
	float4 debugValue = UnpackF16ToF32(LightingOutputBuffer[pixelIndex]);

#ifdef DEFERRED_MULTISAMPLE
	float4 colValue = ColorBufferMS.Load(pixelPosition, 0);
#else // DEFERRED_MULTISAMPLE
	float4 colValue = ColorBuffer.Load(int3(pixelPosition, 0));
#endif // DEFERRED_MULTISAMPLE
	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;
	float4 colour = colValue;
	if (IsValidDepth(zvalue))
		colour.xyz = lerp(colValue.xyz, debugValue.xyz, debugValue.w);

	return colour;
}

void GetScreenWidthHeight(out uint screenWidth, out uint screenHeight)
{
#ifdef DEFERRED_MULTISAMPLE
	uint samples;
	DepthBufferMS.GetDimensionsFast(screenWidth, screenHeight, samples);
#else //  DEFERRED_MULTISAMPLE
	DepthBuffer.GetDimensionsFast(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE
}

uint GetInputDepthBufferWidth()
{
	uint screenWidth, screenHeight;
#ifdef DEFERRED_MULTISAMPLE
	uint samples;
	DepthBufferMS.GetDimensionsFast(screenWidth, screenHeight, samples);
#else //  DEFERRED_MULTISAMPLE
	DepthBuffer.GetDimensionsFast(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE
	return screenWidth;
}

StructuredBuffer<uint> DeferredLightingTileIDs;

uint GetTilePosition(uint3 GroupId, uint3 GroupThreadId, uint3 DispatchThreadId, out uint2 tilePosition, out uint2 pixelPosition)
{
#if defined(DEFERRED_VR) && defined(__ORBIS__)
	uint tile = DeferredLightingTileIDs[GroupId.x];
	uint tileSizeShift = (tile >> 24) & 0xFF;
	uint tileSize = PE_DEFERRED_TILE_SIZE << tileSizeShift;
	tilePosition = uint2(tile & 0x3FF, (tile >> 10) & 0x3FF);
	pixelPosition = tilePosition * tileSize + GroupThreadId.xy;
	tilePosition <<= tileSizeShift;
	return tileSizeShift;
#else //! defined(DEFERRED_VR) && defined(__ORBIS__)
	tilePosition = GroupId.xy;
	pixelPosition = DispatchThreadId.xy;
	return 0;
#endif //! defined(DEFERRED_VR) && defined(__ORBIS__)
}

void WriteToOutputBuffer(uint2 pos, float4 color)
{
	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	if (pos.x < screenWidth && pos.y < screenHeight)
	{
		uint pixelIndex = pos.y * screenWidth + pos.x;

		// pack to half
		RWLightingOutputBuffer[pixelIndex] = PackF32ToF16(color);
	}
}

void WriteToOutputBuffer(uint2 pos, float3 color)
{
	WriteToOutputBuffer(pos, float4(color, 1.0f));
}


groupshared uint TileMinMaxZ[2];
groupshared float ZSamples[64 * 4];
groupshared uint NumSpotLightsActive;

groupshared uint NumInstantLightsActive;
groupshared uint ActiveInstantLightIndices[PE_MAX_ACTIVE_LIGHTS];

float3 ScreenToView(float2 screenPos, float viewSpaceDepth)
{
#ifdef DEFERRED_VR
	// Calculate viewPosition when using PlayStation(R)VR's Asymmetric projection matrices.
#ifdef __ORBIS__
	float3 viewPosition = float3(((screenPos.x * ProjInverse[0][0]) + ProjInverse[3][0]) * viewSpaceDepth, screenPos.y * ProjInverse[1][1] * viewSpaceDepth, -viewSpaceDepth);
#else //! __ORBIS__
	float3 viewPosition = float3(((screenPos.x * ProjInverse[0][0]) + ProjInverse[3][0]) * viewSpaceDepth, ((screenPos.y * ProjInverse[1][1]) + ProjInverse[3][1]) * viewSpaceDepth, -viewSpaceDepth);
#endif //! __ORBIS__
#else // DEFERRED_VR
	float3 viewPosition = float3(screenPos * InvProjXY.xy * viewSpaceDepth, -viewSpaceDepth);
#endif //! DEFERRED_VR
	return viewPosition;
}

float3 LightPoint(uint2 pixelPosition, float2 screenPos, float viewSpaceDepth, float4 normalGloss)
{
	uint i;
	float gloss = normalGloss.w;
	float3 viewSpaceNormal = normalize(float3(normalGloss.xyz * 2.0f - 1.0f));
	float3 viewPosition = ScreenToView(screenPos, viewSpaceDepth);
	float4 shadowResults = ShadowBuffer.Load(int3(pixelPosition, 0));

	float3 lightRslt = DeferredAmbientColor;
	for (i = 0; i < NumDeferredDirectionalLights; ++i)
	{
		PDeferredDirectionalLight light = DeferredDirectionalLights[i];
		float dp = saturate(dot(light.m_direction, viewSpaceNormal));

		float shadowBufferValue = CalculateShadow(light.m_shadowMask, shadowResults);
		lightRslt += (float3)(light.m_color * dp) * shadowBufferValue;
	}

	float3 eyeDirection = normalize(-viewPosition.xyz);

	for (i = 0; i < NumSpotLightsActive; ++i)
	{
		uint lightIndex = GetLightIndex(i);
		PDeferredLight light = DeferredSpotLights[lightIndex];

		float3 rslt = light.m_color.xyz;

		float3 lightDir = light.m_position - viewPosition.xyz;
		float3 lightDirNrm = normalize(lightDir);
		float dist = length(lightDir);
		float dp = dot(lightDirNrm, viewSpaceNormal);

		float distanceAttenuation = 1 - saturate(smoothstep(light.m_attenuation.x, light.m_attenuation.y, dist));

		float specularValue = calcSpecularLightAmt(viewSpaceNormal, eyeDirection, lightDirNrm, gloss, 7.0f);
		dp = saturate(dp);
		rslt *= (specularValue + dp) * distanceAttenuation;

		float spotDp = dot(lightDirNrm, light.m_direction);
		float spotAttenuation = saturate((light.m_spotAngles.y - max(spotDp, 0)) / (light.m_spotAngles.y - light.m_spotAngles.x));
		spotAttenuation = spotAttenuation * spotAttenuation;
		rslt *= spotAttenuation;

		float shadowBufferValue = CalculateShadow(light.m_shadowMask, shadowResults);
		rslt *= shadowBufferValue;
		lightRslt += rslt;
	}

	for (i = NumSpotLightsActive; i < NumLightsActive; ++i)
	{
		uint lightIndex = GetLightIndex(i);
		PDeferredLight light = DeferredPointLights[lightIndex];

		float3 rslt = light.m_color.xyz;

		float3 lightDir = light.m_position - viewPosition.xyz;
		float3 lightDirNrm = normalize(lightDir);
		float dist = length(lightDir);
		float dp = dot(lightDirNrm, viewSpaceNormal);

		float distanceAttenuation = 1 - saturate(smoothstep(light.m_attenuation.x, light.m_attenuation.y, dist));

		float specularValue = calcSpecularLightAmt(viewSpaceNormal, eyeDirection, lightDirNrm, gloss, 7.0f);
		dp = saturate(dp);
		rslt *= (specularValue + dp) * distanceAttenuation;

		float shadowBufferValue = CalculateShadow(light.m_shadowMask, shadowResults);
		rslt *= shadowBufferValue;

		lightRslt += rslt;
	}
	return lightRslt;
}

void FrustumCullLights(uint groupIndex, uint2 tilePosition, float2 unprojtileMinMax)
{
	uint i;

#ifndef __ORBIS__
	if (groupIndex == 0)
#endif // __ORBIS__
		NumLightsActive = 0;

	float2 tileMinMax;
#ifndef DEFERRED_VR

	tileMinMax.x = ConvertDepth(unprojtileMinMax.x);
	tileMinMax.y = ConvertDepth(unprojtileMinMax.y);

#else //! DEFERRED_VR

	// Calculate view space depth when using PlayStation(R)VR's Asymmetric projection matrices. Need to remap depth texture range to -1 to +1 using this method on PS4 hence the * 2.0f - 1.0f.
#ifdef __ORBIS__
	tileMinMax.x = ConvertDepthFullProjection(unprojtileMinMax.x * 2.0f - 1.0f);
	tileMinMax.y = ConvertDepthFullProjection(unprojtileMinMax.y * 2.0f - 1.0f);
#else
	tileMinMax.x = ConvertDepthFullProjection(unprojtileMinMax.x);
	tileMinMax.y = ConvertDepthFullProjection(unprojtileMinMax.y);
#endif //! __ORBIS__

#endif //! DEFERRED_VR

#ifdef __ORBIS__
	// Convert Z values to +-1 range to allow unproject
	unprojtileMinMax = unprojtileMinMax * 2 - 1;
#endif // __ORBIS__

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);

	float4 sphere;
	float4 frustumPlanes[6];
	GenerateFrustumPlanes(frustumPlanes, tilePosition, tileMinMax, sphere, unprojtileMinMax, screenWidth, screenHeight);

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive

	for (i = groupIndex; i < min(NumDeferredSpotLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		[branch] if (!SphereIntersectsCone(sphere, DeferredSpotLights[i].m_position, -DeferredSpotLights[i].m_direction, DeferredSpotLights[i].m_spotAngles.y, DeferredSpotLights[i].m_tanConeAngle))
			continue;
		bool isLightVisible = IsSpotLightVisible(DeferredSpotLights[i].m_position, -DeferredSpotLights[i].m_direction, DeferredSpotLights[i].m_attenuation.y, DeferredSpotLights[i].m_coneBaseRadius, frustumPlanes);

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive

	if (groupIndex == 0)
		NumSpotLightsActive = NumLightsActive;

	for (i = groupIndex; i < min(NumDeferredPointLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		[branch] if (!SphereIntersectsSphere(sphere, DeferredPointLights[i].m_position, DeferredPointLights[i].m_attenuation.y))
			continue;
		bool isLightVisible = IsPointLightVisible(DeferredPointLights[i].m_position, DeferredPointLights[i].m_attenuation.y, frustumPlanes);

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumSpotLightsActive and ensure all lights processed
}

void GetZRange(out ZRange range, uint2 tilePosition, uint2 pixelPosition)
{
#ifdef __ORBIS__

	// Get the size of the depth buffer
	uint screenWidth = GetInputDepthBufferWidth();

	uint ht = HTileData[HTileIndexForTile(tilePosition.x, tilePosition.y, screenWidth)];
	range.htile = ht;

	float2 tileMinMax = HTileToMinMaxZ(ht);

#else //! __ORBIS__

#ifdef DEFERRED_MULTISAMPLE

	float zvalue = DepthBufferMS.Load(int2(pixelPosition), 0);
	float zvalueMin = zvalue;
	float zvalueMax = zvalue;
	for (int i = 1; i < 4; i++)
	{
		float zsample = DepthBufferMS.Load(int2(pixelPosition), i);
		zvalueMin = min(zvalueMin, zsample);
		zvalueMax = max(zvalueMax, zsample);
	}

#else // DEFERRED_MULTISAMPLE

	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;
	float zvalueMin = zvalue;
	float zvalueMax = zvalue;

#endif // DEFERRED_MULTISAMPLE

	if (((pixelPosition.x | pixelPosition.y) & 0x7) == 0)
	{
		TileMinMaxZ[0] = asuint(1.0f);
		TileMinMaxZ[1] = asuint(0.0f);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync previous writes
	if (IsValidDepth(zvalue))
	{
		InterlockedMin(TileMinMaxZ[0], asuint(zvalueMin));
		InterlockedMax(TileMinMaxZ[1], asuint(zvalueMax));
	}
	GroupMemoryBarrierWithGroupSync();	// Sync updates

	range.zvalue = zvalue;

	float2 tileMinMax = float2(asfloat(TileMinMaxZ[0]), asfloat(TileMinMaxZ[1]));

#endif //! __ORBIS__

	range.unprojtileMinMax = tileMinMax;
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_RenderDeferredLightCount(
	uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 pixelPosition = DispatchThreadId.xy;
	uint2 tilePosition = GroupId.xy;

	ZRange zRange;
	GetZRange(zRange, tilePosition, pixelPosition);

	FrustumCullLights(GroupIndex, tilePosition, zRange.unprojtileMinMax);

	uint total = NumLightsActive;
	float3 color = float3(0, 0, 1);
	if (total < 10)
		color = float3(0, 1, 0);
	else if (total < 20)
		color = float3(1, 1, 0);
	else if (total < 30)
		color = float3(1, 0, 0);
	float colorscale = GetPixelMaskForDigit(total % 10, GroupThreadId.xy);
	color *= colorscale;

	WriteToOutputBuffer(DispatchThreadId.xy, float4(color, 0.15f + 0.85f * colorscale)); // Prepare for backend lerp 0->0.15, 1 -> 1
}

uint GetFragmentCount(uint fmaskValue)
{
	int s;
	uint sampleCounts = 0;
	for (s = 0; s < 4; s++)
	{
		int smpl = (fmaskValue >> (s * 4)) & ((1 << 4) - 1);
		sampleCounts += 1 << (smpl * 8);
	}

	uint fragmentCount = 0;
	for (s = 0; s < 4; s++)
	{
		if (sampleCounts & 0xFF)
			fragmentCount++;
		sampleCounts >>= 8;
	}
	return fragmentCount;
}

groupshared uint MaxFragments;

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_RenderDeferredMaxFragmentsPerTile(
	uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(pixelPosition, 0)).x;
	uint fragmentCount = GetFragmentCount(fmaskValue);

	if (GroupIndex == 0)
		MaxFragments = 0;
	GroupMemoryBarrierWithGroupSync();
	InterlockedMax(MaxFragments, fragmentCount);

	uint total = MaxFragments;
	float3 color = float3(1, 0, 0);
	if (total < 2)
		color = float3(0, 1, 0);
	else if (total < 3)
		color = float3(1, 0.5, 0);
	else if (total < 4)
		color = float3(1, 1, 0);

	WriteToOutputBuffer(pixelPosition.xy, float4(color, 0.5f));
}

groupshared uint TotalFragments;

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_RenderDeferredTotalAdditionalFragments(
	uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(pixelPosition, 0)).x;
	uint remainingFragmentCount = GetFragmentCount(fmaskValue) - 1;

	if (GroupIndex == 0)
		TotalFragments = 0;
	GroupMemoryBarrierWithGroupSync();
	InterlockedAdd(TotalFragments, remainingFragmentCount);

	uint total = TotalFragments;
	float3 color = float3(1, 0, 0);
	if (total < 1)
		color = float3(0, 1, 0);
	else if (total <= 64)
		color = float3(1, 0.5, 0);
	else if (total <= 128)
		color = float3(1, 1, 0);

	WriteToOutputBuffer(pixelPosition.xy, float4(color, 0.5f));
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_RenderDeferredFMASKPassesSaved(
	uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint x;
	uint y;
	uint2 tilePosition, pixelPosition;
	uint tileSizeShift = GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	uint maxFragmentCount = 0;
	uint totalFragments = 0;
	for (y = 0; y < 1 << tileSizeShift; y++)
	for (x = 0; x < 1 << tileSizeShift; x++)
	{
		uint2 currentPixelPosition = pixelPosition + uint2(x, y) * PE_DEFERRED_TILE_SIZE;
		int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(currentPixelPosition, 0)).x;
		uint fragmentCount = GetFragmentCount(fmaskValue);

		if (GroupIndex == 0)
			MaxFragments = 0;
		GroupMemoryBarrierWithGroupSync();
		InterlockedMax(MaxFragments, fragmentCount);

		maxFragmentCount += MaxFragments;
		totalFragments += fragmentCount - 1; // 1 processed locally
	}

	if (GroupIndex == 0)
		TotalFragments = 0;
	GroupMemoryBarrierWithGroupSync();
	InterlockedAdd(TotalFragments, totalFragments);

	int passes = 4 + ((TotalFragments + 63) / 64);
	int total = maxFragmentCount - passes;
	float3 color = float3(0, 1, 0);
	if (total <= 0) // MaxFragments <= passes - same or less work
		color = float3(1, 0, 0);
	else if (total == 1) // 
		color = float3(1, 0.5, 0);
	else if (total == 2)
		color = float3(1, 1, 0);

	for (y = 0; y < 1 << tileSizeShift; y++)
	for (x = 0; x < 1 << tileSizeShift; x++)
	{
		uint2 currentPixelPosition = pixelPosition + uint2(x, y) * PE_DEFERRED_TILE_SIZE;
			WriteToOutputBuffer(currentPixelPosition, float4(color, 0.5f));
	}
}

// Outputs for downsampled Z data on PS4 - allows non-AA reuse when rendering subsequent passes
RWTexture2D<float> RWDepthOutputBuffer;
RWStructuredBuffer<uint> RWHTileOutputData;

#ifdef __ORBIS__

void OutputHTile(uint2 tilePosition, uint htile)
{
	uint screenWidth, screenHeight;
	RWDepthOutputBuffer.GetDimensionsFast(screenWidth, screenHeight);

	uint2 outputTilePosition = tilePosition;
#ifdef DEFERRED_INVERT
	outputTilePosition.y = ((screenHeight >> PE_DEFERRED_TILE_SIZE_SHIFT) - 1) - outputTilePosition.y;
#endif // DEFERRED_INVERT
	RWHTileOutputData[HTileIndexForTile(outputTilePosition.x, outputTilePosition.y, screenWidth)] = htile;
}

void OutputZOnly(uint2 pixelPosition, float minZ)
{
	uint screenWidth, screenHeight;
	RWDepthOutputBuffer.GetDimensionsFast(screenWidth, screenHeight);

	uint2 outputPixelPosition = pixelPosition;
#ifdef DEFERRED_INVERT
	outputPixelPosition.y = (screenHeight - 1) - outputPixelPosition.y;
#endif // DEFERRED_INVERT
	RWDepthOutputBuffer[outputPixelPosition] = minZ;
}

void OutputZ(uint2 pixelPosition, uint2 tilePosition, float minZ, uint htile)
{
	OutputZOnly(pixelPosition, minZ);
	OutputHTile(tilePosition, htile);
}

#endif // __ORBIS__

// Note: sampleIndex is really a fragment index on PS4.
float3 LightSampleWithZ(int sampleIndex, uint2 pixelPosition, float viewSpaceDepth, float2 invViewportWidthHeight)
{
	float2 uv = float2(pixelPosition) * invViewportWidthHeight;
	float2 screenPos = GetScreenPosition(uv);
	float4 normalMapValue = NormalDepthBufferMS.Load(int2(pixelPosition), sampleIndex);

	// Mix color with lighting per sample
	float3 lighted = LightPoint(pixelPosition, screenPos, viewSpaceDepth, normalMapValue);
	float4 color = ColorBufferMS.Load(int2(pixelPosition), sampleIndex);
	return MixLight(color, lighted, viewSpaceDepth).xyz;
}

// Note: sampleIndex is really a fragment index on PS4.
float3 LightSample(int sampleIndex, uint2 pixelPosition, uint groupIndex, float count, float2 invViewportWidthHeight)
{
#ifdef __ORBIS__
	float zvalue = ZSamples[groupIndex + sampleIndex * 64] / count;
	float viewSpaceDepth = zvalue;
#else
	float zvalue = DepthBufferMS.Load(int2(pixelPosition), sampleIndex).x;
	float viewSpaceDepth = ConvertDepth(zvalue);
#endif
	return LightSampleWithZ(sampleIndex, pixelPosition, viewSpaceDepth, invViewportWidthHeight);
}

float3 CS_GenerateLightingTiled(
	uint2 tilePosition,
	uint2 pixelPosition,
	uint groupIndex)
{
	ZRange zRange;
	GetZRange(zRange, tilePosition, pixelPosition);
	FrustumCullLights(groupIndex, tilePosition, zRange.unprojtileMinMax);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

#ifdef DEFERRED_MULTISAMPLE
	float3 lightRslt = float3(0, 0, 0);

	uint sampleRequiredMask = 0;	// Mask of samples required - 1 byte per sample, bottom bit set if required - for FirstSetBit_Lo
	uint sampleCounts = 0;			// Number of copies of sample required

#ifdef __ORBIS__
	int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(pixelPosition, 0)).x;
	for (int s = 0; s < 4; s++)
		ZSamples[groupIndex + s * 64] = 0.0f;

	float minZ = 1.0f;
	for (int s = 0; s < 4; s++)
	{
		int smpl = (fmaskValue >> (s * 4)) & ((1 << 4) - 1);
		// Assumed int valid = (smpl != 0x8) ? 1 : 0;
		int valid = 1;
		if (valid)
		{
			float zvalue = DepthBufferMS.Load(int2(pixelPosition), s).x;
#ifdef ALL_SAMPLES
			ZSamples[groupIndex + smpl * 64] = ConvertDepth(zvalue);
#else
			ZSamples[groupIndex + smpl * 64] += ConvertDepth(zvalue);
#endif
			minZ = min(minZ, zvalue);
		}
		int mask = valid << (smpl * 8);
		sampleCounts += mask;
		sampleRequiredMask |= mask;
	}

	OutputZ(pixelPosition, tilePosition, minZ, zRange.htile);

#else // __ORBIS__

	sampleCounts = 0x01010101;
	sampleRequiredMask = sampleCounts;
	uint fmaskValue = 0x3210;

#endif // __ORBIS__

	float sum = 0;

#ifdef SAMPLE_MASK
	int smpl = 0;
	do
	{
		float count = (float)(sampleCounts & 0xff);
		sum += count;
		lightRslt += count * LightSample(smpl, pixelPosition, groupIndex, count, invViewportWidthHeight).xyz;
		smpl++;
		sampleCounts >>= 8;
	} while (sampleCounts);
#endif //! SAMPLE_MASK

#ifdef ALL_SAMPLES
	for (int s = 0; s < 4; s++)
	{
		int smpl = (fmaskValue >> (s * 4)) & ((1 << 4) - 1);
		// Assumed: if (smpl != 8)
		{
			lightRslt += LightSample(smpl, pixelPosition, groupIndex, 1.0f, invViewportWidthHeight).xyz;
			sum += 1.0f;
		}
	}
#endif // ALL_SAMPLES

#ifdef SAMPLE_LIST
	do
	{
		uint next = ConsumeNextBitFromMask(sampleRequiredMask);
		uint smpl = next / 8;
		float count = UnpackByte0(sampleCounts >> next);
		lightRslt += count * LightSample(smpl, pixelPosition, groupIndex, count, invViewportWidthHeight).xyz;
		sum += count;
	} while (sampleRequiredMask);
#endif //! SAMPLE_LIST

	lightRslt /= sum;

#else // DEFERRED_MULTISAMPLE

	float3 lightRslt = float3(0,0,0);
	float2 uv = float2(pixelPosition) * invViewportWidthHeight;
	float2 screenPos = GetScreenPosition(uv);

#ifdef __ORBIS__
		float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;
#else // __ORBIS__
		float zvalue = zRange.zvalue;
#endif // __ORBIS__

	float4 normalMapValue = NormalDepthBuffer.Load(int3(pixelPosition, 0));
	float viewSpaceDepth = ConvertDepth(zvalue);

	lightRslt += LightPoint(pixelPosition, screenPos, viewSpaceDepth, normalMapValue);

#endif // DEFERRED_MULTISAMPLE

	return lightRslt;
}

float3 CS_GenerateLightingTiledLQ(
	uint2 tilePosition,
	uint2 pixelPosition,
	uint groupIndex)
{
	ZRange zRange;
	GetZRange(zRange, tilePosition, pixelPosition);
	FrustumCullLights(groupIndex, tilePosition, zRange.unprojtileMinMax);

#ifdef __ORBIS__
	int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(pixelPosition, 0)).x;
	uint fragmentHisto = 0x03020100;
	for (int s = 0; s < 4; s++)
	{
		int frag = (fmaskValue >> (s * 4)) & ((1 << 4) - 1);
		// Assumed int valid = (frag != 0x8) ? 1 : 0;
		int valid = 1;
		int mask = valid << (frag * 8);
		fragmentHisto += mask << 4;
	}

	uint f0 = (fragmentHisto >> 0) & 0xFF;
	uint f1 = (fragmentHisto >> 8) & 0xFF;
	uint f2 = (fragmentHisto >> 16) & 0xFF;
	uint f3 = (fragmentHisto >> 24) & 0xFF;
	uint fmax = max(max(f0, f1), max(f2, f3));
	int fragmentToProcess = fmax & 0xF;

	float aveZ = 0.0f;
	float minZ = 1.0f;
	for (int s = 0; s < 4; s++)
	{
		int frag = (fmaskValue >> (s * 4)) & ((1 << 4) - 1);
		float zvalue = DepthBufferMS.Load(int2(pixelPosition), s).x;
		if (frag == fragmentToProcess)
			aveZ += ConvertDepth(zvalue);
		minZ = min(minZ, zvalue);
	}
	OutputZ(pixelPosition, tilePosition, minZ, zRange.htile);
	float zvalue = aveZ / (float)(fmax >> 4);

#else // __ORBIS__

	// Just 1 sample on PC
	int fragmentToProcess = 0;
	float zvalue = DepthBufferMS.Load(int2(pixelPosition), fragmentToProcess).x;
	zvalue = ConvertDepth(zvalue);

#endif // __ORBIS__

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

	return LightSampleWithZ(fragmentToProcess, pixelPosition, zvalue, invViewportWidthHeight).xyz;
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_RenderDeferredLightOnly(
	uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	float3 lightResult = CS_GenerateLightingTiled(GroupId.xy, DispatchThreadId.xy, GroupIndex);

	WriteToOutputBuffer(DispatchThreadId.xy, float4(lightResult, 1));
}

// Inscattering function - derivations from Miles Macklin
// This one is faster but fails for wide cone angles > pi/4
float evaluateInScatteringThinCones(float3 start, float3 dir, float3 lightPos, float d)
{
	float3 q = start - lightPos;

	float b = dot(dir, q);
	float c = dot(q, q);
	float s = 1.0f / sqrt(c - b*b);
	// Trig identity version from Miles Macklin's faster fog update - appears to fail if outer cone angle > pi/4
	float x = d*s;
	float y = b*s;
	float l = s * atan( (x) / (1.0+(x+y)*y));
	return l;	
}

// Inscattering function - derivations from Miles Macklin
// Slower but works for wide angles
float evaluateInScattering(float3 start, float3 dir, float3 lightPos, float d)
{
	float3 q = start - lightPos;

	float b = dot(dir, q);
	float c = dot(q, q);
	float s = 1.0f / sqrt(c - b*b);
	float l = s * (atan( (d + b) * s) - atan( b*s ));
	return l;	
}

bool solveQuadratic(float a, float b, float c, out float r0, out float r1)
{
	float discrim = b*b - 4.0f*a*c;
	if (discrim < 0.0f)
	{
		r0 = 1.0;
		r1 = 0.0;
		return false;
	}
	float q = sqrt(discrim) * (b < 0.0f ? -1.0f : 1.0f);
	q = (q + b) * -0.5f;

	float rslt0 = q/a;
	float rslt1 = c/q;

	r0 = min(rslt0, rslt1);
	r1 = max(rslt0, rslt1);

	return true;
}

void intersectCone(float3 localOrigin, float3 localDir, float tanConeAngle, float height, out float minT, out float maxT)
{
	localDir = localDir.xzy;
	localOrigin = localOrigin.xzy;

	// Stop massively wide-angled cones from exploding by clamping the tangent. 
	tanConeAngle = min(tanConeAngle, 6.0f);

	float tanTheta = tanConeAngle * tanConeAngle;
	
	float a = localDir.x*localDir.x + localDir.z*localDir.z - localDir.y*localDir.y*tanTheta;
	float b = 2.0*(localOrigin.x*localDir.x + localOrigin.z*localDir.z - localOrigin.y*localDir.y*tanTheta);
	float c = localOrigin.x*localOrigin.x + localOrigin.z*localOrigin.z - localOrigin.y*localOrigin.y*tanTheta;

	if(solveQuadratic(a, b, c, minT, maxT))
	{
		float y1 = localOrigin.y + localDir.y*minT;
		float y2 = localOrigin.y + localDir.y*maxT;
		
		// should be possible to simplify these branches if the compiler isn't already doing it
		if (y1 > 0.0f && y2 > 0.0f)
		{
			// both intersections are in the reflected cone so return degenerate value
			minT = 0.0;
			maxT = -1.0;
		}
		else if (y1 > 0.0f && y2 < 0.0f)
		{
			// closest t on the wrong side, furthest on the right side => ray enters volume but doesn't leave it (so set maxT arbitrarily large)
			minT = maxT;
			maxT = 10000.0;
		}
		else if (y1 < 0.0f && y2 > 0.0f)
		{
			// closest t on the right side, largest on the wrong side => ray starts in volume and exits once
			maxT = minT;
			minT = 0.0;		
		}
	}
}

float4 PS_EvaluateScatteringLights(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR0
{
	// Load shared data 
	uint2 pixelPosition = (uint2)input.position.xy;
		
	float2 uv = float2(pixelPosition) * ViewportWidthHeightInv;
	float2 screenPos = GetScreenPosition(uv);
		
	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x; 
	
	float3 scatterResult = 0.0f;
	if(IsValidDepth(zvalue))
	{
		uint i;
		float viewSpaceDepth = ConvertDepth(zvalue);		
		float4 viewRayDirection = float4( normalize(float3(screenPos.xy * InvProjXY.xy, -1.0f)), 0);
	
		for(i = 0; i < NumDeferredSpotLights; ++i)
		{
			PDeferredLight light = DeferredSpotLights[i];
			
			float3 rayPos = mul(float4(0,0,0,1.0f), light.m_viewToLocalTransform).xyz;
			float3 rayDir = normalize( mul(viewRayDirection, light.m_viewToLocalTransform).xyz );
		
			float t0 = 0.0f;
			float t1 = viewSpaceDepth;
			intersectCone(rayPos, rayDir, light.m_tanConeAngle, light.m_attenuation.y, t0, t1);
			t1 = clamp(t1, 0.0f, viewSpaceDepth);
			t0 = max(0.0f, t0);
			
			[branch] if(t1 > t0)
			{
				scatterResult += (float3)(light.m_color * evaluateInScattering(rayPos + rayDir*t0, rayDir, 0, t1-t0) * light.m_scatterIntensity);
			}
		}
		for (i = 0; i < NumDeferredPointLights; ++i)
		{
			PDeferredLight light = DeferredPointLights[i];

			float3 rayPos = mul(float4(0, 0, 0, 1.0f), light.m_viewToLocalTransform).xyz;
			float3 rayDir = normalize(mul(viewRayDirection, light.m_viewToLocalTransform).xyz);

			float t0 = 0.0f;
			float t1 = viewSpaceDepth;

			[branch] if (t1 > t0)
			{
				scatterResult += (float3)(light.m_color * evaluateInScattering(rayPos + rayDir*t0, rayDir, 0, t1 - t0) * light.m_scatterIntensity);
			}
		}

		scatterResult = pow(scatterResult, 1.0f/2.2f);
	}	
	return float4(scatterResult,0);
}

void GenerateFrustumPlanesInstantLights(out float4 frustumPlanes[6], uint2 tileLocation, float2 tileMinMax)
{
	uint screenWidth, screenHeight;
	screenWidth = uint(ViewportWidthHeight.x);
	screenHeight = uint(ViewportWidthHeight.y);

	uint2 numTilesXY = uint2(screenWidth,screenHeight) >> PE_DEFERRED_TILE_SIZE_SHIFT;
	numTilesXY += (uint2(screenWidth,screenHeight) & (PE_DEFERRED_TILE_SIZE-1)) != 0 ? 1 : 0;
	
#ifdef __ORBIS__
	tileLocation.y = numTilesXY.y - tileLocation.y;
#endif //! __ORBIS__

	float2 tileScale = float2(numTilesXY) * 0.5f;
	float2 tileBias = tileScale - float2(tileLocation.xy);
	
	float4 cx = float4( -Projection[0].x * tileScale.x, 0.0f, tileBias.x, 0.0f);
	float4 cy = float4(0.0f, Projection[1].y * tileScale.y, tileBias.y, 0.0f);
	float4 cw = float4(0.0f, 0.0f, -1.0f, 0.0f);
		
	frustumPlanes[0] = cw - cx;		// left
	frustumPlanes[1] = cw + cx;		// right
	frustumPlanes[2] = cw - cy;		// bottom
	frustumPlanes[3] = cw + cy;		// top
	frustumPlanes[4] = float4(0.0f, 0.0f, -1.0f, -tileMinMax.x);	// near
	frustumPlanes[5] = float4(0.0f, 0.0f,  1.0f,  tileMinMax.y);	// far

	for (uint i = 0; i < 4; ++i) 
	{
		frustumPlanes[i] /= length(frustumPlanes[i].xyz);
	}
}

bool IsInstantSpotLightVisible(float3 lightPosition, float3 spotDir, float lightRadius, float coneBaseRadius, float4 frustumPlanes[6])
{
	bool inFrustum = true;
	for (uint i = 0; i < 4; ++i) 
	{
		bool d = ConePlaneTest(frustumPlanes[i], lightPosition, spotDir, lightRadius, coneBaseRadius);
		inFrustum = inFrustum && d;
	}
	return inFrustum;
}

bool IsInstantPointLightVisible(float3 lightPosition, float lightRadius, float4 frustumPlanes[6])
{
	bool inFrustum = true;
	for (uint i = 0; i < 4; ++i) 
	{
		float d = dot(frustumPlanes[i], float4(lightPosition, 1.0f));
		inFrustum = inFrustum && (d >= -lightRadius);
	}
	return inFrustum;
}

void FrustumCullInstantLights(uint groupIndex, uint numLights, uint2 tilePosition, float2 tileMinMax)
{
	float4 frustumPlanes[6];
	GenerateFrustumPlanesInstantLights(frustumPlanes, tilePosition, tileMinMax);

	for(uint i = groupIndex; i < min(numLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		bool isLightVisible = true;
		if(DeferredInstantLights[i].m_lightType == PD_DEFERRED_LIGHT_TYPE_SPOT)
		{
			isLightVisible = IsInstantSpotLightVisible(DeferredInstantLights[i].m_position, -DeferredInstantLights[i].m_direction, DeferredInstantLights[i].m_attenuation.y * 3.0f,DeferredInstantLights[i].m_coneBaseRadius * 3.0f, frustumPlanes);
		}
		else
		{
			isLightVisible = IsInstantPointLightVisible(DeferredInstantLights[i].m_position, DeferredInstantLights[i].m_attenuation.y * 3.0f,frustumPlanes);
		}
		
		if(isLightVisible && DeferredInstantLights[i].m_attenuation.y > 0.0001f)
		{
			uint listIndex;
			InterlockedAdd(NumInstantLightsActive, uint(1), listIndex);
			if(listIndex < PE_MAX_ACTIVE_LIGHTS)
			{
				ActiveInstantLightIndices[listIndex] = i;
			}
		}
	}
	GroupMemoryBarrierWithGroupSync();
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateLightingInstantLightsTiled(	uint3 GroupId : SV_GroupID, 
						uint3 DispatchThreadId : SV_DispatchThreadID, 
						uint3 GroupThreadId : SV_GroupThreadID)
{
   // Load shared data 
	uint groupIndex = GroupThreadId.y * PE_DEFERRED_TILE_SIZE + GroupThreadId.x;
	uint2 pixelPosition = DispatchThreadId.xy;
	uint2 tilePosition = GroupId.xy;

	uint numLights = DeferredLightCount[0];

	// Get the size of the depth buffer
	uint screenWidth, screenHeight;
	DepthBuffer.GetDimensions(screenWidth, screenHeight);
	
	uint pixelIndex = DispatchThreadId.y * screenWidth + DispatchThreadId.x;

	if (groupIndex == 0)
		NumInstantLightsActive = 0;

	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;  

	float2 tileMinMax = cameraNearFar;
	GroupMemoryBarrierWithGroupSync();
	FrustumCullInstantLights(groupIndex, numLights, tilePosition, tileMinMax);

	if(pixelPosition.x < screenWidth && pixelPosition.y < screenHeight)
	{
		float3 scatterResult = 0;
		
		if(IsValidDepth(zvalue))
		{
			float3 lightRslt = 0;	
		
			float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

			float2 uv = float2(pixelPosition) * ViewportWidthHeightInv;
			float2 screenPos = GetScreenPosition(uv);

			float4 normalMapValue = NormalDepthBuffer.Load(int3(pixelPosition, 0));
			float viewSpaceDepth = ConvertDepth(zvalue);
			float3 viewSpaceNormal = normalize(float3(normalMapValue.xyz * 2.0f - 1.0f));
					
			float3 viewRayDirection = float3(screenPos * InvProjXY.xy, -1.0f);
			float3 viewPosition = viewRayDirection * viewSpaceDepth;

			float3 eyeDirection = normalize(-viewPosition);

			//float3 viewRayDirection = normalize(viewPosition); //normalize(float3(screenPos * InvProjXY, -1.0f));
			float3 worldRayPos = ViewInverse[3].xyz;//mul(float4(0,0,0,1.0f), ViewInverse).xyz;
			float3 worldRayDir = mul(float4(viewRayDirection,0.0f), ViewInverse).xyz;

			for (int i = 0; i < min(int(NumInstantLightsActive), PE_MAX_ACTIVE_LIGHTS); ++i)
			{
				uint lightIndex = ActiveInstantLightIndices[i];
				PDeferredLight light = DeferredInstantLights[lightIndex];

				float3 rslt = light.m_color.xyz;

				float3 lightDir = light.m_position - viewPosition;
				float dist = length(lightDir);
				float3 lightDirNrm = (lightDir) * (1.0f/dist);
				float dp = dot(lightDirNrm,viewSpaceNormal);

				float distanceAttenuation = 1-saturate(smoothstep(light.m_attenuation.x,light.m_attenuation.y,dist));

				float specularValue = calcSpecularLightAmt(viewSpaceNormal, eyeDirection, lightDirNrm, normalMapValue.w, 7.0f);
				dp = saturate(dp);
				rslt *= (specularValue + dp) * distanceAttenuation;

				float3 rayPos = mul(float4(worldRayPos,1.0f), light.m_viewToLocalTransform).xyz;
				float3 rayDir = normalize( mul(float4(worldRayDir,0.0f), light.m_viewToLocalTransform).xyz );
			
				float t0 = 0.0f;
				float t1 = viewSpaceDepth;

				if(light.m_lightType == PD_DEFERRED_LIGHT_TYPE_SPOT)
				{
					float spotDp = dot(lightDirNrm,light.m_direction);
					float spotAttenuation = saturate((light.m_spotAngles.y - max(spotDp,0)) / (light.m_spotAngles.y - light.m_spotAngles.x));
					spotAttenuation = spotAttenuation * spotAttenuation;
					rslt *= spotAttenuation;
					
					intersectCone(rayPos, rayDir, light.m_tanConeAngle, light.m_attenuation.y, t0, t1);
					t1 = clamp(t1, 0.0f, viewSpaceDepth);
					t0 = max(0.0f, t0);
				}
								
				lightRslt += rslt;
							
				if(t1 > t0)
				{
					scatterResult += (float3)(light.m_color * evaluateInScatteringThinCones(rayPos + rayDir*t0, rayDir, 0, t1-t0) * light.m_scatterIntensity);
				}
			}

			lightRslt *= DeferredInstantIntensity;

			// pack to half
			float4 previousLightResult = UnpackF16ToF32(RWLightingOutputBuffer[pixelIndex]);
			lightRslt.xyz += previousLightResult.xyz;
			WriteToOutputBuffer(DispatchThreadId.xy, lightRslt);

			scatterResult *= DeferredInstantScatteringIntensity;
			scatterResult = pow(scatterResult, 1.0f/2.2f);		
		}

		RWScatteredLightingOutputBuffer[pixelIndex] = PackF32ToF16(float4(scatterResult.xyz, 1.0f));
	}
}

float4 PS_EvaluateScatteringInstantLights(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR0
{
	uint pixelIndex = uint(input.position.y) * uint(ViewportWidthHeight.x) + uint(input.position.x);
	float4 lightValue = UnpackF16ToF32(LightingOutputBuffer[pixelIndex]);

	return lightValue;
}

#ifdef __ORBIS__
	#ifdef PHYRE_ENTRYPOINT_CS_GenerateLightingToOutputBuffer
		#pragma argument(fastmath)
	#endif //! PHYRE_ENTRYPOINT_CS_GenerateLightingToOutputBuffer
#endif //! __ORBIS__

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateLightingToOutputBuffer(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	float3 lightRslt = CS_GenerateLightingTiled(GroupId.xy, DispatchThreadId.xy, GroupIndex);
	WriteToOutputBuffer(DispatchThreadId.xy, lightRslt);
}

RWTexture2D<float4> CompositeTarget;

void Output(uint2 pixelPosition, float3 lightRslt)
{
	uint2 outputPixelPosition = pixelPosition;
#ifdef DEFERRED_INVERT
	uint screenWidth, screenHeight;
	CompositeTarget.GetDimensionsFast(screenWidth, screenHeight);
	outputPixelPosition.y = (screenHeight - 1) - outputPixelPosition.y;
#endif // DEFERRED_INVERT

#ifdef DEFERRED_MULTISAMPLE

	// Multisample mixes color per sample as required
	CompositeTarget[outputPixelPosition] = float4(lightRslt, 1);

#else // DEFERRED_MULTISAMPLE

	float zvalue = DepthBuffer[pixelPosition].x;
	float4 colValue = ColorBuffer[pixelPosition];
	if (IsValidDepth(zvalue))
	{
		float viewSpaceDepth = ConvertDepth(zvalue);
		CompositeTarget[outputPixelPosition] = MixLight(colValue, lightRslt, viewSpaceDepth);
	}
	else
	{
		CompositeTarget[outputPixelPosition] = colValue;
	}
#endif // DEFERRED_MULTISAMPLE
}

#define MAX_TILE_SIZE 16
groupshared uint IntermediateResults[MAX_TILE_SIZE * MAX_TILE_SIZE];

uint PackLighting(float3 lightResult, float scale)
{
	lightResult = saturate(lightResult) * (1023.0f /4.0f) * scale;
	return uint(lightResult.x) | (uint(lightResult.y) << 10) | (uint(lightResult.z) << 20);
}

float GetViewSpaceDepthForMask(uint2 currentPixelPosition, uint sampleMask)
{
	float aveZ = 0.0f;
	uint count = countbits(sampleMask);
	do
	{
		uint bit = firstbitlow(sampleMask);
		float zvalue = DepthBufferMS.Load(int2(currentPixelPosition), bit).x;
		aveZ += ConvertDepth(zvalue);
		sampleMask ^= 1 << bit;
	} while (sampleMask);
	return aveZ / count;
}

void ProcessFragment(uint index, uint tileSize, uint2 tilePixelOrigin, float2 invViewportWidthHeight)
{
	uint packedFragment = GetFragmentToProcess(index);
	uint smpl = packedFragment & 0x3;
	uint x = (packedFragment >> 2) & 0xF;
	uint y = (packedFragment >> 6) & 0xF;
	uint sampleMask = (packedFragment >> 10) & 0xF;

	uint count = countbits(sampleMask);
	uint2 currentPixelPosition = tilePixelOrigin + uint2(x, y);
	float aveZ = GetViewSpaceDepthForMask(currentPixelPosition, sampleMask);

	float3 lightRslt = LightSampleWithZ(smpl, currentPixelPosition, aveZ, invViewportWidthHeight).xyz;
	uint packedResult = PackLighting(lightRslt, count);
	InterlockedAdd(IntermediateResults[x + mul24(y, tileSize)], packedResult);
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateAndCompositeLightingTiled(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	uint tileSizeShift = GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

#if defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)
	tileSizeShift = 1;	// Assumption: Known tile size for this variant of the shader - allows the shader compiler to optimize for that case
	FragsToDo = 0;

	uint depthBufferWidth = GetInputDepthBufferWidth();
	float2 tileMinMax = float2(1, 0);
	for (uint y = 0; y < 1 << tileSizeShift; y++)
	for (uint x = 0; x < 1 << tileSizeShift; x++)
	{
		uint2 currentTilePosition = tilePosition + uint2(x, y);
		uint ht = HTileData[HTileIndexForTile(currentTilePosition.x, currentTilePosition.y, depthBufferWidth)];
		float2 currentTileMinMax = HTileToMinMaxZ(ht);
		tileMinMax.x = min(tileMinMax.x, currentTileMinMax.x);
		tileMinMax.y = max(tileMinMax.y, currentTileMinMax.y);
		OutputHTile(currentTilePosition, ht);
	}

	FrustumCullLights(GroupIndex, tilePosition, tileMinMax);

	uint tileSize = PE_DEFERRED_TILE_SIZE << tileSizeShift;
	for (uint y = 0; y < 8 << tileSizeShift; y += 8)
	for (uint x = 0; x < 8 << tileSizeShift; x += 8)
	{
		uint2 pixelInTile = GroupThreadId.xy + uint2(x, y);
		uint2 currentPixelPosition = pixelInTile + tilePosition * PE_DEFERRED_TILE_SIZE;
		uint sampleRequiredMask = 0;	// Mask of samples required - 1 byte per sample, bottom bit set if required - for FirstSetBit_Lo
		uint sampleMasks = 0;
		int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(currentPixelPosition, 0)).x;
		float minZ = 1.0f;
		for (int s = 0; s < 4; s++)
		{
			int smpl = (fmaskValue >> (s * 4)) & ((1 << 4) - 1);
			float zvalue = DepthBufferMS.Load(int2(currentPixelPosition), s).x;
			minZ = min(minZ, zvalue);
			int mask = 1 << (smpl * 8);
			sampleRequiredMask |= mask;
			sampleMasks |= mask << s;
		}
		OutputZOnly(currentPixelPosition, minZ);

		uint firstSample = ConsumeNextBitFromMask(sampleRequiredMask);

		while (sampleRequiredMask)
		{
			uint next = ConsumeNextBitFromMask(sampleRequiredMask);
			uint smpl = next / 8;

			uint sampleMask = (sampleMasks >> next) & 0xF;

			uint packedFragment = smpl | (pixelInTile.x << 2) | (pixelInTile.y << 6) | (sampleMask << 10);
			AddFragmentToProcess(packedFragment);
		}

		uint smpl = firstSample / 8;
		uint sampleMask = (sampleMasks >> firstSample) & 0xF;
		float count = countbits(sampleMask);
		float aveZ = GetViewSpaceDepthForMask(currentPixelPosition, sampleMask);

		float3 lightRslt = LightSampleWithZ(smpl, currentPixelPosition, aveZ, invViewportWidthHeight).xyz;
		uint packedResult = PackLighting(lightRslt, count);
		IntermediateResults[pixelInTile.x + mul24(pixelInTile.y, tileSize)] = packedResult;

		while (FragsToDo >= 64)
		{
			uint index = (FragsToDo - 1) - GroupIndex;
			FragsToDo -= 64;
			ProcessFragment(index, tileSize, tilePosition * PE_DEFERRED_TILE_SIZE, invViewportWidthHeight);
		}

		// Handle scrag element - will have bits set in upper 16
		if (FragsToDo & 0x1)
			FragsToDoList[FragsToDo / 2] = FragsToDoList[FragsToDo / 2] & 0xFFFF;
	}

	// Less than 64 remaining
	if (GroupIndex < FragsToDo)
		ProcessFragment(GroupIndex, tileSize, tilePosition * PE_DEFERRED_TILE_SIZE, invViewportWidthHeight);

	for (uint y = 0; y < 8 << tileSizeShift; y += 8)
	for (uint x = 0; x < 8 << tileSizeShift; x += 8)
	{
		uint2 pixelInTile = GroupThreadId.xy + uint2(x, y);
		uint packedResult = IntermediateResults[pixelInTile.x + mul24(pixelInTile.y, tileSize)];
		float3 lightRslt = float3(packedResult & 0x3FF, (packedResult >> 10) & 0x3FF, (packedResult >> 20) & 0x3FF) / 1023.0f;
		uint2 currentPixelPosition = pixelInTile + tilePosition * PE_DEFERRED_TILE_SIZE;
		Output(currentPixelPosition, lightRslt);
	}
#else // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)

	float3 lightRslt = CS_GenerateLightingTiled(tilePosition, pixelPosition, GroupIndex);
	Output(pixelPosition, lightRslt);

#endif // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateAndCompositeLightingTiledLQ(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	float3 lightRslt = CS_GenerateLightingTiledLQ(tilePosition, pixelPosition, GroupIndex);
	Output(pixelPosition, lightRslt);
}

groupshared float SwapSpace[4][4];

// Uses SwapSpace to exchange a set of sub tile values to output low res data to a higher resolution output.
// For example, if tileSizeShift = 1, we have 2x2 tiles to output and 8x8 threads, so we need to copy 4x4 to SwapSpace then re-distribute the output value per thread.
// value - The value to exchange.
// GroupThreadId - The ID of this thread in the tile.
// subTileXY - The XY coordinates of the output tile in the current super tile.
// tileSizeShift - The shift to calculate the size of the sub-tile.
float GetOutputFor(float value, uint2 GroupThreadId, uint2 subTileXY, uint tileSizeShift)
{
	uint outputTileSize = PE_DEFERRED_TILE_SIZE >> tileSizeShift;
	int2 outputXY = int2(GroupThreadId) - int2(subTileXY * outputTileSize);
	bool inThisTile = max(uint(outputXY.x), uint(outputXY.y)) < outputTileSize; // Use unsigned compare to check within range 0 to outputTileSize
	if (inThisTile)
		SwapSpace[outputXY.y][outputXY.x] = value;
	GroupMemoryBarrierWithGroupSync();

	return SwapSpace[GroupThreadId.y >> tileSizeShift][GroupThreadId.x >> tileSizeShift];
}

[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateAndCompositeLightingTiledLowLowQ(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	uint tileSizeShift = GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

#if defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)
	tileSizeShift = 1;	// Assumption: Known tile size for this variant of the shader - allows the shader compiler to optimize for that case

	uint depthBufferWidth = GetInputDepthBufferWidth();
	float2 tileMinMax = float2(1, 0);
	for (uint y = 0; y < 1 << tileSizeShift; y++)
	for (uint x = 0; x < 1 << tileSizeShift; x++)
	{
		uint2 currentTilePosition = tilePosition + uint2(x, y);
		uint ht = HTileData[HTileIndexForTile(currentTilePosition.x, currentTilePosition.y, depthBufferWidth)];
		float2 currentTileMinMax = HTileToMinMaxZ(ht);
		tileMinMax.x = min(tileMinMax.x, currentTileMinMax.x);
		tileMinMax.y = max(tileMinMax.y, currentTileMinMax.y);
		OutputHTile(currentTilePosition, ht);
	}

	FrustumCullLights(GroupIndex, tilePosition, tileMinMax);

	// Do every other pixel to reduce load
	uint2 currentPixelPosition = (GroupThreadId.xy << tileSizeShift) + (tilePosition * PE_DEFERRED_TILE_SIZE);

	int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(currentPixelPosition, 0)).x;
	float minZ = DepthBufferMS.Load(int2(currentPixelPosition), 0).x;
	float zvalue = ConvertDepth(minZ);
	int fragmentToProcess = fmaskValue & 0xF;

	for (uint y = 0; y < 1 << tileSizeShift; y++)
	for (uint x = 0; x < 1 << tileSizeShift; x++)
	{
		//OutputZOnly(currentPixelPosition + uint2(x, y), minZ);
		uint offset = x + y << tileSizeShift;
		float zToWrite = GetOutputFor(minZ, GroupThreadId.xy, uint2(x, y), tileSizeShift);
		uint2 pp = GroupThreadId.xy + ((tilePosition + uint2(x,y))* PE_DEFERRED_TILE_SIZE);
		OutputZOnly(pp, minZ);
	}

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

	float3 lightRslt = LightSampleWithZ(fragmentToProcess, currentPixelPosition, zvalue, invViewportWidthHeight).xyz;
	for (uint y = 0; y < 1 << tileSizeShift; y++)
	for (uint x = 0; x < 1 << tileSizeShift; x++)
	{
		//Output(currentPixelPosition + uint2(x, y), lightRslt);
		float3 lightRslt2;
		lightRslt2.x = GetOutputFor(lightRslt.x, GroupThreadId.xy, uint2(x, y), tileSizeShift);
		lightRslt2.y = GetOutputFor(lightRslt.y, GroupThreadId.xy, uint2(x, y), tileSizeShift);
		lightRslt2.z = GetOutputFor(lightRslt.z, GroupThreadId.xy, uint2(x, y), tileSizeShift);
		uint2 pp = GroupThreadId.xy + ((tilePosition + uint2(x, y))* PE_DEFERRED_TILE_SIZE);
		Output(pp, lightRslt2);
	}

#else // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)

	float3 lightRslt = CS_GenerateLightingTiled(tilePosition, pixelPosition, GroupIndex);
	Output(pixelPosition, lightRslt);

#endif // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)
}

float PS_DownSampleDepth(FullscreenVertexOut input) : FRAG_OUTPUT_DEPTH
{
	float d0 = DepthBufferMS.Load(int2(input.position.xy), 0).x;
	float d1 = DepthBufferMS.Load(int2(input.position.xy), 1).x;
	float d2 = DepthBufferMS.Load(int2(input.position.xy), 2).x;
	float d3 = DepthBufferMS.Load(int2(input.position.xy), 3).x;
	return min(min(d0, d1), min(d2, d3));
}

float PS_CopyDepth(FullscreenVertexOut input) : FRAG_OUTPUT_DEPTH
{
	return DepthBuffer.Load(int3(input.position.xy, 0)).x;
}

#ifndef __ORBIS__

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
  RenderTargetWriteMask[0] = 15;
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

BlendState NoColourBlend 
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 0;
};

DepthStencilState DepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

DepthStencilState TwoSidedStencilDepthState {
  DepthEnable = TRUE;
  DepthWriteMask = Zero;
  DepthFunc = Less;
  StencilEnable = TRUE; 

  FrontFaceStencilFail = Keep;
  FrontFaceStencilDepthFail = Incr;
  FrontFaceStencilPass = Keep;
  FrontFaceStencilFunc = Always;
  BackFaceStencilFail = Keep;
  BackFaceStencilDepthFail = Decr;
  BackFaceStencilPass = Keep;
  BackFaceStencilFunc = Always;
  StencilReadMask = 255;
  StencilWriteMask = 255;
};

DepthStencilState StencilTestDepthState 
{
  DepthEnable = FALSE;
  DepthWriteMask = Zero;
  DepthFunc = Less;
  StencilEnable = TRUE; 

  FrontFaceStencilFail = Keep;
  FrontFaceStencilDepthFail = Keep;
  FrontFaceStencilPass = Keep;
  FrontFaceStencilFunc = Less;
  BackFaceStencilFail = Keep;
  BackFaceStencilDepthFail = Keep;
  BackFaceStencilPass = Keep;
  BackFaceStencilFunc = Less;
  StencilReadMask = 255;
  StencilWriteMask = 0;
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
};

RasterizerState LightRasterState 
{
	CullMode = Back;
};

technique11 RenderPointLight
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass1
	{
		SetVertexShader( CompileShader( vs_4_0, RenderLightVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderPointLightFP() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( LightRasterState );		
	}
}

technique11 RenderSpotLight
<
string VpIgnoreContextSwitches[] = { "DEFERRED_SHADOWS" };
string IgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass1
	{
		SetVertexShader( CompileShader( vs_4_0, RenderLightVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderSpotLightFP() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( LightRasterState );		
	}
}

technique11 RenderDirectionalLight
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderDirectionalLightFP() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}


technique11 ShadowSpotLight
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass1
	{
		SetVertexShader( CompileShader( vs_4_0, RenderLightVP() ) );
		SetPixelShader( CompileShader( ps_4_0, ShadowSpotLightFP() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( LightRasterState );		
	}
}

technique11 ShadowDirectionalLight
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, ShadowDirectionalLightFP() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 CompositeToScreen
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "PHYRE_NEO" };
string FpIgnoreContextSwitches[] = { "DEFERRED_INVERT" };
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, FullscreenVPWithOptionalInvert()));
		SetPixelShader( CompileShader( ps_4_0, CompositeToScreenFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 CompositeToScreenTiled
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "PHYRE_NEO" };
string VpIgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT" };
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, FullscreenVP()));
		SetPixelShader( CompileShader( ps_4_1, CompositeToScreenTiledFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 CopyLitToScreen
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "PHYRE_NEO" };
string VpIgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT" };
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, FullscreenVP()));
		SetPixelShader(CompileShader(ps_4_1, CopyLitToScreenFP()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 CompositeToScreenAddTiled
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "PHYRE_NEO" };
string VpIgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT" };
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, FullscreenVP()));
		SetPixelShader(CompileShader(ps_4_1, CompositeToScreenAddTiledFP()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 GenerateLightScattering
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_EvaluateScatteringLights() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 GenerateLightScatteringInstantLights
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_EvaluateScatteringInstantLights() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 GenerateLightingTiled
<
string IgnoreContextSwitches[] = { "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateLightingToOutputBuffer()));
	}
}

technique11 GenerateAndCompositeLightingTiled
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateAndCompositeLightingTiled()));
	}
}

technique11 GenerateAndCompositeLightingTiledLQ
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateAndCompositeLightingTiledLQ()));
	}
}

technique11 GenerateAndCompositeLightingTiledLowLowQ
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateAndCompositeLightingTiledLowLowQ()));
	}
}

technique11 GenerateLightingInstantLightsTiled
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateLightingInstantLightsTiled()));
	}
}

technique11 RenderDeferredLightCount
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_RenderDeferredLightCount()));
	}
}

technique11 RenderDeferredLightOnly
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_RenderDeferredLightOnly()));
	}
}

technique11 RenderDeferredMaxFragmentsPerTile
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_RenderDeferredMaxFragmentsPerTile()));
	}
}

technique11 RenderDeferredTotalAdditionalFragments
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_RenderDeferredTotalAdditionalFragments()));
	}
}

technique11 RenderDeferredFMASKPassesSaved
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_RenderDeferredFMASKPassesSaved()));
	}
}

technique11 CopyCompositedOutputToScreen
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_CopyCompositedBufferToScreen() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

DepthStencilState DepthAlways {
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Always;
	StencilEnable = FALSE;
};

technique11 DownSampleDepth
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, FullscreenVP()));
		SetPixelShader(CompileShader(ps_4_1, PS_DownSampleDepth()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthAlways, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 CopyDepth
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_4_0, FullscreenVP()));
		SetPixelShader(CompileShader(ps_4_1, PS_CopyDepth()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthAlways, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__
