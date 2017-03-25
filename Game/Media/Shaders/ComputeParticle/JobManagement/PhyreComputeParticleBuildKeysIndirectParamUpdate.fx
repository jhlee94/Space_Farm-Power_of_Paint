/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer dispatchIndirectArgs;												// The particle system's dispatch indirect arguments for a full count.

uint roundNonZeroUpToPowerOf2(uint val)
{
	val--;
	val <<= 1;

#ifdef __ORBIS__
	uint hiBitNum = FirstSetBit_Hi(val);
#else //! __ORBIS__
	uint hiBitNum = firstbithigh(val);
#endif //! __ORBIS__

	val = 1<<hiBitNum;
	return val;
}

[numthreads(1, 1, 1)]
void CS_BitonicSortBuildKeysIndirectParamUpdate()
{
	// Grab the population from the particle state.
	uint population = particleSystemState[0].m_population;

	// Minimum size of 1024 particles.
	population = max(population, PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2);

	// Find the next accomodating power of two.
	population = roundNonZeroUpToPowerOf2(population);

	// Set up the dispatch indirect arguments.  These contain:
	//
	// uint32_t m_dimX;						X dimension of dispatch size.
	// uint32_t m_dimY;						Y dimension of dispatch size.
	// uint32_t m_dimZ;						Z dimension of dispatch size.

	dispatchIndirectArgs.Store3(0, uint3(population/64, 1, 1));
}

#ifndef __ORBIS__

technique11 BitonicSortBuildKeysIndirectParamUpdate
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_BitonicSortBuildKeysIndirectParamUpdate() ) );
	}
};

#endif //! __ORBIS__
