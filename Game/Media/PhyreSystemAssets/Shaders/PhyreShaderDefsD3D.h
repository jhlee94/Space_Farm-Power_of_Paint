/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_SHADER_DEFS_H
#define PHYRE_SHADER_DEFS_H

// A list of context switches that the engine knows about.

//#define NUM_LIGHTS 3
//#define NUM_LIGHTS 1
//#define TONE_MAP_ENABLED
//#define FOG_ENABLED
//#define ZPREPASS_ENABLED
//#define SSAO_ENABLED
//#define MOTION_BLUR_ENABLED
//#define LIGHTPREPASS_ENABLED

// A list of platforms/hosts the engine might define.
//#define PS3
//#define WIN32
//#define WIN32_NVIDIA
//#define WIN32_ATI
//#define MAYA
//#define MAX
//#define LEVEL_EDITOR
//#define DCC_TOOL

// DCC tool mode - disables some context switches and e.g. shadow mapping.
#if defined(MAYA) || defined(MAX) || defined(LEVEL_EDITOR)
#define DCC_TOOL
#endif //! defined(MAYA) || defined(MAX) || defined(LEVEL_EDITOR)

// A list of light structures.

#define EXTENDED_LIGHT_TYPES

// Description:
// An empty structure used as the type for NULL/void parameters.
struct EmptyStruct
{
};

#define DECL_LIGHT_AUX_TYPES(LIGHTTYPE, SPEC_MAP, DIFF_MAP, DIFF_BUF) \
	typedef SPEC_MAP LIGHTTYPE##SpecularMapType; \
	typedef DIFF_MAP LIGHTTYPE##DiffuseMapType; \
	typedef DIFF_BUF LIGHTTYPE##DiffuseBufferType

//////////////////
// Light types. //
//////////////////

struct DirectionalLight
{
	// 6 floats
	float3					 m_direction		: LIGHTDIRECTIONWS;					// World space direction of light.
	float3					 m_colorIntensity	: LIGHTCOLORINTENSITY;				// Color and intensity of light.
};
DECL_LIGHT_AUX_TYPES(DirectionalLight, EmptyStruct, EmptyStruct, EmptyStruct);

struct PointLight
{
	// 10 floats
	float3					 m_position			: LIGHTPOSITIONWS;					// World space position of light.
	float3					 m_colorIntensity	: LIGHTCOLORINTENSITY;				// Color and intensity of light.
	float4					 m_attenuation		: LIGHTATTENUATION;					// Attenuation factors.
};
DECL_LIGHT_AUX_TYPES(PointLight, EmptyStruct, EmptyStruct, EmptyStruct);

struct SpotLight
{
	// 17 floats
	float3					m_position			: LIGHTPOSITIONWS;					// World space position of light.
	float3					m_direction			: LIGHTDIRECTIONWS;					// World space direction of light.
	float3					m_colorIntensity	: LIGHTCOLORINTENSITY;				// Color and intensity of light.
	float4					m_spotAngles		: LIGHTSPOTANGLES;					// Spot light cone angles.
	float4					m_attenuation		: LIGHTATTENUATION;					// Attenuation factors.
};
DECL_LIGHT_AUX_TYPES(SpotLight, EmptyStruct, EmptyStruct, EmptyStruct);

