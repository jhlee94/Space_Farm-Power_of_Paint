/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_LINEAR_TRANSFORMED_COSINES_H
#define PHYRE_LINEAR_TRANSFORMED_COSINES_H

// Copyright 2010-2016 Branimir Karadzic. All rights reserved.
// 
// https://github.com/bkaradzic/bgfx
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
//    1. Redistributions of source code must retain the above copyright notice, this
//       list of conditions and the following disclaimer.
// 
//    2. Redistributions in binary form must reproduce the above copyright notice,
//       this list of conditions and the following disclaimer in the documentation
//       and/or other materials provided with the distribution.
// 
// THIS SOFTWARE IS PROVIDED BY COPYRIGHT HOLDER ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
// SHALL COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
// OF THE POSSIBILITY OF SUCH DAMAGE.
//
// https://github.com/bkaradzic/bgfx/blob/master/LICENSE

float4 LTC_SampleAmp(float2 coord);
float4 LTC_SampleMat(float2 coord);

// -------------------------------------------------------------------------------------------------

// Description:
// Transpose a 3x3 matrix.
// Arguments:
// v - The matrix to transpose.
// Returns:
// The transposed matrix.
float3x3 transposeFloat3x3(float3x3 v)
{
    float3x3 tmp;
    tmp[0] = float3(v[0].x, v[1].x, v[2].x);
    tmp[1] = float3(v[0].y, v[1].y, v[2].y);
    tmp[2] = float3(v[0].z, v[1].z, v[2].z);

    return tmp;
}

// Description:
// Create an identity matrix.
// Returns:
// The identify 3x3 matrix.
float3x3 identity33()
{
    float3x3 tmp;
    tmp[0] = float3(1, 0, 0);
    tmp[1] = float3(0, 1, 0);
    tmp[2] = float3(0, 0, 1);

    return tmp;
}

// Description:
// Build a 3x3 matrix from column vectors.
// Arguments:
// c0 - The first column vector.
// c1 - The second column vector.
// c2 - The third column vetcor.
// Returns:
// The 3x3 matrix.
float3x3 mat3_from_columns(float3 c0, float3 c1, float3 c2)
{
    float3x3 m = float3x3(c0, c1, c2);
#if defined(PHYRE_D3DFX) || defined(__ORBIS__)
    m = transposeFloat3x3(m);		    // The HLSL matrix constructor takes rows rather than columns, so transpose after
#endif //! defined(PHYRE_D3DFX) || defined(__ORBIS__)
    return m;
}

// Description:
// Build a 3x3 matrix from row vectors.
// Arguments:
// c0 - The first row vector.
// c1 - The second row vector.
// c2 - The third row vector.
// Returns:
// The 3x3 matrix.
float3x3 mat3_from_rows(float3 c0, float3 c1, float3 c2)
{
    float3x3 m = float3x3(c0, c1, c2);
#if defined(PHYRE_D3DFX) || defined(__ORBIS__)
	// Nothing
#else //! defined(PHYRE_D3DFX) || defined(__ORBIS__)
    m = transposeFloat3x3(m);		// Transpose cols to rows.
#endif //! defined(PHYRE_D3DFX) || defined(__ORBIS__)
    return m;
}

// -------------------------------------------------------------------------------------------------

#if 0
// Description:
// Compute the integer modulus of x % y.
// Arguments:
// x - The first parameter to the modulus calculation.
// y - The second parameter to the modulus calculation.
// Returns:
// The modulus.
int modi(int x, int y)
{
    return int(mod(x, y));
}

// Descrition:
// Compute the orthonormal Frisvad basis coordinate system for the specified vector.
// Arguments:
// v - The vector for which to build the coordinate system.
// Returns:
// The orthonormal Frisvad basis for the specified input vector.
float3x3 BasisFrisvad(float3 v)
{
    float3 x, y;

    if (v.z < -0.999999)
    {
        x = float3( 0, -1, 0);
        y = float3(-1,  0, 0);
    }
    else
    {
        float a = 1.0 / (1.0 + v.z);
        float b = -v.x*v.y*a;
        x = float3(1.0 - v.x*v.x*a, b, -v.x);
        y = float3(b, 1.0 - v.y*v.y*a, -v.y);
    }

    return mat3_from_columns(x, y, v);
}

