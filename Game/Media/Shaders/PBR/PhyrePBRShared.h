/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_PBR_SHARED_H
#define PHYRE_PBR_SHARED_H

// Description:
// The dielectric specular color, chosen to be mid-range for typical dielectric materials.
#define DIELECTRIC_SPECULAR float3(0.04f, 0.04f, 0.04f)

// Description:
// The value of PI.
#define PBR_PI							3.14159265358979323846f

// Description:
// The reciprocal value of PI.
#define PBR_INV_PI						0.31830988618379067153f

// Description:
// A small epsilon value used to avoid 
#define PBR_EPSILON						1e-5

// Description:
// The define to enable Linearly Transformed Cosines for area lights.  Otherwise use representative point lights.
#define USE_LTC_FOR_AREA_LIGHTS

// Description:
// The define to use view space normals in the GBuffers. If not defined then world space normals are used.
//#define USE_VIEWSPACE_GBUFFER_NORMALS

#include "PhyreLinearTransformedCosine.h"

// Things which do belong here:
// ============================
//
// Code fragments common to PBR pre-processing and per-frame computation.
// Code fragments that can be shared between CgFX and HLSL.

// Things which do not belong here:
// ================================
//
// Shader parameters or uniforms.
// Any code depending directly on shader parameters or uniforms.
// And texture based code - since CgFX and HLSL have different syntax for that.
// Material or context switches.

// Description:
// Pack a -1->+1 vector4 into 0->1 range.   Out of range components will be clamped.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float4 bx2Pack(float4 v)
{
	v = (v+1.0f) * 0.5f;
	v = saturate(v);
	return v;
}

// Description:
// Pack a -1->+1 vector3 into 0->1 range.   Out of range components will be clamped.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float3 bx2Pack(float3 v)
{
	v = (v+1.0f) * 0.5f;
	v = saturate(v);
	return v;
}

// Description:
// Pack a -1->+1 vector2 into 0->1 range.   Out of range components will be clamped.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float2 bx2Pack(float2 v)
{
	v = (v+1.0f) * 0.5f;
	v = saturate(v);
	return v;
}

// Description:
// Pack a -1->+1 float into 0->1 range.   Out of range components will be clamped.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float bx2Pack(float v)
{
	v = (v+1.0f) * 0.5f;
	v = saturate(v);
	return v;
}

// Description:
// Unpack a 0->1 vector4 into -1->+1 range.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float4 bx2Unpack(float4 v)
{
	v = (v*2.0f) - 1.0f;
	return v;
}

// Description:
// Unpack a 0->1 vector3 into -1->+1 range.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float3 bx2Unpack(float3 v)
{
	v = (v*2.0f) - 1.0f;
	return v;
}

// Description:
// Unpack a 0->1 vector2 into -1->+1 range.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float2 bx2Unpack(float2 v)
{
	v = (v*2.0f) - 1.0f;
	return v;
}

// Description:
// Unpack a 0->1 float into -1->+1 range.
// Arguments:
// v - The vector to pack.
// Returns:
// The packed vector.
static float bx2Unpack(float v)
{
	v = (v*2.0f) - 1.0f;
	return v;
}

//!
//! Octahedral normal encoding reference: http://jcgt.org/published/0003/02/01/
//!

#ifdef USE_VIEWSPACE_GBUFFER_NORMALS

// Description:
// Transform the normal from world space to GBuffer space.
// Arguments:
// normal - The world space normal to transform.
// Returns:
// The normal to be written to the GBuffer (view space).
static float3 Normal_WorldSpaceToGBufferSpace(float3 normal)
{
	return mul(float4(normal, 0), View).xyz;
}

// Description:
// Transform the normal from GBuffer space to world space.
// Arguments:
// normal - The GBuffer space (view space) normal to transform.
// Returns:
// The world space normal.
static float3 Normal_GBufferSpaceToWorldSpace(float3 normal)
{
	return mul(float4(normal,0), ViewInverse).xyz;
}

#else //! USE_VIEWSPACE_GBUFFER_NORMALS

// Description:
// Transform the normal from world space to GBuffer space.
// Arguments:
// normal - The world space normal to transform.
// Returns:
// The normal to be written to the GBuffer (world space).
static float3 Normal_WorldSpaceToGBufferSpace(float3 normal)
{
	return normal;
}

// Description:
// Transform the normal from GBuffer space to world space.
// Arguments:
// normal - The GBuffer space (world space) normal to transform.
// Returns:
// The world space normal.
static float3 Normal_GBufferSpaceToWorldSpace(float3 normal)
{
	return normal;
}

#endif //! USE_VIEWSPACE_GBUFFER_NORMALS

// Description:
// Returns +/-1 for the sign of vector components.  0 is considered +ve.
// Arguments:
// v - The vector to determine the signs of.
// Returns:
// Vector of signs.
static float2 signNotZero(float2 v)
{
	return float2((v.x >= 0.0f) ? +1.0f : -1.0f, (v.y >= 0.0f) ? +1.0f : -1.0f);
}

// Description:
// Packs a normalized float3 into a oct representation.
// Arguments:
// v - The float3 to pack.
// Returns:
// The packed vector.
static float2 packFloat3ToOct(float3 v)
{
	// Project the sphere onto the octahedron, and then onto the xy plane
	float2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + abs(v.z)));

	// Reflect the folds of the lower hemisphere over the diagonals
	return (v.z <= 0.0) ? ((1.0 - abs(p.yx)) * signNotZero(p)) : p;
}

// Description:
// Unpack an oct compressed vector back to a float3.
// Arguments:
// e - The oct compressed vector.
// Returns:
// The decompressed float3 vector.
static float3 unpackOctToFloat3(float2 e)
{
	float3 v = float3(e.xy, 1.0 - abs(e.x) - abs(e.y));
	if (v.z < 0)
		v.xy = (1.0 - abs(v.yx)) * signNotZero(v.xy);
	return normalize(v);
}

//!
//! PbrReferential implementation.
//!

// Description:
// The PbrReferential structure stores a temporary orthonormal coordinate space on the surface being lit.
struct PbrReferential
{
	float3 m_normal;							// The surface normal for the referential space.
	float3 m_tangentX;							// The tangent X direction along the surface for the referential space.
	float3 m_tangentY;							// The tangent Y direction along the surface for the referential space.
};

// Description:
// Create an orthonormal basis referential for the specified normal vector.
// Arguments:
// N - The normal for which to create a referential. This assumed to be normalized.
// Returns:
// The referential for the specified normal.
static PbrReferential CreateReferential(float3 N)
{
	PbrReferential referential;

	// Local referential
	float3 upVector = abs(N.z) < 0.999 ? float3(0,0,1) : float3(1,0,0);

	referential.m_normal = N;
	referential.m_tangentX = normalize( cross(upVector, N) );
	referential.m_tangentY = cross( N, referential.m_tangentX);

	return referential;
}

// Description:
// Create an orthonormal basis referential for the normal vector (0,0,1) with tangents (1,0,0) and (0,1,0).
// Returns:
// The identity referential.
static PbrReferential CreateIdentityReferential()
{
	PbrReferential referential;

	float3 upVector = float3(1,0,0);

	referential.m_normal = float3(0,0,1);
	referential.m_tangentX = normalize( cross(upVector, referential.m_normal) );
	referential.m_tangentY = cross( referential.m_normal, referential.m_tangentX);

	return referential;
}

//!
//! PbrLightingResults implementation.
//!

// Description:
// The PbrLightingResults object stored and accumulates lighting results.
struct PbrLightingResults
{
	float3 m_diffuse;													// The diffuse lighting results.
	float m_diffuseValidity;											// The validity of the diffuse result. Local IBL may not have lighting results for given direction.
	float3 m_specular;													// The specular lighting results.
	float m_specularValidity;											// The validity of the specular result. Local IBL may not have lighting results for given direction.
};

// Description:
// Reset the light results to valid black.
// Arguments:
// self - The PbrLightingResults object to reset.
void ResetValid(out PbrLightingResults self)
{
	self.m_diffuse = float3(0,0,0);
	self.m_diffuseValidity = 1.0f;
	self.m_specular = float3(0,0,0);
	self.m_specularValidity = 1.0f;
}

// Description:
// Reset the light results to invalid black.
// Arguments:
// self - The PbrLightingResults object to reset.
void ResetInvalid(out PbrLightingResults self)
{
	self.m_diffuse = float3(0,0,0);
	self.m_diffuseValidity = 0;
	self.m_specular = float3(0,0,0);
	self.m_specularValidity = 0;
}

// Description:
// Scale the lighting results by the specified scalar.
// Arguments:
// self - The PbrLightingResults object to scale.
// scale - The scale factor by which to scale the lighting results.
void Scale(inout PbrLightingResults self, float scale)
{
	self.m_diffuse *= scale;
	self.m_specular *= scale;
}

// Description:
// Scale the lighting results by the specified vector.
// Arguments:
// self - The PbrLightingResults object to scale.
// scale - The scale factor by which to scale the lighting results.
void Scale(inout PbrLightingResults self, float3 scale)
{
	self.m_diffuse *= scale;
	self.m_specular *= scale;
}

// Description:
// Accumulate lighting results.
// Arguments:
// acc - The target of the accumulate.
// toAdd - The lighting results from which to accumulate.
void Accumulate(inout PbrLightingResults acc, PbrLightingResults toAdd)
{
	acc.m_diffuse += toAdd.m_diffuse;
	acc.m_specular += toAdd.m_specular;
}

// Description:
// Accumulate scaled lighting results.
// Arguments:
// acc - The target of the accumulate.
// toAdd - The lighting results from which to accumulate.
// scale - The amount by which to scale the lighting results before accumulating.
void AccumulateScaled(inout PbrLightingResults acc, PbrLightingResults toAdd, float scale)
{
	acc.m_diffuse += (toAdd.m_diffuse * scale);
	acc.m_specular += (toAdd.m_specular * scale);
}

//!
//! PbrMaterialProperties implementation.
//!

// Description:
// Captured material properties for shading.
struct PbrMaterialProperties
{
	float m_linearRoughness;											// The material roughness (0-1).
	float m_viewDependentRoughnessStrength;								// The strength of the view dependent roughness effect (0-1).
	float m_metallicity;												// The material metallicity (switches to metal at >0.5).
	float m_cavity;														// The material cavity (0-1).
	float3 m_specularColor;												// The material specular color.
	float4 m_albedo;													// The material albedo.
};

// Description:
// Test if a material is metal.
// Arguments:
// metallicity - The metallicity of the material.
// Return Value List:
// true - The material is metal (is a conductor).
// false - The meterial is not metal (is a dielectric).
bool IsMetal(float metallicity)
{
	return metallicity > 0.5f;
}

//!
//! PbrSurfaceProperties implementation.
//!

// Description:
// Captured geometry properties for shading.
struct PbrGeomProperties
{
	float3 m_worldPosition;												// The world position of the surface point being shaded.
	float3 m_geometricNormal;											// The geometric normal (before normal map applied).
	float3 m_surfaceNormal;												// The surface normal (after normal map applied).
	float m_viewDepth;													// The view depth for the surface point being shaded.
};

