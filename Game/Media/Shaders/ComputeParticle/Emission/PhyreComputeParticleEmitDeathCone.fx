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
	PEmitDeathConeStateStruct						emissionState;							// The emission state for emitting particles from dead particles.
};

[numthreads(64, 1, 1)]
void CS_EmitDeathCone(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];
	ParticleStateBufferInfoStruct deadState = deadParticleSystemState[0];

	// Cap to end of emission window.
	uint topEndOfEmissionWindow = emissionCount + state.m_population;
	if (topEndOfEmissionWindow > state.m_capacity)
		topEndOfEmissionWindow = state.m_capacity;

	uint particleIndex = DispatchThreadId.x;

	// Work out the source dead particle.
	uint deadParticleIndex = particleIndex / emissionState.m_emissionMultiplier;

	particleIndex += state.m_population;			// Append to the end of the live particles.

	if ((particleIndex < topEndOfEmissionWindow) && (deadParticleIndex < deadState.m_deadPopulation))
	{
		deadParticleIndex += deadState.m_deadBaseIndex;
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		// Set up random number generator.
		uint randSeed = randomSeed + DispatchThreadId.x * 20;
		uint3 vRandSeed = uint3(randSeed, randSeed + 1, randSeed + 2);

		// Generate sufficient random numbers for our emission.
		float3 r1 = genRandFloat3(vRandSeed);
		float2 r2 = genRandFloat2(vRandSeed.xy);

		float varianceVelocity = interpSpread(emissionState.m_velocity, emissionState.m_velocityVariance, r2.x);
		float varianceLifetime = interpSpread(emissionState.m_lifetime, emissionState.m_lifetimeVariance, r2.y);
		float3 directionVariance = interpSpread(emissionState.m_emitterDirection, emissionState.m_emitterDirectionVariance, r1.xyz);

		// Normalize if direction has sufficient length.
		float dirLengthSqr = dot(directionVariance, directionVariance);
		if (dirLengthSqr > 0.0f)
			directionVariance *= 1.0f/sqrt(dirLengthSqr);

		particle_PositionVelocityLifetime[particleIndex].m_location = deadParticle_PositionVelocityLifetime[deadParticleIndex].m_location;
		particle_PositionVelocityLifetime[particleIndex].m_velocity =  (directionVariance * varianceVelocity);
		particle_PositionVelocityLifetime[particleIndex].m_lifetime = varianceLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_spawnedLifetime = varianceLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_recipSpawnedLifetime = 1.0f/varianceLifetime;
	}
}

#ifndef __ORBIS__

technique11 EmitDeathCone
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitDeathCone() ) );
	}
};

#endif //! __ORBIS__
