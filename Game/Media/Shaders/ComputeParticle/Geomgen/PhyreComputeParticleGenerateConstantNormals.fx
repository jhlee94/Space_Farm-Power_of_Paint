/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>									// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;	// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer								output_Normal;			// The buffer to contain output normal stream (trilist).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.
cbuffer geomGenStateBuffer
{
	PGenerateConstantNormalsStateStruct			geomGenState;			// The geomGen state for generating contant normals.
};

[numthreads(64, 1, 1)]
void CS_GenerateConstantNormals(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our population.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		uint outIndex = particleIndex * 6;
		uint outByteOffset = outputOffset + (particleIndex * 6 * 12);	// 6 vertices, float3 per vertex (size 12).

		// Load the particle normal.
		float3 normal = geomGenState.m_normal;

		// Emit to the 6 vertices for the tri-list.
		output_Normal.Store4(outByteOffset,    asint(float4(normal.xyzx)));
		output_Normal.Store4(outByteOffset+16, asint(float4(normal.yzxy)));
		output_Normal.Store4(outByteOffset+32, asint(float4(normal.zxyz)));
		output_Normal.Store4(outByteOffset+48, asint(float4(normal.xyzx)));
		output_Normal.Store2(outByteOffset+64, asint(float2(normal.yz)));
	}
}

#ifndef __ORBIS__

technique11 GenerateConstantNormals
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateConstantNormals() ) );
	}
};

#endif //! __ORBIS__