// Description:
// Initialize the geometric surface properties for a non-normal mapped surface.
// Arguments:
// self - The geometric properties to initialize.
// worldPosition - The world position with which to initialize.
// viewDepth - The view depth with which to initialize.
// normal - The normal with which to initialize.
static void Initialize(out PbrGeomProperties self, float3 worldPosition, float viewDepth, float3 normal)
{
	// Capture position and normals.
	self.m_worldPosition = worldPosition;
	self.m_geometricNormal = normal;
	self.m_surfaceNormal = normal;
	self.m_viewDepth = viewDepth;
}

// Description:
// Initialize the geometric surface properties for a non-normal mapped surface.
// Arguments:
// self - The geometric properties to initialize.
// worldPosition - The world position with which to initialize.
// viewDepth - The view depth with which to initialize.
// geomNormal - The geometric normal with which to initialize.
// surfNormal - The surface normal with which to initialize.
static void Initialize(out PbrGeomProperties self, float3 worldPosition, float viewDepth, float3 geomNormal, float3 surfNormal)
{
	// Capture position and normals.
	self.m_worldPosition = worldPosition;
	self.m_geometricNormal = geomNormal;
	self.m_surfaceNormal = surfNormal;
	self.m_viewDepth = viewDepth;
}

//!
//! Face permutor for generating face sampling normals.
//!

// Description:
// The face permutor permutes +Z axis face vectors to a specific face.
struct CubemapFacePermutor
{
	float3 m_xSelector;						// The x selector for generating sampling normals.
	float3 m_ySelector;						// The y selector for generating sampling normals.
	float3 m_zSelector;						// The z selector for generating sampling normals.
};

// Description:
// Initialize the selector with the specified fields.
// Arguments:
// self - The permutor to initialize.
// selX - The X selector.
// selY - The Y selector.
// selZ - The Z selector.
static void Initialize(out CubemapFacePermutor self, float3 selX, float3 selY, float3 selZ)
{
	self.m_xSelector = selX;
	self.m_ySelector = selY;
	self.m_zSelector = selZ;
}

#define SEL_POS_X	float3(1,0,0)
#define SEL_NEG_X	float3(-1,0,0)
#define SEL_POS_Y	float3(0,1,0)
#define SEL_NEG_Y	float3(0,-1,0)
#define SEL_POS_1	float3(0,0,1)
#define SEL_NEG_1	float3(0,0,-1)

// Description:
// Create a permutor for permuting +Z axis vectors to a specified face.
// Arguments:
// face - The face for which to create the permutor.
// Returns:
// The created permutor.
CubemapFacePermutor CreatePermutor(int face)
{
	CubemapFacePermutor perm;

	if (face == 5)
		Initialize(perm, SEL_POS_X, SEL_POS_Y, SEL_NEG_1);		// Negative Z
	else if (face == 4)
		Initialize(perm, SEL_NEG_X, SEL_POS_Y, SEL_POS_1);		// Positive Z
	else if (face == 3)
		Initialize(perm, SEL_NEG_X, SEL_NEG_1, SEL_POS_Y);		// Negative Y
	else if (face == 2)
		Initialize(perm, SEL_NEG_X, SEL_POS_1, SEL_NEG_Y);		// Positive Y
	else if (face == 1)
		Initialize(perm, SEL_NEG_1, SEL_POS_Y, SEL_NEG_X);		// Negative X
	else
		Initialize(perm, SEL_POS_1, SEL_POS_Y, SEL_POS_X);		// Positive X

	return perm;
}

// Description:
// Create a permutor for permuting +Z axis vectors to a specified X face (positive or negative).
// Arguments:
// neg - The flag that indicates that the negative face is to be processed.
// Returns:
// The permutor that was created.
CubemapFacePermutor CreatePermutorX(int neg)
{
	CubemapFacePermutor perm;

	if (neg)
		Initialize(perm, SEL_NEG_1, SEL_POS_Y, SEL_NEG_X);
	else
		Initialize(perm, SEL_POS_1, SEL_POS_Y, SEL_POS_X);

	return perm;
}

// Description:
// Create a permutor for permuting +Z axis vectors to a specified X face (positive or negative).
// Arguments:
// neg - The flag that indicates that the negative face is to be processed.
// Returns:
// The permutor that was created.
CubemapFacePermutor CreatePermutorY(int neg)
{
	CubemapFacePermutor perm;

	if (neg)
		Initialize(perm, SEL_NEG_X, SEL_NEG_1, SEL_POS_Y);
	else
		Initialize(perm, SEL_NEG_X, SEL_POS_1, SEL_NEG_Y);

	return perm;
}

// Description:
// Create a permutor for permuting +Z axis vectors to a specified X face (positive or negative).
// Arguments:
// neg - The flag that indicates that the negative face is to be processed.
// Returns:
// The permutor that was created.
CubemapFacePermutor CreatePermutorZ(int neg)
{
	CubemapFacePermutor perm;

	if (neg)
		Initialize(perm, SEL_POS_X, SEL_POS_Y, SEL_NEG_1);
	else
		Initialize(perm, SEL_NEG_X, SEL_POS_Y, SEL_POS_1);

	return perm;
}

// Description:
// Permute a vector for a specified face.
// Arguments:
// perm - The permutor describing how to permute the vector.
// vec - The vector to permute.
// Returns:
// The permuted vector.
float3 PermuteVector(CubemapFacePermutor perm, float3 vec)
{
	float ix = dot(perm.m_xSelector, vec);
	float iy = dot(perm.m_ySelector, vec);
	float iz = dot(perm.m_zSelector, vec);

	return float3(ix, iy, iz);
}

//!
//! Cubemap normal generator.
//!

// Description:
// The cubemap normal generator generates sampling vectors for faces of a cubemap, given the pixel coordinate and the face index.
struct CubemapNormalGenerator
{
	float m_size;							// The size of the cubemap texture.
	float m_recipSizeSquared;				// The square of the reciprocal size.
	float m_fB;								// The bias for calculating differential solid angles.
	float m_fS;								// The scale for calculating differential solid angles.
};

// Description:
// Initialize the cubemap normal generator for the specified cubemap size and specified face.
// Arguments:
// size - The size of the cubemap for which to generate the normals.
// face - The face of the cubemap for which to generate the normals.
// Returns:
// The cubemap normal generator that was created.
CubemapNormalGenerator CreateNormalGenerator(int size)
{
	CubemapNormalGenerator gen;

	gen.m_size = (float)size;

	float recipSize = 1.0f/(float)size;
	gen.m_recipSizeSquared = recipSize*recipSize;

	// index from [0,W-1], f(0) maps to -1 + 1/W, f(W-1) maps to 1 - 1/w
	// linear function x*S +B, 1st constraint means B is (-1+1/W), plug into
	// second and solve for S: S = 2*(1-1/W)/(W-1). The old code that did 
	// this was incorrect - but only for computing the differential solid
	// angle, where the final value was 1.0 instead of 1-1/w...
	
	gen.m_fB = -1.0f + recipSize;
	gen.m_fS = ( size > 1 ) ? (2.0f*(1.0f-recipSize)/(gen.m_size-1.0f)) : 0.f;

	return gen;
}

// Description:
// Get the differential solid angle of the specified texel in the cubemap.
// Arguments:
// gen - The cubemap normal generator with which to get the different solid angle.
// x - The x coordinate of the texel in the cubemap for for which to get the differential solid angle.
// y - The y coordinate of the texel in the cubemap for for which to get the differential solid angle.
// Returns:
// The differential solid angle.
float GetDifferentialSolidAngle(CubemapNormalGenerator gen, int x, int y)
{
	float fV = y*gen.m_fS + gen.m_fB;
	float fU = x*gen.m_fS + gen.m_fB;
	float fDiffSolid = 4.0f/((1.0f + fU*fU + fV*fV)*sqrt(1.0f + fU*fU+fV*fV));

	// Correct for size of cubemap so total over cubemap sums to 4*pi.
	fDiffSolid *= gen.m_recipSizeSquared;

	return fDiffSolid;
}

// Description:
// Generate a sampling normal for the given face texel coordinate.
// Arguments:
// gen - The cubemap normal generator with which to generate the sampling normal.
// x - The x coordinate of the texel in the cubemap for for which to generate the normal.
// y - The y coordinate of the texel in the cubemap for for which to generate the normal.
// Returns:
// The sampling normal for the specified x,y coordinate.
float3 GetNormal(CubemapNormalGenerator gen, int x, int y)
{
	// Calculate in pixel space before normalizing.
	float3 norm = float3(gen.m_size - (2.0f * (float)x + 1.0f),
						 gen.m_size - (2.0f * (float)y + 1.0f),
						 gen.m_size);

	return normalize(norm);
}

/////////////////////////////////
// BRDF evaluation components. //
/////////////////////////////////

// F_ functions evaluate the Fresnel term.
// G_ functions evaluate the geometric term (masking/shadowing).
// D_ functions evaluate the normal distribution term.

// Description:
// Evaluate the Schlick approximation for Fresnel.
// Arguments:
// f0 - The specular color at face on.
// f90 - The specular reflection at grazing angles.
// lDotH - The cosine of the angle between the light vector and the view vector.
// Returns:
// The specular reflection color.
static float3 F_Schlick(in float3 f0, in float f90, in float lDotH)
{
	return f0 + (float3(f90,f90,f90)-f0) * pow(1.f - lDotH, 5.f);

	// Could also use spherical gaussian : https://seblagarde.wordpress.com/2012/06/03/spherical-gaussien-approximation-for-blinn-phong-phong-and-fresnel/
	// Epic say this is faster to calculate and not perceptibly different.
	// F(v, h) = F0 + (1 - F0) * exp2(-5.55473 * vDotH - 6.98316) * vDotH
}

// Description:
// Evaluate the geometry shadowing/masking for GGX.
// Arguments:
// NdotL - The cosine of the angle between the surface normal and the light direction.
// NdotV - The cosine of the angle between the surface normal and the view direction.
// roughness - The surface roughness.
// Returns:
// The scalar geometry term for the BRDF evaluation.
static float G_GGX(float NdotL, float NdotV, float roughness)
{
	float a = roughness * roughness;
	float a2 = a * a;
	float2 nDotVL = float2(NdotV, NdotL);
	float2 GVL = nDotVL + sqrt(((nDotVL - (nDotVL * a2)) * nDotVL) + a2);

	// TODO : Work out how to avoid this max - we get divide by zero otherwise and NaNs in our image.
	return 1.0f / (max(GVL.x * GVL.y, PBR_EPSILON));
}

