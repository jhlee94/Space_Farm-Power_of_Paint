/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_COMPUTE_PARTICLE_COMMON_H
#define PHYRE_COMPUTE_PARTICLE_COMMON_H

#define PE_PARTICLECURVE_BEZIER 0
#define PE_PARTICLECURVE_LINEAR 1
#define PE_PARTICLECURVE_STEP 2

// Description:
// Get parametric lifetime.
// Arguments:
// state - The particle state to get the parametric lifetime for.
// Returns:
// Parametric lifetime in the range of 1.0 = new, 0.0 = dead.
float getParametricLifetime(PParticleStateStruct state)
{
	return (state.m_lifetime * state.m_recipSpawnedLifetime);
}

// Description:
// Get an envelope interpolator value.
// Arguments:
// interpolators - The patricle state containing the inteprolator values.
// selector - The selector index determining which interpolator to use.
// Returns:
// The requested interpolator value.
float getInterpolator(PParticleEnvelopeInterpolatorsStruct interpolators, uint selector)
{
	switch (selector)
	{
		default:
		case 0:
			return interpolators.m_interpolators[0];
		case 1:
			return interpolators.m_interpolators[1];
		case 2:
			return interpolators.m_interpolators[2];
		case 3:
			return interpolators.m_interpolators[3];
	}
}

// Description:
// Build a rotation matrix from an axis and an angle.
// Arguments:
// angle - The angle of the rotation.
// axus - The axis of the rotation.
// Returns:
// The rotation matrix.
float3x3 rotationMatrix(float angle, float3 axis)
{
	float s = sin(angle);
	float c = cos(angle);
	float x = axis.x;
	float y = axis.y;
	float z = axis.z;
	float xx = x*x;
	float yy = y*y;
	float zz = z*z;
	float xy = x*y;
	float yz = y*z;
	float zx = z*x;
	float oneMinusC = ( 1.0f - c );
	float3x3 rotation;
	rotation[0] = float3(((xx * oneMinusC) + c ),			( ( xy * oneMinusC ) + ( z * s ) ),		( ( zx * oneMinusC ) - ( y * s ) ) );
	rotation[1] = float3(((xy * oneMinusC) - (z * s) ),		( ( yy * oneMinusC ) + c ),				( ( yz * oneMinusC ) + ( x * s ) ) );
	rotation[2] = float3(((zx * oneMinusC) + (y * s) ),		( ( yz * oneMinusC ) - ( x * s ) ),		( ( zz * oneMinusC ) + c ) );

	return rotation;
}

// Description:
// Build a rotatoin matrix from a quaternion.
// Arguments:
// unitQuat - The quaternion to build the rotation matrix from.
// Returns:
// The rotation matrix.
float3x3 rotationMatrixFromQuaternion(float4 unitQuat)
{
	float qx = unitQuat.x;
	float qy = unitQuat.y;
	float qz = unitQuat.z;
	float qw = unitQuat.w;
	float qx2 = ( qx + qx );
	float qy2 = ( qy + qy );
	float qz2 = ( qz + qz );
	float qxqx2 = ( qx * qx2 );
	float qxqy2 = ( qx * qy2 );
	float qxqz2 = ( qx * qz2 );
	float qxqw2 = ( qw * qx2 );
	float qyqy2 = ( qy * qy2 );
	float qyqz2 = ( qy * qz2 );
	float qyqw2 = ( qw * qy2 );
	float qzqz2 = ( qz * qz2 );
	float qzqw2 = ( qw * qz2 );

	float3x3 rotation;
	rotation[0] = float3( ( ( 1.0f - qyqy2 ) - qzqz2 ), ( qxqy2 + qzqw2 ), ( qxqz2 - qyqw2 ) );
	rotation[1] = float3( ( qxqy2 - qzqw2 ), ( ( 1.0f - qxqx2 ) - qzqz2 ), ( qyqz2 + qxqw2 ) );
	rotation[2] = float3( ( qxqz2 + qyqw2 ), ( qyqz2 - qxqw2 ), ( ( 1.0f - qxqx2 ) - qyqy2 ) );

	return rotation;
}

// Description:
// Build a rotation matrix about the X axis.
// Arguments:
// angle - The angle about which to rotate.
// Returns:
// The matrix for the X axis rotation.
float3x3 rotationX(float angle)
{
	float s = sin(angle);
	float c = cos(angle);

	float3x3 rotation;

	rotation[0] = float3(1, 0, 0);
	rotation[1] = float3(0, c, s);
	rotation[2] = float3(0, -s, c);

	return rotation;
}