// From: https://briansharpe.wordpress.com/2011/11/15/a-fast-and-simple-32bit-floating-point-hash-function/
float4 FAST_32_hash(float2 gridcell)
{
    // gridcell is assumed to be an integer coordinate
    const float2 OFFSET = float2(26.0, 161.0);
    const float DOMAIN = 71.0;
    const float SOMELARGEFLOAT = 951.135664;
    float4 P = float4(gridcell.xy, gridcell.xy + float2(1, 1));
    P = P - floor(P * (1.0 / DOMAIN)) * DOMAIN;    //    truncate the domain
    P += OFFSET.xyxy;                              //    offset to interesting part of the noise
    P *= P;                                        //    calculate and return the hash
    return fract(P.xzxz * P.yyww * (1.0 / SOMELARGEFLOAT));
}
#endif

// -------------------------------------------------------------------------------------------------

// Description:
// Evaluate the GGX BRDF.
// Arguments:
// V - The surface point to eye vector.
// L - The surface point to light vector.
// alpha - The alpha parameter.
// pdf - The probability density function value returned.
// Returns:
// The evaluated result of the GGX BRDF.
float GGX(float3 V, float3 L, float alpha, out float pdf)
{
    if (V.z <= 0.0 || L.z <= 0.0)
    {
        pdf = 0.0;
        return 0.0;
    }

    float a2 = alpha*alpha;

    // height-correlated Smith masking-shadowing function
    float G1_wi = 2.0*V.z/(V.z + sqrt(a2 + (1.0 - a2)*V.z*V.z));
    float G1_wo = 2.0*L.z/(L.z + sqrt(a2 + (1.0 - a2)*L.z*L.z));
    float G     = G1_wi*G1_wo / (G1_wi + G1_wo - G1_wi*G1_wo);

    // D
    float3 H = normalize(V + L);
    float d = 1.0 + (a2 - 1.0)*H.z*H.z;
    float D = a2/(PBR_PI * d*d);

    float ndoth = H.z;
    float vdoth = dot(V, H);

    if (vdoth <= 0.0)
    {
        pdf = 0.0;
        return 0.0;
    }

    pdf = D * ndoth / (4.0*vdoth);

    float res = D * G / 4.0 / V.z / L.z;
    return res;
}

// -------------------------------------------------------------------------------------------------

#if 0

// Description:
// Ray test against a quad.
// Arguments:
// q - The vertices of the quad.
// pos - The origin of the ray to test.
// dir - The direction of the ray to test.
// uv - The parametric position in the quad for a hit.
// twoSided - The flag that indicates that the quad is two sided.
// Return Value List:
// true - The ray hit the quad.
// false - The ray did not hit the quad.
bool QuadRayTest(float4 q[4], float3 pos, float3 dir, out float2 uv, bool twoSided)
{
    // compute plane normal and distance from origin
    float3 xaxis = q[1].xyz - q[0].xyz;
    float3 yaxis = q[3].xyz - q[0].xyz;

    float xlen = length(xaxis);
    float ylen = length(yaxis);
    xaxis = xaxis / xlen;
    yaxis = yaxis / ylen;

    float3 zaxis = normalize(cross(xaxis, yaxis));
    float d = -dot(zaxis, q[0].xyz);

    float ndotz = -dot(dir, zaxis);
    if (twoSided)
        ndotz = abs(ndotz);

    if (ndotz < 0.00001)
        return false;

    // compute intersection point
    float t = -(dot(pos, zaxis) + d) / dot(dir, zaxis);

    if (t < 0.0)
        return false;

    float3 projpt = pos + dir * t;

    // use intersection point to determine the UV
    uv = float2(dot(xaxis, projpt - q[0].xyz),
                dot(yaxis, projpt - q[0].xyz)) / float2(xlen, ylen);

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return false;

    return true;
}

