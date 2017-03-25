/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_DEFAULT_SHADER_SHARED_CODE_H
#define PHYRE_DEFAULT_SHADER_SHARED_CODE_H

#include "PhyreShaderCommon.h"

// Shared code and shader implementations.

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Context Switch definitions

#ifndef MAX_NUM_LIGHTS
	// The maximum number of lights this shader supports.
	#define MAX_NUM_LIGHTS 3
#endif //! MAX_NUM_LIGHTS

#ifndef DEFINED_CONTEXT_SWITCHES
	// Context switches
	bool PhyreContextSwitches 
	< 
	string ContextSwitchNames[] = {"NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "SHADER_LOD_LEVEL", "LOW_RES_PARTICLES"}; 
	int MaxNumLights = MAX_NUM_LIGHTS; 
	string SupportedLightTypes[] = {"DirectionalLight","PointLight","SpotLight"};
	string SupportedShadowTypes[] = {"PCFShadowMap", "CascadedShadowMap", "CombinedCascadedShadowMap"};
	int NumSupportedShaderLODLevels = 1;
	>;
	#define DEFINED_CONTEXT_SWITCHES
#endif //! DEFINED_CONTEXT_SWITCHES

#ifdef SHADER_LOD_LEVEL

#if SHADER_LOD_LEVEL > 0
	#ifdef NORMAL_MAPPING_ENABLED
		#undef NORMAL_MAPPING_ENABLED
	#endif //! NORMAL_MAPPING_ENABLED
#endif //! SHADER_LOD_LEVEL > 0

#endif //! SHADER_LOD_LEVEL

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Preprocessing of switches. 
// Setup macros for common combinations of switches
#ifdef NUM_LIGHTS
#if NUM_LIGHTS > MAX_NUM_LIGHTS
#error Maximum number of supported lights exceeded.
#endif //! NUM_LIGHTS > MAX_NUM_LIGHTS
#endif //! NUM_LIGHTS

#ifdef NUM_LIGHTS
#if defined(LIGHTING_ENABLED) && NUM_LIGHTS > 0
#define USE_LIGHTING
#endif //! defined(LIGHTING_ENABLED) && NUM_LIGHTS > 0
#endif //! NUM_LIGHTS

#ifdef NORMAL_MAPPING_ENABLED
#define USE_TANGENTS
#endif //! NORMAL_MAPPING_ENABLED

#if defined(ALPHA_ENABLED) && defined(TEXTURE_ENABLED)
#define SHADOW_TEXTURE_SAMPLING_ENABLED
#define ZPREPASS_TEXTURE_SAMPLING_ENABLED
#endif //! defined(ALPHA_ENABLED) && defined(TEXTURE_ENABLED)

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global shader parameters.

// Un-tweakables
float4x4 World		: World;		
float4x4 WorldView	: WorldView;		
float4x4 WorldInverse	: WorldInverse;
float4x4 WorldViewProjection		: WorldViewProjection;	
float4x4 WorldViewInverse	: WorldViewInverse;

#ifdef MOTION_BLUR_ENABLED
float4x4 PreviousWorld		: PreviousWorld;	
float4x4 PreviousWorldViewProjection : PreviousWorldViewProjection;
#endif //! MOTION_BLUR_ENABLED

#ifdef SKINNING_ENABLED
#ifndef NUM_SKIN_TRANSFORMS
	#define NUM_SKIN_TRANSFORMS 80 // Note: This number is mirrored in Core as PD_MATERIAL_SKINNING_MAX_GPU_BONE_COUNT
#endif // NUM_SKIN_TRANSFORMS
float3x4 BoneTransforms[NUM_SKIN_TRANSFORMS] : BONETRANSFORMS;
#endif //! SKINNING_ENABLED

// Ambient lighting parameters
half4 GlobalAmbientColor;

// Distance fog parameters.
#ifdef FOG_ENABLED
half4 FogColor : FOGCOLOR;
// FogRangeParameters : x = Near, y = Far, z = 1/(Far-Near)
float4 FogRangeParameters : FOGRANGEPARAMETERS;
#endif //! FOG_ENABLED

// Tone mapping parameters.
#ifdef TONE_MAP_ENABLED
float SceneBrightnessScale;
float InvAverageVisibleLuminanceValueScaled;
#endif //! TONE_MAP_ENABLED

// Cel shading parameters
#ifdef CEL_ENABLED
half3 CelLight : CelLight = half3( 0, 1, 0 );
half4 CelColor : CelColor = half4( 1.0f, 0.0f, 0.0f, 1.0f );
float CelLevels : CelLevels
	<
	float UIMin = 1; float UIMax = 10;
	> = 4;
half4 CelOutlineColor : CelOutlineColor = half4( 0.0f, 0.0f, 0.0f, 1.0f );
float CelOutlineThickness : CelOutlineThickness
	<
	float UIMin = 0.0f; float UIMax = 1.0f;
	> = 0.5f;
#endif //! CEL_ENABLED

// Material Parameters
half4 MaterialColour : MaterialColour <string UIWidget = "ColorPicker"; string UIName = "Material Color"; string UILabel = "The material color.";> = half4(1.0f,1.0f,1.0f,1.0f);
// Material-supplied lighting Parameters.
half MaterialDiffuse : MaterialDiffuse <float UIMin = 0.0f; float UIMax = 1.0f; string UIName = "Material Diffuse"; string UILabel = "The material diffuse value.";> = 1.0f;
half MaterialEmissiveness : MaterialEmissiveness <float UIMin = 0.0f; float UIMax = 1.0f; string UIName = "Material Emissiveness"; string UILabel = "The materials emissiveness.";> = 0.0f;
#ifdef SPECULAR_ENABLED
half Shininess : Shininess 
<
float UIMin = 0; float UIMax = 20.0;
>  = 0.0f;
half SpecularPower : SpecularPower
<
float UIMin = 0; float UIMax = 64.0;
> = 16.0f;
half FresnelPower : FresnelPower
<
float UIMin = 0; float UIMax = 64.0;
>  = 5.0f;
#endif //! SPECULAR_ENABLED

// Engine-supplied lighting parameters
#ifdef USE_LIGHTING

// Combined parameters for SIMD lighting calculations..
half4 CombinedLightAttenuationCoeff0 : COMBINEDLIGHTATTENUATIONCOEFF0;		// The first distance attenuation coefficient for all the lights
half4 CombinedLightAttenuationCoeff1 : COMBINEDLIGHTATTENUATIONCOEFF1;		// The second distance attenuation coefficient for all the lights
half4 CombinedLightSpotCoeff0 : COMBINEDLIGHTSPOTCOEFF0;					// The first spot attenuation coefficient for all the lights
half4 CombinedLightSpotCoeff1 : COMBINEDLIGHTSPOTCOEFF1;					// The second spot attenuation coefficient for all the lights

// Separate lighting structures

#if NUM_LIGHTS > 0
LIGHTTYPE_0 Light0 : LIGHT0;
#ifndef SHADOWTYPE_0
#define LightShadow0 0.0f
#else //! SHADOWTYPE_0
SHADOWTYPE_0 LightShadow0 : LIGHTSHADOW0;
#endif //! SHADOWTYPE_0
#endif //! NUM_LIGHTS > 0

#if NUM_LIGHTS > 1
LIGHTTYPE_1 Light1 : LIGHT1;
#ifndef SHADOWTYPE_1
#define LightShadow1 0.0f
#else //! SHADOWTYPE_1
SHADOWTYPE_1 LightShadow1 : LIGHTSHADOW1;
#endif //! SHADOWTYPE_1
#endif //! NUM_LIGHTS > 1

#if NUM_LIGHTS > 2
LIGHTTYPE_2 Light2 : LIGHT2;
#ifndef SHADOWTYPE_2
#define LightShadow2 0.0f
#else //! SHADOWTYPE_2
SHADOWTYPE_2 LightShadow2 : LIGHTSHADOW2;
#endif //! SHADOWTYPE_2
#endif //! NUM_LIGHTS > 2

#if NUM_LIGHTS > 3
LIGHTTYPE_3 Light3 : LIGHT3;
#ifndef SHADOWTYPE_3
#define LightShadow3 0.0f
#else //! SHADOWTYPE_3
SHADOWTYPE_3 LightShadow3 : LIGHTSHADOW3;
#endif //! SHADOWTYPE_3
#endif //! NUM_LIGHTS > 2

#endif //! USE_LIGHTING

// Textures
#ifdef TEXTURE_ENABLED
sampler2D TextureSampler;
#ifdef MULTIPLE_UVS_ENABLED
sampler2D TextureSampler1;
#endif //! MULTIPLE_UVS_ENABLED
#endif //! TEXTURE_ENABLED

#ifdef NORMAL_MAPPING_ENABLED
sampler2D NormalMapSampler;
#endif //! NORMAL_MAPPING_ENABLED

#ifdef SSAO_ENABLED
sampler2D SSAOSampler;
#endif //! SSAO_ENABLED

#ifdef LIGHTPREPASS_ENABLED
sampler2D LightPrepassSampler;
#endif //! LIGHTPREPASS_ENABLED

#ifdef LOD_BLEND
half LodBlendValue : LodBlendValue;

#ifdef __psp2__
#define GET_LOD_FRAGMENT_UV(uv) uv
#else //! __psp2__
#define GET_LOD_FRAGMENT_UV(uv) (uv * (1.0f/256.0f))
#endif //! __psp2__

#endif //! LOD_BLEND

#if defined(LIGHTMAP_OCCLUSION) || defined(LIGHTMAP_RGB)
	#define LIGHTMAPPING
#endif //! defined(LIGHTMAP_OCCLUSION) || defined(LIGHTMAP_RGB)

#ifdef LIGHTMAPPING
// Sampler for lightmap texture. To be sampled with Uv, or Uv1 if MULTIPLE_UVS_ENABLED.
sampler2D LightmapSampler;
float4 LightmapUVScaleOffset = float4(1, 1, 0, 0);
#endif // LIGHTMAPPING

#if defined(NORMAL_MAPPING_ENABLED) || defined(TEXTURE_ENABLED) || defined(MULTIPLE_UVS_ENABLED) || defined(LIGHTMAPPING)
	#define USE_UVS
#endif //! defined(NORMAL_MAPPING_ENABLED) || defined(TEXTURE_ENABLED) || defined(MULTIPLE_UVS_ENABLED) || defined(LIGHTMAPPING)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Structures

#ifdef INSTANCING_ENABLED
struct InstancingInput
{
	float4	InstanceTransform0	: ATTR13;
	float4	InstanceTransform1	: ATTR14;
	float4	InstanceTransform2	: ATTR15;
};
#endif //! INSTANCING_ENABLED

struct ZVSInput
{
#ifdef SKINNING_ENABLED
	float3	SkinnableVertex		: POSITION;
	float4	SkinIndices			: COLOR0;
	float4	SkinWeights			: TEXCOORD2;
#else //! SKINNING_ENABLED
	float4	Position			: POSITION;
#endif //! SKINNING_ENABLED

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED
};

struct DefaultVSInput
{
#ifdef VERTEX_COLOR_ENABLED
	float4  Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
#ifdef SKINNING_ENABLED
	float3	SkinnableVertex		: POSITION;
	float3	SkinnableNormal		: NORMAL; 	
	float4	SkinIndices			: COLOR1;
	float4	SkinWeights			: TEXCOORD2;
#else //! SKINNING_ENABLED
	float4	Position			: POSITION;
	float3	Normal				: NORMAL; 	
#endif //! SKINNING_ENABLED

#ifdef USE_UVS
	float2	Uv					: TEXCOORD0;
#endif // USE_UVS

#ifdef USE_TANGENTS
#ifdef SKINNING_ENABLED
	float3	SkinnableTangent	: TEXCOORD1;
#else //! SKINNING_ENABLED
	float3	Tangent				: TEXCOORD1;
#endif //! SKINNING_ENABLED
#endif //! USE_TANGENTS
#ifdef MULTIPLE_UVS_ENABLED
#ifdef SKINNING_ENABLED
	float2 Uv1					: TEXCOORD3;
#else //! SKINNING_ENABLED
	float2 Uv1					: TEXCOORD2;
#endif //! SKINNING_ENABLED
#endif //! MULTIPLE_UVS_ENABLED

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED
};

#ifdef USE_TANGENTS
#define FWD_SCREENPOSITION_TEXCOORD TEXCOORD4
#else //! USE_TANGENTS
#define FWD_SCREENPOSITION_TEXCOORD TEXCOORD3
#endif //! USE_TANGENTS

struct DefaultVSForwardRenderOutput
{
#ifdef VERTEX_COLOR_ENABLED
	float4  Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
	float4	Position			: POSITION;	
	float2	Uv					: TEXCOORD0;
	float4	WorldPositionDepth	: TEXCOORD1;
	half3	Normal				: TEXCOORD2;
#ifdef USE_TANGENTS
	half3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS

#ifdef __psp2__
#ifdef LOD_BLEND
	float4  ScreenPosition		: FWD_SCREENPOSITION_TEXCOORD;	// Use a 4d texture coordinate and a projected texture read for screen-space texture reads on PlayStation(R)Vita.
#endif //! LOD_BLEND
#endif //! __psp2__
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1					: TEXCOORD5;
#endif //! MULTIPLE_UVS_ENABLED
#ifdef LOW_RES_PARTICLES
	float3 DepthTexCoord		: TEXCOORD6;
#endif // LOW_RES_PARTICLES
};

struct DefaultPSForwardRenderInput
{
#ifdef VERTEX_COLOR_ENABLED
	float4  Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
	float2	Uv					: TEXCOORD0;
	float4	WorldPositionDepth	: TEXCOORD1;
	half3	Normal				: TEXCOORD2;
#ifdef USE_TANGENTS
	half3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS

#ifdef __psp2__
#ifdef LOD_BLEND
	float4  ScreenPosition		: FWD_SCREENPOSITION_TEXCOORD;	// Use a 4d texture coordinate and a projected texture read for screen-space texture reads on PlayStation(R)Vita.
#endif //! LOD_BLEND
#else //! __psp2__
	float4	ScreenPosition		: WPOS;			// Use the WPOS register to derive the screen UV on non-PlayStation(R)Vita platforms.
#endif //! __psp2__
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1					: TEXCOORD5;
#endif //! MULTIPLE_UVS_ENABLED
#ifdef LOW_RES_PARTICLES
	float3 DepthTexCoord		: TEXCOORD6;
#endif // LOW_RES_PARTICLES
};

struct DefaultPSLightPrepassRenderInput
{
#ifdef VERTEX_COLOR_ENABLED
	float4  Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
	float4	Position			: POSITION;	
	float4	ScreenPosition		: WPOS;
	float2	Uv					: TEXCOORD0;	
	float4	WorldPositionDepth	: TEXCOORD1;

#ifdef __psp2__
	half3	Normal				: TEXCOORD3;
#ifdef USE_TANGENTS
	half3	Tangent				: TEXCOORD4;
#endif //! USE_TANGENTS
#else //! __psp2__
	half3	Normal				: TEXCOORD2; 
#ifdef USE_TANGENTS
	half3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS
#endif //! __psp2__
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1					: TEXCOORD5;
#endif //! MULTIPLE_UVS_ENABLED
};

struct DefaultVSDeferredRenderOutput
{
	float4	Position			: POSITION;	
	float2	Uv					: TEXCOORD0;
	half3	Normal				: TEXCOORD1; 	

#ifdef __psp2__
	half4	Color				: TEXCOORD2;
#else //! __psp2__
	float4	WorldPositionDepth	: TEXCOORD2;
	float4	Color				: COLOR0;
#endif //! __psp2__

#ifdef USE_TANGENTS
	half3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1					: TEXCOORD4;
#endif //! MULTIPLE_UVS_ENABLED
};

struct DefaultPSDeferredRenderInput
{
	float4	ScreenPosition		: WPOS;
	float2	Uv					: TEXCOORD0;
	half3	Normal				: TEXCOORD1;

#ifdef __psp2__
	half4	Color				: TEXCOORD2;
#else //! __psp2__
	float4	WorldPositionDepth	: TEXCOORD2;
	float4	Color				: COLOR0;
#endif //! __psp2__

#ifdef USE_TANGENTS
	half3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1					: TEXCOORD4;
#endif //! MULTIPLE_UVS_ENABLED
};

#ifdef INSTANCING_ENABLED
void ApplyInstanceTransformVertex(InstancingInput IN, inout float3 toTransform)
{
	float3 instanceTransformedPosition;
	instanceTransformedPosition.x = dot(IN.InstanceTransform0, float4(toTransform,1));
	instanceTransformedPosition.y = dot(IN.InstanceTransform1, float4(toTransform,1));
	instanceTransformedPosition.z = dot(IN.InstanceTransform2, float4(toTransform,1));
	toTransform = instanceTransformedPosition;
}

void ApplyInstanceTransformNormal(InstancingInput IN, inout float3 toTransform)
{
	float3 instanceTransformedNormal;
	instanceTransformedNormal.x = dot(IN.InstanceTransform0.xyz, toTransform);
	instanceTransformedNormal.y = dot(IN.InstanceTransform1.xyz, toTransform);
	instanceTransformedNormal.z = dot(IN.InstanceTransform2.xyz, toTransform);
	toTransform = instanceTransformedNormal;
}
void ApplyInstanceTransform(inout DefaultVSInput IN)
{
#ifdef SKINNING_ENABLED
	ApplyInstanceTransformVertex(IN.instancingInput, IN.SkinnableVertex.xyz);
	ApplyInstanceTransformNormal(IN.instancingInput, IN.SkinnableNormal.xyz);
	#ifdef USE_TANGENTS
		ApplyInstanceTransformNormal(IN.instancingInput, IN.SkinnableTangent.xyz);
	#endif //! USE_TANGENTS
#else //! SKINNING_ENABLED
	ApplyInstanceTransformVertex(IN.instancingInput, IN.Position.xyz);
	ApplyInstanceTransformNormal(IN.instancingInput, IN.Normal.xyz);
	#ifdef USE_TANGENTS
		ApplyInstanceTransformNormal(IN.instancingInput, IN.Tangent.xyz);
	#endif //! USE_TANGENTS
#endif //! SKINNING_ENABLED
}
#endif //! INSTANCING_ENABLED

float4 GenerateScreenProjectedUv(float4 projPosition)
{
	float2 clipSpaceDivided = projPosition.xy / projPosition.w;
	clipSpaceDivided.y = -clipSpaceDivided.y;
	float2 tc = clipSpaceDivided.xy * 0.5 + 0.5;

	tc *= float2(960.0f/256.0f,544.0f/256.0f);

	return float4(tc * projPosition.w,0,projPosition.w);	
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Vertex shaders

// Default shadow vertex shader.
float4 DefaultShadowVS(ZVSInput IN) : POSITION
{
#ifdef SKINNING_ENABLED
	float3 position = IN.SkinnableVertex;
	UNNORMALIZE_SKININDICES(IN.SkinIndices);
#ifdef __psp2__
	EvaluateSkinPosition2Bones(position.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);	
#else //! __psp2__
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);	
#endif //! __psp2__
#else  //! SKINNING_ENABLED
	float3 position = IN.Position.xyz;
#endif //! SKINNING_ENABLED
#ifdef INSTANCING_ENABLED
	ApplyInstanceTransformVertex(IN.instancingInput, position);
#endif //! INSTANCING_ENABLED

#ifdef SKINNING_ENABLED
	return mul(scene.ViewProjection, float4(position.xyz,1));
#else //! SKINNING_ENABLED
	return mul(WorldViewProjection, float4(position.xyz,1));
#endif //! SKINNING_ENABLED
}

// Default Z prepass vertex shader.
float4 DefaultZPrePassVS(ZVSInput IN) : POSITION
{
#ifdef SKINNING_ENABLED
	float3 position = IN.SkinnableVertex;
	UNNORMALIZE_SKININDICES(IN.SkinIndices);
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);
#else //! SKINNING_ENABLED
	float3 position = IN.Position.xyz;
#endif //! SKINNING_ENABLED

#ifdef INSTANCING_ENABLED
	ApplyInstanceTransformVertex(IN.instancingInput, position);
#endif //! INSTANCING_ENABLED

#ifdef SKINNING_ENABLED
	return mul(scene.ViewProjection, float4(position.xyz,1));
#else //! SKINNING_ENABLED
	return mul(WorldViewProjection, float4(position.xyz,1));
#endif //! SKINNING_ENABLED
}

