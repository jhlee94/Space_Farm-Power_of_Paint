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
float preFilterGain;										// The gain to use whilst prefiltering.
#define SH_ORDER_STRUCT4 SHOrder2Float4
#define SH_ORDER_STRUCT SHOrder2Float
StructuredBuffer <SH_ORDER_STRUCT4> SphericalHarmonicCoefficients;
int SphericalHarmonicIndex;									// The index of the spherical harmonic to process.
RWTexture2D<float4> rwCubemapFace;						// The mip-face of a cubemap.
int rwCubemapFaceRes;									// The resolution of the cubemap faces.

static float4 GetDiffuseSH(float3 dir)
{
	// Evaluate Spherical Harmonics at surface normal direction.
	SH_ORDER_STRUCT shBuff;
	EvaluateSH(shBuff, dir);

	// Multiply in SH-projection of cosinus lobe (NdotL term in frequency domain).
	ApplyCosinusLobe(shBuff);

	// Reconstruct the answer.
	SH_ORDER_STRUCT4 coeffs = SphericalHarmonicCoefficients[SphericalHarmonicIndex];
	float4 PrefilteredColor = ShReconstruct(coeffs, shBuff);

	PrefilteredColor.xyz *= preFilterGain;

	return PrefilteredColor;
}

static void CS_ConvolveDiffuseSHFace(uint2 pixelPos, uint face)
{
	uint res = (uint)rwCubemapFaceRes;

	if ((pixelPos.x < res) && (pixelPos.y < res))
	{
		CubemapNormalGenerator cubemapNormalGenerator = CreateNormalGenerator(res);
		float3 normDir = GetNormal(cubemapNormalGenerator, pixelPos.x, pixelPos.y);

		CubemapFacePermutor cubemapFacePermutor = CreatePermutor(face);
		normDir = PermuteVector(cubemapFacePermutor, normDir);

		pixelPos.y += face * res;
		rwCubemapFace[pixelPos] = GetDiffuseSH(normDir);
	}
}

[numthreads(8, 8, 6)]
void CS_ConvolveDiffuseSH(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	CS_ConvolveDiffuseSHFace(DispatchThreadId.xy, DispatchThreadId.z);
}

technique11 PBRConvolveDiffuseSHCS
{
	pass p0 { SetComputeShader(CompileShader(cs_5_0, CS_ConvolveDiffuseSH())); }
}
