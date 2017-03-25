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
RWStructuredBuffer<PParticleOrientation2DStruct>	particle_Orientation2D;	// The structure buffer containing particle 2D orientations.
cbuffer emissionStateBuffer
{
	PEmitOrientation2DStateStruct					emissionState;			// The emission state for emitting 2D orientations.
};

[numthreads(64, 1, 1)]
void CS_EmitOrientation2D(uint3 DispatchThreadId : SV_DispatchThreadID)
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
		uint2 vRandSeed = uint2(randSeed, randSeed + 1);

		// Generate sufficient random numbers for our emission.
		float2 r1 = genRandFloat2(vRandSeed);

		// Generate the "random" orientation based on the emission state.
		float emittedOrientation = interpSpread(emissionState.m_orientation, emissionState.m_orientationVariance, r1.x);
		float emittedAngularVelocity = interpSpread(emissionState.m_angularVelocity, emissionState.m_angularVelocityVariance, r1.y);

		particle_Orientation2D[particleIndex].m_orientation = emittedOrientation;
		particle_Orientation2D[particleIndex].m_angularVelocity = emittedAngularVelocity;
	}
}

#ifndef __ORBIS__

technique11 EmitOrientation2D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitOrientation2D() ) );
	}
};

#endif //! __ORBIS__
