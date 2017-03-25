/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"
#include "../PhyreShaderDefsD3D.h"

#ifndef __ORBIS__
	// Material switches - There are no material switches.
#endif //! __ORBIS__

#ifndef __ORBIS__
	// Context switches.
	bool PhyreContextSwitches 
	< 
		string ContextSwitchNames[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>;

	// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
	#define DEFINED_CONTEXT_SWITCHES 1
#endif //! __ORBIS__

#if defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)
#define PACK_LIGHT_INDICES  // Extra work to pack down to uint8s to reduce LDS usage
#endif // defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)

#ifdef __ORBIS__
#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

#include "../PhyreSceneWideParametersD3D.h"
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
	float2 Uv			: TEXCOORD0;									// The full screen texture coordinate.
};

// Description:
// The output vertex for a textured vertex.
struct PbrLightingTexVSOutput
{
	float4 Position		: SV_POSITION;										// The transformed light hull vertex.
	float2 Uv			: TEXCOORD0;									// The full screen texture coordinate.
	float3 ScreenPos	: TEXCOORD3;									// The full screen position.
};

// Description:
// The input vertex for an untextured vertex.
struct PbrLightingVSInput
{
#ifdef __ORBIS__
	float4 Vertex		: POSITION;											// The full screen vertex.
#else //! __ORBIS__
	float3 Vertex		: POSITION;											// The full screen vertex.
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

float2 InvProjXY;

Texture2D<float> DepthBuffer;											// The depth buffer.
Texture2D<float4> ColorBuffer;											// Albedo.rgb, ao.
Texture2D<float4> NormalDepthBuffer;									// Normal.xyz, depth.
Texture2D<float4> SpecularRoughBuffer;									// Specular.xyz, linearRoughness.
Texture2D<float4> ShadowBuffer;											// The shadow buffer containing 4 shadow maps.

//! The multisampled buffers
Texture2DMS<float> DepthBufferMS;										// The multi-sampled depth buffer.

//! Light parameters
float4x4 DeferredWorldTransform;										// The light's world transform.
float3 DeferredPos;														// The light's position.
float3 DeferredDir;														// The light's direction.
float4 DeferredColor;													// The light's color.
float3 DeferredHalfWidth;												// The light's half width.
float3 DeferredHalfHeight;												// The light's half height.
float3 DeferredHalfDepth;												// The light's half depth.
float DeferredRadius;													// The light's radius.
float4 DeferredSpotAngles;												// The light's spot angles.
float4 DeferredAttenParams;												// The light's attenuation parameters.
float4 DeferredShadowMask;												// The light's shadow mask.
uint DeferredLog2ProbeRes;												// The light's log2 probe resolution.
TextureCube<float4> DeferredSpecIbl;									// The light's image based specular cubemap.
TextureCube<float4> DeferredDiffIbl;									// The light's image based diffuse cubemap,
StructuredBuffer<SHOrder2Float4> DeferredDiffBuf;						// The light's spherical harmonics buffer.
StructuredBuffer<uint> DeferredLightingTileIDs;							// The tile IDs to process for deferred lighting generation.

//! The lighting buffers
RWStructuredBuffer<uint2> RWLightingDiffuseOutputBuffer;
RWStructuredBuffer<uint2> RWLightingSpecularOutputBuffer;

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
// Transform the general light shape into the specific light position for the light instance, as described by the light matrix supplied.
// Arguments:
// IN - The general light shape vertex.
// Returns:
// The specific light instance's position.
PbrLightingTexVSOutput PbrRenderLightTexVS(PbrLightingTexVSInput IN)
{
	PbrLightingTexVSOutput OUT;

	float4 worldPosition = mul(float4(IN.Vertex.xyz, 1), DeferredWorldTransform);
	OUT.Position = mul(float4(worldPosition.xyz,1), ViewProjection);

	OUT.Uv = IN.Uv;

	OUT.ScreenPos.z = -1.0;
	OUT.ScreenPos.xy = OUT.Uv * 2.0 - 1.0;
	OUT.ScreenPos.y = -OUT.ScreenPos.y;
	OUT.ScreenPos.xy *= InvProjXY;

	return OUT;
}

//! Untextured

// Description:
// Transform the general light shape into the specific light position for the light instance, as described by the light matrix supplied.
// Arguments:
// IN - The general light shape vertex.
// Returns:
// The specific light instance's position.
PbrLightingVSOutput PbrRenderLightVS(PbrLightingVSInput IN)
{
	PbrLightingVSOutput OUT;

	float4 worldPosition = mul(float4(IN.Vertex.xyz, 1), DeferredWorldTransform);
	OUT.Position = mul(float4(worldPosition.xyz,1), ViewProjection);

	return OUT;
}

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
// Render the PBR lighting results from a directional light.
// Arguments:
// IN - The input fragment to be lit.
// Returns:
// The lighting results (diffuse and specular) from the light.
PbrDeferredLightBuffersOutput PbrRenderDirectionalLightPS(PbrLightingVSOutput IN)
{
	// Capture the material state and geometry state from the G buffers.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;

	PbrDeferredLightBuffersOutput OUT;
	if (Initialize(mat, geom, IN.Position.xy))
	{
		float3 V = normalize(EyePosition - geom.m_worldPosition);

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		DirectionalLight light;
		light.m_direction = DeferredDir;
		light.m_colorIntensity = DeferredColor.xyz;

		PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

		// Accumulate the light in the lighting buffers.
		OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
		OUT.Specular = float4(lightResult.m_specular, 0.0f);
	}
	else
	{
		OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
		OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
	}

	return OUT;
}

// Description:
// Render the PBR lighting results from a point light.
// Arguments:
// IN - The input fragment to be lit.
// Returns:
// The lighting results (diffuse and specular) from the light.
PbrDeferredLightBuffersOutput PbrRenderPointLightPS(PbrLightingVSOutput IN)
{
	// Capture the material state and geometry state from the G buffers.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;

	PbrDeferredLightBuffersOutput OUT;
	if (Initialize(mat, geom, IN.Position.xy))
	{
		float3 V = normalize(EyePosition - geom.m_worldPosition);

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		PointLight light;
		light.m_position = DeferredPos;
		light.m_colorIntensity = DeferredColor.xyz;
		light.m_attenuation = DeferredAttenParams;

		PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

		// Accumulate the light in the lighting buffers.
		OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
		OUT.Specular = float4(lightResult.m_specular, 0.0f);
	}
	else
	{
		OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
		OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
	}

	return OUT;
}

// Description:
// Render the PBR lighting results from a spot light.
// Arguments:
// IN - The input fragment to be lit.
// Returns:
// The lighting results (diffuse and specular) from the light.
PbrDeferredLightBuffersOutput PbrRenderSpotLightPS(PbrLightingVSOutput IN)
{
	// Capture the material state and geometry state from the G buffers.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;

	PbrDeferredLightBuffersOutput OUT;
	if (Initialize(mat, geom, IN.Position.xy))
	{
		float3 V = normalize(EyePosition - geom.m_worldPosition);

		// Apply the light.
		float shad = CalculateShadow(DeferredShadowMask, ShadowBuffer.Load(int3(IN.Position.xy, 0)));

		// Populate the light with lighty parameters.
		SpotLight light;
		light.m_position = DeferredPos;
		light.m_direction = DeferredDir;
		light.m_colorIntensity = DeferredColor.xyz;
		light.m_spotAngles = DeferredSpotAngles;
		light.m_attenuation = DeferredAttenParams;

		PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

		// Accumulate the light in the lighting buffers.
		OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
		OUT.Specular = float4(lightResult.m_specular, 0.0f);
	}
	else
	{
		OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
		OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
	}

	return OUT;
}

#ifdef EXTENDED_LIGHT_TYPES

