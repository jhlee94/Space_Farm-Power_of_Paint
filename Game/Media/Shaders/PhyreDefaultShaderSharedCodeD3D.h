/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_DEFAULT_SHADER_SHARED_CODE_D3D11_H
#define PHYRE_DEFAULT_SHADER_SHARED_CODE_D3D11_H

#include "PhyreShaderCommonD3D.h"
#include "PhyreSceneWideParametersD3D.h"

// Shared code and shader implementations.

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Context Switch definitions

#ifndef MAX_NUM_LIGHTS
	// The maximum number of lights this shader supports.
	#define MAX_NUM_LIGHTS 3
#endif //! MAX_NUM_LIGHTS

#ifndef __ORBIS__
	#ifndef DEFINED_CONTEXT_SWITCHES
		// Context switches
		bool PhyreContextSwitches 
		< 
		string ContextSwitchNames[] = {"NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES"}; 
		int MaxNumLights = MAX_NUM_LIGHTS; 
		string SupportedLightTypes[] = {"DirectionalLight","PointLight","SpotLight"};
		string SupportedShadowTypes[] = {"PCFShadowMap", "CascadedShadowMap", "CombinedCascadedShadowMap"};
		int NumSupportedShaderLODLevels = 1;
		>;
		#define DEFINED_CONTEXT_SWITCHES
	#endif //! DEFINED_CONTEXT_SWITCHES
#endif //! __ORBIS__

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
float4x4 World					 : World;
float4x4 WorldView				 : WorldView;
float4x4 WorldInverse			 : WorldInverse;
float4x4 WorldViewProjection	 : WorldViewProjection;
float4x4 WorldViewProjectionPrev : WorldViewProjectionPrev;
float4x4 WorldViewInverse		 : WorldViewInverse;

#ifdef MOTION_BLUR_ENABLED
	float4x4 PreviousWorld		 : PreviousWorld;	
	float4x4 PreviousWorldViewProjection : PreviousWorldViewProjection;
#endif //! MOTION_BLUR_ENABLED

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

// Ambient lighting parameters
float4 GlobalAmbientColor;

// Distance fog parameters.
#ifdef FOG_ENABLED
	float4 FogColor : FOGCOLOR;
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
	float3 CelLight : CelLight = float3( 1, 0, 0 );
	float3 CelColor : CelColor = float3( 1, 0, 0 );
	float CelLevels : CelLevels
	<
	float UIMin = 1; float UIMax = 10;
	> = 4;
	float4 CelOutlineColor : OutlineColor = float4( 0.0f, 0.0f, 0.0f, 1.0f );
	float CelOutlineThickness : OutlineThickness
	<
	float UIMin = 0.0f; float UIMax = 1.0f;
	> = 0.5f;
#endif //! CEL_ENABLED

// Material Parameters
float4 MaterialColour : MaterialColour = float4(1.0f,1.0f,1.0f,1.0f);
// Material-supplied lighting Parameters.
float MaterialDiffuse : MaterialDiffuse = 1.0f;
float MaterialEmissiveness : MaterialEmissiveness = 0.0f;
#ifdef SPECULAR_ENABLED
	float Shininess : Shininess 
	<
		float UIMin = 0; float UIMax = 20.0;
	>  = 0.0f;
	float SpecularPower : SpecularPower
	<
		float UIMin = 0; float UIMax = 64.0;
	> = 16.0f;
	float FresnelPower : FresnelPower
	<
		float UIMin = 0; float UIMax = 64.0;
	>  = 5.0f;
#endif //! SPECULAR_ENABLED

#if defined(LIGHTMAP_OCCLUSION) || defined(LIGHTMAP_RGB)
	#define LIGHTMAPPING
#endif //! defined(LIGHTMAP_OCCLUSION) || defined(LIGHTMAP_RGB)

#ifdef LIGHTMAPPING
	// Sampler for lightmap texture. To be sampled with Uv, or Uv1 if MULTIPLE_UVS_ENABLED.
	Texture2D <float4> LightmapSampler;
	float4 LightmapUVScaleOffset = float4(1, 1, 0, 0);
	sampler LightmapSamplerSampler
	{
		Filter = Min_Mag_Mip_Linear;
		AddressU = Wrap;
		AddressV = Wrap;
	};
#endif // LIGHTMAPPING

