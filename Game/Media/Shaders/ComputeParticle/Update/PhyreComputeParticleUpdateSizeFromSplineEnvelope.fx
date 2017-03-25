/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "..\Common\PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>			particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).

StructuredBuffer<PParticleStateStruct>					particle_PositionVelocityLifetime;		// The structure buffer containing particle time.
StructuredBuffer<PParticleEnvelopeInterpolatorsStruct>	particle_EnvelopeInterpolators;			// The structure buffer containing particle envelope interpolators.
RWStructuredBuffer<PParticleSizeStruct>					particle_Size;							// The structure buffer containing particle size.
cbuffer updateStateBuffer
{
	PUpdateSizeFromSplineEnvelopeStateStruct			updateState;							// The update state for updating size.
};

[numthreads(64, 1, 1)]
void CS_UpdateSizeFromSplineEnvelope(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float parametricLifetime = getParametricLifetime(particle_PositionVelocityLifetime[particleIndex]);
		float t = distortTime(parametricLifetime, updateState.m_time1, updateState.m_time2, updateState.m_repeatCount);

		float size = 0.0f;
		float cA0 = updateState.m_sizeA0;
		float cA1 = updateState.m_sizeA1;
		float cA2 = updateState.m_sizeA2;
		float cA3 = updateState.m_sizeA3;
		float cB0 = updateState.m_sizeB0;
		float cB1 = updateState.m_sizeB1;
		float cB2 = updateState.m_sizeB2;
		float cB3 = updateState.m_sizeB3;
		float i = getInterpolator(particle_EnvelopeInterpolators[particleIndex], updateState.m_interpolatorSelect);
		switch (updateState.m_curveMethod)
		{
			default:
			case PE_PARTICLECURVE_BEZIER:
				size = particleBezierInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_LINEAR:
				size = particleLinearInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_STEP:
				size = particleStepInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
		}

		particle_Size[particleIndex].m_size = size;
	}
}

#ifndef __ORBIS__

technique11 UpdateSizeFromSplineEnvelope
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateSizeFromSplineEnvelope() ) );
	}
};

#endif //! __ORBIS__