// Description:
// Evaluate the geometry shadowing/masking for GGX correlated.
// Arguments:
// NdotV - The cosine of the angle between the surface normal and the view direction.
// NdotL - The cosine of the angle between the surface normal and the light direction.
// roughness - The surface roughness.
// Returns:
// The scalar geometry term for the BRDF evaluation.
static float G_SmithGGXCorrelated(float NdotL, float NdotV, float roughness)
{
	// Original formaulation of G_SmithGGX Correlated
	// lambda_v				= (-1 + sqrt(alphaG2 * (1 - NdotL2) / NdotL2 + 1)) * 0.5f;
	// lambda_l				= (-1 + sqrt(alphaG2 * (1 - NdotV2) / NdotV2 _ 1)) * 0.5f;
	// G_SmithGGXCorrelated	= 1 / (1 + lambda_v + lambda_l);
	// V_SmithGGXCorrelated	= G_SmithGGXCorrelated / (4.0f * NdotL * NdotV);

	// This is the optimized version
	float alphaG2 = roughness * roughness;
	// Caution: the "NdotL *" and "NdotV *" are explicitly inversed, this is not a mistake.
	float Lambda_GGXV = NdotL * sqrt((-NdotV * alphaG2 + NdotV) * NdotV + alphaG2);
	float Lambda_GGXL = NdotV * sqrt((-NdotL * alphaG2 + NdotL) * NdotL + alphaG2);

	// TODO : Work out how to avoid this max - we get divide by zero otherwise and NaNs in our image.
	return 0.5f / (max(Lambda_GGXV + Lambda_GGXL, PBR_EPSILON));
}

// Description:
// Evaluate the normal distribution term for GGX.
// Arguments:
// NdotH - The cosine of the angle between the surface normal and the half vector.
// roughness - The surface roughness.
// normValue - The normalization value.
// Returns:
// The scalar geometry term for the BRDF evaluation.
static float D_GGX(float NdotH, float roughness, float normValue)
{
	float a = roughness * roughness;
	float a2 = a * a;
	//float d = ((NdotH * a2) - NdotH) * NdotH + 1;
	float d = ((NdotH*NdotH) * (a2-1)) + 1;
	//d = max(d, 1e-7f);
	return (a2 * normValue) / (PBR_PI * (d * d));
}

// Declared here, defined in the SharedCgfx/SharedFx files.
float GGX_D_Normalization(float roughness);

// Description:
// Evaluate the specular BRDF.
// Arguments:
// NdotV - The cosine of the angle between the surface normal and the view vector.
// LdotH - The cosine of the angle between the light vector and the half vector.
// NdotH - The cosine of the angle between the surface normal and the half vector.
// NdotL - The cosine of the angle between the surface normal and the light vector.
// roughness - The surface roughness.
// specularColor - The specular color of the surface.
// Returns:
// The evaluated specular color.
static float3 EvaluateSpecular(float NdotV, float LdotH, float NdotH, float NdotL, float roughness, float3 specularColor)
{
	// Specular BRDF
	float3 F			= F_Schlick(specularColor, 1.0f, LdotH);			// Fresnel
	//float G				= G_GGX(NdotL, NdotV, roughness);				// Geometric Shadowing/Visiblity.
	float G				= G_SmithGGXCorrelated(NdotL, NdotV, roughness);	// Geometric Shadowing/Visiblity.

	float normValue = GGX_D_Normalization(roughness);						// Normalize the lighting.
	float D = D_GGX(NdotH, roughness, normValue);				// Specular distribution (Trowbridge-Reitz - GGX).
	
	float3 Fr			= D * F * G;										// Specular reflectance color.

	return Fr;
}

// Description:
// Evaluate the diffuse principled Disney BRDF.
// Arguments:
// NdotV - The cosine of the angle between the surface normal and the view vector.
// NdotL - The cosine of the angle between the surface normal and the light vector.
// LdotH - The cosine of the angle between the light vector and the half vector.
// linearRoughness - The surface linear roughness. This is parametrized as the square root of the GGX roughness.
// Returns:
// The principled Disney diffuse BRDF evaluation.
static float Fr_DisneyDiffuse(float NdotV, float NdotL, float LdotH, float linearRoughness)
{
	float energyBias	= lerp(0, 0.5, linearRoughness);
	float energyFactor	= lerp(1.0, 1.0/ 1.51, linearRoughness);
	float fd90			= energyBias + 2.0 * LdotH*LdotH * linearRoughness;
	float3 f0			= float3(1.0f, 1.0f, 1.0f);
	float lightScatter	= F_Schlick(f0, fd90, NdotL).r;
	float viewScatter	= F_Schlick(f0, fd90, NdotV).r;

	return lightScatter * viewScatter * energyFactor;
}

// Description:
// Evaluate the lighting at the surface point.
// Arguments:
// L - The light incident vector.
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateDiffuseLightingPBR(float3 L, float3 V, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float linearRoughness = mat.m_linearRoughness;
	float roughness = linearRoughness * linearRoughness;

	float3 N			= geom.m_surfaceNormal;
	float NdotV			= saturate(abs(dot(N, V)) + PBR_EPSILON);
	float3 H			= normalize(V + L);
	float LdotH			= saturate(dot(L, H));
	float NdotL			= saturate(dot(N, L));

	PbrLightingResults lightResult;

	lightResult.m_diffuse = IsMetal(mat.m_metallicity) ? float3(0,0,0) : (Fr_DisneyDiffuse(NdotV, NdotL, LdotH, linearRoughness) / PBR_PI) * NdotL;
	lightResult.m_diffuseValidity = 1.0f;
	lightResult.m_specular = float3(0,0,0);
	lightResult.m_specularValidity = 1.0f;

	return lightResult;
}

// Description:
// Evaluate the lighting at the surface point.
// Arguments:
// L - The light incident vector.
// V - The view vector.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingPBR(float3 L, float3 V, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float linearRoughness = mat.m_linearRoughness;
	float roughness = linearRoughness * linearRoughness;

	float3 N			= geom.m_surfaceNormal;
	float NdotV			= saturate(abs(dot(N, V)) + PBR_EPSILON);
	float3 H			= normalize(V + L);
	float LdotH			= saturate(dot(L, H));
	float NdotH			= saturate(dot(N, H));
	float NdotL			= saturate(dot(N, L));

	PbrLightingResults lightResult;

	lightResult.m_diffuse = IsMetal(mat.m_metallicity) ? float3(0,0,0) : (Fr_DisneyDiffuse(NdotV, NdotL, LdotH, linearRoughness) / PBR_PI) * NdotL;
	lightResult.m_diffuseValidity = 1.0f;
	lightResult.m_specular = EvaluateSpecular(NdotV, LdotH, NdotH, NdotL, roughness, mat.m_specularColor) * NdotL;
	lightResult.m_specularValidity = 1.0f;

	return lightResult;
}

// Description:
// Evaluate the lighting at the surface point with separate diffuse and specular light positions.
// This is typically used for area lights with specular reflections.
// Arguments:
// diffuseL - The diffuse light incident vector.
// specularL - The diffuse light incident vector.
// V - The view vector.
// mat - The material properties at the surface point.
// linearRoughness - The linear roughness to use (not the one in mat).
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightingPBR(float3 diffuseL, float3 specularL, float3 V, PbrMaterialProperties mat, float linearRoughness, PbrGeomProperties geom)
{
	float roughness = linearRoughness * linearRoughness;

	float3 N			= geom.m_surfaceNormal;
	float NdotV			= saturate(abs(dot(N, V)) - PBR_EPSILON);

	PbrLightingResults lightResult;

	if (IsMetal(mat.m_metallicity))
	{
		// Conductors have no diffuse.
		lightResult.m_diffuse = float3(0,0,0);
	}
	else
	{
		float3 diffuseH		= normalize(V + diffuseL);
		float diffuseLdotH	= saturate(dot(diffuseL, diffuseH));
		float diffuseNdotL	= saturate(dot(N, diffuseL));

		lightResult.m_diffuse = (Fr_DisneyDiffuse(NdotV, diffuseNdotL, diffuseLdotH, linearRoughness) / PBR_PI) * diffuseNdotL;
	}
	lightResult.m_diffuseValidity = 1.0f;

	float3 specularH		= normalize(V + specularL);
	float specularLdotH	= saturate(dot(specularL, specularH));
	float specularNdotH	= saturate(dot(N, specularH));
	float specularNdotL	= saturate(dot(N, specularL));
	lightResult.m_specular = EvaluateSpecular(NdotV, specularLdotH, specularNdotH, specularNdotL, roughness, mat.m_specularColor) * specularNdotL;

	lightResult.m_specularValidity = 1.0f;

	return lightResult;
}

// Description:
// Importance sample the BRDF for GGX at the specified sample point. Also calculate the geometric term G.
// Arguments:
// u - The sample point at which to importance sample the BRDF.
// V - The view vector.
// N - The surface normal.
// referential - The referential coordinate space on the surface.
// roughness - The surface roughness.
// NdotH - The cosine of the angle between the surface normal and the half vector (returned).
// LdotH - The cosine of the angle between the light vector and the half vector (returned).
// L - The incident lighht vector (returned).
// H - The half vector (returned).
// G - The geometric term for the BRDF (returned).
static void importanceSampleGGX_G(in float2 u, in float3 V, in float3 N, in PbrReferential referential, in float roughness,
									out float NdotH, out float LdotH, out float3 L, out float3 H, out float G)
{
	float a = roughness * roughness;

	// Treat u as polar coordinate. u.x=longitude, u.y=latitude

	float phi = 2 * PBR_PI * u.x;
	float sinPhi, cosPhi;
	sincos(phi, sinPhi, cosPhi);
	float cosTheta2 = (1 - u.y) / ( 1 + (a*a - 1) * u.y );			// The BRDF lobe spread based on roughness.
	float cosTheta = sqrt(cosTheta2);
	float sinTheta = sqrt( 1 - min(1.0f, cosTheta2) );				// sin^2+cos^2 = 1

	// Calculate half vector in tangent space.
	float3 HTangentSpace = float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);

	// Transform half vector from tangent to world space
	H = referential.m_tangentX * HTangentSpace.x + referential.m_tangentY * HTangentSpace.y + referential.m_normal * HTangentSpace.z;

	// Light incident vector.
	L = (2 * dot(V,H) * H) - V;

	NdotH = saturate(dot(N, H));
	LdotH = saturate(dot(L, H));

	// Calculate G...!
	float NdotL = saturate(dot(N, L));
	float NdotV = saturate(dot(N, V));
	G = G_SmithGGXCorrelated(NdotL, NdotV, roughness);
}

// Description:
// Importance sample the BRDF for GGX at the specified sample point. Also calculate the geometric term G.
// Arguments:
// u - The sample point at which to importance sample the BRDF.
// N - The surface normal.
// referential - The referential coordinate space on the surface.
// roughness - The surface roughness.
// Returns:
// The normal distribution term for the BRDF (returned).
static float importanceSampleGGX_D(in float2 u, in float3 N, in PbrReferential referential, in float roughness)
{
	float a = roughness * roughness;

	// Treat u as polar coordinate. u.x=longitude, u.y=latitude

	float phi = 2 * PBR_PI * u.x;
	float sinPhi, cosPhi;
	sincos(phi, sinPhi, cosPhi);
	float cosTheta2 = (1 - u.y) / ( 1 + (a*a - 1) * u.y );			// The BRDF lobe spread based on roughness.
	float cosTheta = sqrt(cosTheta2);
	float sinTheta = sqrt( 1 - min(1.0f, cosTheta2) );				// sin^2+cos^2 = 1

	// Calculate half vector in tangent space.
	float3 HTangentSpace = float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);

	// Transform half vector from tangent to world space
	float3 H = referential.m_tangentX * HTangentSpace.x + referential.m_tangentY * HTangentSpace.y + referential.m_normal * HTangentSpace.z;

	float NdotH = saturate(dot(N, H));

	// Calculate D
	float D = D_GGX(NdotH, roughness, 1.0f);			// No normalization value here.

	return D;
}

