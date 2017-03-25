/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>												// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "..\Common\PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
ByteAddressBuffer								sortBuffer;							// The optional sort buffer supplied if the particles have been depth sorted.
StructuredBuffer<PParticleStateStruct>			particle_PositionVelocityLifetime;	// The structure buffer containing input particle position.
StructuredBuffer<PParticleSizeStruct>			particle_Size;						// The optional structure buffer containing input particle size.
StructuredBuffer<PParticleOrientation2DStruct>	particle_Orientation2D;				// The optional structure buffer containing input particle orientation.
RWByteAddressBuffer								output_Vertex;						// The buffer to contain the output stream of positions (tri list).
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.

cbuffer geomGenStateBuffer
{
	PGenerateCameraAlignedQuadsStateStruct	geomGenState;							// The geom gen state for generating camera aligned quads.
}
float3 crossLeftCamera;
float3 crossUpCamera;

[numthreads(64, 1, 1)]
void CS_GenerateCameraAlignedQuads(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our population.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		uint count = 0;
		uint stride = 0;

		uint inIndex = particleIndex;

		// Remap the source particle index through the sort buffer if the system is depth sorted.
		sortBuffer.GetDimensions(count);
		if (count > 0)
			inIndex = sortBuffer.Load(inIndex*8);

		inIndex += state.m_baseIndex;				// Adjust to be in the correct budget block portion.

		uint outByteOffset = outputOffset + (particleIndex * 6 * 12);	// 6 vertices, float3 per vertex (size 12).

		// Precalculate some state.
		float3 left = crossLeftCamera;
		float3 up = crossUpCamera;
		float size = geomGenState.m_size;

		// Do we have per-particle orientation to process?
		particle_Orientation2D.GetDimensions(count, stride);
		if (count > 0)
		{
			// Rotate left and up axes by orientation.
			float3 axis = normalize(cross(left, up));
			float orientation = particle_Orientation2D[inIndex].m_orientation;
			float3x3 rotation = rotationMatrix(orientation, axis);
			up = mul(rotation, up);
			left = mul(rotation, left);
		}

		// Do we have per-particle size to process.
		particle_Size.GetDimensions(count, stride);
		if (count > 0)
		{
			// Apply particle size.
			size *= particle_Size[inIndex].m_size;
		}

		left *= size;
		up *= size;

		// Generate our quad.
		float3 particlePos = particle_PositionVelocityLifetime[inIndex].m_location;
		float3 upLeft = up + left;
		float3 upRight = up - left;

		float3 tl = particlePos + upLeft;
		float3 br = particlePos - upLeft;
		float3 tr = particlePos + upRight;
		float3 bl = particlePos - upRight;

		// Write out the two triangles.
		output_Vertex.Store4(outByteOffset,    asint(float4(tl.xyz, tr.x)));
		output_Vertex.Store4(outByteOffset+16, asint(float4(tr.yz, br.xy)));
		output_Vertex.Store4(outByteOffset+32, asint(float4(br.z, tl.xyz)));
		output_Vertex.Store4(outByteOffset+48, asint(float4(br.xyz, bl.x)));
		output_Vertex.Store2(outByteOffset+64, asint(float2(bl.yz)));
	}
}

#ifndef __ORBIS__

technique11 GenerateCameraAlignedQuads
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateCameraAlignedQuads() ) );
	}
};

#endif //! __ORBIS__
