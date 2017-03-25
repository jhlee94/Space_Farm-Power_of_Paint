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
RWStructuredBuffer<PParticleTexCoordsStruct>		particle_TexCoords;		// The structure buffer containing particle texture coordinates.
cbuffer emissionStateBuffer
{
	PEmitTexCoordTileStateStruct					emissionState;			// The emission state for emitting texture coordinates.
};

[numthreads(64, 1, 1)]
void CS_EmitTexCoordTile(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		// Load the emission state.
		uint tilesU = emissionState.m_tilesU;
		uint tilesV = emissionState.m_tilesV;
		float tileSizeU = 1.0f / tilesU;
		float tileSizeV = 1.0f / tilesV;

		// Generate the "random" tile based on the emission state.
		float rFloat = genRandFloat(randSeed);
		uint r = asint(rFloat);

		uint tileU = r % tilesU;
		uint tileV = (r>>16) % tilesV;
		float u = tileU * tileSizeU;
		float v = tileV * tileSizeV;

		particle_TexCoords[particleIndex].m_minU = u;
		particle_TexCoords[particleIndex].m_minV = v;
		particle_TexCoords[particleIndex].m_maxU = u + tileSizeU;
		particle_TexCoords[particleIndex].m_maxV = v + tileSizeV;
	}
}

#ifndef __ORBIS__

technique11 EmitTexCoordTile
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitTexCoordTile() ) );
	}
};

#endif //! __ORBIS__
