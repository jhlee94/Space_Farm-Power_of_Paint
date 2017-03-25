/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Enabling lighting for the terrain mesh
#define LIGHTING_ENABLED
// The maximum number of lights for this shader
#define MAX_NUM_LIGHTS 3
// Enabling specular highlights for the terrain mesh
#define SPECULAR_ENABLED
// Enabling shadow casting from the terrain mesh
//#define CAST_SHADOWS
// Enabling shadow map lookups for the terrain mesh
#define RECEIVE_SHADOWS
// Enabling better normals calculations
//#define BETTER_NORMALS

// Context switches
bool PhyreContextSwitches
<
	string	ContextSwitchNames[]		= { "NUM_LIGHTS", "TEXTURING_ENABLED", "MIP_DEBUGGING", "SPLATMAP_DEBUGGING", "VELOCITY_ENABLED" };
	int		MaxNumLights				= MAX_NUM_LIGHTS;
	string	SupportedLightTypes[]		= { "DirectionalLight", "PointLight", "SpotLight" };
	string	SupportedShadowTypes[]		= { "PCFShadowMap", "CascadedShadowMap", "CombinedCascadedShadowMap" };
	int		NumSupportedShaderLODLevels	= 1;
>;
#define DEFINED_CONTEXT_SWITCHES

#include "PhyreShaderPlatform.h"
#include "PhyreDefaultShaderSharedCodeD3D.h"
#include "PhyreTerrainSharedFx.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Terrain brush.

uint				ToolBrushEnabled;
uint				ToolBrushIsParameterized;
float4				ToolBrushColor;
float				ToolBrushOpacity;
Texture2D			ToolBrushTexture;
float				ToolBrushTextureSize;
float2				ToolBrushPosition;
float				ToolBrushMaxSize;
float				ToolBrushSize;
float				ToolBrushOrientation;
float				ToolBrushFallOff;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Terrain sampler states.

SamplerState MeshSamplerState
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};

SamplerState PaletteSamplerState
{
	Filter = ANISOTROPIC;
	AddressU = Wrap;
	AddressV = Wrap;
	MaxAnisotropy = 4;
};

SamplerState ProcSamplerState
{
	Filter = ANISOTROPIC;
	AddressU = Clamp;
	AddressV = Clamp;
	MaxAnisotropy = 4;
};

SamplerState ToolBrushTextureSamplerState
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};

// Description:
// The colors used for coloring the splatmap output when debugging.
static const float4 s_splatmapColors[] =
{
	float4(1.0f, 0.0f, 0.0f, 1.0f),			// Red
	float4(0.0f, 1.0f, 0.0f, 1.0f),			// Green
	float4(0.0f, 0.0f, 1.0f, 1.0f),			// Blue

	float4(1.0f, 0.0f, 1.0f, 1.0f),			// Magenta
	float4(1.0f, 0.498f, 0.054f, 1.0f),		// Dark Green
	float4(0.0f, 1.0f, 1.0f, 1.0f),			// Cyan

	float4(1.0f, 0.415f, 0.0f, 1.0f),		// Orange
	float4(1.0f, 1.0f, 0.0f, 1.0f),			// Yellow
	float4(0.0f, 0.58f, 1.0f, 1.0f),		// Light Blue

	float4(1.0f, 0.498f, 0.713f, 1.0f),		// Salmon
	float4(0.356f, 0.498f, 0.0f, 1.0f),		// Kaki
	float4(0.247f, 0.392f, 0.498f, 1.0f),	// Steel Blue

	float4(0.498f, 0.247f, 0.247f, 1.0f),	// Brown
	float4(0.713f, 1.0f, 0.0f, 1.0f),		// Pale Green
	float4(0.698f, 0.0f, 1.0f, 1.0f),		// Purple

	float4(1.0f, 0.498f, 0.713f, 1.0f),		// Pink
	float4(0.247f, 0.498f, 0.384f, 1.0f),	// Bottle Green
	float4(0.839f, 0.498f, 1.0f, 1.0f)		// 'Mauve'
};

// Description:
// The value for 1 / sqrt(2).
#define ONE_OVER_SQRT_2	0.707107f

// Description:
// Extracts the first texture index for a given splat value.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted first texture index.
#define SPLAT_INDEX0(SPLAT)			\
	(float((((SPLAT).x) & 0xF8) >> 3))

