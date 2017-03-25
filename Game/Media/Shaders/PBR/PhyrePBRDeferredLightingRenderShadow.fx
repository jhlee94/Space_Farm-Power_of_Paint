/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"
#include "../PhyreShaderDefsD3D.h"

#ifndef __ORBIS__
	// Material switches - There are no material switches.
#endif //! __ORBIS__

#ifndef __ORBIS__
	// Context switches - there are none.

// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
	#define DEFINED_CONTEXT_SWITCHES 1
#endif //! __ORBIS__

#if defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)
#define PACK_LIGHT_INDICES  // Extra work to pack down to uint8s to reduce LDS usage
#endif // defined(DEFERRED_VR) && defined(DEFERRED_MULTISAMPLE)

#ifdef __ORBIS__
#pragma argument(barycentricmode=center) // Force center mode for sample locations in case rendering to an AA target - PhyreEngine defaults to sample barycentricmode
#endif // __ORBIS__

#include "../PhyreSceneWideParametersD3D.h"
#include "../PhyreDeferredLightingSharedFx.h"

// Instantiate dummy default lit lighting functions for new PBR light types.
#define InstantiateDummyLightingFns(LIGHT_TYPE) \
	float3 EvaluateLight(LIGHT_TYPE light,float3 worldPosition, float3 normal, float3 eyeDirection, float shadowAmount, float shininess, float specularPower) { return float3(shadowAmount,shadowAmount,shadowAmount); } \
	float3 EvaluateLight(LIGHT_TYPE light,float3 worldPosition, float3 normal, float shadowAmount) { return float3(shadowAmount,shadowAmount,shadowAmount); } \
	float EvaluateShadow(LIGHT_TYPE light, float dummy, float dummy2, float3 worldPosition, float viewDepth) { return 1; }

#ifdef EXTENDED_LIGHT_TYPES
InstantiateDummyLightingFns(AreaDiscLight)
InstantiateDummyLightingFns(AreaSphereLight)
InstantiateDummyLightingFns(AreaRectangleLight)
InstantiateDummyLightingFns(AreaTubeLight)
InstantiateDummyLightingFns(GlobalLightProbe)
InstantiateDummyLightingFns(LocalLightProbe)
InstantiateDummyLightingFns(RadianceVolume)
#endif // EXTENDED_LIGHT_TYPES

#include "../PhyreShaderCommonD3D.h"

#ifdef RECEIVE_SHADOWS
	#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) EvaluateShadow(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth)
#else //! RECEIVE_SHADOWS
	#define EvaluateShadowValue(LightId, LightShadowId, ShadowMapId, worldPos, viewDepth) 1.0f
#endif //! RECEIVE_SHADOWS

float4x4 World		: World;		
float4x4 WorldView	: WorldView;		
float4x4 WorldViewProjection		: WorldViewProjection;	
float4x4 WorldViewProjectionPrev		: WorldViewProjectionPrev;

sampler LightprobeSamplerSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler NormalMapSamplerSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Wrap;
	AddressV = Wrap;
};

// Shared Physically Based Rendering functionality.
#include "PhyrePBRShared.h"
#include "PhyrePBRSharedFx.h"

///////////////////////
// Vertex structures //
///////////////////////

// Description:
// The input vertex for an untextured vertex.
struct PbrLightingVSInput
{
#ifdef __ORBIS__
	float4 Vertex		: POSITION;											// The full screen vertex.
#else //! __ORBIS__
	float3 Vertex		: POSITION;											// The full screen vertex.
#endif //! __ORBIS__
};

// Description:
// The output vertex for an untextured vertex.
struct PbrLightingVSOutput
{
	float4 Position		: SV_POSITION;									// The transformed light hull vertex.
};

////////////////
// Parameters //
////////////////

float2 ViewportWidthHeightInv;

Texture2D<float> DepthBuffer;											// The depth buffer.

Texture2D <float> ShadowTexture;										// The shadow depth buffer from the POV of the light.

//! Shadow parameters
float4x4 DeferredShadowMatrix;											// The shadow matrix for when only 1 matrix exists.
float4x4 DeferredShadowMatrixSplit0;									// The shadow matrix for the 0th split.
float4x4 DeferredShadowMatrixSplit1;									// The shadow matrix for the 1st split.
float4x4 DeferredShadowMatrixSplit2;									// The shadow matrix for the 2nd split.
float4x4 DeferredShadowMatrixSplit3;									// The shadow matrix for the 3rd split.
float4 DeferredSplitDistances;											// The shadow split distances for the splits.

//! Light parameters
float4x4 DeferredWorldTransform;										// The light's world transform.
float4 DeferredShadowMask;												// The light's shadow mask.

////////////////////
// Vertex shaders //
////////////////////

//! Untextured

// Description:
// Transform the general light shape into the specific light position for the light instance, as described by the light matrix supplied.
// Arguments:
// IN - The general light shape vertex.
// Returns:
// The specific light instance's position.
PbrLightingVSOutput PbrRenderLightVS(PbrLightingVSInput IN)
{
	PbrLightingVSOutput OUT;

	float4 worldPosition = mul(float4(IN.Vertex.xyz, 1), DeferredWorldTransform);
	OUT.Position = mul(float4(worldPosition.xyz,1), ViewProjection);

	return OUT;
}

