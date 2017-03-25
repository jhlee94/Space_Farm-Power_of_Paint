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

#include "PhyreSphericalHarmonics.h"


// Parameters for the various shaders.
TextureCube <float4> lightprobe;							// The lightprobe texture to pre-filter.
#define SH_ORDER_STRUCT4 SHOrder2Float4
#define SH_ORDER_STRUCT SHOrder2Float
RWStructuredBuffer <SH_ORDER_STRUCT4> RWSphericalHarmonicCoefficients;
int SphericalHarmonicIndex;									// The index of the spherical harmonic to process.

#ifdef __ORBIS__
groupshared SH_ORDER_STRUCT4 sharedShCoeffs[2];
#else //! __ORBIS__
groupshared SH_ORDER_STRUCT4 sharedShCoeffs[128];
#endif //! __ORBIS__

sampler PointFilterSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Wrap;
	AddressV = Wrap;
};

////////////////////////////////////////////////////////////
// Generate spherical harmonic coefficients for a cubemap //
////////////////////////////////////////////////////////////

// Description:
// Fold two bounds and store the result in the lower slot.
// Arguments:
// minBB - The tracked bounds minimum for the current thread ID.
// maxBB - The tracked bounds minimum for the current thread ID.
// step - The separation for the fold.
// tid - The current thread ID.
void fold(inout SH_ORDER_STRUCT4 results, uint step, uint tid)
{
	ShAdd(results, sharedShCoeffs[tid+step]);
	sharedShCoeffs[tid] = results;
}

// Description:
// Fold two bounds and store the result in the lower slot.
// Arguments:
// minBB - The tracked bounds minimum for the current thread ID.
// maxBB - The tracked bounds minimum for the current thread ID.
// step - The separation for the fold.
// tid - The current thread ID.
void foldFinal(inout SH_ORDER_STRUCT4 results, uint step, uint tid)
{
	ShAdd(results, sharedShCoeffs[tid+step]);
}

void doFace(inout SH_ORDER_STRUCT4 results, CubemapNormalGenerator cubemapNormalGenerator, CubemapFacePermutor cubemapFacePermutor, uint size, uint2 posInTile)
{
	// Loop over all texels.
	for (uint y=0; y<size; y+=8)
	{
		for (uint x=0; x<size; x+=8)
		{
			float3 normDir = GetNormal(cubemapNormalGenerator, x+posInTile.x, y+posInTile.y);
			normDir = PermuteVector(cubemapFacePermutor, normDir);

			SH_ORDER_STRUCT shBuff;
			EvaluateSH(shBuff, normDir);

			// Calculate and accumulate differential solid angle.
			float fDiffSolid = GetDifferentialSolidAngle(cubemapNormalGenerator, x+posInTile.x, y+posInTile.y);

			// Get cubemap texel.
			float4 rgba = lightprobe.SampleLevel(PointFilterSampler, normDir, 0);			// Add in this sample.
			rgba *= fDiffSolid;																// Scale by differential solid angle (all solid angles add to 4*pi).

			SH_ORDER_STRUCT resultR = shBuff;				ShScale(resultR, rgba.r);
			SH_ORDER_STRUCT resultG = shBuff;				ShScale(resultG, rgba.g);
			SH_ORDER_STRUCT resultB = shBuff;				ShScale(resultB, rgba.b);
			SH_ORDER_STRUCT resultA = shBuff;				ShScale(resultA, rgba.a);

			// Accumulate result.
			ShAdd4(results, resultR, resultG, resultB, resultA);
		}
	}
}

[numthreads(8, 8, 2)]
void CS_GenerateSphericalHarmonicCoefficients(uint3 GroupId : SV_GroupID, 
												uint3 DispatchThreadId : SV_DispatchThreadID, 
												uint3 GroupThreadId : SV_GroupThreadID)
{
	uint tid = GroupThreadId.z*64 + GroupThreadId.y*8 + GroupThreadId.x;

	// Each thread processes a pixel in an 8x8 tile on 3 faces. The origin is:
	uint2 posInTile = GroupThreadId.xy;

	uint size, height;
	lightprobe.GetDimensions(size, height);

	// Coefficient results for each band.
	SH_ORDER_STRUCT4	results;
	ShReset(results);

	CubemapNormalGenerator cubemapNormalGenerator = CreateNormalGenerator(size);

	// Loop over all faces. Each Z group does 3 faces (min or max), the 2 Z groups together cover all 6 faces.
	CubemapFacePermutor permutorX = CreatePermutor(0+GroupThreadId.z);
	doFace(results, cubemapNormalGenerator, permutorX, size, posInTile);

	CubemapFacePermutor permutorY = CreatePermutor(2+GroupThreadId.z);
	doFace(results, cubemapNormalGenerator, permutorY, size, posInTile);

	CubemapFacePermutor permutorZ = CreatePermutor(4+GroupThreadId.z);
	doFace(results, cubemapNormalGenerator, permutorZ, size, posInTile);

#ifdef __ORBIS__
	// Fold the 64 entries using lane swizzling.
	ShLaneSwizzle(results);
	// Write to LDS and fold final two results from two cube faces.
	sharedShCoeffs[GroupThreadId.z] = results;
	GroupMemoryBarrierWithGroupSync();
	foldFinal(results, 1, GroupThreadId.z);			// Don't bother with final LDS write.
#else //! __ORBIS__
	// Write into shared memory for parallel reduction.
	sharedShCoeffs[tid] = results;
	GroupMemoryBarrierWithGroupSync();

	// Now fold the 128 entries down to 1 and write to the intermediate buffer.
	fold(results, 64, tid);
	GroupMemoryBarrierWithGroupSync();
	fold(results, 32, tid);
	GroupMemoryBarrierWithGroupSync();
	fold(results, 16, tid);
	GroupMemoryBarrier();
	fold(results, 8, tid);
	GroupMemoryBarrier();
	fold(results, 4, tid);
	GroupMemoryBarrier();
	fold(results, 2, tid);
	GroupMemoryBarrier();
	foldFinal(results, 1, tid);						// Don't bother with final LDS write.
#endif //! __ORBIS

	// Results are in "results" already for thread 0.
	if (tid < 1)
	{
		// Write to output.
		RWSphericalHarmonicCoefficients[SphericalHarmonicIndex] = results;
	}
}

technique11 GenerateSphericalHarmonicCoefficients
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_GenerateSphericalHarmonicCoefficients()));
	}
}
