/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>														// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.
#include "..\Common\PhyreComputeParticleCommon.h"

StructuredBuffer<ParticleStateBufferInfoStruct>		particleSystemState;					// The particle system's state for the update (population, capacity, time step, etc).

StructuredBuffer<PParticleStateStruct>				particle_PositionVelocityLifetime;		// The structure buffer containing particle time.
RWStructuredBuffer<PParticleOrientation2DStruct>	particle_Orientation2D;					// The structure buffer containing particle orientation.
cbuffer updateStateBuffer
{
	PUpdateAngularVelocity2DFromSplineStateStruct	updateState;							// The update state for updating angular velocity.
};

[numthreads(64, 1, 1)]
void CS_UpdateAngularVelocity2DFromSpline(uint3 DispatchThreadId : SV_DispatchThreadID)
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
		float c0 = updateState.m_angularVelocity0;
		float c1 = updateState.m_angularVelocity1;
		float c2 = updateState.m_angularVelocity2;
		float c3 = updateState.m_angularVelocity3;
		switch (updateState.m_curveMethod)
		{
			default:
			case PE_PARTICLECURVE_BEZIER:
				angularVelocity = particleBezierInterpolate(t, c0, c1, c2, c3);
				break;
			case PE_PARTICLECURVE_LINEAR:
				angularVelocity = particleLinearInterpolate(t, c0, c1, c2, c3);
				break;
			case PE_PARTICLECURVE_STEP:
				angularVelocity = particleStepInterpolate(t, c0, c1, c2, c3);
				break;
		}

		particle_Orientation2D[particleIndex].m_angularVelocity = angularVelocity;
	}
}

#ifndef __ORBIS__

technique11 UpdateAngularVelocity2DFromSpline
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateAngularVelocity2DFromSpline() ) );
	}
};

#endif //! __ORBIS__
