/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_SPHERICAL_HARMONICS_H
#define PHYRE_SPHERICAL_HARMONICS_H

///////////////////////////////////////////////////////////////////////////////////////
// Structures to hold spherical harmonic coefficients and evaluated basis functions. //
///////////////////////////////////////////////////////////////////////////////////////

// Indices of coefficients in flattened array:
//
//							0
//						1	2	3
//					4	5	6	7	8
//				9	10	11	12	13	14	15
//			16	17	18	19	20	21	22	23	24
//		25	26	27	28	29	30	31	32	33	34	35

#define SH_COEFF_0	0		// Index of band 0 center
#define SH_COEFF_1	2		// Index of band 1 center
#define SH_COEFF_2	6		// Index of band 2 center
#define SH_COEFF_3	12		// Index of band 3 center
#define SH_COEFF_4	20		// Index of band 4 center
#define SH_COEFF_5	30		// Index of band 5 center

#if defined(PHYRE_D3DFX) || defined(__ORBIS__)
#define UNROLL [unroll]
#else //! defined(PHYRE_D3DFX) || defined(__ORBIS__)
#define UNROLL /* Nothing */
#endif //! defined(PHYRE_D3DFX) || defined(__ORBIS__)

#define DECLARE_SH_STRUCT(NAME, EL_TYPE, ORDER)					\
	struct NAME													\
	{															\
		EL_TYPE m_c[(ORDER+1)*(ORDER+1)];						\
	};															\
	static void ShReset(out NAME r)								\
	{															\
		UNROLL													\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)				\
			r.m_c[i] = 0.0f;									\
	}															\
	static void ShAdd(inout NAME a, NAME b)						\
	{															\
		UNROLL													\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)				\
			a.m_c[i] += b.m_c[i];								\
	}															\
	static void ShScale(inout NAME a, float s)					\
	{															\
		UNROLL													\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)				\
			a.m_c[i] *= s;										\
	}															\
	static void ShLerp(inout NAME a, NAME b, float t)			\
	{															\
		UNROLL													\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)				\
			a.m_c[i] = a.m_c[i] + (b.m_c[i] - a.m_c[i]) * t;	\
	}															\
	static void ApplyCosinusLobe(inout NAME a)					\
	{															\
		BAND0(a.m_c[0] *= 1.0f);								\
		BAND1(a.m_c[1] *= 2.0f/3.0f);							\
		BAND1(a.m_c[2] *= 2.0f/3.0f);							\
		BAND1(a.m_c[3] *= 2.0f/3.0f);							\
		BAND2(a.m_c[4] *= 1.0f/4.0f);							\
		BAND2(a.m_c[5] *= 1.0f/4.0f);							\
		BAND2(a.m_c[6] *= 1.0f/4.0f);							\
		BAND2(a.m_c[7] *= 1.0f/4.0f);							\
		BAND2(a.m_c[8] *= 1.0f/4.0f);							\
	}


///////////////////////////////////////////////////////////
// Functions to evaluate spherical harmonic polynomials. //
///////////////////////////////////////////////////////////

#define DECLARE_SH_MIXEDOPS3(TYPE_VEC, TYPE_SCAL, ORDER)						\
	static void ShAdd3(inout TYPE_VEC a, TYPE_SCAL x, TYPE_SCAL y, TYPE_SCAL z)	\
	{																			\
		UNROLL																	\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)								\
			a.m_c[i] += float3(x.m_c[i], y.m_c[i], z.m_c[i]);					\
	}																			\
	static float3 ShReconstruct(TYPE_VEC coeffs, TYPE_SCAL basis)				\
	{																			\
		float3 r = float3(0.0f, 0.0f, 0.0f);									\
		UNROLL																	\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)								\
			r += coeffs.m_c[i] * basis.m_c[i];									\
		return r;																\
	}

