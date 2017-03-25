/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>										// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

uint startStage;															// The first stage to run.
uint endStage;																// The last stage to run.
StructuredBuffer<uint2> kjTable;											// The lookup table defining the sort stages.
RWByteAddressBuffer sortBuffer;												// The structure buffer containing the elements to sort.
StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;		// The particle system's state for the update (population, capacity, etc).

groupshared uint2 local_table[512 * 2];

uint PhyreBitCount32(uint word)
{
#ifdef __ORBIS__
	return CountSetBits(word);
#else //! __ORBIS__
	return countbits(word);
#endif //! __ORBIS__
}

uint TrailingZeroCount(uint val)
{
#ifdef __ORBIS__
	return FirstSetBit_Lo(val);
#else //! __ORBIS__
	return firstbitlow(val);
#endif //! __ORBIS__
}

[numthreads(PD_PARTICLE_BITONIC_THREADS_PER_GROUP, 1, 1)]
void CS_BitonicSortPass(uint3 groupID : SV_GroupID, uint3 group_threadID : SV_GroupThreadID)
{
	// Get particle count from system state and calculate log2.
	uint particleCount = particleSystemState[0].m_population;
	particleCount--;
	particleCount <<= 1;

	if (particleCount < (PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2))
		particleCount = (PD_PARTICLE_BITONIC_THREADS_PER_GROUP*2);

#ifdef __ORBIS__
	uint log2ParticleCount = FirstSetBit_Hi(particleCount);
#else //! __ORBIS__
	uint log2ParticleCount = firstbithigh(particleCount);
#endif //! __ORBIS__

	// Clamp stages to sufficient for particle count. This trims the worst case to actual case number of passes.
	uint maxStage = (log2ParticleCount * (log2ParticleCount+1)) / 2;
	uint lastStage = endStage;
	if (lastStage > (maxStage-1))
		lastStage = maxStage-1;

	if (startStage < lastStage)
	{
		// Build the mask and bit assignments.
		uint currentMask = PD_PARTICLE_LINEAR_ACCESS_MASK;

		// Or together the stage masks.
		uint stage = startStage;
		do
		{
			currentMask |= kjTable[stage++].y;
		}
		while (stage <= lastStage);

		// Adjust granularity when working set bits are not fully populated.  Fill zero bits starting at LSB until the bit count is numLocalBits.
		uint groupScale = PhyreBitCount32(currentMask);
		for(uint k = groupScale; k < PD_PARTICLE_NUM_LOCAL_BITS; k++)
		{
			uint lsbClear = ~currentMask & (currentMask+1);
			currentMask |= lsbClear;
		}
		currentMask |= (2 << log2ParticleCount);
		uint localBit0 = TrailingZeroCount(~currentMask);
		uint localBit1 = TrailingZeroCount(currentMask & ~((1U << localBit0) - 1));
		uint localBit2 = TrailingZeroCount(~currentMask & ~((1U << localBit1) - 1));
		uint localGap01 = localBit1 - localBit0;
		uint localGap12 = localBit2 - localBit1;

		// Loop invariants
		uint groupBits = groupID.x << localBit0;
		uint maskBit0 = (((uint)1) << localBit0) - 1;
		uint maskBit1 = (((uint)1) << localBit1) - 1;
		groupBits = (groupBits & maskBit1) | ((groupBits & ~maskBit1) << localGap12);

		stage = startStage;

		uint2 kj = kjTable[stage];
		uint shiftK = kj.x;
		uint j = kj.y;

		uint localJMask = ((uint)1 << localBit1) - 1;
		uint localJ = (j & localJMask) | ((j & ~localJMask) >> localGap01);

		uint mask = localJ - 1;
		uint threadBits = group_threadID.x;
		uint local_index = (threadBits & mask) | ((threadBits & ~mask) << 1);				// Spread local_index apart at localJ bit.
		threadBits = (local_index & maskBit0) | ((local_index & ~maskBit0) << localGap01);
		uint index = groupBits + threadBits;

		// Load initial data from the structured buffer
		uint2 data0 = sortBuffer.Load2(index*8);
		uint2 data1 = sortBuffer.Load2((index + j)*8);

		// XOR k bit with compare to determine uphill/downhill intervals.
		uint swapEls = ((index >> shiftK) ^ (asfloat(data1.y) < asfloat(data0.y))) & 1;

		// Write first results back to LDS - subsequent sorting will be done in LDS apart from the final pass that writes back to the structured buffer.
		uint outOffset0 = local_index;
		uint outOffset1 = local_index + localJ;
		if (swapEls)
		{
			outOffset0 = local_index + localJ;
			outOffset1 = local_index;
		}
		local_table[outOffset0] = data0;
		local_table[outOffset1] = data1;

		while (true)
		{
			++stage;
			kj = kjTable[stage];
			shiftK = kj.x;
			j = kj.y;

			localJ = (j & localJMask) | ((j & ~localJMask) >> localGap01);				// The local J step in LDS.

			mask = localJ - 1;
			threadBits = group_threadID.x;
			local_index = (threadBits & mask) | ((threadBits & ~mask) << 1);				// Spread local_index apart at localJ bit.
			threadBits = (local_index & maskBit0) | ((local_index & ~maskBit0) << localGap01);
			index = groupBits + threadBits;

			// Wait for all the other shader instances to reach here so we read the correct data.
			GroupMemoryBarrierWithGroupSync();

			// Read data from LDS.
			data0 = local_table[local_index];
			data1 = local_table[local_index + localJ];

			// XOR k bit with compare to determine uphill/downhill intervals.
			swapEls = ((index >> shiftK) ^ (asfloat(data1.y) < asfloat(data0.y))) & 1;

			if (stage >= lastStage)									// Is this is the last pass...
			{
				// Exit loop to write data back to structured buffer.
				break;
			}
			if (swapEls)
			{
				local_table[local_index + localJ] = data0;
				local_table[local_index] = data1;
			}
		}

		outOffset0 = index;
		outOffset1 = (index+j);
		if (swapEls)
		{
			outOffset0 = (index+j);
			outOffset1 = index;
		}
		sortBuffer.Store2(outOffset0*8, data0);
		sortBuffer.Store2(outOffset1*8, data1);
	}
}

#ifndef __ORBIS__

technique11 BitonicSortPass
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_BitonicSortPass() ) );
	}
};

#endif //! __ORBIS__