// Description:
// Build a rotation matrix about the Z axis.
// Arguments:
// angle - The angle about which to rotate.
// Returns:
// The matrix for the Z axis rotation.
float3x3 rotationZ(float angle)
{
	float s = sin(angle);
	float c = cos(angle);

	float3x3 rotation;

	rotation[0] = float3(c, s, 0);
	rotation[1] = float3(-s, c, 0);
	rotation[2] = float3(0, 0, 1);

	return rotation;
}

// Description:
// Multiply two quaternions.
// Arguments:
// l - The left hand side of the multiplication.
// r - The right hand side of the multiplication.
// Returns:
// The product of the two quaternions.
float4 quatMul(float4 l, float4 r)
{
	return float4(
		( ( (l.w*r.x) + (l.x*r.w) ) + (l.y*r.z) ) - (l.z*r.y),
		( ( (l.w*r.y) + (l.y*r.w) ) + (l.z*r.x) ) - (l.x*r.z),
		( ( (l.w*r.z) + (l.z*r.w) ) + (l.x*r.y) ) - (l.y*r.x),
		( ( (l.w*r.w) - (l.x*r.x) ) - (l.y*r.y) ) - (l.z*r.z)
		);
}

// Description:
// Slerp between two quaternions.
// Arguments:
// t - The position to slerp to.
// unitQuat0 - The quaternion at t = 0.
// unitQuat1 - The quaternion at t = 1.
// Returns:
// The inteprolaion quaternion.
float4 quatSlerp(float t, float4 unitQuat0, float4 unitQuat1)
{
	// Flip unitQuat0 because it is on the other side of hypersphere from unitQuat1?
	float cosAngle = dot(unitQuat0, unitQuat1);
	if (cosAngle < 0.0f)
	{
		cosAngle = -cosAngle;
		unitQuat0 = -unitQuat0;
	}

	// If they are distant then slerp, else lerp.
	float scale0, scale1;
	if ( cosAngle < 0.999f )
	{
		// Distant.
		float angle = acos( cosAngle );
		float recipSinAngle = ( 1.0f / sin( angle ) );
		scale0 = (sin( ( ( 1.0f - t ) * angle ) ) * recipSinAngle );
		scale1 = (sin( ( t * angle ) ) * recipSinAngle );
	}
	else
	{
		// Close.
		scale0 = ( 1.0f - t );
		scale1 = t;
	}
	return ( ( unitQuat0 * scale0 ) + ( unitQuat1 * scale1 ) );
}
 
// Description:
// Calculate the quaternion conjugate.
// Arguemnts:
// quat - The quaternion to calculate the conjugate from.
// Returns:
// The quaternion conjugate.
float4 quatConjugate(float4 quat)
{
	return float4(-quat.x, -quat.y, -quat.z, quat.w);
}

// Description:
// Generate a float4 with four 0-1 floating point random numbers.
// Arguments:
// seed - The seed to permute (updated).
// Returns:
// The four random numbers.
float4 genRandFloat4(inout uint4 seed)
{
	uint4 i = seed ^ 12345391u;
	i = i * 2654435769u;

	i = i ^ ((i << 6) | (i >> 26));
	i = i * 2654435769u;
	i = i + ((i<<5) ^ (i >> 12));

	float4 f = float4(i) * 1.0f/0xFFFFFFFFu;

	seed += 15;
	return f;
}

// Description:
// Generate a float3 with three 0-1 floating point random numbers.
// Arguments:
// seed - The seed to permute (updated).
// Returns:
// The three random numbers.
float3 genRandFloat3(inout uint3 seed)
{
	uint3 i = seed ^ 12345391u;
	i = i * 2654435769u;

	i = i ^ ((i << 6) | (i >> 26));
	i = i * 2654435769u;
	i = i + ((i<<5) ^ (i >> 12));

	float3 f = float3(i) * 1.0f/0xFFFFFFFFu;

	seed += 15;
	return f;
}

