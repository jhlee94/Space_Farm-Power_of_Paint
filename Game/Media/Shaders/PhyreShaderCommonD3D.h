/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_SHADER_COMMON_H
#define PHYRE_SHADER_COMMON_H

#include "PhyreShaderPlatform.h"
#include "PhyreShaderDefsD3D.h"

// Common code which is likely to be used by multiple shader files is placed in here. 

#define UNNORMALIZE_SKININDICES(VAR) /* Nothing - skin indices are supplied using the SKININDICES semantic as 4 uints on D3D11. */

float ClampPlusMinusOneToNonNegative(float value)
{
	return saturate(value);
}

SamplerComparisonState ShadowMapSampler
{
	Filter = Comparison_Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
	ComparisonFunc = Less;
};

// SampleShadowMap
// Sample a shadow map with 1 sample tap. 
float SampleShadowMap(float4 shadowPosition, Texture2D <float> shadowMap)
{
#ifdef DCC_TOOL
	// no shadows in DCC TOOL mode 
	return 1.0f;
#else //! DCC_TOOL
	float4 shadowPositionProjected = shadowPosition / shadowPosition.w;
	float shad = shadowMap.SampleCmpLevelZero(ShadowMapSampler,shadowPositionProjected.xy, shadowPositionProjected.z).x;
	return shad;
#endif //! DCC_TOOL
}


// SampleOrthographicShadowMap
// Sample a shadow map with 1 sample tap and no perspective correction.
float SampleOrthographicShadowMap(float3 shadowPosition, Texture2D <float> shadowMap)
{
#ifdef DCC_TOOL
	// no shadows in DCC TOOL mode 
	return 1.0f;
#else //! DCC_TOOL
//	shadowPosition.y = 1.0f - shadowPosition.y;
	float shad = shadowMap.SampleCmpLevelZero(ShadowMapSampler,shadowPosition.xy, shadowPosition.z).x;
	return shad;
#endif //! DCC_TOOL
}


// SampleShadowMapPCF5
// Sample a shadow map with 5 sample taps. 
float SampleShadowMapPCF5(float4 shadowPosition, Texture2D <float> shadowMap)
{
	float w = shadowPosition.w * 1.0f/1024.0f;
	float h = shadowPosition.w * 1.0f/1024.0f;
	float4 sampleOffsets[5] = 
	{
		float4(0,0,0,0),
		float4(-w,-h,0,0),
		float4(w,-h,0,0),
		float4(-w,h,0,0),
		float4(w,h,0,0)
	};
	const float shadowWeights[5] =
	{
		0.5f,
		0.125f,
		0.125f,
		0.125f,
		0.125f
	};
	float shadowRslt = 0;
	for(int i = 0; i < 5; ++i)
	{
		shadowRslt += SampleShadowMap(shadowPosition + sampleOffsets[i], shadowMap) * shadowWeights[i];
	}
	return shadowRslt;
}

// EvaluateSpotFalloff
// Evaluate the directional attenuation for a spot light.
float EvaluateSpotFalloff(float dp, float cosInnerAngle, float cosOuterAngle)
{
	float a = (cosOuterAngle - dp) / (cosOuterAngle - cosInnerAngle);
	a = saturate(a);
	return a * a;
}

float3 EvaluateStandardNormal(float3 inNormal)
{
	return normalize(inNormal).xyz;
}

float calcDiffuseLightAmt(float3 lightDir, float3 normal)
{
	// Diffuse calcs.
	float diffuseLightAmt = dot(lightDir,normal);

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmt = diffuseLightAmt * 0.5h + 0.5h;
	diffuseLightAmt *= diffuseLightAmt;
#else //! WRAP_DIFFUSE_LIGHTING
	diffuseLightAmt = ClampPlusMinusOneToNonNegative(diffuseLightAmt);
#endif //! WRAP_DIFFUSE_LIGHTING

	return diffuseLightAmt;
}