// Description:
// Importance sample the BRDF for GGX at the specified sample point. Also calculate the geometric term G.
// Arguments:
// u - The sample point at which to importance sample the BRDF.
// roughness - The surface roughness.
// L - The incident lighht vector (returned in tangent space).
// Returns:
// NdotL, the cosine of the angle between the light incident vector and the sampled direction.
static float cutDownImportanceSampleGGX_G(in float2 u, in float roughness, out float3 L)
{
	float a = roughness * roughness;

	// Treat u as polar coordinate. u.x=longitude, u.y=latitude

	float phi = 2.0f * PBR_PI * u.x;
	float sinPhi, cosPhi;
	sincos(phi, sinPhi, cosPhi);
	float cosTheta2 = (1 - u.y) / ( 1 + (a*a - 1) * u.y );			// The BRDF lobe spread based on roughness.
	float cosTheta = sqrt(cosTheta2);
	float sinTheta = sqrt( 1 - min(1.0f, cosTheta2) );				// sin^2+cos^2 = 1

	// Calculate half vector in tangent space.
	float3 HTangentSpace = float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta);

	// Calculate light incident vector in tangent space.
	float3 VTangentSpace = float3(0,0,1);
	L = (2 * dot(VTangentSpace,HTangentSpace) * HTangentSpace) - VTangentSpace;
	float NdotL = L.z;		// dot(VTangentSpace, LTangentSpace);

	return NdotL;
}

// Description:
// Importance sample the BRDF for the specific sample point.
// Arguments:
// u - The sample point (2d 0-1).
// referential - The referential coordinate space on the surface.
// L - The incident light direction.
// NdotL - The cosine of the angle between the surface normal and the light direction (returned).
// pdf - The probability density function at the sample.
static void importanceSampleCosDir(in float2 u, in PbrReferential referential, out float3 L, out float NdotL, out float pdf)
{
	float u1 = u.x;							// cosTheta^2
	float u2 = u.y;							// phi/(2*PI)

	float r = sqrt(u1);						// Radius - cos(theta)
	float h = sqrt(max(0, 1.0f-u1));		// Elevation - sin(theta)
	float phi = u2 * PBR_PI * 2;				// Rotation about referential normal.
	float cosPhi, sinPhi;
	sincos(phi, sinPhi, cosPhi);

	// Generate ray in surface hemisphere.
	L = float3(r*cosPhi, r*sinPhi, h);

	// Transform back through referential to world space.
	L = normalize(referential.m_tangentX * L.x + referential.m_tangentY * L.y + referential.m_normal * L.z);

	NdotL = dot(L, referential.m_normal);
	pdf = NdotL / PBR_PI;
}

//////////////////////
// Lighting helpers //
//////////////////////

static float3 Reflection(float3 N, float3 V)
{
	// Calculate the reflection point and determine if it intersects the light.
	float NdotV			= saturate(abs(dot(N, V)) + PBR_EPSILON);
	float3 R			= 2*NdotV * N - V;						// Calculate reflection vector.
	return R;
}

// Description:
// Calculate the illuminance from a sphere or disc.
// Arguments:
// cosTheta - The cosine of the angle between the light direction and the surface normal.
// sinSigmaSqr -
// Returns:
// The illuminance from the sphere or disc.
static float illuminanceSphereOrDisc(float cosTheta, float sinSigmaSqr)
{
	float sinTheta = sqrt(1.0f - cosTheta*cosTheta);
	float illuminance = 0;

	if ((cosTheta * cosTheta) > sinSigmaSqr)
	{
		illuminance = PBR_PI * sinSigmaSqr * saturate(cosTheta);
	}
	else
	{
		float x = sqrt(1.0f / sinSigmaSqr - 1.0f);		// For a disk this simplifies to x = d/r
		float y = -x * (cosTheta / sinTheta);
		float sinThetaSqrtY = sinTheta * sqrt(1.0f - y*y);
		illuminance = (cosTheta * acos(y) - x * sinThetaSqrtY) * sinSigmaSqr + atan(sinThetaSqrtY / x);
	}

	return max(illuminance, 0);
}

// Description:
// Calculate the illuminance from an area disc light.
// Arguments:
// lightPos - The light's position.
// lightNormal - The light's normal vector (direction).
// lightRadius - The radius of the disc light.
// worldPos - The position of the surface being illuminated.
// worldNormal - The normal of the surface being illuminated.
// Returns:
// The illuminance from the disc light.
static float illuminateDiscLight(float3 lightPos, float3 lightNormal, float lightRadius,
								 float3 worldPos, float3 worldNormal, out float3 nearestLightPos)
{
	float3 surfaceToLight	= lightPos - worldPos;
	float3 L				= normalize(surfaceToLight);
	float sqrDist			= dot(surfaceToLight,surfaceToLight);

	float cosTheta = dot(worldNormal, L);
	float sqrLightRadius = lightRadius*lightRadius;
	float sinSigmaSqr = sqrLightRadius / (sqrLightRadius + max(sqrLightRadius, sqrDist));
	float illuminance = illuminanceSphereOrDisc(cosTheta, sinSigmaSqr) * saturate(dot(lightNormal, -L));

	nearestLightPos = lightPos;

	return illuminance;
}

// Description:
// Calculate the illuminance from a area sphere light.
// Arguments:
// lightPos - The light's position.
// lightRadius - The radius of the sphere light.
// worldPos - The position of the surface being illuminated.
// worldNormal - The normal of the surface being illuminated.
// Returns:
// The illuminance from the sphere light.
static float illuminateSphereLight(float3 lightPos, float lightRadius,
									float3 worldPos, float3 worldNormal, out float3 nearestLightPos)
{
	float3 surfaceToLight	= lightPos - worldPos;
	float3 L				= normalize(surfaceToLight);
	float sqrDist			= dot(surfaceToLight,surfaceToLight);

	float cosTheta = clamp(dot(worldNormal, L), -0.999, 0.999);		// Clamp to avoid edge case.
	float sqrLightRadius = lightRadius*lightRadius;
	float sinSigmaSqr = min(sqrLightRadius / sqrDist, 0.9999f);
	float illuminance = illuminanceSphereOrDisc(cosTheta, sinSigmaSqr);

	nearestLightPos = lightPos;

	return illuminance;
}

// Description:
// Compute the solid angle for a rectangle.
// Arguments:
// worldPos - The position of the surface point for which to compute the solid angle.
// p0 - The first corner of the rectangle for which to compute the solid angle.
// p1 - The second corner of the rectangle for which to compute the solid angle.
// p2 - The third corner of the rectangle for which to compute the solid angle.
// p3 - The fourth corner of the rectangle for which to compute the solid angle.
// Returns:
// The solid angle subtended by the specified rectangle.
static float rectangleSolidAngle(float3 worldPos, float3 p0, float3 p1, float3 p2, float3 p3)
{
	float3 v0 = p0 - worldPos;
	float3 v1 = p1 - worldPos;
	float3 v2 = p2 - worldPos;
	float3 v3 = p3 - worldPos;

	float3 n0 = normalize(cross(v0, v1));
	float3 n1 = normalize(cross(v1, v2));
	float3 n2 = normalize(cross(v2, v3));
	float3 n3 = normalize(cross(v3, v0));

	float g0 = acos(dot(-n0, n1));
	float g1 = acos(dot(-n1, n2));
	float g2 = acos(dot(-n2, n3));
	float g3 = acos(dot(-n3, n0));

	float solidAngle = g0 + g1 + g2 + g3 - 2*PBR_PI;

	// Handle the instabilities in rectangel solid angle when near to the plane of the rectangle.
	if (isnan(solidAngle))
		solidAngle = 0.0f;

	return solidAngle;
}

// Description:
// Calculate the solid angle projection of a sphere.
// Arguments:
// worldPos - Relative position of sphere from point for which to calculate solid angle.
// sphereRadius - The radius of the sphere for which to calculate the solid angle for.
// Returns:
// The solid angle for the sphere.
static float sphereSolidAngle(float3 worldPos, float sphereRadius)
{
	float sphereDistance = length(worldPos);
	float solidAngle = 0;
	float radiusOverDistance = sphereRadius / sphereDistance;

	if (radiusOverDistance >= 1.0f)
		solidAngle = 4 * PBR_PI;				// The sphere contains the center of the projection, therefore solid angle is 4*pi.
	else
	{
		float sinTheta = radiusOverDistance;
#if 1
		float cosTheta = sqrt(1 - sinTheta*sinTheta);
#else
		// Calculate the half apex angle of the conical projection.
		float theta = asin(sinTheta);
		float cosTheta = cos(theta);
#endif

		// Calculate the solid angle of a conical projection with apex angle 2*theta.
		solidAngle = 2 * PBR_PI * (1-cosTheta);
	}

	return solidAngle;
}

// Description:
// Intersect an infinite ray with an unbounded plane.
// rayOrigin - The start of the ray.
// rayDirection - The direction of the ray.
// planeOrigin - A point on the plane.
// planeNormal - The plane normal.
// Returns:
// The intersection of the plane and the ray.
float3 rayPlaneIntersect(float3 rayOrigin, float3 rayDirection, float3 planeOrigin, float3 planeNormal)
{
	float dist = dot(planeNormal, planeOrigin - rayOrigin) / dot(planeNormal, rayDirection);
	return rayOrigin + rayDirection * dist;
}

// Description:
// Return the closest point to a rectangular shape defined by two vectors and a center point.
// Arguments:
// pos - The pos for which to generate a closest point in the rectangle.
// centerPos - The center of the rectangle.
// halfLeft - The half left vector defining the rectangle's size and orientation.
// halfUp - The half up vector defining the rectangle's size and orientation.
// Returns:
// The closest point in the rectangle to the specified pos.
float3 closestPointRect(float3 pos, float3 centerPos, float3 halfLeft, float3 halfUp)
{
	float3 left = normalize(halfLeft);
	float3 up = normalize(halfUp);
	float2 rectHalfSize = float2(length(halfLeft), length(halfUp));

	// Transform into coordinate space with rectangle center at origin.
	float3 dir = pos - centerPos;

	// Project in 2D plane defined by left and up vectors.
	float2 dist2D = float2(dot(dir, left), dot(dir, up));
	dist2D = clamp(dist2D, -rectHalfSize, rectHalfSize);
	return centerPos + dist2D.x * left + dist2D.y * up;
}

