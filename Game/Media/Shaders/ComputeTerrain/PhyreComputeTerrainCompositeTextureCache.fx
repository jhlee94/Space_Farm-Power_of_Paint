/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Enabling splatmap debugging
//#define SPLATMAP_DEBUGGING

#include "../PhyreShaderPlatform.h"
#include "PhyreComputeTerrainCompressDXT.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Terrain composite texture cache.

RWTexture2D<uint4>		ProceduralTexture;			// The physical representation for the rendered PVT.
uint2					ProceduralTextureOffset;	// The offset for writing to the rendered PVT.
Texture2D				MaskPRTexture;				// The PRT sampler for the virtual splatmap.
float2					MaskPRTextureOffset;		// The offset for reading from the mask texture.
uint2					MaxCompositeCoordinates;	// The maximum texture coordinates when compositing.
float					UpsamplingFactor;			// The upsampling factor for the procedural texture.
Texture2DArray			PaletteTextureArray;		// The texture array containing the terrain palette.
float3					VirtualCoordinates;			// The virtual coordinates for the page top-left corner.
float2					VirtualDimensions;			// The dimensions for the procedural virtual texture.
float2					VirtualTileCounts;			// The counts for tiling the procedural virtual texture.

SamplerState PaletteSamplerState
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Wrap;
	AddressV = Wrap;
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
// Extracts the first texture index for a given splat value.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted first texture index.
#define SPLAT_INDEX0(SPLAT)		\
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
#define SPLAT_INDEX1(SPLAT)		\
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
#define SPLAT_WEIGHT0(SPLAT)	\
	(float(((((SPLAT).x) & 0x7) << 8) | (((SPLAT).y) & 0xFF)) / 2047.0f)

// Description:
// Extracts the second weight value for a given splat value.
// Arguments:
// SPLAT - The splat value.
// Returns:
// The extracted second weight value.
#define SPLAT_WEIGHT1(SPLAT)	\
	(float(((((SPLAT).z) & 0x7) << 8) | (((SPLAT).w) & 0xFF)) / 2047.0f)

// Description:
// Evaluates the content of the splatmap for the given splat coordinates.
// Arguments:
// maskUv - The UVs for the splat texture.
// Returns:
// The splatmap content.
float4 EvaluateSplatSample(in float2 maskUv)
{
	const float2 interp = frac(maskUv);

	// Read out the splatmap
	const uint4 mask0 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(0, 0), 0)) * 255.0f),
				mask1 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(0, 1), 0)) * 255.0f),
				mask2 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(1, 0), 0)) * 255.0f),
				mask3 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(1, 1), 0)) * 255.0f);

	// Composite the splatting information
	return SPLAT_WEIGHT0(mask0) * (1.0f - interp.x) * (1.0f - interp.y) * s_splatmapColors[SPLAT_INDEX0_WARPED(mask0)] +
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
float4 EvaluateTextureSample(in float2 maskUv, in float3 procUv)
{
	const float2 interp = frac(maskUv);

	// Read out the splatmap
	const uint4 mask0 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(0, 0), 0)) * 255.0f),
				mask1 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(0, 1), 0)) * 255.0f),
				mask2 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(1, 0), 0)) * 255.0f),
				mask3 = uint4(MaskPRTexture.Load(int3(int2(maskUv) + int2(1, 1), 0)) * 255.0f);

	// Composite the texture sources
	return SPLAT_WEIGHT0(mask0) * (1.0f - interp.x) * (1.0f - interp.y) * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX0(mask0)), procUv.z) +
		   SPLAT_WEIGHT1(mask0) * (1.0f - interp.x) * (1.0f - interp.y) * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX1(mask0)), procUv.z) +
		   SPLAT_WEIGHT0(mask1) * (1.0f - interp.x) * interp.y          * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX0(mask1)), procUv.z) +
		   SPLAT_WEIGHT1(mask1) * (1.0f - interp.x) * interp.y          * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX1(mask1)), procUv.z) +
		   SPLAT_WEIGHT0(mask2) * interp.x          * (1.0f - interp.y) * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX0(mask2)), procUv.z) +
		   SPLAT_WEIGHT1(mask2) * interp.x          * (1.0f - interp.y) * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX1(mask2)), procUv.z) +
		   SPLAT_WEIGHT0(mask3) * interp.x          * interp.y          * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX0(mask3)), procUv.z) +
		   SPLAT_WEIGHT1(mask3) * interp.x          * interp.y          * PaletteTextureArray.SampleLevel(PaletteSamplerState, float3(procUv.xy, SPLAT_INDEX1(mask3)), procUv.z);
}