#define DECLARE_SH_MIXEDOPS4(TYPE_VEC, TYPE_SCAL, ORDER)						\
	static void ShAdd4(inout TYPE_VEC a, TYPE_SCAL x, TYPE_SCAL y, TYPE_SCAL z, TYPE_SCAL w)	\
	{																			\
		UNROLL																	\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)								\
			a.m_c[i] += float4(x.m_c[i], y.m_c[i], z.m_c[i], w.m_c[i]);			\
	}																			\
	static float4 ShReconstruct(TYPE_VEC coeffs, TYPE_SCAL basis)				\
	{																			\
		float4 r = float4(0.0f, 0.0f, 0.0f, 0.0f);								\
		UNROLL																	\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)								\
			r += coeffs.m_c[i] * basis.m_c[i];									\
		return r;																\
	}

#define DECLARE_SH_EVALUATE(OUT_TYPE)																		\
	/* Description: */																						\
	/* Evaluate spherical harmonic. */																		\
	/* Arguments: */																						\
	/* coeffs - The coefficients (returned). Normalization factor is premultiplied in. */					\
	/* dir - The unit direction at which to evaluate the spherical harmonic. */								\
	static void EvaluateSH(out OUT_TYPE coeffs, float3 dir)													\
	{																										\
		float x = dir.x;																					\
		float y = dir.y;																					\
		float z = dir.z;																					\
		float z2 = z*z;																						\
																											\
		/* m = 0 */																							\
		BAND0(const float p_0_0 = 0.282094791773878140f);													\
		BAND0(coeffs.m_c[SH_COEFF_0] = p_0_0);												/* l=0,m=0 */	\
		BAND1(const float p_1_0 = 0.488602511902919920f * z);												\
		BAND1(coeffs.m_c[SH_COEFF_1] = p_1_0);												/* l=1,m=0 */	\
		BAND2(const float p_2_0 = 0.946174695757560080f * z2 + -0.315391565252520050f);						\
		BAND2(coeffs.m_c[SH_COEFF_2] = p_2_0);												/* l=2,m=0 */	\
		BAND3(const float p_3_0 = z*(1.865881662950577000f * z2 + -1.119528997770346200f));					\
		BAND3(coeffs.m_c[SH_COEFF_3] = p_3_0);												/* l=3,m=0 */	\
		BAND4(const float p_4_0 = 1.984313483298443000f * z * p_3_0 + -1.006230589874905300f * p_2_0);		\
		BAND4(coeffs.m_c[SH_COEFF_4] = p_4_0);												/* l=4,m=0 */	\
		BAND5(const float p_5_0 = 1.989974874213239700f * z * p_4_0 + -1.002853072844814000f * p_3_0);		\
		BAND5(coeffs.m_c[SH_COEFF_5] = p_5_0);												/* l=5,m=0 */	\
																											\
		/* m = +/- 1 */																						\
		BAND1(const float s1 = y);																			\
		BAND1(const float c1 = x);																			\
		BAND1(const float p_1_1 = -0.488602511902919920f);													\
		BAND1(coeffs.m_c[SH_COEFF_1-1] = p_1_1*s1);											/* l=1,m=-1 */	\
		BAND1(coeffs.m_c[SH_COEFF_1+1] = p_1_1*c1);											/* l=1,m=+1 */	\
		BAND2(const float p_2_1 = -1.092548430592079200f * z);												\
		BAND2(coeffs.m_c[SH_COEFF_2-1] = p_2_1*s1);											/* l=2,m=-1 */	\
		BAND2(coeffs.m_c[SH_COEFF_2+1] = p_2_1*c1);											/* l=2,m=+1 */	\
		BAND3(const float p_3_1 = -2.285228997322328800f * z2 + 0.457045799464465770f);						\
		BAND3(coeffs.m_c[SH_COEFF_3-1] = p_3_1*s1);											/* l=3,m=-1 */	\
		BAND3(coeffs.m_c[SH_COEFF_3+1] = p_3_1*c1);											/* l=3,m=+1 */	\
		BAND4(const float p_4_1 = z*(-4.683325804901024000f * z2 + 2.007139630671867200f));					\
		BAND4(coeffs.m_c[SH_COEFF_4-1] = p_4_1*s1);											/* l=4,m=-1 */	\
		BAND4(coeffs.m_c[SH_COEFF_4+1] = p_4_1*c1);											/* l=4,m=+1 */	\
		BAND5(const float p_5_1 = 2.031009601158990200f * z * p_4_1 + -0.991031208965114650f * p_3_1);		\
		BAND5(coeffs.m_c[SH_COEFF_5-1] = p_5_1*s1);											/* l=5,m=-1 */	\
		BAND5(coeffs.m_c[SH_COEFF_5+1] = p_5_1*c1);											/* l=5,m=+1 */	\
																											\
		/* m = +/- 2 */																						\
		BAND2(const float s2 = x*s1 + y*c1);																\
		BAND2(const float c2 = x*c1 - y*s1);																\
		BAND2(const float p_2_2 = 0.546274215296039590f);													\
		BAND2(coeffs.m_c[SH_COEFF_2-2] = p_2_2*s2);											/* l=2,m=-2 */	\
		BAND2(coeffs.m_c[SH_COEFF_2+2] = p_2_2*c2);											/* l=2,m=+2 */	\
		BAND3(const float p_3_2 = 1.445305721320277100f * z);												\
		BAND3(coeffs.m_c[SH_COEFF_3-2] = p_3_2*s2);											/* l=3,m=-2 */	\
		BAND3(coeffs.m_c[SH_COEFF_3+2] = p_3_2*c2);											/* l=3,m=+2 */	\
		BAND4(const float p_4_2 = 3.311611435151459800f * z2 + -0.473087347878779980f);						\
		BAND4(coeffs.m_c[SH_COEFF_4-2] = p_4_2*s2);											/* l=4,m=-2 */	\
		BAND4(coeffs.m_c[SH_COEFF_4+2] = p_4_2*c2);											/* l=4,m=+2 */	\
		BAND5(const float p_5_2 = z*(7.190305177459987500f * z2 + -2.396768392486662100f));					\
		BAND5(coeffs.m_c[SH_COEFF_5-2] = p_5_2*s2);											/* l=5,m=-2 */	\
		BAND5(coeffs.m_c[SH_COEFF_5+2] = p_5_2*c2);											/* l=5,m=+2 */	\
																											\
		/* m = +/- 3 */																						\
		BAND3(const float s3 = x*s2 + y*c2);																\
		BAND3(const float c3 = x*c2 - y*s2);																\
		BAND3(const float p_3_3 = -0.590043589926643520f);													\
		BAND3(coeffs.m_c[SH_COEFF_3-3] = p_3_3*s3);											/* l=3,m=-3 */	\
		BAND3(coeffs.m_c[SH_COEFF_3+3] = p_3_3*c3);											/* l=3,m=+3 */	\
		BAND4(const float p_4_3 = -1.770130769779930200f * z);												\
		BAND4(coeffs.m_c[SH_COEFF_4-3] = p_4_3*s3);											/* l=4,m=-3 */	\
		BAND4(coeffs.m_c[SH_COEFF_4+3] = p_4_3*c3);											/* l=4,m=+3 */	\
		BAND5(const float p_5_3 = -4.403144694917253700f * z2 + 0.489238299435250430f);						\
		BAND5(coeffs.m_c[SH_COEFF_5-3] = p_5_3*s3);											/* l=5,m=-3 */	\
		BAND5(coeffs.m_c[SH_COEFF_5+3] = p_5_3*c3);											/* l=5,m=+3 */	\
																											\
		/* m = +/- 4 */																						\
		BAND4(const float s4 = x*s3 + y*c3);																\
		BAND4(const float c4 = x*c3 - y*s3);																\
		BAND4(const float p_4_4 = 0.625835735449176030f);													\
		BAND4(coeffs.m_c[SH_COEFF_4-4] = p_4_4*s4);											/* l=4,m=-4 */	\
		BAND4(coeffs.m_c[SH_COEFF_4+4] = p_4_4*c4);											/* l=4,m=+4 */	\
		BAND5(const float p_5_4 = 2.075662314881041100f * z);												\
		BAND5(coeffs.m_c[SH_COEFF_5-4] = p_5_4*s4);											/* l=5,m=-4 */	\
		BAND5(coeffs.m_c[SH_COEFF_5+4] = p_5_4*c4);											/* l=5,m=+4 */	\
																											\
		/* m = +/- 5 */																						\
		BAND5(const float s5 = x*s4 + y*c4);																\
		BAND5(const float c5 = x*c4 - y*s4);																\
		BAND5(const float p_5_5 = -0.656382056840170150f);													\
		BAND5(coeffs.m_c[SH_COEFF_5-5] = p_5_5*s5);											/* l=5,m=-5 */	\
		BAND5(coeffs.m_c[SH_COEFF_5+5] = p_5_5*c5);											/* l=5,m=+5 */	\
	}

