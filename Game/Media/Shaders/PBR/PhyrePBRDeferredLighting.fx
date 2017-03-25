/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"
#include "../PhyreShaderDefsD3D.h"
#include "../PhyrePixelFont.h" // For debug view

#ifndef __ORBIS__
	// Material switches - There are no material switches.
#endif //! __ORBIS__

#ifndef __ORBIS__
	// Context switches.
	bool PhyreContextSwitches 
	< 
		string ContextSwitchNames[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
	>;

	// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
	#define DEFINED_CONTEXT_SWITCHES 1
#endif //! __ORBIS__

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center)	// Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

#if defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)
#define PACK_LIGHT_INDICES  // Extra work to pack down to uint8s to reduce LDS usage
#endif // defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)

#ifdef PHYRE_D3DFX
#pragma warning (disable : 3557) // Disable loop only executes for 1 iteration(s), forcing loop to unroll - Occurs on some of the larger tiled operations
#endif // PHYRE_D3DFX

	//#define ALL_SAMPLES
//#define SAMPLE_MASK
#define SAMPLE_LIST

#include "../PhyreSceneWideParametersD3D.h"
#ifdef __ORBIS__
	#include "../PhyreHTile.h"
#endif //! __ORBIS__
#include "../PhyreDeferredLightingSharedFx.h"

// Instantiate dummy default lit lighting functions for new PBR light types.
#define InstantiateDummyLightingFns(LIGHT_TYPE) \
	float3 EvaluateLight(LIGHT_TYPE light,float3 worldPosition, float3 normal, float3 eyeDirection, float shadowAmount, float shininess, float specularPower) { return float3(shadowAmount,shadowAmount,shadowAmount); } \
	float3 EvaluateLight(LIGHT_TYPE light,float3 worldPosition, float3 normal, float shadowAmount) { return float3(shadowAmount,shadowAmount,shadowAmount); } \
	float EvaluateShadow(LIGHT_TYPE light, float dummy, float dummy2, float3 worldPosition, float viewDepth) { return 1; }

#ifdef EXTENDED_LIGHT_TYPES
InstantiateDummyLightingFns(AreaDiscLight)
InstantiateDummyLightingFns(AreaSphereLight)
InstantiateDummyLightingFns(AreaRectangleLight)
InstantiateDummyLightingFns(AreaTubeLight)
InstantiateDummyLightingFns(GlobalLightProbe)
InstantiateDummyLightingFns(LocalLightProbe)
InstantiateDummyLightingFns(RadianceVolume)
#endif // EXTENDED_LIGHT_TYPES

#include "../PhyreShaderCommonD3D.h"

#ifdef RECEIVE_SHADOWS
	#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) EvaluateShadow(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth)
#else //! RECEIVE_SHADOWS
	#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) 1.0f
#endif //! RECEIVE_SHADOWS

float4x4 World		: World;
float4x4 WorldView	: WorldView;
float4x4 WorldViewProjection		: WorldViewProjection;
float4x4 WorldViewProjectionPrev		: WorldViewProjectionPrev;
float4x4 WorldViewInverse;

sampler LightprobeSamplerSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler NormalMapSamplerSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Wrap;
	AddressV = Wrap;
};

// Shared Physically Based Rendering functionality.
#include "PhyrePBRShared.h"
#include "PhyrePBRSharedFx.h"

///////////////////////
// Vertex structures //
///////////////////////

// Description:
// The input vertex for a textured vertex.
struct PbrLightingTexVSInput
{
#ifdef __ORBIS__
	float4 Vertex	: POSITION;											// The full screen vertex.
#else //! __ORBIS__
	float3 Vertex	: POSITION;											// The full screen vertex.
#endif //! __ORBIS__
	float2 Uv		: TEXCOORD0;										// The full screen texture coordinate.
};

// Description:
// The output vertex for a textured vertex.
struct PbrLightingTexVSOutput
{
	float4 Position		: SV_POSITION;									// The transformed light hull vertex.
	float2 Uv			: TEXCOORD0;									// The full screen texture coordinate.
	float3 ScreenPos	: TEXCOORD3;									// The full screen position.
};

// Description:
// The input vertex for an untextured vertex.
struct PbrLightingVSInput
{
#ifdef __ORBIS__
	float4 Vertex		: POSITION;										// The full screen vertex.
#else //! __ORBIS__
	float3 Vertex		: POSITION;										// The full screen vertex.
#endif //! __ORBIS__
};

// Description:
// The output vertex for an untextured vertex.
struct PbrLightingVSOutput
{
	float4 Position		: SV_POSITION;									// The transformed light hull vertex.
};

////////////////
// Parameters //
////////////////

StructuredBuffer<uint> HTileData;

float2 InvProjXY;

int2 ViewportOrigin;													// The origin of the set viewport.

Texture2D<float> DepthBuffer;											// The depth buffer.
Texture2D<float4> ColorBuffer;											// Albedo.rgb, ao.
Texture2D<float4> NormalDepthBuffer;									// Normal.xyz, depth.
Texture2D<float4> SpecularRoughBuffer;									// Specular.xyz, linearRoughness.
Texture2D<float4> ShadowBuffer;											// The shadow buffer containing 4 shadow maps.

Texture2D<float4> LightDiffuseBuffer;									// The diffuse lighting buffer.
Texture2D<float4> LightSpecularBuffer;									// The specular lighting buffer.

Texture2D <float> ShadowTexture;										// The shadow depth buffer from the POV of the light.

//! The multisampled buffers
Texture2D<uint2> NormalDepthBufferMSFMASK;								// The multi-sampled FMask buffer.
Texture2DMS<float> DepthBufferMS;										// The multi-sampled depth buffer.
Texture2DMS<float4> NormalDepthBufferMS;								// The multi-sampled normal/depth buffer.
Texture2DMS<float4> ColorBufferMS;										// The multi-sampled color buffer.