[numthreads(8, 8, 1)]
void TerrainCompositeTextureCacheCs(uint3 In : SV_DispatchThreadID)
{
	const float2 xy = float2(min(In.xy, MaxCompositeCoordinates));

	// Calculate textures read coordinates
	const float maskUvIncrement = 1.0f / UpsamplingFactor;
	const float2 maskUv = MaskPRTextureOffset + 4.0f * maskUvIncrement * xy;
	const float procUvIncrement = 1.0f / VirtualDimensions.x * VirtualTileCounts.x * float(1 << (uint)VirtualCoordinates.z);
	const float3 procUv = float3(
		(1.0f + 2.0f * VirtualCoordinates.xy) / (2.0f * VirtualDimensions.x) * VirtualTileCounts.x +
		4.0f * procUvIncrement * xy,
		VirtualCoordinates.z);

	// Read out a 4x4 block worth of pixel data
	const float4 block[16] =
	{
#ifdef SPLATMAP_DEBUGGING
		// First column
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(0.0f, 0.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(1.0f, 0.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(2.0f, 0.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(3.0f, 0.0f)),
		// Second column
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(0.0f, 1.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(1.0f, 1.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(2.0f, 1.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(3.0f, 1.0f)),
		// Third column
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(0.0f, 2.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(1.0f, 2.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(2.0f, 2.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(3.0f, 2.0f)),
		// Fourth column
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(0.0f, 3.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(1.0f, 3.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(2.0f, 3.0f)),
		EvaluateSplatSample(maskUv + maskUvIncrement * float2(3.0f, 3.0f))
#else //! SPLATMAP_DEBUGGING
		// First column
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(0.0f, 0.0f), procUv + procUvIncrement * float3(0.0f, 0.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(1.0f, 0.0f), procUv + procUvIncrement * float3(1.0f, 0.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(2.0f, 0.0f), procUv + procUvIncrement * float3(2.0f, 0.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(3.0f, 0.0f), procUv + procUvIncrement * float3(3.0f, 0.0f, 0.0f)),
		// Second column
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(0.0f, 1.0f), procUv + procUvIncrement * float3(0.0f, 1.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(1.0f, 1.0f), procUv + procUvIncrement * float3(1.0f, 1.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(2.0f, 1.0f), procUv + procUvIncrement * float3(2.0f, 1.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(3.0f, 1.0f), procUv + procUvIncrement * float3(3.0f, 1.0f, 0.0f)),
		// Third column
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(0.0f, 2.0f), procUv + procUvIncrement * float3(0.0f, 2.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(1.0f, 2.0f), procUv + procUvIncrement * float3(1.0f, 2.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(2.0f, 2.0f), procUv + procUvIncrement * float3(2.0f, 2.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(3.0f, 2.0f), procUv + procUvIncrement * float3(3.0f, 2.0f, 0.0f)),
		// Fourth column
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(0.0f, 3.0f), procUv + procUvIncrement * float3(0.0f, 3.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(1.0f, 3.0f), procUv + procUvIncrement * float3(1.0f, 3.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(2.0f, 3.0f), procUv + procUvIncrement * float3(2.0f, 3.0f, 0.0f)),
		EvaluateTextureSample(maskUv + maskUvIncrement * float2(3.0f, 3.0f), procUv + procUvIncrement * float3(3.0f, 3.0f, 0.0f))
#endif //! SPLATMAP_DEBUGGING
	};

	// Write out the encoded block
	ProceduralTexture[uint2(xy) + ProceduralTextureOffset] = uint4(CompressBlock_Alpha(block), CompressBlock_Color(block));
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Technique declarations.

#ifndef __ORBIS__

technique11 TerrainCompositeTextureCache
<
	string PhyreRenderPass = "TerrainCompositeTextureCache";
>
{
	pass pass0
	{
		SetComputeShader( CompileShader( cs_5_0, TerrainCompositeTextureCacheCs() ) );
	}
}

#endif //! __ORBIS__
