/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

struct PStruct32
{
	float4		m_el1;
	float4		m_el2;
};

StructuredBuffer<PStruct32>						srce;							// The source structure buffer containing 16 byte particle state.
RWStructuredBuffer<PStruct32>					dest;							// The destination structure buffer containing 16 byte particle state.
uint											srceStart;						// The source element offset for the copy.
uint											destStart;						// The destination element offset for the copy.
uint											size;							// The element count for the copy.

[numthreads(64, 1, 1)]
void CS_StateCopy32(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint moveIndex = DispatchThreadId.x;

	if (moveIndex < size)
	{
		float4 el1 = srce[moveIndex+srceStart].m_el1;
		float4 el2 = srce[moveIndex+srceStart].m_el2;

		dest[moveIndex+destStart].m_el1 = el1;
		dest[moveIndex+destStart].m_el2 = el2;
	}
}

#ifndef __ORBIS__

technique11 StateCopy32
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_StateCopy32() ) );
	}
};

#endif //! __ORBIS__