// Description:
// Generate a float2 with two 0-1 floating point random numbers.
// Arguments:
// seed - The seed to permute (updated).
// Returns:
// The two random numbers.
float2 genRandFloat2(inout uint2 seed)
{
	uint2 i = seed ^ 12345391u;
	i = i * 2654435769u;

	i = i ^ ((i << 6) | (i >> 26));
	i = i * 2654435769u;
	i = i + ((i<<5) ^ (i >> 12));

	float2 f = float2(i) * 1.0f/0xFFFFFFFFu;

	seed += 15;
	return f;
}

// Description:
// Generate a float with a 0-1 floating point random number.
// Arguments:
// seed - The seed to permute (updated).
// Returns:
// The random number.
float genRandFloat(inout uint seed)
{
	uint i = seed ^ 12345391u;
	i = i * 2654435769u;

	i = i ^ ((i << 6) | (i >> 26));
	i = i * 2654435769u;
	i = i + ((i<<5) ^ (i >> 12));

	float f = float(i) * 1.0f/0xFFFFFFFFu;

	seed += 15;
	return f;
}

// Description:
// Interpolate a center + variance distribution.
// Arguments:
// center - The center of the distribution.
// variance - The maximum deviation from center.
// t - The position to interpolate, 0->1.
// Returns:
// The interpolated distribution.
float interpSpread(float center, float variance, float t)
{
	t = (t*2.0f)-1.0f;
	return center + (variance * t);
}

// Description:
// Interpolate a center + variance distribution.
// Arguments:
// center - The center of the distribution.
// variance - The maximum deviation from center.
// t - The position to interpolate, 0->1.
// Returns:
// The interpolated distribution.
float2 interpSpread(float2 center, float2 variance, float2 t)
{
	t = (t*2.0f)-float2(1.0f,1.0f);
	return center + (variance * t);
}

// Description:
// Interpolate a center + variance distribution.
// Arguments:
// center - The center of the distribution.
// variance - The maximum deviation from center.
// t - The position to interpolate, 0->1.
// Returns:
// The interpolated distribution.
float3 interpSpread(float3 center, float3 variance, float3 t)
{
	t = (t*2.0f)-float3(1.0f,1.0f,1.0f);
	return center + (variance * t);
}

// Description:
// Interpolate a center + variance distribution.
// Arguments:
// center - The center of the distribution.
// variance - The maximum deviation from center.
// t - The position to interpolate, 0->1.
// Returns:
// The interpolated distribution.
float4 interpSpread(float4 center, float4 variance, float4 t)
{
	t = (t*2.0f)-float4(1.0f,1.0f,1.0f,1.0f);
	return center + (variance * t);
}

// Description:
// Emit a Vector3 within a unit sphere.
// Arguments:
// seed - The seed for the emission (updated).
// Returns:
// The emitted value.
float3 emitVector3WithinUnitSphere(inout uint4 seed)
{
	float3 v;
	float length2;
	do
	{
		v = (genRandFloat4(seed).xyz * 2.0f) - 1.0f;
		length2 = dot(v,v);
	}
	while (length2 > 1.0f);

	return v;
}

// Description:
// Clamp a float value between a minimum and maximum value.
// Arguments:
// v - The value to clamp.
// lo - The low extent of the clamp region.
// hi - The high extent of the clamp region.
// Returns:
// The clamped value (between lo and hi).
float PhyreClamp(float v, float lo, float hi)
{
	if (v < lo)
		v = lo;
	if (v > hi)
		v = hi;
	return v;
}

// Description:
// Calculate the parametric value to interpolate the curve from the particle's time value.
// Arguments:
// time - The parametric lifetime remaining for the particle (1 for a new particle, 0 for a dead particle).
// Returns:
// The parametric value for interpolating the curve (0 for control point 0, 1/3 for control point 1, 2/3 for control point 2, 1 for control point 3).
float distortTime(float time, float time1, float time2, float repeatCount)
{
	float m, c;

	time = (1.0f-time) * repeatCount;								// 0.0f = new, repeatCount = dead.
	
	// Take modulus 1.0f, but don't wrap the last boundary close to death back to 0.
	float subtract = (float)(int)time;
	if (subtract > (repeatCount-0.01f))
		subtract -= 1.0f;
	time -= subtract;											// 0.0f = new, looped for spline interp.
	time = min(time, 1.0f);

	// Enforce that 0.0f < time1 < time2  < 1.0f;
	time1 = PhyreClamp(time1, 0.001f, 0.997f);
	time2 = PhyreClamp(time2, time1+0.001f, 0.999f);

	if (time < time1)
	{
		m = ((1.0f/3.0f) / time1 - 0.0f);
		c = (0.0f/3.0f) - (m * 0.0f);
	}
	else if (time < time2)
	{
		m = ((1.0f/3.0f) / (time2-time1));
		c = (1.0f/3.0f) - (m * time1);
	}
	else
	{
		m = ((1.0f/3.0f) / (1.0f-time2));
		c = (2.0f/3.0f) - (m * time2);
	}

	float t = m * time + c;

	return t;
}

