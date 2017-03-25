/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "..\Common\PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>			particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).
float timeDelta;																				// The time step for which to update the particle system.
StructuredBuffer<PParticleStateStruct>					particle_PositionVelocityLifetime;		// The structure buffer containing particle time.
StructuredBuffer<PParticleEnvelopeInterpolatorsStruct>	particle_EnvelopeInterpolators;			// The structure buffer containing particle envelope interpolators.
RWStructuredBuffer<PParticleOrientation2DStruct>		particle_Orientation2D;					// The structure buffer containing particle orientation.
cbuffer updateStateBuffer
{
	PUpdateAngularVelocity2DFromSplineEnvelopeStateStruct	updateState;					// The update state for updating angular velocity.
};

[numthreads(64, 1, 1)]
void CS_UpdateAngularVelocity2DFromSplineEnvelope(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float parametricLifetime = getParametricLifetime(particle_PositionVelocityLifetime[particleIndex]);
		float t = distortTime(parametricLifetime, updateState.m_time1, updateState.m_time2, updateState.m_repeatCount);

		float angularVelocity = 0.0f;
		float cA0 = updateState.m_angularVelocityA0;
		float cA1 = updateState.m_angularVelocityA1;
		float cA2 = updateState.m_angularVelocityA2;
		float cA3 = updateState.m_angularVelocityA3;
		float cB0 = updateState.m_angularVelocityB0;
		float cB1 = updateState.m_angularVelocityB1;
		float cB2 = updateState.m_angularVelocityB2;
		float cB3 = updateState.m_angularVelocityB3;
		float i = getInterpolator(particle_EnvelopeInterpolators[particleIndex], updateState.m_interpolatorSelect);
		switch (updateState.m_curveMethod)
		{
			default:
			case PE_PARTICLECURVE_BEZIER:
				angularVelocity = particleBezierInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_LINEAR:
				angularVelocity = particleLinearInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_STEP:
				angularVelocity = particleStepInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
		}

		particle_Orientation2D[particleIndex].m_angularVelocity = angularVelocity;
	}
}

#ifndef __ORBIS__

technique11 UpdateAngularVelocity2DFromSplineEnvelope
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateAngularVelocity2DFromSplineEnvelope() ) );
	}
};

#endif //! __ORBIS__
