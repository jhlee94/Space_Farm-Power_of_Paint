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

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
StructuredBuffer<uint>							particleMoveCount;				// The number of particle moves to perform.
RWStructuredBuffer<PStruct32>					particle_state;					// The structure buffer containing 32 byte particle state.
StructuredBuffer<uint2>							particleMoves;					// The mappings for the particles to move.

[numthreads(64, 1, 1)]
void CS_DefragRemap32(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint moveIndex = DispatchThreadId.x;
	uint moveCount = particleMoveCount[0];
	if (moveIndex < moveCount)
	{
		uint2 indices = particleMoves[moveIndex];
		uint srceIndex = indices.x + state.m_baseIndex;
		uint destIndex = indices.y + state.m_baseIndex;

		float4 el1 = particle_state[srceIndex].m_el1;
		float4 el2 = particle_state[srceIndex].m_el2;
		particle_state[destIndex].m_el1 = el1;
		particle_state[destIndex].m_el2 = el2;
	}
}

#ifndef __ORBIS__

technique11 DefragRemap32
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefragRemap32() ) );
	}
};

#endif //! __ORBIS__
