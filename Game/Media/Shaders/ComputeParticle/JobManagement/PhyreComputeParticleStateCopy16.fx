/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

struct PStruct16
{
	float4		m_el1;
};

StructuredBuffer<PStruct16>						srce;							// The source structure buffer containing 16 byte particle state.
RWStructuredBuffer<PStruct16>					dest;							// The destination structure buffer containing 16 byte particle state.
uint											srceStart;						// The source element offset for the copy.
uint											destStart;						// The destination element offset for the copy.
uint											size;							// The element count for the copy.

[numthreads(64, 1, 1)]
void CS_StateCopy16(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint moveIndex = DispatchThreadId.x;

	if (moveIndex < size)
	{
		dest[moveIndex+destStart].m_el1 = srce[moveIndex+srceStart].m_el1;
	}
}

#ifndef __ORBIS__

technique11 StateCopy16
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_StateCopy16() ) );
	}
};

#endif //! __ORBIS__
