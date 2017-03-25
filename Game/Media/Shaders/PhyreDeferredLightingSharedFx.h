/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_DEFERRED_LIGHTING_SHARED_FX_H
#define PHYRE_DEFERRED_LIGHTING_SHARED_FX_H

/////////////
// Defines //
/////////////

#ifdef PACK_LIGHT_INDICES
	#define PE_MAX_ACTIVE_LIGHTS (128/4)
#else // PACK_LIGHT_INDICES
	#define PE_MAX_ACTIVE_LIGHTS 128
#endif //PACK_LIGHT_INDICES

// Tile size: 8 pixels
#define PE_DEFERRED_TILE_SIZE_SHIFT 3
#define PE_DEFERRED_TILE_SIZE (1<<PE_DEFERRED_TILE_SIZE_SHIFT)

///////////
// Types //
///////////

// Description:
// The range of Z values for a tile.
struct ZRange
{
	float2		unprojtileMinMax;		// The Z range in the platforms Z space.

#ifdef __ORBIS__
	uint		htile;					// HTile value for the group.
#else // __ORBIS__
	float		zvalue;					// The Z value for this pixel.
#endif // __ORBIS__
};

//////////////////
// Data storage //
//////////////////

//! The list of light indices to process.
groupshared uint NumLightsActive;
groupshared uint ActiveLightIndices[PE_MAX_ACTIVE_LIGHTS * 2];	// Spots then points

//! The list of fragment indices to process.
groupshared uint FragsToDo;
groupshared uint FragsToDoList[(PE_DEFERRED_TILE_SIZE * PE_DEFERRED_TILE_SIZE * 3 + 64) / 2]; // Store a tile's worth of fragments plus upto 64 from last tile. Note will pack as 16 bit values

///////////////
// Functions //
///////////////

// Description:
// Append a light index to the active lights.
// Arguments:
// index - The index of the light to add.
void AddLight(uint index)
{
	uint listIndex;
	InterlockedAdd(NumLightsActive, uint(1), listIndex);
	if (listIndex < PE_MAX_ACTIVE_LIGHTS * 2)
	{
#ifdef PACK_LIGHT_INDICES

		if ((listIndex & 0x3) == 0)
			ActiveLightIndices[listIndex / 4] = index;

		GroupMemoryBarrier(); // Should be removed by the compiler on PS4, but acts as a compiler barrier to ensure that initial write completes

		if (listIndex & 0x3)
		{
			uint shift = 8 * (listIndex & 0x3);
			InterlockedOr(ActiveLightIndices[listIndex / 4], index << shift);
		}

#else // PACK_LIGHT_INDICES

		ActiveLightIndices[listIndex] = index;

#endif // PACK_LIGHT_INDICES
	}
}

// Description:
// Get a light index from the active lights.
// Arguments:
// listIndex - The index in the active light list to get.
// Returns:
// The light index.
uint GetLightIndex(uint listIndex)
{
#ifdef PACK_LIGHT_INDICES

	uint shift = 8 * (listIndex & 0x3);
	uint indices = ActiveLightIndices[listIndex/4];
	return (indices >> shift) & 0xFF;

#else // PACK_LIGHT_INDICES

	return ActiveLightIndices[listIndex];

#endif // PACK_LIGHT_INDICES
}

// Description:
// Add a fragment to the list of fragments to process.
// Arguments:
// fragment - The index of the fragment to add to the process list.
void AddFragmentToProcess(uint fragment)
{
	uint listIndex;
	InterlockedAdd(FragsToDo, uint(1), listIndex);
	if ((listIndex & 0x1) == 0)
		FragsToDoList[listIndex / 2] = fragment;
	GroupMemoryBarrier(); // Should be removed by the compiler on PS4, but acts as a compiler barrier to ensure that initial write completes
	if (listIndex & 0x1)
		InterlockedOr(FragsToDoList[listIndex / 2], fragment << 16);
}

// Description:
// Get a fragment from the list of fragments to process.
// Arguments:
// index - The index of the fragment to get.
// Returns:
// The fragment to process.
uint GetFragmentToProcess(uint index)
{
	uint val = FragsToDoList[index / 2];
	uint shift = (index & 1) * 16;
	return val >> shift; // Note no mask since we'll mask out the elements
}

// Description:
// Test if a depth value is valid.  Valid values lie in front of the far clip plane.
// Arguments:
// zvalue - The depth value to test for validity.
// Return Value List:
// true - The depth value is valid.
// false - The depth value is not valid.
bool IsValidDepth(float zvalue)
{
	return zvalue < 1.0f;
}