#define DECLARE_PARTICLE_BEZIER_INTERPOLATOR(TYPE)																								\
	/* Description:																																\
	 * Beziér interpolate four control points.																									\
	 * Arguments:																																\
	 * t - The interpolator value.																												\
	 * c0 - The first control point (at t==0).																									\
	 * c1 - The second control point.																											\
	 * c2 - The third control point.																											\
	 * c3 - The fourth control point (at t==1).																									\
	 * Returns:																																	\
	 * The interpolated value.																													\
	 */																																			\
	TYPE particleBezierInterpolate(float t, TYPE c0, TYPE c1, TYPE c2, TYPE c3)																	\
	{																																			\
		float invT = 1.0f-t;																													\
																																				\
		float b0 = invT*invT*invT;						/* Basis */																				\
		float b1 = 3*invT*invT*t;																												\
		float b2 = 3*invT*t*t;																													\
		float b3 = t*t*t;																														\
																																				\
		return b0*c0 + b1*c1 + b2*c2 + b3*c3;																									\
	}

#define DECLARE_PARTICLE_BEZIER_ENVELOPE_INTERPOLATOR(TYPE)																						\
	/* Description:																																\
	 * Beziér interpolate four control points.																									\
	 * Arguments:																																\
	 * t - The interpolator value.																												\
	 * i - The envelope interpolator value.																										\
	 * c0A - The curve A first control point (at t==0).																							\
	 * c1A - The curve A second control point.																									\
	 * c2A - The curve A third control point.																									\
	 * c3A - The curve A fourth control point (at t==1).																						\
	 * c0B - The curve B first control point (at t==0).																							\
	 * c1B - The curve B second control point.																									\
	 * c2B - The curve B third control point.																									\
	 * c3B - The curve B fourth control point (at t==1).																						\
	 * Returns:																																	\
	 * The interpolated value.																													\
	 */																																			\
	TYPE particleBezierInterpolateEnvelope(float t, float i, TYPE c0A, TYPE c1A, TYPE c2A, TYPE c3A, TYPE c0B, TYPE c1B, TYPE c2B, TYPE c3B)	\
	{																																			\
		float invT = 1.0f-t;																													\
																																				\
		float b0 = invT*invT*invT;						/* Basis */																				\
		float b1 = 3*invT*invT*t;																												\
		float b2 = 3*invT*t*t;																													\
		float b3 = t*t*t;																														\
																																				\
		TYPE resultA = b0*c0A + b1*c1A + b2*c2A + b3*c3A;																						\
		TYPE resultB = b0*c0B + b1*c1B + b2*c2B + b3*c3B;																						\
																																				\
		return resultA + (resultB-resultA) * i;																									\
	}

#define DECLARE_PARTICLE_LINEAR_INTERPOLATOR(TYPE)																								\
	/* Description:																																\
	 * Linearly interpolate four control points.																								\
	 * Arguments:																																\
	 * t - The interpolator value.																												\
	 * c0 - The first control point (at t==0).																									\
	 * c1 - The second control point.																											\
	 * c2 - The third control point.																											\
	 * c3 - The fourth control point (at t==1).																									\
	 * Returns:																																	\
	 * The interpolated value.																													\
	 */																																			\
	TYPE particleLinearInterpolate(float t, TYPE c0, TYPE c1, TYPE c2, TYPE c3)																	\
	{																																			\
		if (t < (1.0f/3.0f))																													\
		{																																		\
			t = saturate((t-(0.0f/3.0f)) * 3.0f);																								\
			return c0 + (c1 - c0) * t;																											\
		}																																		\
		else if (t < (2.0f/3.0f))																												\
		{																																		\
			t = (t-(1.0f/3.0f)) * 3.0f;																											\
			return c1 + (c2 - c1) * t;																											\
		}																																		\
		else																																	\
		{																																		\
			t = saturate((t-(2.0f/3.0f)) * 3.0f);																								\
			return c2 + (c3 - c2) * t;																											\
		}																																		\
	}

