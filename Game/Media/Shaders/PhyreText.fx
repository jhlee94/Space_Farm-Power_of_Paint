/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"

Texture2D <float4> BitmapFontTexture;


float4 textColor		= { 1.0f, 1.0f, 1.0f, 1.0f };
float4x4 World;
float CameraAspectRatio;

// Alpha threshold
float alphaThreshold	= 0.5f;

// Outlines
float4 outlineColor		= { 0.0f, 0.0f, 0.0f, 1.0f };
float4 outlineValues	= { 0.47f, 0.50f, 0.62f, 0.63f };

// Drop Shadows
float4 shadowColor		= { 0.0f, 0.0f, 0.0f, 1.0f };
float2 shadowUVOffset	= { -0.0025f, -0.0025f };

// Glows
float4 glowColor		= { 1.0f, 0.0f, 0.0f, 1.0f };
float2 glowValues		= { 0.17f, 0.5f };

// Soft Edges
float2 softEdges		= { 0.5f, 0.51f };

struct VPInput
{
#ifdef __ORBIS__
	float4 position		: POSITION;
#else //! __ORBIS
	float2 position		: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct VPOutput
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
};



sampler LinearClampSampler
{
	Filter = Min_Mag_Mip_Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};



VPOutput TextVP(VPInput IN)
{
	VPOutput OUT;
	
	OUT.position = mul(float4(IN.position.xy, 0.0f, 1.0f), World);
	OUT.position.x *= CameraAspectRatio;
	OUT.uv = IN.uv;
	
	return OUT;
}

float4 TextFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	return float4(textColor.xyz, textColor.w * BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
}

float4 TextAlphaTestFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 color = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
	if(color.a <= alphaThreshold)
		discard;	// Use discard to simulate alpha test.
	return float4(color.xyz, color.w * textColor.w);
}

float SoftEdges(float alphaMask, float distMin, float distMax)
{
	return smoothstep(distMin, distMax, alphaMask);
}

float HardEdges(float alphaMask, float threshold)
{
	return alphaMask >= threshold;
}

float4 ShadowGlow(float2 uv, float4 color, float4 shadowGlowColor, float maskUsed)
{
	float4 glowTexel = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, uv).x);
	float4 glowc = shadowGlowColor * smoothstep(glowValues.x, glowValues.y, glowTexel.a);
	return lerp(glowc, color, maskUsed);
}

float4 Outline(float4 color, float alphaMask)
{
	float4 result = color;

	if((alphaMask >= outlineValues.x) && (alphaMask <= outlineValues.w))
	{
		float oFactor;
		if(alphaMask <= outlineValues.y)
			oFactor = smoothstep(outlineValues.x, outlineValues.y, alphaMask);
		else
			oFactor = smoothstep(outlineValues.w, outlineValues.z, alphaMask);
		result = lerp(color, outlineColor, oFactor);
	}

	return result;
}

float4 TextHardEdgesFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 color = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
	color.a = textColor.w * HardEdges(color.a, alphaThreshold);
	return color;
}

float4 TextSoftEdgesFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 color = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
	color.a = textColor.w * SoftEdges(color.a, softEdges.x, softEdges.y);
	return color;
}

float4 TextSoftEdgesAndOutlineFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 color = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
	float distAlphaMask = color.a;
	color = Outline(color, distAlphaMask);
	color.a = textColor.w * SoftEdges(distAlphaMask, softEdges.x, softEdges.y);
	return color;
}

float4 TextSoftEdgesAndShadowFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 color = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
	float distAlphaMask = color.a;
	float maskUsed = SoftEdges(distAlphaMask, softEdges.x, softEdges.y);
	color.a = maskUsed;
	color = ShadowGlow(IN.uv + shadowUVOffset, color, shadowColor, maskUsed);
	return float4(color.xyz, color.w * textColor.w);
}

float4 TextSoftEdgesAndGlowFP(VPOutput IN) : FRAG_OUTPUT_COLOR
{
	float4 color = float4(textColor.xyz, BitmapFontTexture.Sample(LinearClampSampler, IN.uv).x);
	float distAlphaMask = color.a;
	color = Outline(color, distAlphaMask);
	float maskUsed = SoftEdges(distAlphaMask, softEdges.x, softEdges.y);
	color.a = maskUsed;
	color = ShadowGlow(IN.uv, color, glowColor, maskUsed);
	return float4(color.xyz, color.w * textColor.w);
}

#ifndef __ORBIS__
BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
  RenderTargetWriteMask[0] = 15;
};
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
DepthStencilState DepthState {
  DepthEnable = TRUE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};
DepthStencilState NoDepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};
RasterizerState DefaultRasterState 
{
	CullMode = None;
};


technique11 RenderText_AlphaBlend
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_AlphaTest
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextAlphaTestFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_SoftEdges
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextSoftEdgesFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_HardEdges
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextHardEdgesFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_SoftEdgesAndOutline
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextSoftEdgesAndOutlineFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_SoftEdgesAndShadow
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextSoftEdgesAndShadowFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 RenderText_SoftEdgesAndGlow
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, TextVP() ) );
		SetPixelShader( CompileShader( ps_4_0, TextSoftEdgesAndGlowFP() ) );
		
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

#endif //! __ORBIS__
