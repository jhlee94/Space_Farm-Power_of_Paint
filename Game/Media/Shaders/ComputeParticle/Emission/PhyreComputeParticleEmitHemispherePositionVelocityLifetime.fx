/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>															// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "../Common/PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>			particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
uint													emissionCount;							// The number of particles to emit.
uint													randomSeed;								// The random seed for tihs emission.  Offset by dispatch thread ID and then permute.
RWStructuredBuffer<PParticleStateStruct>				particle_PositionVelocityLifetime;		// The structure buffer containing particle positions, velocities and lifetimes.
cbuffer emissionStateBuffer
{
	PEmitHemispherePositionVelocityLifetimeStateStruct	emissionState;							// The emission state for emitting hemisphere positions, velocities and lifetimes.
};

[numthreads(64, 1, 1)]
void CS_EmitHemispherePositionVelocityLifetime(uint3 DispatchThreadId : SV_DispatchThreadID)
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
		uint4 vRandSeed = uint4(randSeed, randSeed + 1, randSeed + 2, randSeed + 3);

		// Temporary location for the emission parameters.
		float3 emitterPoint = emissionState.m_emitterPoint + emissionState.m_parentPosition;
		float3 emitterDirection = emissionState.m_parentFacingX * emissionState.m_emitterDirection.x +
								  emissionState.m_parentFacingY * emissionState.m_emitterDirection.y +
								  emissionState.m_parentFacingZ * emissionState.m_emitterDirection.z;
		float3 hemispherePole = emissionState.m_emitterPole;
		float3 parentVelocity = emissionState.m_parentVelocity;
		float radius = emissionState.m_emitterRadius;

		// Normalize if direction has sufficient length.
		float dirLengthSqr = dot(emitterDirection, emitterDirection);
		if (dirLengthSqr > 0.0f)
			emitterDirection *= 1.0f/sqrt(dirLengthSqr);

		// Generate sufficient random numbers for our emission.
		float4 r1 = genRandFloat4(vRandSeed);

		float varianceVelocity = interpSpread(emissionState.m_velocity, emissionState.m_velocityVariance, r1.x);
		float varianceLifetime = interpSpread(emissionState.m_lifetime, emissionState.m_lifetimeVariance, r1.y);

		float3 directionVariance = emitPerturbedNormal(emitterDirection, emissionState.m_emitterDirectionVariance, r1.zw);

		// Generate a vector inside a unit sphere.
		float3 vec = emitVector3WithinUnitSphere(vRandSeed);

		// Flip the vector if in the wrong hemisphere.
		if (dot(vec, hemispherePole) < 0.0f)
			vec = -vec;

		float3 emittedLocation = (vec * radius) + emitterPoint;
		float3 emittedVelocity = parentVelocity + (directionVariance * varianceVelocity);
		float emittedLifetime = max(varianceLifetime, 0.01f);

		particle_PositionVelocityLifetime[particleIndex].m_location = emittedLocation;
		particle_PositionVelocityLifetime[particleIndex].m_velocity = emittedVelocity;
		particle_PositionVelocityLifetime[particleIndex].m_lifetime = emittedLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_spawnedLifetime = emittedLifetime;
		particle_PositionVelocityLifetime[particleIndex].m_recipSpawnedLifetime = 1.0f/emittedLifetime;
	}
}

#ifndef __ORBIS__

technique11 EmitHemispherePositionVelocityLifetime
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitHemispherePositionVelocityLifetime() ) );
	}
};

#endif //! __ORBIS__
