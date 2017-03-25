/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>									// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;	// The particle system's state for the update (population, capacity, time step, etc).
ByteAddressBuffer								sortBuffer;				// The optional sort buffer supplied if the particles have been depth sorted.
StructuredBuffer<PParticleColorStruct>			particle_Color;			// The structure buffer containing input particle colors.
RWByteAddressBuffer								output_Color;			// The buffer to contain output color stream (trilist).
uint											outputOffset;			// The byte offset in the output buffer to receive the generated data.

[numthreads(64, 1, 1)]
void CS_GenerateColor(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		uint outByteOffset = outputOffset + (particleIndex * 6 * 16);	// 6 verts, float4 (16 bytes) each.

		// Load the particle color.
		float4 color = particle_Color[inIndex].m_color;

		// Emit to the 6 vertices for the tri-list.
		output_Color.Store4(outByteOffset,    asint(color));
		output_Color.Store4(outByteOffset+16, asint(color));
		output_Color.Store4(outByteOffset+32, asint(color));
		output_Color.Store4(outByteOffset+48, asint(color));
		output_Color.Store4(outByteOffset+64, asint(color));
		output_Color.Store4(outByteOffset+80, asint(color));
	}
}

#ifndef __ORBIS__

technique11 GenerateColor
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateColor() ) );
	}
};

#endif //! __ORBIS__
