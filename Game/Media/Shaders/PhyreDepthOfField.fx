/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

#ifndef __ORBIS__
// Context switches
bool PhyreContextSwitches 
< 
string ContextSwitchNames[] = {"ORTHO_CAMERA"}; 
>;
#endif //! __ORBIS__

float FocusPlaneDistance;
float FocusRange;
float FocusBlurRange; 

Texture2D <float> DepthBuffer;
Texture2D <float4> ColorInput;				// Full color buffer on 1st pass, blurred on 2nd pass
Texture2D <float4> NearProcessed;			// For the 2nd pass, the output of the previous near-field blur pass.
Texture2D <float4> DoFCompositeNearInput;
Texture2D <float4> DoFCompositeBlurInput;
Texture2D <float4> DoFCompositeColorInput;

// Fixed CoC settings
static const float maxCoCRadiusPixels = 4.0f;
static const float nearBlurRadiusPixels = 4.0f;
static const float invNearBlurRadiusPixels = 1.0f / nearBlurRadiusPixels;

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct FullScreenVS_Output 
{  
	float4 Pos : SV_POSITION;              
    float2 Tex : TEXCOORD0; 
};

FullScreenVS_Output FullScreenVS(uint id : SV_VertexID) 
{
    FullScreenVS_Output Output;
    Output.Tex = float2((id << 1) & 2, id & 2);
    Output.Pos = float4(Output.Tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    return Output; 
}

FullScreenVS_Output FullScreenVSWithFlip(uint id : SV_VertexID) 
{
    FullScreenVS_Output Output;
    Output.Tex = float2((id << 1) & 2, id & 2);
    Output.Pos = float4(Output.Tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
#ifdef __ORBIS__
	Output.Tex.y = 1 - Output.Tex.y;
#endif // __ORBIS__
    return Output; 
}

struct PS_OUTPUT
{
	float4 NearResult : FRAG_OUTPUT_COLOR0;
	float4 BlurResult : FRAG_OUTPUT_COLOR1;
};

//
// Functions used by both axis shaders
//

bool inNearField(float radiusPixels)
{
	return radiusPixels > 0.25;
}

int2 textureSize(Texture2D tex, int a)
{
	uint w, h;
	tex.GetDimensions(w,h);
	return int2(w,h);
}

float GetSignedDistanceToFocusPlane(float depth)
{
#ifdef ORTHO_CAMERA
	float viewSpaceZ = -(depth * cameraFarMinusNear + cameraNearFar.x);
#else //! ORTHO_CAMERA
	float viewSpaceZ = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
#endif //! ORTHO_CAMERA

	float off = (FocusPlaneDistance - viewSpaceZ);
	float signOff = off > 0.0f ? 1.0f : -1.0f;
	off = abs(off);
	off -= FocusRange;
	return signOff * saturate(off * (1.0f / FocusBlurRange));
}

#include "PhyreDepthOfFieldAxis.h"
#define HORIZONTAL
#include "PhyreDepthOfFieldAxis.h"

#ifndef __ORBIS__

BlendState NoBlend 
{
	BlendEnable[0] = FALSE;
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};

DepthStencilState NoDepthState {
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

technique11 RenderDoFHorizontal
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_1, FullScreenVS()));
		SetPixelShader(CompileShader(ps_5_0, RenderDoFPSHorizontal()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(NoDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 RenderDoFVertical
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_1, FullScreenVS()));
		SetPixelShader(CompileShader(ps_5_0, RenderDoFPSVertical()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(NoDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__

// Render FXAA
float4 RenderDoFCompositePS(FullScreenVS_Output Input) : FRAG_OUTPUT_COLOR 
{
	float2 uv = Input.Tex.xy;

	float4 pack	   = DoFCompositeColorInput.SampleLevel(PointClampSampler, uv, 0);
	float3 sharp   = pack.rgb;
	float4 blur    = DoFCompositeBlurInput.SampleLevel(PointClampSampler,uv, 0);
	float3 blurred = blur.xyz;
	float4 near    = DoFCompositeNearInput.SampleLevel(PointClampSampler,uv, 0);

	// Decrease sharp image's contribution rapidly in the near field
	// (which has positive normRadius)
	float normRadius = blur.a * 2 - 1;
	if (normRadius > 0.1) {
		normRadius = min(normRadius * 1.5, 1.0);
	}

	// Two lerps, the second of which has a premultiplied alpha
	float3 result = lerp(sharp, blurred, abs(normRadius)) * (1.0 - near.a) + near.rgb;
	return float4(result, 1);
}

#ifndef __ORBIS__

technique11 RenderDoFComposite
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_4_1, FullScreenVSWithFlip()));
		SetPixelShader(CompileShader(ps_5_0, RenderDoFCompositePS()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(NoDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

#endif //! __ORBIS__