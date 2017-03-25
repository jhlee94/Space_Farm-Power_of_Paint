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
RWStructuredBuffer<PParticleOrientation3DStruct>	particle_Orientation3D;					// The structure buffer containing particle orientation.

[numthreads(64, 1, 1)]
void CS_UpdateOrientation3D(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float4 orientation = particle_Orientation3D[particleIndex].m_orientation;
		float4 angularVelocity = particle_Orientation3D[particleIndex].m_angularVelocity;

		// Do some maths here to integrate the 3D motion.
		float4 quatIdentity = float4(0, 0, 0, 1);

		float4 quatStep = quatSlerp(period, quatIdentity, angularVelocity);			// How much should we rotate by for the timestep?
		orientation = quatMul(quatMul(quatStep, orientation), quatConjugate(quatStep));

		particle_Orientation3D[particleIndex].m_orientation = orientation;
	}
}

#ifndef __ORBIS__

technique11 UpdateOrientation3D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateOrientation3D() ) );
	}
};

#endif //! __ORBIS__
