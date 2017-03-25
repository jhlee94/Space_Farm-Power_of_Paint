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
Texture2D <float4> InputFrameBuffer;						// The input frame buffer for gamma correction.

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
// The pixel shader for the frame buffer gamma correction operation.
// Arguments:
// IN - The input point to be shaded with the results of the gamma correction.
// Returns:
// The gamma corrected fragment to be inserted into the result frame buffer.
float4 PbrLinearToSrgbPS(PbrPosUvOut IN) : FRAG_OUTPUT_COLOR0
{
	float2 uv = IN.Uv;

	uint width, height;
	InputFrameBuffer.GetDimensions(width, height);
	int x = width * uv.x;
#ifdef __ORBIS__
	int y = height - (height * uv.y);
#else //! __ORBIS__
	int y = height * uv.y;
#endif //! __ORBIS__

	float4 inRgba = InputFrameBuffer.Load(int3(x, y, 0));
	float3 outRgb = pow(abs(inRgba.xyz), 1.0f/2.2f);				// Gamma correct linear to sRGB.

	return float4(outRgb, inRgba.w);
}

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

technique11 PBRLinearToSrgb
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GenFullscreenPosUvVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrLinearToSrgbPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
