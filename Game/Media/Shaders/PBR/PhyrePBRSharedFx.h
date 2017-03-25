/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_PBR_SHARED_FX_H
#define PHYRE_PBR_SHARED_FX_H

// Description:
// The pre-integrated DFG terms for the fast evaluation of IBL BRDFs.
Texture2D <float4> PbrPreintegratedDFG : PbrPreintegratedDFG;

// Description:
// The linear filter texture sampler with clamp address mode.
sampler ClampLinearSampler
{
	Filter = Min_Mag_Mip_Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

// Description:
// The MRT output from the PBR deferred pixel shader.
struct PbrDeferredPSOutput
{
	float4 Color : FRAG_OUTPUT_COLOR0;									// The albedo.rgb and AO/cavity in w.
	float4 Normal_Depth : FRAG_OUTPUT_COLOR1;							// The normal packed as octahedron in xy, view depedent roughness in z and depth in w.
	float4 Specular_Rough : FRAG_OUTPUT_COLOR2;							// The Specular.rgb and roughness.  Metallicity is inferred from a high specular value.
#if VELOCITY_ENABLED
	float2 Velocity : FRAG_OUTPUT_COLOR3;
#endif //! VELOCITY_ENABLED
};

// Description:
// Get the GGX_D normalization value for the specified roughness.
// Arguments:
// roughness - The roughness for which to get the GGX_D normalization value.
// Returns:
// The GGX_D normalization value for the specified roughness.
float GGX_D_Normalization(float roughness)
{
	return PbrPreintegratedDFG.SampleLevel(ClampLinearSampler, float2(0, roughness), 0).w;
}

///////////////////////////
// LTC Sampling methods. //
///////////////////////////

Texture2D <float4> PbrLtcAmpTex : PbrLtcAmpTex;			// The LTC Amplitude texture.
Texture2D <float4> PbrLtcMatTex : PbrLtcMatTex;			// The LTC matrix texture.

// Description:
// Sample the Linear Transformed Cosine amplitude texture for the specified coordinates.
// Arguments:
// coordinate - The texture coordinate for which to sample the texture.
// Returns:
// The LTC amplitude texture sample.
float4 LTC_SampleAmp(float2 coord)
{
	return PbrLtcAmpTex.SampleLevel(ClampLinearSampler, coord, 0);
}

// Description:
// Sample the Linear Transformed Cosine matrix texture for the specified coordinates.
// Arguments:
// coordinate - The texture coordinate for which to sample the texture.
// Returns:
// The LTC matrix texture sample.
float4 LTC_SampleMat(float2 coord)
{
	return PbrLtcMatTex.SampleLevel(ClampLinearSampler, coord, 0);
}

// Description:
// Pastes two tokens together.
// Arguments:
// a - The first token to paste.
// b - The second token to paste.
#define MERGE(a,b) a##b

// Description:
// Evaluate a normal map normal and transform into world space using the geometric normal and tangent.
// Arguments:
// normal - The geometric normal.
// uv - The texture coordinate with which to address the normal map.
// tangent - The tangent that orients the normla map on the geometry's surface.
// normalMapSampler - The normal map to sample.
// Returns:
// The evaluated normal map normal.
float3 EvaluateNormalMapNormal(float3 normal, float2 uv, float3 tangent, Texture2D <float4> normalMapSampler)
{
	float4 normalMapValue = normalMapSampler.Sample(NormalMapSamplerSampler, uv);
	float3 normalMapNormal = normalize(normalMapValue.xyz * 2.0h - 1.0h);

	// Evaluate tangent basis
	float3 basis0 = normalize(tangent);
	float3 basis2 = normalize(normal);
	float3 basis1 = cross(basis0, basis2);

	return (normalMapNormal.x * basis0) + (normalMapNormal.y * basis1) + (normalMapNormal.z * basis2);	
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
// Returns:
// The specular color at the surface point.
static float4 EvaluateIBLSpecular(float NdotV, float3 R, float linearRoughness, PbrMaterialProperties mat, TextureCube <float4> ibl)
{
	float roughness = linearRoughness*linearRoughness;

	uint width, height, mipCount;
	ibl.GetDimensions(0, width, height, mipCount);

	// Rebuild the function
	// L . D. ( f0.Gv.(1-Fc) + Gv.Fc ) , cosTheta / (4 . NdotL . NdotV)
	NdotV = max(NdotV, 0.5f/(float)width);

	// Bias the roughness for the specular map lookup by the perpendicularity of view vector and surface normal.
	// This sharpens up the specular for grazing angles - view dependent roughness.
	float viewDependentLinearRoughness = lerp(linearRoughness, linearRoughness * abs(NdotV), mat.m_viewDependentRoughnessStrength);

	float mipLevel = linearRoughnessToMipLevel(viewDependentLinearRoughness, mipCount);
	float4 preLD = ibl.SampleLevel(LightprobeSamplerSampler, R, mipLevel);

	// Sample pre-integration DFG
	// Fc = (1-H.L)^5
	// PbrPreintegratedDFG.r = Gv.(1-Fc)
	// PbrPreintegratedDFG.g = Gv.Fc
	float2 preDFG = PbrPreintegratedDFG.SampleLevel(ClampLinearSampler, float2(NdotV, roughness), 0).xy;

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
// Returns:
// The specular color at the surface point.
static float4 EvaluateIBLSpecular(float3 N, float3 V, float linearRoughness, PbrMaterialProperties mat, TextureCube <float4> ibl)
{
	float NdotV = dot(N, V);
	float3 R = Reflection(N, V);						// Calculate reflection vector.

	return EvaluateIBLSpecular(NdotV, R, linearRoughness, mat, ibl);
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
static float4 EvaluateIBLDiffuse(float3 N, float3 V, float linearRoughness, TextureCube <float4> ibl)
{
	float roughness = linearRoughness*linearRoughness;
	float NdotV = dot(N, V);
	float4 diffuseLighting = ibl.SampleLevel(LightprobeSamplerSampler, N, 0);

	float diffF = PbrPreintegratedDFG.SampleLevel(ClampLinearSampler, float2(NdotV, roughness), 0).z;

	return float4(diffuseLighting.xyz * diffF, diffuseLighting.w);
}

// Description:
// Evaluate image based lighting at a point on the surface.
// Arguments:
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// specIbl - The pre-convolved specular light probe.
// diffIbl - The pre-convolved diffuse light probe.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingGlobalIblPBR(float3 V, PbrMaterialProperties mat, PbrGeomProperties geom, TextureCube <float4> specIbl, TextureCube <float4> diffIbl)
{
	float linearRoughness = mat.m_linearRoughness;
	float3 N = geom.m_surfaceNormal;

	PbrLightingResults lightResult;
	lightResult.m_specular = EvaluateIBLSpecular(N, V, linearRoughness, mat, specIbl).xyz;
	lightResult.m_diffuse = IsMetal(mat.m_metallicity) ? float3(0,0,0) : EvaluateIBLDiffuse(N, V, linearRoughness, diffIbl).xyz;
	lightResult.m_specularValidity = 1.0f;
	lightResult.m_diffuseValidity = 1.0f;

	return lightResult;
}

// Description:
// Evaluate local image based lighting at a point on the surface.
// Arguments:
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// spherePos - The centre of the IBL sphere.
// sphereRadius - The radius of the IBL sphere.
// specIbl - The pre-convolved specular light probe.
// diffIbl - The pre-convolved diffuse light probe.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingLocalSphereIblPBR(float3 V, PbrMaterialProperties mat, PbrGeomProperties geom, float3 spherePos, float sphereRadius, TextureCube <float4> specIbl, TextureCube <float4> diffIbl)
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
		float4 specularResult = EvaluateIBLSpecular(NdotV, localR, localLinearRoughness, mat, specIbl);

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
// diffIbl - The pre-convolved diffuse light probe.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingLocalBoxIblPBR(float3 V, PbrMaterialProperties mat, PbrGeomProperties geom, float3 boxPos, float3 boxHalfWidth, float3 boxHalfHeight, float3 boxHalfDepth, TextureCube <float4> specIbl, TextureCube <float4> diffIbl)
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
		float4 specularResult = EvaluateIBLSpecular(NdotV, localR, localLinearRoughness, mat, specIbl);

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
static PbrLightingResults EvaluateLightPBR(GlobalLightProbe light, TextureCube <float4> specIbl, TextureCube <float4> diffIbl, EmptyStruct diffBuff, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	PbrLightingResults lightResult = EvaluateLightingGlobalIblPBR(V, mat, geom, specIbl, diffIbl);

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
static PbrLightingResults EvaluateLightPBR(LocalLightProbe light, TextureCube <float4> specIbl, TextureCube <float4> diffIbl, EmptyStruct diffBuff, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	PbrLightingResults lightResult;

	// Select correct local IBL shape.
	if (light.m_radius > 0)
		lightResult = EvaluateLightingLocalSphereIblPBR(V, mat, geom, light.m_position, light.m_radius, specIbl, diffIbl);
	else
		lightResult = EvaluateLightingLocalBoxIblPBR(V, mat, geom, light.m_position, light.m_halfWidth, light.m_halfHeight, light.m_halfDepth, specIbl, diffIbl);

	Scale(lightResult, shadowAmount);	// Shadowing.

	return lightResult;
}

// Description:
// Calculate the offset of the spherical harmonic within the radiance volume structured buffer.
// Arguments:
// nX - The X index of the SH probe in the radiance volume.
// nY - The Y index of the SH probe in the radiance volume.
// nZ - The Z index of the SH probe in the radiance volume.
// log2ProbeRes - The base 2 logarithm of the probe resolution in each axis in the radiance volume.
// Returns:
// The index of the spherical harmonic in the radiance volume.
static uint ShOffset(uint nX, uint nY, uint nZ, uint log2ProbeRes)
{
	uint offset = (nZ << (log2ProbeRes*2)) + (nY << log2ProbeRes) + nX;
	return offset;
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
static PbrLightingResults EvaluateLightPBR(RadianceVolume light, EmptyStruct specIbl, EmptyStruct diffIbl, StructuredBuffer<SHOrder2Float4> diffBuff, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	PbrLightingResults lightResult;

	uint lightProbeRes = 1 << light.m_log2ProbeRes;
	// Generate parametric position in radiance volume from surface position.
	float3 lightSpaceSurfacePosition = geom.m_worldPosition - light.m_position;

	float lenX = length(light.m_halfWidth);
	float3 dirX = normalize(light.m_halfWidth);
	float lenY = length(light.m_halfHeight);
	float3 dirY = normalize(light.m_halfHeight);
	float lenZ = length(light.m_halfDepth);
	float3 dirZ = normalize(light.m_halfDepth);

	float x = saturate(dot(lightSpaceSurfacePosition, dirX) * 0.5f/lenX + 0.5f);
	float y = saturate(dot(lightSpaceSurfacePosition, dirY) * 0.5f/lenY + 0.5f);
	float z = saturate(dot(lightSpaceSurfacePosition, dirZ) * 0.5f/lenZ + 0.5f);

	float nX = x * (lightProbeRes-1);
	float nY = y * (lightProbeRes-1);
	float nZ = z * (lightProbeRes-1);

	uint nX1 = (uint)nX;
	uint nY1 = (uint)nY;
	uint nZ1 = (uint)nZ;

	uint nX2 = min(nX1 + 1, (lightProbeRes-1));				// Clamp to upper bounds of probe grid.
	uint nY2 = min(nY1 + 1, (lightProbeRes-1));
	uint nZ2 = min(nZ1 + 1, (lightProbeRes-1));

	float tX1 = frac(nX);
	float tY1 = frac(nY);
	float tZ1 = frac(nZ);

	// Fetch 8 spherical harmonics.
	SHOrder2Float4		sh000 = diffBuff[ShOffset(nX1, nY1, nZ1, light.m_log2ProbeRes)];
	SHOrder2Float4		sh001 = diffBuff[ShOffset(nX2, nY1, nZ1, light.m_log2ProbeRes)];
	SHOrder2Float4		sh010 = diffBuff[ShOffset(nX1, nY2, nZ1, light.m_log2ProbeRes)];
	SHOrder2Float4		sh011 = diffBuff[ShOffset(nX2, nY2, nZ1, light.m_log2ProbeRes)];
	SHOrder2Float4		sh100 = diffBuff[ShOffset(nX1, nY1, nZ2, light.m_log2ProbeRes)];
	SHOrder2Float4		sh101 = diffBuff[ShOffset(nX2, nY1, nZ2, light.m_log2ProbeRes)];
	SHOrder2Float4		sh110 = diffBuff[ShOffset(nX1, nY2, nZ2, light.m_log2ProbeRes)];
	SHOrder2Float4		sh111 = diffBuff[ShOffset(nX2, nY2, nZ2, light.m_log2ProbeRes)];

	// Trilinearly interpolate the 8 spherical harmonic coefficients for the geometric surface position.
	ShLerp(sh000, sh100, tZ1);
	ShLerp(sh001, sh101, tZ1);
	ShLerp(sh010, sh110, tZ1);
	ShLerp(sh011, sh111, tZ1);

	ShLerp(sh000, sh010, tY1);
	ShLerp(sh001, sh011, tY1);

	ShLerp(sh000, sh001, tX1);

	// Evaluate the interpolated spherical harmonic at surface normal direction.
	SHOrder2Float shBuff;
	EvaluateSH(shBuff, geom.m_surfaceNormal);

	// Multiply in SH-projection of cosinus lobe (NdotL term in frequency domain).
	ApplyCosinusLobe(shBuff);

	// Reconstruct the answer.
	float4 color = ShReconstruct(sh000, shBuff);

	lightResult.m_diffuse = color.xyz;
	lightResult.m_specular = float3(0,0,0);
	lightResult.m_diffuseValidity = saturate(color.w);
	lightResult.m_specularValidity = 0.0f;

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(RadianceVolume light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += (toAdd.m_diffuse * toAdd.m_diffuseValidity);
}

#endif //! EXTENDED_LIGHT_TYPES

////////////////////////////////////////////////////////////////////////////////////////////
// Passthrough for non image based lights that discard the specular and diffuse samplers. //
////////////////////////////////////////////////////////////////////////////////////////////

#define InstantiateNonIBLPassthrough(LIGHT_TYPE) \
	static PbrLightingResults EvaluateLightPBR(LIGHT_TYPE light, EmptyStruct specMap, EmptyStruct diffMap, EmptyStruct diffBuff, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom) \
	{ \
		return EvaluateLightPBR(light, V, shadowAmount, mat, geom); \
	}

InstantiateNonIBLPassthrough(DirectionalLight);
InstantiateNonIBLPassthrough(PointLight);
InstantiateNonIBLPassthrough(SpotLight);
#ifdef EXTENDED_LIGHT_TYPES
InstantiateNonIBLPassthrough(AreaDiscLight);
InstantiateNonIBLPassthrough(AreaSphereLight);
InstantiateNonIBLPassthrough(AreaRectangleLight);
InstantiateNonIBLPassthrough(AreaTubeLight);
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
#ifdef MAYA
	return float2(uv.x, 1.0f - uv.y);
#else //! MAYA
	return uv;
#endif //! MAYA
}

#ifdef __ORBIS__
	#define POSTYPE float4
#else //! __ORBIS__
	#define POSTYPE float3
#endif //! __ORBIS__

// Description:
// The skinned and unskinned vertex input.
struct VIn
{
#ifdef SKINNING_ENABLED
	POSTYPE	SkinnableVertex			: POSITION;
	uint4	SkinIndices				: BLENDINDICES;
	float4	SkinWeights				: BLENDWEIGHTS;
#else //! SKINNING_ENABLED
	POSTYPE	Position				: POSITION;
#endif //! SKINNING_ENABLED
};

// Description:
// The skinned and unskinned vertex input with normals.
struct VNIn
{
#ifdef SKINNING_ENABLED
	POSTYPE	SkinnableVertex			: POSITION;
	float3	SkinnableNormal			: NORMAL; 	
	uint4	SkinIndices				: BLENDINDICES;
	float4	SkinWeights				: BLENDWEIGHTS;
#else //! SKINNING_ENABLED
	POSTYPE	Position				: POSITION;
	float3	Normal					: NORMAL;
#endif //! SKINNING_ENABLED
};

// Description:
// The skinned and unskinned vertex input with normals and tangents.
struct VNTIn
{
#ifdef SKINNING_ENABLED
	POSTYPE	SkinnableVertex			: POSITION;
	float3	SkinnableNormal			: NORMAL; 	
	uint4	SkinIndices				: BLENDINDICES;
	float4	SkinWeights				: BLENDWEIGHTS;
	float3	SkinnableTangent		: TANGENT;
#else //! SKINNING_ENABLED
	POSTYPE	Position				: POSITION;
	float3	Normal					: NORMAL;
	float3	Tangent					: TANGENT;
#endif //! SKINNING_ENABLED
};

// Description:
// The vertex output.
struct VOut
{
	float4 Position					: SV_POSITION;	
};

// Description:
// The vertex output with normals.
struct VNOut
{
	float4	Position				: SV_POSITION;	
	float4	WorldPositionDepth		: TEXCOORD1;
	centroid float3	Normal			: TEXCOORD2;
};

// Description:
// The vertex output with normals and tangents.
struct VNTOut
{
	float4	Position				: SV_POSITION;	
	float4	WorldPositionDepth		: TEXCOORD1;
	centroid float3	Normal			: TEXCOORD2;
	centroid float3	Tangent			: TEXCOORD3;
};

// Description:
// Structure containing the instancing transformation for a geometry instance.
struct InstancingInput
{
	float4	InstanceTransform0 : InstanceTransform0;
	float4	InstanceTransform1 : InstanceTransform1;
	float4	InstanceTransform2 : InstanceTransform2;
#ifdef VELOCITY_ENABLED
	float4	InstanceTransformPrev0 : InstanceTransformPrev0;
	float4	InstanceTransformPrev1 : InstanceTransformPrev1;
	float4	InstanceTransformPrev2 : InstanceTransformPrev2;
#endif //! #ifdef VELOCITY_ENABLED
};

struct  VelocityBufferVertexInfo
{
	float4	PositionCurrent : TEXCOORD7;
	float4	PositionPrev : TEXCOORD8;
};

struct PS_OUTPUT
{
	float4 Colour : FRAG_OUTPUT_COLOR0;
#ifdef VELOCITY_ENABLED
	float2 Velocity : FRAG_OUTPUT_COLOR1;
#endif //! VELOCITY_ENABLED
};

#ifdef SKINNING_ENABLED
// Description:
// Skin a float4 vector. The w component distinguishes between a position and a direction vector.
// Arguments:
// v - The float4 vector to skin.
// weights - The bone weights to apply.
// boneIndices - The indices of the bones to apply.
// Transform - The transform matrices for skinning.
// Returns:
// The skinned vector.
static float3 SkinVec(float4 v, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform)
{
	float3 r = mul(v, Transform[boneIndices.x]).xyz * weights.x
		+ mul(v, Transform[boneIndices.y]).xyz * weights.y
		+ mul(v, Transform[boneIndices.z]).xyz * weights.z
		+ mul(v, Transform[boneIndices.w]).xyz * weights.w;

	return r;
}

// Description:
// Evaluate skin for position, normal and tangent, for 4 bone weights.
// Arguments:
// pos - The position to skin.
// nrm - The normal to skin.
// tng - The tangent to skin.
// weights - The skin weights to apply for the 4 bones.
// boneIndices - The indices of the 4 bones to apply.
void EvaluateSkinPositionNormalTangent4Bones(inout float3 pos, inout float3 nrm, inout float3 tng, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform)
{
	pos = SkinVec(float4(pos, 1), weights, boneIndices, Transform);
	nrm = SkinVec(float4(nrm, 0), weights, boneIndices, Transform);
	tng = SkinVec(float4(tng, 0), weights, boneIndices, Transform);
}

// Description:
// Evaluate skin for position, and normal for 4 bone weights.
// Arguments:
// pos - The position to skin.
// nrm - The normal to skin.
// weights - The skin weights to apply for the 4 bones.
// boneIndices - The indices of the 4 bones to apply.
void EvaluateSkinPositionNormal4Bones(inout float3 pos, inout float3 nrm, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform)
{
	pos = SkinVec(float4(pos, 1), weights, boneIndices, Transform);
	nrm = SkinVec(float4(nrm, 0), weights, boneIndices, Transform);
}

// Description:
// Evaluate skin for position for 4 bone weights.
// Arguments:
// pos - The position to skin.
// weights - The skin weights to apply for the 4 bones.
// boneIndices - The indices of the 4 bones to apply.
void EvaluateSkinPosition4Bones(inout float3 pos, float4 weights, uint4 boneIndices, StructuredBuffer<float4x4> Transform)
{
	pos = SkinVec(float4(pos, 1), weights, boneIndices, Transform);
}

// Description:
// Evaluate the skinned vertex with positions, normals and tangents.
// Arguments:
// v - The vertex containing position, normal and tangent.
static void EvalSkin(inout VNTIn v)
{
	EvaluateSkinPositionNormalTangent4Bones(v.SkinnableVertex.xyz, v.SkinnableNormal, v.SkinnableTangent, v.SkinWeights, v.SkinIndices, BoneTransforms);
}

// Description:
// Evaluate the skinned vertex with positions and normals.
// Arguments:
// v - The vertex containing position and normal.
static void EvalSkin(inout VNIn v)
{
	EvaluateSkinPositionNormal4Bones(v.SkinnableVertex.xyz, v.SkinnableNormal, v.SkinWeights, v.SkinIndices, BoneTransforms);
}

// Description:
// Evaluate the skinned vertex with position.
// Arguments:
// v - The vertex containing position.
static void EvalSkin(inout VIn v)
{
	EvaluateSkinPosition4Bones(v.SkinnableVertex.xyz, v.SkinWeights, v.SkinIndices, BoneTransforms);
}

#endif //! SKINNING_ENABLED

// Description:
// Sets the vertex shader outputs used for velocity buffer calculations.
// Input vertices have just a position, normal and tangent for skinning.
// Arguments:
// IN - The input vertex to calculate previous frame position.
// position - The current frames vertex position.
VelocityBufferVertexInfo SetVelocityBufferOutputsVS(VNTIn IN, float4 position)
{
	VelocityBufferVertexInfo OUT;

	OUT.PositionCurrent = position;

#ifdef SKINNING_ENABLED
	EvaluateSkinPositionNormalTangent4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinnableTangent.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransformsPrev);
	OUT.PositionPrev = mul(float4(IN.SkinnableVertex.xyz, 1.0f), ViewProjectionPrev);
#else //! SKINNING_ENABLED
	OUT.PositionPrev = mul(float4(IN.Position.xyz, 1.0f), WorldViewProjectionPrev);
#endif //! SKINNING_ENABLED

	return OUT;
}

// Description:
// Sets the vertex shader outputs used for velocity buffer calculations.
// Input vertices have just a position and a normal for skinning.
// Arguments:
// IN - The input vertex to calculate previous frame position.
// position - The current frames vertex position.
VelocityBufferVertexInfo SetVelocityBufferOutputsVS(VNIn IN, float4 position)
{
	VelocityBufferVertexInfo OUT;

	OUT.PositionCurrent = position;

#ifdef SKINNING_ENABLED
	EvaluateSkinPositionNormal4Bones(IN.SkinnableVertex.xyz, IN.SkinnableNormal.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransformsPrev);
	OUT.PositionPrev = mul(float4(IN.SkinnableVertex.xyz, 1.0f), ViewProjectionPrev);
#else //! SKINNING_ENABLED
	OUT.PositionPrev = mul(float4(IN.Position.xyz, 1.0f), WorldViewProjectionPrev);
#endif //! SKINNING_ENABLED

	return OUT;
}

// Description:
// Sets the vertex shader outputs used for velocity buffer calculations.
// Input vertices have just a position and a for skinning.
// Arguments:
// IN - The input vertex to calculate previous frame position.
// position - The current frames vertex position.
VelocityBufferVertexInfo SetVelocityBufferOutputsVS(VIn IN, float4 position)
{
	VelocityBufferVertexInfo OUT;

	OUT.PositionCurrent = position;

#ifdef SKINNING_ENABLED
	EvaluateSkinPosition4Bones(IN.SkinnableVertex.xyz, IN.SkinWeights, IN.SkinIndices, BoneTransformsPrev);
	OUT.PositionPrev = mul(float4(IN.SkinnableVertex.xyz, 1.0f), ViewProjectionPrev);
#else //! SKINNING_ENABLED
	OUT.PositionPrev = mul(float4(IN.Position.xyz, 1.0f), WorldViewProjectionPrev);
#endif //! SKINNING_ENABLED

	return OUT;
}

// Calculate velocity buffer data.
float2 CalculateVelocity(VelocityBufferVertexInfo velocityData)
{
	const float2 positionCurrent = velocityData.PositionCurrent.xy / velocityData.PositionCurrent.w + ProjectionJitter,
		positionPrev = velocityData.PositionPrev.xy / velocityData.PositionPrev.w + ProjectionJitterPrev;
	return positionCurrent - positionPrev;
}


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
	o.Position = mul(float4(position.xyz,1), ViewProjection);
#else //! SKINNING_ENABLED
	float3 position = i.Position.xyz;
	o.Position = mul(float4(position.xyz,1), WorldViewProjection);
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
	float3 position = i.SkinnableVertex.xyz;
	o.Position = mul(float4(position,1.0f), ViewProjection);
	o.WorldPositionDepth = float4(position, -mul(float4(position,1.0f), View).z);
	o.Normal = normalize(i.SkinnableNormal);
#else //! SKINNING_ENABLED
	float3 position = i.Position.xyz;
	o.Position = mul(float4(position,1.0f), WorldViewProjection);
	o.WorldPositionDepth = float4(mul(float4(position,1.0f),World).xyz, -mul(float4(position,1.0f),WorldView).z);
	o.Normal = normalize(mul(float4(i.Normal,0), World).xyz);
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
	float3 position = i.SkinnableVertex.xyz;
	o.Position = mul(float4(position,1.0f), ViewProjection);
	o.WorldPositionDepth = float4(position, -mul(float4(position,1.0f), View).z);
	o.Normal = normalize(i.SkinnableNormal);
	o.Tangent = normalize(i.SkinnableTangent);
#else //! SKINNING_ENABLED
	float3 position = i.Position.xyz;
	o.Position = mul(float4(position,1.0f), WorldViewProjection);
	o.WorldPositionDepth = float4(mul(float4(position,1.0f),World).xyz, -mul(float4(position,1.0f),WorldView).z);
	o.Normal = normalize(mul(float4(i.Normal,0), World).xyz);
	o.Tangent = normalize(mul(float4(i.Tangent,0), World).xyz);
#endif //! SKINNING_ENABLED	
}

/////////////////////////////////////////
// Shared state blocks for techniques. //
/////////////////////////////////////////

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

BlendState One_InvSrcAlpha_Blend
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = ONE;
	DestBlend[0] = INV_SRC_ALPHA;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
};

BlendState AdditiveBlend
{
	BlendEnable[0] = TRUE;
	SrcBlend[0] = ONE;
	DestBlend[0] = ONE;
	BlendOp[0] = ADD;
	SrcBlendAlpha[0] = ONE;
	DestBlendAlpha[0] = ONE;
	BlendOpAlpha[0] = ADD;
};

DepthStencilState DepthState
{
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Less_equal;
};

DepthStencilState NoDepthState
{
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less_equal;
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

#endif //! PHYRE_PBR_SHARED_FX_H
