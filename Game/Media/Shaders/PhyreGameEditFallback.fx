/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Define local context switches.

#define MAX_NUM_LIGHTS 0
// Context switches
bool PhyreContextSwitches 
< 
	string ContextSwitchNames[] = {"LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT"}; 
	int MaxNumLights = MAX_NUM_LIGHTS; 
	string SupportedLightTypes[] = {"DirectionalLight","PointLight","SpotLight"};
	string SupportedShadowTypes[] = {"PCFShadowMap", "CascadedShadowMap", "CombinedCascadedShadowMap"};
	int NumSupportedShaderLODLevels = 1;
>;
#define DEFINED_CONTEXT_SWITCHES

#include "PhyreDefaultShaderSharedCodeD3D.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global shader parameters.

float4 constantColor = {1,1,1,1};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Structures
struct ShadowTexturedVSInput
{
#ifdef SKINNING_ENABLED
	#ifdef __ORBIS__
		float4 SkinnableVertex : POSITION;
	#else //! __ORBIS__
		float3 SkinnableVertex : POSITION;
	#endif //! __ORBIS__
#else //! SKINNING_ENABLED
	#ifdef __ORBIS__
		float4 Position	: POSITION;
	#else //! __ORBIS__
		float3 Position	: POSITION;
	#endif //! __ORBIS__
#endif //! SKINNING_ENABLED
#ifdef SKINNING_ENABLED
	uint4	SkinIndices		: BLENDINDICES;
	float4	SkinWeights		: BLENDWEIGHTS;
#endif //! SKINNING_ENABLED
};

struct ShadowTexturedVSOutput
{
	float4 Position	: SV_POSITION;	
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Vertex shaders

// Default shadow vertex shader.
ShadowTexturedVSOutput ShadowTexturedVS(ShadowTexturedVSInput IN)
{
	ShadowTexturedVSOutput Out = (ShadowTexturedVSOutput)0;	
#ifdef SKINNING_ENABLED
	float3 position = IN.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, IN.SkinWeights, IN.SkinIndices);
	Out.Position = mul(float4(position.xyz,1), ViewProjection);	
#else //! SKINNING_ENABLED
	float3 position = IN.Position.xyz;
	Out.Position = mul(float4(position.xyz,1), WorldViewProjection);
#endif //! SKINNING_ENABLED

	return Out;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment shaders.

// Forward render fragment shader
float4 ForwardRenderFP(DefaultVSForwardRenderOutput In) : FRAG_OUTPUT_COLOR0
{
	return constantColor;
}

// Light pre pass second pass shader. Samples the light prepass buffer.
float4 LightPrepassApplyFP(DefaultVSForwardRenderOutput In) : FRAG_OUTPUT_COLOR0
{
	return constantColor;
}


// Textured shadow shader.
float4 ShadowTexturedFP(ShadowTexturedVSOutput IN) : FRAG_OUTPUT_COLOR0
{
	return constantColor;
}

#ifndef __ORBIS__

BlendState NoBlend 
{
  BlendEnable[0] = FALSE;
};
BlendState LinearBlend 
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = SRC_ALPHA;
	DestBlend[0] = INV_SRC_ALPHA;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
};
DepthStencilState DepthState {
  DepthEnable = TRUE;
  DepthWriteMask = All;
  DepthFunc = Less_equal;
};
DepthStencilState NoDepthState {
  DepthEnable = FALSE;
  DepthWriteMask = All;
  DepthFunc = Less_equal;
};
DepthStencilState DepthStateWithNoStencil {
  DepthEnable = TRUE;
  DepthWriteMask = All;
  DepthFunc = Less_equal;
  StencilEnable = FALSE;
};

RasterizerState NoCullRasterState
{
	CullMode = None;
};

#ifdef DOUBLE_SIDED

RasterizerState DefaultRasterState 
{
	CullMode = None;
};

#else //! DOUBLE_SIDED

RasterizerState DefaultRasterState 
{
	CullMode = Front;
};

#endif //! DOUBLE_SIDED

RasterizerState CullRasterState 
{
	CullMode = Front;
};


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Techniques.

technique11 ForwardRender
<
	string PhyreRenderPass = "Opaque";
	string VpIgnoreContextSwitches[] = {"INDICES_16BIT"};
	string FpIgnoreContextSwitches[] = {"LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultForwardRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 ForwardRenderAlpha
<
	string PhyreRenderPass = "Transparent";
	string VpIgnoreContextSwitches[] = {"INDICES_16BIT"};
	string FpIgnoreContextSwitches[] = {"LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT"};
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultForwardRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
	
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 ShadowTransparent
<
	string PhyreRenderPass = "ShadowTransparent";
	string VpIgnoreContextSwitches[] = {"LOD_BLEND", "INDICES_16BIT"};
	string FpIgnoreContextSwitches[] = {"LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT"};
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, ShadowTexturedVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ShadowTexturedFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 Shadow
<
	string PhyreRenderPass = "Shadow";
	string VpIgnoreContextSwitches[] = {"LOD_BLEND", "INDICES_16BIT"};
	string FpIgnoreContextSwitches[] = {"LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT"};
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultShadowVS() ) );
		//We're not writing color, so bind no pixel shader here.
		//SetPixelShader( CompileShader( ps_4_0, DefaultShadowFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );		
	}
}

technique11 ZPrePass
<
	string PhyreRenderPass = "ZPrePass";
	string VpIgnoreContextSwitches[] = {"LOD_BLEND", "INDICES_16BIT"};
	string FpIgnoreContextSwitches[] = {"INSTANCING_ENABLED", "INDICES_16BIT"};
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultZPrePassVS() ) );
		SetPixelShader( CompileShader( ps_4_0, DefaultUnshadedFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

// Techniques
technique11 DeferredRender
<
	string PhyreRenderPass = "DeferredRender";
	string VpIgnoreContextSwitches[] = {"LOD_BLEND", "INDICES_16BIT"};
	string FpIgnoreContextSwitches[] = {"INSTANCING_ENABLED", "INDICES_16BIT"};
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultDeferredRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, DefaultDeferredRenderFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthStateWithNoStencil, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

#endif //! __ORBIS__
