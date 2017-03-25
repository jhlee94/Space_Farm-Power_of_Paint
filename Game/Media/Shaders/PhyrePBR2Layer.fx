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
													"LIGHTING_ENABLED",				"TEXTURE_ENABLED",				"ALPHA_ENABLED",					"NORMAL_MAPPING_ENABLED",
													"CASTS_SHADOWS",				"RECEIVE_SHADOWS",				"DOUBLE_SIDED",						"TEXTURE_LAYER_BLEND",
													"LAYER2_UVS",					"LIGHTMAP_OCCLUSION"};
		string MaterialSwitchUiNames[] = {			"Texture Roughness",			"Texture Metalicity",			"Texture Specular Color",			"Texture Cavity",
													"Lighting",						"Texture",						"Transparency",						"Normal Mapping",
													"Casts Shadows",				"Receive Shadows",				"Render Double Sided",				"Texture Layer Blend",
													"Layer 2 has own UVs",			"Lightmap Occlusion"};
		string MaterialSwitchDefaultValues[] = {	"",								"",								"",									"",
													"",								"",								"",									"",
													"",								"1",							"",									"",
													"",								""};
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

#include "PBR/PhyrePBRLightsFX.h"

////////////////////////////////////////////
// PBR Material parameters (layers 1 & 2) //
////////////////////////////////////////////

#ifdef TEXTURE_ROUGHNESS
	Texture2D <float4> L1MaterialLinearRoughnessSampler;								// Texture based roughness
	Texture2D <float4> L2MaterialLinearRoughnessSampler;								// Texture based roughness
#else //! TEXTURE_ROUGHNESS
	float L1MaterialLinearRoughness < float UIMin = 0; float UIMax = 1.0; > = 0.8f;		// Material constant roughness.
	float L2MaterialLinearRoughness < float UIMin = 0; float UIMax = 1.0; > = 0.8f;	// Material constant roughness.
#endif //! TEXTURE_ROUGHNESS

float L1MaterialViewDependentRoughnessStrength < float UIMin = 0; float UIMax = 1.0; > = 0.6f;	// Material constant roughness.
float L2MaterialViewDependentRoughnessStrength < float UIMin = 0; float UIMax = 1.0; > = 0.6f;	// Material constant roughness.

#ifdef TEXTURE_METALLICITY
	Texture2D <float4> L1MaterialMetallicitySampler;									// Texture based metallicity.
	Texture2D <float4> L2MaterialMetallicitySampler;									// Texture based metallicity.
#else //! TEXTURE_METALLICITY
	float L1MaterialMetallicity < float UIMin = 0; float UIMax = 1.0; > = 0.0f;			// Material constant metallicity.
	float L2MaterialMetallicity < float UIMin = 0; float UIMax = 1.0; > = 0.0f;		// Material constant metallicity.
#endif //! TEXTURE_METALLICITY

#ifdef TEXTURE_CAVITY
	Texture2D <float4> L1MaterialCavitySampler;										// Texture based cavity.
	Texture2D <float4> L2MaterialCavitySampler;										// Texture based cavity.
#endif //! TEXTURE_CAVITY

#ifdef TEXTURE_SPECULAR_COLOR
	Texture2D <float4> L1MaterialSpecularColorSampler;									// Texture based conductor specular color.
	Texture2D <float4> L2MaterialSpecularColorSampler;									// Texture based conductor specular color.
#else //! TEXTURE_SPECULAR_COLOR
	float3 L1MaterialSpecularColor = float3(1.00, 0.71, 0.29);							// Material constant conductor specular color.
	float3 L2MaterialSpecularColor = float3(1.00, 0.71, 0.29);							// Material constant conductor specular color.
#endif //! TEXTURE_SPECULAR_COLOR

#ifdef TEXTURE_ENABLED
	Texture2D <float4> L1AlbedoSampler;													// Texture based albedo.
	Texture2D <float4> L2AlbedoSampler;												// Texture based albedo.
#else //! TEXTURE_ENABLED
	float4 L1Albedo = float4(1,1,1,1);													// Material constant albedo.
	float4 L2Albedo = float4(1,1,1,1);													// Material constant albedo.
#endif //! TEXTURE_ENABLED

