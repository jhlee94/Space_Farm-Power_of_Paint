/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "..\Common\PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
float												period;									// The time step to update the particle for.
RWStructuredBuffer<PParticleStateStruct>			particle_PositionVelocityLifetime;		// The structure buffer containing particle time.
cbuffer updateStateBuffer
{
	PUpdatePointAttractorPositionVelocityStateStruct		updateState;							// The update state for updating position and velocity.
};

[numthreads(64, 1, 1)]
void CS_UpdatePointAttractorPositionVelocity(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < particleSystemState[0].m_population)
	{
		particleIndex += particleSystemState[0].m_baseIndex;			// Adjust to be in the correct budget block portion.

		float3 attractPoint = updateState.m_attractPoint;
		float strength = updateState.m_strength;

		// Load particle state.
		float3 location = particle_PositionVelocityLifetime[particleIndex].m_location;
		float3 velocity = particle_PositionVelocityLifetime[particleIndex].m_velocity;
		float lifetime = particle_PositionVelocityLifetime[particleIndex].m_lifetime;

		// Integrate velocity and acceleration.  Age the particle.
		location += (velocity * period);
		lifetime -= period;

		float3 diff = attractPoint - location;
		if (diff.x != 0 || diff.y != 0 || diff.z != 0)
		{
			float3 attractForce = strength * normalize(diff);
			velocity += (attractForce * period);
		}

		// Store particle state.
		particle_PositionVelocityLifetime[particleIndex].m_location = location;
		particle_PositionVelocityLifetime[particleIndex].m_velocity = velocity;
		particle_PositionVelocityLifetime[particleIndex].m_lifetime = lifetime;
	}
}

#ifndef __ORBIS__

technique11 UpdatePointAttractorPositionVelocity
{
	pass p0
	{
		SetComputeShader(CompileShader(cs_5_0, CS_UpdatePointAttractorPositionVelocity()));
	}
};

#endif //! __ORBIS__
