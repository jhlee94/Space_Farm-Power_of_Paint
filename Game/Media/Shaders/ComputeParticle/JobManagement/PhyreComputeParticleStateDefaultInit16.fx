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

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
StructuredBuffer<PStruct16>							srce;								// The source structure buffer containing 16 byte particle state.
RWStructuredBuffer<PStruct16>						dest;								// The destination structure buffer containing 16 byte particle state.
uint												emissionCount;						// The element count for the initialization.

[numthreads(64, 1, 1)]
void CS_DefaultInit16(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	uint topEndOfEmissionWindow = emissionCount + state.m_population;
	if (topEndOfEmissionWindow > state.m_capacity)
		topEndOfEmissionWindow = state.m_capacity;

	uint particleIndex = DispatchThreadId.x;
	particleIndex += state.m_population;			// Append to the end of the live particles.

	if (particleIndex < topEndOfEmissionWindow)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		dest[particleIndex].m_el1 = srce[0].m_el1;
	}
}

#ifndef __ORBIS__

technique11 DefaultInit16
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefaultInit16() ) );
	}
};

#endif //! __ORBIS__