// Description:
// Initialize the material properties from texture based or material constant parameters as specified by material switches.
// Arguments:
// self - The material properties to initialize.
// uv - The texture coordinate with which to sample texture based material parameters.
static void L1Initialize(out PbrMaterialProperties self, float2 uv)
{
#ifdef TEXTURE_ROUGHNESS
	self.m_linearRoughness = L1MaterialLinearRoughnessSampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_ROUGHNESS
	self.m_linearRoughness = L1MaterialLinearRoughness;
#endif //! TEXTURE_ROUGHNESS
	self.m_linearRoughness = max(self.m_linearRoughness, 0.01f);			// Avoid issues with mirror surfaces.

	self.m_viewDependentRoughnessStrength = L1MaterialViewDependentRoughnessStrength;

#ifdef TEXTURE_METALLICITY
	self.m_metallicity = L1MaterialMetallicitySampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_METALLICITY
	self.m_metallicity = L1MaterialMetallicity;
#endif //! TEXTURE_METALLICITY

#ifdef TEXTURE_CAVITY
	self.m_cavity = L1MaterialCavitySampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_CAVITY
	self.m_cavity = 1.0f;
#endif //! TEXTURE_CAVITY

	if (IsMetal(self.m_metallicity))
	{
#ifdef TEXTURE_SPECULAR_COLOR
		self.m_specularColor = L1MaterialSpecularColorSampler.Sample(TextureSamplerSampler, uv).xyz;
#else //! TEXTURE_SPECULAR_COLOR
		self.m_specularColor = L1MaterialSpecularColor;
#endif //! TEXTURE_SPECULAR_COLOR
	}
	else
	{
		self.m_specularColor = DIELECTRIC_SPECULAR;
	}

#ifdef TEXTURE_ENABLED
	self.m_albedo = L1AlbedoSampler.Sample(TextureSamplerSampler, uv);
#else //! TEXTURE_ENABLED
	self.m_albedo = L1Albedo;
#endif //! TEXTURE_ENABLED
}

// Description:
// Initialize the material properties from texture based or material constant parameters as specified by material switches.
// Arguments:
// self - The material properties to initialize.
// uv - The texture coordinate with which to sample texture based material parameters.
static void L2Initialize(out PbrMaterialProperties self, float2 uv)
{
#ifdef TEXTURE_ROUGHNESS
	self.m_linearRoughness = L2MaterialLinearRoughnessSampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_ROUGHNESS
	self.m_linearRoughness = L2MaterialLinearRoughness;
#endif //! TEXTURE_ROUGHNESS
	self.m_linearRoughness = max(self.m_linearRoughness, 0.01f);			// Avoid issues with mirror surfaces.

	self.m_viewDependentRoughnessStrength = L2MaterialViewDependentRoughnessStrength;

#ifdef TEXTURE_METALLICITY
	self.m_metallicity = L2MaterialMetallicitySampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_METALLICITY
	self.m_metallicity = L2MaterialMetallicity;
#endif //! TEXTURE_METALLICITY

#ifdef TEXTURE_CAVITY
	self.m_cavity = L2MaterialCavitySampler.Sample(TextureSamplerSampler, uv).x;
#else //! TEXTURE_CAVITY
	self.m_cavity = 1.0f;
#endif //! TEXTURE_CAVITY

	if (IsMetal(self.m_metallicity))
	{
#ifdef TEXTURE_SPECULAR_COLOR
		self.m_specularColor = L2MaterialSpecularColorSampler.Sample(TextureSamplerSampler, uv).xyz;
#else //! TEXTURE_SPECULAR_COLOR
		self.m_specularColor = L2MaterialSpecularColor;
#endif //! TEXTURE_SPECULAR_COLOR
	}
	else
	{
		self.m_specularColor = DIELECTRIC_SPECULAR;
	}

#ifdef TEXTURE_ENABLED
	self.m_albedo = L2AlbedoSampler.Sample(TextureSamplerSampler, uv);
#else //! TEXTURE_ENABLED
	self.m_albedo = L2Albedo;
#endif //! TEXTURE_ENABLED
}

////////////////////
// Layer blending //
////////////////////

#ifdef TEXTURE_LAYER_BLEND
	Texture2D <float4> LayerBlendSampler;										// Texture based layer blend.