	// Description:
	// Render the PBR lighting results from an area disc light.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderAreaDiscLightPS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			AreaDiscLight light;
			light.m_position = DeferredPos;
			light.m_direction = DeferredDir;
			light.m_radius = DeferredRadius;
			light.m_colorIntensity = DeferredColor.xyz;
			light.m_attenuation = DeferredAttenParams;

			PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

			// Accumulate the light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
			OUT.Specular = float4(lightResult.m_specular, 0.0f);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
			OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		return OUT;
	}

	// Description:
	// Render the PBR lighting results from an area sphere light.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderAreaSphereLightPS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			AreaSphereLight light;
			light.m_position = DeferredPos;
			light.m_radius = DeferredRadius;
			light.m_colorIntensity = DeferredColor.xyz;
			light.m_attenuation = DeferredAttenParams;

			PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

			// Accumulate the light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
			OUT.Specular = float4(lightResult.m_specular, 0.0f);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
			OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		return OUT;
	}

	// Description:
	// Render the PBR lighting results from an area rectangle light.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderAreaRectangleLightPS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			AreaRectangleLight light;
			light.m_position = DeferredPos;
			light.m_direction = DeferredDir;
			light.m_halfWidth = DeferredHalfWidth;
			light.m_halfHeight = DeferredHalfHeight;
			light.m_colorIntensity = DeferredColor.xyz;
			light.m_attenuation = DeferredAttenParams;

			PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

			// Accumulate the light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
			OUT.Specular = float4(lightResult.m_specular, 0.0f);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
			OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		return OUT;
	}

	// Description:
	// Render the PBR lighting results from an area tube light.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderAreaTubeLightPS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			AreaTubeLight light;
			light.m_position = DeferredPos;
			light.m_halfWidth = DeferredHalfWidth;
			light.m_radius = DeferredRadius;
			light.m_colorIntensity = DeferredColor.xyz;
			light.m_attenuation = DeferredAttenParams;

			PbrLightingResults lightResult = EvaluateLightPBR(light, V, shad, mat, geom);

			// Accumulate the light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse, 0.0f);
			OUT.Specular = float4(lightResult.m_specular, 0.0f);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
			OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		return OUT;
	}

	// Description:
	// Render the PBR lighting results from a local light probe.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderLocalLightProbePS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			LocalLightProbe light;
			light.m_position = DeferredPos;
			light.m_radius = DeferredRadius;
			light.m_halfWidth = DeferredHalfWidth;
			light.m_halfHeight = DeferredHalfHeight;
			light.m_halfDepth = DeferredHalfDepth;
			TextureCube<float4> specIbl = DeferredSpecIbl;
			TextureCube<float4> diffIbl = DeferredDiffIbl;
			EmptyStruct diffBuf;

			PbrLightingResults lightResult = EvaluateLightPBR(light, specIbl, diffIbl, diffBuf, V, shad, mat, geom);

			// Accumulate the light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse, lightResult.m_diffuseValidity);
			OUT.Specular = float4(lightResult.m_specular, lightResult.m_specularValidity);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
			OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		return OUT;
	}

	// Description:
	// Render the PBR lighting results from a global light probe.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderGlobalLightProbePS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			GlobalLightProbe light;
			TextureCube<float4> specIbl = DeferredSpecIbl;
			TextureCube<float4> diffIbl = DeferredDiffIbl;
			EmptyStruct diffBuf;

			PbrLightingResults lightResult = EvaluateLightPBR(light, specIbl, diffIbl, diffBuf, V, shad, mat, geom);

			// Accumulate the light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse, 1.0f);
			OUT.Specular = float4(lightResult.m_specular, 1.0f);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
			OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		return OUT;
	}

	// Description:
	// Render the PBR lighting results from a radiance volume.
	// Arguments:
	// IN - The input fragment to be lit.
	// Returns:
	// The lighting results (diffuse and specular) from the light.
	PbrDeferredLightBuffersOutput PbrRenderRadianceVolumePS(PbrLightingVSOutput IN)
	{
		// Capture the material state and geometry state from the G buffers.
		PbrMaterialProperties mat;
		PbrGeomProperties geom;

		PbrDeferredLightBuffersOutput OUT;
		if (Initialize(mat, geom, IN.Position.xy))
		{

			float3 V = normalize(EyePosition - geom.m_worldPosition);

			// Apply the light.
			float shad = 1.0f;					// Calculate unshadowed results for now.

			// Populate the light with lighty parameters.
			RadianceVolume light;
			light.m_position = DeferredPos;
			light.m_halfWidth = DeferredHalfWidth;
			light.m_halfHeight = DeferredHalfHeight;
			light.m_halfDepth = DeferredHalfDepth;
			light.m_log2ProbeRes = DeferredLog2ProbeRes;
			EmptyStruct specIbl;
			EmptyStruct diffIbl;
			StructuredBuffer<SHOrder2Float4> diffBuf = DeferredDiffBuf;

			PbrLightingResults lightResult = EvaluateLightPBR(light, specIbl, diffIbl, diffBuf, V, shad, mat, geom);

			// Accumulate the diffuse light in the lighting buffers.
			OUT.Diffuse = float4(lightResult.m_diffuse * lightResult.m_diffuseValidity, 0.0f);
		}
		else
		{
			OUT.Diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
		}

		OUT.Specular = float4(0.0f, 0.0f, 0.0f, 0.0f);

		return OUT;
	}

