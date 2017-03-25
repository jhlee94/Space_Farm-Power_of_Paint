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
#define SH_ORDER_STRUCT4 SHOrder2Float4
#define SH_ORDER_STRUCT SHOrder2Float
StructuredBuffer <SH_ORDER_STRUCT4> SrcSphericalHarmonicCoefficients;
RWStructuredBuffer <SH_ORDER_STRUCT4> RWDstSphericalHarmonicCoefficients;
int DstOffset;
int DstStride;
int SrcCount;

////////////////////////////////////////////////////////////
// Generate spherical harmonic coefficients for a cubemap //
////////////////////////////////////////////////////////////

[numthreads(64, 1, 1)]
void CS_StridedSphericalHarmonicCopy(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint tid = DispatchThreadId.x;

	if (tid < (uint)SrcCount)
	{
		RWDstSphericalHarmonicCoefficients[tid*DstStride + DstOffset] = SrcSphericalHarmonicCoefficients[tid];
	}
}

technique11 StridedSphericalHarmonicCopy
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_StridedSphericalHarmonicCopy()));
	}
}
