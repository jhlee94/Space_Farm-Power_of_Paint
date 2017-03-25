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
RWStructuredBuffer<PParticleColorStruct>				particle_Color;							// The structure buffer containing particle color.
cbuffer updateStateBuffer
{
	PUpdateColorFromSplineEnvelopeStateStruct			updateState;							// The update state for updating color.
};

[numthreads(64, 1, 1)]
void CS_UpdateColorFromSplineEnvelope(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float parametricLifetime = getParametricLifetime(particle_PositionVelocityLifetime[particleIndex]);
		float t = distortTime(parametricLifetime, updateState.m_time1, updateState.m_time2, updateState.m_repeatCount);

		float4 color = float4(0.0f,0.0f,0.0f,0.0f);
		float4 cA0 = updateState.m_colorA0;
		float4 cA1 = updateState.m_colorA1;
		float4 cA2 = updateState.m_colorA2;
		float4 cA3 = updateState.m_colorA3;
		float4 cB0 = updateState.m_colorB0;
		float4 cB1 = updateState.m_colorB1;
		float4 cB2 = updateState.m_colorB2;
		float4 cB3 = updateState.m_colorB3;
		float i = getInterpolator(particle_EnvelopeInterpolators[particleIndex], updateState.m_interpolatorSelect);
		switch (updateState.m_curveMethod)
		{
			default:
			case PE_PARTICLECURVE_BEZIER:
				color = particleBezierInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_LINEAR:
				color = particleLinearInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_STEP:
				color = particleStepInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
		}

		particle_Color[particleIndex].m_color = color;
	}
}

#ifndef __ORBIS__

technique11 UpdateColorFromSplineEnvelope
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateColorFromSplineEnvelope() ) );
	}
};

#endif //! __ORBIS__