#endif //! EXTENDED_LIGHT_TYPES

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
// Compute the lighting for a pixel in this tile by processing the local light probe.
// Arguments:
// tilePosition - The index of the tile.
// pixelPosition - The index of the pixel.
// groupIndex - The index of the thread in the thread group.
// Returns:
// The lighting result for the pixel. 
PbrLightingResults CS_GenerateLocalLightProbeLightingTiled(uint2 tilePosition, uint2 pixelPosition, uint groupIndex)
{
	PbrLightingResults result;
	ResetInvalid(result);

	// Capture the material state and geometry state from the G buffers.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;

	PbrDeferredLightBuffersOutput OUT;
	if (Initialize(mat, geom, pixelPosition))
	{
		float3 V = normalize(EyePosition - geom.m_worldPosition);

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		LocalLightProbe light;
		light.m_position = DeferredPos;
		light.m_radius = DeferredRadius;
		light.m_halfWidth = DeferredHalfWidth;
		light.m_halfHeight = DeferredHalfHeight;
		light.m_halfDepth = DeferredHalfDepth;
		TextureCube<float4> specIbl = DeferredSpecIbl;
		TextureCube<float4> diffIbl = DeferredDiffIbl;
		EmptyStruct diffBuf;

		result = EvaluateLightPBR(light, specIbl, diffIbl, diffBuf, V, shad, mat, geom);
	}

	return result;
}

