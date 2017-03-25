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

#include "PhyreSphericalHarmonics.h"

// Parameters for the various shaders.
float3 cubeFaceXDir;										// The direction in cube space of the local X axis.
float3 cubeFaceYDir;										// The direction in cube space of the local Y axis.
float3 cubeFaceZDir;										// The direction in cube space of the local Z axis.
float preFilterGain;										// The gain to use whilst prefiltering.
#define SH_ORDER_STRUCT4 SHOrder2Float4
#define SH_ORDER_STRUCT SHOrder2Float
StructuredBuffer <SH_ORDER_STRUCT4> SphericalHarmonicCoefficients;
int SphericalHarmonicIndex;									// The index of the spherical harmonic to process.

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

////////////////////////////////////////////////////////////
// Generate spherical harmonic coefficients for a cubemap //
////////////////////////////////////////////////////////////

static float4 GetDiffuseSH(float3 dir)
{
	// Evaluate Spherical Harmonics at surface normal direction.
	SH_ORDER_STRUCT shBuff;
	EvaluateSH(shBuff, dir);

	// Multiply in SH-projection of cosinus lobe (NdotL term in frequency domain).
	ApplyCosinusLobe(shBuff);

	// Reconstruct the answer.
	SH_ORDER_STRUCT4 coeffs = SphericalHarmonicCoefficients[SphericalHarmonicIndex];
	float4 PrefilteredColor = ShReconstruct(coeffs, shBuff);

	PrefilteredColor.xyz *= preFilterGain;

	return PrefilteredColor;
}

// Description:
// The pixel shader for the light probe diffuse pre-filter.
// Arguments:
// IN - The input point to be shaded with the results of the pre-filter operation.
// Returns:
// The shaded fragment to be inserted into the pre-filtered map.
float4 ConvolveDiffuseSHPS(PrefilterLightprobeOut IN) : FRAG_OUTPUT_COLOR0
{
	return GetDiffuseSH(normalize(IN.Direction));
}

technique11 PBRConvolveDiffuseSH
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, ConvolveVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ConvolveDiffuseSHPS() ) );

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
