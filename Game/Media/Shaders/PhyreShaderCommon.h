/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_SHADER_COMMON_H
#define PHYRE_SHADER_COMMON_H

#include "PhyreShaderDefs.h"

// Common code which is likely to be used by multiple shader files is placed in here. 

#ifdef __psp2__
#define UNNORMALIZE_SKININDICES(VAR) /* Nothing */
#else // __psp2__
#define UNNORMALIZE_SKININDICES(VAR) VAR *= 255.00001
#endif // __psp2__

half ClampPlusMinusOneToNonNegative(half value)
{
#ifdef __psp2__
	return max(value, 0.0h);
#else // __psp2__
	return saturate(value);
#endif // __psp2__
}

float ClampPlusMinusOneToNonNegative(float value)
{
#ifdef __psp2__
	return max(value, 0.0f);
#else // __psp2__
	return saturate(value);
#endif // __psp2__
}

// SampleShadowMap
// Sample a shadow map with 1 sample tap. 
half SampleShadowMap(float4 shadowPosition, sampler2D shadowMapSampler)
{
#ifdef DCC_TOOL
	// no shadows in DCC TOOL mode 
	return 1;
#else
#ifdef WIN32_ATI
	// fetch4 - have to do the compare and average results in shader code
	half4 value = tex2Dproj(shadowMapSampler,shadowPosition) > (shadowPosition.z/shadowPosition.w);
	return dot(value,0.25f);
#else
	return tex2Dproj(shadowMapSampler,shadowPosition).x;
#endif
#endif
}


// SampleOrthographicShadowMap
// Sample a shadow map with 1 sample tap and no perspective correction.
half SampleOrthographicShadowMap(float3 shadowPosition, sampler2D shadowMapSampler)
{
#ifdef DCC_TOOL
	// no shadows in DCC TOOL mode 
	return 1;
#else
#ifdef WIN32_ATI
	// fetch4 - have to do the compare and average results in shader code
	half4 value = tex2D(shadowMapSampler,shadowPosition.xy) > shadowPosition.z;
	return dot(value,0.25f);
#else
#ifdef __psp2__
	return tex2D<float>(shadowMapSampler,shadowPosition.xyz).x;
#else
	return h4tex2D(shadowMapSampler,shadowPosition.xyz).x;
#endif
#endif
#endif
}


// SampleShadowMapPCF5
// Sample a shadow map with 5 sample taps. 
half SampleShadowMapPCF5(float4 shadowPosition, sampler2D shadowMapSampler)
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
	const half shadowWeights[5] =
	{
		0.5f,
		0.125f,
		0.125f,
		0.125f,
		0.125f
	};
	half shadowRslt = 0;
	for(int i = 0; i < 5; ++i)
	{
		shadowRslt += SampleShadowMap(shadowPosition + sampleOffsets[i], shadowMapSampler) * shadowWeights[i];
	}
	return shadowRslt;
}

// EvaluateSpotFalloff
// Evaluate the directional attenuation for a spot light.
half EvaluateSpotFalloff(half dp, half cosInnerAngle, half cosOuterAngle)
{
	half a = (cosOuterAngle - dp) / (cosOuterAngle - cosInnerAngle);
	a = saturate(a);
	return a * a;
}

half3 EvaluateNormalMapNormal(half3 inNormal, float2 inUv, half3 inTangent, uniform sampler2D normalMapSampler)
{
	// Sample normal map
#ifdef __psp2__
	half3 normalMapValue = tex2D<half4>(normalMapSampler, inUv).xyz;
	normalMapValue = normalMapValue * 2.0 - 1.0;
	half3 basis1 = cross(inTangent, inNormal);
	return normalize( (normalMapValue.x * inTangent) + (normalMapValue.y * basis1) + (normalMapValue.z * inNormal) );	
#else
	half4 normalMapValue = h4tex2D(normalMapSampler, inUv);
	half3 normalMapNormal = normalize(normalMapValue.xyz * 2.0h - 1.0h);

	// Evaluate tangent basis
	half3 basis0 = normalize(inTangent);
	half3 basis2 = normalize(inNormal);
	half3 basis1 = cross(basis0, basis2);

	half3 normal = (normalMapNormal.x * basis0) + (normalMapNormal.y * basis1) + (normalMapNormal.z * basis2);	
	return normal;
#endif
}