// Engine-supplied lighting parameters
#ifdef USE_LIGHTING

	// Combined parameters for SIMD lighting calculations..
	float4 CombinedLightAttenuationCoeff0 : COMBINEDLIGHTATTENUATIONCOEFF0;		// The first distance attenuation coefficient for all the lights
	float4 CombinedLightAttenuationCoeff1 : COMBINEDLIGHTATTENUATIONCOEFF1;		// The second distance attenuation coefficient for all the lights
	float4 CombinedLightSpotCoeff0 : COMBINEDLIGHTSPOTCOEFF0;					// The first spot attenuation coefficient for all the lights
	float4 CombinedLightSpotCoeff1 : COMBINEDLIGHTSPOTCOEFF1;					// The second spot attenuation coefficient for all the lights
	// Separate lighting structures

	#if NUM_LIGHTS > 0
		LIGHTTYPE_0 Light0 : LIGHT0;
		#ifndef SHADOWTYPE_0
			#define LightShadow0 0.0f
			#define LightShadowMap0 0.0f
		#else //! SHADOWTYPE_0
			SHADOWTYPE_0 LightShadow0 : LIGHTSHADOW0;
			Texture2D <float> LightShadowMap0 : LIGHTSHADOWMAP0;
		#endif //! SHADOWTYPE_0
	#endif //! NUM_LIGHTS > 0

	#if NUM_LIGHTS > 1
		LIGHTTYPE_1 Light1 : LIGHT1;
		#ifndef SHADOWTYPE_1
			#define LightShadow1 0.0f
			#define LightShadowMap1 0.0f
		#else //! SHADOWTYPE_1
			SHADOWTYPE_1 LightShadow1 : LIGHTSHADOW1;
			Texture2D <float> LightShadowMap1 : LIGHTSHADOWMAP1;
		#endif //! SHADOWTYPE_1
	#endif //! NUM_LIGHTS > 1

	#if NUM_LIGHTS > 2
		LIGHTTYPE_2 Light2 : LIGHT2;
		#ifndef SHADOWTYPE_2
			#define LightShadow2 0.0f
			#define LightShadowMap2 0.0f
		#else //! SHADOWTYPE_2
			SHADOWTYPE_2 LightShadow2 : LIGHTSHADOW2;
			Texture2D <float> LightShadowMap2 : LIGHTSHADOWMAP2;
		#endif //! SHADOWTYPE_2
	#endif //! NUM_LIGHTS > 2

	#if NUM_LIGHTS > 3
		LIGHTTYPE_3 Light3 : LIGHT3;
		#ifndef SHADOWTYPE_3
			#define LightShadow3 0.0f
			#define LightShadowMap3 0.0f
		#else //! SHADOWTYPE_3
			SHADOWTYPE_3 LightShadow3 : LIGHTSHADOW3;
			Texture2D <float> LightShadowMap3 : LIGHTSHADOWMAP3;
		#endif //! SHADOWTYPE_3
	#endif //! NUM_LIGHTS > 3

#endif //! USE_LIGHTING

// Textures
#ifdef TEXTURE_ENABLED
	Texture2D <float4> TextureSampler;
	sampler TextureSamplerSampler
	{
		Filter = Min_Mag_Mip_Linear;
		AddressU = Wrap;
		AddressV = Wrap;
	};
	#ifdef MULTIPLE_UVS_ENABLED
		Texture2D <float4> TextureSampler1;
		sampler TextureSampler1Sampler
		{
			Filter = Min_Mag_Mip_Linear;
			AddressU = Wrap;
			AddressV = Wrap;
		};
	#endif //! MULTIPLE_UVS_ENABLED
#endif //! TEXTURE_ENABLED

#ifdef NORMAL_MAPPING_ENABLED
	Texture2D <float4> NormalMapSampler;

	sampler NormalMapSamplerSampler
	{
		Filter = Min_Mag_Mip_Linear;
		AddressU = Wrap;
		AddressV = Wrap;
	};
#endif //! NORMAL_MAPPING_ENABLED

#ifdef SSAO_ENABLED
	Texture2D <float4> SSAOSampler;
#endif //! SSAO_ENABLED

#ifdef LIGHTPREPASS_ENABLED
	Texture2D <float4> LightPrepassSampler;
#endif //! LIGHTPREPASS_ENABLED

#ifdef LOD_BLEND
	float LodBlendValue : LodBlendValue;

	#define GET_LOD_FRAGMENT_UV(uv) (float2(uv.xy))

#endif //! LOD_BLEND

sampler LinearWrapSampler
{
	Filter = Min_Mag_Mip_Linear;
    AddressU = Wrap;
    AddressV = Wrap;
};

sampler DitherSampler
{
	Filter = Min_Mag_Point_Mip_Linear;
    AddressU = Wrap;
    AddressV = Wrap;
};

#if defined(NORMAL_MAPPING_ENABLED) || defined(TEXTURE_ENABLED) || defined(LIGHTMAPPING)
	#define USE_UVS
#endif //! defined(NORMAL_MAPPING_ENABLED) || defined(TEXTURE_ENABLED) || defined(LIGHTMAPPING)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Structures

#ifdef INSTANCING_ENABLED
	struct InstancingInput
	{
		float4	InstanceTransform0 : InstanceTransform0;
		float4	InstanceTransform1 : InstanceTransform1;
		float4	InstanceTransform2 : InstanceTransform2;

#ifdef VELOCITY_ENABLED
		float4	InstanceTransformPrev0 : InstanceTransformPrev0;
		float4	InstanceTransformPrev1 : InstanceTransformPrev1;
		float4	InstanceTransformPrev2 : InstanceTransformPrev2;
#endif //! #ifdef VELOCITY_ENABLED
	};

#endif //! INSTANCING_ENABLED

