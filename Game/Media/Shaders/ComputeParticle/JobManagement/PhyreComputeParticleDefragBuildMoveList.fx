/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

// Discard live particle indices that live within range.  Build mapping pairs from out-of-range live to dead indices.
StructuredBuffer<uint>								liveIndexCount;						// The structured buffer containing the new live particle count.
StructuredBuffer<uint>								particleLiveIndices;				// The list of live particle indices.
ConsumeStructuredBuffer<uint>						particleDeadIndices;				// The list of dead particle indices.
AppendStructuredBuffer<uint2>						particleLiveToDeadIndices;			// The list of live to dead index mappings.

[numthreads(64, 1, 1)]
void CS_DefragBuildMoveList(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint liveCount = liveIndexCount[0];

	if (DispatchThreadId.x < liveCount)
	{
		uint liveParticleIndex = particleLiveIndices[DispatchThreadId.x];
		if (liveParticleIndex >= liveCount)
		{
			uint deadParticleIndex = particleDeadIndices.Consume();

			uint2	liveToDead = uint2(liveParticleIndex, deadParticleIndex);
			particleLiveToDeadIndices.Append(liveToDead);
		}
	}
}

#ifndef __ORBIS__

technique11 DefragBuildMoveList
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DefragBuildMoveList() ) );
	}
};

#endif //! __ORBIS__
