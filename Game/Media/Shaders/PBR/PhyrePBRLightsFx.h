/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_PBR_LIGHTS_FX_H
#define PHYRE_PBR_LIGHTS_FX_H

//////////////////////////////////////////
// Engine-supplied lighting parameters. //
//////////////////////////////////////////

#ifdef USE_LIGHTING

	// Separate lighting structures
	#if NUM_LIGHTS > 0
		LIGHTTYPE_0								Light0 : LIGHT0;
		MERGE(LIGHTTYPE_0, SpecularMapType)		LightSpecularMap0 : LIGHTSPECULARMAP0;
		MERGE(LIGHTTYPE_0, DiffuseMapType)		LightDiffuseMap0 : LIGHTDIFFUSEMAP0;
		MERGE(LIGHTTYPE_0, DiffuseBufferType)	LightDiffuseBuffer0 : LIGHTDIFFUSEBUFFER0;
		#ifndef SHADOWTYPE_0
			#define LightShadow0 0.0f
			#define LightShadowMap0 0.0f
		#else //! SHADOWTYPE_0
			SHADOWTYPE_0						LightShadow0 : LIGHTSHADOW0;
			Texture2D <float>					LightShadowMap0 : LIGHTSHADOWMAP0;
		#endif //! SHADOWTYPE_0
	#endif //! NUM_LIGHTS > 0

	#if NUM_LIGHTS > 1
		LIGHTTYPE_1								Light1 : LIGHT1;
		MERGE(LIGHTTYPE_1, SpecularMapType)		LightSpecularMap1 : LIGHTSPECULARMAP1;
		MERGE(LIGHTTYPE_1, DiffuseMapType)		LightDiffuseMap1 : LIGHTDIFFUSEMAP1;
		MERGE(LIGHTTYPE_1, DiffuseBufferType)	LightDiffuseBuffer1 : LIGHTDIFFUSEBUFFER1;
		#ifndef SHADOWTYPE_1
			#define LightShadow1 0.0f
			#define LightShadowMap1 0.0f
		#else //! SHADOWTYPE_1
			SHADOWTYPE_1						LightShadow1 : LIGHTSHADOW1;
			Texture2D <float>					LightShadowMap1 : LIGHTSHADOWMAP1;
		#endif //! SHADOWTYPE_1
	#endif //! NUM_LIGHTS > 1

	#if NUM_LIGHTS > 2
		LIGHTTYPE_2								Light2 : LIGHT2;
		MERGE(LIGHTTYPE_2, SpecularMapType)		LightSpecularMap2 : LIGHTSPECULARMAP2;
		MERGE(LIGHTTYPE_2, DiffuseMapType)		LightDiffuseMap2 : LIGHTDIFFUSEMAP2;
		MERGE(LIGHTTYPE_2, DiffuseBufferType)	LightDiffuseBuffer2 : LIGHTDIFFUSEBUFFER2;
		#ifndef SHADOWTYPE_2
			#define LightShadow2 0.0f
			#define LightShadowMap2 0.0f
		#else //! SHADOWTYPE_2
			SHADOWTYPE_2						LightShadow2 : LIGHTSHADOW2;
			Texture2D <float>					LightShadowMap2 : LIGHTSHADOWMAP2;
		#endif //! SHADOWTYPE_2
	#endif //! NUM_LIGHTS > 2

	#if NUM_LIGHTS > 3
		LIGHTTYPE_3								Light3 : LIGHT3;
		MERGE(LIGHTTYPE_3, SpecularMapType)		LightSpecularMap3 : LIGHTSPECULARMAP3;
		MERGE(LIGHTTYPE_3, DiffuseMapType)		LightDiffuseMap3 : LIGHTDIFFUSEMAP3;
		MERGE(LIGHTTYPE_3, DiffuseBufferType)	LightDiffuseBuffer3 : LIGHTDIFFUSEBUFFER3;
		#ifndef SHADOWTYPE_3
			#define LightShadow3 0.0f
			#define LightShadowMap3 0.0f
		#else //! SHADOWTYPE_3
			SHADOWTYPE_3						LightShadow3 : LIGHTSHADOW3;
			Texture2D <float>					LightShadowMap3 : LIGHTSHADOWMAP3;
		#endif //! SHADOWTYPE_3
	#endif //! NUM_LIGHTS > 3

	#if NUM_LIGHTS > 4
		LIGHTTYPE_4								Light4 : LIGHT4;
		MERGE(LIGHTTYPE_4, SpecularMapType)		LightSpecularMap4 : LIGHTSPECULARMAP4;
		MERGE(LIGHTTYPE_4, DiffuseMapType)		LightDiffuseMap4 : LIGHTDIFFUSEMAP4;
		MERGE(LIGHTTYPE_4, DiffuseBufferType)	LightDiffuseBuffer4 : LIGHTDIFFUSEBUFFER4;
		#ifndef SHADOWTYPE_4
			#define LightShadow4 0.0f
			#define LightShadowMap4 0.0f
		#else //! SHADOWTYPE_4
			SHADOWTYPE_4						LightShadow4 : LIGHTSHADOW4;
			Texture2D <float>					LightShadowMap4 : LIGHTSHADOWMAP4;
		#endif //! SHADOWTYPE_4
	#endif //! NUM_LIGHTS > 4

	#if NUM_LIGHTS > 5
		LIGHTTYPE_5								Light5 : LIGHT5;
		MERGE(LIGHTTYPE_5, SpecularMapType)		LightSpecularMap5 : LIGHTSPECULARMAP5;
		MERGE(LIGHTTYPE_5, DiffuseMapType)		LightDiffuseMap5 : LIGHTDIFFUSEMAP5;
		MERGE(LIGHTTYPE_5, DiffuseBufferType)	LightDiffuseBuffer5 : LIGHTDIFFUSEBUFFER5;
		#ifndef SHADOWTYPE_5
			#define LightShadow5 0.0f
			#define LightShadowMap5 0.0f
		#else //! SHADOWTYPE_5
			SHADOWTYPE_5						LightShadow5 : LIGHTSHADOW5;
			Texture2D <float>					LightShadowMap5 : LIGHTSHADOWMAP5;
		#endif //! SHADOWTYPE_5
	#endif //! NUM_LIGHTS > 5

	#if NUM_LIGHTS > 6
		LIGHTTYPE_6								Light6 : LIGHT6;
		MERGE(LIGHTTYPE_6, SpecularMapType)		LightSpecularMap6 : LIGHTSPECULARMAP6;
		MERGE(LIGHTTYPE_6, DiffuseMapType)		LightDiffuseMap6 : LIGHTDIFFUSEMAP6;
		MERGE(LIGHTTYPE_6, DiffuseBufferType)	LightDiffuseBuffer6 : LIGHTDIFFUSEBUFFER6;
		#ifndef SHADOWTYPE_6
			#define LightShadow6 0.0f
			#define LightShadowMap6 0.0f
		#else //! SHADOWTYPE_6
			SHADOWTYPE_6						LightShadow6 : LIGHTSHADOW6;
			Texture2D <float>					LightShadowMap6 : LIGHTSHADOWMAP6;
		#endif //! SHADOWTYPE_6
	#endif //! NUM_LIGHTS > 6

	#if NUM_LIGHTS > 7
		LIGHTTYPE_7								Light7 : LIGHT7;
		MERGE(LIGHTTYPE_7, SpecularMapType)		LightSpecularMap7 : LIGHTSPECULARMAP7;
		MERGE(LIGHTTYPE_7, DiffuseMapType)		LightDiffuseMap7 : LIGHTDIFFUSEMAP7;
		MERGE(LIGHTTYPE_7, DiffuseBufferType)	LightDiffuseBuffer7 : LIGHTDIFFUSEBUFFER7;
		#ifndef SHADOWTYPE_7
			#define LightShadow7 0.0f
			#define LightShadowMap7 0.0f
		#else //! SHADOWTYPE_7
			SHADOWTYPE_7						LightShadow7 : LIGHTSHADOW7;
			Texture2D <float>					LightShadowMap7 : LIGHTSHADOWMAP7;
		#endif //! SHADOWTYPE_7
	#endif //! NUM_LIGHTS > 7
