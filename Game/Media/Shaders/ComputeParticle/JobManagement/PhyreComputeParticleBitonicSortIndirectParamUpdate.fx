/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer dispatchIndirectArgs0;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs1;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs2;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs3;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs4;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs5;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs6;												// The particle system's dispatch indirect arguments for a full count.
RWByteAddressBuffer dispatchIndirectArgs7;												// The particle system's dispatch indirect arguments for a full count.
uint k;																					// The k value for the bitonic pass to be run.

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
void CS_BitonicSortPassIndirectParamUpdate()
{
	// Grab the population from the particle state.
	uint population = particleSystemState[0].m_population;

	// Minimum size of 1024 particles.
	population = max(population, PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2);

	// Find the next accomodating power of two.
	population = roundNonZeroUpToPowerOf2(population);

	// Calculate populations for each of the indirect args for 8 successive bitonic passes.
	uint population0 = ((k  )   > population) ? 0 : population;
	uint population1 = ((k*2)   > population) ? 0 : population;
	uint population2 = ((k*4)   > population) ? 0 : population;
	uint population3 = ((k*8)   > population) ? 0 : population;
	uint population4 = ((k*16)  > population) ? 0 : population;
	uint population5 = ((k*32)  > population) ? 0 : population;
	uint population6 = ((k*64)  > population) ? 0 : population;
	uint population7 = ((k*128) > population) ? 0 : population;

	// Set up the dispatch indirect arguments.  These contain:
	//
	// uint32_t m_dimX;						X dimension of dispatch size.
	// uint32_t m_dimY;						Y dimension of dispatch size.
	// uint32_t m_dimZ;						Z dimension of dispatch size.

	// We issue half the instances for the sort pass - each instance compares two elements.  Thread count per group is 512.
	dispatchIndirectArgs0.Store3(0, uint3(population0/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs1.Store3(0, uint3(population1/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs2.Store3(0, uint3(population2/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs3.Store3(0, uint3(population3/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs4.Store3(0, uint3(population4/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs5.Store3(0, uint3(population5/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs6.Store3(0, uint3(population6/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
	dispatchIndirectArgs7.Store3(0, uint3(population7/(PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2), 1, 1));
}

#ifndef __ORBIS__

technique11 BitonicSortPassIndirectParamUpdate
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_BitonicSortPassIndirectParamUpdate() ) );
	}
};

#endif //! __ORBIS__