// Description:
// Extracts the first texture index for a given splat value and warps it for debug coloring.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted first texture index.
#define SPLAT_INDEX0_WARPED(SPLAT)	\
	(((((SPLAT).x) & 0xF8) >> 3) % 18/*PHYRE_STATIC_ARRAY_SIZE(s_splatmapColors)*/)

// Description:
// Extracts the second texture index for a given splat value.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted second texture index.
#define SPLAT_INDEX1(SPLAT)			\
	(float((((SPLAT).z) & 0xF8) >> 3))

// Description:
// Extracts the second texture index for a given splat value and warps it for debug coloring.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted second texture index.
#define SPLAT_INDEX1_WARPED(SPLAT)	\
	(((((SPLAT).z) & 0xF8) >> 3) % 18/*PHYRE_STATIC_ARRAY_SIZE(s_splatmapColors)*/)

// Description:
// Extracts the first weight value for a given splat value.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted first weight value.
#define SPLAT_WEIGHT0(SPLAT)		\
	(float(((((SPLAT).x) & 0x7) << 8) | (((SPLAT).y) & 0xFF)) / 2047.0f)

// Description:
// Extracts the second weight value for a given splat value.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted second weight value.
#define SPLAT_WEIGHT1(SPLAT)		\
	(float(((((SPLAT).z) & 0x7) << 8) | (((SPLAT).w) & 0xFF)) / 2047.0f)

#ifdef __ORBIS__

// Description:
// Returns the computed level of detail.
// Arguments:
// s - The sampler state to be used.
// loc - The location to be sampled.
// Returns:
// The calculated level of detail.
#define CalculateLevelOfDetail(s, loc)	\
		GetLOD(s, loc)

#endif //! __ORBIS__

// Description:
// Evaluates the content of the splatmap for the given splat coordinates.
// Arguments:
// maskUv - The UVs for the splat texture.
// Returns:
// The splatmap content.
float4 EvaluateSplatSample(in float2 maskUv)
{
	const float2 interp = frac(maskUv);

	// Read out the splatmap control points
	const uint4 mask0 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(0, 0), 0)) * 255.0f),
				mask1 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(0, 1), 0)) * 255.0f),
				mask2 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(1, 0), 0)) * 255.0f),
				mask3 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(1, 1), 0)) * 255.0f);

	// Returns the colored output for debugging
	return
		SPLAT_WEIGHT0(mask0) * (1.0f - interp.x) * (1.0f - interp.y) * s_splatmapColors[SPLAT_INDEX0_WARPED(mask0)] +
		SPLAT_WEIGHT1(mask0) * (1.0f - interp.x) * (1.0f - interp.y) * s_splatmapColors[SPLAT_INDEX1_WARPED(mask0)] +
		SPLAT_WEIGHT0(mask1) * (1.0f - interp.x) * interp.y          * s_splatmapColors[SPLAT_INDEX0_WARPED(mask1)] +
		SPLAT_WEIGHT1(mask1) * (1.0f - interp.x) * interp.y          * s_splatmapColors[SPLAT_INDEX1_WARPED(mask1)] +
		SPLAT_WEIGHT0(mask2) * interp.x          * (1.0f - interp.y) * s_splatmapColors[SPLAT_INDEX0_WARPED(mask2)] +
		SPLAT_WEIGHT1(mask2) * interp.x          * (1.0f - interp.y) * s_splatmapColors[SPLAT_INDEX1_WARPED(mask2)] +
		SPLAT_WEIGHT0(mask3) * interp.x          * interp.y          * s_splatmapColors[SPLAT_INDEX0_WARPED(mask3)] +
		SPLAT_WEIGHT1(mask3) * interp.x          * interp.y          * s_splatmapColors[SPLAT_INDEX1_WARPED(mask3)];
}