#else //! TEXTURE_LAYER_BLEND
	float LayerBlend < float UIMin = 0; float UIMax = 1.0; > = 0.0f;			// Material constant layer blend.
#endif //! TEXTURE_LAYER_BLEND

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
#if defined(LAYER2_UVS)|| defined(LIGHTMAP_OCCLUSION)
	float2	Uv1						: TEXCOORD2;
#endif //! defined(LAYER2_UVS)|| defined(LIGHTMAP_OCCLUSION)

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
#if defined(LAYER2_UVS)|| defined(LIGHTMAP_OCCLUSION)
	float2	Uv1						: TEXCOORD4;
#endif //! defined(LAYER2_UVS)|| defined(LIGHTMAP_OCCLUSION)

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
#ifdef LAYER2_UVS
	float2	Uv1						: TEXCOORD1;
#endif //! LAYER2_UVS

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
#ifdef LAYER2_UVS
	float2	Uv1						: TEXCOORD1;
#endif //! LAYER2_UVS
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

	// Copy tex coordinate.
	OUT.Uv = CopyUV(IN.Uv);
#if defined(LAYER2_UVS) || defined(LIGHTMAP_OCCLUSION)
	OUT.Uv1 = CopyUV(IN.Uv1);
#endif //! defined(LAYER2_UVS) || defined(LIGHTMAP_OCCLUSION)

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
#ifdef LAYER2_UVS
	OUT.Uv1 = CopyUV(IN.Uv1);
#endif //! LAYER2_UVS

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
	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties layer1Mat, layer2Mat;
	L1Initialize(layer1Mat, IN.Uv);
#ifdef LAYER2_UVS
	L2Initialize(layer2Mat, IN.Uv1);
#else //! LAYER2_UVS
	L2Initialize(layer2Mat, IN.Uv);
#endif //! LAYER2_UVS

#ifdef ALPHA_ENABLED
	float layer1Alpha = layer1Mat.m_albedo.w;
	float layer2Alpha = layer2Mat.m_albedo.w;
#else //! ALPHA_ENABLED
	float layer1Alpha = 1.0f;
	float layer2Alpha = 1.0f;
#endif //! ALPHA_ENABLED

	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

#ifdef USE_LIGHTING
	// Perform lighting
	PbrLightingResults layer1LightResult = EvaluateLightingPBR(layer1Mat, geom);
	PbrLightingResults layer2LightResult = EvaluateLightingPBR(layer2Mat, geom);

	float3 layer1Fragment = layer1Mat.m_albedo.xyz * layer1Alpha * layer1LightResult.m_diffuse + layer1LightResult.m_specular;
	float3 layer2Fragment = layer2Mat.m_albedo.xyz * layer2Alpha * layer2LightResult.m_diffuse + layer2LightResult.m_specular;
#else //! USE_LIGHTING
	float3 layer1Fragment = layer1Mat.m_albedo.xyz * layer1Alpha;
	float3 layer2Fragment = layer2Mat.m_albedo.xyz * layer2Alpha;
#endif //! USE_LIGHTING

	// Blend the materials based on the blend layer.
#ifdef TEXTURE_LAYER_BLEND
	float layerBlend = LayerBlendSampler.Sample(TextureSamplerSampler, IN.Uv).x;
#else //! TEXTURE_LAYER_BLEND
	float layerBlend = LayerBlend;
#endif //! TEXTURE_LAYER_BLEND

// Premultiply alpha into diffuse and add specular. Then blend is set up to be Src + Dst*(1-Alpha).
// Final result is	Diffuse * Alpha		+ Framebuffer * 1-Alpha		+ Specular.
//					Scattered			+ Transmitted				+ Reflected.

	float3 fragment = lerp(layer1Fragment, layer2Fragment, layerBlend);
	float blendedAlpha = lerp(layer1Alpha, layer2Alpha, layerBlend);

#ifdef LIGHTMAP_OCCLUSION
	fragment *= LightmapSampler.Sample(LightprobeSamplerSampler, IN.Uv1).x;				// Apply occlusion lightmap.
#endif //! LIGHTMAP_OCCLUSION

	PS_OUTPUT Out;
	Out.Colour = float4(fragment, blendedAlpha);

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
	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties layer1Mat, layer2Mat;
	L1Initialize(layer1Mat, IN.Uv);