// Description:
// Convert a depth value from post projection space to view space.
// Assumes the depth is in a 0-1 range.
// Arguments:
// depth - The post projection depth to convert.
// Returns:
// The converted view space depth.
float ConvertDepth(float depth)
{	
#ifdef ORTHO_CAMERA
	float viewSpaceZ = -(depth * cameraFarMinusNear + cameraNearFar.x);
#else //! ORTHO_CAMERA
	float viewSpaceZ = -(cameraNearTimesFar / (depth * cameraFarMinusNear - cameraNearFar.y));
#endif //! ORTHO_CAMERA
	return viewSpaceZ;
}

// Description:
// Convert a depth value from post projection space to view space using Inverse Projection Matrix.
// Assumes the depth is in the output range for the platform. Eg 0-1 on D3D11, +-1 on GNM.
// Arguments:
// depth - The post projection depth to convert.
// Returns:
// The converted view space depth.
float ConvertDepthFullProjection(float depth)
{
	float viewSpaceZ = 1.0f / (depth * ProjInverse._34 + ProjInverse._44);
	return viewSpaceZ;
}

// Description:
// Convert a texture UV to screen space position.
// Arguments:
// uv - The input texture coordinate to convert (0 -> 1).
// Returns:
// The screen position (-1 -> 1).
float2 GetScreenPosition(float2 uv)
{
#ifdef __ORBIS__
	float2 screenPos = float2(uv.xy) * 2.0f - 1.0f;
#else //! __ORBIS__
	float2 screenPos = float2(uv.x,1.0f-uv.y) * 2.0f - 1.0f;
#endif //! __ORBIS__
	return screenPos;
}

// Description:
// Extract the shadow value from the shadow results.
// Arguments:
// mask - The mask for which to extract the shadow value.
// shadowResults - The shadow results from which to extract the shadow value.
// Returns:
// The extracted shadow value.
float CalculateShadow(float4 mask, float4 shadowResults)
{
#ifdef DEFERRED_SHADOWS
	float shadowBufferValue = dot(shadowResults, mask);
	shadowBufferValue += saturate(1.0f - dot(mask, 1.0f));
#else // DEFERRED_SHADOWS
	float shadowBufferValue = 1.0f;
#endif // DEFERRED_SHADOWS
	return shadowBufferValue;
}

// Description:
// Test if a cone intersects a plane.
// Arguments:
// planeEq - The plane equation (normal + distance) of the plane with which to test.
// lightPosition - The position of the light (point of the cone).
// spotDir - The direction of the spot light cone.
// lightRadius - The height of the cone/radius of the light.
// coneBaseRadius - The radius of the cone at its base.
// Return Value List:
// true - The cone and plane intersect.
// false - The cone and plane do not intersect.
bool ConePlaneTest(float4 planeEq, float3 lightPosition, float3 spotDir, float lightRadius, float coneBaseRadius)
{
	// Either light position is in front of plane
	float dp0 = dot(float4(lightPosition, 1.0f), planeEq);

	// Or far point on cone projected through plane is
	float3 q = lightPosition + spotDir * lightRadius + planeEq.xyz * coneBaseRadius;
	float dp1 = dot(float4(q,1.0f), planeEq);

	bool rslt = dp0 >= 0.0f || dp1 >= 0.0f;
	return rslt;
}

// Description:
// Test a spot light cone against a view frustum for visibility determination.
// Arguments:
// lightPosition - The position of the light (point of the cone).
// spotDir - The direction of the spot light cone.
// lightRadius - The height of the cone/radius of the light.
// coneBaseRadius - The radius of the cone at its base.
// frustumPlanes - The frustum planes against which to test for visibility.
// Return Value List:
// true - The light lies at least partially within the frustum.
// false - The light lies entirely outside of the frustum.
bool IsSpotLightVisible(float3 lightPosition, float3 spotDir, float lightRadius, float coneBaseRadius, float4 frustumPlanes[6])
{
	bool inFrustum = true;
#ifndef __ORBIS__
	[unroll]
#endif //! __ORBIS__
	for (uint i = 0; i < 6; ++i) 
	{
		bool d = ConePlaneTest(frustumPlanes[i], lightPosition, spotDir, lightRadius, coneBaseRadius);
		inFrustum = inFrustum && d;
	}
	return inFrustum;
}

