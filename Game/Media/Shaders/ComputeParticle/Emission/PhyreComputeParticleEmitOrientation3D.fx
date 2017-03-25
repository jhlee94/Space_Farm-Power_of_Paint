/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>										// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "../Common/PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;	// The particle system's state for the update (population, capacity, time step, etc).
uint												emissionCount;			// The number of particles to emit.
uint												randomSeed;								// The random seed for tihs emission.  Offset by dispatch thread ID and then permute.
RWStructuredBuffer<PParticleOrientation3DStruct>	particle_Orientation3D;	// The structure buffer containing particle 3D orientations.

[numthreads(64, 1, 1)]
void CS_EmitOrientation3D(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	uint topEndOfEmissionWindow = emissionCount + state.m_population;
	if (topEndOfEmissionWindow > state.m_capacity)
		topEndOfEmissionWindow = state.m_capacity;
	uint particleIndex = DispatchThreadId.x;
	particleIndex += state.m_population;			// Append to the end of the live particles.

	if (particleIndex < topEndOfEmissionWindow)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		// Set up random number generator.
		uint randSeed = randomSeed + DispatchThreadId.x * 20;
		uint4 vRandSeed = uint4(randSeed, randSeed + 1, randSeed + 2, randSeed + 3);

		// Generate the "random" orientation and angular velocity.
		float4 emittedOrientation = genRandFloat4(vRandSeed);
		float4 emittedAngularVelocity = genRandFloat4(vRandSeed);

		// Normalize if long enough, else set identity.
		if (length(emittedOrientation) > 0.0f)
			emittedOrientation = normalize(emittedOrientation);
		else
			emittedOrientation = float4(0,0,0,1);

		if (length(emittedAngularVelocity) > 0.0f)
			emittedAngularVelocity = normalize(emittedAngularVelocity);
		else
			emittedAngularVelocity = float4(0,0,0,1);

		particle_Orientation3D[particleIndex].m_orientation = emittedOrientation;
		particle_Orientation3D[particleIndex].m_angularVelocity = emittedAngularVelocity;
	}
}

#ifndef __ORBIS__

technique11 EmitOrientation3D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitOrientation3D() ) );
	}
};

#endif //! __ORBIS__