#ifdef LAYER2_UVS
	L2Initialize(layer2Mat, IN.Uv1);
#else //! LAYER2_UVS
	L2Initialize(layer2Mat, IN.Uv);
#endif //! LAYER2_UVS

#ifdef ALPHA_ENABLED
	float layer1Alpha = layer1Mat.m_albedo.w;
	float layer2Alpha = layer2Mat.m_albedo.w;
#else //! ALPHA_ENABLED
	float layer1Alpha = 1.0f;
	float layer2Alpha = 1.0f;
#endif //! ALPHA_ENABLED

	PbrGeomProperties geom;
	float3 geomNormal = normalize(IN.v.Normal);
#ifdef NORMAL_MAPPING_ENABLED
	float3 surfaceNormal = EvaluateNormalMapNormal(geomNormal, IN.Uv, IN.v.Tangent, NormalMapSampler);
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal, surfaceNormal);
#else //! NORMAL_MAPPING_ENABLED
	Initialize(geom, IN.v.WorldPositionDepth.xyz, IN.v.WorldPositionDepth.w, geomNormal);
#endif //! NORMAL_MAPPING_ENABLED

	// Blend the materials based on the blend layer.
#ifdef TEXTURE_LAYER_BLEND
	float layerBlend = LayerBlendSampler.Sample(TextureSamplerSampler, IN.Uv).x;
#else //! TEXTURE_LAYER_BLEND
	float layerBlend = LayerBlend;
#endif //! TEXTURE_LAYER_BLEND

	// Blend the material parameters before writing to the G buffers.
	float4 albedo = lerp(layer1Mat.m_albedo, layer2Mat.m_albedo, layerBlend);																			// Blend albedo.
	float3 specularColor = lerp(layer1Mat.m_specularColor, layer2Mat.m_specularColor, layerBlend);														// Blend specular.
	float linearRoughness = lerp(layer1Mat.m_linearRoughness, layer2Mat.m_linearRoughness, layerBlend);													// Blend roughness.
	float viewDependentRoughnessStrength = lerp(layer1Mat.m_viewDependentRoughnessStrength, layer2Mat.m_viewDependentRoughnessStrength, layerBlend);	// Blend view dep roughness.

	float ao = 1;
#ifdef LIGHTMAP_OCCLUSION
	ao = LightmapSampler.Sample(LightprobeSamplerSampler, IN.Uv1).x;				// Apply occlusion lightmap.
#endif //! LIGHTMAP_OCCLUSION

	float2 octPackedNormal = packFloat3ToOct(normalize(geom.m_surfaceNormal.xyz));

	PbrDeferredPSOutput OUT;
	OUT.Color = float4(albedo.xyz, ao);
	OUT.Normal_Depth = float4(bx2Pack(octPackedNormal), viewDependentRoughnessStrength, geom.m_viewDepth);
	OUT.Specular_Rough = float4(specularColor.xyz, linearRoughness);

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
	// Fetch material parameters from the right place based on material switches.
	PbrMaterialProperties layer1Mat, layer2Mat;
	L1Initialize(layer1Mat, IN.Uv);
#ifdef LAYER2_UVS
	L2Initialize(layer2Mat, IN.Uv1);
#else //! LAYER2_UVS
	L2Initialize(layer2Mat, IN.Uv);
#endif //! LAYER2_UVS

	float layer1Alpha = layer1Mat.m_albedo.w;
	float layer2Alpha = layer2Mat.m_albedo.w;

	// Blend the materials based on the blend layer.
#ifdef TEXTURE_LAYER_BLEND
	float layerBlend = LayerBlendSampler.Sample(TextureSamplerSampler, IN.Uv).x;
#else //! TEXTURE_LAYER_BLEND
	float layerBlend = LayerBlend;
#endif //! TEXTURE_LAYER_BLEND

	float blendedAlpha = lerp(layer1Alpha, layer2Alpha, layerBlend);

	clip(blendedAlpha - AlphaThreshold);
#endif //! ALPHA_ENABLED
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
				//SetPixelShader( CompileShader( ps_4_0, DefaultShadowFP() ) );
	
				SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
				SetDepthStencilState( DepthState, 0);
				SetRasterizerState( DefaultRasterState );
			}
		}
	#endif //! ALPHA_ENABLED
#endif //! CASTS_SHADOWS
