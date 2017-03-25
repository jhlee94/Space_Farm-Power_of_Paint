/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_PBR_SHARED_CGFX_H
#define PHYRE_PBR_SHARED_CGFX_H

// The pre-integrated DFG terms for the fast evaluation of IBL BRDFs.
sampler2D PbrPreintegratedDFG : PbrPreintegratedDFG;

// Description:
// Get the GGX_D normalization value for the specified roughness.
// Arguments:
// roughness - The roughness for which to get the GGX_D normalization value.
// Returns:
// The GGX_D normalization value for the specified roughness.
float GGX_D_Normalization(float roughness)
{
	return tex2D(PbrPreintegratedDFG, float2(0, roughness)).w;
}

///////////////////////////
// LTC Sampling methods. //
///////////////////////////

sampler2D PbrLtcAmpTex : PbrLtcAmpTex;			// The LTC Amplitude texture.
sampler2D PbrLtcMatTex : PbrLtcMatTex;			// The LTC matrix texture.

// Description:
// Sample the Linear Transformed Cosine amplitude texture for the specified coordinates.
// Arguments:
// coordinate - The texture coordinate for which to sample the texture.
// Returns:
// The LTC amplitude texture sample.
float4 LTC_SampleAmp(float2 coord)
{
	return tex2D(PbrLtcAmpTex, coord);
}