// Description:
// Evaluates the composited sample for the given splat and procedural texture coordinates.
// Arguments:
// maskUv - The UVs for the splat texture.
// procUv - The UVs for the procedural virtual texture.
// Returns:
// The composited texture sample.
float2x4 EvaluateTextureSample(in float2 maskUv, in float2 procUv)
{
	uint2 indices = uint2(0, 0);
	float2 weights = float2(-1.0f, -1.0f);

	// Retrieve the indices of the two texture sources to be used
	{
		// Read out the splatmap
		const float2 interp = frac(maskUv);
		const uint4 mask0 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(0, 0), 0)) * 255.0f),
					mask1 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(0, 1), 0)) * 255.0f),
					mask2 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(1, 0), 0)) * 255.0f),
					mask3 = uint4(MaskPRTextureSampler.Load(int3(int2(maskUv) + int2(1, 1), 0)) * 255.0f);

		// Allocate and initialize array for weight accumulation
		float weightAccumulator[32];
		{
			[unroll]
			for(uint i = 0; i < 32; ++i)
				weightAccumulator[i] = 0.0f;
		}

		// Accumulate the weights
		weightAccumulator[SPLAT_INDEX0(mask0)] += SPLAT_WEIGHT0(mask0) * (1.0f - interp.x) * (1.0f - interp.y);
		weightAccumulator[SPLAT_INDEX1(mask0)] += SPLAT_WEIGHT1(mask0) * (1.0f - interp.x) * (1.0f - interp.y);
		weightAccumulator[SPLAT_INDEX0(mask1)] += SPLAT_WEIGHT0(mask1) * (1.0f - interp.x) * interp.y;
		weightAccumulator[SPLAT_INDEX1(mask1)] += SPLAT_WEIGHT1(mask1) * (1.0f - interp.x) * interp.y;
		weightAccumulator[SPLAT_INDEX0(mask2)] += SPLAT_WEIGHT0(mask2) * interp.x          * (1.0f - interp.y);
		weightAccumulator[SPLAT_INDEX1(mask2)] += SPLAT_WEIGHT1(mask2) * interp.x          * (1.0f - interp.y);
		weightAccumulator[SPLAT_INDEX0(mask3)] += SPLAT_WEIGHT0(mask3) * interp.x          * interp.y;
		weightAccumulator[SPLAT_INDEX1(mask3)] += SPLAT_WEIGHT1(mask3) * interp.x          * interp.y;

		// Retrieve the two most important samples
		{
			[unroll]
			for(uint i = 0; i < 32; ++i)
			{
				const float weight = weightAccumulator[i];
				if(weight > weights.x)
				{
					indices.y = indices.x;
					weights.y = weights.x;
					indices.x = i;
					weights.x = weight;
				}
				else if(weight > weights.y)
				{
					indices.y = i;
					weights.y = weight;
				}
			}
		}

		// Fixup the weights
		weights += (1.0f - weights.x - weights.y) * 0.5f;
	}

	// Composite the texture sources
	return float2x4(
		weights.x * PaletteTextureArray0.Sample(PaletteSamplerState, float3(procUv.xy, indices.x)) +
		weights.y * PaletteTextureArray0.Sample(PaletteSamplerState, float3(procUv.xy, indices.y)),
		weights.x * PaletteTextureArray1.Sample(PaletteSamplerState, float3(procUv.xy, indices.x)) +
		weights.y * PaletteTextureArray1.Sample(PaletteSamplerState, float3(procUv.xy, indices.y)));
}

// Description:
// Gets the color, normal, and gloss information for the terrain mesh at the current fragment.
// Arguments:
// In - The interpolated fragment attributes.
// color - The output color value.
// normal - The output normal vector.
// gloss - The output gloss value.
void GetTerrainColorAndNormalAndGloss(in TerrainRenderVsOutput In, out float4 color, out float3 normal, out float gloss)
{
	// Initialize the color value
	color = BlockColor;

	// Calculate the normal at this point
	{
		float4 heightSamples;
		float dimensionScaleLoddedInverse = 1.0f / (float)(1 << (uint)MeshPRTextureSamplerPhysicalDesc.z);

		// Fetch the height samples
		heightSamples.x = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2( 0.0f, -1.0f) / MeshPRTextureSamplerPhysicalDesc.xy).x;
		heightSamples.y = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2(-1.0f,  0.0f) / MeshPRTextureSamplerPhysicalDesc.xy).x;
		heightSamples.z = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2( 1.0f,  0.0f) / MeshPRTextureSamplerPhysicalDesc.xy).x;
		heightSamples.w = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2( 0.0f,  1.0f) / MeshPRTextureSamplerPhysicalDesc.xy).x;

		// Calculate the non-normalized normal vector
		normal = float3(
			EvaluateHeight(heightSamples[1] - heightSamples[2]) * dimensionScaleLoddedInverse,
			2.0f,
			EvaluateHeight(heightSamples[0] - heightSamples[3]) * dimensionScaleLoddedInverse);