// Description:
// Test a point light against a view frustum for visibility determination.
// Arguments:
// lightPosition - The position of the light (centre of the sphere).
// lightRadius - The radius of the light sphere.
// frustumPlanes - The frustum planes against which to test for visibility.
// Return Value List:
// true - The light lies at least partially within the frustum.
// false - The light lies entirely outside of the frustum.
bool IsPointLightVisible(float3 lightPosition, float lightRadius, float4 frustumPlanes[6])
{
	bool inFrustum = true;
#ifndef __ORBIS__
	[unroll]
#endif //! __ORBIS__
	for (uint i = 0; i < 6; ++i) 
	{
		float d = dot(frustumPlanes[i], float4(lightPosition, 1.0f));
		inFrustum = inFrustum && (d >= -lightRadius);
	}
	return inFrustum;
}

// Description:
// Convert a tile index to a screen position.
// Arguments:
// tileLocation - The index of the tile.
// invScreenWidthHeight - The width of the screen.
// screenHeight - The height of the screen.
// Returns:
// The screen position of the tile.
float2 TileToScreenXY(uint2 tileLocation, float2 invScreenWidthHeight)
{
	uint2 p = PE_DEFERRED_TILE_SIZE*tileLocation;
	return (float2(p) * invScreenWidthHeight) * 2 - 1;
}

// Description:
// Create plane equation for plane containing origin and points b and c.
// Arguments:
// b - The second point on the plane.
// c - The third point on the plane.
// Returns:
// The plane equation containing the origin, point b and point c.
float4 CreatePlaneEquation(float4 b,float4 c)
{
	return float4(normalize(cross(b.xyz, c.xyz)), 0.0f);
}

// Description:
// Pack a float4 into 4 half floats in a uint2.
// Arguments:
// input - The input floats.
// Returns:
// The packed half floats.
uint2 PackF32ToF16(float4 input)
{
	uint2 halves = f32tof16(input.xy) | (f32tof16(float2(input.zw)) << 16);
	return halves;
}

// Description:
// Unpack 4 half floats in a uint2 to a float4.
// Arguments:
// input  - The input half floats.
// Returns:
// The unpacked floats.
float4 UnpackF16ToF32(uint2 input)
{
	float4 floats = float4(f16tof32(input), f16tof32(input >> 16));
	return floats;
}

// Description:
// Test for intersection between a sphere and a cone.
// Based on http://www.cbloom.com/3d/techdocs/culling.txt
// Arguments:
// sphere - The center and radius of the sphere.
// coneOrigin - The point of the cone.
// coneDirection - The direction of the cone.
// coneCosAngle - The cosine of the cone angle.
// coneTanAngle - The tangent of the cone angle.
// Return Value List:
// true - The cone and sphere do intersect.
// false - The cone and sphere do not intersect.
bool SphereIntersectsCone(float4 sphere, float3 coneOrigin, float3 coneDirection, float coneCosAngle, float coneTanAngle)
{
	float3 v = sphere.xyz - coneOrigin;
	float a = dot(v, coneDirection);
	float b = a * coneTanAngle;
	float c = sqrt(dot(v, v) - (a*a));
	float d = c - b;
	float e = d * coneCosAngle;
	return e <= sphere.w;
}

// Description:
// Test for intersection between a sphere and a sphere.
// Arguments:
// sphere - The first sphere's center and radius.
// other - The second sphere's center.
// otherRadius - The second sphere's radius.
// Return Value List:
// true - The spheres do intersect.
// false - The spheres do not intersect.
bool SphereIntersectsSphere(float4 sphere, float3 other, float otherRadius)
{
	float3 d = sphere.xyz - other;
	float radiiSum = sphere.w + otherRadius;
	return dot(d, d) < (radiiSum * radiiSum);
}

// Description:
// Get the index of the next set LSB and remove it from the mask.
// Arguments:
// sampleRequiredMask - The mask to find the set LSB and remove the bit from. The set LSB is reset by this function.
// Returns:
// The index of the set LSB.
uint ConsumeNextBitFromMask(inout uint sampleRequiredMask)
{
	uint next = firstbitlow(sampleRequiredMask);
	sampleRequiredMask ^= (0x1 << next);
	return next;
}

// Description:
// Calculate the min/max of the absolute values.
// Arguments:
// a - The first value.
// b - The second value.
// Returns:
// A float2 with value with minimum magnitude in x and the value with maximum magnitude in y.
float2 MinMaxAbs(float a, float b)
{
	if (abs(a) > abs(b))
		return float2(b, a);
	return float2(a, b);
}

