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
cbuffer emissionStateBuffer
{
	PEmitConePositionVelocityLifetimeStateStruct	emissionState;							// The emission state for emitting cone positions, velocities and lifetimes.
};

[numthreads(64, 1, 1)]
void CS_EmitConePositionVelocityLifetime(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		// Set up random number generator.
		uint randSeed = randomSeed + DispatchThreadId.x * 20;
		uint3 vRandSeed = uint3(randSeed, randSeed + 1, randSeed + 2);

		// Temporary location for the emission parameters.
		float3 emitterPoint = emissionState.m_emitterPoint + emissionState.m_parentPosition;
		float3 parentVelocity = emissionState.m_parentVelocity;

		// Generate sufficient random numbers for our emission.
		float3 r1 = genRandFloat3(vRandSeed);
		float2 r2 = genRandFloat2(vRandSeed.xy);

		float varianceVelocity = interpSpread(emissionState.m_velocity, emissionState.m_velocityVariance, r2.x);
		float varianceLifetime = interpSpread(emissionState.m_lifetime, emissionState.m_lifetimeVariance, r2.y);
		float3 directionVariance = interpSpread(emissionState.m_emitterDirection, emissionState.m_emitterDirectionVariance, r1.xyz);

		varianceLifetime = max(varianceLifetime, 0.01f);

		directionVariance = emissionState.m_parentFacingX * directionVariance.x +
							emissionState.m_parentFacingY * directionVariance.y +
							emissionState.m_parentFacingZ * directionVariance.z;

		// Normalize if direction has sufficient length.
		float dirLengthSqr = dot(directionVariance, directionVariance);
		if (dirLengthSqr > 0.0f)
			directionVariance *= 1.0f/sqrt(dirLengthSqr);

		particle_PositionVelocityLifetime[particleIndex].m_location = emitterPoint;
		particle_PositionVelocityLifetime[particleIndex].m_velocity =  parentVelocity + (directionVariance * varianceVelocity);
		particle_PositionVelocityLifetime[particleIndex].m_lifetime = varianceLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_spawnedLifetime = varianceLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_recipSpawnedLifetime = 1.0f/varianceLifetime;
	}
}

#ifndef __ORBIS__

technique11 EmitConePositionVelocityLifetime
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitConePositionVelocityLifetime() ) );
	}
};

#endif //! __ORBIS__
