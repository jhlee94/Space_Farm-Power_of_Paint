/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"

float4x4 WorldViewProjection	: WorldViewProjection;
Texture2D <float4> TextureSampler;

struct InstancingInput
{
	float4	InstanceTransform0	: InstanceTransform0;
	float4	InstanceTransform1	: InstanceTransform1;
	float4	InstanceTransform2	: InstanceTransform2;
	float4  InstanceColor		: InstanceColor;
};

struct DefaultVSInput
{
#ifdef __ORBIS__
	float4 Vertex				: POSITION;
#else //! __ORBIS__
	float2 Vertex				: POSITION;
#endif //! __ORBIS__
	InstancingInput instancingInput;
};

struct DefaultVSForwardRenderOutput
{
	float4 Position				: SV_POSITION;	
	float2 Uv					: TEXCOORD0;
	float4 Color				: TEXCOORD1;
};

sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

DefaultVSForwardRenderOutput DefaultForwardRenderVS(DefaultVSInput IN)
{			
	////////////////////////////////////////////////////
	// See PSpriteAttributes for data layout ///////////
	////////////////////////////////////////////////////
	// IN.instancingInput.InstanceTransform0 contains //
	// posX, posY, sinPhi, cosPhi                     //
	// IN.instancingInput.InstanceTransform1 contains //
	// uOrigin, vOrigin, textureSizeX, textureSize    //
	// IN.instancingInput.InstanceTransform2 contains //
	// spriteSizeX, spriteSizeY, depth, Phi           //
	// IN.instancingInput.InstanceColor contains	  //
	// red, green, blue, alpha						  //
	////////////////////////////////////////////////////
    
	// Transform sprite into world space 
	DefaultVSForwardRenderOutput OUT;
	float4 trans = IN.instancingInput.InstanceTransform0 * float4(1.0f, 1.0f, -1.0f, 1.0f);
	
	// Texture coordinates.
	OUT.Uv = (IN.Vertex.xy + float2(0.5f, 0.5f)) * IN.instancingInput.InstanceTransform1.zw + IN.instancingInput.InstanceTransform1.xy;
	
	IN.Vertex.xy *= IN.instancingInput.InstanceTransform2.xy;                              // Scale
	float y = dot(float3(1.0f, IN.Vertex.xy), IN.instancingInput.InstanceTransform0.yzw);  // Rotate + Translate
	float x = dot(float3(1.0f, IN.Vertex.yx), trans.xzw);                                  // Rotate + Translate
		
	// Transform from world space to view
	OUT.Position = mul(float4(x, y, IN.instancingInput.InstanceTransform2.z, 1.0f), WorldViewProjection);

	// Hardcoded z scale bias here. 
	OUT.Position.z = OUT.Position.z * 0.5 + 0.5;

	OUT.Color = IN.instancingInput.InstanceColor;
	
	return OUT;
}

float4 ForwardRenderFP(DefaultVSForwardRenderOutput In) : FRAG_OUTPUT_COLOR0
{
	return TextureSampler.Sample(LinearClampSampler, In.Uv) * In.Color;
}

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

DepthStencilState DepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less;
  StencilEnable = FALSE; 
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	DepthBias = 0;
};

technique11 ForwardRender < string PhyreRenderPass = "Transparent"; >
{
	pass mainRender
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultForwardRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
	
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}		
}

#endif //! __ORBIS__