// Description:
// The full screen transform that passes the full screen vertex through.
// Arguments:
// IN - The input full screen vertex.
// Returns:
// The output full screen vertex.
PbrLightingVSOutput PbrFullscreenVS(PbrLightingVSInput IN)
{
	PbrLightingVSOutput OUT;

#ifdef __ORBIS__
	OUT.Position = float4(IN.Vertex.xy, 1, 1);
#else //! __ORBIS__
	OUT.Position = float4(IN.Vertex.x, -IN.Vertex.y, 1, 1);
#endif //! __ORBIS__

	return OUT;
}

///////////////////
// Pixel shaders //
///////////////////

// Description:
// Sample the light depth buffer for a directional light to render the shadow buffer.
// Arguments:
// IN - The input fragment to be shadowed.
// Returns:
// The shadow buffer value in the correct channel for the light.
float4 PbrShadowDirectionalLightPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_COLOR
{	
	float2 uv = IN.Position.xy * ViewportWidthHeightInv;
	float2 screenPos = GetScreenPosition(uv);
	
	float zvalue = DepthBuffer.Load(int3(IN.Position.xy, 0)).x;  
	float unpackedDepth = abs(ConvertDepth(zvalue));

#ifdef ORTHO_CAMERA
	float4 viewPos = float4(screenPos, unpackedDepth, 1);
#else //! ORTHO_CAMERA
	float4 viewPos = float4(screenPos * unpackedDepth, unpackedDepth, 1);
#endif //! ORTHO_CAMERA
	
	float4 shadowPosition0 = mul(viewPos, DeferredShadowMatrixSplit0);
	float4 shadowPosition1 = mul(viewPos, DeferredShadowMatrixSplit1);
	float4 shadowPosition2 = mul(viewPos, DeferredShadowMatrixSplit2);
	float4 shadowPosition3 = mul(viewPos, DeferredShadowMatrixSplit3);

	float4 shadowPosition = unpackedDepth < DeferredSplitDistances.y ? 
		(unpackedDepth < DeferredSplitDistances.x ? shadowPosition0 : shadowPosition1)
		:
		(unpackedDepth < DeferredSplitDistances.z ? shadowPosition2 : shadowPosition3);

#define kShadowSize2 (2.0f/4096.0f)
	
	float4 offsets[5] = 
	{
		float4( 0.0f, 0.0f,0,0),
		float4(-kShadowSize2,-kShadowSize2,0,0),
		float4( kShadowSize2,-kShadowSize2,0,0),
		float4(-kShadowSize2, kShadowSize2,0,0),
		float4( kShadowSize2, kShadowSize2,0,0),
	};
	
	float rslt = 1.0f;
	if(unpackedDepth < DeferredSplitDistances.w)
	{		
		float shadowValue0 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[0].xy, shadowPosition.z).x;
		float shadowValue1 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[1].xy, shadowPosition.z).x;
		float shadowValue2 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[2].xy, shadowPosition.z).x;
		float shadowValue3 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[3].xy, shadowPosition.z).x;
		float shadowValue4 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[4].xy, shadowPosition.z).x;

		rslt = (shadowValue1+shadowValue2+shadowValue3+shadowValue4)*0.125f + shadowValue0 * 0.5f;
	}
		
	return DeferredShadowMask * rslt;
}

// Description:
// Sample the light depth buffer for a spot light to render the shadow buffer.
// Arguments:
// IN - The input fragment to be shadowed.
// Returns:
// The shadow buffer value in the correct channel for the light.
float4 PbrShadowSpotLightPS(PbrLightingVSOutput IN) : FRAG_OUTPUT_COLOR
{	
	float2 uv = IN.Position.xy * ViewportWidthHeightInv;
	float2 screenPos = GetScreenPosition(uv);
	
	float zvalue = DepthBuffer.Load(int3(IN.Position.xy, 0)).x;  
	float unpackedDepth = abs(ConvertDepth(zvalue));

#ifdef ORTHO_CAMERA
	float4 viewPos = float4(screenPos, unpackedDepth, 1);
#else //! ORTHO_CAMERA
	float4 viewPos = float4(screenPos * unpackedDepth, unpackedDepth, 1);
#endif //! ORTHO_CAMERA
	float4 shadowPosition = mul(viewPos, DeferredShadowMatrix);

	shadowPosition.xyz /= shadowPosition.w;
	
#define kShadowSize3 (3.0f/4096.0f)
	
	float4 offsets[2] = 
	{
		float4(-kShadowSize3,-kShadowSize3,0,0),
		float4( kShadowSize3, kShadowSize3,0,0),
	};

//	shadowPosition.z = shadowPosition.z * 0.5f + 0.5f;
//	shadowPosition.z -= 0.00001f;

	float shadowValue0 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[0].xy, shadowPosition.z).x;
	float shadowValue1 = ShadowTexture.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy + offsets[1].xy, shadowPosition.z).x;
	float rslt = (shadowValue0+shadowValue1)*0.5f;
	
	return DeferredShadowMask * rslt;
}

////////////////
// Techniques //
////////////////

RasterizerState LightRasterState 
{
	CullMode = Back;
};

technique11 ShadowDirectionalLight
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, PbrFullscreenVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrShadowDirectionalLightPS() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( NoCullRasterState );		
	}
}

technique11 ShadowSpotLight
{
	pass pass1
	{
		SetVertexShader( CompileShader( vs_4_0, PbrRenderLightVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PbrShadowSpotLightPS() ) );
	
		SetBlendState( AdditiveBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( LightRasterState );		
	}
}
