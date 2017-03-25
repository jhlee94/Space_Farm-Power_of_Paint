/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	//! Set the output format for picking to be 32 bit.
	#ifdef PHYRE_ENTRYPOINT_GenerateLinearDepth
		#pragma PSSL_target_output_format(default FMT_32_ABGR)
	#else //! PHYRE_ENTRYPOINT_GenerateLinearDepth
		#pragma PSSL_target_output_format(default FMT_FP16_ABGR)
	#endif //! PHYRE_ENTRYPOINT_GenerateLinearDepth

	#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif //! __ORBIS_

Texture2D <float> DepthBuffer;
RWTexture2D<float> RWLinearDepthBuffer;
Texture2D <float> LinearDepthBuffer;
Texture2D <float4> ColorBuffer;
Texture2D <float4> SSAOBuffer;
Texture2D <float4> NormalBuffer;
Texture2D <float4> BlurBuffer;

// Precaluclated values to quickly calculate xy view space values from st's.
float4 InvProjXY;

///////////////////////////////////////////////////////////////
// structures /////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

struct FullscreenVertexIn
{
#ifdef __ORBIS__
	float4 vertex	: POSITION;
#else //! __ORBIS__
	float3 vertex	: POSITION;
#endif //! __ORBIS__
	float2 uv			: TEXCOORD0;
};

struct FullscreenVertexOut
{
	float4 position		: SV_POSITION;
	float2 uv			: TEXCOORD0;
	float3 screenPos		: TEXCOORD3;
};

struct FullScreenVS_Output2 
{  
	float4 Pos : SV_POSITION;              
};

struct FullScreenVS_Output3 
{  
	float4 Pos : SV_POSITION; 
	float2 Tex : TEXCOORD0; 
};

///////////////////////////////
/// samplers///////////////////
///////////////////////////////
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

/////////////////////////////////////////
/// state ///////////////////////////////
/////////////////////////////////////////
BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
};

DepthStencilState DepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};

//////////////////////////////////
// Vertex Shader//////////////////
//////////////////////////////////
FullscreenVertexOut FullscreenVP(FullscreenVertexIn input)
{
	FullscreenVertexOut output;

#ifdef __ORBIS__
	output.position = float4(input.vertex.xy, 1, 1);
#else //! __ORBIS__
	output.position = float4(input.vertex.x,-input.vertex.y, 1, 1);
#endif //! __ORBIS__
	output.uv = input.uv;

	output.screenPos.z = 1.0;
	output.screenPos.xy = output.uv * 2.0 - 1.0;
	output.screenPos.xy *= InvProjXY.xy;

	return output;
}

FullScreenVS_Output2 FullscreenVP2(uint id : SV_VertexID) 
{
    FullScreenVS_Output2 Output;
    float2 tex = float2((id << 1) & 2, id & 2);
    Output.Pos = float4(tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    return Output; 
}

FullScreenVS_Output3 FullscreenVP3(uint id : SV_VertexID) 
{
    FullScreenVS_Output3 Output;
    Output.Tex = float2((id << 1) & 2, id & 2);
    Output.Pos = float4(Output.Tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);

#ifdef __ORBIS__
	Output.Tex.y = 1 - Output.Tex.y;
#endif // __ORBIS__

	Output.Tex = Output.Tex * 2.0 - 1.0;
	Output.Tex *= InvProjXY.xy;

    return Output; 
}

///////////////////////
// Pixel shader////////
///////////////////////

#include "ScalableAmbientObscurance/PhyreScalableAmbientObscurance.fx"

// Convert a depth value from post projection space to view space. 
float ConvertDepth(float depth)
{	
	float viewSpaceZ = (cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
	return viewSpaceZ;
}

// Mix ssao values with color values.
float4 ApplySSAOFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float4 colorValue = ColorBuffer.Sample(PointClampSampler,input.uv);
	float4 ssaoValue =  SSAOBuffer.Sample(LinearClampSampler, input.uv);
	return colorValue * ssaoValue.r;
}

// Display only ssao values.
float4 OnlySSAOFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{	
	float4 ssaoValue =  SSAOBuffer.Sample(LinearClampSampler, input.uv);
	return float4(ssaoValue.r,ssaoValue.r,ssaoValue.r,1);
}

float4 CopyBufferFP(FullscreenVertexOut input) : FRAG_OUTPUT_COLOR
{
#ifdef __ORBIS__
	return ColorBuffer.Load(int3(input.position.x, screenWidthHeight.y-input.position.y, 0));
#else //! __ORBIS__
	return ColorBuffer.Load(int3(input.position.xy,0));
#endif //! __ORBIS
}

/////////////////
// techniques////
/////////////////
technique11 GenerateLinearDepthCS
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, GenerateLinearDepth_CS() ) );
	}
}
  
technique11 DownSampleLinearDepth
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_5_0, FullscreenVP2() ) );
		SetPixelShader( CompileShader( ps_5_0, DownSampleDepth() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 ApplySSAO
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, ApplySSAOFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 OnlySSAO
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, OnlySSAOFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 CopyBuffer
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, FullscreenVP() ) );
		SetPixelShader( CompileShader( ps_4_0, CopyBufferFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 SAO
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_5_0, FullscreenVP3() ) );
		SetPixelShader( CompileShader( ps_5_0, generateSAO() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 SAOWithNormalBuffer
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_5_0, FullscreenVP3() ) );
		SetPixelShader( CompileShader( ps_5_0, generateSAOWithNormalBuffer() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 SAOBlur
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_5_0, FullscreenVP2() ) );
		SetPixelShader( CompileShader( ps_5_0, blur() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