half3 EvaluateParallaxMapNormal(half3 inNormal, float2 inUv, half3 inTangent, uniform sampler2D normalMapSampler, float3 eyeDir)
{
	// Evaluate tangent basis
	half3 binormal = cross(inTangent, inNormal);
	half3 basis0 = normalize(inTangent);
	half3 basis1 = normalize(binormal);
	half3 basis2 = normalize(inNormal);

	// Get the view vector in tangent space
	float3 viewVecTangentSpace;
	viewVecTangentSpace.x = dot(eyeDir,basis0);
	viewVecTangentSpace.y = dot(eyeDir,basis1);
	viewVecTangentSpace.z = dot(eyeDir,basis2);	

	half3 texCoord = half3(inUv,1);
	
	// Evaluate parallax mapping.
	const float parallax = 0.025f;
	float height = tex2D(normalMapSampler, texCoord.xy).w ;
	float offset = parallax * (2.0f * height - 1.0f) ;
	float2 parallaxTexCoord = texCoord.xy + offset * viewVecTangentSpace.xy;

	// Sample normal map
	half4 normalMapValue = h4tex2D(normalMapSampler, parallaxTexCoord);
	half3 normalMapNormal = normalize(normalMapValue.xyz * 2.0h - 1.0h);

	half3 normal = (normalMapNormal.x * basis0) + (normalMapNormal.y * basis1) + (normalMapNormal.z * basis2);
	return normal;
}

half3 EvaluateStandardNormal(half3 inNormal)
{
	return normalize(inNormal).xyz;
}

half calcDiffuseLightAmt(half3 lightDir, half3 normal)
{
	// Diffuse calcs.
	half diffuseLightAmt = dot(lightDir,normal);

#ifdef WRAP_DIFFUSE_LIGHTING
	diffuseLightAmt = diffuseLightAmt * 0.5h + 0.5h;
	diffuseLightAmt *= diffuseLightAmt;
#else //! WRAP_DIFFUSE_LIGHTING
	diffuseLightAmt = ClampPlusMinusOneToNonNegative(diffuseLightAmt);
#endif //! WRAP_DIFFUSE_LIGHTING

	return diffuseLightAmt;
}

half calcSpecularLightAmt(half3 normal, half3 lightDir, half3 eyeDirection, half shininess, half specularPower /*, half fresnelPower*/)
{
	// Specular calcs
	half3 halfVec = normalize(eyeDirection + lightDir);
	half nDotH = ClampPlusMinusOneToNonNegative(dot(normal,halfVec));

	//half fresnel = saturate( 1 - pow(abs(dot(normal, eyeDirection)), fresnelPower) );
	half specularLightAmount = ClampPlusMinusOneToNonNegative(pow(nDotH, specularPower)) * shininess; // * fresnel

	specularLightAmount = (dot(normal,lightDir) > 0.0f) ? specularLightAmount : 0.0f;
	
	return specularLightAmount;
}

half calculateAttenuation(float distanceToLight, float4 attenuationProperties)
{
	// attenuationProperties contains:
	// innerRange, outerRange, 1.0f/(outerRange/innerRange), (-innerRange / (outerRange/innerRange)
	float attenValue = ClampPlusMinusOneToNonNegative(distanceToLight * attenuationProperties.z + attenuationProperties.w);
	return 1.0 - (half)attenValue;
}


