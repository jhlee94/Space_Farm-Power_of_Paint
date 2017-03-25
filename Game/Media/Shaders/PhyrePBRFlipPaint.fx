/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreShaderDefsD3D.h"

#ifndef __ORBIS__

	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Material switches. 
	//

	// Material switch definitions. These are the material switches this shader exposes.
	bool PhyreMaterialSwitches 
	< 
		string MaterialSwitchNames[] = {			"TEXTURE_ROUGHNESS",			"TEXTURE_METALLICITY",			"TEXTURE_SPECULAR_COLOR",			"TEXTURE_CAVITY",
													"LIGHTING_ENABLED",				"ALPHA_ENABLED",				"NORMAL_MAPPING_ENABLED",			"CASTS_SHADOWS",
													"RECEIVE_SHADOWS",				"DOUBLE_SIDED",					"LIGHTMAP_OCCLUSION"}; 
		string MaterialSwitchUiNames[] = {			"Texture roughness",			"Texture Metalicity",			"Texture Specular Color",			"Texture Cavity",
													"Lighting",						"Transparency",					"Normal Mapping",					"Casts Shadows",
													"Receive Shadows",				"Render Double Sided",			"Lightmap Occlusion"}; 
		string MaterialSwitchDefaultValues[] = {	"",								"",								"",									"",
													"",								"",								"",									"",
													"1",							"",								""};
	>;
#endif //! __ORBIS__

// The maximum number of lights this shader supports.
#define MAX_NUM_LIGHTS 3

#ifndef __ORBIS__
	// Context switches
	bool PhyreContextSwitches 
	< 
	    string ContextSwitchNames[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
		string SupportedLightTypes[] = {"DirectionalLight", "PointLight", "SpotLight"
	#ifdef EXTENDED_LIGHT_TYPES
		, "AreaDiscLight", "AreaSphereLight", "AreaRectangleLight", "AreaTubeLight", "GlobalLightProbe", "LocalLightProbe", "RadianceVolume"
	#endif // EXTENDED_LIGHT_TYPES
		}; 
		string SupportedShadowTypes[] = {"PCFShadowMap", "CascadedShadowMap", "CombinedCascadedShadowMap"};
		int NumSupportedShaderLODLevels = 1;
		int MaxNumLights = MAX_NUM_LIGHTS;
		int MaxNumLights_GlobalLightProbe = 1;
	>;
	// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
	#define DEFINED_CONTEXT_SWITCHES 1
#endif //! __ORBIS__

#include "PhyreSceneWideParametersD3D.h"

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

#include "PhyreShaderCommonD3D.h"

#ifdef NUM_LIGHTS
	#if defined(LIGHTING_ENABLED) && NUM_LIGHTS > 0
		#define USE_LIGHTING
	#endif //! defined(LIGHTING_ENABLED) && NUM_LIGHTS > 0
#endif //! NUM_LIGHTS

#ifdef RECEIVE_SHADOWS
	#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) EvaluateShadow(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth)
#else //! RECEIVE_SHADOWS
	#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) 1.0f
#endif //! RECEIVE_SHADOWS

float4x4 World		: World;		
float4x4 WorldView	: WorldView;		
float4x4 WorldViewProjection		: WorldViewProjection;	
float4x4 WorldViewProjectionPrev		: WorldViewProjectionPrev;

#ifdef SKINNING_ENABLED

	#if 0
		// This is the standard non constant buffer implementation.
		#define NUM_SKIN_TRANSFORMS 80 // Note: This number is mirrored in Core as PD_MATERIAL_SKINNING_MAX_GPU_BONE_COUNT
		float4x4 BoneTransforms[NUM_SKIN_TRANSFORMS] : BONETRANSFORMS;
	#else
		// This is the structured buffer implementation that uses the structured buffer from PhyreCoreShaderShared.h
		#define BoneTransforms BoneTransformConstantBuffer
        #define BoneTransformsPrev PrevBoneTransformConstantBuffer
	#endif

#endif //! SKINNING_ENABLED

sampler TextureSamplerSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Wrap;
	AddressV = Wrap;
};

