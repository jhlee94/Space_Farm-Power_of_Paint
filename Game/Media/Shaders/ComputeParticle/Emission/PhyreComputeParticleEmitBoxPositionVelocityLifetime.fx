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
	PEmitBoxPositionVelocityLifetimeStateStruct			emissionState;							// The emission state for emitting box positions, velocities and lifetimes.
};

[numthreads(64, 1, 1)]
void CS_EmitBoxPositionVelocityLifetime(uint3 DispatchThreadId : SV_DispatchThreadID)
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
		float3 parentVelocity = emissionState.m_parentVelocity;

		// Normalize if direction has sufficient length.
		float dirLengthSqr = dot(emitterDirection, emitterDirection);
		if (dirLengthSqr > 0.0f)
			emitterDirection *= 1.0f/sqrt(dirLengthSqr);

		// Generate sufficient random numbers for our emission.
		float4 r1 = genRandFloat4(vRandSeed);
		float3 r2 = genRandFloat3(vRandSeed.xyz);

		float3 boxPos = interpSpread(emitterPoint, emissionState.m_emitterBox, r1.xyz);
		float varianceVelocity = interpSpread(emissionState.m_velocity, emissionState.m_velocityVariance, r1.w);
		float varianceLifetime = interpSpread(emissionState.m_lifetime, emissionState.m_lifetimeVariance, r2.x);
		float VarianceDirectionX = interpSpread(0.0f, emissionState.m_emitterDirectionVariance, r2.y);
		float VarianceDirectionY = interpSpread(0.0f, emissionState.m_emitterDirectionVariance, r2.z);

		float3x3 randDirectionMatrixX = rotationX(VarianceDirectionX);
		float3x3 randDirectionMatrixZ = rotationZ(VarianceDirectionY);
		randDirectionMatrixX *= randDirectionMatrixZ;
		float3 directionVariance = mul(randDirectionMatrixX, emitterDirection);

		// Generate the "random" position, velocity and lifetime based on the emission state.
		float3 emittedLocation = boxPos;
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

technique11 EmitBoxPositionVelocityLifetime
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitBoxPositionVelocityLifetime() ) );
	}
};

#endif //! __ORBIS__
