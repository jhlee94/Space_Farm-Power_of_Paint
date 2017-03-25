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

////////////////////////////////////
// Flip cubemap renders for D3D11 //
////////////////////////////////////

Texture2D <float4> InputFrameBuffer;						// The input frame buffer for gamma correction.

// Description:
// The vertex shader for the frame buffer gamma correction operation. Generates a triangle that covers the viewport.
// Arguments:
// id - The primitive id used to generate the triangle vertices.
// Returns:
// The generated triangle vertex.
float4 GenFullscreenPosUvVS(float4	Position : POSITION) : SV_POSITION
{
	float2 uv = Position.xy;
	return float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 1.0f, 1.0f);
}


float4 FlipCubeFacePS(float4 Position : SV_POSITION) : FRAG_OUTPUT_COLOR0
{
	uint width, height;
	InputFrameBuffer.GetDimensions(width, height);

	// Look up the 2d texture (inverted).
	return InputFrameBuffer.Load(int3(Position.x, height-Position.y, 0));
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

technique11 FlipCubeFace
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, GenFullscreenPosUvVS() ) );
		SetPixelShader( CompileShader( ps_4_0, FlipCubeFacePS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