half calculateAttenuationQuadratic(half distanceToLightSqr, float4 attenuationProperties)
{
	// attenuationProperties contains:
	// innerRange, outerRange, 1.0f/(outerRange/innerRange), (-innerRange / (outerRange/innerRange)
	float rd = (attenuationProperties.y * attenuationProperties.y ) - (attenuationProperties.x*attenuationProperties.x);
	float b = 1.0f / rd;
	float a = attenuationProperties.x*attenuationProperties.x;
	float c = a * b + 1.0f;

#ifdef __psp2__
	half coeff0 = (half)(-b);
	half coeff1 = (half)(c);
	half attenValue = saturate(distanceToLightSqr * coeff0 + coeff1);
#else
	float coeff0 = (half)(-b);
	float coeff1 = (half)(c);
	float attenValuef = saturate(distanceToLightSqr * coeff0 + coeff1);
	half attenValue = (half)attenValuef;
#endif

	return attenValue;
}




#ifdef SPECULAR_ENABLED

half3 EvaluateLighting(half3 normal, half3 lightDir, half3 eyeDirection, half shadowAmount, half3 lightColour, half attenuationResult, half shininess, half specularPower/*, half fresnelPower*/)
{
	// Diffuse and specular calcs.
	half diffuseLightAmt = calcDiffuseLightAmt(lightDir, normal);
	half specularLightAmount = calcSpecularLightAmt(normal, lightDir, eyeDirection, shininess, specularPower/*, fresnelPower*/);

	half3 lightResult = lightColour * (diffuseLightAmt + specularLightAmount);

	return lightResult * shadowAmount * attenuationResult;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Lighting code - could/should be defined in an external .h file. 

half3 EvaluateLight(DirectionalLight light,float3 worldPosition, half3 normal, half3 eyeDirection, half shadowAmount, half shininess, half specularPower/*, half fresnelPower*/)
{
	return EvaluateLighting(normal,light.m_direction,eyeDirection,shadowAmount, light.m_colorIntensity, 1, shininess, specularPower/*, fresnelPower*/);
}
half3 EvaluateLight(PointLight light,float3 worldPosition, half3 normal, half3 eyeDirection, half shadowAmount, half shininess, half specularPower/*, half fresnelPower*/)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	half3 lightDir = offset / sqrt(vecLengthSqr);
	half atten = calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);
	return EvaluateLighting(normal,lightDir,eyeDirection,shadowAmount, light.m_colorIntensity, atten, shininess, specularPower/*, fresnelPower*/);	
}
half3 EvaluateLight(SpotLight light,float3 worldPosition, half3 normal, half3 eyeDirection, half shadowAmount, half shininess, half specularPower/*, half fresnelPower*/)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	half3 lightDir = offset / sqrt(vecLengthSqr);
	half angle = dot(lightDir, light.m_direction);
	if(angle > light.m_spotAngles.w)
	{
		half atten = EvaluateSpotFalloff( angle, light.m_spotAngles.z, light.m_spotAngles.w );
		atten *= calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);
		return EvaluateLighting(normal,lightDir,eyeDirection,shadowAmount, light.m_colorIntensity, atten, shininess, specularPower/*, fresnelPower*/);	
	}
	return 0;
}

#else //! SPECULAR_ENABLED

half3 EvaluateLighting(half3 normal, half3 lightDir, half shadowAmount, half3 lightColour, half attenuationResult)
{
	// Diffuse calcs.
	half diffuseLightAmt = calcDiffuseLightAmt(lightDir, normal);

	half3 lightResult = lightColour * diffuseLightAmt;

	return lightResult * shadowAmount * attenuationResult;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Lighting code - could/should be defined in an external .h file. 

half3 EvaluateLight(DirectionalLight light,float3 worldPosition, half3 normal, half shadowAmount)
{
	return EvaluateLighting(normal, light.m_direction, shadowAmount, light.m_colorIntensity, 1);
}
half3 EvaluateLight(PointLight light,float3 worldPosition, half3 normal, half shadowAmount)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	half3 lightDir = offset / sqrt(vecLengthSqr);
  	half atten = calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);

	return EvaluateLighting(normal, lightDir, shadowAmount, light.m_colorIntensity, atten);	
}
half3 EvaluateLight(SpotLight light,float3 worldPosition, half3 normal, half shadowAmount)
{
	float3 offset = light.m_position - worldPosition;
	float vecLengthSqr = dot(offset, offset);
  	half3 lightDir = offset / sqrt(vecLengthSqr);
	half angle = dot(lightDir, light.m_direction);

	if(angle > light.m_spotAngles.w)
	{
		half atten = EvaluateSpotFalloff( angle, light.m_spotAngles.z, light.m_spotAngles.w );
		atten *= calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);
		return EvaluateLighting(normal, lightDir, shadowAmount, light.m_colorIntensity, atten);	
	}
	return 0;
}