// Constant buffers for the deferred lights.
cbuffer DeferredDirectionalLightConstantBuffer
{
	PDeferredDirectionalLight DeferredDirectionalLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredSpotLightConstantBuffer
{
	PDeferredLight DeferredSpotLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredPointLightConstantBuffer
{
	PDeferredLight DeferredPointLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredAreaRectangleLightConstantBuffer
{
	PDeferredPBRLight DeferredAreaRectangleLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredAreaSphereLightConstantBuffer
{
	PDeferredPBRLight DeferredAreaSphereLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredAreaDiscLightConstantBuffer
{
	PDeferredPBRLight DeferredAreaDiscLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}
cbuffer DeferredAreaTubeLightConstantBuffer
{
	PDeferredPBRLight DeferredAreaTubeLights[PE_MAX_NUM_DEFERRED_LIGHTS];
}

uint NumDeferredSpotLights;
uint NumDeferredPointLights;
uint NumDeferredDirectionalLights;
uint NumDeferredAreaRectangleLights;
uint NumDeferredAreaSphereLights;
uint NumDeferredAreaDiscLights;
uint NumDeferredAreaTubeLights;
uint NumDeferredLocalLightProbes;
uint NumDeferredGlobalLightProbes;
uint NumDeferredRadianceVolumes;

StructuredBuffer<uint> DeferredLightingTileIDs;							// The tile IDs to process for deferred lighting generation.

//! Fog parameters
float4 FogCoefficients;													// The fog coefficients describing the front and rear fog distances.
float4 FogColor;														// The fog color.

//! The lighting buffers
StructuredBuffer<uint2> LightingDiffuseOutputBuffer;
StructuredBuffer<uint2> LightingSpecularOutputBuffer;
RWStructuredBuffer<uint2> RWLightingDiffuseOutputBuffer;
RWStructuredBuffer<uint2> RWLightingSpecularOutputBuffer;

RWTexture2D<float4> CompositeTarget;									// The composited color/tiled lighting target.

#include "PhyrePBRDeferredLightingSharedFx.h"

////////////////
// MRT output //
////////////////

// Description:
// The MRT output from the PBR deferred lighting pixel shader.
struct PbrDeferredLightBuffersOutput
{
	float4 Diffuse : FRAG_OUTPUT_COLOR0;								// The diffuse lighting result.
	float4 Specular : FRAG_OUTPUT_COLOR1;								// The specular lighting result.
};

////////////////////
// Vertex shaders //
////////////////////

//! Textured

// Description:
// The full screen transform that passes the full screen vertex through.
// Arguments:
// IN - The input full screen vertex.
// Returns:
// The output full screen vertex.
PbrLightingTexVSOutput PbrFullscreenTexVS(PbrLightingTexVSInput IN)
{
	PbrLightingTexVSOutput OUT;

#ifdef __ORBIS__
	OUT.Position = float4(IN.Vertex.xy, 1, 1);
#else //! __ORBIS__
	OUT.Position = float4(IN.Vertex.x, -IN.Vertex.y, 1, 1);
#endif //! __ORBIS__
	OUT.Uv = IN.Uv;

	OUT.ScreenPos.z = -1.0;
	OUT.ScreenPos.xy = OUT.Uv * 2.0 - 1.0;
	OUT.ScreenPos.y = -OUT.ScreenPos.y;
	OUT.ScreenPos.xy *= InvProjXY;

	return OUT;
}

// Description:
// The full screen transform that passes the full screen vertex through. A context switch can be used to flip the texture coordinate.
// Arguments:
// IN - The input full screen vertex.
// Returns:
// The output full screen vertex.
PbrLightingTexVSOutput PbrFullscreenTexVSWithOptionalInvert(PbrLightingTexVSInput IN)
{
	PbrLightingTexVSOutput OUT = PbrFullscreenTexVS(IN);

#ifdef DEFERRED_INVERT
	OUT.Uv.y = 1.0f - IN.Uv.y;
#endif // DEFERRED_INVERT

	return OUT;
}

//! Untextured

// Description:
// The full screen transform that passes the full screen vertex through.
// Arguments:
// IN - The input full screen vertex.
// Returns:
// The output full screen vertex.
PbrLightingVSOutput PbrFullscreenVS(PbrLightingVSInput IN)
{
	PbrLightingVSOutput OUT;

#ifdef __ORBIS__
	OUT.Position = float4(IN.Vertex.xy, 1, 1);
#else //! __ORBIS__
	OUT.Position = float4(IN.Vertex.x, -IN.Vertex.y, 1, 1);
#endif //! __ORBIS__

	return OUT;
}

///////////////////
// Pixel shaders //
///////////////////

// Description:
// Mix the color and light values, apply fog to produce a final lit fragment.
// Arguments:
// albedo - The unlit color buffer value to light.
// lightRslt - The light result to mix.
// viewSpaceDepth - The view space depth at which to apply fog.
// Returns:
// The mixed color, light and fog value.
float4 MixLight(float4 albedo, PbrLightingResults lightRslt, float viewSpaceDepth)
{
	float3 color = (albedo.xyz * lightRslt.m_diffuse) + lightRslt.m_specular;

	// Calculate fog
	float fogDepth = saturate((viewSpaceDepth - FogCoefficients.x) * FogCoefficients.z);
	fogDepth = exp2(fogDepth) - 1.0f;
	float fogAmount = saturate(fogDepth * FogCoefficients.w);
	color = lerp(color, FogColor.xyz, fogAmount);

	return float4(color, albedo.w);
}

// Description:
// Combine the lighting buffers and color buffer to produce a lit render buffer.
// Arguments:
// IN - The vertex for the full screen pass.
// Returns:
// The combined color with lighting.
float4 CompositeToScreenPS(PbrLightingTexVSOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 colValue = ColorBuffer.SampleLevel(PointClampSampler, IN.Uv.xy, 0);

	float zvalue = DepthBuffer.SampleLevel(PointClampSampler, IN.Uv.xy, 0);
	if(IsValidDepth(zvalue))
	{
		float4 diffuseLightValue = LightDiffuseBuffer.SampleLevel(PointClampSampler, IN.Uv.xy, 0);
		float4 specularLightValue = LightSpecularBuffer.SampleLevel(PointClampSampler, IN.Uv.xy, 0);

		colValue = float4(diffuseLightValue.xyz * colValue.xyz + specularLightValue.xyz, colValue.w);
	}

	return colValue;
}

// Description:
// Combine the lighting buffers and color buffer to produce a lit render buffer for tiled rendering.
// Arguments:
// IN - The vertex for the full screen pass.
// Returns:
// The combined color with lighting.
float4 PbrCompositeToScreenTiledPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_COLOR
{	
	uint screenWidth, screenHeight, samples;
#ifdef DEFERRED_MULTISAMPLE
	ColorBufferMS.GetDimensions(screenWidth, screenHeight, samples);
#else // DEFERRED_MULTISAMPLE
	ColorBuffer.GetDimensions(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE

	// Adjust this for the target's viewport origin, so we can read the various sources with no viewport offset.
	int2 pixelPosition = int2(IN.Position.xy);
	pixelPosition.y -= ViewportOrigin.y;

#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT

	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;

	PbrLightingResults lightValue;
	ResetValid(lightValue);

	lightValue.m_diffuse = UnpackF16ToF32(LightingDiffuseOutputBuffer[pixelIndex]).xyz;
	lightValue.m_specular = UnpackF16ToF32(LightingSpecularOutputBuffer[pixelIndex]).xyz;

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
		colour = MixLight(colValue, lightValue, viewSpaceDepth);
	}
	
	return colour;
}

// Description:
// Copy the lit buffer to the screen.
// Arguments:
// IN - The vertex for the full screen pass.
// Returns:
// The combined color with lighting.
float4 PbrCopyLitToScreenPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_COLOR
{
	uint screenWidth, screenHeight, samples;
#ifdef DEFERRED_MULTISAMPLE
	ColorBufferMS.GetDimensions(screenWidth, screenHeight, samples);
#else // DEFERRED_MULTISAMPLE
	ColorBuffer.GetDimensions(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE

	int2 pixelPosition = int2(IN.Position.xy);
	pixelPosition.y -= ViewportOrigin.y;

#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT

	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;

	float4 lightDiffuseValue = UnpackF16ToF32(LightingDiffuseOutputBuffer[pixelIndex]);
	float4 lightSpecularValue = UnpackF16ToF32(LightingSpecularOutputBuffer[pixelIndex]);

	return lightDiffuseValue + lightSpecularValue;
}

// Description:
// Lerp between the color value and lighting value based on the lighting w component.
// Intended for debug only.
// Arguments:
// IN - The vertex for the full screen pass.
// Returns:
// The lerped color/lighting value.
float4 PbrCompositeToScreenAddTiledPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_COLOR
{
	uint screenWidth, screenHeight;
	ColorBuffer.GetDimensions(screenWidth, screenHeight);

	int2 pixelPosition = int2(IN.Position.xy);
	pixelPosition.y -= ViewportOrigin.y;

#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT

	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;
	float4 debugDiffuseValue = UnpackF16ToF32(LightingDiffuseOutputBuffer[pixelIndex]);
	float4 debugSpecularValue = UnpackF16ToF32(LightingSpecularOutputBuffer[pixelIndex]);
	float4 debugValue = float4(debugDiffuseValue.xyz + debugSpecularValue.xyz, max(debugDiffuseValue.w, debugSpecularValue.w));

#ifdef DEFERRED_MULTISAMPLE
	float4 colValue = ColorBufferMS.Load(pixelPosition, 0);
#else // DEFERRED_MULTISAMPLE
	float4 colValue = ColorBuffer.Load(int3(pixelPosition, 0));
#endif // DEFERRED_MULTISAMPLE

	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;
	float4 colour = colValue;
	if (IsValidDepth(zvalue))
		colour.xyz = lerp(colValue.xyz, debugValue.xyz, colValue.w);

	return colour;
}

// Description:
// Copy the tiled lighting value to the output buffer.
// Intended for debug only.
// Arguments:
// IN - The vertex for the full screen pass.
// Returns:
// The lerped color/lighting value.
float4 PbrCopyToScreenAddTiledPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_COLOR
{
	uint screenWidth, screenHeight;
	ColorBuffer.GetDimensions(screenWidth, screenHeight);

	int2 pixelPosition = int2(IN.Position.xy);
	pixelPosition.y -= ViewportOrigin.y;

#ifdef DEFERRED_INVERT
	pixelPosition.y = (screenHeight - 1) - pixelPosition.y;
#endif // DEFERRED_INVERT

	uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;
	float4 debugDiffuseValue = UnpackF16ToF32(LightingDiffuseOutputBuffer[pixelIndex]);
	float4 debugSpecularValue = UnpackF16ToF32(LightingSpecularOutputBuffer[pixelIndex]);
	float4 debugValue = float4(debugDiffuseValue.xyz + debugSpecularValue.xyz, max(debugDiffuseValue.w, debugSpecularValue.w));

	return debugValue;
}

// Description:
// Copy the final render buffer (sampled via the NormalDepthBuffer) to the back buffer.
// Arguments:
// IN - The vertex for the full screen pass.
// Returns:
// The copied color buffer pixel.
float4 CopyCompositedBufferToScreenPS(PbrLightingTexVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	return NormalDepthBuffer.SampleLevel(PointClampSampler, IN.Uv.xy, 0);	
}

// Description:
// Get the screen width and height using the depth buffer.
// Arguments:
// screenWidth - The screen width (returned).
// screenHeight - The screen height (returned).
void GetScreenWidthHeight(out uint screenWidth, out uint screenHeight)
{
#ifdef DEFERRED_MULTISAMPLE
	uint samples;
	DepthBufferMS.GetDimensionsFast(screenWidth, screenHeight, samples);
#else //  DEFERRED_MULTISAMPLE
	DepthBuffer.GetDimensionsFast(screenWidth, screenHeight);
#endif // DEFERRED_MULTISAMPLE
}

// Description:
// Get the depth buffer width.
// Returns:
// The depth buffer width.
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

// Description:
// Get the tile position for the specified tile index.
// Arguments:
// GroupId - The index of the tile to get.
// GroupThreadId - The index of the pixel within the tile.
// DispatchThreadId - The overall pixel position assuming linear arrangement of tiles.
// tilePosition - The position of the tile (returned).
// pixelPosition - The position of the pixel within the image (returned).
uint GetTilePosition(uint3 GroupId, uint3 GroupThreadId, uint3 DispatchThreadId, out uint2 tilePosition, out uint2 pixelPosition)
{
#ifdef DEFERRED_VR
	uint tile = DeferredLightingTileIDs[GroupId.x];
	uint tileSizeShift = (tile >> 24) & 0xFF;
	uint tileSize = PE_DEFERRED_TILE_SIZE << tileSizeShift;
	tilePosition = uint2(tile & 0x3FF, (tile >> 10) & 0x3FF);
	pixelPosition = tilePosition * tileSize + GroupThreadId.xy;
	tilePosition <<= tileSizeShift;
	return tileSizeShift;
#else // DEFERRED_VR
	tilePosition = GroupId.xy;
	pixelPosition = DispatchThreadId.xy;
	return 0;
#endif // DEFERRED_VR
}

// Description:
// Write lighting results to the output buffer.
// Arguments:
// pos - The pixel position to write.
// diffuse - The diffuse lighting value to write.
// specular - The specular lighting value to write.
void WriteToOutputBuffer(uint2 pos, float4 diffuse, float4 specular)
{
	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	if ((pos.x < screenWidth) && (pos.y < screenHeight))
	{
		uint pixelIndex = pos.y * screenWidth + pos.x;

		// pack to half and write
		RWLightingDiffuseOutputBuffer[pixelIndex] = PackF32ToF16(diffuse);
		RWLightingSpecularOutputBuffer[pixelIndex] = PackF32ToF16(specular);
	}
}

// Description:
// Write lighting results to the output buffer.
// Arguments:
// pos - The pixel position to write.
// diffuse - The diffuse lighting value to write.
// specular - The specular lighting value to write.
void WriteToOutputBuffer(uint2 pos, PbrLightingResults lightRslt)
{
	// Coverage is zero for analytical lights. Use alpha channel for IBL masking.
	WriteToOutputBuffer(pos, float4(lightRslt.m_diffuse, 0.0f), float4(lightRslt.m_specular, 0.0f));
}

groupshared uint TileMinMaxZ[2];
groupshared float ZSamples[64 * 4];

// Description:
// Get the Z range for the specified tile and pixel position.
// Arguments:
// range - The Z range returned.
// tilePosition - The position of the tile being processed.
// pixelPosition - The position of the pixel being processed.
// groupIndex - The index of the thread within the threadgroup.
void GetZRange(out ZRange range, uint2 tilePosition, uint2 pixelPosition, uint groupIndex)
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

	if (groupIndex == 0)
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
// Lights are stacked by type in the active lights list. High water marks are recorded for each light type.
// For each region the indices refer back to the input constant buffers for that light type.
// Global (full screen) lights are not entered into the culled list. Image basde lights (light probes, radiance volumes)
// are processed separately.

groupshared uint HWM_ActiveSpotLights;
groupshared uint HWM_ActivePointLights;
groupshared uint HWM_ActiveAreaRectangleLights;
groupshared uint HWM_ActiveAreaSphereLights;
groupshared uint HWM_ActiveAreaDiscLights;
groupshared uint HWM_ActiveAreaTubeLights;

// Description:
// Frustum cull the deferred lights in the constant buffers against the specified tile.
// Arguments:
// groupIndex - The index of the thread in the tile.
// tilePosition - The position of the tile.
// unprojtileMinMax - The post projection tile min/max depth.
void FrustumCullLights(uint groupIndex, uint2 tilePosition, float2 unprojtileMinMax)
{
	uint i;
	if (groupIndex == 0)
		NumLightsActive = 0;

	float2 tileMinMax;

#ifndef DEFERRED_VR
	tileMinMax.x = ConvertDepth(unprojtileMinMax.x);
	tileMinMax.y = ConvertDepth(unprojtileMinMax.y);
#else //! DEFERRED_VR
	// CLR - Calculate view space depth when using PlayStation(R)VR's Asymmetric projection matrices. Need to remap depth texture range to -1 to +1 using this method on PS4 hence the * 2.0f - 1.0f.
	tileMinMax.x = ConvertDepthFullProjection(unprojtileMinMax.x * 2.0f - 1.0f);
	tileMinMax.y = ConvertDepthFullProjection(unprojtileMinMax.y * 2.0f - 1.0f);
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

	float3 frustumVerts[8];
	GenerateFrustumVerts(frustumVerts, tilePosition, unprojtileMinMax, screenWidth, screenHeight);

	// Transform the frustum sphere, vertices and planes to world space.
	float4x4 invViewMtx = ViewInverse;
	for (i=0; i<6; i++)
	{
		float3 N = frustumPlanes[i].xyz;					// Plane normal.
		float3 P = N.xyz * frustumPlanes[i].w;				// Point on plane.

		P = mul(float4(P, 1), invViewMtx).xyz;				// Transform point.
		N = normalize(mul(float4(N,0), invViewMtx).xyz);	// Transform normal

		float newD = dot(P, N);

		frustumPlanes[i] = float4(N, newD);
	}
	for (i=0; i<8; i++)
	{
		float3 P = frustumVerts[i];							// Frustum vertex.

		P = mul(float4(P, 1), invViewMtx).xyz;				// Transform point.

		frustumVerts[i] = P;
	}

	float3 newSphereCenter = mul(float4(sphere.xyz, 1), invViewMtx).xyz;
	sphere = float4(newSphereCenter, sphere.w);

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive

	// Cull the spot lights.
	for (i = groupIndex; i < min(NumDeferredSpotLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		PDeferredLight l = DeferredSpotLights[i];

		[branch] if (!SphereIntersectsCone(sphere, l.m_position, -l.m_direction, l.m_spotAngles.y, l.m_tanConeAngle))
			continue;
		bool isLightVisible = true;//IsSpotLightVisible(l.m_position, -l.m_direction, l.m_ttenuation.y, l.m_coneBaseRadius, frustumPlanes);

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive
	if (groupIndex == 0)
		HWM_ActiveSpotLights = NumLightsActive;

	// Cull the point lights.
	for (i = groupIndex; i < min(NumDeferredPointLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		PDeferredLight l = DeferredPointLights[i];

		[branch] if (!SphereIntersectsSphere(sphere, l.m_position, l.m_attenuation.y))
			continue;
		bool isLightVisible = true;//IsPointLightVisible(l.m_position, l.m_attenuation.y, frustumPlanes);

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive
	if (groupIndex == 0)
		HWM_ActivePointLights = NumLightsActive;

	// Cull the area rectangle lights.
	for (i = groupIndex; i < min(NumDeferredAreaRectangleLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		PDeferredPBRLight l = DeferredAreaRectangleLights[i];

		// Cull against the light plane.
		bool isLightVisible = IsFrustumVisibleAgainstPlane(-l.m_direction, l.m_position, frustumVerts);

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive
	if (groupIndex == 0)
		HWM_ActiveAreaRectangleLights = NumLightsActive;

	// Cull the area sphere lights.
	for (i = groupIndex; i < min(NumDeferredAreaSphereLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		bool isLightVisible = true;					// Sphere lights are always visible for now.

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive
	if (groupIndex == 0)
		HWM_ActiveAreaSphereLights = NumLightsActive;

	// Cull the area disc lights.
	for (i = groupIndex; i < min(NumDeferredAreaDiscLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		PDeferredPBRLight l = DeferredAreaDiscLights[i];

		// Cull against the light plane.
		bool isLightVisible = IsFrustumVisibleAgainstPlane(-l.m_direction, l.m_position, frustumVerts);

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive
	if (groupIndex == 0)
		HWM_ActiveAreaDiscLights = NumLightsActive;

	// Cull the area tube lights.
	for (i = groupIndex; i < min(NumDeferredAreaTubeLights, PE_MAX_NUM_DEFERRED_LIGHTS); i += (PE_DEFERRED_TILE_SIZE*PE_DEFERRED_TILE_SIZE))
	{
		bool isLightVisible = true;					// Tube lights are always visible for now.

		[branch] if (isLightVisible)
			AddLight(i);
	}

	GroupMemoryBarrierWithGroupSync();	// Sync NumLightsActive
	if (groupIndex == 0)
		HWM_ActiveAreaTubeLights = NumLightsActive;
}

// Description:
// Light a single point.
// Arguments:
// pixelPosition - The position of the pixel to light.
// screenPos - The screen position of the pixel to light (-1 -> +1)
// viewSpaceDepth - The view space depth for the point to light.
// normal- The normal buffer value for the point to light.
// Returns:
// The lighting result for the pixel. 
PbrLightingResults LightPoint(uint2 pixelPosition, float2 screenPos, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	uint i;
	float4 shadowResults = ShadowBuffer.Load(int3(pixelPosition, 0));
	float3 V = normalize(EyePosition - geom.m_worldPosition);

	PbrLightingResults result;
	ResetValid(result);

	for (i = 0; i < NumDeferredDirectionalLights; ++i)
	{
		// Apply the directional light.
		PDeferredDirectionalLight light = DeferredDirectionalLights[i];

		float shad = CalculateShadow(light.m_shadowMask, shadowResults);

		// Populate the light with lighty parameters.
		DirectionalLight dl;
		dl.m_direction = light.m_direction;
		dl.m_colorIntensity = light.m_color.xyz;

		Accumulate(result, EvaluateLightPBR(dl, V, shad, mat, geom));
	}

	for (i = 0; i < HWM_ActiveSpotLights; ++i)
	{
		// Apply the spot light.
		uint lightIndex = GetLightIndex(i);
		PDeferredLight light = DeferredSpotLights[lightIndex];

		// Apply the light.
		float shad = CalculateShadow(light.m_shadowMask, shadowResults);

		// Populate the light with lighty parameters.
		SpotLight sl;
		sl.m_position = light.m_position;
		sl.m_direction = light.m_direction;
		sl.m_colorIntensity = light.m_color.xyz;
		sl.m_spotAngles = float4(0, 0, light.m_spotAngles.xy);				// cosf supplied, only use these from sl.m_spotAngles.zw.
		sl.m_attenuation = float4(light.m_attenuation.xy, 0, 0);			// only xy and y (inner and outer distance) used.

		Accumulate(result, EvaluateLightPBR(sl, V, shad, mat, geom));
	}

	for (i = HWM_ActiveSpotLights; i < HWM_ActivePointLights; ++i)
	{
		// Apply the point light.
		uint lightIndex = GetLightIndex(i);
		PDeferredLight light = DeferredPointLights[lightIndex];

		// Apply the light.
		float shad = 1.0f;

		// Populate the light with lighty parameters.
		PointLight pl;
		pl.m_position = light.m_position;
		pl.m_colorIntensity = light.m_color.xyz;
		pl.m_attenuation = float4(light.m_attenuation, 0, 0);				// only xy and y (inner and outer distance) used.

		Accumulate(result, EvaluateLightPBR(pl, V, shad, mat, geom));
	}

	for (i = HWM_ActivePointLights; i < HWM_ActiveAreaRectangleLights; ++i)
	{
		// Apply the area rectangle light.
		uint lightIndex = GetLightIndex(i);
		PDeferredPBRLight light = DeferredAreaRectangleLights[lightIndex];

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		AreaRectangleLight arl;
		arl.m_position = light.m_position;
		arl.m_direction = light.m_direction;
		arl.m_halfWidth = light.m_halfWidth;
		arl.m_halfHeight = light.m_halfHeight;
		arl.m_colorIntensity = light.m_color.xyz;
		arl.m_attenuation = float4(light.m_attenuation, 0, 0);

		Accumulate(result, EvaluateLightPBR(arl, V, shad, mat, geom));
	}

	for (i = HWM_ActiveAreaRectangleLights; i < HWM_ActiveAreaSphereLights; ++i)
	{
		// Apply the area sphere light.
		uint lightIndex = GetLightIndex(i);
		PDeferredPBRLight light = DeferredAreaSphereLights[lightIndex];

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		AreaSphereLight asl;
		asl.m_position = light.m_position;
		asl.m_radius = light.m_radius;
		asl.m_colorIntensity = light.m_color.xyz;
		asl.m_attenuation = float4(light.m_attenuation, 0, 0);

		Accumulate(result, EvaluateLightPBR(asl, V, shad, mat, geom));
	}

	for (i = HWM_ActiveAreaSphereLights; i < HWM_ActiveAreaDiscLights; ++i)
	{
		// Apply the area disc light.
		uint lightIndex = GetLightIndex(i);
		PDeferredPBRLight light = DeferredAreaDiscLights[lightIndex];

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		AreaDiscLight adl;
		adl.m_position = light.m_position;
		adl.m_direction = light.m_direction;
		adl.m_radius = light.m_radius;
		adl.m_colorIntensity = light.m_color.xyz;
		adl.m_attenuation = float4(light.m_attenuation, 0, 0);

		Accumulate(result, EvaluateLightPBR(adl, V, shad, mat, geom));
	}

	for (i = HWM_ActiveAreaDiscLights; i < HWM_ActiveAreaTubeLights; ++i)
	{
		// Apply the area tube light.
		uint lightIndex = GetLightIndex(i);
		PDeferredPBRLight light = DeferredAreaTubeLights[lightIndex];

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		AreaTubeLight atl;
		atl.m_position = light.m_position;
		atl.m_halfWidth = light.m_halfWidth;
		atl.m_radius = light.m_radius;
		atl.m_colorIntensity = light.m_color.xyz;
		atl.m_attenuation = float4(light.m_attenuation, 0, 0);

		Accumulate(result, EvaluateLightPBR(atl, V, shad, mat, geom));
	}

	return result;
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
	GetZRange(zRange, tilePosition, pixelPosition, GroupIndex);

	FrustumCullLights(GroupIndex, tilePosition, zRange.unprojtileMinMax);

	uint total = NumLightsActive;

	// Add in local light probes, global light probes and radiance volumes which are sepearate full screen light passes.
	total += NumDeferredLocalLightProbes;
	total += NumDeferredGlobalLightProbes;
	total += NumDeferredRadianceVolumes;

	float3 color = float3(0, 0, 1);
	if (total < 10)
		color = float3(0, 1, 0);
	else if (total < 20)
		color = float3(1, 1, 0);
	else if (total < 30)
		color = float3(1, 0, 0);
	float colorscale = GetPixelMaskForDigit(total % 10, GroupThreadId.xy);
	color *= colorscale;

	float4 result = float4(color, 0.15f + 0.85f * colorscale);
	WriteToOutputBuffer(DispatchThreadId.xy, result, result); // Prepare for backend lerp 0->0.15, 1 -> 1
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

	float4 result = float4(color, 0.5f);
	WriteToOutputBuffer(pixelPosition.xy, result, result);
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

	float4 result = float4(color, 0.5f);
	WriteToOutputBuffer(pixelPosition.xy, result, result);
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
	{
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
	{
		for (x = 0; x < 1 << tileSizeShift; x++)
		{
			uint2 currentPixelPosition = pixelPosition + uint2(x, y) * PE_DEFERRED_TILE_SIZE;
			float4 result = float4(color, 0.5f);
			WriteToOutputBuffer(currentPixelPosition, result, result);
		}
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
PbrLightingResults LightSampleWithZ(int sampleIndex, uint2 pixelPosition, float viewSpaceDepth, float2 invViewportWidthHeight)
{
	PbrLightingResults result;
	ResetValid(result);

	float2 uv = float2(pixelPosition)* invViewportWidthHeight;
	float2 screenPos = GetScreenPosition(uv);

	// Get the GBuffer information for lighting and light if a valid depth.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;
	if (InitializeWithDepth(mat, geom, pixelPosition, viewSpaceDepth))
		result = LightPoint(pixelPosition, screenPos, mat, geom);
	
	return result;
}

// Note: sampleIndex is really a fragment index on PS4.
PbrLightingResults LightSample(int sampleIndex, uint2 pixelPosition, uint groupIndex, float count, float2 invViewportWidthHeight)
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

// Description:
// Compute the lighting for a pixel in this tile by processing the deferred non image based lights.
// Arguments:
// tilePosition - The index of the tile.
// pixelPosition - The index of the pixel.
// groupIndex - The index of the thread in the thread group.
// Returns:
// The lighting result for the pixel. 
PbrLightingResults CS_GenerateLightingTiled(uint2 tilePosition, uint2 pixelPosition, uint groupIndex)
{
	ZRange zRange;
	GetZRange(zRange, tilePosition, pixelPosition, groupIndex);
	FrustumCullLights(groupIndex, tilePosition, zRange.unprojtileMinMax);

	PbrLightingResults result;
	ResetValid(result);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

#ifdef DEFERRED_MULTISAMPLE

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

	// Sample them all for non ORBIS.
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
		AccumulateScaled(result, LightSample(diff, spec, smpl, pixelPosition, groupIndex, count, invViewportWidthHeight), count);
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
			Accumulate(result, LightSample(diff, spec, smpl, pixelPosition, groupIndex, 1.0f, invViewportWidthHeight));
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

		AccumulateScaled(result, LightSample(smpl, pixelPosition, groupIndex, count, invViewportWidthHeight), count);
		sum += count;
	} while (sampleRequiredMask);
#endif //! SAMPLE_LIST

	// Normalize.
	if (sum > 0.0f)
		Scale(result, 1.0f/sum);

#else // DEFERRED_MULTISAMPLE

	float2 uv = float2(pixelPosition)* invViewportWidthHeight;
	float2 screenPos = GetScreenPosition(uv);

#ifdef __ORBIS__
	float zvalue = DepthBuffer.Load(int3(pixelPosition, 0)).x;
#else // __ORBIS__
	float zvalue = zRange.zvalue;
#endif // __ORBIS__

	// Get the GBuffer information for lighting and light if a valid depth.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;
	if (InitializeWithDepth(mat, geom, pixelPosition, zvalue))
	{
		Accumulate(result, LightPoint(pixelPosition, screenPos, mat, geom));
	}

#endif // DEFERRED_MULTISAMPLE

	return result;
}

// Description:
// Compute the low quality lighting for a pixel in this tile by processing the deferred non image based lights.
// Arguments:
// tilePosition - The index of the tile.
// pixelPosition - The index of the pixel.
// groupIndex - The index of the thread in the thread group.
// Returns:
// The lighting result for the pixel. 
PbrLightingResults CS_GenerateLightingTiledLQ(uint2 tilePosition, uint2 pixelPosition, uint groupIndex)
{
	ZRange zRange;
	GetZRange(zRange, tilePosition, pixelPosition, groupIndex);
	FrustumCullLights(groupIndex, tilePosition, zRange.unprojtileMinMax);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

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

	return LightSampleWithZ(fragmentToProcess, pixelPosition, zvalue, invViewportWidthHeight);
}

#ifdef __ORBIS__
	#ifdef PHYRE_ENTRYPOINT_CS_GenerateLightingToOutputBuffer
		#pragma argument(fastmath)
	#endif //! PHYRE_ENTRYPOINT_CS_GenerateLightingToOutputBuffer
#endif //! __ORBIS__

// Description:
// Compute the lighting for one tile to the output buffer.
// Arguments:
// GroupId - The thread group ID (tile ID).
// DispatchThreadId - The dispatch ID (pixel position).
// GroupIndex - The group Index (index of the pixel in a tile).
[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateLightingToOutputBuffer(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	PbrLightingResults lightRslt = CS_GenerateLightingTiled(GroupId.xy, DispatchThreadId.xy, GroupIndex);

	WriteToOutputBuffer(DispatchThreadId.xy, lightRslt);
}

// Description:
// Composite the specified lighting value with the color buffer and write to the composite target.
// Arguments:
// pixelPosition - The pixel position for which to composite the lighting.
// lightRslt - The lighting result to composite with the color buffer.
void Output(uint2 pixelPosition, PbrLightingResults lightRslt)
{
	uint2 outputPixelPosition = pixelPosition;

#ifdef DEFERRED_INVERT
	uint screenWidth, screenHeight;
	CompositeTarget.GetDimensionsFast(screenWidth, screenHeight);
	outputPixelPosition.y = (screenHeight - 1) - outputPixelPosition.y;
#endif // DEFERRED_INVERT

#ifdef DEFERRED_MULTISAMPLE

	// Multisample mixes color per sample as required
	CompositeTarget[outputPixelPosition] = float4(lightRslt.m_diffuse + lightRslt.m_specular, 1);					// TODO : Make more space to store separate diffuse and specular lighting.

#else // DEFERRED_MULTISAMPLE

	float zvalue = DepthBuffer[pixelPosition].x;
	float4 colValue = ColorBuffer[pixelPosition];
	if (IsValidDepth(zvalue))
	{
		float viewSpaceDepth = ConvertDepth(zvalue);
		colValue = MixLight(colValue, lightRslt, viewSpaceDepth);
	}

	CompositeTarget[outputPixelPosition] = colValue;
#endif // DEFERRED_MULTISAMPLE
}

#define MAX_TILE_SIZE 16
groupshared uint IntermediateDiffuseResults[MAX_TILE_SIZE * MAX_TILE_SIZE];
groupshared uint IntermediateSpecularResults[MAX_TILE_SIZE * MAX_TILE_SIZE];

// Description:
// Pack lighting values as 10:10:10 in a uint.
// Arguments:
// lightResult - The lighting result to pack.
// scale - The scale factor to use when packing the light value.
// Returns:
// The 10:10:10 packed lighting value.
uint PackLighting(float3 lightResult, float scale)
{
	lightResult = saturate(lightResult) * (1023.0f /4.0f) * scale;
	return uint(lightResult.x) | (uint(lightResult.y) << 10) | (uint(lightResult.z) << 20);
}

// Description:
// Get the average view space depth for the fragments at the specified pixel position.
// Arguments:
// currentPixelPosition - The pixel position for which to get the average view space depth.
// sampleMask - The bitmask specifying the samples for which to get the average depth.
// Returns:
// The average view space depth.
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

// Description:
// Process a fragment, accumulating the lighting results in the intermediate results buffer.
// Arguments:
// index - The index of the fragment to process.
// tileSize - The tile size to process.
// tilePixelOrigin - The origin of the tile. Fragment offset is added to this.
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

	PbrLightingResults lightRslt = LightSampleWithZ(smpl, currentPixelPosition, aveZ, invViewportWidthHeight);
	uint packedDiffuseResult = PackLighting(lightRslt.m_diffuse, count);
	uint packedSpecularResult = PackLighting(lightRslt.m_specular, count);
	InterlockedAdd(IntermediateDiffuseResults[x + mul24(y, tileSize)], packedDiffuseResult);
	InterlockedAdd(IntermediateSpecularResults[x + mul24(y, tileSize)], packedSpecularResult);
}

// Description:
// Calculate the tiled lighting and composite with the color buffer before writing to the output.
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
	{
		for (uint x = 0; x < 1 << tileSizeShift; x++)
		{
			uint2 currentTilePosition = tilePosition + uint2(x, y);
			uint ht = HTileData[HTileIndexForTile(currentTilePosition.x, currentTilePosition.y, depthBufferWidth)];
			float2 currentTileMinMax = HTileToMinMaxZ(ht);
			tileMinMax.x = min(tileMinMax.x, currentTileMinMax.x);
			tileMinMax.y = max(tileMinMax.y, currentTileMinMax.y);
			OutputHTile(currentTilePosition, ht);
		}
	}

	FrustumCullLights(GroupIndex, tilePosition, tileMinMax);

	uint tileSize = PE_DEFERRED_TILE_SIZE << tileSizeShift;
	for (uint y = 0; y < 8 << tileSizeShift; y += 8)
	{
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

			PbrLightingResults lightRslt = LightSampleWithZ(smpl, currentPixelPosition, aveZ, invViewportWidthHeight);
			uint packedDiffuseResult = PackLighting(lightRslt.m_diffuse, count);
			uint packedSpecularResult = PackLighting(lightRslt.m_specular, count);
			IntermediateDiffuseResults[pixelInTile.x + mul24(pixelInTile.y, tileSize)] = packedDiffuseResult;
			IntermediateSpecularResults[pixelInTile.x + mul24(pixelInTile.y, tileSize)] = packedSpecularResult;

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
	}

	// Less than 64 remaining
	if (GroupIndex < FragsToDo)
		ProcessFragment(GroupIndex, tileSize, tilePosition * PE_DEFERRED_TILE_SIZE, invViewportWidthHeight);

	for (uint y = 0; y < 8 << tileSizeShift; y += 8)
	{
		for (uint x = 0; x < 8 << tileSizeShift; x += 8)
		{
			uint2 pixelInTile = GroupThreadId.xy + uint2(x, y);
			uint packedDiffuseResult = IntermediateDiffuseResults[pixelInTile.x + mul24(pixelInTile.y, tileSize)];
			uint packedSpecularResult = IntermediateSpecularResults[pixelInTile.x + mul24(pixelInTile.y, tileSize)];
			PbrLightingResults lightRslt;
			ResetValid(lightRslt);
			lightRslt.m_diffuse = float3(packedDiffuseResult & 0x3FF, (packedDiffuseResult >> 10) & 0x3FF, (packedDiffuseResult >> 20) & 0x3FF) / 1023.0f;
			lightRslt.m_specular = float3(packedSpecularResult & 0x3FF, (packedSpecularResult >> 10) & 0x3FF, (packedSpecularResult >> 20) & 0x3FF) / 1023.0f;
			uint2 currentPixelPosition = pixelInTile + tilePosition * PE_DEFERRED_TILE_SIZE;
			Output(currentPixelPosition, lightRslt);
		}
	}
#else // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)

	PbrLightingResults lightRslt = CS_GenerateLightingTiled(tilePosition, pixelPosition, GroupIndex);
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

	PbrLightingResults lightRslt = CS_GenerateLightingTiledLQ(tilePosition, pixelPosition, GroupIndex);
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
	{
		for (uint x = 0; x < 1 << tileSizeShift; x++)
		{
			uint2 currentTilePosition = tilePosition + uint2(x, y);
			uint ht = HTileData[HTileIndexForTile(currentTilePosition.x, currentTilePosition.y, depthBufferWidth)];
			float2 currentTileMinMax = HTileToMinMaxZ(ht);
			tileMinMax.x = min(tileMinMax.x, currentTileMinMax.x);
			tileMinMax.y = max(tileMinMax.y, currentTileMinMax.y);
			OutputHTile(currentTilePosition, ht);
		}
	}

	FrustumCullLights(GroupIndex, tilePosition, tileMinMax);

	// Do every other pixel to reduce load
	uint2 currentPixelPosition = (GroupThreadId.xy << tileSizeShift) + (tilePosition * PE_DEFERRED_TILE_SIZE);

	int fmaskValue = NormalDepthBufferMSFMASK.Load(int3(currentPixelPosition, 0)).x;
	float minZ = DepthBufferMS.Load(int2(currentPixelPosition), 0).x;
	float zvalue = ConvertDepth(minZ);
	int fragmentToProcess = fmaskValue & 0xF;

	for (uint y = 0; y < 1 << tileSizeShift; y++)
	{
		for (uint x = 0; x < 1 << tileSizeShift; x++)
		{
			//OutputZOnly(currentPixelPosition + uint2(x, y), minZ);
			uint offset = x + y << tileSizeShift;
			float zToWrite = GetOutputFor(minZ, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			uint2 pp = GroupThreadId.xy + ((tilePosition + uint2(x,y))* PE_DEFERRED_TILE_SIZE);
			OutputZOnly(pp, minZ);
		}
	}

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	float2 invViewportWidthHeight = float2(1.0f/(float)screenWidth, 1.0f/(float)screenHeight);

	PbrLightingResults lightRslt = LightSampleWithZ(fragmentToProcess, currentPixelPosition, zvalue, invViewportWidthHeight);
	for (uint y = 0; y < 1 << tileSizeShift; y++)
	{
		for (uint x = 0; x < 1 << tileSizeShift; x++)
		{
			//Output(currentPixelPosition + uint2(x, y), lightRslt);
			PbrLightingResults lightRslt2;
			lightRslt2.m_diffuse.x = GetOutputFor(lightRslt.m_diffuse.x, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			lightRslt2.m_diffuse.y = GetOutputFor(lightRslt.m_diffuse.y, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			lightRslt2.m_diffuse.z = GetOutputFor(lightRslt.m_diffuse.z, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			lightRslt2.m_specular.x = GetOutputFor(lightRslt.m_specular.x, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			lightRslt2.m_specular.y = GetOutputFor(lightRslt.m_specular.y, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			lightRslt2.m_specular.z = GetOutputFor(lightRslt.m_specular.z, GroupThreadId.xy, uint2(x, y), tileSizeShift);
			uint2 pp = GroupThreadId.xy + ((tilePosition + uint2(x, y))* PE_DEFERRED_TILE_SIZE);
			Output(pp, lightRslt2);
		}
	}

#else // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)

	PbrLightingResults lightRslt = CS_GenerateLightingTiled(tilePosition, pixelPosition, GroupIndex);
	Output(pixelPosition, lightRslt);

#endif // defined(DEFERRED_VR) && defined(__ORBIS__) && defined(DEFERRED_MULTISAMPLE)
}

// Description:
// Downsample a multi-sample depth buffer.
// Arguments:
// IN - The vertex for the down sample pass.
// Returns:
// The downsampled depth.
float PbrDownSampleDepthPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_DEPTH
{
	float d0 = DepthBufferMS.Load(int2(IN.Position.xy), 0).x;
	float d1 = DepthBufferMS.Load(int2(IN.Position.xy), 1).x;
	float d2 = DepthBufferMS.Load(int2(IN.Position.xy), 2).x;
	float d3 = DepthBufferMS.Load(int2(IN.Position.xy), 3).x;

	return min(min(d0, d1), min(d2, d3));
}

// Description:
// Copy a single sample depth buffer.
// Arguments:
// IN - The vertex for the copy pass.
// Returns:
// The copied depth.
float PbrCopyDepthPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_DEPTH
{
	return DepthBuffer.Load(int3(IN.Position.xy, 0)).x;
}

////////////////
// Techniques //
////////////////

// Always write depth, used for depth downsampling.
DepthStencilState DepthAlways
{
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Always;
	StencilEnable = FALSE;
};

technique11 CompositeToScreen
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "PHYRE_NEO" };
	string FpIgnoreContextSwitches[] = { "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenTexVSWithOptionalInvert()));
		SetPixelShader( CompileShader( ps_4_0, CompositeToScreenPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

technique11 CompositeToScreenTiled
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "PHYRE_NEO" };
	string VpIgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenVS()));
		SetPixelShader( CompileShader( ps_4_1, PbrCompositeToScreenTiledPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

technique11 CopyLitToScreen
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "PHYRE_NEO" };
	string VpIgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenVS()));
		SetPixelShader(CompileShader(ps_4_1, PbrCopyLitToScreenPS()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(NoCullRasterState);
	}
}

technique11 CompositeToScreenAddTiled
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR", "PHYRE_NEO" };
	string VpIgnoreContextSwitches[] = { "DEFERRED_MULTISAMPLE", "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenVS()));
		SetPixelShader(CompileShader(ps_4_1, PbrCompositeToScreenAddTiledPS()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(NoCullRasterState);
	}
}

technique11 CopyToScreenAddTiled
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "PHYRE_NEO" };
	string VpIgnoreContextSwitches[] = { "DEFERRED_INVERT" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenVS()));
		SetPixelShader(CompileShader(ps_4_1, PbrCopyToScreenAddTiledPS()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthState, 0);
		SetRasterizerState(NoCullRasterState);
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
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrFullscreenTexVS() ) );
		SetPixelShader( CompileShader( ps_4_0, CopyCompositedBufferToScreenPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

technique11 DownSampleDepth
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenVS()));
		SetPixelShader(CompileShader(ps_4_1, PbrDownSampleDepthPS()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthAlways, 0);
		SetRasterizerState(NoCullRasterState);
	}
}

technique11 CopyDepth
<
string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_MULTISAMPLE", "DEFERRED_VR", "DEFERRED_INVERT", "PHYRE_NEO" };
>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_0, PbrFullscreenVS()));
		SetPixelShader(CompileShader(ps_4_1, PbrCopyDepthPS()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(DepthAlways, 0);
		SetRasterizerState(NoCullRasterState);
	}
}