// Description:
// Compute the lighting for a pixel in this tile by processing the global light probe.
// Arguments:
// tilePosition - The index of the tile.
// pixelPosition - The index of the pixel.
// groupIndex - The index of the thread in the thread group.
// Returns:
// The lighting result for the pixel. 
PbrLightingResults CS_GenerateGlobalLightProbeLightingTiled(uint2 tilePosition, uint2 pixelPosition, uint groupIndex)
{
	PbrLightingResults result;
	ResetInvalid(result);

	// Capture the material state and geometry state from the G buffers.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;

	PbrDeferredLightBuffersOutput OUT;
	if (Initialize(mat, geom, pixelPosition))
	{
		float3 V = normalize(EyePosition - geom.m_worldPosition);

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		GlobalLightProbe light;
		TextureCube<float4> specIbl = DeferredSpecIbl;
		TextureCube<float4> diffIbl = DeferredDiffIbl;
		EmptyStruct diffBuf;

		result = EvaluateLightPBR(light, specIbl, diffIbl, diffBuf, V, shad, mat, geom);
	}

	return result;
}

// Description:
// Compute the lighting for a pixel in this tile by processing the radiance volume.
// Arguments:
// tilePosition - The index of the tile.
// pixelPosition - The index of the pixel.
// groupIndex - The index of the thread in the thread group.
// Returns:
// The lighting result for the pixel. 
PbrLightingResults CS_GenerateRadianceVolumeLightingTiled(uint2 tilePosition, uint2 pixelPosition, uint groupIndex)
{
	PbrLightingResults result;
	ResetInvalid(result);

	// Capture the material state and geometry state from the G buffers.
	PbrMaterialProperties mat;
	PbrGeomProperties geom;

	PbrDeferredLightBuffersOutput OUT;
	if (Initialize(mat, geom, pixelPosition))
	{
		float3 V = normalize(EyePosition - geom.m_worldPosition);

		// Apply the light.
		float shad = 1.0f;					// Calculate unshadowed results for now.

		// Populate the light with lighty parameters.
		RadianceVolume light;
		light.m_position = DeferredPos;
		light.m_halfWidth = DeferredHalfWidth;
		light.m_halfHeight = DeferredHalfHeight;
		light.m_halfDepth = DeferredHalfDepth;
		light.m_log2ProbeRes = DeferredLog2ProbeRes;
		EmptyStruct specIbl;
		EmptyStruct diffIbl;
		StructuredBuffer<SHOrder2Float4> diffBuf = DeferredDiffBuf;

		result = EvaluateLightPBR(light, specIbl, diffIbl, diffBuf, V, shad, mat, geom);
	}

	return result;
}