struct ZVSInput
{
#ifdef SKINNING_ENABLED
	#ifdef __ORBIS__
		float4	SkinnableVertex		: POSITION;
	#else //! __ORBIS__
		float3	SkinnableVertex		: POSITION;
	#endif //! __ORBIS__
	uint4	SkinIndices			: BLENDINDICES;
	float4	SkinWeights			: BLENDWEIGHTS;
#else //! SKINNING_ENABLED
	#ifdef __ORBIS__
		float4	Position			: POSITION;
	#else //! __ORBIS__
		float3	Position			: POSITION;
	#endif //! __ORBIS__
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
	#ifdef __ORBIS__
		float4	SkinnableVertex		: POSITION;
	#else //! __ORBIS__
		float3	SkinnableVertex		: POSITION;
	#endif //! __ORBIS__
	float3	SkinnableNormal		: NORMAL; 	
	uint4	SkinIndices			: BLENDINDICES;
	float4	SkinWeights			: BLENDWEIGHTS;
#else //! SKINNING_ENABLED
	#ifdef __ORBIS__
		float4	Position			: POSITION;
	#else //! __ORBIS__
		float3	Position			: POSITION;
	#endif //! __ORBIS__
	float3	Normal				: NORMAL; 	
#endif //! SKINNING_ENABLED

#ifdef USE_UVS
	float2	Uv					: TEXCOORD0;
#endif //! USE_UVS

#ifdef USE_TANGENTS
	#ifdef SKINNING_ENABLED
		float3	SkinnableTangent	: TANGENT;
	#else //! SKINNING_ENABLED
		float3	Tangent				: TANGENT;
	#endif //! SKINNING_ENABLED
#endif //! USE_TANGENTS
#ifdef MULTIPLE_UVS_ENABLED
	float3 Uv1					: TEXCOORD2;
#endif //! MULTIPLE_UVS_ENABLED

#ifdef INSTANCING_ENABLED
	InstancingInput instancingInput;
#endif //! INSTANCING_ENABLED

#if defined(__ORBIS__) && defined(MULTISLICE_VR)
	uint   InstanceID : SV_INSTANCEID;
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)
};

#ifdef USE_TANGENTS
	#define FWD_SCREENPOSITION_TEXCOORD TEXCOORD4
#else //! USE_TANGENTS
	#define FWD_SCREENPOSITION_TEXCOORD TEXCOORD3
#endif //! USE_TANGENTS


struct  VelocityBufferVertexInfo
{
	float4	PositionCurrent : TEXCOORD8;
	float4	PositionPrev : TEXCOORD9;
};

struct DefaultVSForwardRenderOutput
{
#ifdef VERTEX_COLOR_ENABLED
	float4  Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
	float4	Position			: SV_POSITION;	
#ifdef USE_UVS
	float2	Uv					: TEXCOORD0;
#endif //! USE_UVS
#ifdef MULTIPLE_UVS_ENABLED
	float3 Uv1					: TEXCOORD4;
#endif //! MULTIPLE_UVS_ENABLED
	float4	WorldPositionDepth	: TEXCOORD1;
	float3	Normal				: TEXCOORD2;
#ifdef USE_TANGENTS
	float3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS
#ifdef LOW_RES_PARTICLES
	float2 DepthTexCoord		: TEXCOORD5;
#endif // LOW_RES_PARTICLES

#ifdef VELOCITY_ENABLED
	VelocityBufferVertexInfo VelocityData;
#endif //! VELOCITY_ENABLED
#if defined(__ORBIS__) && defined(MULTISLICE_VR)
	uint   SliceIndex : SV_RENDERTARGETARRAYINDEX;
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)
};

struct DefaultVSDeferredRenderOutput
{
	float4	Position			: SV_POSITION;	
#ifdef USE_UVS
	float2	Uv					: TEXCOORD0;
#endif //! USE_UVS
	float3	Normal				: TEXCOORD1; 	
	float4	WorldPositionDepth	: TEXCOORD2;
	float4	Color				: COLOR0;
#ifdef USE_TANGENTS
	float3	Tangent				: TEXCOORD3;
#endif //! USE_TANGENTS
#ifdef MULTIPLE_UVS_ENABLED
	float3 Uv1					: TEXCOORD4;
#endif //! MULTIPLE_UVS_ENABLED

#ifdef VELOCITY_ENABLED
	VelocityBufferVertexInfo VelocityData;
#endif //! VELOCITY_ENABLED
#if defined(__ORBIS__) && defined(MULTISLICE_VR)
	uint   SliceIndex : SV_RENDERTARGETARRAYINDEX;
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)
};

#ifdef SKINNING_ENABLED
// Evaluate skin for position, normal and tangent, for 4 bone weights.
void EvaluateSkinPositionNormalTangent4Bones(inout float3 position, inout float3 normal, inout float3 tangent, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform) 
{


	uint indexArray[4] = { boneIndices.x, boneIndices.y, boneIndices.z, boneIndices.w };

	float4 inPosition = float4(position, 1);
	float4 inNormal = float4(normal, 0);
	float4 inTangent = float4(tangent, 0);

	position =
		mul(inPosition, Transform[indexArray[0]]).xyz * weights.x
		+ mul(inPosition, Transform[indexArray[1]]).xyz * weights.y
		+ mul(inPosition, Transform[indexArray[2]]).xyz * weights.z
		+ mul(inPosition, Transform[indexArray[3]]).xyz * weights.w;

	normal =
		mul(inNormal, Transform[indexArray[0]]).xyz * weights.x
		+ mul(inNormal, Transform[indexArray[1]]).xyz * weights.y
		+ mul(inNormal, Transform[indexArray[2]]).xyz * weights.z
		+ mul(inNormal, Transform[indexArray[3]]).xyz * weights.w;

	tangent =
		mul(inTangent, Transform[indexArray[0]]).xyz * weights.x
		+ mul(inTangent, Transform[indexArray[1]]).xyz * weights.y
		+ mul(inTangent, Transform[indexArray[2]]).xyz * weights.z
		+ mul(inTangent, Transform[indexArray[3]]).xyz * weights.w;


}

