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
StructuredBuffer<PParticleOrientation3DStruct>	particle_Orientation3D;				// The structure buffer containing input particle orientation.
RWByteAddressBuffer								output_InstanceTransform0;			// The buffer to contain the instance transforms.
uint											outputOffset;						// The byte offset in the output buffer to receive the generated data.

[numthreads(64, 1, 1)]
void CS_GenerateInstanceTransforms(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		uint outByteOffset = outputOffset + (particleIndex * 3 * 16);	// 3 vertices, float4 per row (size 16).

		// Load the particle texture coordinates.
		float3 position = particle_PositionVelocityLifetime[inIndex].m_location;
		float4 orientation = particle_Orientation3D[inIndex].m_orientation;

		float3x3 rotation = rotationMatrixFromQuaternion(particle_Orientation3D[inIndex].m_orientation);

		// Emit an instance transform.
		output_InstanceTransform0.Store4(outByteOffset,    asint(float4(rotation[0], position.x)));
		output_InstanceTransform0.Store4(outByteOffset+16, asint(float4(rotation[1], position.y)));
		output_InstanceTransform0.Store4(outByteOffset+32, asint(float4(rotation[2], position.z)));
	}
}

#ifndef __ORBIS__

technique11 GenerateInstanceTransforms
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_GenerateInstanceTransforms() ) );
	}
};

#endif //! __ORBIS__
