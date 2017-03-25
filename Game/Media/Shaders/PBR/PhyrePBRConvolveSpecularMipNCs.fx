/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Shaders for management of PBR. These include setup shaders executed once, and per frame shaders for rendering.

// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
#define DEFINED_CONTEXT_SWITCHES 1

#include "../PhyreShaderPlatform.h"
#include "../PhyreShaderDefsD3D.h"
#include "../PhyreDefaultShaderSharedCodeD3D.h"
#include "PhyrePbrShared.h"

// Parameters for the various shaders.

float roughness;											// The roughness for which to pre-filter the lightprobe.
float preFilterGain;										// The gain to use whilst prefiltering.
TextureCube <float4> lightprobe;							// The lightprobe texture to pre-filter.
RWTexture2D<float4> rwCubemapFace;						// The mip-face of a cubemap.
int rwCubemapFaceRes;									// The resolution of the cubemap faces.

#define SAMPLE_BATCH_SIZE 128
groupshared float4 LdsFloat4Buffer128[SAMPLE_BATCH_SIZE];				// Generate samples here and then use to sample faces.
groupshared float LdsFloatBuffer128[SAMPLE_BATCH_SIZE];			// 32 threads * 2 pixels * 2 faces

sampler BilinearFilterSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
	AddressU = Wrap;
	AddressV = Wrap;
};

// Description:
// Get a Hammersley point.
// Arguments:
// num - The index of the hammersley point to get.
// count - The size of the hammersley point set from which to get the point. Should be a power of two.
// Returns:
// The hammersley point.
static uint2 GetHammersleyPoint(uint num, uint bitCount)
{
	uint rev = reversebits(num << 32-bitCount);
	return uint2(num, rev);
}

// Description:
// Get a Hammersley point as a normalized float2.
// Arguments:
// num - The index of the hammersley point to get.
// count - The size of the hammersley point set from which to get the point. Should be a power of two.
// Returns:
// The hammersley point.
static float2 GetHammersleyPointFloat(uint num, uint bitCount)
{
	uint2 pt = GetHammersleyPoint(num, bitCount);
	float2 fPt = (float2)pt * float2(1.0f/(1<<bitCount), 1.0f/(1<<bitCount));

	return fPt;
}

///////////////////////////////////////////////////
// Prefilter the lightprobe for BRDF evaluation. //
///////////////////////////////////////////////////

// Description:
// Build a tangent space specular space for convolving the specular irradiance map.
// Arguments:
// Returns:
// The light vector (L) and cosine weighting (NdotL) for the sample.
static float4 BuildSpecularTangentSpaceSample(uint sampleIndex, uint sampleBitCount)
{
	// Generate a sample per thread. These are then used by all threads.
	// Samples are generated in tangent space, and then transformed to the relevant world space (based on dir passed in) on usage.
	float2 Xi = GetHammersleyPointFloat(sampleIndex, sampleBitCount);
			
	float3 L = 0;
	float NdotL = cutDownImportanceSampleGGX_G(Xi, roughness, L);
	NdotL = saturate(NdotL);

	return float4(L, NdotL);
}

// Description:
// Process a batch of generated specular samples.
// Arguments:
// color - The accumulated filtered color.
// weight - The accumulated weight.
// referential - The referential defining world space (in which samples are actually taken).
// sampleStart - The index of the sample this thread is to start evaluating at.
// sampleStep - The step across the samples this thread is to make.
static void ProcessSpecularTangentSpaceSamples(inout float4 color, inout float weight, PbrReferential referential, uint sampleStart, uint sampleStep)
{
	// Then process the samples.
	for (uint i=sampleStart; i<SAMPLE_BATCH_SIZE; i+=sampleStep)
	{
		float4 samp = LdsFloat4Buffer128[i];
		float NdotL = samp.w;
		if (NdotL > 0)
		{
			// Transform light vector vector back into world space for this referential.
			float3 L = referential.m_tangentX * samp.x + referential.m_tangentY * samp.y + referential.m_normal * samp.z;

			// Add in this sample weighted by cosine distribution.
			color += lightprobe.SampleLevel(BilinearFilterSampler, L, 0) * NdotL;
			weight += NdotL;
		}
	}
}

// Description:
// Get the specular mip N color for the specified direction.
// Arguments:
// dir - The direction for which to get the mip N specular color.
// sampleStart - The start index for the hammersley samples.
// sampleStep - The step for the hammersley samples.
// Returns:
// The specular mip N color for the specified direction.
static float4 GetBatchedUnnormalizedSpecularMipNCol(out float totalWeight, float3 dir, uint sampleStart, uint sampleStep, uint groupTid)
{
	// Build surface referential for required direction.
	PbrReferential referential = CreateReferential(dir);

	// Assume both normal and view direction are same as reflection vector for isotropic BRDF lobe. Thus NdotL == NdotH == NdotV.
	float4 PrefilteredColor = 0;
	totalWeight = 0.0f;

	// Use 1024 samples to prefilter.
	const uint sampleBitCount = 10;
	const uint sampleCount = (1<<sampleBitCount);

	for (uint batchBase=0; batchBase<sampleCount; batchBase+=SAMPLE_BATCH_SIZE)
	{
		LdsFloat4Buffer128[groupTid] = BuildSpecularTangentSpaceSample(batchBase|groupTid, sampleBitCount);
		GroupMemoryBarrierWithGroupSync();		// Wait for all samples to be written to LDS.

		// Then process the samples.
		ProcessSpecularTangentSpaceSamples(PrefilteredColor, totalWeight, referential, sampleStart, sampleStep);
		GroupMemoryBarrierWithGroupSync();		// Wait for all samples to be used before overwriting with more on the next iteration.
												// Note: even with the last iteration of this loop there follows another loop for another face which requires the barrier.
	}

	return PrefilteredColor;
}