sampler LightprobeSamplerSampler
{
	Filter = Min_Mag_Mip_Linear;
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
#include "PBR/PhyrePBRShared.h"
#include "PBR/PhyrePBRSharedFx.h"

#ifdef ALPHA_ENABLED
	float AlphaThreshold : ALPHATHRESHOLD <float UIMin = 0.0; float UIMax = 1.0; string UIName = "Alpha Threshold"; string UILabel = "The alpha threshold.";> = 0.0;		// The alpha threshold.
#endif //! ALPHA_ENABLED

#ifdef NORMAL_MAPPING_ENABLED
	Texture2D <float4> NormalMapSampler;
	#define USE_TANGENTS
#endif //! NORMAL_MAPPING_ENABLED

#ifdef LIGHTMAP_OCCLUSION
	Texture2D <float4> LightmapSampler;
#endif //! LIGHTMAP_OCCLUSION

//////////////////////////////////////////
// Engine-supplied lighting parameters. //
//////////////////////////////////////////

#include "PBR/PhyrePBRLightsFx.h"

/////////////////////////////
// PBR Material parameters //
/////////////////////////////

#ifdef TEXTURE_ROUGHNESS
	Texture2D <float4> MaterialLinearRoughnessSampler;								// Texture based roughness
#else //! TEXTURE_ROUGHNESS
	float MaterialLinearRoughness < float UIMin = 0; float UIMax = 1.0; > = 0.8f;	// Material constant roughness.
#endif //! TEXTURE_ROUGHNESS

float MaterialViewDependentRoughnessStrength < float UIMin = 0; float UIMax = 1.0; > = 0.6f;	// Material constant roughness.

#ifdef TEXTURE_METALLICITY
	Texture2D <float4> MaterialMetallicitySampler;									// Texture based metallicity.
#else //! TEXTURE_METALLICITY
	float MaterialMetallicity < float UIMin = 0; float UIMax = 1.0; > = 0.0f;		// Material constant metallicity.
#endif //! TEXTURE_METALLICITY

#ifdef TEXTURE_CAVITY
	Texture2D <float4> MaterialCavitySampler;										// Texture based cavity.
#endif //! TEXTURE_CAVITY

#ifdef TEXTURE_SPECULAR_COLOR
	Texture2D <float4> MaterialSpecularColorSampler;								// Texture based conductor specular color.
#else //! TEXTURE_SPECULAR_COLOR
	float3 MaterialSpecularColor = float3(1.00, 0.71, 0.29);						// Material constant conductor specular color.
#endif //! TEXTURE_SPECULAR_COLOR

	Texture2D <float4> TextureSampler;												// Texture based albedo.

// Description:
// Initialize the material properties from texture based or material constant parameters as specified by material switches.
// Arguments:
// self - The material properties to initialize.
// uv - The texture coordinate with which to sample texture based material parameters.
// NdotV - The cosine of the angle between the surface normal and the view vector.
static void Initialize(out PbrMaterialProperties self, float2 uv, float NdotV)
{
#ifdef TEXTURE_ROUGHNESS
	self.m_linearRoughness = MaterialLinearRoughnessSampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_ROUGHNESS
	self.m_linearRoughness = MaterialLinearRoughness;
#endif //! TEXTURE_ROUGHNESS
	self.m_linearRoughness = max(self.m_linearRoughness, 0.01f);			// Avoid issues with mirror surfaces.

	self.m_viewDependentRoughnessStrength = MaterialViewDependentRoughnessStrength;

#ifdef TEXTURE_METALLICITY
	self.m_metallicity = MaterialMetallicitySampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_METALLICITY
	self.m_metallicity = MaterialMetallicity;
#endif //! TEXTURE_METALLICITY

#ifdef TEXTURE_CAVITY
	self.m_cavity = L1MaterialCavitySampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_CAVITY
	self.m_cavity = 1.0f;
#endif //! TEXTURE_CAVITY

	if (IsMetal(self.m_metallicity))
	{
#ifdef TEXTURE_SPECULAR_COLOR
		self.m_specularColor = MaterialSpecularColorSampler.Sample(TextureSamplerSampler, uv).xyz;
#else //! TEXTURE_SPECULAR_COLOR
		self.m_specularColor = MaterialSpecularColor;
#endif //! TEXTURE_SPECULAR_COLOR
	}
	else
	{
		self.m_specularColor = DIELECTRIC_SPECULAR;
	}

	self.m_albedo = TextureSampler.Sample(TextureSamplerSampler, float2(NdotV, NdotV));
}

///////////////////////
// Vertex structures //
///////////////////////

// Description:
// Input vertex for PBR vertex shader.
struct PbrVSInput
{
#ifdef USE_TANGENTS
	VNTIn	v;
#else //! USE_TANGENTS
	VNIn	v;
#endif //! USE_TANGENTS

	float2	Uv						: TEXCOORD0;
#ifdef LIGHTMAP_OCCLUSION
	float2	Uv1						: TEXCOORD2;				// Lightmapping.
#endif //! LIGHTMAP_OCCLUSION

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED
};

// Description:
// Output vertex for PBR vertex shader (and input to pixel shader).
struct PbrVSOutput
{
#ifdef USE_TANGENTS
	VNTOut	v;
#else //! USE_TANGENTS
	VNOut	v;
#endif //! USE_TANGENTS
	
	float2	Uv						: TEXCOORD0;
#ifdef LIGHTMAP_OCCLUSION
	float2	Uv1						: TEXCOORD4;				// Lightmapping.
#endif //! LIGHTMAP_OCCLUSION

#ifdef VELOCITY_ENABLED
	VelocityBufferVertexInfo VelocityData;
#endif //! VELOCITY_ENABLED
};

// Description:
// Input vertex for the shadow casting vertex shader.
struct ShadowVSInput
{
	VIn		v;
	float2	Uv						: TEXCOORD0;

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED
};

// Description:
// Output vertex for the shadow casting vertex shader (and input to pixel shader).
struct ShadowVSOutput
{
	VOut	v;
	float2	Uv						: TEXCOORD0;
};

////////////////////
// Shader helpers //
////////////////////

// Description:
// Apply the instancing transform to the specified vertex. This does nothing if instancing is not enabled.
// Arguments:
// IN - The vertex to which to apply the instancing transform.
void ApplyInstanceTransform(inout PbrVSInput IN)
{
#ifdef INSTANCING_ENABLED
	#ifdef SKINNING_ENABLED
		ApplyInstanceTransformVertex(IN.instancingInput, IN.v.SkinnableVertex.xyz);
		ApplyInstanceTransformNormal(IN.instancingInput, IN.v.SkinnableNormal.xyz);
		#ifdef USE_TANGENTS
			ApplyInstanceTransformNormal(IN.instancingInput, IN.v.SkinnableTangent.xyz);
		#endif //! USE_TANGENTS
	#else //! SKINNING_ENABLED
		ApplyInstanceTransformVertex(IN.instancingInput, IN.v.Position.xyz);
		ApplyInstanceTransformNormal(IN.instancingInput, IN.v.Normal.xyz);
		#ifdef USE_TANGENTS
			ApplyInstanceTransformNormal(IN.instancingInput, IN.v.Tangent.xyz);
		#endif //! USE_TANGENTS
	#endif //! SKINNING_ENABLED
#endif //! INSTANCING_ENABLED
}

// Description:
// Apply the instancing transform to the specified vertex. This does nothing if instancing is not enabled.
// Arguments:
// IN - The vertex to which to apply the instancing transform.
void ApplyInstanceTransform(inout ShadowVSInput IN)
{
#ifdef INSTANCING_ENABLED
	#ifdef SKINNING_ENABLED
		ApplyInstanceTransformVertex(IN.instancingInput, IN.v.SkinnableVertex.xyz);
	#else //! SKINNING_ENABLED
		ApplyInstanceTransformVertex(IN.instancingInput, IN.v.Position.xyz);
	#endif //! SKINNING_ENABLED
#endif //! INSTANCING_ENABLED
}

////////////////////
// Vertex shaders //
////////////////////

// Description:
// The vertex shader for all physically based forward rendered geometry.
// Arguments:
// IN - The input vertex.
// Returns:
// The transformed output vertex.
PbrVSOutput PbrForwardVS(PbrVSInput IN)
{
	PbrVSOutput OUT;

#ifdef VELOCITY_ENABLED
	PbrVSInput IN2 = IN;
#endif //! VELOCITY_ENABLED

	// Transform position.
#ifdef SKINNING_ENABLED
	EvalSkin(IN.v);
#endif //! SKINNING_ENABLED	
	ApplyInstanceTransform(IN);
	MoveToOutputVert(OUT.v, IN.v);

	OUT.Uv = CopyUV(IN.Uv);
#ifdef LIGHTMAP_OCCLUSION
	OUT.Uv1 = CopyUV(IN.Uv1);
#endif //! LIGHTMAP_OCCLUSION

#ifdef VELOCITY_ENABLED
	OUT.VelocityData = SetVelocityBufferOutputsVS(IN2.v, OUT.v.Position);
#endif //! VELOCITY_ENABLED

	return OUT;
}

// Description:
// The vertex shader for all physically based deferred rendered geometry.
// Arguments:
// IN - The input vertex.
// Returns:
// The transformed output vertex.
PbrVSOutput PbrDeferredVS(PbrVSInput IN)
{
	PbrVSOutput OUT = PbrForwardVS(IN);

	// Transform the normal into correct space for GBuffer.
	OUT.v.Normal = normalize(Normal_WorldSpaceToGBufferSpace(OUT.v.Normal.xyz));
#ifdef USE_TANGENTS
	OUT.v.Tangent = normalize(Normal_WorldSpaceToGBufferSpace(OUT.v.Tangent.xyz));
#endif //! USE_TANGENTS

	return OUT;
}

// Description:
// The vertex shader for shadow casting.
// Arguments:
// IN - The input vertex.
// Returns:
// The transformed output vertex.
ShadowVSOutput ShadowVS(ShadowVSInput IN)
{
	ShadowVSOutput OUT;

#ifdef SKINNING_ENABLED
	EvalSkin(IN.v);
#endif //! SKINNING_ENABLED
	ApplyInstanceTransform(IN);
	MoveToOutputVert(OUT.v, IN.v);

	OUT.Uv = CopyUV(IN.Uv);

	return OUT;
}

///////////////////
// Pixel shaders //
///////////////////

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
PS_OUTPUT PbrForwardPS(PbrVSOutput IN)
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

#ifdef ALPHA_ENABLED
	float alpha = mat.m_albedo.w;
#else //! ALPHA_ENABLED
	float alpha = 1.0f;
#endif //! ALPHA_ENABLED

#ifdef USE_LIGHTING
	// Perform lighting
	PbrLightingResults lightResult = EvaluateLightingPBR(mat, geom);

	float3 fragment = mat.m_albedo.xyz * alpha * lightResult.m_diffuse + lightResult.m_specular;
#else //! USE_LIGHTING
	float3 fragment = mat.m_albedo.xyz * alpha;
#endif //! USE_LIGHTING

#ifdef LIGHTMAP_OCCLUSION
	fragment *= LightmapSampler.Sample(LightprobeSamplerSampler, IN.Uv1).x;				// Apply occlusion lightmap.
#endif //! LIGHTMAP_OCCLUSION

	// Premultiply alpha into diffuse and add specular. Then blend is set up to be Src + Dst*(1-Alpha).
// Final result is	Diffuse * Alpha		+ Framebuffer * 1-Alpha		+ Specular.
//					Scattered			+ Transmitted				+ Reflected.

	PS_OUTPUT Out;
	Out.Colour = float4(fragment, alpha);

#ifdef VELOCITY_ENABLED
	Out.Velocity = CalculateVelocity(IN.VelocityData);
#endif //! VELOCITY_ENABLED
	return Out;
}

