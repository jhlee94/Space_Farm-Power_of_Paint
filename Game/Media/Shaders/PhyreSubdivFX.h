/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_SUBDIV_FX_H
#define PHYRE_SUBDIV_FX_H

#define SCE_SUBDIV_POST_MULTIPLY

///
// Fill out required method implementations

#ifdef __WAVE__

// Required:
// The following functions must have implementations defined by the user
// The implementations may refer to any existing user matrices
float4x4 OsdModelViewMatrix()
{
	return WorldView;
}

float4x4 OsdProjectionMatrix()
{
	return Projection;
}

float4x4 OsdModelViewProjectionMatrix()
{
	return WorldViewProjection;
}

float4x4 OsdModelMatrix()
{
	return World;
}

float4x4 OsdViewProjectionMatrix()
{
	return ViewProjection;
}

float4x4 OsdViewMatrix()
{
	return View;
}

#endif

// Required:
// Must include this file for the mapping of resources
#include <sce_subdiv/shader/bezier_resources.h> // Angle brackets for SDK header

// Required:
// Must include this file for drawing a mesh
#include <sce_subdiv/shader/bezier_draw_common.h> // Angle brackets for SDK header

// Note that bezier_refine_common.h is not needed in this case because refinement is not used


#endif // PHYRE_SUBDIV_FX_H
