/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

// Extract particle state for dead particles for death emissions to use.
StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
StructuredBuffer<PParticleStateStruct>				particle_PositionVelocityLifetime;		// The structure buffer containing particle positions, velocities and lifetimes.
StructuredBuffer<uint>								deadIndexCount;							// The structured buffer containing the new dead particle count.
StructuredBuffer<uint>								particleDeadIndices;					// The list of dead particle indices.
RWStructuredBuffer<PParticleStateStruct>			deadParticle_PositionVelocityLifetime;	// The buffer of dead particle states captured.

[numthreads(64, 1, 1)]
void CS_DefragCaptureDeadParticles(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	uint deadCount = min(deadIndexCount[0], state.m_deadCapacity);
	uint deadIndex = DispatchThreadId.x;
	if (deadIndex < deadCount)
	{
		uint deadParticleIndex = particleDeadIndices[deadIndex];

		// Offset into batch and append state to the dead list.
		PParticleStateStruct deadParticle = particle_PositionVelocityLifetime[state.m_baseIndex + deadParticleIndex];

		deadParticle_PositionVelocityLifetime[state.m_deadBaseIndex + deadIndex] = deadParticle;
	}
}

#ifndef __ORBIS__

technique11 DefragCaptureDeadParticles
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefragCaptureDeadParticles() ) );
	}
};

#endif //! __ORBIS__