#ifdef BETTER_NORMALS
		// Fetch some more height samples
		heightSamples.x = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2( ONE_OVER_SQRT_2, -ONE_OVER_SQRT_2) / MeshPRTextureSamplerPhysicalDesc.xy).x;
		heightSamples.y = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2(-ONE_OVER_SQRT_2, -ONE_OVER_SQRT_2) / MeshPRTextureSamplerPhysicalDesc.xy).x;
		heightSamples.z = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2( ONE_OVER_SQRT_2,  ONE_OVER_SQRT_2) / MeshPRTextureSamplerPhysicalDesc.xy).x;
		heightSamples.w = MeshPRTextureSampler.Sample(MeshSamplerState, In.Uv + float2(-ONE_OVER_SQRT_2,  ONE_OVER_SQRT_2) / MeshPRTextureSamplerPhysicalDesc.xy).x;

		// Calculate an extra normal vector for better shading
		normal += float3(
			EvaluateHeight(heightSamples[1] - heightSamples[2]) * dimensionScaleLoddedInverse,
			2.0f,
			EvaluateHeight(heightSamples[0] - heightSamples[3]) * dimensionScaleLoddedInverse);
#endif //! BETTER_NORMALS

		// Normalize the normal vector
		normal = EvaluateStandardNormal(normal);
	}

#ifdef TEXTURING_ENABLED
#ifndef SPLATMAP_DEBUGGING
	{
		// Fetch the texture information for the current pixel
		float2x4 textureInformation;
		{
			// Read out the composite texture cache
			const float mipLevel = PaletteTextureArray0.CalculateLevelOfDetail(PaletteSamplerState, In.Uv2);
			{
				const float mipLevelClampedAndRemapped = min(max(mipLevel - NearToFarMipBias, In.MipLevel) - MinMipLevel, float(MipLevelDelta)),
							mipLevelBlendFactor = frac(mipLevelClampedAndRemapped);
				const uint levelHigh = uint(mipLevelClampedAndRemapped),
						   levelLow = min(levelHigh + 1, MipLevelDelta);
				const float2 uvHigh = (1.0f + 2.0f * (In.Uv1 * ProcPRTextureSamplerVirtualToPhysical[levelHigh].zw + ProcPRTextureSamplerVirtualToPhysical[levelHigh].xy)) / (2.0f * ProcPRTextureSamplerPhysicalDesc),
							 uvLow  = (1.0f + 2.0f * (In.Uv1 * ProcPRTextureSamplerVirtualToPhysical[levelLow ].zw + ProcPRTextureSamplerVirtualToPhysical[levelLow ].xy)) / (2.0f * ProcPRTextureSamplerPhysicalDesc);
				textureInformation =
					float2x4(ProcPRTextureSampler.Sample(ProcSamplerState, uvHigh), ProcTextureSampler.Sample(ProcSamplerState, uvHigh)) * (1.0f - mipLevelBlendFactor) +
					float2x4(ProcPRTextureSampler.Sample(ProcSamplerState, uvLow ), ProcTextureSampler.Sample(ProcSamplerState, uvLow )) * mipLevelBlendFactor;
			}

			// Super-branching-power!
			if(DepthBias + In.WorldPositionDepth.w < NearMaterialDistanceThreshold + 1.0f)
			{
				const float directSplatSampleWeight = clamp(((NearMaterialDistanceThreshold - In.WorldPositionDepth.w) / NearMaterialDistanceThreshold) * 2.0f, 0.0f, 1.0f);
				textureInformation *= 1.0f - directSplatSampleWeight;
				textureInformation += directSplatSampleWeight * EvaluateTextureSample(In.Uv3, In.Uv2);
			}
		}

		// Update the color information
		color *= float4(textureInformation._m00_m01_m02, 1.0f);

		// Calculate the bumped normal according to the normal map
		{
			const float3 tempTangent = float3(1.0f, 0.0f, 0.0f),
						 tangent = normalize(tempTangent - dot(tempTangent, normal) * normal),
						 bitangent = cross(tangent, normal);
			const float3x3 tbnMatrix = float3x3(tangent, bitangent, normal);
			normal = EvaluateStandardNormal(mul(textureInformation._m03_m11_m13 * 2.0f - 1.0f, tbnMatrix));
		}

		// Output the gloss value for this fragment
		gloss = textureInformation._m10;
	}