// Description:
// Compute the lighting for one local light probe over one tile to the output buffer.
// Arguments:
// GroupId - The thread group ID (tile ID).
// DispatchThreadId - The dispatch ID (pixel position).
// GroupIndex - The group Index (index of the pixel in a tile).
[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateLocalLightProbeLightingToOutputBuffer(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	if ((pixelPosition.x < screenWidth) && (pixelPosition.y < screenHeight))
	{
		uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;

		PbrLightingResults lightRslt = CS_GenerateLocalLightProbeLightingTiled(tilePosition, pixelPosition, GroupIndex);

		// Read and unpack existing lighting info.
		float4 diffuse = UnpackF16ToF32(RWLightingDiffuseOutputBuffer[pixelIndex]);
		float4 specular = UnpackF16ToF32(RWLightingSpecularOutputBuffer[pixelIndex]);

		// Merge in new lighting info.
		float newDiffuseValid = min(1.0f - diffuse.w, lightRslt.m_diffuseValidity);
		float newSpecularValid = min(1.0f - specular.w, lightRslt.m_specularValidity);
		diffuse += float4((lightRslt.m_diffuse * newDiffuseValid), newDiffuseValid);
		specular += float4((lightRslt.m_specular * newSpecularValid), newSpecularValid);

		// pack to half and write
		RWLightingDiffuseOutputBuffer[pixelIndex] = PackF32ToF16(diffuse);
		RWLightingSpecularOutputBuffer[pixelIndex] = PackF32ToF16(specular);
	}
}

// Description:
// Compute the lighting for one global light probe over one tile to the output buffer.
// Arguments:
// GroupId - The thread group ID (tile ID).
// DispatchThreadId - The dispatch ID (pixel position).
// GroupIndex - The group Index (index of the pixel in a tile).
[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateGlobalLightProbeLightingToOutputBuffer(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	if ((pixelPosition.x < screenWidth) && (pixelPosition.y < screenHeight))
	{
		uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;

		PbrLightingResults lightRslt = CS_GenerateGlobalLightProbeLightingTiled(tilePosition, pixelPosition, GroupIndex);

		// Read and unpack existing lighting info.
		float4 diffuse = UnpackF16ToF32(RWLightingDiffuseOutputBuffer[pixelIndex]);
		float4 specular = UnpackF16ToF32(RWLightingSpecularOutputBuffer[pixelIndex]);

		// Merge in new lighting info.
		float newDiffuseValid = 1.0f - diffuse.w;
		float newSpecularValid = 1.0f - specular.w;
		diffuse += float4((lightRslt.m_diffuse * newDiffuseValid), newDiffuseValid);
		specular += float4((lightRslt.m_specular * newSpecularValid), newSpecularValid);

		// pack to half and write
		RWLightingDiffuseOutputBuffer[pixelIndex] = PackF32ToF16(diffuse);
		RWLightingSpecularOutputBuffer[pixelIndex] = PackF32ToF16(specular);
	}
}

// Description:
// Compute the lighting for one radiance volume over one tile to the output buffer.
// Arguments:
// GroupId - The thread group ID (tile ID).
// DispatchThreadId - The dispatch ID (pixel position).
// GroupIndex - The group Index (index of the pixel in a tile).
[numthreads(PE_DEFERRED_TILE_SIZE, PE_DEFERRED_TILE_SIZE, 1)]
void CS_GenerateRadianceVolumeLightingToOutputBuffer(uint3 GroupId : SV_GroupID,
	uint3 DispatchThreadId : SV_DispatchThreadID,
	uint3 GroupThreadId : SV_GroupThreadID,
	uint GroupIndex : SV_GroupIndex)
{
	uint2 tilePosition, pixelPosition;
	GetTilePosition(GroupId, GroupThreadId, DispatchThreadId, tilePosition, pixelPosition);

	uint screenWidth, screenHeight;
	GetScreenWidthHeight(screenWidth, screenHeight);
	if ((pixelPosition.x < screenWidth) && (pixelPosition.y < screenHeight))
	{
		uint pixelIndex = pixelPosition.y * screenWidth + pixelPosition.x;

		PbrLightingResults lightRslt = CS_GenerateRadianceVolumeLightingTiled(tilePosition, pixelPosition, GroupIndex);

		// Read and unpack existing lighting info.
		float4 diffuse = UnpackF16ToF32(RWLightingDiffuseOutputBuffer[pixelIndex]);
		float4 specular = UnpackF16ToF32(RWLightingSpecularOutputBuffer[pixelIndex]);

		// Merge in new lighting info.
		diffuse += float4(lightRslt.m_diffuse, 0.0f);
		specular += float4(lightRslt.m_specular, 0.0f);

		// pack to half and write
		RWLightingDiffuseOutputBuffer[pixelIndex] = PackF32ToF16(diffuse);
		RWLightingSpecularOutputBuffer[pixelIndex] = PackF32ToF16(specular);
	}
}

////////////////
// Techniques //
////////////////

// Local light probes use dest alpha to reduce contributions. As long as probes are rendered from near to far then near probes will occlude far ones.
BlendState LocalLightProbeBlend
{
	BlendEnable[0] = TRUE;
	BlendEnable[1] = TRUE;

	SrcBlend[0] = INV_DEST_ALPHA;
	DestBlend[0] = ONE;
	BlendOp[0] = ADD;
	SrcBlend[1] = INV_DEST_ALPHA;
	DestBlend[1] = ONE;
	BlendOp[1] = ADD;

	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	SrcBlendAlpha[1] = ONE;
	DestBlendAlpha[1] = ONE;
	BlendOpAlpha[1] = ADD;

	RenderTargetWriteMask[0] = 15;
	RenderTargetWriteMask[1] = 15;
};

// Local light probes use dest alpha to reduce contributions.
BlendState GlobalLightProbeBlend
{
	BlendEnable[0] = TRUE;
	BlendEnable[1] = TRUE;

	SrcBlend[0] = INV_DEST_ALPHA;
	DestBlend[0] = ONE;
	BlendOp[0] = ADD;
	SrcBlend[1] = INV_DEST_ALPHA;
	DestBlend[1] = ONE;
	BlendOp[1] = ADD;

	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	SrcBlendAlpha[1] = ONE;
	DestBlendAlpha[1] = ONE;
	BlendOpAlpha[1] = ADD;

	RenderTargetWriteMask[0] = 15;
	RenderTargetWriteMask[1] = 15;
};

// Non light probes are additive but don't write alpha.
BlendState NonLightProbeBlend
{
	BlendEnable[0] = TRUE;
	BlendEnable[1] = TRUE;

	SrcBlend[0] = ONE;
	DestBlend[0] = ONE;
	BlendOp[0] = ADD;
	SrcBlend[1] = ONE;
	DestBlend[1] = ONE;
	BlendOp[1] = ADD;

	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	SrcBlendAlpha[1] = ONE;
	DestBlendAlpha[1] = ONE;
	BlendOpAlpha[1] = ADD;

	RenderTargetWriteMask[0] = 7;			// Don't write alpha.
	RenderTargetWriteMask[1] = 7;			// Don't write alpha.
};

technique11 RenderDirectionalLight
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrRenderDirectionalLightPS() ) );

		SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