void EvaluateSkinPositionNormal4Bones(inout float3 position, inout float3 normal, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform)
{
	uint indexArray[4] = { boneIndices.x, boneIndices.y, boneIndices.z, boneIndices.w };

	float4 inPosition = float4(position, 1);
	float4 inNormal = float4(normal, 0);

	position =
		mul(inPosition, Transform[indexArray[0]]).xyz * weights.x
		+ mul(inPosition, Transform[indexArray[1]]).xyz * weights.y
		+ mul(inPosition, Transform[indexArray[2]]).xyz * weights.z
		+ mul(inPosition, Transform[indexArray[3]]).xyz * weights.w;

	normal =
		mul(inNormal, Transform[indexArray[0]]).xyz * weights.x
		+ mul(inNormal, Transform[indexArray[1]]).xyz * weights.y
		+ mul(inNormal, Transform[indexArray[2]]).xyz * weights.z
		+ mul(inNormal, Transform[indexArray[3]]).xyz * weights.w;

}

void EvaluateSkinPosition4Bones(inout float3 position, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform)
{
	uint indexArray[4] = { boneIndices.x, boneIndices.y, boneIndices.z, boneIndices.w };
	float4 inPosition = float4(position, 1);

	position =
		mul(inPosition, Transform[indexArray[0]]).xyz * weights.x
		+ mul(inPosition, Transform[indexArray[1]]).xyz * weights.y
		+ mul(inPosition, Transform[indexArray[2]]).xyz * weights.z
		+ mul(inPosition, Transform[indexArray[3]]).xyz * weights.w;
}


// Evaluate skin for position, normal and tangent, for 4 bone weights using previous frame transforms.
void EvaluateSkinPositionNormalTangent4BonesPrev(inout float3 position, inout float3 normal, inout float3 tangent, float4 weights, uint4 boneIndices)
{
	EvaluateSkinPositionNormalTangent4Bones(position, normal, tangent, weights, boneIndices, BoneTransformsPrev);
}

void EvaluateSkinPositionNormal4BonesPrev(inout float3 position, inout float3 normal, float4 weights, uint4 boneIndices)
{
	EvaluateSkinPositionNormal4Bones(position, normal, weights, boneIndices, BoneTransformsPrev);
}

void EvaluateSkinPosition4BonesPrev(inout float3 position, float4 weights, uint4 boneIndices)
{
	EvaluateSkinPosition4Bones(position, weights, boneIndices, BoneTransformsPrev);
}

// Evaluate skin for position, normal and tangent, for 4 bone weights using current frame transforms.
void EvaluateSkinPositionNormalTangent4Bones(inout float3 position, inout float3 normal, inout float3 tangent, float4 weights, uint4 boneIndices)
{
	EvaluateSkinPositionNormalTangent4Bones(position, normal, tangent, weights, boneIndices, BoneTransforms);
}

void EvaluateSkinPositionNormal4Bones(inout float3 position, inout float3 normal, float4 weights, uint4 boneIndices)
{
	EvaluateSkinPositionNormal4Bones(position, normal, weights, boneIndices, BoneTransforms);
}

void EvaluateSkinPosition4Bones(inout float3 position, float4 weights, uint4 boneIndices)
{
	EvaluateSkinPosition4Bones(position, weights, boneIndices, BoneTransforms);
}

#endif //! SKINNING_ENABLED

#ifdef INSTANCING_ENABLED
void ApplyInstanceTransformVertex(InstancingInput IN, inout float3 toTransform)
{
	float3 instanceTransformedPosition;
	instanceTransformedPosition.x = dot(IN.InstanceTransform0, float4(toTransform,1));
	instanceTransformedPosition.y = dot(IN.InstanceTransform1, float4(toTransform,1));
	instanceTransformedPosition.z = dot(IN.InstanceTransform2, float4(toTransform,1));
	toTransform = instanceTransformedPosition;
}

#ifdef VELOCITY_ENABLED
void ApplyInstancePrevTransformVertex(InstancingInput IN, inout float3 toTransform)
{
	float3 instanceTransformedPosition;
	instanceTransformedPosition.x = dot(IN.InstanceTransformPrev0, float4(toTransform, 1));
	instanceTransformedPosition.y = dot(IN.InstanceTransformPrev1, float4(toTransform, 1));
	instanceTransformedPosition.z = dot(IN.InstanceTransformPrev2, float4(toTransform, 1));
	toTransform = instanceTransformedPosition;
}
#endif //! VELOCITY_ENABLED
 
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
float4 DefaultShadowVS(ZVSInput IN) : SV_POSITION
{
#ifdef SKINNING_ENABLED
	float3 position = IN.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, IN.SkinIndices);
#else  //! SKINNING_ENABLED
	float3 position = IN.Position.xyz;
#endif //! SKINNING_ENABLED
#ifdef INSTANCING_ENABLED
	ApplyInstanceTransformVertex(IN.instancingInput, position);
#endif //! INSTANCING_ENABLED

#ifdef SKINNING_ENABLED
	return mul(float4(position.xyz,1), ViewProjection);
#else //! SKINNING_ENABLED
	return mul(float4(position.xyz,1), WorldViewProjection);