// Description:
// Deferred pixel shader for gathering the material parameters for a surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The MRT output for the captured output.
PbrDeferredPSOutput PbrDeferredPS(PbrVSOutput IN)
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	float ao = 1.0f;
#ifdef LIGHTMAP_OCCLUSION
	ao = LightmapSampler.Sample(LightprobeSamplerSampler, IN.Uv1).x;				// Apply occlusion lightmap.
#endif //! LIGHTMAP_OCCLUSION

	float2 octPackedNormal = packFloat3ToOct(normalize(geom.m_surfaceNormal.xyz));
	PbrDeferredPSOutput OUT;
	OUT.Color = float4(mat.m_albedo.xyz, ao);
	OUT.Normal_Depth = float4(bx2Pack(octPackedNormal), mat.m_viewDependentRoughnessStrength, geom.m_viewDepth);
	OUT.Specular_Rough = float4(mat.m_specularColor.xyz, mat.m_linearRoughness);

#ifdef VELOCITY_ENABLED
	OUT.Velocity = CalculateVelocity(IN.VelocityData);
#endif //! VELOCITY_ENABLED

	return OUT;
}

// Description:
// Pixel shader for shadow casting.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
void ShadowTexturedFP(ShadowVSOutput IN)
{
#ifdef ALPHA_ENABLED
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	float alpha = mat.m_albedo.w;
	clip(alpha - AlphaThreshold);
#endif //! ALPHA_ENABLED
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardRoughnessPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	return float4(mat.m_linearRoughness, mat.m_linearRoughness, mat.m_linearRoughness, 1.0f);
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardAlbedoPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	return float4(mat.m_albedo.xyz, 1.0f);
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardSpecularColorPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	return float4(mat.m_specularColor, 1.0f);
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardMetallicityPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	if (IsMetal(mat.m_metallicity))
		return float4(1.0f, 1.0f, 1.0f, 1.0f);
	else
		return float4(0.0f, 0.0f, 0.0f, 1.0f);
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardDiffuseLightingPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	float3 fragment = float3(1.0, 1.0f, 1.0f);
#ifdef USE_LIGHTING
	// Perform lighting
	PbrLightingResults lightResult = EvaluateLightingPBR(mat, geom);

	fragment = lightResult.m_diffuse;
#endif //! USE_LIGHTING

#ifdef LIGHTMAP_OCCLUSION
	fragment *= LightmapSampler.Sample(LightprobeSamplerSampler, IN.Uv1).x;				// Apply occlusion lightmap.
#endif //! LIGHTMAP_OCCLUSION

	return float4(fragment, 1.0f);
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardSpecularLightingPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

	float3 fragment = float3(0.0f, 0.0f, 0.0f);
#ifdef USE_LIGHTING
	// Perform lighting
	PbrLightingResults lightResult = EvaluateLightingPBR(mat, geom);

	fragment = lightResult.m_specular;
#endif //! USE_LIGHTING

#ifdef LIGHTMAP_OCCLUSION
	fragment *= LightmapSampler.Sample(LightprobeSamplerSampler, IN.Uv1).x;				// Apply occlusion lightmap.
#endif //! LIGHTMAP_OCCLUSION

	return float4(fragment, 1.0f);
}