#ifdef EXTENDED_LIGHT_TYPES
#include "PBR/PhyreSphericalHarmonics.h"
	struct AreaDiscLight
	{
		// 14 floats
		float3					m_position			: LIGHTPOSITIONWS;				// World space position of light.
		float3					m_direction			: LIGHTDIRECTIONWS;				// World space direction of light.
		float					m_radius			: LIGHTRADIUSWS;				// World space radius of light.
		float3					m_colorIntensity	: LIGHTCOLORINTENSITY;			// Color and intensity of light.
		float4					m_attenuation		: LIGHTATTENUATION;				// Attenuation factors.
	};
	DECL_LIGHT_AUX_TYPES(AreaDiscLight, EmptyStruct, EmptyStruct, EmptyStruct);

	struct AreaSphereLight
	{
		// 11 floats
		float3					m_position			: LIGHTPOSITIONWS;				// World space position of light.
		float					m_radius			: LIGHTRADIUSWS;				// World space radius of light.
		float3					m_colorIntensity	: LIGHTCOLORINTENSITY;			// Color and intensity of light.
		float4					m_attenuation		: LIGHTATTENUATION;				// Attenuation factors.
	};
	DECL_LIGHT_AUX_TYPES(AreaSphereLight, EmptyStruct, EmptyStruct, EmptyStruct);

	struct AreaRectangleLight
	{
		// 19 floats
		float3					m_position			: LIGHTPOSITIONWS;				// World space position of light.
		float3					m_direction			: LIGHTDIRECTIONWS;				// World space direction of light.
		float3					m_halfWidth			: LIGHTHALFWIDTHWS;				// World space half width of light.
		float3					m_halfHeight		: LIGHTHALFHEIGHTWS;			// World space half height of light.
		float3					m_colorIntensity	: LIGHTCOLORINTENSITY;			// Color and intensity of light.
		float4					m_attenuation		: LIGHTATTENUATION;				// Attenuation factors.
	};
	DECL_LIGHT_AUX_TYPES(AreaRectangleLight, EmptyStruct, EmptyStruct, EmptyStruct);

	struct AreaTubeLight
	{
		// 14 floats + 1 uint to distinguish from AreaDiscLight.
		float3					m_position			: LIGHTPOSITIONWS;				// World space position of light.
		float3					m_halfWidth			: LIGHTHALFWIDTHWS;				// World space half width of light.
		float					m_radius			: LIGHTRADIUSWS;				// World space radius of light.
		float3					m_colorIntensity	: LIGHTCOLORINTENSITY;			// Color and intensity of light.
		float4					m_attenuation		: LIGHTATTENUATION;				// Attenuation factors.

		uint					m_paddingDoNotParse;								// Add a uint to distinguish this from AreaDiscLight. This is not added to the parameter buffer.
	};
	DECL_LIGHT_AUX_TYPES(AreaTubeLight, EmptyStruct, EmptyStruct, EmptyStruct);

	struct GlobalLightProbe
	{
	};
	DECL_LIGHT_AUX_TYPES(GlobalLightProbe, TextureCube<float4>, TextureCube<float4>, EmptyStruct);

	struct LocalLightProbe
	{
		// 13 floats
		float3					m_position			: LIGHTPOSITIONWS;				// World space position of light.
		float					m_radius			: LIGHTRADIUSWS;				// Positive for sphere, negative for box.
		float3					m_halfWidth			: LIGHTHALFWIDTHWS;				// World space size and orientation of X axis of box.
		float3					m_halfHeight		: LIGHTHALFHEIGHTWS;			// World space size and orientation of Y axis of box.
		float3					m_halfDepth			: LIGHTHALFDEPTHWS;				// World space size and orientation of Z axis of box.
	};
	DECL_LIGHT_AUX_TYPES(LocalLightProbe, TextureCube<float4>, TextureCube<float4>, EmptyStruct);

	struct RadianceVolume
	{
		// 12 floats + 1 uint
		float3					m_position			: LIGHTPOSITIONWS;				// World space position of light.
		float3					m_halfWidth			: LIGHTHALFWIDTHWS;				// World space half width of radiance volume.
		float3					m_halfHeight		: LIGHTHALFHEIGHTWS;			// World space half height of radiance volume.
		float3					m_halfDepth			: LIGHTHALFDEPTHWS;				// World space half depth of radiance volume.
		uint					m_log2ProbeRes		: LIGHTLOG2PROBERES;			// The log2 probe resolution (0=1, 1=2, 2=4, 3=8, 4=16, etc...)
	};
	DECL_LIGHT_AUX_TYPES(RadianceVolume, EmptyStruct, EmptyStruct, StructuredBuffer<SHOrder2Float4>);

#endif //! EXTENDED_LIGHT_TYPES

///////////////////////
// Shadow map types. //
///////////////////////

struct PCFShadowMap
{
	float4x4 m_shadowTransform	: SHADOWTRANSFORM;
};

struct CascadedShadowMap
{
	float3x4 m_split0Transform	: SHADOWTRANSFORMSPLIT0;
	float3x4 m_split1Transform	: SHADOWTRANSFORMSPLIT1;
	float3x4 m_split2Transform	: SHADOWTRANSFORMSPLIT2;
	float3x4 m_split3Transform	: SHADOWTRANSFORMSPLIT3;
	float4 m_splitDistances		: SHADOWSPLITDISTANCES;
};

struct CombinedCascadedShadowMap
{
	float4x4 m_split0Transform	: SHADOWTRANSFORMSPLIT0;
	float4x4 m_split1Transform	: SHADOWTRANSFORMSPLIT1;
	float4x4 m_split2Transform	: SHADOWTRANSFORMSPLIT2;
	float4x4 m_split3Transform	: SHADOWTRANSFORMSPLIT3;
	float4 m_splitDistances		: SHADOWSPLITDISTANCES;
};

// Output structure for deferred lighting fragment shader.
struct PSDeferredOutput
{
	float4 Colour : FRAG_OUTPUT_COLOR0;
	float4 NormalDepth : FRAG_OUTPUT_COLOR1;
#if VELOCITY_ENABLED
	float2 Velocity : FRAG_OUTPUT_COLOR3;
#endif //! VELOCITY_ENABLED
};

#endif //! PHYRE_SHADER_DEFS_H