#endif //! USE_LIGHTING

////////////////////
// Shader helpers //
////////////////////

// Description:
// Macro to evaluate the lighting for a single light.
// Arguments:
// lightIndex - The index of the light to evaluate.
#define EvaluateLightFunctionPBR(LightIndex) \
	{ \
		float shad = EvaluateShadowValue(Light##LightIndex, LightShadow##LightIndex, LightShadowMap##LightIndex, geom.m_worldPosition, viewDepth); \
		PbrLightingResults localLightResult = EvaluateLightPBR(Light##LightIndex, LightSpecularMap##LightIndex, LightDiffuseMap##LightIndex, LightDiffuseBuffer##LightIndex, V, shad, mat, geom); \
		Accumulate(Light##LightIndex, lightResult, iblLightResult, localLightResult); \
	}

// Description:
// Evaluate the lighting for all lights at a point on the surface.
// Arguments:
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The lighting results at the point on the surface.
static PbrLightingResults EvaluateLightingPBR(PbrMaterialProperties mat, PbrGeomProperties geom)
{
	// Lighting
	PbrLightingResults lightResult;
	ResetValid(lightResult);
	PbrLightingResults iblLightResult;
	ResetInvalid(iblLightResult);

#ifdef USE_LIGHTING

	float viewDepth = geom.m_viewDepth;
	float3 V = normalize(EyePosition - geom.m_worldPosition);

#if NUM_LIGHTS > 0
	EvaluateLightFunctionPBR(0);
#endif //! NUM_LIGHTS > 0
#if NUM_LIGHTS > 1
	EvaluateLightFunctionPBR(1);
#endif //! NUM_LIGHTS > 1
#if NUM_LIGHTS > 2
	EvaluateLightFunctionPBR(2);
#endif //! NUM_LIGHTS > 2
#if NUM_LIGHTS > 3
	EvaluateLightFunctionPBR(3);
#endif //! NUM_LIGHTS > 3
#if NUM_LIGHTS > 4
	EvaluateLightFunctionPBR(4);
#endif //! NUM_LIGHTS > 4
#if NUM_LIGHTS > 5
	EvaluateLightFunctionPBR(5);
#endif //! NUM_LIGHTS > 5
#if NUM_LIGHTS > 6
	EvaluateLightFunctionPBR(6);
#endif //! NUM_LIGHTS > 6
#if NUM_LIGHTS > 7
	EvaluateLightFunctionPBR(7);
#endif //! NUM_LIGHTS > 7

	// Final combine of ibl and direct lighting.
	lightResult.m_diffuse += (iblLightResult.m_diffuse * iblLightResult.m_diffuseValidity);
	lightResult.m_specular += (iblLightResult.m_specular * iblLightResult.m_specularValidity);

	Scale(lightResult, mat.m_cavity);					// Apply cavity map.
#endif //! USE_LIGHTING

	return lightResult;
}

#endif //! PHYRE_PBR_LIGHTS_FX_H