// Description:
// Calculate the illuminance from an area rectangle light.
// Arguments:
// lightPos - The light's position.
// lightNormal - The light's normal vector (direction).
// lightHalfRight - The light's half right vector.
// lightHalfUp - The light's half up vector.
// worldPos - The position of the surface being illuminated.
// worldNormal - The normal of the surface being illuminated.
// Returns:
// The illuminance from the rectangle light.
static float illuminateRectangleLight(float3 lightPos, float3 lightNormal, float3 lightHalfRight, float3 lightHalfUp,
										float3 worldPos, float3 worldNormal, out float3 nearestLightPos)
{
	lightNormal = normalize(lightNormal);
	worldNormal = normalize(worldNormal);

	float illuminance = 0;
	float3 surfaceToLight = lightPos - worldPos;

	// Backface cull light.
	if (dot(surfaceToLight, lightNormal) < 0)
	{
		float clampCosAngle = 0.001f + saturate(dot(worldNormal, lightNormal));
		// Clamp d0 to the positive hemisphere of surface normal.
		float3 d0 = normalize(-lightNormal + worldNormal * clampCosAngle);
		// Clamp d1 to the negative hemisphere of light plane normal.
		float3 d1 = normalize(worldNormal - lightNormal * clampCosAngle);
		float3 dh = normalize(d0 + d1);
		float3 ph = rayPlaneIntersect(worldPos, dh, lightPos, lightNormal);
		ph = closestPointRect(ph, lightPos, lightHalfRight, lightHalfUp);

		nearestLightPos = ph;

		float3 unormLightVector = ph - worldPos;
		float sqrDist = dot(unormLightVector, unormLightVector);
		float3 L = normalize(unormLightVector);

		// Generate 4 corners of the light.
		float3 p0 = lightPos - lightHalfRight + lightHalfUp;
		float3 p1 = lightPos - lightHalfRight - lightHalfUp;
		float3 p2 = lightPos + lightHalfRight - lightHalfUp;
		float3 p3 = lightPos + lightHalfRight + lightHalfUp;
		float solidAngle = rectangleSolidAngle(worldPos, p0, p1, p2, p3);			// NOTE : solidAngle becomes unstable where worldPos lies in plane of light, causing lighting artifacts.

		illuminance = solidAngle * saturate(dot(worldNormal, L));
	}
	else
		nearestLightPos = lightPos;

	return illuminance;
}

// Description:
// Compute the closest point on a line to a specified point.
// Arguments:
// a - The first point defining the line.
// b - The second point defining the line.
// c - The point for which to find the closest point on the line.
// Returns:
// The closest point to c on the line that passes through a and b.
float3 closestPointOnLine(float3 a, float3 b, float3 c)
{
	float3 ab = b-a;
	float t = dot(c-a,ab) / dot(ab,ab);
	return a + t*ab;
}

// Description:
// Compute the closest point on a segment to a specified point.
// Arguments:
// a - The first point defining the segment.
// b - The second point defining the segment.
// c - The point for which to find the closest point on the line.
// Returns:
// The closest point to c on the segment that passes through a and b. The point is bounded to the extent a-b.
float3 closestPointOnSegment(float3 a, float3 b, float3 c)
{
	float3 ab = b-a;
	float t = dot(c-a,ab) / dot(ab,ab);
	return a + saturate(t)*ab;
}

// Description:
// Calculate the illuminance from an area tube light.
// Arguments:
// lightPos - The light's position.
// lightHalfRight - The light's half right vector.
// lightRadius - The light's radius.
// worldPos - The position of the surface being illuminated.
// worldNormal - The normal of the surface being illuminated.
// Returns:
// The illuminance from the tube light.
static float illuminateTubeLight(float3 lightPos, float3 lightHalfRight, float lightRadius,
								 float3 worldPos, float3 worldNormal, out float3 nearestLightPos)
{
	// Calculate the end points.
	float3 segmentP0 = lightPos - lightHalfRight;
	float3 segmentP1 = lightPos + lightHalfRight;

	// Compute a orthonormal frame that is oriented towards the surface.
	float3 closest = closestPointOnLine(segmentP0, segmentP1, worldPos);

	float3 forward = normalize(closest - worldPos); // By definition this is perpendicular to p0-p1.
	float3 left = normalize(-lightHalfRight);
	float3 up = cross(left, forward);

	// Calculate the corner vertices of the rectangular plane facing the surface.
	float3 lightHalfUp = lightRadius * up;
	float3 p0 = segmentP0 + lightHalfUp;
	float3 p1 = segmentP0 - lightHalfUp;
	float3 p2 = segmentP1 - lightHalfUp;
	float3 p3 = segmentP1 + lightHalfUp;

	// Calculate solid angle of light's rectangular section.
	float solidAngle = rectangleSolidAngle(worldPos, p0, p1, p2, p3);

	float illuminanceRectangle = solidAngle * 0.2f * (saturate(dot(normalize(p0 - worldPos),		worldNormal)) +
														saturate(dot(normalize(p1 - worldPos),		worldNormal)) +
														saturate(dot(normalize(p2 - worldPos),		worldNormal)) +
														saturate(dot(normalize(p3 - worldPos),		worldNormal)) +
														saturate(dot(normalize(lightPos - worldPos),	worldNormal)));

	// Position a sphere at the end of the segment nearest the surface.
	float3 spherePos = closestPointOnSegment(segmentP0, segmentP1, worldPos);
	float3 sphereUnormL = spherePos - worldPos;
	float3 sphereL = normalize(sphereUnormL);
	float sphereDistanceSqr = dot(sphereUnormL, sphereUnormL);

	float illuminanceSphere = PBR_PI * saturate(dot(sphereL, worldNormal)) * ((lightRadius*lightRadius) / sphereDistanceSqr);

	nearestLightPos = spherePos;

	return illuminanceRectangle + illuminanceSphere;
}

// Description:
// Convert a material roughness to a mip level for sampling of a specular lightprobe.
// Arguments:
// linearRoughness - The linear roughness for which to get the mip level.
// mipCount - The mipcount for the specular lightprobe to be sampled.
// Returns:
// The mip level to sample. Fractional values indicate that mip levels should be blended.
static float linearRoughnessToMipLevel(float linearRoughness, int mipCount)
{
	// linearRoughness from 0->1. Map this to the whole mip level range.
	return lerp(0, (float)(mipCount-1), saturate(linearRoughness));
}

// Description:
// Intersect a ray with a sphere, returning the intersection distances for entry and exit.
// Arguments:
// intersects - The returned intersection parametric distances along the ray. x is entry pos, y is exit pos.
// rayOrigin - The start of the ray with which to intersect.
// rayDir - The direction of the ray with which to intersect.
// sphereRadius - The radius of the sphere (centred at 0,0,0) with which to intersect.
// Return Value List:
// true - The ray intersected the sphere and the intersection points were returned.
// false - The ray did not intersect the sphere.
static bool sphereRayIntersect(out float2 intersects, float3 rayOrigin, float3 rayDir, float sphereRadius)
{
	// Solve quadratic equation
	float a = dot(rayDir, rayDir);
	float b = 2.0f * dot(rayOrigin, rayDir);
	float c = dot(rayOrigin, rayOrigin) - (sphereRadius*sphereRadius);
	float disc = b * b - 4 * a * c;
	if (disc >= 0)
	{
		float rootDisc = sqrt(disc);
		intersects = float2((-b-rootDisc)/(2*a), (-b+rootDisc)/(2*a));
		return true;
	}

	intersects = float2(0,0);
	return false;
}

// Description:
// Intersect a ray with an oriented bounding box, returning the intersection distances for entry and exit.
// Arguments:
// intersects - The returned intersection parametric distances along the ray. x is entry pos, y is exit pos.
// rayOrigin - The start of the ray with which to intersect.
// rayDir - The direction of the ray with which to intersect.
// boxHalfWidth - The half width of the box (centred at 0,0,0) with which to intersect.
// boxHalfHeight - The half height of the box (centred at 0,0,0) with which to intersect.
// boxHalfDepth - The half depth of the box (centred at 0,0,0) with which to intersect.
// Return Value List:
// true - The ray intersected the box and the intersection points were returned.
// false - The ray did not intersect the box.
static bool obbRayIntersect(out float2 intersections, float3 rayOrigin, float3 rayDir, float3 boxHalfWidth, float3 boxHalfHeight, float3 boxHalfDepth)
{
	rayDir = normalize(rayDir);

	// Track minimum and maximum parametric distance (entry and exit).
	float enter = -100000.0f;
	float exit = 100000.0f;

	// Determine the intersection of the 3 slab entry/exit points.

	// Ray = (widthOrigin1, rayDir). Plane = (0,0,0), boxX.
	// Ray = (widthOrigin2, rayDir). Plane = (0,0,0), boxX.
	float3 boxX = normalize(boxHalfWidth);
	float denomX = -dot(boxX, rayDir);
	if (abs(denomX) > 0.00001f)
	{
		float recipDenomX = 1.0f / denomX;

		// RayDir is not parallel to slab, proceed.
		float3 widthOrigin1 = rayOrigin + boxHalfWidth;
		float3 widthOrigin2 = rayOrigin - boxHalfWidth;
		float t1 = dot(widthOrigin1, boxX) * recipDenomX;
		float t2 = dot(widthOrigin2, boxX) * recipDenomX;
		float enterX = min(t1, t2);
		float exitX = max(t1, t2);

		if ((enterX > exit) || (exitX < enter))
		{
			intersections = float2(0,0);
			return false;							// Slab X does not intersect existing interval - no intersection.
		}
		enter = max(enter, enterX);
		exit = min(exit, exitX);
	}

	float3 boxY = normalize(boxHalfHeight);
	float denomY = -dot(boxY, rayDir);
	if (abs(denomY) > 0.00001f)
	{
		float recipDenomY = 1.0f / denomY;

		// Raydir is not parallel to slab, proceed.
		float3 heightOrigin1 = rayOrigin + boxHalfHeight;
		float3 heightOrigin2 = rayOrigin - boxHalfHeight;

		float t1 = dot(heightOrigin1, boxY) * recipDenomY;
		float t2 = dot(heightOrigin2, boxY) * recipDenomY;
		float enterY = min(t1, t2);
		float exitY = max(t1, t2);

		if ((enterY > exit) || (exitY < enter))
		{
			intersections = float2(0,0);
			return false;							// Slab Y does not intersect existing interval - no intersection.
		}
		enter = max(enter, enterY);
		exit = min(exit, exitY);
	}

	float3 boxZ = normalize(boxHalfDepth);
	float denomZ = -dot(boxZ, rayDir);
	if (abs(denomZ) > 0.00001f)
	{
		float recipDenomZ = 1.0f / denomZ;

		// Raydir is not parallel to slab, proceed.
		float3 depthOrigin1 = rayOrigin + boxHalfDepth;
		float3 depthOrigin2 = rayOrigin - boxHalfDepth;
		float t1 = dot(depthOrigin1, boxZ) * recipDenomZ;
		float t2 = dot(depthOrigin2, boxZ) * recipDenomZ;
		float enterZ = min(t1, t2);
		float exitZ = max(t1, t2);

		if ((enterZ > exit) || (exitZ < enter))
		{
			intersections = float2(0,0);
			return false;							// Slab Z does not intersect existing interval - no intersection.
		}
		enter = max(enter, enterZ);
		exit = min(exit, exitZ);
	}

	// Assumption - at least one of the box planes was not parallel to the ray so that enter and exit were updated.
	intersections = float2(enter, exit);
	return (enter < exit) && (exit > 0);
}