float calcSpecularLightAmt(float3 normal, float3 lightDir, float3 eyeDirection, float shininess, float specularPower /*, float fresnelPower*/)
{
	// Specular calcs
	float3 floatVec = normalize(eyeDirection + lightDir);
	float nDotH = ClampPlusMinusOneToNonNegative(dot(normal,floatVec));

	//float fresnel = saturate( 1 - pow(abs(dot(normal, eyeDirection)), fresnelPower) );
	float specularLightAmount = ClampPlusMinusOneToNonNegative(pow(nDotH, specularPower)) * shininess; // * fresnel

	specularLightAmount = (dot(normal,lightDir) > 0.0f) ? specularLightAmount : 0.0f;
	
	return specularLightAmount;
}

float calculateAttenuation(float distanceToLight, float4 attenuationProperties)
{
	// attenuationProperties contains:
	// innerRange, outerRange, 1.0f/(outerRange/innerRange), (-innerRange / (outerRange/innerRange)
	float attenValue = ClampPlusMinusOneToNonNegative(distanceToLight * attenuationProperties.z + attenuationProperties.w);
	return 1.0 - (float)attenValue;
}


float calculateAttenuationQuadratic(float distanceToLightSqr, float4 attenuationProperties)
{
	// attenuationProperties contains:
	// innerRange, outerRange, 1.0f/(outerRange/innerRange), (-innerRange / (outerRange/innerRange)
	float rd = (attenuationProperties.y * attenuationProperties.y ) - (attenuationProperties.x*attenuationProperties.x);
	float b = 1.0f / rd;
	float a = attenuationProperties.x*attenuationProperties.x;
	float c = a * b + 1.0f;

#ifdef __psp2__
	float coeff0 = (float)(-b);
	float coeff1 = (float)(c);
	float attenValue = saturate(distanceToLightSqr * coeff0 + coeff1);
#else
	float coeff0 = (float)(-b);
	float coeff1 = (float)(c);
	float attenValuef = saturate(distanceToLightSqr * coeff0 + coeff1);
	float attenValue = (float)attenValuef;
#endif

	return attenValue;
}

#ifdef SPECULAR_ENABLED

float3 EvaluateLighting(float3 normal, float3 lightDir, float3 eyeDirection, float shadowAmount, float3 lightColour, float attenuationResult, float shininess, float specularPower/*, float fresnelPower*/)
{
	// Diffuse and specular calcs.
	float diffuseLightAmt = calcDiffuseLightAmt(lightDir, normal);
	float specularLightAmount = calcSpecularLightAmt(normal, lightDir, eyeDirection, shininess, specularPower/*, fresnelPower*/);

	float3 lightResult = lightColour * (diffuseLightAmt + specularLightAmount);

	return lightResult * shadowAmount * attenuationResult;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Lighting code - could/should be defined in an external .h file. 

float3 EvaluateLight(DirectionalLight light,float3 worldPosition, float3 normal, float3 eyeDirection, float shadowAmount, float shininess, float specularPower/*, float fresnelPower*/)
{
	return EvaluateLighting(normal,light.m_direction,eyeDirection,shadowAmount, light.m_colorIntensity, 1, shininess, specularPower/*, fresnelPower*/);
}
float3 EvaluateLight(PointLight light,float3 worldPosition, float3 normal, float3 eyeDirection, float shadowAmount, float shininess, float specularPower/*, float fresnelPower*/)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	float3 lightDir = offset / sqrt(vecLengthSqr);
	float atten = calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);

	//return 0.8f;//float4(normalize(offset)*0.5f+0.5f,1.0f);

	return EvaluateLighting(normal,lightDir,eyeDirection,shadowAmount, light.m_colorIntensity, atten, shininess, specularPower/*, fresnelPower*/);	
}
float3 EvaluateLight(SpotLight light,float3 worldPosition, float3 normal, float3 eyeDirection, float shadowAmount, float shininess, float specularPower/*, float fresnelPower*/)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	float3 lightDir = offset / sqrt(vecLengthSqr);
	float angle = dot(lightDir, light.m_direction);

	float3 result = float3(0,0,0);
	if(angle > light.m_spotAngles.w)
	{
		float atten = EvaluateSpotFalloff( angle, light.m_spotAngles.z, light.m_spotAngles.w );
		atten *= calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);
		result = EvaluateLighting(normal,lightDir,eyeDirection,shadowAmount, light.m_colorIntensity, atten, shininess, specularPower/*, fresnelPower*/);	
	}
	return result;
}