// Description:
// Fetch from a light texture with the quad coordinates specified.
// texLightFiltered - The texture from which to fetch.
// p1_ - The first quad vertex.
// p2_ - The second quad vertex.
// p3_ - The third quad vertex.
// p4_ - The fourth quad vertex.
// Returns:
// The sampled value from the light texture.
float3 FetchDiffuseFilteredTexture(sampler2D texLightFiltered, float3 p1_, float3 p2_, float3 p3_, float3 p4_)
{
    // area light plane basis
    float3 V1 = p2_ - p1_;
    float3 V2 = p4_ - p1_;
    float3 planeOrtho = (cross(V1, V2));
    float planeAreaSquared = dot(planeOrtho, planeOrtho);
    float planeDistxPlaneArea = dot(planeOrtho, p1_);
    // orthonormal projection of (0,0,0) in area light space
    float3 P = planeDistxPlaneArea * planeOrtho / planeAreaSquared - p1_;

    // find tex coords of P
    float dot_V1_V2 = dot(V1,V2);
    float inv_dot_V1_V1 = 1.0 / dot(V1, V1);
    float3 V2_ = V2 - V1 * dot_V1_V2 * inv_dot_V1_V1;
    float2 Puv;
    Puv.y = dot(V2_, P) / dot(V2_, V2_);
    Puv.x = dot(V1, P)*inv_dot_V1_V1 - dot_V1_V2*inv_dot_V1_V1*Puv.y ;

    // LOD
    float d = abs(planeDistxPlaneArea) / pow(planeAreaSquared, 0.75);

    return texture2DLod(texLightFiltered, float2(0.125, 0.125) + 0.75 * Puv, log(2048.0*d)/log(3.0) ).rgb;
}
#endif

// Description:
// Get the LTC lookup coords for the specified cosTheta and roughness parameters.
// Arguemnts:
// cosTheta - The cos theta for which to get the LTC lookup coordinates.
// roughness - The roughness for which to get the LTC lookup coordinates.
// Returns:
// The LTC lookup coordinates.
float2 LTC_Coords(float cosTheta, float roughness)
{
    float theta = acos(cosTheta);
    float2 coords = float2(theta/(0.5f*PBR_PI), roughness);				// Note : Roughness in y, theta in x, transposed from original code for threadpool line filler in PhyreUtilityPBR.cpp.

    const float LUT_SIZE = 64.0f;			// The size of the LTCMat and LTCAmp textures.
    // scale and bias coordinates, for correct filtered lookup
    coords = coords*(LUT_SIZE - 1.0f)/LUT_SIZE + 0.5f/LUT_SIZE;

    return coords;
}

// Description:
// Get the linear transformed cosine for the specified coordinates.
// Arguments:
// coord - The coordinate for which to get the LTC matrix.
// Returns:
// The LTC matrix.
float3x3 LTC_Matrix(float2 coord)
{
    float4 t = LTC_SampleMat(coord);														    // Load inverse matrix components.
    float3x3 Minv = mat3_from_columns(float3(1,0,t.y), float3(0,t.z,0), float3(t.w,0,t.x));		// Rebuild the matrix.

    return Minv;
}

// Description:
// Calculate contour integral of edge.
// Arguments:
// v1 - The first vertex of the edge.
// v2 - The second vertex of the edge.
// Returns:
// The integral value.
float IntegrateEdge(float3 v1, float3 v2)
{
    float cosTheta = dot(v1, v2);
    cosTheta = clamp(cosTheta, -0.9999f, 0.9999f);

    float theta = acos(cosTheta);
	//float sinTheta = sin(theta);
	float sinTheta = sqrt(1.0f - cosTheta*cosTheta);
    float res = cross(v1, v2).z * theta / sinTheta;

    return res;
}