#endif //! SKINNING_ENABLED
}

// Default Z prepass vertex shader.
float4 DefaultZPrePassVS(ZVSInput IN) : SV_POSITION
{
#ifdef SKINNING_ENABLED
	float3 position = IN.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, IN.SkinIndices);
#else //! SKINNING_ENABLED
	float3 position = IN.Position.xyz;
#endif //! SKINNING_ENABLED

#ifdef INSTANCING_ENABLED
	ApplyInstanceTransformVertex(IN.instancingInput, position);
#endif //! INSTANCING_ENABLED

#ifdef SKINNING_ENABLED
	return mul(float4(position.xyz,1), ViewProjection);
#else //! SKINNING_ENABLED
	return mul(float4(position.xyz,1), WorldViewProjection);
#endif //! SKINNING_ENABLED
}

#ifdef VELOCITY_ENABLED
VelocityBufferVertexInfo SetVelocityBufferOutputsVS(DefaultVSInput IN, float4 position)
{
	VelocityBufferVertexInfo OUT;

	OUT.PositionCurrent = position;

#ifdef SKINNING_ENABLED
#ifdef USE_TANGENTS
	EvaluateSkinPositionNormalTangent4BonesPrev(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinnableTangent.xyz, IN.SkinWeights, IN.SkinIndices);
#else //! USE_TANGENTS
	EvaluateSkinPositionNormal4BonesPrev(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinWeights, IN.SkinIndices);
#endif //! USE_TANGENTS
	OUT.PositionPrev = mul(float4(IN.SkinnableVertex.xyz, 1.0f), ViewProjectionPrev);
#else //! SKINNING_ENABLED

#ifdef INSTANCING_ENABLED
	ApplyInstancePrevTransformVertex(IN.instancingInput, IN.Position.xyz);
#endif //! INSTANCING_ENABLED

	OUT.PositionPrev = mul(float4(IN.Position.xyz, 1.0f), WorldViewProjectionPrev);
#endif //! SKINNING_ENABLED

	return OUT;
}
#endif //! VELOCITY_ENABLED

// Default forward render vertex shader
DefaultVSForwardRenderOutput DefaultForwardRenderVS(DefaultVSInput IN)
{
	DefaultVSForwardRenderOutput OUT;

#ifdef VELOCITY_ENABLED
	DefaultVSInput IN2 = IN;
#endif //! VELOCITY_ENABLED
	
#ifdef SKINNING_ENABLED
	#ifdef USE_TANGENTS
		EvaluateSkinPositionNormalTangent4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinnableTangent.xyz, IN.SkinWeights, IN.SkinIndices);
	#else //! USE_TANGENTS
		EvaluateSkinPositionNormal4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinWeights, IN.SkinIndices);
	#endif //! USE_TANGENTS
	float3 position = IN.SkinnableVertex.xyz;
#if defined(MULTISLICE_VR) && defined(__ORBIS__)
	OUT.Position = mul(float4(position,1.0f), MultiSliceParams[IN.InstanceID].ViewProjection);
#else //! defined(__ORBIS__) && defined(MULTISLICE_VR)
	OUT.Position = mul(float4(position, 1.0f), ViewProjection);
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)
	OUT.WorldPositionDepth = float4(position.xyz, -mul(float4(position,1.0f), View).z);
	OUT.Normal = normalize(IN.SkinnableNormal.xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(IN.SkinnableTangent.xyz);
	#endif //! USE_TANGENTS
#else //! SKINNING_ENABLED
	#ifdef INSTANCING_ENABLED
		ApplyInstanceTransform(IN);
	#endif //! INSTANCING_ENABLED
		float3 position = IN.Position.xyz;
#if defined(MULTISLICE_VR) && defined(__ORBIS__)
		float4 worldPosition = mul(float4(position, 1.0f), World);
		OUT.Position = mul(worldPosition, MultiSliceParams[IN.InstanceID].ViewProjection);
#else //! defined(__ORBIS__) && defined(MULTISLICE_VR)
		OUT.Position = mul(float4(position, 1.0f), WorldViewProjection);
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)

		OUT.WorldPositionDepth = float4(mul(float4(position,1.0f),World).xyz, -mul(float4(position,1.0f),WorldView).z);
		OUT.Normal = normalize(mul(float4(IN.Normal,0), World).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(float4(IN.Tangent,0), World).xyz);
	#endif //! USE_TANGENTS
#endif //! SKINNING_ENABLED	

#ifdef USE_UVS
	OUT.Uv.xy = IN.Uv;
#ifdef MULTIPLE_UVS_ENABLED
	OUT.Uv1.xyz = IN.Uv1.xyz;
#endif //! MULTIPLE_UVS_ENABLED

#ifdef MAYA
	OUT.Uv.y = 1.0 - OUT.Uv.y;
#ifdef MULTIPLE_UVS_ENABLED
	OUT.Uv1.y = 1.0 - OUT.Uv1.y;
#endif //! MULTIPLE_UVS_ENABLED
#endif //! MAYA
#endif //! USE_UVS

#ifdef VERTEX_COLOR_ENABLED
	OUT.Color = IN.Color * MaterialColour;
#endif //! VERTEX_COLOR_ENABLED
   
#ifdef LOW_RES_PARTICLES
	OUT.DepthTexCoord.xy = (OUT.Position.xy / OUT.Position.w) * 0.5f + 0.5f;