//#define BAND0(EXPR) EXPR
//#define BAND1(EXPR)
//#define BAND2(EXPR)
//#define BAND3(EXPR)
//#define BAND4(EXPR)
//#define BAND5(EXPR)
//
//DECLARE_SH_STRUCT(SHOrder0Float, float, 0)
//DECLARE_SH_STRUCT(SHOrder0Float3, float3, 0)
//DECLARE_SH_STRUCT(SHOrder0Float4, float4, 0)
//DECLARE_SH_EVALUATE(SHOrder0Float)
//DECLARE_SH_MIXEDOPS3(SHOrder0Float3, SHOrder0Float, 0)
//DECLARE_SH_MIXEDOPS4(SHOrder0Float4, SHOrder0Float, 0)
//
//#define BAND0(EXPR) EXPR
//#define BAND1(EXPR) EXPR
//#define BAND2(EXPR)
//#define BAND3(EXPR)
//#define BAND4(EXPR)
//#define BAND5(EXPR)
//
//DECLARE_SH_STRUCT(SHOrder1Float, float, 1)
//DECLARE_SH_STRUCT(SHOrder1Float3, float3, 1)
//DECLARE_SH_STRUCT(SHOrder1Float4, float4, 1)
//DECLARE_SH_EVALUATE(SHOrder1Float)
//DECLARE_SH_MIXEDOPS3(SHOrder1Float3, SHOrder1Float, 1)
//DECLARE_SH_MIXEDOPS4(SHOrder1Float4, SHOrder1Float, 1)

