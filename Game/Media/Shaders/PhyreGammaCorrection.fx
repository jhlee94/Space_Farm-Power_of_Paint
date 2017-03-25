/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Shader for gamma correction of frame buffers.

#include "PhyreShaderPlatform.h"
#include "PhyreShaderDefsD3D.h"

Texture2D <float4> ColorBuffer;								// The input frame buffer for gamma correction.
float RecipGammaValue;										// The reciprocal gamma value to apply.

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
};

DepthStencilState NoDepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less_equal;
};

RasterizerState NoCullRasterState
{
	CullMode = None;
};

#ifdef __ORBIS__
	#define POSTYPE float4
#else //! __ORBIS__
	#define POSTYPE float3
#endif //! __ORBIS__

// Description:
// The input vertex structure for gamma correction vertex shader.
struct GammaCorrectVsIn
{
	POSTYPE	Position			: POSITION;				// The input position.
	float2	Uv					: TEXCOORD0;			// The matching texture coordinate.
};

// Description:
// The output vertex structure for gamma correction vertex shader.
struct GammaCorrectVsOut
{
	float4	Position			: SV_POSITION;			// The vertex position to rasterize.
	float2	Uv					: TEXCOORD0;			// The matching texture coordinate.
};

// Description:
// The vertex shader for the frame buffer gamma correction operation. This is a simple pass through shader.
// Arguments:
// IN : The input vertex to pass through.
// Returns:
// The vertex passed through.
GammaCorrectVsOut RenderGammaCorrectionVS(GammaCorrectVsIn IN)
{
	GammaCorrectVsOut OUT;
	OUT.Position = float4(IN.Position.xy, 1, 1);
	OUT.Uv = IN.Uv;

	return OUT;
}

// Description:
// The pixel shader for the frame buffer gamma correction operation.
// Arguments:
// IN - The input point to be shaded with the results of the gamma correction.
// Returns:
// The gamma corrected fragment to be inserted into the result frame buffer.
float4 RenderGammaCorrectionPS(GammaCorrectVsOut IN) : FRAG_OUTPUT_COLOR0
{
	float2 uv = IN.Uv;

	uint width, height;
	ColorBuffer.GetDimensions(width, height);
	int x = width * uv.x;
#ifndef __ORBIS__
	int y = height - (height * uv.y);
#else //! __ORBIS__
	int y = height * uv.y;
#endif //! __ORBIS__

	float4 inRgba = ColorBuffer.Load(int3(x, y, 0));
	float3 outRgb = pow(abs(inRgba.xyz), RecipGammaValue);			// Apply gamma correction.

	return float4(outRgb, inRgba.w);
}

technique11 RenderGammaCorrection
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, RenderGammaCorrectionVS() ) );
		SetPixelShader( CompileShader( ps_4_0, RenderGammaCorrectionPS() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}
