/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../../PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "../Common/PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;				// The particle system's state for the update (population, capacity, etc).
StructuredBuffer<PParticleStateStruct>				particle_PositionVelocityLifetime;	// The structure buffer containing particle position.
RWStructuredBuffer<PEmitterBounds>					intermediateBounds;					// The intermediate bounds array input.

groupshared float3 minBounds[512];														// The collapsed minimum bounds.
groupshared float3 maxBounds[512];														// The collapsed maximum bounds.

// Description:
// Fold two bounds and store the result in the lower slot.
// Arguments:
// minBB - The tracked bounds minimum for the current thread ID.
// maxBB - The tracked bounds minimum for the current thread ID.
// step - The separation for the fold.
// tid - The current thread ID.
void fold(inout float3 minBB, inout float3 maxBB, uint step, uint tid)
{
	if (tid < step)
	{
		minBB = min(minBB, minBounds[tid+step]);
		maxBB = max(maxBB, maxBounds[tid+step]);
		minBounds[tid] = minBB;
		maxBounds[tid] = maxBB;
	}
	GroupMemoryBarrierWithGroupSync();
}

// Description:
// Collapse the 512 entry LDS bounds buffer down to a single bounds at element 0.
// Arguments:
// tid - The thread ID within the thread group.
void foldLdsBoundsBuffer(uint tid)
{
	// Now fold the 512 entries down to 1 and write the the intermediate buffer.

	// We are the only thread that can write minBounds[tid] and maxBounds[tid].  Own it...!
	// However other threads may read it to accumulate it into their totals. further down, so we do need to write it at each stage.
	float3 minBB = minBounds[tid];
	float3 maxBB = maxBounds[tid];

	fold(minBB, maxBB, 256, tid);
	fold(minBB, maxBB, 128, tid);
	fold(minBB, maxBB, 64, tid);
	fold(minBB, maxBB, 32, tid);
	fold(minBB, maxBB, 16, tid);
	fold(minBB, maxBB, 8, tid);
	fold(minBB, maxBB, 4, tid);
	fold(minBB, maxBB, 2, tid);
	fold(minBB, maxBB, 1, tid);
}

[numthreads(512, 1, 1)]
void CS_UpdateBoundsStage1(uint3 dispatchThreadID : SV_DispatchThreadID, uint3 groupID : SV_GroupID, uint3 group_threadID : SV_GroupThreadID)
{
	uint particleCount = particleSystemState[0].m_population;

	uint sourceParticleIndex1 = dispatchThreadID.x*2;		// The indices of the two particles we shall merge in the first pass.
	uint sourceParticleIndex2 = dispatchThreadID.x*2+1;

	float3 minOut = float3( 100000.0f,  100000.0f,  100000.0f);
	float3 maxOut = float3(-100000.0f, -100000.0f, -100000.0f);

	// First pass - take the 128 input particles and generate bounds for the pairs of positions.
	if (sourceParticleIndex1 < particleCount)
	{
		float3 pos;

		// Particle 1 is valid.
		pos = particle_PositionVelocityLifetime[sourceParticleIndex1 + particleSystemState[0].m_baseIndex].m_location;
		minOut = pos;
		maxOut = pos;
		if (sourceParticleIndex2 < particleCount)
		{
			// Particle 2 is valid.
			pos = particle_PositionVelocityLifetime[sourceParticleIndex2 + particleSystemState[0].m_baseIndex].m_location;
			minOut = min(minOut, pos);
			maxOut = max(maxOut, pos);
		}
	}

	uint tid = group_threadID.x;							// The index of the thread within the thread group.
	minBounds[tid] = minOut;
	maxBounds[tid] = maxOut;
	GroupMemoryBarrierWithGroupSync();

	foldLdsBoundsBuffer(tid);

	if (tid < 1)
	{
		// Write the value back out to the intermediate buffer.
		intermediateBounds[groupID.x].m_min = minBounds[0];
		intermediateBounds[groupID.x].m_max = maxBounds[0];
	}
}

#ifndef __ORBIS__

technique11 UpdateBoundsStage1
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateBoundsStage1() ) );
	}
};

#endif //! __ORBIS__