technique11 RenderPointLight
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrRenderLightVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrRenderPointLightPS() ) );
	
		SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

technique11 RenderSpotLight
<
	string IgnoreContextSwitches[] = { "DEFERRED_VR" };
	string VpIgnoreContextSwitches[] = { "DEFERRED_SHADOWS" };
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrRenderLightVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrRenderSpotLightPS() ) );
		
		SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

#ifdef EXTENDED_LIGHT_TYPES

	technique11 RenderAreaDiscLight
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderAreaDiscLightPS() ) );
		
			SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}

	technique11 RenderAreaSphereLight
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderAreaSphereLightPS() ) );
		
			SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}

	technique11 RenderAreaRectangleLight
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderAreaRectangleLightPS() ) );
		
			SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}

	technique11 RenderAreaTubeLight
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderAreaTubeLightPS() ) );
		
			SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}

	technique11 RenderLocalLightProbe
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderLocalLightProbePS() ) );
		
			SetBlendState( LocalLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}

	technique11 RenderGlobalLightProbe
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderGlobalLightProbePS() ) );
		
			SetBlendState( GlobalLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}

	technique11 RenderRadianceVolume
	<
		string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS", "DEFERRED_VR" };
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrRenderRadianceVolumePS() ) );
		
			SetBlendState( NonLightProbeBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( NoDepthState, 0);
			SetRasterizerState( NoCullRasterState );
		}
	}
#endif //! EXTENDED_LIGHT_TYPES

technique11 RenderLocalLightProbeTiled
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateLocalLightProbeLightingToOutputBuffer()));
	}
}

technique11 RenderGlobalLightProbeTiled
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateGlobalLightProbeLightingToOutputBuffer()));
	}
}

technique11 RenderRadianceVolumeTiled
<
	string IgnoreContextSwitches[] = { "DEFERRED_SHADOWS" };
>
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateRadianceVolumeLightingToOutputBuffer()));
	}
}