// Description:
// Sample the Linear Transformed Cosine matrix texture for the specified coordinates.
// Arguments:
// coordinate - The texture coordinate for which to sample the texture.
// Returns:
// The LTC matrix texture sample.
float4 LTC_SampleMat(float2 coord)
{
	return tex2D(PbrLtcMatTex, coord);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Image based lighting code - should be local to cgfx/hlsl file due to platform specific texture lookup. //
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Description:
// Evaluate image based specular lighting at a point on the surface. This requires a suitably pre-convolved light probe to be supplied as a cubemap.
// Arguments:
// NdotV - The cosine of the angle between the normal and view vector.
// localR - The reflection vector.
// linearRoughness - The surface linear roughness.
// mat - The material properties at the surface point.
// ibl - The pre-convolved light probe.
// iblRes - The resolution and mipmap count of the ibl sampler.
// Returns:
// The specular color at the surface point.
static float4 EvaluateIBLSpecular(float NdotV, float3 R, float linearRoughness, PbrMaterialProperties mat, samplerCUBE ibl, float2 iblRes)
{
	float roughness = linearRoughness*linearRoughness;

	float width = iblRes.x;
	int mipCount = (int) (iblRes.y + 0.5f);

	// Rebuild the function
	// L . D. ( f0.Gv.(1-Fc) + Gv.Fc ) , cosTheta / (4 . NdotL . NdotV)
	NdotV = max(NdotV, 0.5f/width);

	// Bias the roughness for the specular map lookup by the perpendicularity of view vector and surface normal.
	// This sharpens up the specular for grazing angles - view dependent roughness.
	float viewDependentLinearRoughness = lerp(linearRoughness, linearRoughness * abs(NdotV), mat.m_viewDependentRoughnessStrength);

	float mipLevel = linearRoughnessToMipLevel(viewDependentLinearRoughness, mipCount);
	float4 preLD = texCUBElod(ibl, float4(R, mipLevel));

	// Sample pre-integration DFG
	// Fc = (1-H.L)^5
	// PbrPreintegratedDFG.r = Gv.(1-Fc)
	// PbrPreintegratedDFG.g = Gv.Fc
	float2 preDFG = tex2D(PbrPreintegratedDFG, float2(NdotV, roughness)).xy;

	// LD . (f0.Gv.(1-Fc) + Gv.Fc.f90 )
	float3 f0 = mat.m_specularColor;
	float3 f90 = float3(1,1,1);

	float3 result = preLD.xyz * (f0 * preDFG.x + f90 * preDFG.y);

	return float4(result, preLD.w);
}

// Description:
// Evaluate image based specular lighting at a point on the surface. This requires a suitably pre-convolved light probe to be supplied as a cubemap.
// Arguments:
// N - The surface normal.
// V - The view vector.
// linearRoughness - The surface linear roughness.
// mat - The material properties at the surface point.
// ibl - The pre-convolved light probe.
// iblRes - The resolution and mipmap count of the ibl sampler.
// Returns:
// The specular color at the surface point.
static float4 EvaluateIBLSpecular(float3 N, float3 V, float linearRoughness, PbrMaterialProperties mat, samplerCUBE ibl, float2 iblRes)
{
	float NdotV = dot(N, V);
	float3 R = Reflection(N, V);

	return EvaluateIBLSpecular(NdotV, R, linearRoughness, mat, ibl, iblRes);
}

// Description:
// Evaluate image based diffuse lighting at a point on the surface. This requires a suitably pre-convolved light probe to be supplied as a cubemap.
// Arguments:
// N - The surface normal.
// V - The view vector.
// linearRoughness - The surface roughness.
// ibl - The pre-convolved light probe.
// Returns:
// The diffuse color at the surface point.
static float4 EvaluateIBLDiffuse(float3 N, float3 V, float linearRoughness, samplerCUBE ibl)
{
	float roughness = linearRoughness*linearRoughness;
	float NdotV = dot(N, V);
	float4 diffuseLighting = texCUBElod(ibl, (float4(N, 0)));

	float diffF = tex2D(PbrPreintegratedDFG, float2(NdotV, roughness)).z;

	return float4(diffuseLighting.xyz * diffF, diffuseLighting.w);
}

// Description:
// Evaluate image based lighting at a point on the surface.
// Arguments:
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// specIbl - The pre-convolved specular light probe.
// specIblRes - The resolution and mipmap count of the specular ibl sampler.
// diffIbl - The pre-convolved diffuse light probe.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingGlobalIblPBR(float3 V, PbrMaterialProperties mat, PbrGeomProperties geom, samplerCUBE specIbl, float2 specIblRes, samplerCUBE diffIbl)
{
	float linearRoughness = mat.m_linearRoughness;
	float3 N = geom.m_surfaceNormal;

	PbrLightingResults lightResult;

	lightResult.m_specular = EvaluateIBLSpecular(N, V, linearRoughness, mat, specIbl, specIblRes).xyz;
	lightResult.m_diffuse = IsMetal(mat.m_metallicity) ? float3(0,0,0) : EvaluateIBLDiffuse(N, V, linearRoughness, diffIbl).xyz;
	lightResult.m_specularValidity = 1.0f;
	lightResult.m_diffuseValidity = 1.0f;

	return lightResult;
}

// Description:
// Evaluate image based lighting at a point on the surface.
// Arguments:
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// spherePos - The centre of the IBL sphere.
// sphereRadius - The radius of the IBL sphere.
// specIbl - The pre-convolved specular light probe.
// specIblRes - The resolution and mipmap count of the specular ibl sampler.
// diffIbl - The pre-convolved diffuse light probe.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingLocalSphereIblPBR(float3 V, PbrMaterialProperties mat, PbrGeomProperties geom, float3 spherePos, float sphereRadius, samplerCUBE specIbl, float2 specIblRes, samplerCUBE diffIbl)
{
	// NOTE : We probably need a better diffuse solution than convolved partially populated local light probes.

	PbrLightingResults lightResult;

	float3 N = geom.m_surfaceNormal;
	float3 R = Reflection(N, V);						// Calculate reflection vector.

	float2 intersections;
	if (sphereRayIntersect(intersections, geom.m_worldPosition - spherePos, R, sphereRadius))
	{
		float linearRoughness = mat.m_linearRoughness;
		float NdotV = dot(N, V);

		// Compute the local reflection direction, based on sphere centre and intersection point.
		float3 localR = normalize((geom.m_worldPosition + intersections.y * R) - spherePos);

		float distanceReceiverIntersection = intersections.y;		// Distance between receiving pixel and point on the intersected sphere.
		float distanceSphereCenterIntersection = sphereRadius;		// Distance between the sphere center and point on the intersected sphere (was length(localR)).

		// Adjust the roughness based on proximity of the light probe sphere.
		float localLinearRoughness = evaluateDistanceBasedRoughness(linearRoughness, distanceReceiverIntersection, distanceSphereCenterIntersection);

		// Specular sampling. Limit artifacts introduced with high roughness.
		localR = lerp(localR, R, linearRoughness);
		float4 specularResult = EvaluateIBLSpecular(NdotV, localR, localLinearRoughness, mat, specIbl, specIblRes);

		float4 diffuseResult = IsMetal(mat.m_metallicity) ? float4(0,0,0,0) : EvaluateIBLDiffuse(N, V, localLinearRoughness, diffIbl);

		float fadeDistance = sphereRadius * 0.05f;	// Arbitrary : Fade over last 5% of sphere radius.

		// Fade off the lighting as the lit pixel approaches the boundary of the sphere.
		float localDistance = length(geom.m_worldPosition - spherePos);
		float alpha = saturate((sphereRadius - localDistance) / max(fadeDistance, 0.0001f));
		float alphaAttenuation = smoothstep(0, 1, alpha);

		lightResult.m_specular = specularResult.xyz;
		lightResult.m_diffuse = diffuseResult.xyz;
		lightResult.m_specularValidity = specularResult.w * alphaAttenuation;
		lightResult.m_diffuseValidity = diffuseResult.w * alphaAttenuation;
	}
	else
	{
		ResetInvalid(lightResult);
	}

	return lightResult;
}

// Description:
// Evaluate image based lighting at a point on the surface.
// Arguments:
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// boxPos - The centre of the IBL box.
// boxHalfWidth - The half width of the IBL box.
// boxHalfHeight - The half height of the IBL box.
// boxHalfDepth - The half depth of the IBL box.
// specIbl - The pre-convolved specular light probe.
// specIblRes - The resolution and mipmap count of the specular ibl sampler.
// diffIbl - The pre-convolved diffuse light probe.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingLocalBoxIblPBR(float3 V, PbrMaterialProperties mat, PbrGeomProperties geom, float3 boxPos, float3 boxHalfWidth, float3 boxHalfHeight, float3 boxHalfDepth, samplerCUBE specIbl, float2 specIblRes, samplerCUBE diffIbl)
{
	PbrLightingResults lightResult;

	float3 N = geom.m_surfaceNormal;
	float3 R = Reflection(N, V);						// Calculate reflection vector.

	float2 intersections;
	if (obbRayIntersect(intersections, geom.m_worldPosition - boxPos, R, boxHalfWidth, boxHalfHeight, boxHalfDepth))
	{
		float linearRoughness = mat.m_linearRoughness;
		float NdotV = dot(N, V);

		// Compute the local reflection direction, based on sphere centre and intersection point.
		float3 localR = (geom.m_worldPosition + intersections.y * R) - boxPos;

		float distanceReceiverIntersection = intersections.y;		// Distance between receiving pixel and point on the intersected sphere.
		float distanceBoxCenterIntersection = length(localR);		// Distance between the box center and point on the intersected box.

		localR = normalize(localR);

		// Adjust the roughness based on proximity of the light probe sphere.
		float localLinearRoughness = evaluateDistanceBasedRoughness(linearRoughness, distanceReceiverIntersection, distanceBoxCenterIntersection);

		// Specular sampling. Limit artifacts introduced with high roughness.
		localR = lerp(localR, R, linearRoughness);
		float4 specularResult = EvaluateIBLSpecular(NdotV, localR, localLinearRoughness, mat, specIbl, specIblRes);

		float4 diffuseResult = IsMetal(mat.m_metallicity) ? float4(0,0,0,0) : EvaluateIBLDiffuse(N, V, localLinearRoughness, diffIbl);

#if 0
		float fadeDistance = sphereRadius * 0.05f;	// Arbitrary : Fade over last 5% of sphere radius.

		// Fade off the lighting as the lit pixel approaches the boundary of the sphere.
		float localDistance = length(geom.m_worldPosition - spherePos);
		float alpha = saturate((sphereRadius - localDistance) / max(fadeDistance, 0.0001f));
		float alphaAttenuation = smoothstep(0, 1, alpha);
#else
		// TODO : Write box boundary falloff here.
		float alphaAttenuation = 1.0f;
#endif

		lightResult.m_specular = specularResult.xyz;
		lightResult.m_diffuse = diffuseResult.xyz;
		lightResult.m_specularValidity = specularResult.w * alphaAttenuation;
		lightResult.m_diffuseValidity = diffuseResult.w * alphaAttenuation;
	}
	else
	{
		ResetInvalid(lightResult);
	}

	return lightResult;
}

///////////////////////////////////////////////////
// Lighting functions for different light types. //
///////////////////////////////////////////////////

#ifdef EXTENDED_LIGHT_TYPES
// Description:
// Evaluate the lighting for a global light probe at the surface point.
// Arguments:
// light - The global light probe with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(GlobalLightProbe light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	PbrLightingResults lightResult = EvaluateLightingGlobalIblPBR(V, mat, geom, light.m_lightSpecularMap, light.m_lightSpecularMapRes, light.m_lightDiffuseMap);

	Scale(lightResult, shadowAmount);	// Shadowing.

	return lightResult;
}