static void specularMipNFace(float3 normDir, uint groupTid, uint pixelTid, uint2 pixelPos, uint face)
{
	uint res = (uint)rwCubemapFaceRes;

	// Adjacent 32 threads all target same pixel, but sample using interleaved hammersley points. Partial results are combined at end using LDS or lane swizzle.
	uint hammersleyStart = pixelTid;									// Start index in batch of 32 Hammersley samples (index 0 does final write).
	hammersleyStart |= (res-max(pixelPos.x, pixelPos.y)) & ~1023;		// Invalid value for out of range pixelPos (OR in high bits to hammersleyStart from carry to defeat processing loop and final write).

	// Process specular convolution for a pixel. Partial results are left in 32 threads which need to be combined.
	// This method co-operates to generate tangent space samples in LDS which are then shared.
	float totalWeight = 0.0f;
	float4 partialResult = GetBatchedUnnormalizedSpecularMipNCol(totalWeight, normDir, hammersleyStart, 32, groupTid);

	// Parallel reduction to combine results from 31 other threads in the wave (2 pixels per 64 thread wave, or 1 pixel per warp).

#ifdef __ORBIS__
	partialResult += LaneSwizzleF4(partialResult, 0x1u);
	totalWeight += LaneSwizzle(totalWeight, 0x1fu, 0u, 0x1u);
	partialResult += LaneSwizzleF4(partialResult, 0x2u);
	totalWeight += LaneSwizzle(totalWeight, 0x1fu, 0u, 0x2u);
	partialResult += LaneSwizzleF4(partialResult, 0x4u);
	totalWeight += LaneSwizzle(totalWeight, 0x1fu, 0u, 0x4u);
	partialResult += LaneSwizzleF4(partialResult, 0x8u);
	totalWeight += LaneSwizzle(totalWeight, 0x1fu, 0u, 0x8u);
	partialResult += LaneSwizzleF4(partialResult, 0x10u);
	totalWeight += LaneSwizzle(totalWeight, 0x1fu, 0u, 0x10u);
#else //! __ORBIS__
	LdsFloat4Buffer128[groupTid] = partialResult;
	LdsFloatBuffer128[groupTid] = totalWeight;

	GroupMemoryBarrier();

	partialResult	+= LdsFloat4Buffer128[groupTid+16];
	totalWeight		+= LdsFloatBuffer128[groupTid+16];
	LdsFloat4Buffer128[groupTid] = partialResult;
	LdsFloatBuffer128[groupTid] = totalWeight;

	GroupMemoryBarrier();

	partialResult	+= LdsFloat4Buffer128[groupTid+8];
	totalWeight		+= LdsFloatBuffer128[groupTid+8];
	LdsFloat4Buffer128[groupTid] = partialResult;
	LdsFloatBuffer128[groupTid] = totalWeight;

	GroupMemoryBarrier();

	partialResult	+= LdsFloat4Buffer128[groupTid+4];
	totalWeight		+= LdsFloatBuffer128[groupTid+4];
	LdsFloat4Buffer128[groupTid] = partialResult;
	LdsFloatBuffer128[groupTid] = totalWeight;

	GroupMemoryBarrier();

	partialResult	+= LdsFloat4Buffer128[groupTid+2];
	totalWeight		+= LdsFloatBuffer128[groupTid+2];
	LdsFloat4Buffer128[groupTid] = partialResult;
	LdsFloatBuffer128[groupTid] = totalWeight;

	GroupMemoryBarrier();

	partialResult	+= LdsFloat4Buffer128[groupTid+1];
	totalWeight		+= LdsFloatBuffer128[groupTid+1];
#endif //! __ORBIS__

	if (pixelTid == 0)
	{
		// Final normalize.
		float recipWeight = 1.0f / totalWeight;
		partialResult.xyz *= preFilterGain*recipWeight;			// Normalize and gain
		partialResult.w *= recipWeight;							// Normalize
		partialResult.w = saturate(partialResult.w);			// Clamp W (validity) between 0 and 1.

		pixelPos.y += face*res;												// Offset vertically to correct output face.

		rwCubemapFace[pixelPos] = partialResult;
	}
}

// 32 threads * 2 pixels * 2 faces
[numthreads(32, 2, 2)]
void CS_ConvolveSpecularMipN(uint3 DispatchThreadId : SV_DispatchThreadID,
							 uint3 GroupId : SV_GroupID,
							 uint3 GroupThreadId : SV_GroupThreadID)
{
	uint res = (uint)rwCubemapFaceRes;
	uint2 pixelPos = uint2(GroupId.x, DispatchThreadId.y);
	uint face = DispatchThreadId.z;
	uint pixelTid = GroupThreadId.x;
	uint groupTid = GroupThreadId.z*64 + GroupThreadId.y*32 + GroupThreadId.x;

	CubemapNormalGenerator cubemapNormalGenerator = CreateNormalGenerator(res);
	float3 dir = GetNormal(cubemapNormalGenerator, pixelPos.x, pixelPos.y);

	CubemapFacePermutor permutor;

	permutor = CreatePermutorX(face);
	specularMipNFace(PermuteVector(permutor, dir), groupTid, pixelTid, pixelPos, face);

	permutor = CreatePermutorY(face);
	specularMipNFace(PermuteVector(permutor, dir), groupTid, pixelTid, pixelPos, face+2);

	permutor = CreatePermutorZ(face);
	specularMipNFace(PermuteVector(permutor, dir), groupTid, pixelTid, pixelPos, face+4);
}

// ----------------------------------------------------------------------------

technique11 PBRConvolveSpecularMipNCS
{
	pass p0 { SetComputeShader(CompileShader(cs_5_0, CS_ConvolveSpecularMipN())); }
}