#ifdef MIP_DEBUGGING
	{
		// Visualize the mip transitioning for debugging purposes
		const float mipLevel = PaletteTextureArray0.CalculateLevelOfDetail(PaletteSamplerState, In.Uv2);
		float mipLevelClamped = min(max(mipLevel - NearToFarMipBias, In.MipLevel) - MinMipLevel, float(MipLevelDelta)) + MinMipLevel + NearToFarMipBias;
		if(DepthBias + In.WorldPositionDepth.w < NearMaterialDistanceThreshold + 1.0f)
		{
			const float directSplatSampleWeight = clamp(((NearMaterialDistanceThreshold - In.WorldPositionDepth.w) / NearMaterialDistanceThreshold) * 2.0f, 0.0f, 1.0f);
			mipLevelClamped *= 1.0f - directSplatSampleWeight;
			mipLevelClamped += directSplatSampleWeight * PaletteTextureArray0.CalculateLevelOfDetail(PaletteSamplerState, In.Uv2);
		}
		color = s_splatmapColors[uint(floor(mipLevelClamped)) % 18] * (1.0f - frac(mipLevelClamped)) + s_splatmapColors[uint(ceil(mipLevelClamped)) % 18] * frac(mipLevelClamped);
		gloss = 0.0f;
	}
#endif //! MIP_DEBUGGING
#else //! SPLATMAP_DEBUGGING
	{
		// Output the splatmap content
		color = EvaluateSplatSample(In.Uv3);

		// Disable any glossy reflection
		gloss = 0.0f;
	}
#endif //! SPLATMAP_DEBUGGING
#else //! TEXTURING_ENABLED
	{
		// Make sure to initialize the gloss value to avoid shader compilation errors
		gloss = 0.0f;
	}
#endif //! TEXTURING_ENABLED
}

float2x2 RotationMatrix(float rotation)
{
	float c = cos(rotation);
	float s = sin(rotation);

	return float2x2(c, -s, s ,c);
}

float4 RenderToolBrush(TerrainRenderVsOutput In, float4 shadingResult)
{
	float4	brushPos = float4(ToolBrushPosition.x, 0.0f, ToolBrushPosition.y, 0.0f);
	float4 	brushTeint = lerp(float4(ToolBrushColor.r + 0.15f, ToolBrushColor.g + 0.15f, ToolBrushColor.b + 0.15f, 1.0f), float4(ToolBrushColor.r - 0.15f, ToolBrushColor.g - 0.15f, ToolBrushColor.b - 0.15f, 1.0f), (cos(time * 4.0f) + 1.0f) / 2.0f);
			brushTeint = lerp(brushTeint, shadingResult, 1.0f - ToolBrushOpacity);
	float4 	worldPos = float4(In.LocalPosition.x, 0.0f, In.LocalPosition.z, 0.0f);
	float 	brushRadius = ToolBrushSize * 0.5f;
	float 	dist = distance(brushPos, worldPos);

	if(ToolBrushIsParameterized)
	{
		// Parameterized brush
		if((brushRadius - dist) < lerp(0.01f, 1.0f, ToolBrushSize / ToolBrushMaxSize) && dist < brushRadius)
			shadingResult = float4(1.0f, 1.0f, 1.0f, 1.0f);
		else
		{
			float sat = saturate(dist / brushRadius);
			if(dist < brushRadius * (1.0f - ToolBrushFallOff))
				sat = 0.0f;
			else
			{
				dist = dist - brushRadius * (1.0f - ToolBrushFallOff);
				brushRadius = brushRadius * ToolBrushFallOff;
				sat = saturate(dist / brushRadius);
			}
			shadingResult = lerp(brushTeint, shadingResult, sat);
		}
	}
	else
	{
		// Textured brush
		if(worldPos.x >= (brushPos.x - brushRadius) && worldPos.x < (brushPos.x + brushRadius) &&
		   worldPos.z >= (brushPos.z - brushRadius) && worldPos.z < (brushPos.z + brushRadius))
		{
			float2 brushUV = float2(0.0f, 0.0f);
			float  brushRadiusRatio = 0.5f;
			if(worldPos.x >= brushPos.x && worldPos.z < brushPos.z)
				brushUV = float2(distance(brushPos.x, worldPos.x) / brushRadius * brushRadiusRatio + 0.5f, distance(brushPos.z, worldPos.z) / brushRadius * brushRadiusRatio + 0.5f);
			else if(worldPos.x < brushPos.x && worldPos.z < brushPos.z)
				brushUV = float2(1.0f - distance(brushPos.x, worldPos.x) / brushRadius * brushRadiusRatio - 0.5f, distance(brushPos.z, worldPos.z) / brushRadius * brushRadiusRatio + 0.5f);
			else if(worldPos.x >= brushPos.x && worldPos.z >= brushPos.z)
				brushUV = float2(distance(brushPos.x, worldPos.x) / brushRadius * brushRadiusRatio + 0.5f, 1.0f - distance(brushPos.z, worldPos.z) / brushRadius * brushRadiusRatio - 0.5f);
			else if(worldPos.x < brushPos.x && worldPos.z >= brushPos.z)
				brushUV = float2(1.0f - distance(brushPos.x, worldPos.x) / brushRadius * brushRadiusRatio - 0.5f, 1.0f - distance(brushPos.z, worldPos.z) / brushRadius * brushRadiusRatio - 0.5f);

			float2 rotatedTexcoord = brushUV;
			rotatedTexcoord -= float2(0.5f, 0.5f);
			rotatedTexcoord = mul(rotatedTexcoord, RotationMatrix(ToolBrushOrientation * 3.14159265f / 180.0f));
			rotatedTexcoord += float2(0.5f, 0.5f);
			brushUV = rotatedTexcoord;

			float4 brushColor = ToolBrushTexture.SampleLevel(ToolBrushTextureSamplerState, brushUV, 0.0f);
			shadingResult = lerp(brushTeint, shadingResult, brushColor);
		}
	}

	return shadingResult;
}