// Description:
// Evaluate the lighting for a local light probe at the surface point.
// Arguments:
// light - The local light probe with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(LocalLightProbe light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	PbrLightingResults lightResult;

	// Select correct local IBL shape.
	if (light.m_radius > 0)
		lightResult = EvaluateLightingLocalSphereIblPBR(V, mat, geom, light.m_position, light.m_radius, light.m_lightSpecularMap, light.m_lightSpecularMapRes, light.m_lightDiffuseMap);
	else
		lightResult = EvaluateLightingLocalBoxIblPBR(V, mat, geom, light.m_position, light.m_halfWidth, light.m_halfHeight, light.m_halfDepth, light.m_lightSpecularMap, light.m_lightSpecularMapRes, light.m_lightDiffuseMap);

	Scale(lightResult, shadowAmount);	// Shadowing.

	return lightResult;
}
#endif //! EXTENDED_LIGHT_TYPES

////////////////////////////
// General shader helpers //
////////////////////////////

// Description:
// Copy the texture coordinate as part of vertex shader processing, performing any coordinate conversions required by the target platform.
// Arguments:
// uv - The input texture coordinate.
// Returns:
// The copied texture coordinate with any coordinate conversion applied.
static float2 CopyUV(float2 uv)
{
	return uv;
}

// Description:
// The skinned and unskinned vertex input.
struct VIn
{
#ifdef SKINNING_ENABLED
	float3	SkinnableVertex		: POSITION;
	uint4	SkinIndices			: COLOR0;
	float4	SkinWeights			: TEXCOORD2;
#else //! SKINNING_ENABLED
	float3	Position			: POSITION;
#endif //! SKINNING_ENABLED
};