// Default forward render vertex shader
DefaultVSForwardRenderOutput DefaultForwardRenderVS(DefaultVSInput IN)
{
	DefaultVSForwardRenderOutput OUT;

#ifdef SKINNING_ENABLED
	UNNORMALIZE_SKININDICES(IN.SkinIndices);
	#ifdef USE_TANGENTS
		EvaluateSkinPositionNormalTangent4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinnableTangent.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);
	#else //! USE_TANGENTS
		EvaluateSkinPositionNormal4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);
	#endif //! USE_TANGENTS
	#ifdef INSTANCING_ENABLED
		ApplyInstanceTransform(IN);
	#endif //! INSTANCING_ENABLED
	float3 position = IN.SkinnableVertex.xyz;
	OUT.Position = mul(scene.ViewProjection, float4(position,1.0f));
	OUT.WorldPositionDepth = float4(position.xyz, -mul(scene.View, float4(position,1.0f)).z);
	OUT.Normal = normalize(IN.SkinnableNormal.xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(IN.SkinnableTangent.xyz);
	#endif //! USE_TANGENTS
#else //! SKINNING_ENABLED
	#ifdef INSTANCING_ENABLED
		ApplyInstanceTransform(IN);
	#endif //! INSTANCING_ENABLED
		float3 position = IN.Position.xyz;
		OUT.Position = mul(WorldViewProjection, float4(position,1.0f));
		OUT.WorldPositionDepth = float4(mul(World, float4(position,1.0f)).xyz, -mul(WorldView, float4(position,1.0f)).z);
		OUT.Normal = normalize(mul(World, float4(IN.Normal,0)).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(World, float4(IN.Tangent,0)).xyz);
	#endif //! USE_TANGENTS
#endif //! SKINNING_ENABLED	

#ifdef USE_UVS
	OUT.Uv.xy = IN.Uv;
#else // USE_UVS
	OUT.Uv.xy = 0.0f;
#endif  // USE_UVS

#ifdef MULTIPLE_UVS_ENABLED
	OUT.Uv1.xy = IN.Uv1;
#endif //! MULTIPLE_UVS_ENABLED

#if defined(__psp2__) && defined(LOD_BLEND)
	OUT.ScreenPosition = GenerateScreenProjectedUv(OUT.Position);
#endif //! defined(__psp2__) && defined(LOD_BLEND)

#ifdef VERTEX_COLOR_ENABLED
	OUT.Color = IN.Color * MaterialColour;
#endif //! VERTEX_COLOR_ENABLED
   
#ifdef LOW_RES_PARTICLES
	OUT.DepthTexCoord.xy = (OUT.Position.xy / OUT.Position.w) * 0.5f + 0.5f;
	OUT.DepthTexCoord.z = OUT.Position.z;
#endif // LOW_RES_PARTICLES

	return OUT;
}