// Description:
// Intersect a ray with an oriented rectangle, returning the intersection distance.
// Arguments:
// intersect - The returned intersection parametric distances along the ray.
// rayOrigin - The start of the ray with which to intersect.
// rayDir - The direction of the ray with which to intersect.
// rectHalfWidth - The half width of the rectangle (centred at 0,0,0) with which to intersect.
// rectHalfHeight - The half height of the rectangle (centred at 0,0,0) with which to intersect.
// rectNormal - The normal of the rectangle.
// Returns:
// Parametric intersection along the ray, negative for no intersection.
// false - The ray did not intersect the box.
static float rectangleRayIntersect(float3 rayOrigin, float3 rayDir, float3 rectHalfWidth, float3 rectHalfHeight, float3 rectNormal)
{
	// Process this as a 0-depth box.

	rayDir = normalize(rayDir);

	// Track minimum and maximum parametric distance (entry and exit).
	float enter = -100000.0f;
	float exit = 100000.0f;

	// Reduce to 6 plane tests by offsetting the ray origin by the half width, height and depth in each direction.

	// Ray = (widthOrigin1, rayDir). Plane = (0,0,0), rectX.
	// Ray = (widthOrigin2, rayDir). Plane = (0,0,0), rectX.
	float3 rectX = normalize(rectHalfWidth);
	float denomX = -dot(rectX, rayDir);
	if (abs(denomX) > 0.00001f)
	{
		float recipDenomX = 1.0f / denomX;

		// RayDir is not parallel to slab, proceed.
		float3 widthOrigin1 = rayOrigin + rectHalfWidth;
		float3 widthOrigin2 = rayOrigin - rectHalfWidth;
		float t1 = dot(widthOrigin1, rectX) * recipDenomX;
		float t2 = dot(widthOrigin2, rectX) * recipDenomX;
		float enterX = min(t1, t2);
		float exitX = max(t1, t2);

		if ((enterX > exit) || (exitX < enter))
			return -1.0f;							// Slab X does not intersect existing interval - no intersection.

		enter = max(enter, enterX);
		exit = min(exit, exitX);
	}

	float3 rectY = normalize(rectHalfHeight);
	float denomY = -dot(rectY, rayDir);
	if (abs(denomY) > 0.00001f)
	{
		float recipDenomY = 1.0f / denomY;

		// Raydir is not parallel to slab, proceed.
		float3 heightOrigin1 = rayOrigin + rectHalfHeight;
		float3 heightOrigin2 = rayOrigin - rectHalfHeight;

		float t1 = dot(heightOrigin1, rectY) * recipDenomY;
		float t2 = dot(heightOrigin2, rectY) * recipDenomY;
		float enterY = min(t1, t2);
		float exitY = max(t1, t2);

		if ((enterY > exit) || (exitY < enter))
			return -1.0f;							// Slab Y does not intersect existing interval - no intersection.

		enter = max(enter, enterY);
		exit = min(exit, exitY);
	}

	float3 rectZ = normalize(rectNormal);
	float denomZ = -dot(rectZ, rayDir);
	if (abs(denomZ) > 0.00001f)
	{
		float recipDenomZ = 1.0f / denomZ;

		// Raydir is not parallel to slab, proceed.
		float3 depthOrigin = rayOrigin;
		float enterExitZ = dot(depthOrigin, rectZ) * recipDenomZ;

		if ((enterExitZ > exit) || (enterExitZ < enter))
			return -1.0f;							// Slab Z does not intersect existing interval - no intersection.

		enter = max(enter, enterExitZ);
		exit = min(exit, enterExitZ);
	}

	// Assumption - at least one of the planes was not parallel to the ray so that enter and exit were updated.
	if (exit < enter)
		enter = -1.0f;								// Exit before enter - no collision.
	return enter;
}

// Description:
// Find the closest point in an oriented rectangle to a ray.
// Arguments:
// rayOrigin - The origin of the ray.
// rayDir - The direction of the ray.
// rectHalfWidth - The half width and direction of the rectangle (centred at 0,0,0) .
// rectHalfHeight - The half height and direction of the rectangle (centred at 0,0,0) .
// rectNormal - The orientation of the rectangle.
// Returns:
// The closest point on the rectangle to the ray.
static float3 closestPointInRect(float3 rayOrigin, float3 rayDir, float3 rectHalfWidth, float3 rectHalfHeight, float3 rectNormal)
{
	rayDir = normalize(rayDir);
	rectNormal = normalize(rectNormal);

	// Intersect the ray with the rectangle plane.
	float rectPlaneDistance = 0;
	float denom = -dot(rectNormal, rayDir);

	float recipDenom = 1.0f / denom;
	float t = dot(rayOrigin, rectNormal) * recipDenom;

	float3 pt = rayOrigin + t*rayDir;

	// Now project onto the rectangle perpendicular axes and clamp to find nearest pt.

	float3 normX = normalize(rectHalfWidth);
	float3 normY = normalize(rectHalfHeight);
	float lenX = length(rectHalfWidth);
	float lenY = length(rectHalfHeight);
	float tX = dot(pt, normX);
	float tY = dot(pt, normY);
			
	tX = min(max(tX, -lenX), lenX);
	tY = min(max(tY, -lenY), lenY);
			
	return normX*tX + normY*tY;
}

// Description:
// Find the closest point on a sphere to a ray.
// Arguments:
// rayOrigin - The origin of the ray.
// rayDir - The direction of the ray.
// sphereRadius - The radius of the sphere (centred at 0,0,0).
// Returns:
// The closest point on the sphere to the ray.
static float3 closestPointInSphere(float3 rayOrigin, float3 rayDir, float sphereRadius)
{
	// Solve quadratic equation
	float a = dot(rayDir, rayDir);
	float b = 2.0f * dot(rayOrigin, rayDir);
	float c = dot(rayOrigin, rayOrigin) - (sphereRadius*sphereRadius);
	float disc = b * b - 4 * a * c;
	float t = 0;			// Default closest point to start of ray.
	if (disc >= 0)
	{
		// Ray intersects sphere, closest point is near intersect.
		float rootDisc = sqrt(disc);
		t = max(0, (-b-rootDisc)/(2*a));
		return rayOrigin + normalize(rayDir) * t;
	}
	else
	{
		// Ray does not intersect sphere, closest point is on periphery.
		t = dot(normalize(rayDir), -rayOrigin);
		float3 closestPt = rayOrigin + normalize(rayDir) * t;
		return sphereRadius * normalize(closestPt);
	}
}

// Description:
// Find the nearest points on two line segments.
// Arguments:
// p1 - The start of the first line segment.
// q1 - The end of the first line segment.
// p2 - The start of the second line segment.
// q2 - The end of the second line segment.
// nearest1 - The nearest point on the first line segment.
// nearest2 - The nearest point on the second line segment.
static void closestPtSegmentRay(float3 p1, float3 q1, float3 p2, float3 d2, out float3 nearest1, out float3 nearest2)
{
	float3 d1 = q1 - p1;				// Direction vector of segment1.
	float3 r = p1 - p2;
	float a = dot(d1, d1);				// Squared length of segment1.
	float e = dot(d2, d2);				// Squared length of direction vector.

	float c = dot(d1, r);
	float f = dot(d2, r);

	float s = 0;
	float t = 0;

	// If the segment is degenerate then return the singularity.
	if (a <= PBR_EPSILON)
	{
		// First segment degenerates into a point.
		s = 0;					// s = 0
		t = saturate(f/e);		// t = (b*s + f) / e = f / e
	}
	else
	{
		// The segments has some length. This is the non-degenerate case.
		float b = dot(d1, d2);
		float denom = a*e - b*b;		// Always non-negative.

		// If segments not parallel, compute closest point on L1 to L2 and
		// clamp to segment s1. Else pick arbitrary s (here O).
		if (denom != 0)
			s = saturate((b*f - c*e) / denom);
		else
			s = 0;

		// Compute point on L2 closest to S1(s) using
		// t = dot((p1 + d1*s) - p2, d2) / dot(d2,d2) = (b*s + f) / e
		t = (b*s + f) / e;
		if (t < 0)
		{
			t = 0;
			s = saturate(-c / a);
		}
		// Don't need to clamp positive limit of t - it's a ray.
	}

	nearest1 = p1 + d1*s;
	nearest2 = p2 + d2*t;
}

// Description:
// Find the closest point on a tube to a ray.
// Arguments:
// rayOrigin - The origin of the ray.
// rayDir - The direction of the ray.
// tubeHalfWidth - The half width of the tube (centred at 0,0,0)
// tubeRadius - The radius of the tube (centred at 0,0,0).
// Returns:
// The closest point on the tube to the ray.
static float3 closestPointInTube(float3 rayOrigin, float3 rayDir, float3 tubeHalfWidth, float tubeRadius)
{
	rayDir = normalize(rayDir);

	// Determine distance to light.
	float distanceToLight = -dot(rayDir, rayOrigin);

	// Find closest point between the segment of the tube light and the reflection ray.
	float3 nearestRayPt, nearestTubePt;
	closestPtSegmentRay(-tubeHalfWidth, tubeHalfWidth, rayOrigin, rayDir, nearestTubePt, nearestRayPt);

	float3 radiusVector = nearestRayPt - nearestTubePt;
	float nearestDistance = length(radiusVector);
	if (nearestDistance > tubeRadius)
	{
		// Nearest point on the silhouette/periphery of the tube.
		return nearestTubePt + normalize(radiusVector) * tubeRadius;
	}
	else
	{
		// Really we should bring this point forward because the nearest point is inside the tube whilst the intersection point is on the near side of the tube.
		return nearestRayPt;
	}
}

// Description:
// Find the closest point on a disc to a ray.
// Arguments:
// rayOrigin - The origin of the ray.
// rayDir - The direction of the ray.
// discRadius - The radius of the disc (centred at 0,0,0).
// discNormal - The orientation of the disc.
// Returns:
// The closest point on the disc.
static float3 closestPointInDisc(float3 rayOrigin, float3 rayDir, float discRadius, float3 discNormal)
{
	rayDir = normalize(rayDir);
	discNormal = normalize(discNormal);

	// Intersect the ray with the disc plane.
	float rectPlaneDistance = 0;
	float denom = -dot(discNormal, rayDir);

	float recipDenom = 1.0f / denom;
	float t = dot(rayOrigin, discNormal) * recipDenom;

	float3 pt = rayOrigin + t*rayDir;

	// Now calculate radius of intersection and clamp point to boundary if outside.
	float actualRadius = length(pt);
	if (actualRadius > discRadius)
		pt *= (discRadius / actualRadius);

	return pt;
}

// Description:
// Compute the effective roughness required for distant reflections.
// Arguments:
// linearRoughness - The roughness before being adjusted for distance.
// distanceReceiverIntersection - The distance from the receiver to the captured reflection sphere.
// sphereRadius - The radius of the sphere.
// Returns:
// The required roughness.
static float evaluateDistanceBasedRoughness(float linearRoughness, float distanceReceiverIntersection, float sphereRadius)
{
	float ratio = saturate(distanceReceiverIntersection / sphereRadius);
	float newLinearRoughness = ratio * linearRoughness;
	return lerp(newLinearRoughness, linearRoughness, linearRoughness);
}