// Description:
// Clip the quad to above the horizon. The input quad is specified in local plane space, with +ve Z being above the plane.
// Arguments:
// L - The input (and output) quad. The quad is in L[0]-L[3], and L[4] is equal to L[3].
// n - The number of vertices remaining in the L array after clipping (in entries 0 -> n-1).
void ClipQuadToHorizon(inout float3 L[5], out int n)
{
    // detect clipping config
    int config = 0;
    if (L[0].z > 0.0) config += 1;
    if (L[1].z > 0.0) config += 2;
    if (L[2].z > 0.0) config += 4;
    if (L[3].z > 0.0) config += 8;

    // clip
    n = 0;

    if (config == 0)
    {
        // clip all
    }
    else if (config == 1) // V1 clip V2 V3 V4
    {
        n = 3;
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        L[2] = -L[3].z * L[0] + L[0].z * L[3];
    }
    else if (config == 2) // V2 clip V1 V3 V4
    {
        n = 3;
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
    }
    else if (config == 3) // V1 V2 clip V3 V4
    {
        n = 4;
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
        L[3] = -L[3].z * L[0] + L[0].z * L[3];
    }
    else if (config == 4) // V3 clip V1 V2 V4
    {
        n = 3;
        L[0] = -L[3].z * L[2] + L[2].z * L[3];
        L[1] = -L[1].z * L[2] + L[2].z * L[1];
    }
    else if (config == 5) // V1 V3 clip V2 V4) impossible
    {
        n = 0;
    }
    else if (config == 6) // V2 V3 clip V1 V4
    {
        n = 4;
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        L[3] = -L[3].z * L[2] + L[2].z * L[3];
    }
    else if (config == 7) // V1 V2 V3 clip V4
    {
        n = 5;
        L[4] = -L[3].z * L[0] + L[0].z * L[3];
        L[3] = -L[3].z * L[2] + L[2].z * L[3];
    }
    else if (config == 8) // V4 clip V1 V2 V3
    {
        n = 3;
        L[0] = -L[0].z * L[3] + L[3].z * L[0];
        L[1] = -L[2].z * L[3] + L[3].z * L[2];
        L[2] =  L[3];
    }
    else if (config == 9) // V1 V4 clip V2 V3
    {
        n = 4;
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        L[2] = -L[2].z * L[3] + L[3].z * L[2];
    }
    else if (config == 10) // V2 V4 clip V1 V3) impossible
    {
        n = 0;
    }
    else if (config == 11) // V1 V2 V4 clip V3
    {
        n = 5;
        L[4] = L[3];
        L[3] = -L[2].z * L[3] + L[3].z * L[2];
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
    }
    else if (config == 12) // V3 V4 clip V1 V2
    {
        n = 4;
        L[1] = -L[1].z * L[2] + L[2].z * L[1];
        L[0] = -L[0].z * L[3] + L[3].z * L[0];
    }
    else if (config == 13) // V1 V3 V4 clip V2
    {
        n = 5;
        L[4] = L[3];
        L[3] = L[2];
        L[2] = -L[1].z * L[2] + L[2].z * L[1];
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
    }
    else if (config == 14) // V2 V3 V4 clip V1
    {
        n = 5;
        L[4] = -L[0].z * L[3] + L[3].z * L[0];
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
    }
    else if (config == 15) // V1 V2 V3 V4
    {
        n = 4;
    }
    
    if (n == 3)
        L[3] = L[0];
    if (n == 4)
        L[4] = L[0];
}

// Description:
// Clip an edge against the Z=0 horizon.
// Arguments:
// prevPoint - The previous point.
// nextPoint - The next point.
// Return Value List:
// 0 - Both points were clipped.
// 1 - prevPoint is visible, nextPoint is clipped (nextPoint updated).
// 2 - nextPoint is visible, prevPoint is clipped (prevPoint updated).
// 3 - Both points are visible.
int clipEdgeToHorizon(inout float3 prevPoint, inout float3 nextPoint)
{
    int config = 0;

	if (prevPoint.z > 0.0) config += 1;
    if (nextPoint.z > 0.0) config += 2;

	if (config == 0)
	{
		// Both clipped
	}
	else if (config == 1)
	{
		// prev above, next below.
		float t = (0-prevPoint.z)/(nextPoint.z-prevPoint.z);
		nextPoint.xy = prevPoint.xy + t*(nextPoint.xy-prevPoint.xy);
		nextPoint.z = 0.0f;
	}
	else if (config == 2)
	{
		float t = (0-prevPoint.z)/(nextPoint.z-prevPoint.z);
		// prev below, next above.
        prevPoint.xy = prevPoint.xy + t*(nextPoint.xy-prevPoint.xy);
		prevPoint.z = 0.0f;
	}
	else
	{
		// Both above.
	}

	return config;
}