// Description:
// Pixel shader for shading a point on the surface.
// Arguments:
// IN - The input fragment to be shaded.
// Returns:
// The shaded fragment color.
float4 PbrForwardOpacityPS(PbrVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	float3 N = normalize(geom.m_surfaceNormal);
	float3 V = normalize(EyePosition - geom.m_worldPosition);
	float NdotV = abs(dot(N, V));

	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties mat;
	Initialize(mat, IN.Uv, NdotV);

#ifdef ALPHA_ENABLED
	float alpha = mat.m_albedo.w;
#else //! ALPHA_ENABLED
	float alpha = 1.0f;
#endif //! ALPHA_ENABLED

	return float4(alpha, alpha, alpha, 1.0f);
}

////////////////
// Techniques //
////////////////

#ifdef LIGHTING_ENABLED
	#define IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING /* Nothing */
#else //! LIGHTING_ENABLED
	// If we're not using lighting then the shader is not dependent on the light count.
	#define IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "NUM_LIGHTS",
#endif //! LIGHTING_ENABLED

#ifndef ALPHA_ENABLED
	technique11 ForwardRender
	<
		string PhyreRenderPass = "Opaque";
		string VpIgnoreContextSwitches[] = {"NUM_LIGHTS", "LOD_BLEND"};
		string FpIgnoreContextSwitches[] = {IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "LOD_BLEND", "INSTANCING_ENABLED"};
	>
	{
		pass pass0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrForwardPS() ) );
	
			SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( DepthState, 0);
			SetRasterizerState( DefaultRasterState );
		}
	}

	technique11 DeferredRender
	<
		string PhyreRenderPass = "DeferredRender";
		string VpIgnoreContextSwitches[] = {"NUM_LIGHTS", "LOD_BLEND"};
		string FpIgnoreContextSwitches[] = {"NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED"};
	>
	{
		pass p0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrDeferredVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrDeferredPS() ) );
		
			SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( DepthState, 0);
			SetRasterizerState( DefaultRasterState );
		}
	}

