/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<uint>	particleMoveCount;											// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer dispatchIndirectArgs;												// The particle system's dispatch indirect arguments for a full count.

[numthreads(1, 1, 1)]
void CS_DefragMoveListIndirectParamUpdate()
{
	// Grab the population from the particle state.
	uint moveCount = particleMoveCount[0];

	// Set up the dispatch indirect arguments.  These contain:
	//
	// uint32_t m_dimX;						X dimension of dispatch size.
	// uint32_t m_dimY;						Y dimension of dispatch size.
	// uint32_t m_dimZ;						Z dimension of dispatch size.

	dispatchIndirectArgs.Store3(0, uint3((moveCount+63)/64, 1, 1));
}

#ifndef __ORBIS__

technique11 DefragMoveListIndirectParamUpdate
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefragMoveListIndirectParamUpdate() ) );
	}
};

#endif //! __ORBIS__