// Description:
// Evaluate the linear transformed cosine for the specified quadrilateral.
// Arguments:
// N - The surface normal.
// V - The vector from the illuminated point to the eye position.
// P - The illuminated point.
// MinV - The LTC matrix for the LTC lookup.
// points - The points for the quad to evaluate.
// twoSided - The flag that indicates that the quad is two-sided.
// Returns:
// The illumination value.
float3 LTC_EvaluateQuad(float3 N, float3 V, float3 P, float3x3 Minv, float3 points[4], bool twoSided)//, sampler2D texFilteredMap)
{
	// construct orthonormal basis around N.  Use V to orientate.
    float3 T1 = normalize(V - N*dot(V, N));
    float3 T2 = cross(N, T1);

	// rotate area light in (T1, T2, R) basis
    Minv = mul(Minv, mat3_from_rows(T1, T2, N));

    // Polygon (allocate 5 vertices for clipping).
	// Transform by linear transform to account for roughness and N.V.
    float3 L[5];
    L[0] = mul(Minv, points[0] - P);
    L[1] = mul(Minv, points[1] - P);
    L[2] = mul(Minv, points[2] - P);
    L[3] = mul(Minv, points[3] - P);
    L[4] = L[3]; // avoid warning

    float3 textureLight = float3(1, 1, 1);
#if LTC_TEXTURED
    //textureLight = FetchDiffuseFilteredTexture(texFilteredMap, L[0], L[1], L[2], L[3]);
#endif

    int n;
    ClipQuadToHorizon(L, n);
    
    if (n == 0)
        return float3(0, 0, 0);

    // project onto sphere
    L[0] = normalize(L[0]);
    L[1] = normalize(L[1]);
    L[2] = normalize(L[2]);
    L[3] = normalize(L[3]);
    L[4] = normalize(L[4]);

    // Integrate clipped polygon to find projected area.
    float sum = 0.0;

    sum += IntegrateEdge(L[0], L[1]);
    sum += IntegrateEdge(L[1], L[2]);
    sum += IntegrateEdge(L[2], L[3]);
    if (n >= 4)
        sum += IntegrateEdge(L[3], L[4]);
    if (n == 5)
        sum += IntegrateEdge(L[4], L[0]);

    // Backface cull or handle two-sided-ness.
    sum = twoSided ? abs(sum) : max(0.0, sum);

    float3 Lo_i = float3(sum, sum, sum);

    // scale by filtered light color
    Lo_i *= textureLight;

    return Lo_i;
}

// Description:
// Structure to track the integration of a contour across the clamped cosine.
struct ContourIntegralShape
{
	bool m_open;										// The contour integral is open.
	int m_prevClipLeft;									// The previous clip flags for the left edge.
	int m_prevClipRight;								// The previous clip flags for the right edge.
	float3x3 m_minV;									// The transform from BRDF space to clamped cosine space.
	float3 m_leftPrevPoint;								// The previous (unprojected) integration point on the left.
	float3 m_rightPrevPoint;							// The previous (unprojected) integration point on the right.
	float3 m_integrationPrevLeft;						// The previous (projected) integration point on the left.
	float3 m_integrationPrevRight;						// The previous (projected) integration point on the right.

	// Description:
	// Initialize the contour integration with a single point.
	void initSinglePoint(float3x3 minV, float3 pt)
	{
		// Transform point into clamped cosine space.
		pt = mul(minV, pt);

		m_open = false;
		m_prevClipLeft = 0;							// Initialized on contour open.
		m_prevClipRight = 0;						// Initialized on contour open.
		m_minV = minV;
		m_leftPrevPoint = pt;
		m_rightPrevPoint = pt;
		m_integrationPrevLeft = float3(0,0,0);		// Initialized on contour open.
		m_integrationPrevRight = float3(0,0,0);		// Initialized on contour open.
	}

