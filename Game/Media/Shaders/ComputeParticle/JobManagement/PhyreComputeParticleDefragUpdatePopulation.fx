/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

RWStructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer									dispatchIndirectArgs;				// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer									dispatchDeadIndirectArgs;			// The particle system's dispatch indirect arguments for dead particles.
StructuredBuffer<uint>								liveIndexCount;						// The structured buffer containing the new live particle count.
StructuredBuffer<uint>								deadIndexCount;						// The structured buffer containing the dead particle count.

[numthreads(1, 1, 1)]
void CS_DefragUpdatePopulation()
{
	uint liveCount = liveIndexCount[0];
	uint deadCount = deadIndexCount[0];

	deadCount = min(particleSystemState[0].m_deadCapacity, deadCount);			// Cap to capacity

	particleSystemState[0].m_population = liveCount;
	particleSystemState[0].m_deadPopulation = deadCount;

	uint groupsX;

	groupsX = (liveCount+63)/64;
	dispatchIndirectArgs.Store3(0, uint3(groupsX, 1, 1));

	groupsX = (deadCount+63)/64;
	dispatchDeadIndirectArgs.Store3(0, uint3(groupsX, 1, 1));
}

#ifndef __ORBIS__

technique11 DefragUpdatePopulation
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefragUpdatePopulation() ) );
	}
};

#endif //! __ORBIS__
