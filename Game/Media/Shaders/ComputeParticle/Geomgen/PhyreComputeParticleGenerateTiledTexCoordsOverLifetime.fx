/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>												// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
ByteAddressBuffer								sortBuffer;							// The optional sort buffer supplied if the particles have been depth sorted.
StructuredBuffer<PParticleStateStruct>			particle_PositionVelocityLifetime;	// The structure buffer containing input particle position.
RWByteAddressBuffer								output_ST;							// The buffer to contain the texture coordinates (tri list).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.
cbuffer geomGenStateBuffer
{
	PGenerateTiledTexCoordsOverLifetimeStateStruct	geomGenState;					// The geomGen state for emitting tiled texture coordinates over lifetime.
};

[numthreads(64, 1, 1)]
void CS_GenerateTiledTexCoordsOverLifetime(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our population.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		uint inIndex = particleIndex;

		// Remap the source particle index through the sort buffer if the system is depth sorted.
		uint count = 0;
		sortBuffer.GetDimensions(count);
		if (count > 0)
			inIndex = sortBuffer.Load(inIndex*8);

		inIndex += state.m_baseIndex;				// Adjust to be in the correct budget block portion.

		uint outByteOffset = outputOffset + (particleIndex * 6 * 8);	// 6 vertices, float2 per vertex (size 8).

		// Load all the constant geomGen state.
		uint tilesU = geomGenState.m_tilesU;
		uint tilesV = geomGenState.m_tilesV;
		float loopsPerLifetime = geomGenState.m_repeatCount;
		uint tileCount = tilesU * tilesV;
		float2 tileSize = float2(1.0f/tilesU, -1.0f/tilesV);

		// Load the particle parametric lifetime and calculate the desired tile.
		float age = 1.0f - (particle_PositionVelocityLifetime[inIndex].m_lifetime * particle_PositionVelocityLifetime[inIndex].m_recipSpawnedLifetime);
		uint tileNum = (uint)(loopsPerLifetime * age * tileCount) % tileCount;

		uint tileU = tileNum % tilesU;
		uint tileV = tileNum / tilesU;

		float2 minTc = float2(tileU, tileV) * tileSize + float2(0,1);
		float2 maxTc = minTc + tileSize;

		// Emit texture coordinates for the texture tile.
		output_ST.Store4(outByteOffset,    asint(float4(minTc.x, minTc.y, maxTc.x, minTc.y)));
		output_ST.Store4(outByteOffset+16, asint(float4(maxTc.x, maxTc.y, minTc.x, minTc.y)));
		output_ST.Store4(outByteOffset+32, asint(float4(maxTc.x, maxTc.y, minTc.x, maxTc.y)));
	}
}

#ifndef __ORBIS__

technique11 GenerateTiledTexCoordsOverLifetime
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateTiledTexCoordsOverLifetime() ) );
	}
};

#endif //! __ORBIS__