#else //! SPECULAR_ENABLED

float3 EvaluateLighting(float3 normal, float3 lightDir, float shadowAmount, float3 lightColour, float attenuationResult)
{
	// Diffuse calcs.
	float diffuseLightAmt = calcDiffuseLightAmt(lightDir, normal);

	float3 lightResult = lightColour * diffuseLightAmt;

	return lightResult * shadowAmount * attenuationResult;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Lighting code - could/should be defined in an external .h file. 

float3 EvaluateLight(DirectionalLight light,float3 worldPosition, float3 normal, float shadowAmount)
{	
	return EvaluateLighting(normal, light.m_direction, shadowAmount, light.m_colorIntensity, 1);
}
float3 EvaluateLight(PointLight light,float3 worldPosition, float3 normal, float shadowAmount)
{	
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	float3 lightDir = offset / sqrt(vecLengthSqr);
  	float atten = calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);

	//return 0.3f;//float4(normalize(offset)*0.5f+0.5f,1.0f);

	return EvaluateLighting(normal, lightDir, shadowAmount, light.m_colorIntensity, atten);	
}
float3 EvaluateLight(SpotLight light,float3 worldPosition, float3 normal, float shadowAmount)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	float3 lightDir = offset / sqrt(vecLengthSqr);
	float angle = dot(lightDir, light.m_direction);
	
	float3 result = float3(0,0,0);
	if(angle > light.m_spotAngles.w)
	{
		float atten = EvaluateSpotFalloff( angle, light.m_spotAngles.z, light.m_spotAngles.w );
		atten *= calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);
		result = EvaluateLighting(normal, lightDir, shadowAmount, light.m_colorIntensity, atten);	
	}
	return result;
}

#endif //! SPECULAR_ENABLED


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Shadow code.

// No shadow.
float EvaluateShadow(DirectionalLight light, float dummy, float dummy2, float3 worldPosition, float viewDepth)
{
	return 1;
}
float EvaluateShadow(PointLight light, float dummy, float dummy2, float3 worldPosition, float viewDepth)
{
	return 1;
}
float EvaluateShadow(SpotLight light, float dummy, float dummy2, float3 worldPosition, float viewDepth)
{
	return 1;
}

// PCF shadow.
float EvaluateShadow(SpotLight light, PCFShadowMap shadow, Texture2D <float> shadowMap, float3 worldPosition, float viewDepth)
{
	float4 shadowPosition = mul(float4(worldPosition,1), shadow.m_shadowTransform);
	return SampleShadowMap(shadowPosition, shadowMap);
}

float EvaluateShadow(DirectionalLight light, CascadedShadowMap shadow, Texture2D <float> shadowMap, float3 worldPosition, float viewDepth)
{
	return 1.0f;
}

float EvaluateShadow(DirectionalLight light, CombinedCascadedShadowMap shadow, Texture2D <float> shadowMap, float3 worldPosition, float viewDepth)
{
	// Brute force cascaded split map implementation - sample all the splits, then determine which result to use.

	float3 shadowPosition0 = mul(float4(worldPosition,1), shadow.m_split0Transform).xyz;
	float3 shadowPosition1 = mul(float4(worldPosition,1), shadow.m_split1Transform).xyz;
	float3 shadowPosition2 = mul(float4(worldPosition,1), shadow.m_split2Transform).xyz;
	float3 shadowPosition3 = mul(float4(worldPosition,1), shadow.m_split3Transform).xyz;
	
	float3 shadowPosition = viewDepth < shadow.m_splitDistances.y ? 
							(viewDepth < shadow.m_splitDistances.x ? shadowPosition0 : shadowPosition1)
							:
							(viewDepth < shadow.m_splitDistances.z ? shadowPosition2 : shadowPosition3);

	float result = viewDepth < shadow.m_splitDistances.w ? SampleOrthographicShadowMap(shadowPosition,shadowMap) : 1;
	
	return result;
}

#endif