struct PS_OUTPUT
{
	float4 Colour	: FRAG_OUTPUT_COLOR0;
#ifdef VELOCITY_ENABLED
	float2 Velocity	: FRAG_OUTPUT_COLOR1;
#endif //! VELOCITY_ENABLED
};

PS_OUTPUT TerrainRenderPs(TerrainRenderVsOutput In)
{
	// Fetch the shading information
	float gloss;
	float3 normal;
	float4 shadingResult;
	GetTerrainColorAndNormalAndGloss(In, shadingResult, normal, gloss);

	// Calculate the lighting value
	{
		DefaultVSForwardRenderOutput In2;
		In2.WorldPositionDepth.w = In.WorldPositionDepth.w;
		shadingResult *= float4(EvaluateLightingDefault(In2, In.WorldPositionDepth.xyz, normal, gloss), 1.0f);
	}

	// Tools brush support
	if(ToolBrushEnabled)
		shadingResult = RenderToolBrush(In, shadingResult);

	PS_OUTPUT Out;
	Out.Colour = shadingResult;

#ifdef VELOCITY_ENABLED
	Out.Velocity = CalculateVelocity(In.VelocityData);
#endif

	return Out;
}

PSDeferredOutput TerrainDeferredRenderPs(TerrainRenderVsOutput In)
{
	PSDeferredOutput Out;

	// Fetch the shading information
	float gloss;
	float3 normal;
	float4 shadingResult;
	GetTerrainColorAndNormalAndGloss(In, shadingResult, normal, gloss);

	// Tools brush support
	if(ToolBrushEnabled)
		shadingResult = RenderToolBrush(In, shadingResult);

	// Populate the output structure
	Out.NormalDepth = float4(mul(float4(normal, 0.0f), View).xyz * 0.5f + 0.5f, gloss); // fx implemetation reads gloss value from here.
	Out.Colour = float4(shadingResult.xyz, gloss);

#ifdef VELOCITY_ENABLED
	Out.Velocity = CalculateVelocity(In.VelocityData);
#endif

	return Out;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Technique declarations.

RasterizerState CullRasterState
{
	CullMode = Front;
};

#ifndef __ORBIS__

technique11 TerrainRender
<
	string PhyreRenderPass = "Opaque";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "MIP_DEBUGGING", "SPLATMAP_DEBUGGING" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_5_0, TerrainRenderVs() ) );
		SetPixelShader( CompileShader( ps_5_0, TerrainRenderPs() ) );

		SetRasterizerState( CullRasterState );
	}
}

#ifdef CAST_SHADOWS

technique11 TerrainShadow
<
	string PhyreRenderPass = "Shadow";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "TEXTURING_ENABLED", "MIP_DEBUGGING", "SPLATMAP_DEBUGGING", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { "VELOCITY_ENABLED" };
>
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_5_0, TerrainRenderVs() ) );

		SetRasterizerState( CullRasterState );
	}
}

#endif //! CAST_SHADOWS

technique11 TerrainDeferredRender
<
	string PhyreRenderPass = "DeferredRender";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "MIP_DEBUGGING", "SPLATMAP_DEBUGGING" };
	string FpIgnoreContextSwitches[] = { "NUM_LIGHTS" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_5_0, TerrainRenderVs() ) );
		SetPixelShader( CompileShader( ps_5_0, TerrainDeferredRenderPs() ) );

		SetRasterizerState( CullRasterState );
	}
}

#endif //! __ORBIS__
