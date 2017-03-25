/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_SHADER_PLATFORM_H
#define PHYRE_SHADER_PLATFORM_H

#ifdef __psp2__
	// Disable the D6204: profile 'sce_v/fp_psp2' does not support uniform default values warning
	#pragma warning (disable:6204)
#endif //! __psp2__
#ifdef __ORBIS__
	#pragma warning (disable:5203) // parameter unreferenced
	#pragma warning (disable:5206) // local variable unreferenced
	#pragma warning (disable:6204) // does not support uniform default values
	#pragma warning (disable:6459) // __user_defined__ is not a valid semantic for uniform
	#pragma warning (disable:5581) // PSSL treats 'half' type as 'float'
	#pragma warning (disable:5609) // PSSL treats 'half' type as 'float'
	#pragma warning (disable:5583) // PSSL treats 'half' literals as 'float'
	#pragma warning (disable:5524) // unsupported compiler hint
#endif //! __ORBIS__

#ifdef __ORBIS__
	//! Some evil #defines to sort out matrix multiplies.
	#define float4x4 row_major float4x4
	#define float3x4 row_major float3x4
	#define float4x3 row_major float4x3

	//! Semantics for VS/PS inputs and outputs.
	#define POSITION S_POSITION
	#define SV_POSITION S_POSITION
	#define SV_GroupID S_GROUP_ID
	#define SV_VertexID S_VERTEX_ID
	#define SV_PrimitiveID S_PRIMITIVE_ID
	#define SV_InstanceID S_INSTANCE_ID
	#define SV_DispatchThreadID S_DISPATCH_THREAD_ID
	#define SV_GroupThreadID S_GROUP_THREAD_ID
	#define SV_GroupIndex S_GROUP_INDEX
	#define SV_INSTANCEID S_INSTANCE_ID
	#define SV_PRIMITIVEID S_PRIMITIVE_ID
	#define SV_VERTEXID S_VERTEX_ID
	#define SV_IsFrontFace S_FRONT_FACE
	#define SV_Coverage S_COVERAGE
	#define SV_RenderTargetArrayIndex S_RENDER_TARGET_INDEX
	#define SV_RENDERTARGETARRAYINDEX S_RENDER_TARGET_INDEX
	#define FRAG_OUTPUT_COLOR S_TARGET_OUTPUT0
	#define FRAG_OUTPUT_COLOR0 S_TARGET_OUTPUT0
	#define FRAG_OUTPUT_COLOR1 S_TARGET_OUTPUT1
	#define FRAG_OUTPUT_COLOR2 S_TARGET_OUTPUT2
	#define FRAG_OUTPUT_COLOR3 S_TARGET_OUTPUT3
	#define FRAG_OUTPUT_COLOR4 S_TARGET_OUTPUT4
	#define FRAG_OUTPUT_COLOR5 S_TARGET_OUTPUT5
	#define FRAG_OUTPUT_COLOR6 S_TARGET_OUTPUT6
	#define FRAG_OUTPUT_COLOR7 S_TARGET_OUTPUT7
	#define FRAG_OUTPUT_DEPTH S_DEPTH_OUTPUT
	#define partitioning PARTITIONING_TYPE
	#define outputtopology OUTPUT_TOPOLOGY_TYPE
	#define outputcontrolpoints OUTPUT_CONTROL_POINTS
	#define patchconstantfunc PATCH_CONSTANT_FUNC
	#define maxtessfactor MAX_TESS_FACTOR
	#define domain DOMAIN_PATCH_TYPE
	#define SV_TessFactor S_EDGE_TESS_FACTOR
	#define SV_InsideTessFactor S_INSIDE_TESS_FACTOR
	#define SV_OutputControlPointID S_OUTPUT_CONTROL_POINT_ID
	#define SV_DomainLocation S_DOMAIN_LOCATION

	//! Some defines to make textures compile with PSSL for now (sort out later)
	SamplerState globalSamplerState;
	SamplerComparisonState globalSamplerComparisonState
	{
		// Sampler state
		Filter = MIN_MAG_LINEAR_MIP_POINT;
		AddressU = CLAMP;
		AddressV = CLAMP;
		// Sampler comparison state
		ComparisonFunc = LESS;
		ComparisonFilter = COMPARISON_MIN_MAG_LINEAR_MIP_POINT;
	};

	#define cbuffer ConstantBuffer
	#define sampler SamplerState
	#define sampler2D Texture2D
	#define sampler3D Texture3D
	#define samplerCUBE TextureCube
	#define tex2Dproj(a,b) a.Sample(globalSamplerState, (b).xy / (b).w)
	#define h1tex2Dproj(a,b) ((half)(a.Sample(globalSamplerState, (b).xy / (b).w).x))
	#define h4tex2D(a,b) ((half4)a.Sample(globalSamplerState, (b).xy))
	#define h4tex2Dlod(a,b) ((half4)a.SampleLOD(globalSamplerState, (b).xy, (b).w))
	#define tex2D(a,b) a.Sample(globalSamplerState, (b).xy)

	#define SampleLevel SampleLOD
	#define SampleCmpLevelZero SampleCmpLOD0
	#define StructuredBuffer RegularBuffer
	#define RWStructuredBuffer RW_RegularBuffer
	#define ByteAddressBuffer ByteBuffer
	#define RWByteAddressBuffer RW_ByteBuffer
	#define AppendStructuredBuffer AppendRegularBuffer
	#define ConsumeStructuredBuffer ConsumeRegularBuffer
	#define numthreads NUM_THREADS
	#define maxvertexcount MAX_VERTEX_COUNT
	#define groupshared thread_group_memory
	#define TriangleStream TriangleBuffer
	#define PointStream PointBuffer
	#define LineStream LineBuffer
	#define point Point
	#define line Line
	#define triangle Triangle
	#define IncrementCounter IncrementCount
	#define DecrementCounter DecrementCount

	#define RWTexture3D RW_Texture3D
	#define RWTexture2D RW_Texture2D

	#define Texture2DArray Texture2D_Array
	#define TextureCubeArray TextureCube_Array
	#define RWTexture2DArray RW_Texture2D_Array

	#define Texture2DMS MS_Texture2D

	#define	GroupMemoryBarrier					ThreadGroupMemoryBarrier
	#define	GroupMemoryBarrierWithGroupSync		ThreadGroupMemoryBarrierSync
	#define DeviceMemoryBarrier					SharedMemoryBarrier
	#define DeviceMemoryBarrierWithGroupSync	SharedMemoryBarrierSync
	#define AllMemoryBarrier					MemoryBarrier
	#define AllMemoryBarrierWithGroupSync		MemoryBarrierSync

	#define InterlockedAdd			AtomicAdd
	#define InterlockedAnd			AtomicAnd
	#define InterlockedCmpExchange	AtomicCmpExchange
	#define InterlockedCmpStore		AtomicCmpStore
	#define InterlockedExchange		AtomicExchange
	#define InterlockedMax			AtomicMax
	#define InterlockedMin			AtomicMin
	#define InterlockedOr			AtomicOr 
	#define InterlockedXor			AtomicXor

	#define reversebits				ReverseBits
	#define countbits				CountSetBits
	#define firstbitlow				FirstSetBit_Lo
	#define firstbithigh			FirstSetBit_Hi