#define DECLARE_PARTICLE_LINEAR_ENVELOPE_INTERPOLATOR(TYPE)																						\
	/* Description:																																\
	 * Linearly interpolate four control points.																								\
	 * Arguments:																																\
	 * t - The interpolator value.																												\
	 * i - The envelope interpolator value.																										\
	 * c0A - The curve A first control point (at t==0).																							\
	 * c1A - The curve A second control point.																									\
	 * c2A - The curve A third control point.																									\
	 * c3A - The curve A fourth control point (at t==1).																						\
	 * c0B - The curve B first control point (at t==0).																							\
	 * c1B - The curve B second control point.																									\
	 * c2B - The curve B third control point.																									\
	 * c3B - The curve B fourth control point (at t==1).																						\
	 * Returns:																																	\
	 * The interpolated value.																													\
	 */																																			\
	TYPE particleLinearInterpolateEnvelope(float t, float i, TYPE c0A, TYPE c1A, TYPE c2A, TYPE c3A, TYPE c0B, TYPE c1B, TYPE c2B, TYPE c3B)	\
	{																																			\
		TYPE resultA;																															\
		TYPE resultB;																															\
		if (t < (1.0f/3.0f))																													\
		{																																		\
			t = saturate((t-(0.0f/3.0f)) * 3.0f);																								\
			resultA = c0A + (c1A - c0A) * t;																									\
			resultB = c0B + (c1B - c0B) * t;																									\
		}																																		\
		else if (t < (2.0f/3.0f))																												\
		{																																		\
			t = (t-(1.0f/3.0f)) * 3.0f;																											\
			resultA = c1A + (c2A - c1A) * t;																									\
			resultB = c1B + (c2B - c1B) * t;																									\
		}																																		\
		else																																	\
		{																																		\
			t = saturate((t-(2.0f/3.0f)) * 3.0f);																								\
			resultA = c2A + (c3A - c2A) * t;																									\
			resultB = c2B + (c3B - c2B) * t;																									\
		}																																		\
																																				\
		return resultA + (resultB-resultA) * i;																									\
	}

#define DECLARE_PARTICLE_STEP_INTERPOLATOR(TYPE)																								\
	/* Description:																																\
	 * Step interpolate four control points.																									\
	 * Arguments:																																\
	 * t - The interpolator value.																												\
	 * c0 - The first control point (at t==0).																									\
	 * c1 - The second control point.																											\
	 * c2 - The third control point.																											\
	 * c3 - The fourth control point (at t==1).																									\
	 * Returns:																																	\
	 * The interpolated value.																													\
	 */																																			\
	TYPE particleStepInterpolate(float t, TYPE c0, TYPE c1, TYPE c2, TYPE c3)																	\
	{																																			\
		if (t < (1.0f/3.0f))																													\
			return c0;																															\
		else if (t < (2.0f/3.0f))																												\
			return c1;																															\
		else																																	\
			return c2;																															\
	}

#define DECLARE_PARTICLE_STEP_ENVELOPE_INTERPOLATOR(TYPE)																						\
	/* Description:																																\
	 * Step interpolate four control points.																									\
	 * Arguments:																																\
	 * t - The interpolator value.																												\
	 * i - The envelope interpolator value.																										\
	 * c0A - The curve A first control point (at t==0).																							\
	 * c1A - The curve A second control point.																									\
	 * c2A - The curve A third control point.																									\
	 * c3A - The curve A fourth control point (at t==1).																						\
	 * c0B - The curve B first control point (at t==0).																							\
	 * c1B - The curve B second control point.																									\
	 * c2B - The curve B third control point.																									\
	 * c3B - The curve B fourth control point (at t==1).																						\
	 * Returns:																																	\
	 * The interpolated value.																													\
	 */																																			\
	TYPE particleStepInterpolateEnvelope(float t, float i, TYPE c0A, TYPE c1A, TYPE c2A, TYPE c3A, TYPE c0B, TYPE c1B, TYPE c2B, TYPE c3B)		\
	{																																			\
		TYPE resultA;																															\
		TYPE resultB;																															\
		if (t < (1.0f/3.0f))																													\
		{																																		\
			resultA = c0A;																														\
			resultB = c0B;																														\
		}																																		\
		else if (t < (2.0f/3.0f))																												\
		{																																		\
			resultA = c1A;																														\
			resultB = c1B;																														\
		}																																		\
		else																																	\
		{																																		\
			resultA = c2A;																														\
			resultB = c2B;																														\
		}																																		\
																																				\
		return resultA + (resultB-resultA) * i;																									\
	}

