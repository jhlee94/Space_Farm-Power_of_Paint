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

// Description:
// The output vertex structure for DFG preintegration population.
struct PbrPosUvOut
{
	float4	Position			: SV_POSITION;			// The vertex position to rasterize.
	float2	Uv					: TEXCOORD0;			// The matching texture coordinate.
};

// Description:
// The vertex shader for the frame buffer gamma correction operation. Generates a triangle that covers the viewport.
// Arguments:
// id - The primitive id used to generate the triangle vertices.
// Returns:
// The generated triangle vertex.
PbrPosUvOut GenFullscreenPosUvVS(float4	Position : POSITION)
{
	// Generate 3 verts for triangle covering the screen.
	PbrPosUvOut OUT;

	float2 uv = Position.xy;

	OUT.Position = float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 1.0f, 1.0f);
	OUT.Uv = uv;

	return OUT;
}

// Description:
// Get a Hammersley point.
// Arguments:
// num - The index of the hammersley point to get.
// count - The size of the hammersley point set from which to get the point. Should be a power of two.
// Returns:
// The hammersley point.
static uint2 GetHammersleyPoint(uint num, uint bitCount)
{
	uint rev = reversebits(num << 32-bitCount);
	return uint2(num, rev);
}

// Description:
// Get a Hammersley point as a normalized float2.
// Arguments:
// num - The index of the hammersley point to get.
// count - The size of the hammersley point set from which to get the point. Should be a power of two.
// Returns:
// The hammersley point.
static float2 GetHammersleyPointFloat(uint num, uint bitCount)
{
	uint2 pt = GetHammersleyPoint(num, bitCount);
	float2 fPt = (float2)pt * float2(1.0f/(1<<bitCount), 1.0f/(1<<bitCount));

	return fPt;
}

///////////////////////////////////////////////////////////////
// Generate the preintegrated DFG terms for BRDF evaluation. //
///////////////////////////////////////////////////////////////

// Description:
// Integrate D, F and G components of the BRDF for the specified V, N and roughness. Assumes isotropic lobe.
// Arguments:
// V - The view vector in surface tangent space.
// roughness - The surface roughness.
// Returns:
// DFG value packed into xyz. Importance sampled GGX_D in w component.
static float4 integrateDFGOnly(in float3 V, in float roughness)
{
	// Tweak roughness to avoid very low values.
	roughness = max(roughness, 0.001f);

	// We do everything in surface tangent space, so referential is identity and normal is float3(0,0,1)
	PbrReferential referential = CreateIdentityReferential();
	float3 N = referential.m_normal;

	float linearRoughness = sqrt(roughness);

	float NdotV = saturate(dot(N, V));
	float4 acc = float4(0,0,0,0);

	// Compute pre-integration.
	uint sampleBitCount = 10;
	uint sampleCount = 1<<sampleBitCount;			// Integrate using a lot of samples for precision - this is a one off hit.
	for (uint i=0; i<sampleCount; i++)
	{
		float2 u = GetHammersleyPointFloat(i, sampleBitCount);
		float3 L = 0;
		float3 H = 0;
		float NdotH = 0;
		float LdotH = 0;
		float G = 0;

		// See [Karis13] for implementation
		importanceSampleGGX_G(u, V, N, referential, roughness, NdotH, LdotH, L, H, G);

		// Specular GGX DFG preintegration into acc.xy
		float NdotL = dot(N, L);
		if (NdotL > 0.0f)
		{
			float VdotH = dot(V, H);
			float GVis = NdotL * G * (4 * VdotH / NdotH);
			float Fc = pow(1-VdotH, 5.0f);
			acc.x += (1-Fc) * GVis;
			acc.y += Fc * GVis;
		}

		// Diffuse Disney preintegration into acc.z
		u = frac(u + 0.5);
		float pdf = 0;
		importanceSampleCosDir(u, referential, L, NdotL, pdf);
		if (NdotL > 0.0f)
		{
			float LdotH2 = saturate(dot(L, normalize(V + L)));
			acc.z += Fr_DisneyDiffuse(NdotV, NdotL, LdotH2, linearRoughness);
		}

		// Importance sample GGX_D at specified roughness.
		acc.w += importanceSampleGGX_D(u, N, referential, roughness);
	}

	acc /= float(sampleCount);	// Normalize for sample count.
	acc.w = 1/acc.w;			// Reciprocal the GGX_D value in preparation for normalization application.

	return acc;
}

// Description:
// The pixel shader for DFG preintegration population.
// Arguments:
// IN - The input vertex with which to shade.
// Returns:
// The shaded pixel for the DFG pre-integration.
float4 FillPreintegratedDFGPS(PbrPosUvOut IN) : FRAG_OUTPUT_COLOR0
{
	float2 uv = IN.Uv;

	// Calculate N and V so that N.V = uv.x.
	float cosTheta = uv.x;
	float sinTheta = sqrt(1-(cosTheta*cosTheta));		// sin^2+cos^2 = 1

	float3 V = float3(0, sinTheta, cosTheta);
#ifdef __ORBIS__
	float dfgRoughness = 1.0f-uv.y;
#else //! __ORBIS__
	float dfgRoughness = uv.y;
#endif //! __ORBIS__
	float4 result = integrateDFGOnly(V, dfgRoughness);

	return result;
}

technique11 PBRFillPreintegratedDFG
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GenFullscreenPosUvVS() ) );
		SetPixelShader( CompileShader( ps_4_0, FillPreintegratedDFGPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
