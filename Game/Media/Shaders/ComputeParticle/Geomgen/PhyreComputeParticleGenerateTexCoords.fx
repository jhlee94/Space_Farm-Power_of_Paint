/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>									// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;	// The particle system's state for the update (population, capacity, time step, etc).
ByteAddressBuffer								sortBuffer;							// The optional sort buffer supplied if the particles have been depth sorted.
StructuredBuffer<PParticleTexCoordsStruct>		particle_TexCoords;		// The structure buffer containing input particle texture coordinates.
RWByteAddressBuffer								output_ST;				// The buffer to contain output texture coordinate (trilist).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.

[numthreads(64, 1, 1)]
void CS_GenerateTexCoords(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		// Load the particle texture coordinates.
		float2 minTc = float2(particle_TexCoords[inIndex].m_minU,
				      particle_TexCoords[inIndex].m_minV);
		float2 maxTc = float2(particle_TexCoords[inIndex].m_maxU,
				      particle_TexCoords[inIndex].m_maxV);

		// Emit to the 6 vertices for the tri-list.
		output_ST.Store4(outByteOffset,    asint(float4(minTc.x, minTc.y, maxTc.x, minTc.y)));
		output_ST.Store4(outByteOffset+16, asint(float4(maxTc.x, maxTc.y, minTc.x, minTc.y)));
		output_ST.Store4(outByteOffset+32, asint(float4(maxTc.x, maxTc.y, minTc.x, maxTc.y)));
	}
}

#ifndef __ORBIS__

technique11 GenerateTexCoords
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateTexCoords() ) );
	}
};

#endif //! __ORBIS__
