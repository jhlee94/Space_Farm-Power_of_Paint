/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

uint												emissionCount;						// The number of particles to be emitted.
StructuredBuffer<ParticleStateBufferInfoStruct>		deadParticleSystemState;			// The death emission particle system's state for the update (population, capacity, time step, etc).
uint												deadParticleEmissionMultiplier;		// The number of particles to emit for each pre-deceased particle.
RWByteAddressBuffer									dispatchIndirectArgs;				// The particle system's dispatch indirect arguments for a full count.

[numthreads(1, 1, 1)]
void CS_EmitIndirectParamUpdate()
{
	uint count = emissionCount;

	// Set up the dispatch indirect arguments.  These contain:
	//
	// uint32_t m_dimX;						X dimension of dispatch size.
	// uint32_t m_dimY;						Y dimension of dispatch size.
	// uint32_t m_dimZ;						Z dimension of dispatch size.

	dispatchIndirectArgs.Store3(0, uint3((count+63)/64, 1, 1));
}

[numthreads(1, 1, 1)]
void CS_EmitDeathIndirectParamUpdate()
{
	uint deadParticleCount = deadParticleSystemState[0].m_deadPopulation * deadParticleEmissionMultiplier;
	uint count = min(emissionCount, deadParticleCount);

	// Set up the dispatch indirect arguments.  These contain:
	//
	// uint32_t m_dimX;						X dimension of dispatch size.
	// uint32_t m_dimY;						Y dimension of dispatch size.
	// uint32_t m_dimZ;						Z dimension of dispatch size.

	dispatchIndirectArgs.Store3(0, uint3((count+63)/64, 1, 1));
}

#ifndef __ORBIS__

technique11 EmitIndirectParamUpdate
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitIndirectParamUpdate() ) );
	}
};

technique11 EmitDeathIndirectParamUpdate
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitDeathIndirectParamUpdate() ) );
	}
};

#endif //! __ORBIS__
