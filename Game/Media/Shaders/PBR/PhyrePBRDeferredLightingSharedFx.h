/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_PBR_DEFERRED_LIGHTING_SHARED_FX_H
#define PHYRE_PBR_DEFERRED_LIGHTING_SHARED_FX_H

///////////////////////
// Utility functions //
///////////////////////

// Description:
// Reconstruct the world position using the screen position and depth buffer value.
// Arguments:
// pixelPos - The pixel position for which to get the world position.
// Returns:
// The reconstructed world position.
float3 GetWorldPosition(float2 pixelPos)
{
	float zvalue = DepthBuffer.Load(int3(pixelPos.xy, 0));
	float viewSpaceDepth = ConvertDepth(zvalue);

	// Pull dimensions from the depth buffer for calculating the uv in the depth buffer.
	uint screenWidth, screenHeight;
	DepthBuffer.GetDimensionsFast(screenWidth, screenHeight);
	float2 invScreenWidthHeight = float2(1.0f/screenWidth, 1.0f/screenHeight);

	float2 uv = pixelPos.xy * invScreenWidthHeight;
	float2 screenPos = GetScreenPosition(uv);

#ifdef ORTHO_CAMERA
	float4 viewPos = float4(screenPos * InvProjXY.xy, -viewSpaceDepth, 1);
#else //! ORTHO_CAMERA
	float4 viewPos = float4(screenPos * InvProjXY.xy * viewSpaceDepth, -viewSpaceDepth, 1);
#endif //! ORTHO_CAMERA

	float3 worldPosition = mul(viewPos, ViewInverse).xyz;

	return worldPosition;
}

// Description:
// Initialize the material properties from the GBuffers.
// Arguments:
// mat - The material state to initialize.
// geom - The geometry state to initialize.
// pixelPos - The pixel position for which to initialize.
// zvalue - The Z value to initialize with.
// Return Value List:
// true - The pixel is valid and needs lighting.
// false - The pixel is not valid and doesn't need lighting.
static bool InitializeWithDepth(out PbrMaterialProperties mat, out PbrGeomProperties geom, float2 pixelPos, float zvalue)
{
	mat.m_linearRoughness = 0;
	mat.m_viewDependentRoughnessStrength = 0;
	mat.m_metallicity = 0;
	mat.m_cavity = 0;
	mat.m_specularColor = float3(0,0,0);
	mat.m_albedo = float4(0,0,0,0);

	geom.m_worldPosition = float3(0,0,0);
	geom.m_geometricNormal = float3(0,0,0);
	geom.m_surfaceNormal = float3(0,0,0);
	geom.m_viewDepth = 0;

	if(!IsValidDepth(zvalue))
		return false;

	float4 gbuffer_color = ColorBuffer.Load(int3(pixelPos.xy, 0));
	float4 gbuffer_normalDepth = NormalDepthBuffer.Load(int3(pixelPos.xy, 0));
	float4 gbuffer_specularRough = SpecularRoughBuffer.Load(int3(pixelPos.xy, 0));

	// Valid test for pixel is that the normal is valid.  0,0,0 is an invalid normal of -1,-1,-1.
	if (dot(gbuffer_normalDepth.xyz, gbuffer_normalDepth.xyz) < 0.05f)
		return false;

	// Transform normal from view space to world space.
	float3 gbufferSpaceNormal = unpackOctToFloat3(bx2Unpack(gbuffer_normalDepth.xy));
	float3 worldNormal = normalize(Normal_GBufferSpaceToWorldSpace(gbufferSpaceNormal));

	mat.m_linearRoughness = gbuffer_specularRough.w;
	mat.m_viewDependentRoughnessStrength = gbuffer_normalDepth.z;
	float3 d = DIELECTRIC_SPECULAR - gbuffer_specularRough.xyz;
	if (dot(d,d) > 0.05f)
		mat.m_metallicity = 1.0f;										// Specular is significantly different from dielectric specular - it's a metallic material.
	else
		mat.m_metallicity = 0.0f;										// Specular is same as dielectric specular - it's a dielectric material.
	mat.m_cavity = gbuffer_color.w;										// Cavity is rolled together with AO.
	mat.m_specularColor = gbuffer_specularRough.xyz;
	mat.m_albedo = float4(gbuffer_color.xyz, 1.0f);

	geom.m_worldPosition = GetWorldPosition(pixelPos);
	geom.m_geometricNormal = worldNormal;
	geom.m_surfaceNormal = worldNormal;
	geom.m_viewDepth = gbuffer_normalDepth.w;

	return true;
}

// Description:
// Initialize the material properties from the GBuffers.
// Arguments:
// mat - The material state to initialize.
// geom - The geometry state to initialize.
// pixelPos - The screen position for which to initialize.
// Return Value List:
// true - The pixel is valid and needs lighting.
// false - The pixel is not valid and doesn't need lighting.
static bool Initialize(out PbrMaterialProperties mat, out PbrGeomProperties geom, float2 pixelPos)
{
	float zvalue = DepthBuffer.Load(int3(pixelPos.xy, 0));

	return InitializeWithDepth(mat, geom, pixelPos, zvalue);
}

#endif //! PHYRE_PBR_DEFERRED_LIGHTING_SHARED_FX_H
