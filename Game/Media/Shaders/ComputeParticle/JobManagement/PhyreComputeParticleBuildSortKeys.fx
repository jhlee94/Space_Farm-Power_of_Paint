/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
StructuredBuffer<PParticleStateStruct>				particle_PositionVelocityLifetime;	// The structure buffer containing particle positions, velocities and lifetimes.

RWByteAddressBuffer									sortBuffer;							// The structure buffer containing the elements to sort.
float3												sortAxis;							// The axis on which to generate the sort keys.

[numthreads(64, 1, 1)]
void CS_BuildSortKeys(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our population.
	uint particleIndex = DispatchThreadId.x;

	float sortKey = 10000000.0f;
	if (particleIndex < state.m_population)					// It's a live particle.
	{
		float3 location = particle_PositionVelocityLifetime[particleIndex+state.m_baseIndex].m_location;
		sortKey = dot(location, sortAxis);
	}

	uint2 sortElement = uint2(particleIndex, asint(sortKey));
	sortBuffer.Store2(particleIndex*8, sortElement);
}

#ifndef __ORBIS__

technique11 BuildSortKeys
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_BuildSortKeys() ) );
	}
};

#endif //! __ORBIS__