#define BAND0(EXPR) EXPR
#define BAND1(EXPR) EXPR
#define BAND2(EXPR) EXPR
#define BAND3(EXPR)
#define BAND4(EXPR)
#define BAND5(EXPR)

DECLARE_SH_STRUCT(SHOrder2Float, float, 2)
DECLARE_SH_STRUCT(SHOrder2Float3, float3, 2)
DECLARE_SH_STRUCT(SHOrder2Float4, float4, 2)
DECLARE_SH_EVALUATE(SHOrder2Float)
DECLARE_SH_MIXEDOPS3(SHOrder2Float3, SHOrder2Float, 2)
DECLARE_SH_MIXEDOPS4(SHOrder2Float4, SHOrder2Float, 2)

//#define BAND0(EXPR) EXPR
//#define BAND1(EXPR) EXPR
//#define BAND2(EXPR) EXPR
//#define BAND3(EXPR) EXPR
//#define BAND4(EXPR)
//#define BAND5(EXPR)
//
//DECLARE_SH_STRUCT(SHOrder3Float, float, 3)
//DECLARE_SH_STRUCT(SHOrder3Float3, float3, 3)
//DECLARE_SH_STRUCT(SHOrder3Float4, float4, 3)
//DECLARE_SH_EVALUATE(SHOrder3Float)
//DECLARE_SH_MIXEDOPS3(SHOrder3Float3, SHOrder3Float, 3)
//DECLARE_SH_MIXEDOPS4(SHOrder3Float4, SHOrder3Float, 3)

//#define BAND0(EXPR) EXPR
//#define BAND1(EXPR) EXPR
//#define BAND2(EXPR) EXPR
//#define BAND3(EXPR) EXPR
//#define BAND4(EXPR) EXPR
//#define BAND5(EXPR)
//
//DECLARE_SH_STRUCT(SHOrder4Float, float, 4)
//DECLARE_SH_STRUCT(SHOrder4Float3, float3, 4)
//DECLARE_SH_STRUCT(SHOrder4Float4, float4, 4)
//DECLARE_SH_EVALUATE(SHOrder4Float)
//DECLARE_SH_MIXEDOPS3(SHOrder4Float3, SHOrder4Float, 4)
//DECLARE_SH_MIXEDOPS4(SHOrder4Float4, SHOrder4Float, 4)
//
//#define BAND0(EXPR) EXPR
//#define BAND1(EXPR) EXPR
//#define BAND2(EXPR) EXPR
//#define BAND3(EXPR) EXPR
//#define BAND4(EXPR) EXPR
//#define BAND5(EXPR) EXPR
//
//DECLARE_SH_STRUCT(SHOrder5Float, float, 5)
//DECLARE_SH_STRUCT(SHOrder5Float3, float3, 5)
//DECLARE_SH_STRUCT(SHOrder5Float4, float4, 5)
//DECLARE_SH_EVALUATE(SHOrder5Float)
//DECLARE_SH_MIXEDOPS3(SHOrder5Float3, SHOrder5Float, 5)
//DECLARE_SH_MIXEDOPS4(SHOrder5Float4, SHOrder5Float, 5)

