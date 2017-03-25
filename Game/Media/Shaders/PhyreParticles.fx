/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "PhyreShaderPlatform.h"
#include "PhyreSceneWideParametersD3D.h"

float4x4 World		: World;		
float4x4 WorldView	: WorldView;		
float4x4 WorldViewProjection		: WorldViewProjection;	

Texture2D <float4> MeshColorTexture;
float4 ParticleColorScale;

///////////////////////////////////////////////////////////////
// structures /////////////////////
///////////////////////////////////////////////////////////////

/*

struct ParticleVertexIn
{
	float3 Position		: POSITION;
	float4 Color		: COLOR0;
	float4 UvSize		: TEXCOORD0;
};

struct ParticleVertexOut
{
	float4 position		: SV_POSITION;
	float4 color		: COLOR0;
	float2 uv			: TEXCOORD0;
	float2 meshUv		: TEXCOORD1;
	float size			: PSIZE;
};

struct ParticleDeferredVertexOut
{
	float4 position		: SV_POSITION;
	float4 color		: COLOR0;
	float2 uv			: TEXCOORD0;
	float2 meshUv		: TEXCOORD1;
	float viewSpaceDepth : TEXCOORD2;
	float size			: PSIZE;
};

///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////


ParticleVertexOut RenderParticlesVP(ParticleVertexIn input)
{
	ParticleVertexOut output;
	float4 localPosition = float4(input.Position.xyz,1.0f);	
	
	output.position = mul(WorldViewProjection, localPosition);
	//output.color = input.Color * float4(1,1,1,0.4f);//float4(0.5f,0.5f,0.5f,0.8f);
	
	float y = saturate(localPosition.y * 0.4f);
	y *= y;
	y *= 1.5f;
			
	output.color = float4(y,y,y,0.8f) * input.Color * ParticleColorScale;
	//output.color.xyz *= 0.7f;
	//output.color.w *= saturate(input.UvSize.w * 3.0f);
	output.meshUv = input.UvSize.xy;
	output.size = (input.UvSize.z*0.5f+0.5f) * 5.0f * (1.0f-input.UvSize.w*0.7f) + 2.0f;
	output.uv = 0.0;
	
	return output;
}


ParticleVertexOut RenderParticleShadowVP(ParticleVertexIn input)
{
	ParticleVertexOut output;
	float4 localPosition = float4(input.Position.xyz,1.0f);	
	
	output.position = mul(WorldViewProjection, localPosition);
				
	output.color = 1;
	output.meshUv = input.UvSize.xy;
	output.size = 2;
	output.uv = 0.0;
	
	return output;
}


// Output structure for deferred lighting fragment shader.
struct PSDeferredOutput
{
	float4 Colour : FRAG_OUTPUT_COLOR0;
#ifndef __psp2__
	float4 NormalDepth : FRAG_OUTPUT_COLOR1;
#endif //! __psp2__
};

half4 RenderParticlesFP(ParticleFragIn input) : FRAG_OUTPUT_COLOR0
{
	half2 p = input.uv * 2.0f - 1.0f;
	half alpha = saturate(1.0f - dot(p,p)*0.8f);
	alpha *= alpha;
	half4 meshColor = h4tex2D(MeshColorTexture, input.meshUv);
	
	half glowAmt = saturate( ((meshColor.w * meshColor.w * 10.0f) - 0.5f) * 2.0f);
			
	return half4(meshColor.xyz,alpha) * input.color + half4(glowAmt,glowAmt,glowAmt,0);
}

half4 RenderParticlesGlowFP(ParticleFragIn input) : FRAG_OUTPUT_COLOR0
{
	half2 p = input.uv * 2.0f - 1.0f;
	half alpha = saturate(1.0f - dot(p,p)*0.8f);
	alpha *= alpha;
	half4 meshColor = h4tex2D(MeshColorTexture, input.meshUv);
	
	half glowAmt = saturate( ((meshColor.w * meshColor.w * 10.0f) - 0.5f) * 2.0f);
		
	return half4(glowAmt,glowAmt,glowAmt,alpha);
}

half4 RenderParticleShadowFP(ParticleFragIn input) : FRAG_OUTPUT_COLOR0
{
	return 1;
}


half4 PackNormalAndViewSpaceDepth(half3 normal, float viewSpaceZ)
{
	float normalizedViewZ = viewSpaceZ / scene.cameraNearFar.y;

	// Depth is packed into z, w.  W = Most sigificant bits, Z = Least significant bits.
	// We don't use full range on W so that initial value of 1.0 is clearly beyond far plane.
	half2 depthPacked = half2(frac(normalizedViewZ * 256.0f), floor(normalizedViewZ * 256.0f) / 255.0f);

	half4 rslt = half4(normal.xy, depthPacked);
	return rslt;
}


ParticleDeferredVertexOut RenderParticlesDeferredVP(ParticleVertexIn input)
{
	ParticleDeferredVertexOut output;
	float4 localPosition = float4(input.Position.xyz,1.0f);	
	
	output.position = mul(WorldViewProjection, localPosition);
	output.color = input.Color;
	output.meshUv = input.UvSize.xy;
	output.viewSpaceDepth = -mul(WorldView,localPosition).z;
	output.size = (input.UvSize.z*0.5f+0.5f) * input.UvSize.w * 3.0f;
	
	return output;
}


PSDeferredOutput RenderParticlesDeferredFP(ParticleDeferredFragIn input)
{
	half2 p = input.uv * 2.0f - 1.0f;
	half alpha = saturate(1.0f - dot(p,p));
	half4 meshColor = h4tex2D(MeshColorTexture, input.meshUv);
	
	clip((input.color.w * alpha) - 0.02f );
	half glowAmt = saturate( ((meshColor.w * meshColor.w * 10.0f) - 0.5f) * 200.0f);
	
	PSDeferredOutput Out;
	//Out.Colour = half4(meshColor.xyz,0) * input.color;
	Out.Colour = half4(meshColor.xyz,glowAmt);// * half4(1,1,1,input.color;
#ifndef __psp2__
	Out.NormalDepth = PackNormalAndViewSpaceDepth(half3(0.5f,0.5f,1), input.viewSpaceDepth);
#endif //! __psp2__

	return Out;
}




technique Transparent
{
	pass p0
	{
		VertexProgram = compile vp40 RenderParticlesVP();
		FragmentProgram = compile fp40 RenderParticlesFP();	
		colorMask = bool4(true,true,true,true);
		cullFaceEnable = false;
		depthTestEnable = true;
		depthFunc = lessEqual;
		depthMask = false;
		pointSize = 6;			
		blendEnable = true;
		blendFunc = {srcAlpha, oneMinusSrcAlpha};
		pointSpriteCoordReplace[0] = true;
		pointSpriteCoordReplace[1] = false;
	}
}

technique Shadow
{
	pass p0
	{
		VertexProgram = compile vp40 RenderParticleShadowVP();
		FragmentProgram = compile fp40 RenderParticleShadowFP();	
		colorMask = bool4(false,false,false,false);
		cullFaceEnable = false;
		depthTestEnable = true;
		depthFunc = lessEqual;
		depthMask = true;
		pointSize = 3;			
		blendEnable = true;
		blendFunc = {srcAlpha, oneMinusSrcAlpha};
		pointSpriteCoordReplace[0] = true;
		pointSpriteCoordReplace[1] = false;
	}
}


technique GenerateGlowBuffer
{
	pass p0
	{
		VertexProgram = compile vp40 RenderParticlesVP();
		FragmentProgram = compile fp40 RenderParticlesGlowFP();	
		colorMask = bool4(true,true,true,true);
		cullFaceEnable = false;
		depthTestEnable = false;
		depthFunc = lessEqual;
		depthMask = false;
		pointSize = 6;			
		blendEnable = true;
		blendFunc = {srcAlpha, oneMinusSrcAlpha};
		pointSpriteCoordReplace[0] = true;
		pointSpriteCoordReplace[1] = false;
	}
}


*/

