/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
StructuredBuffer<PParticleStateStruct>				particle_PositionVelocityLifetime;	// The structure buffer containing particle positions, velocities and lifetimes.
AppendStructuredBuffer<uint>						particleLiveIndices;				// The list of live particle indices.
AppendStructuredBuffer<uint>						particleDeadIndices;				// The list of dead particle indices.

[numthreads(64, 1, 1)]
void CS_DefragSortLiveAndDeadParticles(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	uint particleIndex = DispatchThreadId .x;
	if (particleIndex < state.m_population)
	{
		// Is this particle live or dead?
		if (particle_PositionVelocityLifetime[state.m_baseIndex + particleIndex].m_lifetime <= 0.0f)
			particleDeadIndices.Append(particleIndex);			// Dead.
		else
			particleLiveIndices.Append(particleIndex);			// Live.
	}
}

#ifndef __ORBIS__

technique11 DefragSortLiveAndDeadParticles
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefragSortLiveAndDeadParticles() ) );
	}
};

#endif //! __ORBIS__
