/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_PBR_LIGHTS_CGFX_H
#define PHYRE_PBR_LIGHTS_CGFX_H

//////////////////////////////////////////
// Engine-supplied lighting parameters. //
//////////////////////////////////////////

#ifdef USE_LIGHTING

	// Separate lighting structures
	#if NUM_LIGHTS > 0
		LIGHTTYPE_0 Light0 : LIGHT0;
		#ifndef SHADOWTYPE_0
			#define LightShadow0 0.0f
		#else //! SHADOWTYPE_0
			SHADOWTYPE_0 LightShadow0 : LIGHTSHADOW0;
		#endif //! SHADOWTYPE_0
	#endif //! NUM_LIGHTS > 0

	#if NUM_LIGHTS > 1
		LIGHTTYPE_1 Light1 : LIGHT1;
		#ifndef SHADOWTYPE_1
			#define LightShadow1 0.0f
		#else //! SHADOWTYPE_1
			SHADOWTYPE_1 LightShadow1 : LIGHTSHADOW1;
		#endif //! SHADOWTYPE_1
	#endif //! NUM_LIGHTS > 1

	#if NUM_LIGHTS > 2
		LIGHTTYPE_2 Light2 : LIGHT2;
		#ifndef SHADOWTYPE_2
			#define LightShadow2 0.0f
		#else //! SHADOWTYPE_2
			SHADOWTYPE_2 LightShadow2 : LIGHTSHADOW2;
		#endif //! SHADOWTYPE_2
	#endif //! NUM_LIGHTS > 2

	#if NUM_LIGHTS > 3
		LIGHTTYPE_3 Light3 : LIGHT3;
		#ifndef SHADOWTYPE_3
			#define LightShadow3 0.0f
		#else //! SHADOWTYPE_3
			SHADOWTYPE_3 LightShadow3 : LIGHTSHADOW3;
		#endif //! SHADOWTYPE_3
	#endif //! NUM_LIGHTS > 3

	#if NUM_LIGHTS > 4
		LIGHTTYPE_4 Light4 : LIGHT4;
		#ifndef SHADOWTYPE_4
			#define LightShadow4 0.0f
		#else //! SHADOWTYPE_4
			SHADOWTYPE_4 LightShadow4 : LIGHTSHADOW4;
		#endif //! SHADOWTYPE_4
	#endif //! NUM_LIGHTS > 4

	#if NUM_LIGHTS > 5
		LIGHTTYPE_5 Light5 : LIGHT5;
		#ifndef SHADOWTYPE_5
			#define LightShadow5 0.0f
		#else //! SHADOWTYPE_5
			SHADOWTYPE_5 LightShadow5 : LIGHTSHADOW5;
		#endif //! SHADOWTYPE_5
	#endif //! NUM_LIGHTS > 5

	#if NUM_LIGHTS > 6
		LIGHTTYPE_6 Light6 : LIGHT6;
		#ifndef SHADOWTYPE_6
			#define LightShadow6 0.0f
		#else //! SHADOWTYPE_6
			SHADOWTYPE_6 LightShadow6 : LIGHTSHADOW6;
		#endif //! SHADOWTYPE_6
	#endif //! NUM_LIGHTS > 6

	#if NUM_LIGHTS > 7
		LIGHTTYPE_7 Light7 : LIGHT7;
		#ifndef SHADOWTYPE_7
			#define LightShadow7 0.0f
		#else //! SHADOWTYPE_7
			SHADOWTYPE_7 LightShadow7 : LIGHTSHADOW7;
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
		float shad = EvaluateShadowValue(Light##LightIndex, LightShadow##LightIndex, geom.m_worldPosition, viewDepth); \
		PbrLightingResults localLightResult = EvaluateLightPBR(Light##LightIndex, V, shad, mat, geom); \
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

#endif //! PHYRE_PBR_LIGHTS_CGFX_H
