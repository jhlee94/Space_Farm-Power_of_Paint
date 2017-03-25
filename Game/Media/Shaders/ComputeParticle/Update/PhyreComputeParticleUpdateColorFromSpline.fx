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
RWStructuredBuffer<PParticleColorStruct>			particle_Color;							// The structure buffer containing particle color.
cbuffer updateStateBuffer
{
	PUpdateColorFromSplineStateStruct				updateState;							// The update state for updating color.
};

[numthreads(64, 1, 1)]
void CS_UpdateColorFromSpline(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	ParticleStateBufferInfoStruct state = particleSystemState[0];

	// Find the particle that we are processing - proceed if it is within our emission allowance.
	uint particleIndex = DispatchThreadId.x;
	if (particleIndex < state.m_population)
	{
		particleIndex += state.m_baseIndex;			// Adjust to be in the correct budget block portion.

		float parametricLifetime = getParametricLifetime(particle_PositionVelocityLifetime[particleIndex]);
		float t = distortTime(parametricLifetime, updateState.m_time1, updateState.m_time2, updateState.m_repeatCount);

		float4 color = float4(0.0f, 0.0f, 0.0f, 0.0f);
		float4 c0 = updateState.m_color0;
		float4 c1 = updateState.m_color1;
		float4 c2 = updateState.m_color2;
		float4 c3 = updateState.m_color3;
		switch (updateState.m_curveMethod)
		{
			default:
			case PE_PARTICLECURVE_BEZIER:
				color = particleBezierInterpolate(t, c0, c1, c2, c3);
				break;
			case PE_PARTICLECURVE_LINEAR:
				color = particleLinearInterpolate(t, c0, c1, c2, c3);
				break;
			case PE_PARTICLECURVE_STEP:
				color = particleStepInterpolate(t, c0, c1, c2, c3);
				break;
		}

		particle_Color[particleIndex].m_color = color;
	}
}

#ifndef __ORBIS__

technique11 UpdateColorFromSpline
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_UpdateColorFromSpline() ) );
	}
};

#endif //! __ORBIS__