// Description:
// The skinned and unskinned vertex input with normals.
struct VNIn
{
#ifdef SKINNING_ENABLED
	float3	SkinnableVertex		: POSITION;
	float3	SkinnableNormal		: NORMAL; 	
	uint4	SkinIndices			: COLOR0;
	float4	SkinWeights			: TEXCOORD2;
#else //! SKINNING_ENABLED
	float3	Position			: POSITION;
	float3	Normal				: NORMAL; 	
#endif //! SKINNING_ENABLED
};

// Description:
// The skinned and unskinned vertex input with normals and tangents.
struct VNTIn
{
#ifdef SKINNING_ENABLED
	float3	SkinnableVertex		: POSITION;
	float3	SkinnableNormal		: NORMAL; 	
	float3	SkinnableTangent	: TEXCOORD2;
	uint4	SkinIndices			: COLOR0;
	float4	SkinWeights			: TEXCOORD3;
#else //! SKINNING_ENABLED
	float3	Position			: POSITION;
	float3	Normal				: NORMAL; 	
	float3	Tangent				: TEXCOORD2;
#endif //! SKINNING_ENABLED
};

// Description:
// The vertex output.
struct VOut
{
	float4	Position			: POSITION;	
};

// Description:
// The vertex output with normals.
struct VNOut
{
	float4	Position			: POSITION;	
	float4	WorldPositionDepth	: TEXCOORD2;
	float3	Normal				: TEXCOORD3;
};

// Description:
// The vertex output with normals and tangents.
struct VNTOut
{
	float4	Position			: POSITION;	
	float4	WorldPositionDepth	: TEXCOORD2;
	float3	Normal				: TEXCOORD3;
	float3	Tangent				: TEXCOORD4;
};

// Description:
// Structure containing the instancing transformation for a geometry instance.
struct InstancingInput
{
	float4	InstanceTransform0	: ATTR13;
	float4	InstanceTransform1	: ATTR14;
	float4	InstanceTransform2	: ATTR15;
};

#ifdef SKINNING_ENABLED
// Description:
// Evaluate the skinned vertex with positions, normals and tangents.
// Arguments:
// v - The vertex containing position, normal and tangent.
// skinTransforms - The bone transforms to apply.
static void EvalSkin(inout VNTIn v, uniform float3x4 skinTransforms[])
{
	UNNORMALIZE_SKININDICES(v.SkinIndices);
	EvaluateSkinPositionNormalTangent4Bones(v.SkinnableVertex, v.SkinnableNormal, v.SkinnableTangent, v.SkinWeights, v.SkinIndices, skinTransforms);
}

// Description:
// Evaluate the skinned vertex with positions and normals.
// Arguments:
// v - The vertex containing position and normal.
// skinTransforms - The bone transforms to apply.
static void EvalSkin(inout VNIn v, uniform float3x4 skinTransforms[])
{
	UNNORMALIZE_SKININDICES(v.SkinIndices);
	EvaluateSkinPositionNormal4Bones(v.SkinnableVertex, v.SkinnableNormal, v.SkinWeights, v.SkinIndices, skinTransforms);
}

