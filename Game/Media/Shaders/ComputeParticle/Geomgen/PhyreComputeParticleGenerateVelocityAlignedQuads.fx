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
StructuredBuffer<PParticleSizeStruct>			particle_Size;						// The optional structure buffer containing input particle size.
RWByteAddressBuffer								output_Vertex;						// The buffer to contain the output stream of positions (tri list).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.

cbuffer geomGenStateBuffer
{
	PGenerateVelocityAlignedQuadsStateStruct	geomGenState;						// The geom gen state for generating camera aligned quads.
}
float3 crossLeftCamera;
float3 crossUpCamera;

[numthreads(64, 1, 1)]
void CS_GenerateVelocityAlignedQuads(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		uint outByteOffset = outputOffset + (particleIndex * 6 * 12);	// 6 vertices, float3 per vertex (size 12).

		// Find out which input streams we have.
		uint sizeCount = 0;
		uint sizeStride = 0;
		particle_Size.GetDimensions(sizeCount, sizeStride);
		bool hasSize = (sizeCount > 0);

		// Precalculate some state.
		float stateSize = geomGenState.m_size;
		float stateAspect = geomGenState.m_aspect;
		float stateOffset = geomGenState.m_offset;
		float stretchFactor = geomGenState.m_speedStretchFactor;
		float3 left = crossLeftCamera * stateSize;
		float3 up = crossUpCamera * stateSize;
		float3 upLeft = up + left;
		float3 upRight = up - left;
		float3 axis = normalize(cross(left, up));

		// Generate our quad.
		float3 particlePos = particle_PositionVelocityLifetime[inIndex].m_location;
		float3 velocity = particle_PositionVelocityLifetime[inIndex].m_velocity;
		float3 tl, tr, br, bl, alignedUp;

		// Project velocity onto screen plane.
		float3 projectionCorrection = dot(velocity, axis) * axis;
		velocity = velocity - projectionCorrection;

		float speed = length(velocity);

		alignedUp = up;

		float particleWidth = stateSize;
		if (hasSize)
		{
			float particleSize = particle_Size[inIndex].m_size;
			particleWidth *= particleSize;
		}

		// Do we need to adjust the particle size based on speed.
		if (speed > 0.0f)
		{
			float particleLength = particleWidth * (1.0f + speed * stretchFactor);

			alignedUp = velocity * (1.0f/speed); // Normalize
			float3 alignedLeft = cross(alignedUp, axis);

			alignedUp *= particleLength;
			alignedLeft *= particleWidth * stateAspect;

			upLeft = alignedUp + alignedLeft;
			upRight = alignedUp - alignedLeft;
		}
		else
		{
			alignedUp *= particleWidth;
		}

		tl = particlePos + upLeft + alignedUp * stateOffset;
		tr = particlePos + upRight + alignedUp * stateOffset;
		br = particlePos - upLeft + alignedUp * stateOffset;
		bl = particlePos - upRight + alignedUp * stateOffset;

		// Write out the two triangles.
		output_Vertex.Store4(outByteOffset,    asint(float4(tl.xyz, tr.x)));
		output_Vertex.Store4(outByteOffset+16, asint(float4(tr.yz, br.xy)));
		output_Vertex.Store4(outByteOffset+32, asint(float4(br.z, tl.xyz)));
		output_Vertex.Store4(outByteOffset+48, asint(float4(br.xyz, bl.x)));
		output_Vertex.Store2(outByteOffset+64, asint(float2(bl.yz)));
	}
}

#ifndef __ORBIS__

technique11 GenerateVelocityAlignedQuads
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateVelocityAlignedQuads() ) );
	}
};

#endif //! __ORBIS__