// Default forward render vertex shader
DefaultVSDeferredRenderOutput DefaultDeferredRenderVS(DefaultVSInput IN)
{
	DefaultVSDeferredRenderOutput OUT;

#ifdef SKINNING_ENABLED
	UNNORMALIZE_SKININDICES(IN.SkinIndices);
	#ifdef USE_TANGENTS
		EvaluateSkinPositionNormalTangent4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinnableTangent.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);
	#else //! USE_TANGENTS
		EvaluateSkinPositionNormal4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransforms);
	#endif //! USE_TANGENTS
	#ifdef INSTANCING_ENABLED
		ApplyInstanceTransform(IN);
	#endif //! INSTANCING_ENABLED
	float3 position = IN.SkinnableVertex.xyz;
	OUT.Position = mul(scene.ViewProjection, float4(position,1.0f));
#ifndef __psp2__
	OUT.WorldPositionDepth = float4(position.xyz, -mul(scene.View, float4(position,1.0f)).z);
#endif //! __psp2__
	OUT.Normal = normalize(mul(scene.View, float4(IN.SkinnableNormal.xyz,0)).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(scene.View, float4(IN.SkinnableTangent.xyz,0)).xyz);
	#endif //! USE_TANGENTS
#else //! SKINNING_ENABLED
	#ifdef INSTANCING_ENABLED
		ApplyInstanceTransform(IN);
	#endif //! INSTANCING_ENABLED
	float3 position = IN.Position.xyz;
	OUT.Position = mul(WorldViewProjection, float4(position,1.0));