// Description:
// Unproject a point in Projection Space to View Space.
// Unrolled since matrix is sparse and assumes row major when indexing
// Arguments:
// p - The projection space point to convert.
// Returns:
// The view space point.
float4 ConvertProjToView(float4 p)
{
	float4 v;
	v.x = ProjInverse[0][0] * p.x + ProjInverse[3][0]; // Note [3][0] is for VR only, it will be zero on non-VR
	v.y = ProjInverse[1][1] * p.y + ProjInverse[3][1]; // Note [3][1] is for OpenVR only it will be zero on non-VR and PS VR.
	v.z = ProjInverse[3][2] * p.w;
	v.w = p.z * ProjInverse[2][3] + p.w * ProjInverse[3][3];
	v /= v.w;

	return v;
}

// Description:
// Generate the frustum planes for the specified tile.
// Arguments:
// frustumPlanes - The frustum planes returned.
// tileLocation - The position of the tile for which to generate the frustum planes.
// tileMinMax - The minimum and maximum depth values for the tile.
// sphere - The bounding sphere for the generated frustum (for fast rejection).
// unprojtileMinMax - The post projection space minimum and maximum depth.
// screenWidth - The width of the screen.
// screenHeight - The height of the screen.
void GenerateFrustumPlanes(out float4 frustumPlanes[6], uint2 tileLocation, float2 tileMinMax, out float4 sphere, float2 unprojtileMinMax, uint screenWidth, uint screenHeight)
{
	uint2 numTilesXY = uint2(screenWidth+(PE_DEFERRED_TILE_SIZE-1), screenHeight+(PE_DEFERRED_TILE_SIZE-1)) >> PE_DEFERRED_TILE_SIZE_SHIFT;
	float2 invScreenWidthHeight = float2(1.0f/screenWidth, 1.0f/screenHeight);

#ifdef __ORBIS__
	tileLocation.y = numTilesXY.y - tileLocation.y;
#endif //! __ORBIS__

#ifndef DEFERRED_VR

	float2 tileScale = float2(numTilesXY)* 0.5f;
	float2 tileBias = tileScale - float2(tileLocation.xy);

	float2 tl = TileToScreenXY(tileLocation, invScreenWidthHeight);
	float2 br = TileToScreenXY(tileLocation + uint2(1, 1), invScreenWidthHeight);
	tl.y = -tl.y;
	br.y = -br.y; 

	float4 cx = float4(-Projection[0].x * tileScale.x, 0.0f, tileBias.x, 0.0f);
	float4 cy = float4(0.0f, Projection[1].y * tileScale.y, tileBias.y, 0.0f);
	float4 cw = float4(0.0f, 0.0f, -1.0f, 0.0f);

	frustumPlanes[0] = cw - cx;		// left
	frustumPlanes[1] = cw + cx;		// right
	frustumPlanes[2] = cw - cy;		// bottom
	frustumPlanes[3] = cw + cy;		// top
	frustumPlanes[4] = float4(0.0f, 0.0f, -1.0f, -tileMinMax.x);	// near
	frustumPlanes[5] = float4(0.0f, 0.0f, 1.0f, tileMinMax.y);	// far

	[unroll] for (uint i = 0; i < 4; ++i)
	{
		frustumPlanes[i] *= rcp(length(frustumPlanes[i].xyz));
	}
#else //! DEFERRED_VR

	tileLocation.y = numTilesXY.y - tileLocation.y;
	float2 tl = TileToScreenXY(tileLocation, invScreenWidthHeight);
	float2 br = TileToScreenXY(tileLocation + uint2(1, 1), invScreenWidthHeight);

	{   // construct frustum for this tile
		float2 tr = float2(br.x, tl.y);
		float2 bl = float2(tl.x, br.y);

		// four corners of the view plane tile, clockwise from top-left
		float4 frustum[4];
		frustum[0] = ConvertProjToView(float4(tl, 1.0f, 1.0f));
		frustum[1] = ConvertProjToView(float4(tr, 1.0f, 1.0f));
		frustum[2] = ConvertProjToView(float4(br, 1.0f, 1.0f));
		frustum[3] = ConvertProjToView(float4(bl, 1.0f, 1.0f));

		for(uint i=0; i<4; i++)
			frustumPlanes[i] = CreatePlaneEquation( frustum[i], frustum[(i+1)&3] );
		frustumPlanes[4] = float4(0.0f, 0.0f, -1.0f, -tileMinMax.x);	// near
		frustumPlanes[5] = float4(0.0f, 0.0f, 1.0f, tileMinMax.y);		// far
	}
#endif //! DEFERRED_VR

	float2 minmaxX = MinMaxAbs(br.x, tl.x);
	float2 minmaxY = MinMaxAbs(br.y, tl.y);

	float3 minPoint = ConvertProjToView(float4(minmaxX.x, minmaxY.x, unprojtileMinMax.x, 1.0f)).xyz;
	float3 maxPoint = ConvertProjToView(float4(minmaxX.y, minmaxY.y, unprojtileMinMax.y, 1.0f)).xyz;

	sphere.xyz = 0.5f * (minPoint + maxPoint);
	sphere.w = length(maxPoint - minPoint) * 0.5f;
}

