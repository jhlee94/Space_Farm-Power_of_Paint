/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>										// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "../Common/PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;	// The particle system's state for the update (population, capacity, time step, etc).
uint												emissionCount;			// The number of particles to emit.
uint												randomSeed;								// The random seed for tihs emission.  Offset by dispatch thread ID and then permute.
RWStructuredBuffer<PParticleSizeStruct>				particle_Size;			// The structure buffer containing particle sizes.
cbuffer emissionStateBuffer
{
	PEmitSizeStateStruct							emissionState;			// The emission state for emitting sizes.
};

[numthreads(64, 1, 1)]
void CS_EmitSize(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	uint topEndOfEmissionWindow = emissionCount + state.m_population;
	if (topEndOfEmissionWindow > state.m_capacity)
		topEndOfEmissionWindow = state.m_capacity;
	uint particleIndex = DispatchThreadId.x;
	particleIndex += state.m_population;			// Append to the end of the live particles.

	if (particleIndex < topEndOfEmissionWindow)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		// Set up random number generator.
		uint randSeed = randomSeed + DispatchThreadId.x * 20;

		// Generate sufficient random numbers for our emission.
		float r1 = genRandFloat(randSeed);

		// Generate the "random" size based on the emission state.
		float emittedSize = interpSpread(emissionState.m_size, emissionState.m_sizeVariance, r1.x);

		particle_Size[particleIndex].m_size = emittedSize;
	}
}

#ifndef __ORBIS__

technique11 EmitSize
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitSize() ) );
	}
};

#endif //! __ORBIS__