#ifndef __psp2__
	OUT.WorldPositionDepth = float4(mul(World, float4(position,1.0)).xyz, -mul(WorldView, float4(position,1.0)).z);
#endif //! __psp2__
	OUT.Normal = normalize(mul(WorldView, float4(IN.Normal,0)).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(WorldView, float4(IN.Tangent,0)).xyz);
	#endif //! USE_TANGENTS
#endif //! SKINNING_ENABLED

#ifdef USE_UVS
	OUT.Uv.xy = IN.Uv;
#else // USE_UVS
	OUT.Uv.xy = 0.0f;
#endif  // USE_UVS
	OUT.Color = MaterialColour * float4(MaterialDiffuse,MaterialDiffuse,MaterialDiffuse,1.0);

#ifdef MULTIPLE_UVS_ENABLED
	OUT.Uv1.xy = IN.Uv1;
#endif //! MULTIPLE_UVS_ENABLED

#ifdef VERTEX_COLOR_ENABLED
	OUT.Color = OUT.Color * IN.Color;
#endif //! VERTEX_COLOR_ENABLED
    
	return OUT;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment utility macros. Just make the fragment shader code a bit neater by hiding some of the combination handling / argument passing here.

#ifdef PARALLAX_OFFSET_MAPPING_ENABLED
#define EvaluateNormal(In) EvaluateParallaxMapNormal(In.Normal.xyz,In.Uv,In.Tangent, NormalMapSampler, normalize(mul(scene.View, float4(IN.WorldPositionDepth.xyz,1)).xyz))
#elif defined(NORMAL_MAPPING_ENABLED)
#define EvaluateNormal(In) EvaluateNormalMapNormal(In.Normal.xyz,In.Uv,In.Tangent, NormalMapSampler)
#else //! PARALLAX_OFFSET_MAPPING_ENABLED
#define EvaluateNormal(In) EvaluateStandardNormal(In.Normal.xyz)
#endif //! PARALLAX_OFFSET_MAPPING_ENABLED