// Description:
// Evaluate the skinned vertex with position.
// Arguments:
// v - The vertex containing position.
// skinTransforms - The bone transforms to apply.
static void EvalSkin(inout VIn v, uniform float3x4 skinTransforms[])
{
	UNNORMALIZE_SKININDICES(v.SkinIndices);
	EvaluateSkinPosition4Bones(v.SkinnableVertex, v.SkinWeights, v.SkinIndices, skinTransforms);
}
#endif //! SKINNING_ENABLED

// Description:
// Transform a position for instancing.
// Arguments:
// IN - The instancing transform by which to transform the position.
// toTransform - The position to transform.
// Returns:
// The transformed position.
static void ApplyInstanceTransformVertex(InstancingInput IN, inout float3 toTransform)
{
	float3 instanceTransformedPosition;
	instanceTransformedPosition.x = dot(IN.InstanceTransform0, float4(toTransform,1));
	instanceTransformedPosition.y = dot(IN.InstanceTransform1, float4(toTransform,1));
	instanceTransformedPosition.z = dot(IN.InstanceTransform2, float4(toTransform,1));
	toTransform = instanceTransformedPosition;
}

// Description:
// Transform a normal for instancing.
// Arguments:
// IN - The instancing transform by which to transform the normal.
// toTransform - The normal to transform.
// Returns:
// The transformed normal.
static void ApplyInstanceTransformNormal(InstancingInput IN, inout float3 toTransform)
{
	float3 instanceTransformedNormal;
	instanceTransformedNormal.x = dot(IN.InstanceTransform0.xyz, toTransform);
	instanceTransformedNormal.y = dot(IN.InstanceTransform1.xyz, toTransform);
	instanceTransformedNormal.z = dot(IN.InstanceTransform2.xyz, toTransform);
	toTransform = instanceTransformedNormal;
}

// Description:
// Move data from input vertex to output vertex, applying transforms as applicable.
// Arguments:
// o - The output vertex to which to move data.
// i - The input vertex from which to move data.
static void MoveToOutputVert(out VOut o, in VIn i)
{
#ifdef SKINNING_ENABLED
	float3 position = i.SkinnableVertex.xyz;
	o.Position = mul(scene.ViewProjection, float4(position.xyz,1));	
#else //! SKINNING_ENABLED
	float3 position = i.Position.xyz;
	o.Position = mul(WorldViewProjection, float4(position.xyz,1));
#endif //! SKINNING_ENABLED
}

// Description:
// Move data from input vertex to output vertex, applying transforms as applicable.
// Arguments:
// o - The output vertex to which to move data.
// i - The input vertex from which to move data.
static void MoveToOutputVert(out VNOut o, in VNIn i)
{
#ifdef SKINNING_ENABLED
	float3 position = i.SkinnableVertex;
	o.Position = mul(scene.ViewProjection, float4(position,1.0f));
	o.WorldPositionDepth = float4(position, -mul(scene.View, float4(position,1.0f)).z);
	o.Normal = normalize(i.SkinnableNormal);
#else //! SKINNING_ENABLED
	float3 position = i.Position.xyz;
	o.Position = mul(WorldViewProjection, float4(position,1.0f));
	o.WorldPositionDepth = float4(mul(World, float4(position,1.0f)).xyz, -mul(WorldView, float4(position,1.0f)).z);
	o.Normal = normalize(mul(World, float4(i.Normal,0)).xyz);
#endif //! SKINNING_ENABLED
}

// Description:
// Move data from input vertex to output vertex, applying transforms as applicable.
// Arguments:
// o - The output vertex to which to move data.
// i - The input vertex from which to move data.
static void MoveToOutputVert(out VNTOut o, in VNTIn i)
{
#ifdef SKINNING_ENABLED
	float3 position = i.SkinnableVertex;
	o.Position = mul(scene.ViewProjection, float4(position,1.0f));
	o.WorldPositionDepth = float4(position, -mul(scene.View, float4(position,1.0f)).z);
	o.Normal = normalize(i.SkinnableNormal);
	o.Tangent = normalize(i.SkinnableTangent);
#else //! SKINNING_ENABLED
	float3 position = i.Position.xyz;
	o.Position = mul(WorldViewProjection, float4(position,1.0f));
	o.WorldPositionDepth = float4(mul(World, float4(position,1.0f)).xyz, -mul(WorldView, float4(position,1.0f)).z);
	o.Normal = normalize(mul(World, float4(i.Normal,0)).xyz);
	o.Tangent = normalize(mul(World, float4(i.Tangent,0)).xyz);
#endif //! SKINNING_ENABLED
}

#endif //! PHYRE_PBR_SHARED_CGFX_H
