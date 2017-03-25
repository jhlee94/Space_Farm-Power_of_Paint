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
RWStructuredBuffer<PParticleOrientation2DStruct>		particle_Orientation2D;					// The structure buffer containing particle orientation.
cbuffer updateStateBuffer
{
	PUpdateOrientation2DFromSplineEnvelopeStateStruct	updateState;					// The update state for updating 2D orientation.
};

[numthreads(64, 1, 1)]
void CS_UpdateOrientation2DFromSplineEnvelope(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float parametricLifetime = getParametricLifetime(particle_PositionVelocityLifetime[particleIndex]);
		float t = distortTime(parametricLifetime, updateState.m_time1, updateState.m_time2, updateState.m_repeatCount);

		float orientation = 0.0f;
		float cA0 = updateState.m_orientationA0;
		float cA1 = updateState.m_orientationA1;
		float cA2 = updateState.m_orientationA2;
		float cA3 = updateState.m_orientationA3;
		float cB0 = updateState.m_orientationB0;
		float cB1 = updateState.m_orientationB1;
		float cB2 = updateState.m_orientationB2;
		float cB3 = updateState.m_orientationB3;
		float i = getInterpolator(particle_EnvelopeInterpolators[particleIndex], updateState.m_interpolatorSelect);
		switch (updateState.m_curveMethod)
		{
			default:
			case PE_PARTICLECURVE_BEZIER:
				orientation = particleBezierInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_LINEAR:
				orientation = particleLinearInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
			case PE_PARTICLECURVE_STEP:
				orientation = particleStepInterpolateEnvelope(t, i, cA0, cA1, cA2, cA3, cB0, cB1, cB2, cB3);
				break;
		}

		particle_Orientation2D[particleIndex].m_orientation = orientation;
	}
}

#ifndef __ORBIS__

technique11 UpdateOrientation2DFromSplineEnvelope
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateOrientation2DFromSplineEnvelope() ) );
	}
};

#endif //! __ORBIS__