	// Description:
	// Add left and right vertices on the contour being integrated.
	// Arguments:
	// leftPoint - The left (unprojected) point being added.
	// rightPoint - The right (unprojected) point being added.
	// Returns:
	// The contour integration value resulting from the added edges.
	float addEdgePair(float3 leftPoint, float3 rightPoint)
	{
		float sum = 0.0f;

		// Transform points into clamped cosine space.
		leftPoint = mul(m_minV, leftPoint);
		rightPoint = mul(m_minV, rightPoint);

		float3 leftPrevPoint = leftPoint;
		float3 rightPrevPoint = rightPoint;

		// Need to treat each edge separately, since they are no longer co-planar with the horizontal after the transform to cosine.
		int clipLeft = clipEdgeToHorizon(m_leftPrevPoint, leftPoint);
		int clipRight = clipEdgeToHorizon(m_rightPrevPoint, rightPoint);

		if (clipLeft || clipRight)
		{
			if (!m_open)
			{
				m_open = true;

				m_integrationPrevLeft = clipLeft ? m_leftPrevPoint : m_rightPrevPoint;					// Open the left (prefer left point).
				m_integrationPrevLeft = normalize(m_integrationPrevLeft);

				m_integrationPrevRight = clipRight ? m_rightPrevPoint : m_leftPrevPoint;				// Open the right (prefer right point).
				m_integrationPrevRight = normalize(m_integrationPrevRight);

				// Integrate the top edge.  The vertices may be coincident in which case this evaluates to 0.
				sum += IntegrateEdge(m_integrationPrevLeft, m_integrationPrevRight);

				m_prevClipLeft = 3;	
				m_prevClipRight = 3;
			}

			// Integrate clockwise.
			if (clipLeft)
			{
				float3 norm = normalize(leftPoint);

				// Do we need to integrate between prev intersection of LTC horizon and current intersection of LTC horizon as well as current clipped edge?
				if (m_prevClipLeft < 2)
				{
					float3 norm2 = normalize(m_leftPrevPoint);
					sum += IntegrateEdge(norm2, m_integrationPrevLeft);
					sum += IntegrateEdge(norm, norm2);
				}
				else
				{
					sum += IntegrateEdge(norm, m_integrationPrevLeft);
				}
				m_integrationPrevLeft = norm;
			}

			if (clipRight)
			{
				float3 norm = normalize(rightPoint);

				// Do we need to integrate between prev intersection of LTC horizon and current intersection of LTC horizon as well as current clipped edge?
				if (m_prevClipRight < 2)
				{
					float3 norm2 = normalize(m_rightPrevPoint);
					sum += IntegrateEdge(m_integrationPrevRight, norm2);
					sum += IntegrateEdge(norm2, norm);
				}
				else
				{
					sum += IntegrateEdge(m_integrationPrevRight, norm);
				}
				m_integrationPrevRight = norm;
			}
		}
		else
		{
			if (m_open)
			{
				// Close the integration shape.
				sum += IntegrateEdge(m_integrationPrevRight, m_integrationPrevLeft);
				m_open = false;
			}
		}
		m_leftPrevPoint = leftPrevPoint;
		m_rightPrevPoint = rightPrevPoint;
		m_prevClipLeft = clipLeft;
		m_prevClipRight = clipRight;

		return sum;
	}

	// Description:
	// Close the contour integral.
	// Returns:
	// The result of integrating the closure.
	float close()
	{
		float sum = 0.0f;
		if (m_open)
		{
			// Close the integration shape.
			m_open = false;
			sum += IntegrateEdge(m_integrationPrevRight, m_integrationPrevLeft);
		}
		return sum;
	}
};

// Description:
// Evaluate the linear transformed cosine for the specified planar disc.
// Arguments:
// N - The surface normal.
// V - The vector from the illuminated point to the eye position.
// P - The illuminated point.
// MinV - The LTC matrix for the LTC lookup.
// discCenter - The center of the disc.
// discDirection - The axis of the disc.
// discRadius - The radius of the disc.
// twoSided - The flag that indicates that the quad is two-sided.
// Returns:
// The illumination value.
float3 LTC_EvaluateDisc(float3 N, float3 V, float3 P, float3x3 Minv, float3 discCenter, float3 discDirection, float discRadius, bool twoSided)//, sampler2D texFilteredMap)
{
	// Build light orthonormal basis with X along the plane and Y aligned as close to the surface normal as possible.
	float3 LX = normalize(cross(N, discDirection));
	float3 LY = normalize(cross(discDirection, LX));

	LX *= discRadius;
	LY *= discRadius;

	discCenter -= P;
		
    // construct orthonormal basis around N.  Use V to orientate.
    float3 T1 = normalize(V - N*dot(V, N));
    float3 T2 = cross(N, T1);

	// rotate area light in (T1, T2, R) basis
    Minv = mul(Minv, mat3_from_rows(T1, T2, N));

    float3 textureLight = float3(1, 1, 1);
#if LTC_TEXTURED
    //textureLight = FetchDiffuseFilteredTexture(texFilteredMap, L[0], L[1], L[2], L[3]);
#endif

	float sum = 0.0f;

	// Build edges around the disc, clip against the horizon, project onto the sphere and integrate.
	// This starts at the top and traces each side independently, integrated where the edges are not completely clipped.
	ContourIntegralShape integral;
	integral.initSinglePoint(Minv, discCenter + LY);

	float thetaStep = PBR_PI / 10.01f;
	for (float theta=thetaStep; theta<PBR_PI; theta=theta+thetaStep)
	{
		float c = cos(theta);
		float s = sin(theta);
			
		float3 left = discCenter + (LY*c + LX*s);
		float3 right = discCenter + (LY*c - LX*s);

		sum += integral.addEdgePair(left, right);
	}

	sum += integral.close();

	// Backface cull or handle two-sided-ness.
    sum = twoSided ? abs(sum) : max(0.0, sum);

    float3 Lo_i = float3(sum, sum, sum);

    // scale by filtered light color
    Lo_i *= textureLight;

    return Lo_i;
}