#endif //! __ORBIS__

#if defined(PHYRE_D3DFX) && !defined(__ORBIS__)

#pragma warning(disable: 3579) // Disable vs/ps_4_0 does not support groupshared, groupshared ignored

	#define FRAG_OUTPUT_COLOR SV_TARGET
	#define FRAG_OUTPUT_COLOR0 SV_TARGET0
	#define FRAG_OUTPUT_COLOR1 SV_TARGET1
	#define FRAG_OUTPUT_COLOR2 SV_TARGET2
	#define FRAG_OUTPUT_COLOR3 SV_TARGET3
	#define FRAG_OUTPUT_COLOR4 SV_TARGET4
	#define FRAG_OUTPUT_COLOR5 SV_TARGET5
	#define FRAG_OUTPUT_COLOR6 SV_TARGET6
	#define FRAG_OUTPUT_COLOR7 SV_TARGET7
	#define FRAG_OUTPUT_DEPTH SV_DEPTH

	#define SYSTEM_PRIMITIVE_INDEX SV_PRIMITIVEID

	// Implementation of Orbis intrinsics for use on D3D11

	int mul24(int a, int b)
	{
		return a * b;
	}

	uint PackUInt2ToUInt(uint a, uint b)
	{
		return a | (b << 16);
	}

	float min3(float a, float b, float c)
	{
		return min(a, min(b, c));
	}
	float max3(float a, float b, float c)
	{
		return max(a, max(b, c));
	}

	#define GetDimensionsFast		GetDimensions

	#define UnpackByte0(f) ((float)((((uint)f) >>  0) & 0xff))
	#define UnpackByte1(f) ((float)((((uint)f) >>  8) & 0xff))
	#define UnpackByte2(f) ((float)((((uint)f) >> 16) & 0xff))
	#define UnpackByte3(f) ((float)((((uint)f) >> 24) & 0xff))

	#define ReadFirstLane(x) (x)

#endif //! defined(PHYRE_D3DFX) && !defined(__ORBIS__)

//! Define fragment shader outputs if not defined yet.
#ifndef FRAG_OUTPUT_COLOR
	#define FRAG_OUTPUT_COLOR COLOR
#endif //! FRAG_OUTPUT_COLOR

#ifndef FRAG_OUTPUT_COLOR0
	#define FRAG_OUTPUT_COLOR0 COLOR0
#endif //! FRAG_OUTPUT_COLOR0

#ifndef FRAG_OUTPUT_COLOR1
	#define FRAG_OUTPUT_COLOR1 COLOR1
#endif //! FRAG_OUTPUT_COLOR1

#ifndef FRAG_OUTPUT_COLOR2
	#define FRAG_OUTPUT_COLOR2 COLOR2
#endif //! FRAG_OUTPUT_COLOR2

#ifndef FRAG_OUTPUT_COLOR3
	#define FRAG_OUTPUT_COLOR3 COLOR3
#endif //! FRAG_OUTPUT_COLOR3

#ifndef FRAG_OUTPUT_DEPTH
	#define FRAG_OUTPUT_DEPTH DEPTH
#endif //! FRAG_OUTPUT_DEPTH

#ifndef SYSTEM_PRIMITIVE_INDEX
	#define SYSTEM_PRIMITIVE_INDEX SV_PRIMITIVEID
#endif //! SYSTEM_PRIMITIVE_INDEX

#endif //! PHYRE_SHADER_PLATFORM_H
