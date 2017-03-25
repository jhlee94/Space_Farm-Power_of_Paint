/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// Default implementation of a shader required by a sprite particle emitter.

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

#ifndef __ORBIS__

bool PhyreContextSwitches 
< 
string ContextSwitchNames[] = {"LOW_RES_PARTICLES"}; 
>;

bool PhyreMaterialSwitches 
< 
string MaterialSwitchNames[] = {"RENDER_AS_LOW_RES"}; 
string MaterialSwitchUiNames[] = {"Render at Lower Resolution"}; 
string MaterialSwitchDefaultValues[] = {""};
>;

#endif //! __ORBIS__

// If the top-level RENDER_AS_LOW_RES material switch hasn't been set, LOW_RES_PARTICLES cannot be supported
#ifndef RENDER_AS_LOW_RES
	#undef LOW_RES_PARTICLES
#endif // RENDER_AS_LOW_RES

float4x4 WorldViewProjection		: WorldViewProjection;
float4 ParticleColor = float4(1,1,1,1);	

float SoftDepthScale <float UIMin = 0.0001; float UIMax = 1.0; string UIName = "Soft Depth Scale"; string UILabel = "The scale for difference in depth between the particle and scene when softening particles."; > = 0.9f;

///////////////////////////////////////////////////////////////
// structures /////////////////////
///////////////////////////////////////////////////////////////

struct ParticleVertexIn
{
#ifdef __ORBIS__
	float4 Position		: POSITION;
#else //! __ORBIS__
	float3 Position		: POSITION;
#endif //! __ORBIS__
	float2 Texcoord 	: TEXCOORD0;
};

struct ParticleVertexOut
{
	float4 position		: SV_POSITION;
	float2 Texcoord 	: TEXCOORD0;
	
#ifdef LOW_RES_PARTICLES
	float2 DepthTexCoord: TEXCOORD1;
#endif // LOW_RES_PARTICLES
};
struct ParticleFragIn
{
	float2 Texcoord 	: TEXCOORD0;
#ifdef LOW_RES_PARTICLES
	float2 DepthTexCoord: TEXCOORD1;
#endif // LOW_RES_PARTICLES
};

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////

// Convert a depth value from post projection space to view space. 
float ConvertDepth(float depth)
{	
#ifdef ORTHO_CAMERA
	float viewSpaceZ = -(depth * cameraFarMinusNear + cameraNearFar.x);
#else //! ORTHO_CAMERA
	float viewSpaceZ = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
#endif //! ORTHO_CAMERA
	return viewSpaceZ;
}

ParticleVertexOut RenderParticlesVP(ParticleVertexIn input)
{
	ParticleVertexOut output;
	float4 localPosition = float4(input.Position.xyz,1.0f);	
	
	output.position = mul(localPosition, WorldViewProjection);
	output.Texcoord = input.Texcoord;

#ifdef LOW_RES_PARTICLES
	output.DepthTexCoord.xy = (output.position.xy / output.position.w) * 0.5f + 0.5f;
#ifndef __ORBIS__
	output.DepthTexCoord.y = 1-output.DepthTexCoord.y;
#endif //! __ORBIS__
#endif // LOW_RES_PARTICLES

	return output;
}


float4 RenderParticlesFP(ParticleVertexOut input) : FRAG_OUTPUT_COLOR0
{
	float2 p = input.Texcoord * 2.0f - 1.0f;
	float a = length(p * 0.7f);
	a = saturate(1.0 - a);
	a = a * a;
	a = a * a;

#ifdef LOW_RES_PARTICLES
	float sceneDepth = abs(ConvertDepth(LowResDepthTexture.SampleLevel(PointClampSampler, input.DepthTexCoord.xy, 0).x));
	float particleDepth = input.position.w;
	float diff = saturate(SoftDepthScale * (sceneDepth - particleDepth));
	return ParticleColor * half4(1.0,1.0,1.0,diff *a);
#else // LOW_RES_PARTICLES
	return ParticleColor * half4(1.0,1.0,1.0,a);
#endif // LOW_RES_PARTICLES
}

#ifndef __ORBIS__

BlendState LinearBlend 
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = SRC_ALPHA;
	DestBlend[0] = INV_SRC_ALPHA;
	BlendOp[0] = ADD;
#ifdef RENDER_AS_LOW_RES
	SrcBlendAlpha[0] = ZERO;
	DestBlendAlpha[0] = INV_SRC_ALPHA;
#else // RENDER_AS_LOW_RES
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
#endif // RENDER_AS_LOW_RES
	BlendOpAlpha[0] = ADD;
};

DepthStencilState DepthState {
	DepthEnable = TRUE;
#ifdef RENDER_AS_LOW_RES
	DepthWriteMask = All;
#else // RENDER_AS_LOW_RES
	DepthWriteMask = Zero;
#endif // RENDER_AS_LOW_RES
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

RasterizerState DisableCulling
{
    CullMode = NONE;
};

#ifdef RENDER_AS_LOW_RES
technique11 LowResParticles
#else // RENDER_AS_LOW_RES
technique11 Transparent
#endif // RENDER_AS_LOW_RES
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_5_0, RenderParticlesVP() ) );
		SetPixelShader( CompileShader( ps_5_0, RenderParticlesFP() ) );

		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DisableCulling );	
	}
}

#endif //! __ORBIS__