#ifndef __ORBIS__
	OUT.DepthTexCoord.y = 1-OUT.DepthTexCoord.y;
#endif //! __ORBIS__
#endif // LOW_RES_PARTICLES

#ifdef VELOCITY_ENABLED
	OUT.VelocityData = SetVelocityBufferOutputsVS(IN2, OUT.Position);
#endif //! VELOCITY_ENABLED

#if defined(__ORBIS__) && defined(MULTISLICE_VR)
	OUT.SliceIndex = IN.InstanceID;
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)

	return OUT;
}


// Default forward render vertex shader
DefaultVSDeferredRenderOutput DefaultDeferredRenderVS(DefaultVSInput IN)
{
	DefaultVSDeferredRenderOutput OUT;

#ifdef VELOCITY_ENABLED
	DefaultVSInput IN2 = IN;
#endif //! VELOCITY_ENABLED

#ifdef SKINNING_ENABLED
	#ifdef USE_TANGENTS
		EvaluateSkinPositionNormalTangent4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinnableTangent.xyz, IN.SkinWeights, IN.SkinIndices);
	#else //! USE_TANGENTS
		EvaluateSkinPositionNormal4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinWeights, IN.SkinIndices);
	#endif //! USE_TANGENTS
	float3 position = IN.SkinnableVertex.xyz;
#if defined(MULTISLICE_VR) && defined(__ORBIS__)
	OUT.Position = mul(float4(position, 1.0f), MultiSliceParams[IN.InstanceID].ViewProjection);
	OUT.WorldPositionDepth = float4(position.xyz, -mul(float4(position, 1.0f), MultiSliceParams[IN.InstanceID].View).z);
	OUT.Normal = normalize(mul(float4(IN.SkinnableNormal.xyz, 0), MultiSliceParams[IN.InstanceID].View).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(float4(IN.SkinnableTangent.xyz, 0), MultiSliceParams[IN.InstanceID].View).xyz);
	#endif //! USE_TANGENTS
#else //! defined(__ORBIS__) && defined(MULTISLICE_VR)
	OUT.Position = mul(float4(position, 1.0f), ViewProjection);
	OUT.WorldPositionDepth = float4(position.xyz, -mul(float4(position, 1.0f), View).z);
	OUT.Normal = normalize(mul(float4(IN.SkinnableNormal.xyz, 0), View).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(float4(IN.SkinnableTangent.xyz, 0), View).xyz);
	#endif //! USE_TANGENTS
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)
#else //! SKINNING_ENABLED
	#ifdef INSTANCING_ENABLED
		ApplyInstanceTransform(IN);
	#endif //! INSTANCING_ENABLED
	float3 position = IN.Position.xyz;
#if defined(MULTISLICE_VR) && defined(__ORBIS__)
	float4 worldPosition = mul(float4(position, 1.0f), World);
	float4 worldNormal = mul(float4(IN.Normal, 0.0f), World);
	OUT.Position = mul(worldPosition, MultiSliceParams[IN.InstanceID].ViewProjection);
	OUT.WorldPositionDepth = float4(worldPosition.xyz, -mul(worldPosition, MultiSliceParams[IN.InstanceID].View).z);
	OUT.Normal = normalize(mul(worldNormal, MultiSliceParams[IN.InstanceID].View).xyz);
	#ifdef USE_TANGENTS
		float4 worldTangent = mul(float4(IN.Tangent, 0.0f), World);
		OUT.Tangent = normalize(mul(worldTangent, MultiSliceParams[IN.InstanceID].View).xyz);
	#endif //! USE_TANGENTS
#else //! defined(__ORBIS__) && defined(MULTISLICE_VR)
	OUT.Position = mul(float4(position, 1.0f), WorldViewProjection);
	OUT.WorldPositionDepth = float4(mul(float4(position, 1.0), World).xyz, -mul(float4(position, 1.0), WorldView).z);
	OUT.Normal = normalize(mul(float4(IN.Normal, 0.0f), WorldView).xyz);
	#ifdef USE_TANGENTS
		OUT.Tangent = normalize(mul(float4(IN.Tangent, 0.0f), WorldView).xyz);
	#endif //! USE_TANGENTS
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)
#endif //! SKINNING_ENABLED

#ifdef USE_UVS
	OUT.Uv.xy = IN.Uv;
#ifdef MULTIPLE_UVS_ENABLED
	OUT.Uv1.xyz = IN.Uv1.xyz;
#endif //! MULTIPLE_UVS_ENABLED

#ifdef MAYA
	OUT.Uv.y = 1.0 - OUT.Uv.y;
#ifdef MULTIPLE_UVS_ENABLED
	OUT.Uv1.y = 1.0 - OUT.Uv1.y;
#endif //! MULTIPLE_UVS_ENABLED
#endif //! MAYA
#endif //! USE_UVS

	OUT.Color = MaterialColour * float4(MaterialDiffuse,MaterialDiffuse,MaterialDiffuse,1.0);

#ifdef VERTEX_COLOR_ENABLED
	OUT.Color = OUT.Color * IN.Color;
#endif //! VERTEX_COLOR_ENABLED

#ifdef VELOCITY_ENABLED
	OUT.VelocityData = SetVelocityBufferOutputsVS(IN2, OUT.Position);
#endif //! VELOCITY_ENABLED	