//////////////////////////////
// Order reduction methods. //
//////////////////////////////

//#define DECLARE_ORDER_REDUCTION(NAME, OUT_TYPE, IN_TYPE, OUT_ORDER)	\
//	static OUT_TYPE NAME(IN_TYPE a)										\
//	{																	\
//		OUT_TYPE r;														\
//		UNROLL															\
//		for (int i=0; i<(OUT_ORDER+1)*(OUT_ORDER+1); i++)				\
//			r.m_c[i] = a.m_c[i];										\
//		return r;														\
//	}
//
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float, SHOrder1Float, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float, SHOrder2Float, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float, SHOrder3Float, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float, SHOrder4Float, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float, SHOrder5Float, 0)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float, SHOrder2Float, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float, SHOrder3Float, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float, SHOrder4Float, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float, SHOrder5Float, 1)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float, SHOrder3Float, 2)
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float, SHOrder4Float, 2)
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float, SHOrder5Float, 2)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder3, SHOrder3Float, SHOrder4Float, 3)
//DECLARE_ORDER_REDUCTION(ShGetOrder3, SHOrder3Float, SHOrder5Float, 3)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder4, SHOrder4Float, SHOrder5Float, 4)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float3, SHOrder1Float3, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float3, SHOrder2Float3, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float3, SHOrder3Float3, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float3, SHOrder4Float3, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float3, SHOrder5Float3, 0)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float3, SHOrder2Float3, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float3, SHOrder3Float3, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float3, SHOrder4Float3, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float3, SHOrder5Float3, 1)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float3, SHOrder3Float3, 2)
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float3, SHOrder4Float3, 2)
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float3, SHOrder5Float3, 2)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder3, SHOrder3Float3, SHOrder4Float3, 3)
//DECLARE_ORDER_REDUCTION(ShGetOrder3, SHOrder3Float3, SHOrder5Float3, 3)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder4, SHOrder4Float3, SHOrder5Float3, 4)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float4, SHOrder1Float4, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float4, SHOrder2Float4, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float4, SHOrder3Float4, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float4, SHOrder4Float4, 0)
//DECLARE_ORDER_REDUCTION(ShGetOrder0, SHOrder0Float4, SHOrder5Float4, 0)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float4, SHOrder2Float4, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float4, SHOrder3Float4, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float4, SHOrder4Float4, 1)
//DECLARE_ORDER_REDUCTION(ShGetOrder1, SHOrder1Float4, SHOrder5Float4, 1)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float4, SHOrder3Float4, 2)
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float4, SHOrder4Float4, 2)
//DECLARE_ORDER_REDUCTION(ShGetOrder2, SHOrder2Float4, SHOrder5Float4, 2)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder3, SHOrder3Float4, SHOrder4Float4, 3)
//DECLARE_ORDER_REDUCTION(ShGetOrder3, SHOrder3Float4, SHOrder5Float4, 3)
//
//DECLARE_ORDER_REDUCTION(ShGetOrder4, SHOrder4Float4, SHOrder5Float4, 4)

#ifdef __ORBIS__

///////////////////////////////////////////
// Parallel reduction by lane swizzling. //
///////////////////////////////////////////

