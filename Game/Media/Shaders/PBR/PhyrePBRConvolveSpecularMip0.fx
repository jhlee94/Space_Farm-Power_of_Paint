/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Shaders for management of PBR. These include setup shaders executed once, and per frame shaders for rendering.

// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
#define DEFINED_CONTEXT_SWITCHES 1

#include "../PhyreShaderPlatform.h"
#include "../PhyreShaderDefsD3D.h"
#include "../PhyreDefaultShaderSharedCodeD3D.h"
#include "PhyrePbrShared.h"

// Parameters for the various shaders.

float3 cubeFaceXDir;										// The direction in cube space of the local X axis.
float3 cubeFaceYDir;										// The direction in cube space of the local Y axis.
float3 cubeFaceZDir;										// The direction in cube space of the local Z axis.
float preFilterGain;										// The gain to use whilst prefiltering.
TextureCube <float4> lightprobe;							// The lightprobe texture to pre-filter.

sampler PointFilterSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Wrap;
	AddressV = Wrap;
};

BlendState NoBlend 
{
	BlendEnable[0] = FALSE;
};

DepthStencilState NoDepthState
{
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less_equal;
};

RasterizerState NoCullRasterState
{
	CullMode = None;
};

///////////////////////////////////////////////////
// Prefilter the lightprobe for BRDF evaluation. //
///////////////////////////////////////////////////

// Description:
// The output vertex structure for lightprobe pre-filtering.
struct PrefilterLightprobeOut
{
	float4	Position			: SV_POSITION;			// The vertex position to rasterize.
	float3	Direction			: TEXCOORD0;			// The matching normal map sampling direction for the vertex position (the viewport quad maps to a cubemap face).
};

// Description:
// The vertex shader for the light probe pre-filter shader. Generates a triangle that covers the viewport.
// Arguments:
// id - The primitive id used to generate the triangle vertices.
// Returns:
// The generated triangle vertex.
PrefilterLightprobeOut ConvolveVS(float4 Position : POSITION)
{
	// Generate 3 verts for triangle covering the screen.
	PrefilterLightprobeOut OUT;

	float2 tex = Position.xy;

	float4 pos = float4(tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 1.0f, 1.0f);
	OUT.Position = pos;

#ifndef __ORBIS__
	pos.y = -pos.y;
#endif //! __ORBIS__

	// Build vector to address cubemap for the vertex.
	OUT.Direction = cubeFaceXDir * pos.x
					+ cubeFaceYDir * pos.y
					+ cubeFaceZDir * pos.z;

	return OUT;
}

// Description:
// Get the specular mip 0 color for the specified direction.
// Arguments:
// dir - The direction for which to get the mip 0 specular color.
// Returns:
// The specular mip 0 color for the specified direction.
static float4 GetSpecularMip0Col(float3 dir)
{
	float4 PrefilteredColor = lightprobe.SampleLevel(PointFilterSampler, dir, 0);

	PrefilteredColor.w = saturate(PrefilteredColor.w);			// Clamp W (validity) between 0 and 1.

	PrefilteredColor.xyz *= preFilterGain;

	return PrefilteredColor;
}

// Description:
// The pixel shader for the light probe specular pre-filter.
// Arguments:
// IN - The input point to be shaded with the results of the pre-filter operation.
// Returns:
// The shaded fragment to be inserted into the pre-filtered map.
float4 ConvolveSpecularMip0PS(PrefilterLightprobeOut IN) : FRAG_OUTPUT_COLOR0
{
	return GetSpecularMip0Col(normalize(IN.Direction));
}

technique11 PBRConvolveSpecularMip0
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, ConvolveVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ConvolveSpecularMip0PS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