#if defined(__ORBIS__) && defined(MULTISLICE_VR)
	OUT.SliceIndex = IN.InstanceID;
#endif //! defined(__ORBIS__) && defined(MULTISLICE_VR)

	return OUT;
}

#ifdef NORMAL_MAPPING_ENABLED
float3 EvaluateNormalMapNormal(float3 inNormal, float2 inUv, float3 inTangent)
{
	float4 normalMapValue = NormalMapSampler.Sample(NormalMapSamplerSampler,inUv);
	float3 normalMapNormal = normalize(normalMapValue.xyz * 2.0h - 1.0h);

	// Evaluate tangent basis
	float3 basis0 = normalize(inTangent);
	float3 basis2 = normalize(inNormal);
	float3 basis1 = cross(basis0, basis2);

	float3 normal = (normalMapNormal.x * basis0) + (normalMapNormal.y * basis1) + (normalMapNormal.z * basis2);	
	return normal;
}
#endif //! NORMAL_MAPPING_ENABLED

#ifdef NORMAL_MAPPING_ENABLED
float3 EvaluateNormalMapPaint(float3 inNormal, float2 inUv, float3 inTangent, Texture2D paintNornamslMap)
{
	float4 normalMapValue = paintNornamslMap.Sample(NormalMapSamplerSampler, inUv);
	float3 normalMapNormal = normalize(normalMapValue.xyz * 2.0h - 1.0h);

	// Evaluate tangent basis
	float3 basis0 = normalize(inTangent);
	float3 basis2 = normalize(inNormal);
	float3 basis1 = cross(basis0, basis2);

	float3 normal = (normalMapNormal.x * basis0) + (normalMapNormal.y * basis1) + (normalMapNormal.z * basis2);
	return normal;
}
#endif //! NORMAL_MAPPING_ENABLED

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment utility macros. Just make the fragment shader code a bit neater by hiding some of the combination handling / argument passing here.

#ifdef PARALLAX_OFFSET_MAPPING_ENABLED
#define EvaluateNormal(In) EvaluateParallaxMapNormal(In.Normal.xyz,In.Uv,In.Tangent, NormalMapSampler, normalize(mul(float4(IN.WorldPositionDepth.xyz,1), View).xyz))
#elif defined(NORMAL_MAPPING_ENABLED)
#define EvaluateNormal(In) EvaluateNormalMapNormal(In.Normal.xyz,In.Uv,In.Tangent)
#else //! PARALLAX_OFFSET_MAPPING_ENABLED
#define EvaluateNormal(In) EvaluateStandardNormal(In.Normal.xyz)
#endif //! PARALLAX_OFFSET_MAPPING_ENABLED

#ifdef RECEIVE_SHADOWS
#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) EvaluateShadow(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth)
#else //! RECEIVE_SHADOWS
#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) 1.0f
#endif //! RECEIVE_SHADOWS