// Description:
// Generate the frustum vertices for the specified tile.
// Arguments:
// frustumVerts - The frustum planes returned.
// tileLocation - The position of the tile for which to generate the frustum planes.
// unprojtileMinMax - The post projection space minimum and maximum depth.
// screenWidth - The width of the screen.
// screenHeight - The height of the screen.
void GenerateFrustumVerts(out float3 frustumVerts[8], uint2 tileLocation, float2 unprojtileMinMax, uint screenWidth, uint screenHeight)
{
	uint2 numTilesXY = uint2(screenWidth+(PE_DEFERRED_TILE_SIZE-1), screenHeight+(PE_DEFERRED_TILE_SIZE-1)) >> PE_DEFERRED_TILE_SIZE_SHIFT;
	float2 invScreenWidthHeight = float2(1.0f/screenWidth, 1.0f/screenHeight);

#ifdef __ORBIS__
	tileLocation.y = numTilesXY.y - tileLocation.y;
#endif //! __ORBIS__

	float2 tl = TileToScreenXY(tileLocation, invScreenWidthHeight);
	float2 br = TileToScreenXY(tileLocation + uint2(1, 1), invScreenWidthHeight);
	tl.y = -tl.y;
	br.y = -br.y; 

	float2 minmaxX = MinMaxAbs(br.x, tl.x);
	float2 minmaxY = MinMaxAbs(br.y, tl.y);

	// Eight corners of the view frustum.
	frustumVerts[0] = ConvertProjToView(float4(minmaxX.x, minmaxY.x, unprojtileMinMax.x, 1.0f)).xyz;		// MinX, MinY, MinZ
	frustumVerts[1] = ConvertProjToView(float4(minmaxX.y, minmaxY.x, unprojtileMinMax.x, 1.0f)).xyz;		// MaxX, minY, minZ
	frustumVerts[2] = ConvertProjToView(float4(minmaxX.x, minmaxY.y, unprojtileMinMax.x, 1.0f)).xyz;		// MinX, MaxY, MinZ
	frustumVerts[3] = ConvertProjToView(float4(minmaxX.y, minmaxY.y, unprojtileMinMax.x, 1.0f)).xyz;		// MaxX, maxY, minZ
	frustumVerts[4] = ConvertProjToView(float4(minmaxX.x, minmaxY.x, unprojtileMinMax.y, 1.0f)).xyz;		// MinX, MinY, MaxZ
	frustumVerts[5] = ConvertProjToView(float4(minmaxX.y, minmaxY.x, unprojtileMinMax.y, 1.0f)).xyz;		// MaxX, minY, maxZ
	frustumVerts[6] = ConvertProjToView(float4(minmaxX.x, minmaxY.y, unprojtileMinMax.y, 1.0f)).xyz;		// MinX, MaxY, MaxZ
	frustumVerts[7] = ConvertProjToView(float4(minmaxX.y, minmaxY.y, unprojtileMinMax.y, 1.0f)).xyz;		// MaxX, maxY, maxZ
}

// Description:
// Cull the frustum against the specified plane.
// Arguments:
// planeNormal - The normal of the plane against which to cull.
// pointOnPlane - A point of the plane.
// frustumVerts - The vertices of the frustum to cull.
// Return Value List:
// true - At least one of the frustum vertices is visible.
// false - All of the frustum vertices are behind the plane.
bool IsFrustumVisibleAgainstPlane(float3 planeNormal, float3 pointOnPlane, float3 frustumVerts[8])
{
	planeNormal = normalize(planeNormal);
	float4 plane = float4(planeNormal, -dot(planeNormal, pointOnPlane));

	float maxDist = dot(plane, float4(frustumVerts[0], 1.0f));
	for (uint i=1; i<8; i++)
		maxDist = max(maxDist, dot(plane, float4(frustumVerts[i], 1.0f)));
	return (maxDist > 0.0f);
}

#endif //! PHYRE_DEFERRED_LIGHTING_SHARED_FX_H