#endif //! ALPHA_ENABLED

#ifdef ALPHA_ENABLED
	technique11 ForwardRenderAlpha
	<
		string PhyreRenderPass = "Transparent";
		string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
	    string FpIgnoreContextSwitches[] = { IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
	>
	{
		pass pass0
		{
			SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
			SetPixelShader( CompileShader( ps_4_0, PbrForwardPS() ) );
	
			SetBlendState( One_InvSrcAlpha_Blend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
			SetDepthStencilState( DepthState, 0);
			SetRasterizerState( DefaultRasterState );
		}
	}
#endif //! ALPHA_ENABLED

#ifdef CASTS_SHADOWS
	#ifdef ALPHA_ENABLED
		technique11 ShadowTransparent
		<
			string PhyreRenderPass = "ShadowTransparent";
			string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
		    string FpIgnoreContextSwitches[] = { IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
		>
		{
			pass p0
			{
				SetVertexShader( CompileShader( vs_4_0, ShadowVS() ) );
				SetPixelShader( CompileShader( ps_4_0, ShadowTexturedFP() ) );
	
				SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
				SetDepthStencilState( DepthState, 0);
				SetRasterizerState( DefaultRasterState );		
			}
		}
	#else //! ALPHA_ENABLED
		technique11 Shadow
		<
			string PhyreRenderPass = "Shadow";
			string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
		    string FpIgnoreContextSwitches[] = { IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
		>
		{
			pass p0
			{
				SetVertexShader( CompileShader( vs_4_0, ShadowVS() ) );
				//We're not writing color, so bind no pixel shader here.
	
				SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
				SetDepthStencilState( DepthState, 0);
				SetRasterizerState( DefaultRasterState );
			}
		}
	#endif //! ALPHA_ENABLED
#endif //! CASTS_SHADOWS

//////////////////////
// Debug techniques //
//////////////////////

technique11 RenderRoughness
<
	string PhyreRenderPass = "RenderRoughness";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardRoughnessPS() ) );

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderAlbedo
<
	string PhyreRenderPass = "RenderAlbedo";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardAlbedoPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderSpecularColor
<
	string PhyreRenderPass = "RenderSpecularColor";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardSpecularColorPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderMetallicity
<
	string PhyreRenderPass = "RenderMetallicity";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardMetallicityPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderDiffuseLighting
<
	string PhyreRenderPass = "RenderDiffuseLighting";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardDiffuseLightingPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderSpecularLighting
<
	string PhyreRenderPass = "RenderSpecularLighting";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardSpecularLightingPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 RenderOpacity
<
	string PhyreRenderPass = "RenderOpacity";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "VELOCITY_ENABLED" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrForwardVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrForwardOpacityPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}