DECLARE_PARTICLE_BEZIER_INTERPOLATOR(float)
DECLARE_PARTICLE_BEZIER_INTERPOLATOR(float2)
DECLARE_PARTICLE_BEZIER_INTERPOLATOR(float3)
DECLARE_PARTICLE_BEZIER_INTERPOLATOR(float4)

DECLARE_PARTICLE_BEZIER_ENVELOPE_INTERPOLATOR(float)
DECLARE_PARTICLE_BEZIER_ENVELOPE_INTERPOLATOR(float2)
DECLARE_PARTICLE_BEZIER_ENVELOPE_INTERPOLATOR(float3)
DECLARE_PARTICLE_BEZIER_ENVELOPE_INTERPOLATOR(float4)

DECLARE_PARTICLE_LINEAR_INTERPOLATOR(float)
DECLARE_PARTICLE_LINEAR_INTERPOLATOR(float2)
DECLARE_PARTICLE_LINEAR_INTERPOLATOR(float3)
DECLARE_PARTICLE_LINEAR_INTERPOLATOR(float4)

DECLARE_PARTICLE_LINEAR_ENVELOPE_INTERPOLATOR(float)
DECLARE_PARTICLE_LINEAR_ENVELOPE_INTERPOLATOR(float2)
DECLARE_PARTICLE_LINEAR_ENVELOPE_INTERPOLATOR(float3)
DECLARE_PARTICLE_LINEAR_ENVELOPE_INTERPOLATOR(float4)

DECLARE_PARTICLE_STEP_INTERPOLATOR(float)
DECLARE_PARTICLE_STEP_INTERPOLATOR(float2)
DECLARE_PARTICLE_STEP_INTERPOLATOR(float3)
DECLARE_PARTICLE_STEP_INTERPOLATOR(float4)

DECLARE_PARTICLE_STEP_ENVELOPE_INTERPOLATOR(float)
DECLARE_PARTICLE_STEP_ENVELOPE_INTERPOLATOR(float2)
DECLARE_PARTICLE_STEP_ENVELOPE_INTERPOLATOR(float3)
DECLARE_PARTICLE_STEP_ENVELOPE_INTERPOLATOR(float4)

// Description:
// Emit a perturbed normal.
// Arguments:
// facing - The principal exis along which to emit the normal.
// variance - The amount by which to perturb the normal.
// rand01 - Two random numbers from 0 - 1.
// Returns:
// The emitted normal.
float3 emitPerturbedNormal(float3 facing, float variance, float2 rand01)
{
	const float dotEpsilon = 0.9f;

	float3 localZ = normalize(facing);
	float cosVariance = cos(variance);

	//	Clamp to -1 : 1
	cosVariance = cosVariance > 1.0f ? 1.0f : (cosVariance < -1.0f ? -1.0f : cosVariance);

	//	Check our dot with (1, 0, 0)
	float fwdDot = localZ.x < 0.0f ? -localZ.x : localZ.x;

	//	Select an appropriate world X vector
	float3 worldX = fwdDot < dotEpsilon ? float3(1,0,0) : float3(0,1,0);

	float3 localY = normalize(cross(localZ, worldX));
	float3 localX = normalize(cross(localY, localZ));

	const float theta = rand01.x * (3.1415926535897932f * 2.0f);

	// Rotation between poles - between 0 to pi radians
	//	This provides a more even distribution over the spherical cap - 
	//	deliberately weighted to the equator to prevent samples bunching up at the poles

	const float cosphi = cosVariance + rand01.y*(1.0f-cosVariance);

	const float sinphi = sqrt(1.0f - cosphi * cosphi);
	
	const float costheta = cos(theta);
	const float sintheta = sin(theta);

	return (localX*costheta*sinphi + localY*sintheta*sinphi + localZ*cosphi);
}

// Description:
// The bounds structure for the partially calculated bounds.
struct PEmitterBounds
{
	float3 m_min;								// The minimum bounds.
	float3 m_max;								// The maximum bounds.
};

#endif //! PHYRE_COMPUTE_PARTICLE_COMMON_H
