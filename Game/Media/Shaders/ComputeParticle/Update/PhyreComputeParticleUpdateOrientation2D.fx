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
RWStructuredBuffer<PParticleOrientation2DStruct>	particle_Orientation2D;					// The structure buffer containing particle orientation.

#define PD_PI_F 3.1415926535897932f

[numthreads(64, 1, 1)]
void CS_UpdateOrientation2D(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float orientation = particle_Orientation2D[particleIndex].m_orientation + period * particle_Orientation2D[particleIndex].m_angularVelocity;

		// Renormalize the orientation.
#ifndef __ORBIS__
		[allow_uav_condition]
#endif //! __ORBIS__
		while (orientation < 0.0f)
			orientation += 2*PD_PI_F;
#ifndef __ORBIS__
		[allow_uav_condition]
#endif //! __ORBIS__
		while (orientation > (2*PD_PI_F))
			orientation -= 2*PD_PI_F;

		particle_Orientation2D[particleIndex].m_orientation = orientation;
	}
}

#ifndef __ORBIS__

technique11 UpdateOrientation2D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateOrientation2D() ) );
	}
};

#endif //! __ORBIS__