#ifdef SPECULAR_ENABLED
#define EvaluateLightFunction(LightIndex) \
	{ \
	float shad = EvaluateShadowValue(Light##LightIndex, LightShadow##LightIndex, LightShadowMap##LightIndex, worldPosition, In.WorldPositionDepth.w); \
		lightResult += EvaluateLight(Light##LightIndex, worldPosition, normal, -eyeDirection, shad, shininess, SpecularPower); \
	}
#else //! SPECULAR_ENABLED
#define EvaluateLightFunction(LightIndex) \
	{ \
		float shad = EvaluateShadowValue(Light##LightIndex, LightShadow##LightIndex, LightShadowMap##LightIndex, worldPosition, In.WorldPositionDepth.w); \
		lightResult += EvaluateLight(Light##LightIndex, worldPosition, normal, shad); \
	}
#endif //! SPECULAR_ENABLED

#ifdef LOD_BLEND

float LODDitherRandom(int n)
{
	n = (n << 13) ^ n;
	int rval = (n * (n*n*15731+789221) + 1376312589) & 0x7fffffff;

	return float(rval) * (1.0f/2147483647.0f);
}

float GetLODDitherValue(float2 screenUv)
{	
	
	float4 ditherValue = DitherNoiseTexture.Load(int3(screenUv,0) & 255);
	float threshold = (1.0f - abs(LodBlendValue));

	float lodBlendValueSign = sign(LodBlendValue);
	float rslt = ((ditherValue.x >= threshold) ? 1.0f : -1.0f) * lodBlendValueSign;
	return rslt;
}
#endif //! LOD_BLEND

// Tone mapping.
#ifdef TONE_MAP_ENABLED

float4 ToneMap(float3 colourValue)
{
	float lum = dot(colourValue,float3(0.299h,0.587h,0.144h)) ;
	float lumToneMap = lum * InvAverageVisibleLuminanceValueScaled;
    float lumToneMap1 = lumToneMap + 1;
    float lD = (lumToneMap*(1 + (lumToneMap * SceneBrightnessScale)))/lumToneMap1;
    
	// divide by luminance 
    float3 colourResult = colour / lum;
   	colourResult *= lD;
   
	return float4(colourResult, (lum * SceneBrightnessScale) + (1.0f/255.0f));
}

#endif //! TONE_MAP_ENABLED

// Fog.
#ifdef FOG_ENABLED

float3 EvaluateFog(float3 colourValue, float3 viewPosition)
{
	float fogAmt = saturate((abs(viewPosition.z)-FogRangeParameters.x) * FogRangeParameters.z);
	return lerp(colourValue,FogColor.xyz,fogAmt);
}

#endif //! FOG_ENABLED

#ifdef CEL_ENABLED

float3 CalcLightVal( float3 normal )
{
	float intensity = dot( -normalize(CelLight), normal );
	intensity *= floor(CelLevels);
	intensity = floor( intensity ) * ( 1.0f / CelLevels );
	return CelColor * intensity;
}

#endif //! CEL_ENABLED

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment shaders

// Default fragment shader. 
float4 DefaultUnshadedFP(float4 ScreenPosition : SV_POSITION) : FRAG_OUTPUT_COLOR0
{
#ifdef LOD_BLEND
	clip(GetLODDitherValue(GET_LOD_FRAGMENT_UV(ScreenPosition)));
#endif //! LOD_BLEND
	return 1;
}

// Default fragment shader. 
float4 DefaultShadowFP() : FRAG_OUTPUT_COLOR0
{
	return 0.0f;
}

float4 PackNormalAndViewSpaceDepth(float3 normal, float viewSpaceZ)
{
	float normalizedViewZ = viewSpaceZ / cameraNearFar.y;

	// Depth is packed into z, w.  W = Most sigificant bits, Z = Least significant bits.
	// We don't use full range on W so that initial value of 1.0 is clearly beyond far plane.
	half2 depthPacked = half2(frac(normalizedViewZ * 256.0f), floor(normalizedViewZ * 256.0f) / 255.0f);

	float4 rslt = float4(normal.xy, depthPacked);
	return rslt;
}
float4 PackNormalAndDepth(float3 normal, float depth)
{
	float viewSpaceZ = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
	return PackNormalAndViewSpaceDepth(normal,viewSpaceZ);
}

// Default light pre pass first pass shader. Outputs normal and defaulted specular power only.
float4 DefaultLightPrepassFP(DefaultVSForwardRenderOutput In) : FRAG_OUTPUT_COLOR0
{
	float3 normal = EvaluateNormal(In);
#ifdef SPECULAR_ENABLED
	float specPower = SpecularPower;
#else //! SPECULAR_ENABLED
	float specPower = 0.0f;
#endif //! SPECULAR_ENABLED

	return float4(normal.xyz * 0.5f+0.5f,specPower);
}

// Calculate velocity buffer data.
float2 CalculateVelocity(VelocityBufferVertexInfo velocityData)
{
	const float2 positionCurrent = velocityData.PositionCurrent.xy / velocityData.PositionCurrent.w + ProjectionJitter,
				 positionPrev    = velocityData.PositionPrev.xy / velocityData.PositionPrev.w + ProjectionJitterPrev;
	return positionCurrent - positionPrev;
}

// Deferred rendering
PSDeferredOutput DefaultDeferredRenderFP(DefaultVSDeferredRenderOutput In)
{
	float3 normal = EvaluateNormal(In);

#ifdef SPECULAR_ENABLED
	// could vary by pixel with a texture lookup
	float specPower = SpecularPower;
	float gloss = Shininess;
#else //! SPECULAR_ENABLED
	float specPower = 0;
	float gloss = 0;
#endif //! SPECULAR_ENABLED

	float4 colour = In.Color;
#ifdef TEXTURE_ENABLED
	colour *= TextureSampler.Sample(TextureSamplerSampler, In.Uv);
#endif //! TEXTURE_ENABLED
	//colour.w *= gloss; // because GL is not using it either. Using GL as "ground-truth"

	float3 viewSpaceNormal = normal;

#ifdef CEL_ENABLED
	float3 worldNormal = mul(float4(normal, 0.0f), ViewInverse).xyz;
	float3 worldPos = mul(float4(In.WorldPositionDepth.xyz, 0.0f), ViewInverse).xyz;
	float3 eyeToSurface = normalize(EyePosition - worldPos);
	colour.xyz = (abs(dot(eyeToSurface, worldNormal)) < CelOutlineThickness) ? CelOutlineColor.xyz : colour.xyz + CalcLightVal(worldNormal);
#endif //! CEL_ENABLED

#ifdef LOD_BLEND
	clip(GetLODDitherValue(GET_LOD_FRAGMENT_UV(In.Position)));
#endif //! LOD_BLEND

	PSDeferredOutput Out;
	// Albedo Colour.xyz, Emissiveness
	Out.Colour = float4(colour.xyz, colour.w);//MaterialEmissiveness);
	// Normal.xyz, Gloss
	Out.NormalDepth = float4(viewSpaceNormal.xyz * 0.5f + 0.5f, colour.w);

#ifdef VELOCITY_ENABLED
	Out.Velocity = CalculateVelocity(In.VelocityData);
#endif //! VELOCITY_ENABLED

	return Out;
}


float3 EvaluateLightingDefault(DefaultVSForwardRenderOutput In, float3 worldPosition, float3 normal, float glossValue)
{
	// Lighting
	float3 lightResult = 1;	

#ifdef USE_LIGHTING
	lightResult = GlobalAmbientColor.xyz;

#ifdef SPECULAR_ENABLED
	float3 eyeDirection = normalize(worldPosition - EyePosition);
	float shininess = Shininess * glossValue;
#endif //! SPECULAR_ENABLED

	
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

#endif //! USE_LIGHTING

	return lightResult;
}


#endif