// Description:
// Evaluate the lighting for a directional light at the surface point. Note that directional lights do not exhibit any distance falloff (since they have no posiiton to falloff from).
// Arguments:
// light - The directional light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(DirectionalLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float3 L = normalize(light.m_direction);

	PbrLightingResults lightResult;
	lightResult = EvaluateLightingPBR(L, V, mat, geom);

	// Distance attenuation, shadowing and modulate by light color.
	Scale(lightResult, shadowAmount*light.m_colorIntensity.xyz);

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(DirectionalLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

// Description:
// Evaluate the lighting for a point light at the surface point.
// Arguments:
// light - The point light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(PointLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float3 surfaceToLight = light.m_position - geom.m_worldPosition;
	float vecLengthSqr = dot(surfaceToLight, surfaceToLight);
	float3 L = normalize(surfaceToLight);

	float atten = calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);

	PbrLightingResults lightResult;
	lightResult = EvaluateLightingPBR(L, V, mat, geom);

	// Distance attenuation, shadowing and modulate by light color.
	Scale(lightResult, shadowAmount*atten*light.m_colorIntensity.xyz);

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(PointLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

// Description:
// Evaluate the lighting for a spot light at the surface point.
// Arguments:
// light - The spot light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(SpotLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float3 surfaceToLight = light.m_position - geom.m_worldPosition;
	float vecLengthSqr = dot(surfaceToLight, surfaceToLight);
	float3 L = normalize(surfaceToLight);

	PbrLightingResults lightResult;
	ResetValid(lightResult);

	float angle = dot(L, light.m_direction);
	if(angle > light.m_spotAngles.w)
	{
		float atten = EvaluateSpotFalloff( angle, light.m_spotAngles.z, light.m_spotAngles.w );
		atten *= calculateAttenuationQuadratic(vecLengthSqr, light.m_attenuation);

		lightResult = EvaluateLightingPBR(L, V, mat, geom);

		// Distance attenuation, shadowing and modulate by light color.
		Scale(lightResult, shadowAmount*atten*light.m_colorIntensity.xyz);
	}

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(SpotLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

#ifdef EXTENDED_LIGHT_TYPES

// Description:
// Evaluate the lighting for an area disc light at the surface point.
// Arguments:
// light - The area disc light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(AreaDiscLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float linearRoughness = mat.m_linearRoughness;

	PbrLightingResults lightResult;

#ifdef USE_LTC_FOR_AREA_LIGHTS
	float roughness = linearRoughness * linearRoughness;

	bool twoSided = false;

	// Use LTC to evaluate the disc light.
	float2 coords = LTC_Coords(dot(geom.m_surfaceNormal, V), roughness);

	// Calculate the specular response.
	float3x3 SpecularMinv = LTC_Matrix(coords);
	float3 specular   = LTC_EvaluateDisc(geom.m_surfaceNormal, V, geom.m_worldPosition, SpecularMinv, light.m_position, light.m_direction, light.m_radius, twoSided);//, s_texFilteredMap);

	// apply BRDF scale terms (BRDF magnitude and Schlick Fresnel)
	float2 schlick = LTC_SampleAmp(coords).xy;
	specular *= mat.m_specularColor * schlick.x + (1.0 - mat.m_specularColor)*schlick.y;

	specular /= 2.0f * PBR_PI;					// normalize
	lightResult.m_specular = specular;			// set output
	lightResult.m_specularValidity = 1.0f;

	if (IsMetal(mat.m_metallicity))
	{
		lightResult.m_diffuse = float3(0,0,0);	// Specular only.
		lightResult.m_diffuseValidity = 0.0f;
	}
	else
	{
		// Calculate diffuse response.
		float3x3 DiffuseMinv = identity33(); // Identity matrix - diffuse response (untransformed cosine).
		float3 diffuse = LTC_EvaluateDisc(geom.m_surfaceNormal, V, geom.m_worldPosition, DiffuseMinv, light.m_position, light.m_direction, light.m_radius, twoSided);//, s_texFilteredMap);

		diffuse *= mat.m_albedo.xyz;			// scale by diffuse albedo
		diffuse /= 2.0f * PBR_PI;				// normalize
		lightResult.m_diffuse = diffuse;		// set output
		lightResult.m_diffuseValidity = 1.0f;
	}
#else //! USE_LTC_FOR_AREA_LIGHTS
	// Clamp linear roughness to >0.2 because specular maths falls part for glossy surfaces.
	linearRoughness = max(linearRoughness, 0.2f);

	float roughness = linearRoughness * linearRoughness;

	float3 nearestLightPos;
	float diffuseIllum = illuminateDiscLight(light.m_position, -light.m_direction, light.m_radius, geom.m_worldPosition, geom.m_surfaceNormal, nearestLightPos);
	float3 diffuseL = normalize(nearestLightPos - geom.m_worldPosition);

	// Calculate the reflection point and determine if it intersects the light.
	float3 R = Reflection(geom.m_surfaceNormal, V);						// Calculate reflection vector.

	// If ray starts behind the light there can be no specular.
	float3 adjustedRayOrigin = geom.m_worldPosition - light.m_position;
	if (dot(adjustedRayOrigin, light.m_direction) < 0)
	{
		float3 lightIntersectPt = closestPointInDisc(adjustedRayOrigin, R, light.m_radius, light.m_direction);
		lightIntersectPt += light.m_position;

		float3 surfaceToLight = lightIntersectPt - geom.m_worldPosition;
		float3 specularL = normalize(surfaceToLight);

		lightResult = EvaluateLightingPBR(diffuseL, specularL, V, mat, linearRoughness, geom);
	}
	else
	{
		lightResult = EvaluateDiffuseLightingPBR(diffuseL, V, mat, geom);
	}

	lightResult.m_diffuse *= diffuseIllum;								// Apply diffuse illumination.
#endif //! USE_LTC_FOR_AREA_LIGHTS

	Scale(lightResult, shadowAmount*light.m_colorIntensity.xyz);		// Shadowing and modulate by light color.

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(AreaDiscLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

// Description:
// Compute a representative disc for the sphere from the viewpoint specified.
// Arguments:
// discPos - The disc position (returned).
// discRad - The disc radius (returned).
// spherePos - The sphere position for which to compute the disc.
// sphereRad - The sphere radius for which to compute the disc.
// surfPos - The surface positoin being lit (hte viewpoint).
static void computeRepresentativeDiscForSphere(out float3 discPos, out float discRad, out float3 discDir, float3 spherePos, float sphereRad, float3 surfPos)
{
	float3 surfaceToLight = spherePos - surfPos;
	discDir = normalize(surfaceToLight);

	discPos = spherePos;
	discRad = sphereRad;
}

// Description:
// Evaluate the lighting for an area sphere light at the surface point.
// Arguments:
// light - The area sphere light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(AreaSphereLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float linearRoughness = mat.m_linearRoughness;

	PbrLightingResults lightResult;

#ifdef USE_LTC_FOR_AREA_LIGHTS
	// Build a representative disc based on lit point to sphere.
	float roughness = linearRoughness * linearRoughness;

	bool twoSided = true;

	// Use LTC to evaluate the disc light.
	float2 coords = LTC_Coords(dot(geom.m_surfaceNormal, V), roughness);

	// Place disc at horizon assuming infinite distance (ie, light radius).
	float3 discDirection, discPosition;
	float discRadius;
	computeRepresentativeDiscForSphere(discPosition, discRadius, discDirection, light.m_position, light.m_radius, geom.m_worldPosition);

	// Calculate the specular response.
	float3x3 SpecularMinv = LTC_Matrix(coords);
	float3 specular   = LTC_EvaluateDisc(geom.m_surfaceNormal, V, geom.m_worldPosition, SpecularMinv, discPosition, discDirection, discRadius, twoSided);//, s_texFilteredMap);

	// apply BRDF scale terms (BRDF magnitude and Schlick Fresnel)
	float2 schlick = LTC_SampleAmp(coords).xy;
	specular *= mat.m_specularColor * schlick.x + (1.0 - mat.m_specularColor)*schlick.y;

	specular /= 2.0f * PBR_PI;					// normalize
	lightResult.m_specular = specular;			// set output
	lightResult.m_specularValidity = 1.0f;

	if (IsMetal(mat.m_metallicity))
	{
		lightResult.m_diffuse = float3(0,0,0);	// Specular only.
		lightResult.m_diffuseValidity = 0.0f;
	}
	else
	{
		// Calculate diffuse response.
		float3x3 DiffuseMinv = identity33(); // Identity matrix - diffuse response (untransformed cosine).
		float3 diffuse = LTC_EvaluateDisc(geom.m_surfaceNormal, V, geom.m_worldPosition, DiffuseMinv, discPosition, discDirection, discRadius, twoSided);//, s_texFilteredMap);

		diffuse *= mat.m_albedo.xyz;			// scale by diffuse albedo
		diffuse /= 2.0f * PBR_PI;				// normalize
		lightResult.m_diffuse = diffuse;		// set output
		lightResult.m_diffuseValidity = 1.0f;
	}
#else //! USE_LTC_FOR_AREA_LIGHTS
	// Clamp linear roughness to >0.2 because specular maths falls part for glossy surfaces.
	linearRoughness = max(linearRoughness, 0.2f);

	float roughness = linearRoughness * linearRoughness;

	float3 nearestLightPos;
	float diffuseIllum = illuminateSphereLight(light.m_position, light.m_radius, geom.m_worldPosition, geom.m_surfaceNormal, nearestLightPos);
	float3 diffuseL = normalize(nearestLightPos - geom.m_worldPosition);

	// Calculate the reflection point and determine if it intersects the light.
	float3 R = Reflection(geom.m_surfaceNormal, V);						// Calculate reflection vector.

	float3 adjustedRayOrigin = geom.m_worldPosition - light.m_position;

	// Calculate closest point on sphere to reflection ray for representative point light.
	float3 lightIntersectPt = closestPointInSphere(adjustedRayOrigin, R, light.m_radius);
	lightIntersectPt += light.m_position;

	float3 surfaceToLight = lightIntersectPt - geom.m_worldPosition;
	float3 specularL = normalize(surfaceToLight);

	lightResult = EvaluateLightingPBR(diffuseL, specularL, V, mat, linearRoughness, geom);

	lightResult.m_diffuse *= diffuseIllum;							// Apply diffuse illumination.
#endif //! USE_LTC_FOR_AREA_LIGHTS

	Scale(lightResult, shadowAmount*light.m_colorIntensity.xyz);	// Shadowing and modulate by light color.

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(AreaSphereLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

// Description:
// Evaluate the lighting for an area rectangle light at the surface point.
// Arguments:
// light - The area rectangle light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(AreaRectangleLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float linearRoughness = mat.m_linearRoughness;

	PbrLightingResults lightResult;

#ifdef USE_LTC_FOR_AREA_LIGHTS
	float roughness = linearRoughness * linearRoughness;

	bool twoSided = false;
	float3 points[4];

	// Construct the quad for the light. Winding order defines the front by virtue of the contour integral giving a positive value for facing the lit point.
	float3 right = light.m_halfWidth;
	float3 up = light.m_halfHeight;
	points[0] = light.m_position - right - up;
	points[1] = light.m_position + right - up;
	points[2] = light.m_position + right + up;
	points[3] = light.m_position - right + up;

	// Use LTC to evaluate the rectangle light.
	float2 coords = LTC_Coords(dot(geom.m_surfaceNormal, V), roughness);

	// Calculate the specular response.
	float3x3 SpecularMinv = LTC_Matrix(coords);
	float3 specular   = LTC_EvaluateQuad(geom.m_surfaceNormal, V, geom.m_worldPosition, SpecularMinv, points, twoSided);//, s_texFilteredMap);

	// apply BRDF scale terms (BRDF magnitude and Schlick Fresnel)
	float2 schlick = LTC_SampleAmp(coords).xy;
	specular *= mat.m_specularColor * schlick.x + (1.0 - mat.m_specularColor)*schlick.y;

	specular /= 2.0f * PBR_PI;					// normalize
	lightResult.m_specular = specular;			// set output
	lightResult.m_specularValidity = 1.0f;

	if (IsMetal(mat.m_metallicity))
	{
		lightResult.m_diffuse = float3(0,0,0);	// Specular only.
		lightResult.m_diffuseValidity = 0.0f;
	}
	else
	{
		// Calculate diffuse response.
		float3x3 DiffuseMinv = identity33(); // Identity matrix - diffuse response (untransformed cosine).
		float3 diffuse = LTC_EvaluateQuad(geom.m_surfaceNormal, V, geom.m_worldPosition, DiffuseMinv, points, twoSided);//, s_texFilteredMap);

		diffuse *= mat.m_albedo.xyz;			// scale by diffuse albedo
		diffuse /= 2.0f * PBR_PI;				// normalize
		lightResult.m_diffuse = diffuse;		// set output
		lightResult.m_diffuseValidity = 1.0f;
	}
#else //! USE_LTC_FOR_AREA_LIGHTS

	// Clamp linear roughness to >0.2 because specular maths falls apart for glossy surfaces with [representative] point light sources
	linearRoughness = max(linearRoughness, 0.2f);

	float roughness = linearRoughness * linearRoughness;

	float3 nearestLightPos;
	float diffuseIllum = illuminateRectangleLight(light.m_position, -light.m_direction, light.m_halfWidth, light.m_halfHeight, geom.m_worldPosition, geom.m_surfaceNormal, nearestLightPos);

	float3 diffuseL = normalize(nearestLightPos - geom.m_worldPosition);

	// Calculate the reflection point and determine if it intersects the light.
	float3 R = Reflection(geom.m_surfaceNormal, V);						// Calculate reflection vector.

	// If ray starts behind the light there can be no specular.
	float3 adjustedRayOrigin = geom.m_worldPosition - light.m_position;
	if (dot(adjustedRayOrigin, light.m_direction) < 0)
	{
		float3 lightIntersectPt = closestPointInRect(adjustedRayOrigin, R, light.m_halfWidth, light.m_halfHeight, light.m_direction);
		lightIntersectPt += light.m_position;

		float3 surfaceToLight = lightIntersectPt - geom.m_worldPosition;
		float3 specularL = normalize(surfaceToLight);

		lightResult = EvaluateLightingPBR(diffuseL, specularL, V, mat, linearRoughness, geom);
	}
	else
	{
		lightResult = EvaluateDiffuseLightingPBR(diffuseL, V, mat, geom);
	}

	lightResult.m_diffuse *= diffuseIllum;							// Apply diffuse illumination.
#endif //! USE_LTC_FOR_AREA_LIGHTS

	// Distance attenuation, shadowing and modulate by light color.
	Scale(lightResult, shadowAmount*light.m_colorIntensity.xyz);

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(AreaRectangleLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

// Description:
// Evaluate the lighting for an area tube light at the surface point.
// Arguments:
// light - The area tube light with which to light.
// V - The view vector.
// shadowAmount - The calculated shadow factor.
// mat - The material properties at the surface point.
// geom - The geometry properties at the surface point.
// Returns:
// The specular and diffuse lighting results.
static PbrLightingResults EvaluateLightPBR(AreaTubeLight light, float3 V, float shadowAmount, PbrMaterialProperties mat, PbrGeomProperties geom)
{
	float linearRoughness = mat.m_linearRoughness;

	PbrLightingResults lightResult;

#ifdef USE_LTC_FOR_AREA_LIGHTS
	float roughness = linearRoughness * linearRoughness;

	bool twoSided = true;

	// Use LTC to evaluate the disc light.
	float2 coords = LTC_Coords(dot(geom.m_surfaceNormal, V), roughness);

	// Build representative planar shape for the capsule. This will be a rectangle with two semicircular caps, oriented toward the fragment being lit.
	float3 surfaceToLight = light.m_position - geom.m_worldPosition;

	// Build axis of light. In case of no axis (zero width) we should ensure that this lies in the plane perpendicular to the surface to light vector.
	float3 along = float3(0, 0, 0);								// Arbitrary until we know orientation.
	float halfWidthMag2 = dot(light.m_halfWidth, light.m_halfWidth);
	if (halfWidthMag2 > 0.0f)
	{
		along = normalize(light.m_halfWidth);
	}
	else
	{
		// Build arbitrary perpendicular to surfaceToLightVector.
		float3 upVector = abs(surfaceToLight.z) < 0.999 ? float3(0,0,1) : float3(1,0,0);

		along = normalize(cross(upVector, surfaceToLight));
	}

	float3 across = normalize(cross(surfaceToLight, along));

	// We have a capsule profile and orientation we can light with.
	// Calculate the specular response.
	float3x3 SpecularMinv = LTC_Matrix(coords);
	float3 specular   = LTC_EvaluateCapsule(geom.m_surfaceNormal, V, geom.m_worldPosition, SpecularMinv, light.m_position, light.m_halfWidth, light.m_radius, along, across, twoSided);//, s_texFilteredMap);

	// apply BRDF scale terms (BRDF magnitude and Schlick Fresnel)
	float2 schlick = LTC_SampleAmp(coords).xy;
	specular *= mat.m_specularColor * schlick.x + (1.0 - mat.m_specularColor)*schlick.y;

	specular /= 2.0f * PBR_PI;					// normalize
	lightResult.m_specular = specular;			// set output
	lightResult.m_specularValidity = 1.0f;

	if (IsMetal(mat.m_metallicity))
	{
		lightResult.m_diffuse = float3(0,0,0);	// Specular only.
		lightResult.m_diffuseValidity = 0.0f;
	}
	else
	{
		// Calculate diffuse response.
		float3x3 DiffuseMinv = identity33(); // Identity matrix - diffuse response (untransformed cosine).
		float3 diffuse = LTC_EvaluateCapsule(geom.m_surfaceNormal, V, geom.m_worldPosition, DiffuseMinv, light.m_position, light.m_halfWidth, light.m_radius, along, across, twoSided);//, s_texFilteredMap);

		diffuse *= mat.m_albedo.xyz;			// scale by diffuse albedo
		diffuse /= 2.0f * PBR_PI;				// normalize
		lightResult.m_diffuse = diffuse;		// set output
		lightResult.m_diffuseValidity = 1.0f;
	}
#else //! USE_LTC_FOR_AREA_LIGHTS
	// Clamp linear roughness to >0.2 because specular maths falls part for glossy surfaces.
	linearRoughness = max(linearRoughness, 0.2f);

	float roughness = linearRoughness * linearRoughness;

	float3 nearestLightPos;
	float diffuseIllum = illuminateTubeLight(light.m_position, light.m_halfWidth, light.m_radius, geom.m_worldPosition, geom.m_surfaceNormal, nearestLightPos);
	float3 diffuseL = normalize(nearestLightPos - geom.m_worldPosition);

	// Calculate the reflection point and determine if it intersects the light.
	float3 R = Reflection(geom.m_surfaceNormal, V);						// Calculate reflection vector.

	float3 adjustedRayOrigin = geom.m_worldPosition - light.m_position;

	// Calculate closest point on tube to reflection ray for representative point light.
	float3 lightIntersectPt = closestPointInTube(adjustedRayOrigin, R, light.m_halfWidth, light.m_radius);
	lightIntersectPt += light.m_position;

	float3 surfaceToLight = lightIntersectPt - geom.m_worldPosition;
	float3 specularL = normalize(surfaceToLight);

	lightResult = EvaluateLightingPBR(diffuseL, specularL, V, mat, linearRoughness, geom);

	lightResult.m_diffuse *= diffuseIllum;							// Apply diffuse illumination.
#endif //! USE_LTC_FOR_AREA_LIGHTS

	// Distance attenuation, shadowing and modulate by light color.
	Scale(lightResult, shadowAmount*light.m_colorIntensity.xyz);

	return lightResult;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(AreaTubeLight light, inout PbrLightingResults direct, PbrLightingResults ibl, PbrLightingResults toAdd)
{
	direct.m_diffuse += toAdd.m_diffuse;
	direct.m_specular += toAdd.m_specular;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(LocalLightProbe light, PbrLightingResults direct, inout PbrLightingResults ibl, PbrLightingResults toAdd)
{
	// We blend in the results using the validity already in the ibl results.
	// We evaluate from local->global - if local has provided 100% validity then global is not needed.
	float newDiffuseValid = min(1.0f-ibl.m_diffuseValidity, toAdd.m_diffuseValidity);
	float newSpecularValid = min(1.0f-ibl.m_specularValidity, toAdd.m_specularValidity);
	ibl.m_diffuse += (toAdd.m_diffuse * newDiffuseValid);
	ibl.m_specular += (toAdd.m_specular * newSpecularValid);
	ibl.m_diffuseValidity += newDiffuseValid;
	ibl.m_specularValidity += newSpecularValid;
}

// Description:
// Accumulate lighting from lighting results.
// Arguments:
// light - The light type to accumulate for. This selects an overload to control how accumulation occurs.
// direct - The PbrLightingResults object for direct lighting to accumulate into.
// ibl - The PbrLightingResults object for image based lighting to accumulate into.
// toAdd - The lighting result from which to accumulate the lighting result.
void Accumulate(GlobalLightProbe light, PbrLightingResults direct, inout PbrLightingResults ibl, PbrLightingResults toAdd)
{
	// We blend in the results using the validity already in the ibl results.
	// We evaluate from local->global - if local has provided 100% validity then global is not needed.
	float newDiffuseValid = 1.0f-ibl.m_diffuseValidity;			// Fill remaining validity from global light probe.
	float newSpecularValid = 1.0f-ibl.m_specularValidity;		// Fill remaining validity from global light probe.
	ibl.m_diffuse += (toAdd.m_diffuse * newDiffuseValid);
	ibl.m_specular += (toAdd.m_specular * newSpecularValid);
	ibl.m_diffuseValidity = 1.0f;				// Global light probe has the last say - evaluated last.
	ibl.m_specularValidity = 1.0f;				// Global light probe has the last say - evaluated last.
}

#endif // EXTENDED_LIGHT_TYPES

#endif //! PHYRE_PBR_SHARED_H
