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

float preFilterGain;										// The gain to use whilst prefiltering.
TextureCube <float4> lightprobe;							// The lightprobe texture to pre-filter.
RWTexture2D<float4> rwCubemapFace;						// The mip-face of a cubemap.
int rwCubemapFaceRes;									// The resolution of the cubemap faces.

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
// Get the diffuse mip 0 color for the specified direction.
// Arguments:
// dir - The direction for which to get the mip 0 diffuse color.
// Returns:
// The diffuse mip 0 color for the specified direction.
static float4 GetDiffuseMip0Col(float3 dir)
{
	// Assume both normal and view direction are same as reflection vector for isotropic BRDF lobe. Thus NdotL == NdotH == NdotV.
	float3 N = dir;
	float4 PrefilteredColor = 0;
	float TotalWeight = 0.0f;
 
	// Build surface referential
	PbrReferential referential = CreateReferential(N);

	// Use 65536 samples to prefilter diffuse.
	const uint sampleBitCount = 16;
	const uint sampleCount = (1<<sampleBitCount);
	for( uint i = 0; i < sampleCount; i++ )
	{
		float2 Xi = GetHammersleyPointFloat(i, sampleBitCount);

		float3 L = float3(0,0,0);
		float NdotL = 0;
		float pdf = 0;

		importanceSampleCosDir(Xi, referential, L, NdotL, pdf);

		if( NdotL > 0 )
			PrefilteredColor += lightprobe.SampleLevel(BilinearFilterSampler, L, 0);			// Add in this sample.

		TotalWeight += 1.0f;
	}

	PrefilteredColor /= TotalWeight;							// Normalize
	PrefilteredColor.w = saturate(PrefilteredColor.w);			// Clamp W (validity) between 0 and 1.

	PrefilteredColor.xyz *= preFilterGain;

	return PrefilteredColor;
}

// ----------------------------------------------------------------------------

static void diffuseFace(uint2 pixelPos, uint face)
{
	uint res = (uint)rwCubemapFaceRes;

	if ((pixelPos.x < res) && (pixelPos.y < res))
	{
		CubemapNormalGenerator cubemapNormalGenerator = CreateNormalGenerator(res);
		float3 normDir = GetNormal(cubemapNormalGenerator, pixelPos.x, pixelPos.y);

		CubemapFacePermutor cubemapFacePermutor = CreatePermutor(face);
		normDir = PermuteVector(cubemapFacePermutor, normDir);

		pixelPos.y += face*res;
		rwCubemapFace[pixelPos] = GetDiffuseMip0Col(normDir);
	}
}

[numthreads(8, 8, 6)]
void CS_ConvolveDiffuse(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	diffuseFace(DispatchThreadId.xy, DispatchThreadId.z);
}

// ----------------------------------------------------------------------------

technique11 PBRConvolveDiffuseCS
{
	pass p0 { SetComputeShader(CompileShader(cs_5_0, CS_ConvolveDiffuse())); }
}
