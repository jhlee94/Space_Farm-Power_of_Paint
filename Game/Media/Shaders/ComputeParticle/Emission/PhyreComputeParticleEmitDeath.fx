/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "../Common/PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
uint												emissionCount;							// The number of particles to emit.
uint												randomSeed;								// The random seed for tihs emission.  Offset by dispatch thread ID and then permute.
RWStructuredBuffer<PParticleStateStruct>			particle_PositionVelocityLifetime;		// The structure buffer containing particle positions, velocities and lifetimes.

StructuredBuffer<PParticleStateStruct>				deadParticle_PositionVelocityLifetime;	// The structure buffer containing the dead particles.
StructuredBuffer<ParticleStateBufferInfoStruct>		deadParticleSystemState;				// The particle system's state for the predecessor particle system (supplying the dead particles).

cbuffer emissionState
{
	PEmitDeathStateStruct							emissionState;							// The emission state for emitting particles from dead particles.
};

[numthreads(64, 1, 1)]
void CS_EmitDeath(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];
	ParticleStateBufferInfoStruct deadState = deadParticleSystemState[0];

	// Cap to end of emission window.
	uint topEndOfEmissionWindow = emissionCount + state.m_population;
	if (topEndOfEmissionWindow > state.m_capacity)
		topEndOfEmissionWindow = state.m_capacity;

	uint particleIndex = DispatchThreadId.x;

	// Work out the source dead particle.
	uint deadParticleIndex = particleIndex;

	particleIndex += state.m_population;			// Append to the end of the live particles.

	if ((particleIndex < topEndOfEmissionWindow) && (deadParticleIndex < deadState.m_deadPopulation))
	{
		deadParticleIndex += deadState.m_deadBaseIndex;
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		// Set up random number generator.
		uint randSeed = randomSeed + DispatchThreadId.x * 20;
		uint4 vRandSeed = uint4(randSeed, randSeed + 1, randSeed + 2, randSeed + 3);

		// Generate sufficient random numbers for our emission.
		float4 r1 = genRandFloat4(vRandSeed);

		float emittedLifetime = interpSpread(emissionState.m_lifetime, emissionState.m_lifetimeVariance, r1.x);

		particle_PositionVelocityLifetime[particleIndex].m_location = deadParticle_PositionVelocityLifetime[deadParticleIndex].m_location;
		particle_PositionVelocityLifetime[particleIndex].m_velocity = deadParticle_PositionVelocityLifetime[deadParticleIndex].m_velocity;
		particle_PositionVelocityLifetime[particleIndex].m_lifetime = emittedLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_spawnedLifetime = emittedLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_recipSpawnedLifetime = 1.0f/emittedLifetime;
	}
}

#ifndef __ORBIS__

technique11 EmitDeath
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitDeath() ) );
	}
};

#endif //! __ORBIS__