#define DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(TYPE, ORDER)					\
	static void ShLaneSwizzle(inout TYPE a)									\
	{																		\
		UNROLL																\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)							\
		{																	\
			a.m_c[i] += LaneSwizzle(a.m_c[i], 0x1fu, 0u, 0x1u);				\
			a.m_c[i] += LaneSwizzle(a.m_c[i], 0x1fu, 0u, 0x2u);				\
			a.m_c[i] += LaneSwizzle(a.m_c[i], 0x1fu, 0u, 0x4u);				\
			a.m_c[i] += LaneSwizzle(a.m_c[i], 0x1fu, 0u, 0x8u);				\
			a.m_c[i] += LaneSwizzle(a.m_c[i], 0x1fu, 0u, 0x10u);			\
			a.m_c[i] = ReadLane(a.m_c[i], 0) + ReadLane(a.m_c[i], 32);		\
		}																	\
	}

#define LaneSwizzleF3(IN, XOR)												\
	float3(LaneSwizzle(IN.x, 0x1fu, 0u, XOR),								\
			LaneSwizzle(IN.y, 0x1fu, 0u, XOR),								\
			LaneSwizzle(IN.z, 0x1fu, 0u, XOR))

#define ReadLaneF3(IN, NUM)													\
	float3(ReadLane(IN.x, NUM), ReadLane(IN.y, NUM), ReadLane(IN.z, NUM))

#define DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(TYPE, ORDER)				\
	static void ShLaneSwizzle(inout TYPE a)									\
	{																		\
		UNROLL																\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)							\
		{																	\
			a.m_c[i] += LaneSwizzleF3(a.m_c[i], 0x1u);						\
			a.m_c[i] += LaneSwizzleF3(a.m_c[i], 0x2u);						\
			a.m_c[i] += LaneSwizzleF3(a.m_c[i], 0x4u);						\
			a.m_c[i] += LaneSwizzleF3(a.m_c[i], 0x8u);						\
			a.m_c[i] += LaneSwizzleF3(a.m_c[i], 0x10u);						\
			a.m_c[i] = ReadLaneF3(a.m_c[i], 0) + ReadLaneF3(a.m_c[i], 32);	\
		}																	\
	}

#define LaneSwizzleF4(IN, XOR)												\
	float4(LaneSwizzle(IN.x, 0x1fu, 0u, XOR),								\
			LaneSwizzle(IN.y, 0x1fu, 0u, XOR),								\
			LaneSwizzle(IN.z, 0x1fu, 0u, XOR),								\
			LaneSwizzle(IN.w, 0x1fu, 0u, XOR))

#define ReadLaneF4(IN, NUM)													\
	float4(ReadLane(IN.x, NUM), ReadLane(IN.y, NUM), ReadLane(IN.z, NUM), ReadLane(IN.w, NUM))

#define DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT4(TYPE, ORDER)				\
	static void ShLaneSwizzle(inout TYPE a)									\
	{																		\
		UNROLL																\
		for (int i=0; i<(ORDER+1)*(ORDER+1); i++)							\
		{																	\
			a.m_c[i] += LaneSwizzleF4(a.m_c[i], 0x1u);						\
			a.m_c[i] += LaneSwizzleF4(a.m_c[i], 0x2u);						\
			a.m_c[i] += LaneSwizzleF4(a.m_c[i], 0x4u);						\
			a.m_c[i] += LaneSwizzleF4(a.m_c[i], 0x8u);						\
			a.m_c[i] += LaneSwizzleF4(a.m_c[i], 0x10u);						\
			a.m_c[i] = ReadLaneF4(a.m_c[i], 0) + ReadLaneF4(a.m_c[i], 32);	\
		}																	\
	}

//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(SHOrder0Float, 0)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(SHOrder1Float, 1)
DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(SHOrder2Float, 2)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(SHOrder3Float, 3)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(SHOrder4Float, 4)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT(SHOrder5Float, 5)

//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder0Float3, 0)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder1Float3, 1)
DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder2Float3, 2)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder3Float3, 3)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder4Float3, 4)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder5Float3, 5)

//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder0Float3, 0)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder1Float3, 1)
DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT4(SHOrder2Float4, 2)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder3Float3, 3)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder4Float3, 4)
//DECLARE_LANE_SWIZZLE_REDUCTION64_FLOAT3(SHOrder5Float3, 5)

#endif //! __ORBIS__

#endif //! PHYRE_SPHERICAL_HARMONICS_H
