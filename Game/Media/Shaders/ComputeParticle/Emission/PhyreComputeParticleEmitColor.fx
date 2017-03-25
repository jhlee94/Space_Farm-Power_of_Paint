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
RWStructuredBuffer<PParticleColorStruct>			particle_Color;			// The structure buffer containing particle colors.
cbuffer emissionStateBuffer
{
	PEmitColorStateStruct							emissionState;			// The emission state for emitting colors.
};

[numthreads(64, 1, 1)]
void CS_EmitColor(uint3 DispatchThreadId : SV_DispatchThreadID)
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

		// Generate sufficient random numbers for our emission.
		float4 r1 = genRandFloat4(vRandSeed);

		// Generate the "random" color based on the emission state.
		float4 emittedColor = interpSpread(emissionState.m_color, emissionState.m_colorVariance, r1);

		particle_Color[particleIndex].m_color = emittedColor;
	}
}

#ifndef __ORBIS__

technique11 EmitColor
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_EmitColor() ) );
	}
};

#endif //! __ORBIS__
