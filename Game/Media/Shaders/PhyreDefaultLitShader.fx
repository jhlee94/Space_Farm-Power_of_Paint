/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/


#ifndef __ORBIS__

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Switches. 

// Material switch definitions. These are the material switches this shader exposes.
bool PhyreMaterialSwitches 
< 
string MaterialSwitchNames[] = {
								"LAYERED_TEXTURE_MODE_OVER_NONE_ENABLED",	"MULTIPLE_UVS_ENABLED",		"VERTEX_COLOR_ENABLED",			"LIGHTING_ENABLED",
								"TEXTURE_ENABLED",							"ALPHA_ENABLED",			"NORMAL_MAPPING_ENABLED",		"WRAP_DIFFUSE_LIGHTING",
								"SPECULAR_ENABLED",							"CASTS_SHADOWS",			"RECEIVE_SHADOWS",				"DOUBLE_SIDED",
								"MOTION_BLUR_ENABLED",						"GENERATE_LIGHTS",			"CEL_ENABLED",					"RENDER_AS_LOW_RES",
								"LIGHTMAP_OCCLUSION",						"SUBDIV",					"SUBDIV_SCALAR_DISPLACEMENT",	"SUBDIV_VECTOR_DISPLACEMENT"}; 
string MaterialSwitchUiNames[] = {
								"Layered Textures",							"Multiple UVs",				"Vertex Color",					"Lighting",
								"Texture",									"Transparency",				"Normal Mapping",				"Use Wrap Diffuse Lighting",
								"Specular",									"Casts Shadows",			"Receive Shadows",				"Render Double Sided",
								"Motion Blur",								"Generate Lights",			"Cel Shading",					"Render at Lower Res",
								"Lightmap Occlusion",						"Subdivision",				"Scalar Displacement",			"Vector Displacement" };
string MaterialSwitchDefaultValues[] = {
								"",											"",							"",								"",
								"",											"",							"",								"",
								"",											"",							"1",							"",
								"",											"",							"",								"",
								"",											"",							"",								""};
>;
#endif //! __ORBIS__

#if defined(MAYA) || defined(MAX)
#undef SUBDIV
#endif // defined(MAYA) || defined(MAX)

#ifdef SUBDIV
#undef SKINNING_ENABLED		// Not needed - done in runtime ahead of subdivision
#undef INSTANCING_ENABLED	// Not supported
#endif // SUBDIV

#include "PhyreShaderPlatform.h"
// Defining DEFINED_CONTEXT_SWITCHES prevents PhyreDefaultShaderSharedCodeD3D.h from defining a default set of context switches.
#define DEFINED_CONTEXT_SWITCHES 1
#include "PhyreDefaultShaderSharedCodeD3D.h"