#ifdef RECEIVE_SHADOWS
#define EvaluateShadowValue(LightId, LightShadowId, worldPos, viewDepth) EvaluateShadow(LightId, LightShadowId, worldPos, viewDepth)
#else //! RECEIVE_SHADOWS
#define EvaluateShadowValue(LightId, LightShadowId, worldPos, viewDepth) 1.0h
#endif //! RECEIVE_SHADOWS

#ifdef SPECULAR_ENABLED
#define EvaluateLightFunction(LightIndex) \
	{ \
		half shad = EvaluateShadowValue(Light##LightIndex, LightShadow##LightIndex, worldPosition, In.WorldPositionDepth.w); \
		lightResult += EvaluateLight(Light##LightIndex, worldPosition, normal, -eyeDirection, shad, shininess, SpecularPower); \
	}
#else //! SPECULAR_ENABLED
#define EvaluateLightFunction(LightIndex) \
	{ \
		half shad = EvaluateShadowValue(Light##LightIndex, LightShadow##LightIndex, worldPosition, In.WorldPositionDepth.w); \
		lightResult += EvaluateLight(Light##LightIndex, worldPosition, normal, shad); \
	}
#endif //! SPECULAR_ENABLED

#ifdef LOD_BLEND
half GetLODDitherValue(float4 screenUv)
{	
#ifdef __psp2__
	half4 ditherValue = tex2Dproj<half4>(DitherNoiseTexture, screenUv.xyw);
#else //! __psp2__
	half4 ditherValue = tex2D(DitherNoiseTexture, screenUv.xy);
#endif //! __psp2__
	half threshold = (1.0h-abs(LodBlendValue));

	half lodBlendValueSign = sign(LodBlendValue);
	half rslt = ((ditherValue.x >= threshold) ? 1.0h : -1.0h) * lodBlendValueSign;
	return rslt;
}
#endif //! LOD_BLEND

// Tone mapping.
#ifdef TONE_MAP_ENABLED

half4 ToneMap(half3 colourValue)
{
	half lum = dot(colourValue,half3(0.299h,0.587h,0.144h)) ;
	half lumToneMap = lum * InvAverageVisibleLuminanceValueScaled;
    half lumToneMap1 = lumToneMap + 1;
    half lD = (lumToneMap*(1 + (lumToneMap * SceneBrightnessScale)))/lumToneMap1;
    
	// divide by luminance 
    half3 colourResult = colour / lum;
   	colourResult *= lD;
   
	return float4(colourResult, (lum * SceneBrightnessScale) + (1.0f/255.0f));
}

#endif //! TONE_MAP_ENABLED

// Fog.
#ifdef FOG_ENABLED

half3 EvaluateFog(half3 colourValue, float3 viewPosition)
{
	half fogAmt = saturate((abs(viewPosition.z)-FogRangeParameters.x) * FogRangeParameters.z);
	return lerp(colourValue,FogColor.xyz,fogAmt);
}

#endif //! FOG_ENABLED

#ifdef CEL_ENABLED

half3 CalcLightVal( half3 normal )
{
	float intensity = dot( -normalize(CelLight), normal );
	intensity *= floor(CelLevels);
	intensity = floor(intensity) * (1.0f / CelLevels);
	return CelColor.xyz * intensity;
}

#endif //! CEL_ENABLED

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment shaders

// Default fragment shader. 
float4 DefaultUnshadedFP(float4 ScreenPosition : WPOS) : COLOR0
{
#ifdef LOD_BLEND
	clip(GetLODDitherValue(GET_LOD_FRAGMENT_UV(ScreenPosition)));
#endif //! LOD_BLEND
	return 1;
}

// Default fragment shader. 
#ifdef __psp2__
__nativecolor __regformat unsigned char4 DefaultShadowFP()
#else //! __psp2__
float4 DefaultShadowFP() : COLOR0
#endif //! __psp2__
{
#ifdef __psp2__
	return unsigned char4(0,0,0,0);
#else //! __psp2__
	return 0.0;
#endif //! __psp2__
}

half4 PackNormalAndViewSpaceDepth(half3 normal, float viewSpaceZ)
{
	float normalizedViewZ = viewSpaceZ / scene.cameraNearFar.y;

	// Depth is packed into z, w.  W = Most sigificant bits, Z = Least significant bits.
	// We don't use full range on W so that initial value of 1.0 is clearly beyond far plane.
	half2 depthPacked = half2(frac(normalizedViewZ * 256.0f), floor(normalizedViewZ * 256.0f) / 255.0f);
	half4 rslt = half4(normal.xy, depthPacked);
	return rslt;
}

half4 PackNormalAndDepth(half3 normal, float depth)
{
	float viewSpaceZ = -(scene.cameraNearTimesFar / (depth * scene.cameraFarMinusNear - scene.cameraNearFar.y));
	return PackNormalAndViewSpaceDepth(normal,viewSpaceZ);
}

// Default light pre pass first pass shader. Outputs normal and defaulted specular power only.
float4 DefaultLightPrepassFP(DefaultVSForwardRenderOutput In) : COLOR0
{
	half3 normal = EvaluateNormal(In);
#ifdef SPECULAR_ENABLED
	half specPower = SpecularPower;
#else //! SPECULAR_ENABLED
	half specPower = 0.0f;
#endif //! SPECULAR_ENABLED

	return half4(normal.xyz * 0.5f+0.5f,specPower);
}


// Deferred rendering
#ifdef __psp2__
__nativecolor __regformat half4 DefaultDeferredRenderFP(DefaultVSDeferredRenderOutput In)
#else //! __psp2__
PSDeferredOutput DefaultDeferredRenderFP(DefaultVSDeferredRenderOutput In, float4 ScreenPosition : WPOS) 
#endif //! __psp2__
{
	half3 normal = EvaluateNormal(In);

#ifdef SPECULAR_ENABLED
	// could vary by pixel with a texture lookup
	half specPower = SpecularPower;
	half gloss = 1;
#else //! SPECULAR_ENABLED
	half specPower = 0;
	half gloss = 0;
#endif //! SPECULAR_ENABLED

	half4 colour = In.Color;

#ifdef TEXTURE_ENABLED
#ifdef __psp2__
	colour *= tex2D<half4>(TextureSampler, In.Uv);
#else //! __psp2__
	colour *= h4tex2D(TextureSampler, In.Uv);
#endif //! __psp2__
#endif //! TEXTURE_ENABLED

	half3 viewSpaceNormal = normal;

#ifdef CEL_ENABLED
	half3 worldNormal = mul(scene.ViewInverse, half4(normal, 0.0)).xyz;
	half3 worldPos = mul(scene.ViewInverse, half4(In.WorldPositionDepth.xyz, 0.0)).xyz;
	half3 eyeToSurface = normalize(scene.EyePosition - worldPos);
	colour.xyz = (abs(dot(eyeToSurface, worldNormal)) < CelOutlineThickness) ? CelOutlineColor.xyz : colour.xyz + CalcLightVal(worldNormal);
#endif //! CEL_ENABLED

				
#ifdef __psp2__
	
	//colour.w = MaterialEmissiveness;
	unsigned char4 out0 = unsigned char4(colour * 255.0);

	char4 viewNormali = char4(viewSpaceNormal.xyzz * 127.0);
 	unsigned char4 out1 = bit_cast<unsigned char4>(viewNormali);

	unsigned int2 outputValue =  unsigned int2(bit_cast<unsigned int>(out0), bit_cast<unsigned int>(out1));		
	return bit_cast<half4>(outputValue);
		
#else //! __psp2__

#ifdef LOD_BLEND
	clip(GetLODDitherValue(GET_LOD_FRAGMENT_UV(ScreenPosition)));
#endif //! LOD_BLEND
	PSDeferredOutput Out;
	Out.Colour = float4(colour.xyz, colour.w);//MaterialEmissiveness);
	Out.NormalDepth = PackNormalAndViewSpaceDepth(half3(viewSpaceNormal.xy*0.5f+0.5f,0), In.WorldPositionDepth.w);
	return Out;	
#endif //! __psp2__

}


#ifdef USE_LIGHTING

// Evaluate coefficients for SIMD processing for a directional light.
void EvaluateLightCoefficients(out half3 dir, out half sqrDistance, out half spotDir, DirectionalLight light, float3 worldPosition)
{
	dir = light.m_direction;
	sqrDistance = 0.0;
	spotDir = 1.0;
}

// Evaluate coefficients for SIMD processing for a point light.
void EvaluateLightCoefficients(out half3 dir, out half sqrDistance, out half spotDir, PointLight light, float3 worldPosition)
{
	half3 offset = (half3)(light.m_position - worldPosition);
	sqrDistance = dot(offset,offset);
	dir = offset * (1.0 / sqrt(sqrDistance));
	spotDir = 1.0;
}

// Evaluate coefficients for SIMD processing for a spot light.
void EvaluateLightCoefficients(out half3 dir, out half sqrDistance, out half spotDir, SpotLight light, float3 worldPosition)
{
	half3 offset = (half3)(light.m_position - worldPosition);
	sqrDistance = dot(offset,offset);
	dir = offset * (1.0 / sqrt(sqrDistance));
	spotDir = dot(dir, light.m_direction);
}

#if NUM_LIGHTS == 1

half3 Evaluate1Light(half3 lightDir0, half attenDistance, half spotDp, half shadowRslt, half3 worldPosition, half3 normal)
{
	half diffuseLightAmt = dot(lightDir0,normal);

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmt = diffuseLightAmt * 0.5 + 0.5;
	diffuseLightAmt *= diffuseLightAmt;
#endif //! WRAP_DIFFUSE_LIGHTING

	half3 lightCoeffs = half3(attenDistance, diffuseLightAmt, spotDp);
	half3 coeffs0 = half3(CombinedLightAttenuationCoeff0.x, 1.0, CombinedLightSpotCoeff0.x);
	half3 coeffs1 = half3(CombinedLightAttenuationCoeff1.x, 0.0, CombinedLightSpotCoeff1.x);
	
	half3 lightValues = saturate(lightCoeffs * coeffs0 + coeffs1);
	half2 lightValues2 = half2(lightValues.z * lightValues.z, shadowRslt); 
	half2 combinedRslt = lightValues.xy * lightValues2;

	half3 lightResult = Light0.m_colorIntensity * (combinedRslt.x * combinedRslt.y);

	return lightResult;
}	

#ifdef SPECULAR_ENABLED

half3 Evaluate1LightSpecular(half3 lightDir0, half attenDistance, half spotDp, half shadowRslt, half3 worldPosition, half3 normal, half3 eyeDirection, half shininess)
{
	half3 halfVec0 = eyeDirection * 0.5 + lightDir0 * 0.5;
	
	half4 lightCoeffs = half4(dot(lightDir0,normal), dot(halfVec0,normal), attenDistance, spotDp);		// N dot L
	
#ifdef WRAP_DIFFUSE_LIGHTING
	lightCoeffs.x = lightCoeffs.x * 0.5 + 0.5;
	lightCoeffs.x *= lightCoeffs.x;
#endif //! WRAP_DIFFUSE_LIGHTING

	half4 coeffs0 = half4(1.0, 1.0, CombinedLightAttenuationCoeff0.x, CombinedLightSpotCoeff0.x);
	half4 coeffs1 = half4(0.0, 0.0, CombinedLightAttenuationCoeff1.x, CombinedLightSpotCoeff1.x);
	lightCoeffs = saturate(lightCoeffs * coeffs0 + coeffs1);
	
	// Clamp specular light values to 0,1
	half diffPlusSpecAmt = pow(lightCoeffs.y, SpecularPower) * shininess + lightCoeffs.x;
	lightCoeffs.w *= lightCoeffs.w;
	
	half2 lightCoeffs2 = half2(diffPlusSpecAmt, shadowRslt); 
	half2 combinedRslt = lightCoeffs.zw * lightCoeffs2;
	half3 lightResult = Light0.m_colorIntensity * (combinedRslt.x * combinedRslt.y);

	return lightResult;
}	

#endif //! SPECULAR_ENABLED

#elif NUM_LIGHTS == 2

// Optimised SIMD calculation of 2 lights. 
half3 Evaluate2Lights(half3 lightDir0, half3 lightDir1, half2 attenDistances, half2 spotDps, half2 shadowRslts, half3 worldPosition, half3 normal)
{
	half2 diffuseLightAmts = half2(dot(lightDir0,normal), dot(lightDir1,normal));

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = diffuseLightAmts * 0.5 + 0.5;
	diffuseLightAmts *= diffuseLightAmts;
#else //! WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = max(diffuseLightAmts, 0.0);
#endif //! WRAP_DIFFUSE_LIGHTING

	half4 coeffs0 = half4(CombinedLightAttenuationCoeff0.xy, CombinedLightSpotCoeff0.xy);
	half4 coeffs1 = half4(CombinedLightAttenuationCoeff1.xy, CombinedLightSpotCoeff1.xy);
	half4 attenCoeffs = half4(attenDistances, spotDps);

	half4 attenValues = saturate(attenCoeffs * coeffs0 + coeffs1);
	attenValues.zw *= attenValues.zw;
	
	diffuseLightAmts *= attenValues.xy * attenValues.zw * shadowRslts;

	half3 lightResult = Light0.m_colorIntensity * diffuseLightAmts.x + Light1.m_colorIntensity * diffuseLightAmts.y;

	return lightResult;
}	

#ifdef SPECULAR_ENABLED

// Optimised SIMD calculation of 2 lights with specular term.
half3 Evaluate2LightsSpecular(half3 lightDir0, half3 lightDir1, half2 attenDistances, half2 spotDps, half2 shadowRslts, half3 worldPosition, half3 normal, half3 eyeDirection, half shininess)
{
	half3 halfVec0 = eyeDirection * 0.5 + lightDir0 * 0.5;
	half3 halfVec1 = eyeDirection * 0.5 + lightDir1 * 0.5;
	
	half2 diffuseLightAmts = half2(dot(lightDir0,normal), dot(lightDir1,normal));		// N dot L
	half2 specularLightAmts = half2(dot(halfVec0,normal), dot(halfVec1,normal));		// N dot H

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = diffuseLightAmts * 0.5 + 0.5;
	diffuseLightAmts *= diffuseLightAmts;
#else //! WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = max(diffuseLightAmts, 0.0);
#endif //! WRAP_DIFFUSE_LIGHTING

	// Clamp specular light values to 0,1
	specularLightAmts = saturate(specularLightAmts);
	specularLightAmts = pow(specularLightAmts, SpecularPower) * shininess;
	diffuseLightAmts += specularLightAmts;

	half4 coeffs0 = half4(CombinedLightAttenuationCoeff0.xy, CombinedLightSpotCoeff0.xy);
	half4 coeffs1 = half4(CombinedLightAttenuationCoeff1.xy, CombinedLightSpotCoeff1.xy);
	half4 attenCoeffs = half4(attenDistances, spotDps);
	half4 attenValues = saturate(attenCoeffs * coeffs0 + coeffs1);
	attenValues.zw *= attenValues.zw;

	diffuseLightAmts *= attenValues.xy * attenValues.zw * shadowRslts;
	
	half3 lightResult = Light0.m_colorIntensity * diffuseLightAmts.x + Light1.m_colorIntensity * diffuseLightAmts.y;

	return lightResult;
}	

#endif //! SPECULAR_ENABLED

#elif NUM_LIGHTS == 3 

// Optimised SIMD calculation of 3 lights.
half3 Evaluate3Lights(half3 lightDir0, half3 lightDir1, half3 lightDir2, half3 attenDistances, half3 spotDps, half3 shadowRslts, half3 worldPosition, half3 normal)
{
	half3 diffuseLightAmts = half3(dot(lightDir0,normal), dot(lightDir1,normal), dot(lightDir2,normal));

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = diffuseLightAmts * 0.5 + 0.5;
	diffuseLightAmts *= diffuseLightAmts;
#else //! WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = max(diffuseLightAmts, 0.0);
#endif //! WRAP_DIFFUSE_LIGHTING

	half3 attenValues = saturate(attenDistances * CombinedLightAttenuationCoeff0.xyz + CombinedLightAttenuationCoeff1.xyz);
	half3 spotLightAttens = saturate(spotDps * CombinedLightSpotCoeff0.xyz + CombinedLightSpotCoeff1.xyz);
	spotLightAttens *= spotLightAttens;
	diffuseLightAmts *= attenValues;

	spotLightAttens *= shadowRslts;
	half3 col0 = Light0.m_colorIntensity * spotLightAttens.x;
	half3 col1 = Light1.m_colorIntensity * spotLightAttens.y;
	half3 col2 = Light2.m_colorIntensity * spotLightAttens.z;
	
	half3 lightResult = col0 * diffuseLightAmts.x + col1 * diffuseLightAmts.y + col2 * diffuseLightAmts.z;

	return lightResult;
}	

#ifdef SPECULAR_ENABLED

// Optimised SIMD calculation of 3 lights with specular term.
half3 Evaluate3LightsSpecular(half3 lightDir0, half3 lightDir1, half3 lightDir2, half3 attenDistances, half3 spotDps, half3 shadowRslts, half3 worldPosition, half3 normal, half3 eyeDirection, half shininess)
{
	half3 halfVec0 = eyeDirection * 0.5 + lightDir0 * 0.5;
	half3 halfVec1 = eyeDirection * 0.5 + lightDir1 * 0.5;
	half3 halfVec2 = eyeDirection * 0.5 + lightDir2 * 0.5;

	half3 diffuseLightAmts = half3(dot(lightDir0,normal), dot(lightDir1,normal), dot(lightDir2,normal));		// N dot L
	half3 specularLightAmts = half3(dot(halfVec0,normal), dot(halfVec1,normal), dot(halfVec2,normal));		// N dot H

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = diffuseLightAmts * 0.5 + 0.5;
	diffuseLightAmts *= diffuseLightAmts;
#else //! WRAP_DIFFUSE_LIGHTING
	diffuseLightAmts = max(diffuseLightAmts, 0.0);
#endif //! WRAP_DIFFUSE_LIGHTING

	// Clamp specular light values to 0,1
	specularLightAmts = saturate(specularLightAmts);
	specularLightAmts = pow(specularLightAmts, SpecularPower) * shininess;

	diffuseLightAmts += specularLightAmts;

	half3 attenValues = saturate(attenDistances * CombinedLightAttenuationCoeff0.xyz + CombinedLightAttenuationCoeff1.xyz);
	half3 spotLightAttens = saturate(spotDps * CombinedLightSpotCoeff0.xyz + CombinedLightSpotCoeff1.xyz);
	spotLightAttens *= spotLightAttens;
	diffuseLightAmts *= attenValues;
	
	spotLightAttens *= shadowRslts;
	half3 col0 = Light0.m_colorIntensity * spotLightAttens.x;
	half3 col1 = Light1.m_colorIntensity * spotLightAttens.y;
	half3 col2 = Light2.m_colorIntensity * spotLightAttens.z;
	
	half3 lightResult = col0 * diffuseLightAmts.x + col1 * diffuseLightAmts.y + col2 * diffuseLightAmts.z;

	return lightResult;
}	

#endif //! SPECULAR_ENABLED

#endif //! NUM_LIGHTS == 3

#endif //! USE_LIGHTING

float3 EvaluateLightingDefault(DefaultPSForwardRenderInput In, float3 worldPosition, half3 normal, half glossValue)
{
	// Lighting
	half3 lightResult = 1;

#ifdef USE_LIGHTING
	lightResult = GlobalAmbientColor.xyz;

#ifdef SPECULAR_ENABLED
	half3 eyeDirection = normalize(worldPosition - scene.EyePosition);
	half shininess = Shininess * glossValue;
#endif //! SPECULAR_ENABLED

#if NUM_LIGHTS == 2 && defined(__psp2__)
	half2 attenuationDistances, spotDps, shadowRslts;
	half3 lightDir0, lightDir1;

	shadowRslts.x = EvaluateShadow(Light0, LightShadow0, worldPosition, In.WorldPositionDepth.w);
	shadowRslts.y = EvaluateShadow(Light1, LightShadow1, worldPosition, In.WorldPositionDepth.w);

	EvaluateLightCoefficients(lightDir0, attenuationDistances.x, spotDps.x, Light0, worldPosition);
	EvaluateLightCoefficients(lightDir1, attenuationDistances.y, spotDps.y, Light1, worldPosition);
	
#ifdef SPECULAR_ENABLED
	lightResult += Evaluate2LightsSpecular(lightDir0, lightDir1, attenuationDistances, spotDps, shadowRslts, worldPosition, normal, eyeDirection, shininess);
#else //! SPECULAR_ENABLED
	lightResult += Evaluate2Lights(lightDir0, lightDir1, attenuationDistances, spotDps, shadowRslts, worldPosition, normal);
#endif //! SPECULAR_ENABLED

#elif NUM_LIGHTS == 3 && defined(__psp2__)

	half3 attenuationDistances, spotDps, shadowRslts;
	half3 lightDir0, lightDir1, lightDir2;
	
	EvaluateLightCoefficients(lightDir0, attenuationDistances.x, spotDps.x, Light0, worldPosition);
	EvaluateLightCoefficients(lightDir1, attenuationDistances.y, spotDps.y, Light1, worldPosition);
	EvaluateLightCoefficients(lightDir2, attenuationDistances.z, spotDps.z, Light2, worldPosition);

	shadowRslts.x = EvaluateShadow(Light0, LightShadow0, worldPosition, In.WorldPositionDepth.w);
	shadowRslts.y = EvaluateShadow(Light1, LightShadow1, worldPosition, In.WorldPositionDepth.w);
	shadowRslts.z = EvaluateShadow(Light2, LightShadow2, worldPosition, In.WorldPositionDepth.w);

#ifdef SPECULAR_ENABLED
	lightResult += Evaluate3LightsSpecular(lightDir0, lightDir1, lightDir2, attenuationDistances, spotDps, shadowRslts, worldPosition, normal, eyeDirection, shininess);
#else //! SPECULAR_ENABLED
	lightResult += Evaluate3Lights(lightDir0, lightDir1, lightDir2, attenuationDistances, spotDps, shadowRslts, worldPosition, normal);
#endif //! SPECULAR_ENABLED

#else //! NUM_LIGHTS == 3 && defined(__psp2__)
	
#if NUM_LIGHTS > 0
	EvaluateLightFunction(0);
#endif //! NUM_LIGHTS > 0
#if NUM_LIGHTS > 1
	EvaluateLightFunction(1);
#endif //! NUM_LIGHTS > 1
#if NUM_LIGHTS > 2
	EvaluateLightFunction(2);
#endif //! NUM_LIGHTS > 2
#if NUM_LIGHTS > 3
	EvaluateLightFunction(3);
#endif //! NUM_LIGHTS > 2
#endif //! //! NUM_LIGHTS == 3 && defined(__psp2__)

#endif //! USE_LIGHTING

	return lightResult;
}

#endif

