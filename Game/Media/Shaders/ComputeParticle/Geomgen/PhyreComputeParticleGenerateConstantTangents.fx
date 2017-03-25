/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>									// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;	// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer								output_Tangent;			// The buffer to contain output tangent stream (trilist).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.
cbuffer geomGenStateBuffer
{
	PGenerateConstantTangentsStateStruct		geomGenState;			// The geomGen state for generating contant tangents.
};

[numthreads(64, 1, 1)]
void CS_GenerateConstantTangents(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our population.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		uint outIndex = particleIndex * 6;
		uint outByteOffset = outputOffset + (particleIndex * 6 * 12);	// 6 vertices, float3 per vertex (size 12).

		// Load the particle tangent.
		float3 tangent = geomGenState.m_tangent;

		// Emit to the 6 vertices for the tri-list.
		output_Tangent.Store4(outByteOffset,    asint(float4(tangent.xyzx)));
		output_Tangent.Store4(outByteOffset+16, asint(float4(tangent.yzxy)));
		output_Tangent.Store4(outByteOffset+32, asint(float4(tangent.zxyz)));
		output_Tangent.Store4(outByteOffset+48, asint(float4(tangent.xyzx)));
		output_Tangent.Store2(outByteOffset+64, asint(float2(tangent.yz)));
	}
}

#ifndef __ORBIS__

technique11 GenerateConstantTangents
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateConstantTangents() ) );
	}
};

#endif //! __ORBIS__
