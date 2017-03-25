/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "..\Common\PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;					// The particle system's state for the update (population, capacity, etc).
float												period;									// The time step over which to update the particle.
RWStructuredBuffer<PParticleStateStruct>			particle_PositionVelocityLifetime;		// The structure buffer containing particle time.
cbuffer updateStateBuffer
{
	PUpdatePlaneCollisionStateStruct				updateState;							// The update state for updating position and velocity.
};

[numthreads(64, 1, 1)]
void CS_UpdatePlaneCollision(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float3 planeNormal = updateState.m_plane.xyz;
		float planeDistanceFromOrigin = -updateState.m_plane.w;
		float bounceScale = updateState.m_coefficientOfRestitution;
		bool deathOnCollision = updateState.m_deathOnCollision;

		float3 particlePos = particle_PositionVelocityLifetime[particleIndex].m_location;
		float3 particleDir = particle_PositionVelocityLifetime[particleIndex].m_velocity;
		// Project point onto plane normal direction vector and take away the distance of plane from the origin
		float distanceFromPlane = dot(particlePos, planeNormal) - planeDistanceFromOrigin;

		// Calculate what component of velocity is approaching the plane (-ve is approaching, +ve is receding).
		float componentApproaching = dot(particleDir, planeNormal);

		// Are we at/through the plane and approaching the plane.  If so, reflect the direction.
		if ((distanceFromPlane <= 0.0f) && (componentApproaching < 0.0f))
		{
			// Bounce the particle.
			particleDir = particleDir - ((1.0f + bounceScale) * componentApproaching * planeNormal);

			particle_PositionVelocityLifetime[particleIndex].m_velocity = particleDir;
			
			if (deathOnCollision)
				particle_PositionVelocityLifetime[particleIndex].m_lifetime = 0.0f;
		}
	}
}

#ifndef __ORBIS__

technique11 UpdatePlaneCollision
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdatePlaneCollision() ) );
	}
};

#endif //! __ORBIS__
