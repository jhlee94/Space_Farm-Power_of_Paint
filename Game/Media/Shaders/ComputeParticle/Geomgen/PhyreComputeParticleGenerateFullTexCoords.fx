/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>												// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).

RWByteAddressBuffer								output_ST;							// The buffer to contain output texture coordinate (trilist).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.

[numthreads(64, 1, 1)]
void CS_GenerateFullTexCoords(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our population.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		uint outByteOffset = outputOffset + (particleIndex * 6 * 8);				// 6 vertices, float2 per vertex (size 8).

		// Emit to the 6 vertices for the tri-list.
		output_ST.Store4(outByteOffset,    asint(float4(0, 0, 1, 0)));
		output_ST.Store4(outByteOffset+16, asint(float4(1, 1, 0, 0)));
		output_ST.Store4(outByteOffset+32, asint(float4(1, 1, 0, 1)));
	}
}

#ifndef __ORBIS__

technique11 GenerateFullTexCoords
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateFullTexCoords() ) );
	}
};

#endif //! __ORBIS__
