/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

#ifndef __ORBIS__

BlendState LinearBlend 
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = Src_Alpha;
	DestBlend[0] = Inv_Src_Alpha;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
	BlendEnable[1] = FALSE;
	RenderTargetWriteMask[0] = 15;
};
DepthStencilState NoDepthState 
{
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};
RasterizerState DefaultRasterState 
{
	CullMode = None;
	ScissorEnable = true;
};
#endif //! __ORBIS__

Texture2D <float4> BitmapFontTexture;

struct VPInput
{
#ifdef __ORBIS__
	float4 position		: POSITION;
#else //! __ORBIS__
	float2 position		: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
	float4 color		: COLOR0;
};

struct VPOutput
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
	float4 color		: COLOR0;
};

VPOutput IMGUIVP(VPInput IN)
{
	VPOutput OUT;
	
	OUT.position = mul(float4(IN.position.xy, 0.0f, 1.0f), Projection);
	OUT.color = IN.color;
	OUT.uv = IN.uv;
	
	return OUT;
}

float4 IMGUIFP(VPOutput IN) : FRAG_OUTPUT_COLOR0
{
	return float4(IN.color * BitmapFontTexture.Sample(PointClampSampler, IN.uv).r);
}

#ifndef __ORBIS__

technique11 RenderIMGUI
{
	pass main
	{
		SetVertexShader( CompileShader( vs_4_0, IMGUIVP() ) );
		SetPixelShader( CompileShader( ps_4_0, IMGUIFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__