// Context switches
bool PhyreContextSwitches
<
string ContextSwitchNames[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
int MaxNumLights = MAX_NUM_LIGHTS;
string SupportedLightTypes[] = { "DirectionalLight", "PointLight", "SpotLight" };
string SupportedShadowTypes[] = { "PCFShadowMap", "CascadedShadowMap", "CombinedCascadedShadowMap" };
int NumSupportedShaderLODLevels = 1;
>;

#ifdef SUBDIV_SCALAR_DISPLACEMENT
Texture2D<float> DisplacementScalar;
#endif // SUBDIV_SCALAR_DISPLACEMENT

#ifdef SUBDIV_VECTOR_DISPLACEMENT
Texture2D<float4> DisplacementVector;
#endif // SUBDIV_VECTOR_DISPLACEMENT

#if defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
float DisplacementScale = 1.0f;
#endif // defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global shader parameters.
#ifdef ALPHA_ENABLED
float AlphaThreshold : ALPHATHRESHOLD <float UIMin = 0.0; float UIMax = 1.0; string UIName = "Alpha Threshold"; string UILabel = "The alpha threshold.";> = 0.0;		// The alpha threshold.
#endif //! ALPHA_ENABLED

float SoftDepthScale <float UIMin = 0.0001; float UIMax = 1.0; string UIName = "Soft Depth Scale"; string UILabel = "The scale for difference in depth between the particle and scene when softening particles.";> = 0.9f;

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Structures
struct ShadowTexturedVSInput
{
#ifdef VERTEX_COLOR_ENABLED
	float4 Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
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
	float2 Uv	: TEXCOORD0;
#ifdef SKINNING_ENABLED
	uint4	SkinIndices		: BLENDINDICES;
	float4	SkinWeights		: BLENDWEIGHTS;
#endif //! SKINNING_ENABLED
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1	: TEXCOORD1;
#endif //! MULTIPLE_UVS_ENABLED
};

struct ShadowTexturedVSOutput
{
#ifdef VERTEX_COLOR_ENABLED
	float4 Color : COLOR0;
#endif //! VERTEX_COLOR_ENABLED
	float4 Position	: SV_POSITION;	
	float2 Uv	: TEXCOORD0;
#ifdef MULTIPLE_UVS_ENABLED
	float2 Uv1	: TEXCOORD1;
#endif //! MULTIPLE_UVS_ENABLED
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
	Out.Uv = IN.Uv;
#ifdef MULTIPLE_UVS_ENABLED
	Out.Uv1 = IN.Uv1;
#endif //! MULTIPLE_UVS_ENABLED

#ifdef MAYA
	Out.Uv.y = 1.0 - Out.Uv.y;
#ifdef MULTIPLE_UVS_ENABLED
	Out.Uv1.y = 1.0 - Out.Uv1.y;
#endif //! MULTIPLE_UVS_ENABLED
#endif //! MAYA
#ifdef VERTEX_COLOR_ENABLED
	Out.Color = IN.Color;
#endif //! VERTEX_COLOR_ENABLED
	return Out;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Fragment shaders.
struct PS_OUTPUT
{
	float4 Colour	: FRAG_OUTPUT_COLOR0;
#ifdef VELOCITY_ENABLED
	float2 Velocity	: FRAG_OUTPUT_COLOR1;
#endif //! VELOCITY_ENABLED
};

// Forward render fragment shader
PS_OUTPUT ForwardRenderFP(DefaultVSForwardRenderOutput In)
{
#ifdef VERTEX_COLOR_ENABLED
	float4 shadingResult = In.Color * MaterialColour;
#else //! VERTEX_COLOR_ENABLED
	float4 shadingResult = MaterialColour;
#endif //! VERTEX_COLOR_ENABLED

#ifdef TEXTURE_ENABLED
	float4 texValue = TextureSampler.Sample(TextureSamplerSampler, In.Uv);
	shadingResult *= texValue;

#ifdef MULTIPLE_UVS_ENABLED
#ifdef LAYERED_TEXTURE_MODE_OVER_NONE_ENABLED
	float4 tex2 = TextureSampler1.Sample(TextureSampler1Sampler, In.Uv1);
	float3 fc = shadingResult.xyz;
	float  fa = shadingResult.w;
	float3 bc = tex2.xyz;
	float  ba = tex2.w;
	shadingResult.xyz = fc * fa + (bc * (1.0f - fa));
	shadingResult.w = 1.0f - ((1.0f - ba) * (1.0f - fa));
#endif //! LAYERED_TEXTURE_MODE_OVER_NONE_ENABLED
#endif //! MULTIPLE_UVS_ENABLED

#endif //! TEXTURE_ENABLED

#ifdef USE_LIGHTING
	// Read the normal here before any LOD clip, to keep the normal map texture read non-dependent on VITA.
	float3 normal = EvaluateNormal(In);
#endif //! USE_LIGHTING

	// Do alpha test and screendoor LOD Blend early.
#ifdef ALPHA_ENABLED
	clip(shadingResult.w - AlphaThreshold);
#endif //! ALPHA_ENABLED

#ifdef LOD_BLEND
	clip(GetLODDitherValue(GET_LOD_FRAGMENT_UV(In.Position)));
#endif //! LOD_BLEND

#ifdef LIGHTMAPPING

	#ifdef MULTIPLE_UVS_ENABLED
		float2 lightmapUV = In.Uv1;
	#else //! MULTIPLE_UVS_ENABLED
		float2 lightmapUV = In.Uv;
	#endif //! MULTIPLE_UVS_ENABLED

	lightmapUV = lightmapUV * LightmapUVScaleOffset.xy + LightmapUVScaleOffset.zw;

	float4 lightmap = LightmapSampler.Sample(LightmapSamplerSampler, lightmapUV);

#endif // LIGHTMAPPING

	// Lighting
#ifdef USE_LIGHTING

	float glossValue = 1;
	#ifdef TEXTURE_ENABLED
		glossValue = texValue.w;
	#endif //! TEXTURE_ENABLED

		float3 lightResult = EvaluateLightingDefault(In, In.WorldPositionDepth.xyz, normal, glossValue);

	#ifdef LIGHTMAP_RGB
		lightResult += lightmap.xyz;
	#endif // LIGHTMAP_RGB

	shadingResult *= float4(((lightResult * MaterialDiffuse) + MaterialEmissiveness), 1);
#endif //! USE_LIGHTING

#ifdef LIGHTMAP_RGB
	#ifndef USE_LIGHTING // No dynamic lights but lightmap detail
		float3 lightResult = GlobalAmbientColor.xyz + lightmap.xyz;
		shadingResult *= float4(((lightResult * MaterialDiffuse) + MaterialEmissiveness), 1);
	#endif // USE_LIGHTING
#endif // LIGHTMAP_RGB

#ifdef LIGHTMAP_OCCLUSION
	shadingResult.xyz *= lightmap.w;
#endif // LIGHTMAP_OCCLUSION

#ifdef FOG_ENABLED
	shadingResult.xyz = EvaluateFog(shadingResult.xyz, In.WorldPositionDepth.w);
#endif //! FOG_ENABLED
#ifdef TONE_MAP_ENABLED
	shadingResult = ToneMap(shadingResult.xyz);
#endif //! TONE_MAP_ENABLED

#ifdef CEL_ENABLED
#ifndef USE_LIGHTING
	float3 normal = EvaluateNormal(In);
#endif //! USE_LIGHTING
	float3 eyeToSurface = normalize(EyePosition - In.WorldPositionDepth.xyz);
	shadingResult.xyz = (abs(dot(eyeToSurface, normal)) < CelOutlineThickness) ? CelOutlineColor.xyz : shadingResult.xyz + CalcLightVal(normal);
#endif //! CEL_ENABLED

#ifdef LOW_RES_PARTICLES
	float sceneDepth = abs(ConvertDepth(LowResDepthTexture.SampleLevel(PointClampSampler, In.DepthTexCoord.xy, 0).x));
	float particleDepth = In.Position.w;
	float diff = saturate(SoftDepthScale * (sceneDepth - particleDepth));
	shadingResult.w *= diff;
#endif // LOW_RES_PARTICLES

	PS_OUTPUT Out;

	Out.Colour = shadingResult;

#ifdef VELOCITY_ENABLED
	Out.Velocity = CalculateVelocity(In.VelocityData);
#endif //! VELOCITY_ENABLED

	return Out;
}


// Light pre pass second pass shader. Samples the light prepass buffer.
float4 LightPrepassApplyFP(DefaultVSForwardRenderOutput In) : FRAG_OUTPUT_COLOR0
{
#ifdef VERTEX_COLOR_ENABLED
	float4 shadingResult = In.Color * MaterialColour;
#else //! VERTEX_COLOR_ENABLED
	float4 shadingResult = MaterialColour;
#endif //! VERTEX_COLOR_ENABLED
#ifdef TEXTURE_ENABLED
	shadingResult *= TextureSampler.Sample(TextureSamplerSampler, In.Uv);
#ifdef MULTIPLE_UVS_ENABLED
#endif //! MULTIPLE_UVS_ENABLED
#endif //! TEXTURE_ENABLED

	// Lighting
#ifdef USE_LIGHTING
#ifdef LIGHTPREPASS_ENABLED
	float2 screenUv = In.Position.xy * scene.screenWidthHeightInv;
	float4 lightResult = tex2D(LightPrepassSampler, screenUv);
#else //! LIGHTPREPASS_ENABLED
	float4 lightResult = 1;
#endif //! LIGHTPREPASS_ENABLED
#ifdef SPECULAR_ENABLED
	lightResult.xyz += (float)(lightResult.w * Shininess);
#endif //! SPECULAR_ENABLED
	shadingResult.xyz *= (float3)((lightResult.xyz * MaterialDiffuse) + MaterialEmissiveness);
#endif //! SPECULAR_ENABLED

#ifdef FOG_ENABLED
	shadingResult.xyz = EvaluateFog(shadingResult.xyz, In.WorldPositionDepth.w);
#endif //! FOG_ENABLED
#ifdef TONE_MAP_ENABLED
	shadingResult = ToneMap(shadingResult.xyz);
#endif //! TONE_MAP_ENABLED

	return shadingResult;
}


// Textured shadow shader.
void ShadowTexturedFP(ShadowTexturedVSOutput IN)
{
#ifdef ALPHA_ENABLED

#ifdef VERTEX_COLOR_ENABLED
	float4 shadingResult = IN.Color * MaterialColour;
#else //! VERTEX_COLOR_ENABLED
	float4 shadingResult = MaterialColour;
#endif //! VERTEX_COLOR_ENABLED

#ifdef TEXTURE_ENABLED
	shadingResult *= TextureSampler.Sample(TextureSamplerSampler, IN.Uv);
#endif //! TEXTURE_ENABLED

	float alphaValue = shadingResult.w;
	clip(alphaValue - AlphaThreshold);
#endif //! ALPHA_ENABLED
}


#ifdef GENERATE_LIGHTS

// Technique to capture emissive surfaces.

[maxvertexcount(1)] void GS_CaptureEmissiveSurfaces( triangle DefaultVSDeferredRenderOutput input[3], inout PointStream<DefaultVSDeferredRenderOutput> OutputStream, uint TriangleIndex : SV_PRIMITIVEID )
{
	// only output emissive faces
	if(MaterialEmissiveness > 0.95f)
	{
		
		// Cull faces that are not emissive
		
		DefaultVSDeferredRenderOutput Out;
		
#ifdef USE_UVS
		Out.Uv = (input[0].Uv + input[1].Uv + input[2].Uv) / 3.0f;
#else // USE_UVS
		Out.Uv = 0.0f;
#endif // USE_UVS
		Out.Normal = normalize( mul(float4( (input[0].Normal + input[1].Normal + input[2].Normal) / 3.0f, 0.0f), ViewInverse ).xyz );

		float3 areaCross = cross(input[1].WorldPositionDepth.xyz - input[0].WorldPositionDepth.xyz, input[2].WorldPositionDepth.xyz - input[0].WorldPositionDepth.xyz);
		float triArea = length(areaCross) * 0.5f;
		
		Out.WorldPositionDepth = (input[0].WorldPositionDepth + input[1].WorldPositionDepth + input[2].WorldPositionDepth) / 3.0f;
		Out.Color = (input[0].Color + input[1].Color + input[2].Color) / 3.0f;

		// normalize tri area 
		triArea = saturate(triArea * 100.0f);
		Out.Color.w = triArea;
#ifdef USE_TANGENTS
		Out.Tangent = (input[0].Tangent + input[1].Tangent + input[2].Tangent) / 3.0f;
#endif //! USE_TANGENTS	

		uint idx = TriangleIndex; 
		uint2 pixelPosition = uint2(idx, idx >> 7) & 127;
	
		// the pixel position is irrelevant - it's just to avoid pixel shader / thread contention
		float2 pos = (float2(pixelPosition) / 128.0f) * 2.0f - 1.0f;
		pos = pos * 0.8f;
		

		Out.Position = float4(pos,0.0f,1.0f);

#ifdef VELOCITY_ENABLED
		Out.VelocityData.PositionCurrent = Out.Position;
		Out.VelocityData.PositionPrev = Out.Position;
#endif //! VELOCITY_ENABLED

		OutputStream.Append( Out );		
	}
}

RWStructuredBuffer <PDeferredLight> RWDeferredLightBuffer;


float4x4 LookAt(float3 pos, float3 dir, float3 lat,float3 up)
{
	float4x4 mat;
	
	mat[0] = float4( lat.x, up.x, dir.x, 0.0f );
	mat[1] = float4( lat.y, up.y, dir.y, 0.0f );
	mat[2] = float4( lat.z, up.z, dir.z, 0.0f );
	mat[3] = float4( -dot(pos,lat), -dot(pos,up), -dot(pos,dir), 1.0f);

	return mat;
}



// Deferred rendering
//InstantLightOutput PS_CaptureEmissiveSurfaces(DefaultVSDeferredRenderOutput In) 
float4 PS_CaptureEmissiveSurfaces(DefaultVSDeferredRenderOutput In) : FRAG_OUTPUT_COLOR0
{ 
	float4 color = In.Color;
#ifdef TEXTURE_ENABLED
	color *= TextureSampler.Sample(TextureSamplerSampler, In.Uv);
#endif //! TEXTURE_ENABLED
	
	float3 centrePosition = In.WorldPositionDepth.xyz;
	float3 centreNormal = In.Normal;
	centreNormal = -normalize(centreNormal);

	float3 worldPosition = centrePosition;
	float3 viewPosition = (float3)(mul(float4(worldPosition,1.0f), View));
	float3 viewNormal = normalize(mul(float4(centreNormal,0.0f), View).xyz);
	float4 projPosition = mul(float4(worldPosition,1.0f),ViewProjection);
	float lightEdgeFade = 1.0f;
	if(projPosition.w > 0)
	{
		projPosition.xy /= projPosition.w;
		lightEdgeFade *= saturate( (0.8f - abs(projPosition.x)) * 4.0f );
	}

	float triArea = In.Color.w;
	float lightAtten = 15.0f * (triArea * 0.7f + 0.3f);
	float spotAngle = 0.3f * (triArea * 0.5f + 0.5f);
	float spotAngleInner = 0.1f * (triArea * 0.5f + 0.5f);
	color.xyz *= lightEdgeFade;

	if(dot(color.xyz, 0.333f) > 0.0001f)
	{
		float3 dir = centreNormal;
		float3 up = abs(dir.y) > 0.9f ? float3(0.0f,0.0f,1.0f) : float3(0.0f,1.0f,0.0f);
		float3 lat = normalize(cross(up,dir));
		up = normalize(cross(lat,dir));
	
		float4x4 worldInverse = LookAt(worldPosition, dir, lat, up);

		uint numLights = RWDeferredLightBuffer.IncrementCounter();

		RWDeferredLightBuffer[numLights].m_viewToLocalTransform = worldInverse;
		RWDeferredLightBuffer[numLights].m_shadowMask = 0;
		RWDeferredLightBuffer[numLights].m_position = viewPosition;
		RWDeferredLightBuffer[numLights].m_direction = viewNormal;
		RWDeferredLightBuffer[numLights].m_color = float4(color.xyz,1.0f);
		RWDeferredLightBuffer[numLights].m_scatterIntensity = 0.06f * triArea;

		RWDeferredLightBuffer[numLights].m_attenuation = float2(0.0f,lightAtten);
		RWDeferredLightBuffer[numLights].m_coneBaseRadius = tan(spotAngle) * lightAtten;

		RWDeferredLightBuffer[numLights].m_spotAngles.x = cos(spotAngleInner - 1e-6f);
		RWDeferredLightBuffer[numLights].m_spotAngles.y = cos(spotAngle - 1e-6f);
		RWDeferredLightBuffer[numLights].m_tanConeAngle = tan(spotAngle);
		RWDeferredLightBuffer[numLights].m_lightType = PD_DEFERRED_LIGHT_TYPE_SPOT;
	}
	return 1;
}

#endif //! GENERATE_LIGHTS

#ifdef SUBDIV

#define PHYRE_BLEND_PATCHES(NAME) IN.NAME = uvwCoord.x * patch[0].NAME + uvwCoord.y * patch[1].NAME + uvwCoord.z * patch[2].NAME

#ifdef __ORBIS__

///
// Subdiv configuration for this shader

// Reusing existing structure as pixel inputs
#ifdef PHYRE_ENTRYPOINT_DefaultDeferredDomainShader

	#define SCE_SUBDIV_USER_PIXEL_INPUT_PARAMETERS \
		DefaultVSDeferredRenderOutput params;

#else //! PHYRE_ENTRYPOINT_DefaultDeferredDomainShader

	#define SCE_SUBDIV_USER_PIXEL_INPUT_PARAMETERS \
		DefaultVSForwardRenderOutput params;

#endif //! PHYRE_ENTRYPOINT_DefaultDeferredDomainShader

#define SCE_SUBDIV_FRACTIONAL_EVEN_SPACING

#ifdef USE_UVS
	// Assume float2 UVs in channel 0
	#define SCE_SUBDIV_FVAR_WIDTH_CHANNEL_0 2

	// Seam data for UVs for any displacement
	#if defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
		#define SCE_SUBDIV_FVAR_SEAM_CHANNEL_0
	#endif // defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
#endif //! USE_UVS

#ifdef USE_TANGENTS
	// Assume float4 tangents in channel 1 - xyz = tangent w = flip
	#define SCE_SUBDIV_FVAR_WIDTH_CHANNEL_1 4

	// Seam data for tangents for only vector displacement
	#ifdef SUBDIV_VECTOR_DISPLACEMENT
		#define SCE_SUBDIV_FVAR_SEAM_CHANNEL_1
	#endif // SUBDIV_VECTOR_DISPLACEMENT
#endif // USE_TANGENTS

#ifdef MULTIPLE_UVS_ENABLED
	// Assume float2 UVs in channel 2
	#define SCE_SUBDIV_FVAR_WIDTH_CHANNEL_2 2

	// Seam data for UVs for any displacement
	#if defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
		#define SCE_SUBDIV_FVAR_SEAM_CHANNEL_2
	#endif // defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
#endif // MULTIPLE_UVS_ENABLED

// Use more accurate tangent calculations on extraordinary points. This reduces cracking when using displacement
#if defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
	#define SCE_SUBDIV_WATERTIGHT_EXTRAORDINARY_POINTS
#endif // defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)

// Include PhyreEngine Subdiv helper after initial configuration
#include "PhyreSubdivFX.h"

// Optional:
// This could be an existing SRT struct if present
struct BaseSRT
{
	sce::Subdiv::Shader::BezierSRT * subdiv;
};

SCE_SUBDIV_BEZIER_LOCAL_FUNCTION(DefaultForwardRenderPassThruVS, BaseSRT baseSRT)
{
#if defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
	BezierHullVertex output = SCE_SUBDIV_RUN_BEZIER_LS_DISP(baseSRT.subdiv, DisplacementScale);
#else
	BezierHullVertex output = SCE_SUBDIV_RUN_BEZIER_LS(baseSRT.subdiv);
#endif // defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)

	SCE_SUBDIV_BEZIER_LS_OUTPUT(output);
}

float4 GetTangentFromBezierData(BezierHullConstants input, float2 domainCoord, BezierEvalData bezierData)
{
	float4 tangent;
	SCE_SUBDIV_COMPUTE_FACE_VARYING_CHANNEL(tangent, 1, bezierData.uv);
	float3 outTangent = SCE_SUBDIV_MUL(World, float4(tangent.xyz, 0.0f)).xyz;
	outTangent = normalize(SCE_SUBDIV_ORTHOGONALIZE(outTangent, bezierData.normal.xyz));
	return float4(outTangent, tangent.w);
}

void HandleDisplacement(BezierHullConstants input, float2 domainCoord, inout BezierEvalData bezierData, float2 dispUV)
{
#if defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)
	SCE_SUBDIV_COMPUTE_FACE_VARYING_IDENTICAL_SEAM(dispUV, 0, bezierData.uv);

	//sce::Gnm::Sampler g_samplerTrilinear;
	//g_samplerTrilinear.init();
	//g_samplerTrilinear.setMipFilterMode(sce::Gnm::kMipFilterModeLinear);
	//g_samplerTrilinear.setXyFilterMode(sce::Gnm::kFilterModeBilinear, sce::Gnm::kFilterModeBilinear);
	uint4 g_samplerTrilinear = uint4(0x00000000, 0x00fff000, 0x09500000, 0x00000000);
	SamplerState samp = __create_sampler_state(g_samplerTrilinear);

#endif // defined(SUBDIV_SCALAR_DISPLACEMENT) || defined(SUBDIV_VECTOR_DISPLACEMENT)

	float mipLevel = 0;
#ifdef SUBDIV_VECTOR_DISPLACEMENT
	// For vector displacement the tangents are used as part of calculating the displacement. 
	// This means that, in addition to using the same UV on either side of a seam, 
	// the same tangent should also be used on either side of a tangent seam in order to avoid cracks.		
	float4 seamTan;
	SCE_SUBDIV_COMPUTE_FACE_VARYING_CHANNEL(seamTan, 1, bezierData.uv);
	SCE_SUBDIV_COMPUTE_FACE_VARYING_IDENTICAL_SEAM(seamTan, 1, bezierData.uv);
	seamTan.xyz = SCE_SUBDIV_MUL(World, float4(seamTan.xyz, 0.0f)).xyz;
	float3 dispTan = normalize(SCE_SUBDIV_ORTHOGONALIZE(seamTan.xyz, bezierData.normal.xyz));
	float3 dispBitan = normalize(cross(bezierData.normal.xyz, dispTan.xyz) * seamTan.w);

	float3 disp = DisplacementVector.SampleLOD(samp, dispUV, mipLevel).xyz;
	// Map has y up so switching y and z
	disp = disp.x * dispTan +
		disp.z * dispBitan +
		disp.y * bezierData.normal.xyz;
	bezierData.position += disp * DisplacementScale;

#elif defined(SUBDIV_SCALAR_DISPLACEMENT)
	// For scalar displacement it is sufficient to use the same UV on either side of a seam, 
	// since the normals will match when using watertightExtraordinaryPoints
	float disp = DisplacementScalar.SampleLOD(samp, dispUV, mipLevel).x;
	bezierData.position += disp * DisplacementScale * normalize(bezierData.normal.xyz);
#endif // DISPLACEMENT
}

void RemoveWorldFromMatrices()
{
	// Since subdiv generates world space data, we need to remove World the matrices for the next steps
	World = float4x4(
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1);
	WorldView = View;
	WorldViewProjection = ViewProjection;
	WorldViewProjectionPrev = ViewProjectionPrev;
}

#ifdef PHYRE_ENTRYPOINT_DefaultForwardDomainShader
SCE_SUBDIV_BEZIER_DOMAIN_FUNCTION(DefaultForwardDomainShader, BaseSRT baseSRT)
{
	BezierEvalData bezierData;
	BezierPixelVertex output = SCE_SUBDIV_RUN_BEZIER_DS(baseSRT.subdiv, bezierData);

	DefaultVSInput IN;

#ifdef VERTEX_COLOR_ENABLED
	PHYRE_BLEND_PATCHES(Color);
#endif //! VERTEX_COLOR_ENABLED

#ifdef USE_UVS
	SCE_SUBDIV_COMPUTE_FACE_VARYING_CHANNEL(IN.Uv, 0, bezierData.uv);

	HandleDisplacement(input, domainCoord, bezierData, IN.Uv);
#endif //! USE_UVS

	IN.Normal = bezierData.normal.xyz;

#ifdef USE_TANGENTS
	IN.Tangent = GetTangentFromBezierData(input, domainCoord, bezierData).xyz;
#endif //! USE_TANGENTS

	IN.Position = float4(bezierData.position.xyz, 1);

#ifdef MULTIPLE_UVS_ENABLED
	SCE_SUBDIV_COMPUTE_FACE_VARYING_CHANNEL(IN.Uv1, 2, bezierData.uv);
#endif //! MULTIPLE_UVS_ENABLED

	// Execute the default forward render shader
	RemoveWorldFromMatrices();
	output.params = DefaultForwardRenderVS(IN);

	SCE_SUBDIV_BEZIER_DS_OUTPUT(bezierData, output);
}
#endif // PHYRE_ENTRYPOINT_DefaultForwardDomainShader

#ifdef PHYRE_ENTRYPOINT_DefaultDeferredDomainShader
SCE_SUBDIV_BEZIER_DOMAIN_FUNCTION(DefaultDeferredDomainShader, BaseSRT baseSRT)
{
	BezierEvalData bezierData;
	BezierPixelVertex output = SCE_SUBDIV_RUN_BEZIER_DS(baseSRT.subdiv, bezierData);

	DefaultVSInput IN;

#ifdef VERTEX_COLOR_ENABLED
	PHYRE_BLEND_PATCHES(Color);
#endif //! VERTEX_COLOR_ENABLED

	IN.Position = float4(bezierData.position.xyz, 1);
	IN.Normal = bezierData.normal.xyz;

#ifdef USE_UVS
	SCE_SUBDIV_COMPUTE_FACE_VARYING_CHANNEL(IN.Uv, 0, bezierData.uv);

	HandleDisplacement(input, domainCoord, bezierData, IN.Uv);
#endif //! USE_UVS

#ifdef USE_TANGENTS
	IN.Tangent = GetTangentFromBezierData(input, domainCoord, bezierData).xyz;
#endif //! USE_TANGENTS

#ifdef MULTIPLE_UVS_ENABLED
	SCE_SUBDIV_COMPUTE_FACE_VARYING_CHANNEL(IN.Uv1, 2, bezierData.uv);
#endif //! MULTIPLE_UVS_ENABLED

	// Execute the default forward render shader
	RemoveWorldFromMatrices();
	output.params = DefaultDeferredRenderVS(IN);

	SCE_SUBDIV_BEZIER_DS_OUTPUT(bezierData, output);
}
#endif // PHYRE_ENTRYPOINT_DefaultDeferredDomainShader

SCE_SUBDIV_BEZIER_HULL_FUNCTION(DefaultForwardHullShader, DefaultForwardHullShaderConstants, BaseSRT baseSRT)
{
	BezierDomainVertex output = SCE_SUBDIV_RUN_BEZIER_HS(baseSRT.subdiv);
	SCE_SUBDIV_BEZIER_HS_OUTPUT(output);
}

SCE_SUBDIV_BEZIER_HULL_CONSTANT_FUNCTION(DefaultForwardHullShaderConstants, BaseSRT baseSRT)
{
	BezierHullConstants hcOutput = SCE_SUBDIV_RUN_BEZIER_HCF(baseSRT.subdiv);
	SCE_SUBDIV_BEZIER_HCF_OUTPUT(hcOutput);
}

#else // Non-ORBIS version - Fixed tessellation as a fallback

DefaultVSInput DefaultForwardRenderPassThruVS(DefaultVSInput IN)
{
	return IN;
}

struct DefaultTessOutputType
{
	float edges[3] : SV_TessFactor;
	float inside : SV_InsideTessFactor;
};

[domain("tri")]
DefaultVSForwardRenderOutput DefaultForwardDomainShader(DefaultTessOutputType input, float3 uvwCoord : SV_DomainLocation, const OutputPatch<DefaultVSInput, 3> patch)
{
	DefaultVSInput IN;

#ifdef VERTEX_COLOR_ENABLED
	PHYRE_BLEND_PATCHES(Color);
#endif //! VERTEX_COLOR_ENABLED

	PHYRE_BLEND_PATCHES(Position);
	PHYRE_BLEND_PATCHES(Normal);

#ifdef USE_UVS
	PHYRE_BLEND_PATCHES(Uv);
#endif //! USE_UVS

#ifdef USE_TANGENTS
	PHYRE_BLEND_PATCHES(Tangent);
#endif //! USE_TANGENTS

#ifdef MULTIPLE_UVS_ENABLED
	PHYRE_BLEND_PATCHES(Uv1);
#endif //! MULTIPLE_UVS_ENABLED

	DefaultVSForwardRenderOutput OUT = DefaultForwardRenderVS(IN);
	return OUT;
}

[domain("tri")]
DefaultVSDeferredRenderOutput DefaultDeferredDomainShader(DefaultTessOutputType input, float3 uvwCoord : SV_DomainLocation, const OutputPatch<DefaultVSInput, 3> patch)
{
	DefaultVSInput IN;

#ifdef VERTEX_COLOR_ENABLED
	PHYRE_BLEND_PATCHES(Color);
#endif //! VERTEX_COLOR_ENABLED

	PHYRE_BLEND_PATCHES(Position);
	PHYRE_BLEND_PATCHES(Normal);

#ifdef USE_UVS
	PHYRE_BLEND_PATCHES(Uv);
#endif //! USE_UVS

#ifdef USE_TANGENTS
	PHYRE_BLEND_PATCHES(Tangent);
#endif //! USE_TANGENTS

#ifdef MULTIPLE_UVS_ENABLED
	PHYRE_BLEND_PATCHES(Uv1);
#endif //! MULTIPLE_UVS_ENABLED

	DefaultVSDeferredRenderOutput OUT = DefaultDeferredRenderVS(IN);
	return OUT;
}

DefaultTessOutputType DefaultForwardHullShaderConstants(InputPatch<DefaultVSInput, 3> inputPatch, uint patchId : SV_PrimitiveID)
{
	// Fixed tessellation as a fallback
	float tessellationAmount = 2.0f;
	DefaultTessOutputType output;

	// Set the tessellation factors for the three edges of the triangle.
	output.edges[0] = tessellationAmount;
	output.edges[1] = tessellationAmount;
	output.edges[2] = tessellationAmount;

	// Set the tessellation factor for tessellating inside the triangle.
	output.inside = tessellationAmount;

	return output;
}

[domain("tri")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("DefaultForwardHullShaderConstants")]
DefaultVSInput DefaultForwardHullShader(InputPatch<DefaultVSInput, 3> patch, uint pointId : SV_OutputControlPointID, uint patchId : SV_PrimitiveID)
{
	DefaultVSInput output;

	output = patch[pointId];

	return output;
}

#endif // ORBIS

#endif // SUBDIV

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
BlendState LowResParticleBlend 
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = SRC_ALPHA;
	DestBlend[0] = INV_SRC_ALPHA;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ZERO;
	DestBlendAlpha[0] = INV_SRC_ALPHA;
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

#ifdef LIGHTING_ENABLED
	#define IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING /* Nothing */
#else //! LIGHTING_ENABLED
	// If we're not using lighting then the shader is not dependent on the light count.
	#define IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "NUM_LIGHTS",
#endif //! LIGHTING_ENABLED

#ifndef ALPHA_ENABLED

technique11 ForwardRender
<
	string PhyreRenderPass = "Opaque";
	string VpIgnoreContextSwitches[] = {"NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES"};
	string FpIgnoreContextSwitches[] = {IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "MULTISLICE_VR" };
>
{
	pass pass0
	{
#ifdef SUBDIV
		SetVertexShader( CompileShader( vs_4_0, DefaultForwardRenderPassThruVS() ) );
		SetHullShader( CompileShader( hs_5_0, DefaultForwardHullShader() ) );
		SetDomainShader( CompileShader( ds_5_0, DefaultForwardDomainShader() ) );
#else // SUBDIV
		SetVertexShader( CompileShader( vs_4_0, DefaultForwardRenderVS() ) );
#endif // SUBDIV
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! ALPHA_ENABLED

#ifdef ALPHA_ENABLED

technique11 ForwardRenderAlpha
<
#ifdef RENDER_AS_LOW_RES
	string PhyreRenderPass = "LowResParticles";
#else // RENDER_AS_LOW_RES
	string PhyreRenderPass = "Transparent";
#endif // RENDER_AS_LOW_RES
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "VELOCITY_ENABLED" };
    string FpIgnoreContextSwitches[] = { IGNORE_NUM_LIGHTS_IF_NOT_LIGHTING "INSTANCING_ENABLED", "INDICES_16BIT", "VELOCITY_ENABLED", "MULTISLICE_VR" };
>
{
	pass pass0
	{
		SetVertexShader( CompileShader( vs_4_0, DefaultForwardRenderVS() ) );
		SetPixelShader( CompileShader( ps_4_0, ForwardRenderFP() ) );
		
#ifdef RENDER_AS_LOW_RES
		SetBlendState( LowResParticleBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
#else // RENDER_AS_LOW_RES
		SetBlendState( LinearBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
#endif // RENDER_AS_LOW_RES
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! ALPHA_ENABLED

#ifdef CASTS_SHADOWS

#ifdef ALPHA_ENABLED

technique11 ShadowTransparent
<
	string PhyreRenderPass = "ShadowTransparent";
	string VpIgnoreContextSwitches[] = {"NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
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

#else //! ALPHA_ENABLED

technique11 Shadow
<
	string PhyreRenderPass = "Shadow";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
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

#endif //! ALPHA_ENABLED

#endif //! CASTS_SHADOWS

#ifndef ALPHA_ENABLED

technique11 ZPrePass
<
	string PhyreRenderPass = "ZPrePass";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES",  "VELOCITY_ENABLED", "MULTISLICE_VR" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
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

#endif //! ALPHA_ENABLED



#ifndef ALPHA_ENABLED

// Techniques
technique11 DeferredRender
<
	string PhyreRenderPass = "DeferredRender";
	string VpIgnoreContextSwitches[] = {"NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES" };
	string FpIgnoreContextSwitches[] = {"NUM_LIGHTS", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "MULTISLICE_VR" };
>
{
	pass p0
	{

#ifdef SUBDIV
		SetVertexShader(CompileShader(vs_4_0, DefaultForwardRenderPassThruVS()));
		SetHullShader(CompileShader(hs_5_0, DefaultForwardHullShader()));
		SetDomainShader(CompileShader(ds_5_0, DefaultDeferredDomainShader()));
#else // SUBDIV
		SetVertexShader(CompileShader(vs_4_0, DefaultDeferredRenderVS()));
#endif // SUBDIV

		SetPixelShader( CompileShader( ps_4_0, DefaultDeferredRenderFP() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthStateWithNoStencil, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! ALPHA_ENABLED




#ifdef GENERATE_LIGHTS

// Techniques
technique11 CaptureEmissiveSurfaces
<
	string PhyreRenderPass = "CaptureEmissiveSurfaces";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
	string IgnoreContextSwitches[] = { "VELOCITY_ENABLED" };
>
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_5_0, DefaultDeferredRenderVS() ) );
		SetGeometryShader( CompileShader( gs_5_0, GS_CaptureEmissiveSurfaces() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_CaptureEmissiveSurfaces() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( NoCullRasterState );
	}
}

#endif //! GENERATE_LIGHTS


#if 0 // Note: These techniques are disabled until future support is added
#ifndef ALPHA_ENABLED

technique11 LightPrePass
<
	string PhyreRenderPass = "LightPrePass";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", , "VELOCITY_ENABLED", "MULTISLICE_VR" };
>
{
	pass p0
	{
		DepthTestEnable=true;
#ifdef ZPREPASS_ENABLED
		DepthMask = false;
#else //! ZPREPASS_ENABLED
		DepthMask = true;
#endif //! ZPREPASS_ENABLED
		DepthFunc = LEqual;
		ColorMask = bool4(true,true,true,true);
#ifdef DOUBLE_SIDED
		CullFaceEnable = false;
#else //! DOUBLE_SIDED
		CullFaceEnable = true;
#ifndef MAX
		CullFace = back;
#endif //! MAX
#endif //! DOUBLE_SIDED
		VertexProgram = compile vp40 DefaultForwardRenderVS();
		FragmentProgram = compile fp40 DefaultLightPrepassFP();
	}
}

technique11 LightPreMaterialPass
<
	string PhyreRenderPass = "LightPrePassMaterial";
	string VpIgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
    string FpIgnoreContextSwitches[] = { "NUM_LIGHTS", "INSTANCING_ENABLED", "INDICES_16BIT", "LOW_RES_PARTICLES", "VELOCITY_ENABLED", "MULTISLICE_VR" };
>
{
	pass
	{
		DepthTestEnable=true;
		DepthMask = false;
		DepthFunc = LEqual;
		ColorMask = bool4(true,true,true,true);
#ifdef DOUBLE_SIDED
		CullFaceEnable = false;
#else //! DOUBLE_SIDED
		CullFaceEnable = true;
#ifndef MAX
		CullFace = back;
#endif //! MAX
#endif //! DOUBLE_SIDED
		VertexProgram = compile vp40 DefaultForwardRenderVS();
		FragmentProgram = compile fp40 LightPrepassApplyFP();
	}
}


#endif //! ALPHA_ENABLED

#endif //! Disabled techniques

#endif //! __ORBIS__