#endif //! SPECULAR_ENABLED


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Shadow code.

// No shadow.
half EvaluateShadow(DirectionalLight light, float dummy, float3 worldPosition, float viewDepth)
{
	return 1;
}
half EvaluateShadow(PointLight light, float dummy, float3 worldPosition, float viewDepth)
{
	return 1;
}
half EvaluateShadow(SpotLight light, float dummy, float3 worldPosition, float viewDepth)
{
	return 1;
}

// PCF shadow.
half EvaluateShadow(SpotLight light, PCFShadowMap shadow, float3 worldPosition, float viewDepth)
{
	float4 shadowPosition = mul(shadow.m_shadowTransform,float4(worldPosition,1));
	return SampleShadowMap(shadowPosition,shadow.m_shadowMap);
}

#ifdef __psp2__
short EvaluateSplitIndex(float viewDepth, float4 splitDistances)
{
	float4 v0 = viewDepth > splitDistances ? 1.0 : 0.0;
	return (short)dot(v0, 1.0);
}
#endif

half EvaluateShadow(DirectionalLight light, CascadedShadowMap shadow, float3 worldPosition, float viewDepth)
{
#ifdef __psp2__
	// Branchy implementation - don't sample unnecessary shadow maps, bandwidth is precious.
	half split = 1;
	short splitIndex = EvaluateSplitIndex(viewDepth, shadow.m_splitDistances);

	float3 shadowPosition = mul(shadow.m_splitTransformArray[splitIndex],float4(worldPosition, 1)).xyz;

	if(viewDepth < shadow.m_splitDistances.w)
	{
		if (splitIndex == 0)
			split = SampleOrthographicShadowMap(shadowPosition, shadow.m_split0ShadowMap);
		else if (splitIndex == 1)
			split = SampleOrthographicShadowMap(shadowPosition, shadow.m_split1ShadowMap);
		else if (splitIndex == 2)
			split = SampleOrthographicShadowMap(shadowPosition, shadow.m_split2ShadowMap);
		else
			split = SampleOrthographicShadowMap(shadowPosition, shadow.m_split3ShadowMap);
	}

	return split;
#else //! __psp2__
	// Brute force cascaded split map implementation - sample all the splits, then determine which result to use.

	float3 shadowPosition0 = mul(shadow.m_split0Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition1 = mul(shadow.m_split1Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition2 = mul(shadow.m_split2Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition3 = mul(shadow.m_split3Transform,float4(worldPosition,1)).xyz;

	half split0 = SampleOrthographicShadowMap(shadowPosition0,shadow.m_split0ShadowMap);
	half split1 = SampleOrthographicShadowMap(shadowPosition1,shadow.m_split1ShadowMap);
	half split2 = SampleOrthographicShadowMap(shadowPosition2,shadow.m_split2ShadowMap);
	half split3 = SampleOrthographicShadowMap(shadowPosition3,shadow.m_split3ShadowMap);

	if(viewDepth < shadow.m_splitDistances.x)
		return split0;
	else if(viewDepth < shadow.m_splitDistances.y)
		return split1;
	else if(viewDepth < shadow.m_splitDistances.z)
		return split2;
	else if(viewDepth < shadow.m_splitDistances.w)
		return split3;
	else 
		return 1;
#endif //! __psp2__
}

#if !defined(__SCE_CGC__) && !defined(__psp2__)
arbfp1 half EvaluateShadow(DirectionalLight light, CascadedShadowMap shadow, float3 worldPosition, float viewDepth)
{
	// Brute force cascaded split map implementation - sample all the splits, then determine which result to use.

	float3 shadowPosition0 = mul(shadow.m_split0Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition1 = mul(shadow.m_split1Transform,float4(worldPosition,1)).xyz;

	half split0 = SampleOrthographicShadowMap(shadowPosition0,shadow.m_split0ShadowMap);
	half split1 = SampleOrthographicShadowMap(shadowPosition1,shadow.m_split1ShadowMap);

	if(viewDepth < shadow.m_splitDistances.x)
		return split0;
	else if(viewDepth < shadow.m_splitDistances.y)
		return split1;
	else 
		return 1;
}
#endif // !defined(__SCE_CGC__) && !defined(__psp2__)

half EvaluateShadow(DirectionalLight light, CombinedCascadedShadowMap shadow, float3 worldPosition, float viewDepth)
{
#ifdef __psp2__
	// Choose the right split transform from the split palette. 
	short splitIndex = EvaluateSplitIndex(viewDepth, shadow.m_splitDistances);
	float3 shadowPosition = mul(shadow.m_splitTransformArray[splitIndex],float4(worldPosition, 1)).xyz;
	half result = SampleOrthographicShadowMap(shadowPosition, shadow.m_shadowMap);

	return result;
#else //! __psp2__
	// Brute force cascaded split map implementation - sample all the splits, then determine which result to use.

	float3 shadowPosition0 = mul(shadow.m_split0Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition1 = mul(shadow.m_split1Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition2 = mul(shadow.m_split2Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition3 = mul(shadow.m_split3Transform,float4(worldPosition,1)).xyz;

	float3 shadowPosition = viewDepth < shadow.m_splitDistances.y ? 
		(viewDepth < shadow.m_splitDistances.x ? shadowPosition0 : shadowPosition1)
		:
		(viewDepth < shadow.m_splitDistances.z ? shadowPosition2 : shadowPosition3);

	half result = viewDepth < shadow.m_splitDistances.w ? SampleOrthographicShadowMap(shadowPosition,shadow.m_shadowMap) : 1;

	return result;
#endif //! __psp2__
}

#if !defined(__SCE_CGC__) && !defined(__psp2__)
arbfp1 half EvaluateShadow(DirectionalLight light, CombinedCascadedShadowMap shadow, float3 worldPosition, float viewDepth)
{
	// Brute force cascaded split map implementation - sample all the splits, then determine which result to use.

	float3 shadowPosition0 = mul(shadow.m_split0Transform,float4(worldPosition,1)).xyz;
	float3 shadowPosition1 = mul(shadow.m_split1Transform,float4(worldPosition,1)).xyz;

	float3 shadowPosition = (viewDepth < shadow.m_splitDistances.x ? shadowPosition0 : shadowPosition1);

	half result = viewDepth < shadow.m_splitDistances.y ? SampleOrthographicShadowMap(shadowPosition,shadow.m_shadowMap) : 1;

	return result;
}
#endif // !defined(__SCE_CGC__) && !defined(__psp2__)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Skinning 

// Evaluate skin for position, normal and tangent, for 4 bone weights.
void EvaluateSkinPositionNormalTangent4Bones( inout float3 position, inout float3 normal, inout float3 tangent, float4 weights, int4 boneIndices, uniform float3x4 skinTransforms[] )
{
	int indexArray[4] = {boneIndices.x,boneIndices.y,boneIndices.z,boneIndices.w};

	float4 inPosition = float4(position,1);
	float4 inNormal = float4(normal,0);
	float4 inTangent = float4(tangent,0);
	
 	position = 
		mul(skinTransforms[indexArray[0]], inPosition).xyz * weights.x
	+	mul(skinTransforms[indexArray[1]], inPosition).xyz * weights.y
	+	mul(skinTransforms[indexArray[2]], inPosition).xyz * weights.z
	+	mul(skinTransforms[indexArray[3]], inPosition).xyz * weights.w;
	
	normal = 
		mul(skinTransforms[indexArray[0]], inNormal).xyz * weights.x
	+	mul(skinTransforms[indexArray[1]], inNormal).xyz * weights.y
	+	mul(skinTransforms[indexArray[2]], inNormal).xyz * weights.z
	+	mul(skinTransforms[indexArray[3]], inNormal).xyz * weights.w;

	tangent = 
		mul(skinTransforms[indexArray[0]], inTangent).xyz * weights.x
	+	mul(skinTransforms[indexArray[1]], inTangent).xyz * weights.y
	+	mul(skinTransforms[indexArray[2]], inTangent).xyz * weights.z
	+	mul(skinTransforms[indexArray[3]], inTangent).xyz * weights.w;
		
}

void EvaluateSkinPositionNormal4Bones( inout float3 position, inout float3 normal, float4 weights, int4 boneIndices, uniform float3x4 skinTransforms[] )
{
	int indexArray[4] = {boneIndices.x,boneIndices.y,boneIndices.z,boneIndices.w};

	float4 inPosition = float4(position,1);
	float4 inNormal = float4(normal,0);
	
 	position = 
		mul(skinTransforms[indexArray[0]], inPosition).xyz * weights.x
	+	mul(skinTransforms[indexArray[1]], inPosition).xyz * weights.y
	+	mul(skinTransforms[indexArray[2]], inPosition).xyz * weights.z
	+	mul(skinTransforms[indexArray[3]], inPosition).xyz * weights.w;
	
	normal = 
		mul(skinTransforms[indexArray[0]], inNormal).xyz * weights.x
	+	mul(skinTransforms[indexArray[1]], inNormal).xyz * weights.y
	+	mul(skinTransforms[indexArray[2]], inNormal).xyz * weights.z
	+	mul(skinTransforms[indexArray[3]], inNormal).xyz * weights.w;
}

void EvaluateSkinPosition1Bone( inout float3 position, float4 weights, int4 boneIndices, uniform float3x4 skinTransforms[] )
{
	int index = boneIndices.x;

	float4 inPosition = float4(position,1.0);
	position = mul(skinTransforms[index], inPosition).xyz;		
}

void EvaluateSkinPosition2Bones( inout float3 position, float4 weights, int4 boneIndices, uniform float3x4 skinTransforms[] )
{
	int indexArray[2] = {boneIndices.x,boneIndices.y};

	float4 inPosition = float4(position,1);
	float scale = 1.0f / (weights.x + weights.y);
 	position = 
		mul(skinTransforms[indexArray[0]], inPosition).xyz * (weights.x * scale)
	+	mul(skinTransforms[indexArray[1]], inPosition).xyz * (weights.y * scale);
}

void EvaluateSkinPosition3Bones( inout float3 position, float4 weights, int4 boneIndices, uniform float3x4 skinTransforms[] )
{
	int indexArray[3] = {boneIndices.x,boneIndices.y,boneIndices.z};

	float4 inPosition = float4(position,1);
	float scale = 1.0f / (weights.x + weights.y + weights.z);
 	position = 
		mul(skinTransforms[indexArray[0]], inPosition).xyz * (weights.x * scale)
	+	mul(skinTransforms[indexArray[1]], inPosition).xyz * (weights.y * scale)
	+	mul(skinTransforms[indexArray[2]], inPosition).xyz * (weights.z * scale);
}

void EvaluateSkinPosition4Bones( inout float3 position, float4 weights, int4 boneIndices, uniform float3x4 skinTransforms[] )
{
	int indexArray[4] = {boneIndices.x,boneIndices.y,boneIndices.z,boneIndices.w};

	float4 inPosition = float4(position,1);
	
 	position = 
		mul(skinTransforms[indexArray[0]], inPosition).xyz * weights.x
	+	mul(skinTransforms[indexArray[1]], inPosition).xyz * weights.y
	+	mul(skinTransforms[indexArray[2]], inPosition).xyz * weights.z
	+	mul(skinTransforms[indexArray[3]], inPosition).xyz * weights.w;
}


#endif