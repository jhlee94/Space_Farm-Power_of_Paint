/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

RWStructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
StructuredBuffer<ParticleStateBufferInfoStruct>		deadParticleSystemState;			// The death emission particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer									dispatchIndirectArgs;				// The particle system's dispatch indirect arguments for a full count.
uint												emissionCount;						// The number of particles to emit.
uint												deadParticleEmissionMultiplier;		// The emission multiplier for emitting from dead particles.

[numthreads(1, 1, 1)]
void CS_EmitUpdatePopulation()
{
	// Increase the population count.
	uint population = particleSystemState[0].m_population;
	population += emissionCount;
	if (population > particleSystemState[0].m_capacity)
		population = particleSystemState[0].m_capacity;
	particleSystemState[0].m_population = population;

	uint groupsX = (population+63)/64;
	dispatchIndirectArgs.Store3(0, uint3(groupsX, 1, 1));
}

// The population update for when death emission is used - this caps the emission to the actual death particle count.
[numthreads(1, 1, 1)]
void CS_EmitUpdatePopulationDeath()
{
	// Increase the population count.
	uint population = particleSystemState[0].m_population;
	uint deadCount = deadParticleSystemState[0].m_deadPopulation * deadParticleEmissionMultiplier;
	population += min(emissionCount, deadCount);
	if (population > particleSystemState[0].m_capacity)
		population = particleSystemState[0].m_capacity;
	particleSystemState[0].m_population = population;

	uint groupsX = (population+63)/64;
	dispatchIndirectArgs.Store3(0, uint3(groupsX, 1, 1));
}

#ifndef __ORBIS__

technique11 EmitUpdatePopulation
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitUpdatePopulation() ) );
	}
};

technique11 EmitUpdatePopulationDeath
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitUpdatePopulationDeath() ) );
	}
};

#endif //! __ORBIS__