// Description:
// Evaluate the linear transformed cosine for the specified planar capsule.
// Arguments:
// N - The surface normal.
// V - The vector from the illuminated point to the eye position.
// P - The illuminated point.
// MinV - The LTC matrix for the LTC lookup.
// capsuleCenter - The center of the capsule.
// capsuleHalfWidth - The half vector of the capsule's width.
// capsuleRadius - The capsule's radius.
// alongVec - The normalized vector along the capsule (to define the end cap orientation).
// acrossVec - The normalized vector across the capsule (to define the end cap orientation).
// twoSided - The flag that indicates that the quad is two-sided.
// Returns:
// The illumination value.
float3 LTC_EvaluateCapsule(float3 N, float3 V, float3 P, float3x3 Minv, float3 capsuleCenter, float3 capsuleHalfWidth, float capsuleRadius, float3 alongVec, float3 acrossVec, bool twoSided)//, sampler2D texFilteredMap)
{
	// Scale end cap orientations by radius.
	float3 LY = alongVec * capsuleRadius;
	float3 LX = acrossVec * capsuleRadius;

	// Move relative to lit surface point.
	capsuleCenter -= P;

	// Compute end points.
	float3 end1 = capsuleCenter + capsuleHalfWidth;
	float3 end2 = capsuleCenter - capsuleHalfWidth;

    // construct orthonormal basis around N.  Use V to orientate.
    float3 T1 = normalize(V - N*dot(V, N));
    float3 T2 = cross(N, T1);

    // rotate area light in (T1, T2, R) basis
    Minv = mul(Minv, mat3_from_rows(T1, T2, N));

    float3 textureLight = float3(1, 1, 1);
#if LTC_TEXTURED
    //textureLight = FetchDiffuseFilteredTexture(texFilteredMap, L[0], L[1], L[2], L[3]);
#endif

	float sum = 0.0f;

	// Build edges around the disc, clip against the horizon, project onto the sphere and integrate.
	// This starts at the top and traces each side independently, integrated where the edges are not completely clipped.
	// Both end caps are built simultaneously and then the contour integrals joined at the end.
	ContourIntegralShape topInt;
	ContourIntegralShape botInt;
	topInt.initSinglePoint(Minv, end1 + LY);
	botInt.initSinglePoint(Minv, end2 - LY);

	float thetaStep = (PBR_PI*0.5f) / 5.01f;
	for (float theta=thetaStep; theta<(PBR_PI*0.5f); theta=theta+thetaStep)
	{
		float c = cos(theta);
		float s = sin(theta);
			
		float3 topLeft = end1 + (LY*c + LX*s);
		float3 topRight = end1 + (LY*c - LX*s);

		float3 botLeft = end2 - (LY*c + LX*s);
		float3 botRight = end2 - (LY*c - LX*s);

		sum += topInt.addEdgePair(topLeft, topRight);
		sum += botInt.addEdgePair(botLeft, botRight);
	}

	// Run out some verts along the straight bit.
	for (float t=0; t<1.0f; t+= 0.099f)
	{
		float3 p = end1 + (end2-end1)*t;
		sum += topInt.addEdgePair(p+LX, p-LX);
	}

	if (topInt.m_open && botInt.m_open)
	{
		// Close the top and bottom against each other (filling the quad between).
		// Match left to right though, since one is rotated 180 degrees.
		sum += IntegrateEdge(topInt.m_integrationPrevRight, botInt.m_integrationPrevLeft);
		sum += IntegrateEdge(botInt.m_integrationPrevRight, topInt.m_integrationPrevLeft);
	}
	else
	{
		// Close each end cap individually if it is open.
		sum += topInt.close();
		sum += botInt.close();
	}

	// Backface cull or handle two-sided-ness.
    sum = twoSided ? abs(sum) : max(0.0, sum);

    float3 Lo_i = float3(sum, sum, sum);

    // scale by filtered light color
    Lo_i *= textureLight;

    return Lo_i;
}

#endif //! PHYRE_LINEAR_TRANSFORMED_COSINES_H
