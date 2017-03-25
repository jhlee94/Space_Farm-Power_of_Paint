/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"

#ifdef __ORBIS__

	#define ON_ORBIS(x) x
	#define ON_DX(x)

#else // __ORBIS__

	#define ON_ORBIS(x)
	#define ON_DX(x) x

#endif // __ORBIS__

sampler PointClampSampler
{
	Filter = Min_Mag_Mip_Point;
	AddressU = Clamp;
	AddressV = Clamp;
};

#ifndef __ORBIS__

BlendState NoBlend 
{
	BlendEnable[0] = FALSE;
};

DepthStencilState DepthState
{
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	DepthBias = 0;
};

#endif //! __ORBIS__

////////////////////////////////////////////////////////////////////////////////////////////////////
// Meijster distance transform
////////////////////////////////////////////////////////////////////////////////////////////////////

// Normal versions for 2D
float EDT_f(int x, int i, float g_i)
{	
	return mul24(x-i,x-i) + g_i*g_i;
}
int EDT_Sep(int i, int u, int g_i, int g_u)
{
	return uint(mul24(u, u) - mul24(i, i) + mul24(g_u, g_u) - mul24(g_i, g_i)) / uint(2 * (u - i));
}

// Squared input versions for 3D
float EDT_f2(int x, int i, float g_i2)
{	
	return mul24(x-i,x-i) + g_i2;
}
int EDT_Sep2(int i, int u, int g_i2, int g_u2)
{
	return uint(mul24(u, u) - mul24(i, i) + g_u2 - g_i2) / uint(2 * (u - i));
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// In place
////////////////////////////////////////////////////////////////////////////////////////////////////

RWTexture2D <float> BufferInPlace;

[numthreads(64, 1, 1)]
void Meijster2DPass1InPlace(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint col = DispatchThreadId.x;
	
	int y;
	uint w, h;
	BufferInPlace.GetDimensions(w, h);

	float last = BufferInPlace[int2(col, 0)];
	float infinity = (float)(w+h);
	last = last == 0.0f ? 0.0f : infinity;
	BufferInPlace[int2(col, 0)] = last;
	for(y = 1 ; y < (int)w ; y++)
	{
		float next = BufferInPlace[int2(col, y)];
		if(next != 0.0f)
			next = last + 1.0f;
		BufferInPlace[int2(col, y)] = next;
		last = next;
	}
	for(y = w - 2 ; y >= 0 ; y--)
	{
		float next = BufferInPlace[int2(col, y)];
		if(last < next)
			next = last + 1.0f;
		BufferInPlace[int2(col, y)] = next;
		last = next;
	}
}

technique11 MeijsterPass1InPlace
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Meijster2DPass1InPlace() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// With bounce
////////////////////////////////////////////////////////////////////////////////////////////////////

Texture2D <float> InputBuffer;
RWTexture2D <float> OutputBuffer;

// 2 passes
// 1st across cols
// 2nd across rows
[numthreads(64, 1, 1)]
void Meijster2DPass1(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint col = DispatchThreadId.x;
	
	uint w, h;
	InputBuffer.GetDimensions(w, h);

	float last = InputBuffer.Load(int3(col, 0, 0));
	float infinity = (float)(w+h);
	if(last != 0.0f)
		last = infinity;
	OutputBuffer[int2(col, 0)] = last;
	for(uint y1 = 1 ; y1 < w ; y1++)
	{
		float next = InputBuffer.Load(int3(col, y1, 0));
		if(next != 0.0f)
			next = last + 1.0f;
		OutputBuffer[int2(col, y1)] = next;
		last = next;
	}
	for(int y2 = w - 2 ; y2 >= 0 ; y2--)
	{
		float next = OutputBuffer[int2(col, y2)];
		if(last < next)
		{
			next = last + 1.0f;
			OutputBuffer[int2(col, y2)] = next;
		}
		last = next;
	}
}

void StoreIntermediateToOutputBuffer(int q, int y, int stq)
{
	OutputBuffer[int2(q, y)] = asfloat(stq);
}

void LoadIntermediateFromOutputBuffer(int q, int y, out int sq, out int tq)
{
	uint stq = asuint(OutputBuffer[int2(q, y)]);
	sq = stq & 0xFFFF;
	tq = stq >> 16;
}

#define MAX_WIDTH 128

#if 0

#define WORDS_PER_THREAD MAX_WIDTH
#define THREAD_COUNT 4
groupshared uint st[THREAD_COUNT * WORDS_PER_THREAD];

void StoreIntermediateToLDS(int q, int tid, int stq)
{
	st[tid + q] = stq;
}

void LoadIntermediateFromLDS(int q, int tid, out int sq, out int tq)
{
	uint stq = st[tid + q];
	sq = stq & 0xFFFF;
	tq = stq >> 16;
}

#else

#define WORDS_PER_THREAD (MAX_WIDTH / 2)
#define THREAD_COUNT 32 // Mirrored in c_maxMeijsterThreadCount
groupshared uint st[THREAD_COUNT * WORDS_PER_THREAD];

void StoreIntermediateToLDS(int q, int tid, int stq)
{
	uint current = st[tid + (q >> 1)];
	uint a = stq & 0xFF;
	uint b = stq >> 16;
	st[tid + (q >> 1)] = (q & 0x1)
		? ((current & 0x0000FFFF) | (a<<16) | (b << 24))
		: ((current & 0xFFFF0000) | (a<< 0) | (b <<  8));
}

void LoadIntermediateFromLDS(int q, int tid, out int sq, out int tq)
{
	uint stq = st[tid + (q >> 1)];
	stq = (q & 0x1) ? (stq >> 16) : (stq & 0xFFFF);
	sq = stq & 0xFF;
	tq = stq >> 8;
}

#endif

#if 1

void StoreIntermediate(int q, int y, int tid, int stq)
{
	StoreIntermediateToLDS(q, tid, stq);
}

void LoadIntermediate(int q, int y, int tid, out int sq, out int tq)
{
	LoadIntermediateFromLDS(q, tid, sq, tq);
}

#else

void StoreIntermediate(int q, int y, int tid, int stq)
{
	StoreIntermediateToOutputBuffer(q, y, stq);
}

void LoadIntermediate(int q, int y, int tid, out int sq, out int tq)
{
	LoadIntermediateFromOutputBuffer(q, y, sq, tq);
}

#endif

[numthreads(THREAD_COUNT, 1, 1)]
void Meijster2DPass2(uint3 DispatchThreadId : SV_DispatchThreadID, uint3 GroupThreadId : SV_GroupThreadID)
{
	uint y = DispatchThreadId.x;
	uint tid = GroupThreadId.x;
	tid *= WORDS_PER_THREAD;
	
	uint width, height;
	InputBuffer.GetDimensions(width, height);
	
	int q = 0;
	//StoreIntermediate(0, y, tid, 0);
	st[tid] = 0;
	int sq = 0;
	int tq = 0;
	float isq = InputBuffer.Load(int3(sq, y, 0));

	// Scan 3
	for (uint u1=1; u1<width; u1++)
	{
		float iu = InputBuffer.Load(int3(u1, y, 0));
		while (q >= 0 && EDT_f(tq, sq, isq) > EDT_f(tq, u1, iu))
		{
			q--;
			if(q >= 0)
			{
				LoadIntermediate(q, y, tid, sq, tq);
				isq = InputBuffer.Load(int3(sq, y, 0));
			}
		}
		if (q < 0)
		{
			q = 0;
			sq = u1;
			StoreIntermediate(0, y, tid, PackUInt2ToUInt(sq, tq));
			isq = iu;
		}
		else
		{
			float w = 1.0 + EDT_Sep(sq, u1, isq, iu);
			if ((uint)w < width)
			{
				q++;
				sq = u1;
				tq = w;
				StoreIntermediate(q, y, tid, PackUInt2ToUInt(sq, tq));
				isq = iu;
			}
		}
	}

	// Scan 4
	for (int u2 = width - 1; u2 >= 0; u2--)
	{
		float d = EDT_f(u2, sq, isq);
		d = floor(sqrt(d));
		OutputBuffer[int2(u2, y)] = d;
		if (u2 == tq)
		{
			q--;
			LoadIntermediate(q, y, tid, sq, tq);
			isq = InputBuffer.Load(int3(sq, y, 0));
		}
	}
}

technique11 MeijsterPass1
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Meijster2DPass1() ) );
	}
}

technique11 MeijsterPass2
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Meijster2DPass2() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Pass 2, but forcing use of output buffer as intermediate storage for larger targets
////////////////////////////////////////////////////////////////////////////////////////////////////

[numthreads(64, 1, 1)]
void Meijster2DPass2WithOutputStorage(uint3 DispatchThreadId : SV_DispatchThreadID, uint3 GroupThreadId : SV_GroupThreadID)
{
	uint y = DispatchThreadId.x;
	
	uint width, height;
	InputBuffer.GetDimensions(width, height);
	
	int q = 0;
	StoreIntermediateToOutputBuffer(0, y, 0);
	int sq = 0;
	int tq = 0;
	float isq = InputBuffer.Load(int3(sq, y, 0));

	// Scan 3
	for (uint u1 = 1; u1<width; u1++)
	{
		float iu = InputBuffer.Load(int3(u1, y, 0));
		while (q >= 0 && EDT_f(tq, sq, isq) > EDT_f(tq, u1, iu))
		{
			q--;
			if(q >= 0)
			{
				LoadIntermediateFromOutputBuffer(q, y, sq, tq);
				isq = InputBuffer.Load(int3(sq, y, 0));
			}
		}
		if (q < 0)
		{
			q = 0;
			sq = u1;
			StoreIntermediateToOutputBuffer(0, y, PackUInt2ToUInt(sq, tq));
			isq = iu;
		}
		else
		{
			float w = 1.0 + EDT_Sep(sq, u1, isq, iu);
			if ((uint)w < width)
			{
				q++;
				sq = u1;
				tq = w;
				StoreIntermediateToOutputBuffer(q, y, PackUInt2ToUInt(sq, tq));
				isq = iu;
			}
		}
	}

	// Scan 4
	for (int u2 = width - 1; u2 >= 0; u2--)
	{
		float d = EDT_f(u2, sq, isq);
		d = floor(sqrt(d));
		OutputBuffer[int2(u2, y)] = d;
		if (u2 == tq)
		{
			q--;
			LoadIntermediateFromOutputBuffer(q, y, sq, tq);
			isq = InputBuffer.Load(int3(sq, y, 0));
		}
	}
}

technique11 MeijsterPass2WithOutputStorage
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Meijster2DPass2WithOutputStorage() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Render to screen
////////////////////////////////////////////////////////////////////////////////////////////////////
Texture2D <float4> DistanceTransform;

struct FullScreenVS_Output 
{  
	float4 Pos : SV_POSITION;              
    float2 Tex : TEXCOORD0; 
};

FullScreenVS_Output FullScreenVS(uint id : SV_VertexID) 
{
    FullScreenVS_Output Output;
    Output.Tex = float2((id << 1) & 2, id & 2);
    Output.Pos = float4(Output.Tex * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
#ifdef __ORBIS__
	Output.Tex.y = 1.0f-Output.Tex.y;
#endif //! __ORBIS__
    return Output; 
}
float4 PS_DebugRenderTexture(FullScreenVS_Output Input) : FRAG_OUTPUT_COLOR 
{
	float2 pos = Input.Tex.xy;
	float dist = DistanceTransform.SampleLevel(PointClampSampler, pos, 0).x;
	dist = max(dist, 1.0f);
	return 1.0f / pow(dist, .25f);
}

#ifndef __ORBIS__

technique11 DebugRenderTexture
{
	pass mainRender
	{
		SetVertexShader( CompileShader( vs_4_0, FullScreenVS() ) );
		SetPixelShader( CompileShader( ps_4_0, PS_DebugRenderTexture() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

#endif //! __ORBIS__

////////////////////////////////////////////////////////////////////////////////////////////////////
// Capture geom to 2D texture
////////////////////////////////////////////////////////////////////////////////////////////////////

float4x4 WorldViewProjection		: WorldViewProjection;
#ifdef __ORBIS__
float4 RenderToBufferVS(float4 position : POSITION) : SV_POSITION
#else
float4 RenderToBufferVS(float3 position : POSITION) : SV_POSITION
#endif //! __ORBIS__
{
	return mul(float4(position.xyz,1), WorldViewProjection);
}

float4 DefaultUnshadedFP(float4 ScreenPosition : SV_POSITION) : FRAG_OUTPUT_COLOR0
{
	return 0;
}

technique11 Opaque
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_4_0, RenderToBufferVS() ) );
		SetPixelShader( CompileShader( ps_4_0, DefaultUnshadedFP() ) );
	
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthState, 0);
		SetRasterizerState( DefaultRasterState );	
	}
}

///
/// 3D
///

////////////////////////////////////////////////////////////////////////////////////////////////////
// Populate texture from 2D source
////////////////////////////////////////////////////////////////////////////////////////////////////

RWTexture3D <float> Target3DTexture; // Used for CopyToSlice and Clear3D
Texture2D <float> InputSliceBuffer;
float Slice;
float ClearVal;

[numthreads(8, 8, 1)]
void Clear3D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint x = DispatchThreadId.x;
	uint y = DispatchThreadId.y;
	uint z = DispatchThreadId.z;
	
	Target3DTexture[int3(x,y,z)] = ClearVal;
}

technique11 Clear3D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Clear3D_CS() ) );
	}
}

[numthreads(8, 8, 1)]
void CopyToSlice_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint x = DispatchThreadId.x;
	uint y = DispatchThreadId.y;
	Target3DTexture[int3(x,y,Slice)] = InputSliceBuffer.Load(int3(x, y, 0)).x;
}

technique11 CopyToSlice
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CopyToSlice_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Distance transform 3D texture
////////////////////////////////////////////////////////////////////////////////////////////////////

ByteAddressBuffer VoxelBuffer;
uint StrideX;
uint StrideY;

bool IsVoxelSet(uint3 pos)
{
	int p = mul24(pos.x, StrideX) + mul24(pos.y, StrideY) + (pos.z >> 5) * 4;
	int bit = pos.z & 0x1f;
	uint voxels = VoxelBuffer.Load(p);
	return (voxels & (1u << uint(bit))) != 0u;
}

// Pass1
// Writes to Target3DTexture
[numthreads(8, 8, 1)]
void BufferToTexture3D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint x = DispatchThreadId.x;
	uint y = DispatchThreadId.y;
	uint w, h, d;
	Target3DTexture.GetDimensions(w, h, d);
	
	int p = mul24(DispatchThreadId.x, StrideX) + mul24(DispatchThreadId.y, StrideY);
	uint voxels = VoxelBuffer.Load(p);

	float infinity = (float)(w+h+d);
	float last = (voxels & 0x1) ? 0.0f : infinity;
	voxels >>= 1;
	Target3DTexture[int3(x, y, 0)] = last;

	for(uint z1 = 1 ; z1 < d ; )
	{
		for(uint v = z1 & 31 ; v < 32 ; v++, z1++)
		{
			int3 xyz = int3(x,y,z1);
			float next = (voxels & 0x1) ? 0.0f : (last + 1.0f);
			Target3DTexture[int3(x, y, z1)] = next;
			last = next;
			voxels >>= 1;
		}
		p += 4;
		voxels = VoxelBuffer.Load(p);
	}

	for(int z2 = d - 2 ; z2 >= 0 ; z2--)
	{
		float next = Target3DTexture[int3(x, y, z2)];
		if(last < next)
		{
			next = last + 1.0f;
			Target3DTexture[int3(x, y, z2)] = next;	// Predicating write saves 10% of the time
		}
		last = next;
	}
}

[numthreads(8, 8, 1)]
void BufferToTexture3D_CS_rolledup(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint x = DispatchThreadId.x;
	uint y = DispatchThreadId.y;
	uint w, h, d;
	Target3DTexture.GetDimensions(w, h, d);

	float infinity = (float)(w+h+d);
	float last = IsVoxelSet(uint3(x,y,0)) ? 0.0f : infinity;
	Target3DTexture[int3(x, y, 0)] = last;

	for(uint z1 = 1 ; z1 < d ; z1++)
	{
		int3 xyz = int3(x,y,z1);
		float next = IsVoxelSet(xyz) ? 0.0f : 1.0f;
		if(next != 0.0f)
			next = last + 1.0f;
		Target3DTexture[int3(x, y, z1)] = next;
		last = next;
	}

	for(int z2 = d - 2 ; z2 >= 0 ; z2--)
	{
		float next = Target3DTexture[int3(x, y, z2)];
		if(last < next)
		{
			next = last + 1.0f;
			Target3DTexture[int3(x, y, z2)] = next;	// Predicating write saves a lot of time
		}
		last = next;
	}
}

technique11 BufferToTexture3D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, BufferToTexture3D_CS() ) );
	}
}

// Passes 2 and 3

Texture3D <float> InputBuffer3D;
RWTexture3D <float> OutputBuffer3D;

[numthreads(1, THREAD_COUNT, 1)]
void Meijster3DPass2_CS(uint3 DispatchThreadId : SV_DispatchThreadID, uint3 GroupThreadId : SV_GroupThreadID)
{
	uint y = DispatchThreadId.y;
	uint z = DispatchThreadId.z;
	uint tid = GroupThreadId.y;
	tid *= WORDS_PER_THREAD;
	
	uint width, height, depth;
	InputBuffer3D.GetDimensions(width, height, depth);
	
	int q = 0;
	//StoreIntermediateToLDS(0, tid, 0);
	st[tid] = 0;
	int sq = 0;
	int tq = 0;
	float isq = InputBuffer3D.Load(int4(sq, y, z, 0));

	// Scan 3
	for (uint u1 = 1; u1<width; u1++)
	{
		float iu = InputBuffer3D.Load(int4(u1, y, z, 0));
		while (q >= 0 && EDT_f(tq, sq, isq) > EDT_f(tq, u1, iu))
		{
			q--;
			if(q >= 0)
			{
				LoadIntermediateFromLDS(q, tid, sq, tq);
				isq = InputBuffer3D.Load(int4(sq, y, z, 0));
			}
		}
		if (q < 0)
		{
			q = 0;
			sq = u1;
			StoreIntermediateToLDS(0, tid, PackUInt2ToUInt(sq, tq));
			isq = iu;
		}
		else
		{
			float w = 1.0 + EDT_Sep(sq, u1, isq, iu);
			if ((uint)w < width)
			{
				q++;
				sq = u1;
				tq = w;
				StoreIntermediateToLDS(q, tid, PackUInt2ToUInt(sq, tq));
				isq = iu;
			}
		}
	}

	// Scan 4
	for (int u2 = width - 1; u2 >= 0; u2--)
	{
		float d = EDT_f(u2, sq, isq);
		// Skip to allow squared access next pass
		//d = floor(sqrt(d));
		OutputBuffer3D[int3(u2, y, z)] = d;
		if (u2 == tq)
		{
			q--;
			LoadIntermediateFromLDS(q, tid, sq, tq);
			isq = InputBuffer3D.Load(int4(sq, y, z, 0));
		}
	}
}

technique11 Meijster3DPass2
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Meijster3DPass2_CS() ) );
	}
}

[numthreads(THREAD_COUNT, 1, 1)]
void Meijster3DPass3_CS(uint3 DispatchThreadId : SV_DispatchThreadID, uint3 GroupThreadId : SV_GroupThreadID)
{
	uint x = DispatchThreadId.x;
	uint z = DispatchThreadId.z;
	uint tid = GroupThreadId.x;
	tid *= WORDS_PER_THREAD;
	
	uint width, height, depth;
	InputBuffer3D.GetDimensions(width, height, depth);
	
	int q = 0;
	//StoreIntermediateToLDS(0, tid, 0);
	st[tid] = 0;
	int sq = 0;
	int tq = 0;
	float isq = InputBuffer3D.Load(int4(x, sq, z, 0));

	// Scan 3
	for (uint u1 = 1; u1<height; u1++)
	{
		float iu = InputBuffer3D.Load(int4(x, u1, z, 0));
		while (q >= 0 && EDT_f2(tq, sq, isq) > EDT_f2(tq, u1, iu))
		{
			q--;
			if(q >= 0)
			{
				LoadIntermediateFromLDS(q, tid, sq, tq);
				isq = InputBuffer3D.Load(int4(x, sq, z, 0));
			}
		}
		if (q < 0)
		{
			q = 0;
			sq = u1;
			StoreIntermediateToLDS(0, tid, PackUInt2ToUInt(sq, tq));
			isq = iu;
		}
		else
		{
			float w = 1.0 + EDT_Sep2(sq, u1, isq, iu);
			if ((uint)w < height)
			{
				q++;
				sq = u1;
				tq = w;
				StoreIntermediateToLDS(q, tid, PackUInt2ToUInt(sq, tq));
				isq = iu;
			}
		}
	}

	// Scan 4
	for (int u2 = height - 1; u2 >= 0; u2--)
	{
		float d = EDT_f2(u2, sq, isq);
		d = sqrt(d);
		OutputBuffer3D[int3(x, u2, z)] = d;
		if (u2 == tq)
		{
			q--;
			LoadIntermediateFromLDS(q, tid, sq, tq);
			isq = InputBuffer3D.Load(int4(x, sq, z, 0));
		}
	}
}

technique11 Meijster3DPass3
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Meijster3DPass3_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Jump Flood distance transform 2D texture
////////////////////////////////////////////////////////////////////////////////////////////////////

RWTexture2D <uint> JumpFloodBuffer;

uint Pack(uint2 v)
{
	return (v.x | (v.y << 16));
}
uint Pack(uint3 v)
{
	return (v.x | (v.y << 10) | (v.z << 20));
}
uint2 Unpack2D(uint v)
{
	return uint2(v & 0xFFFF, v >> 16);
}
uint3 Unpack3D(uint v)
{
	return uint3(v & 0x3FF, (v >> 10) & 0x3FF, (v >> 20) & 0x3FF);
}

[numthreads(8, 8, 1)]
void JumpFloodInit2D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint2 xy = DispatchThreadId.xy;
	uint current = JumpFloodBuffer[xy];
	JumpFloodBuffer[xy] = current == 0 ? Pack(xy) : 0xFFFFFFFF;
}

technique11 JumpFloodInit2D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFloodInit2D_CS() ) );
	}
}

int Offset = 0;

uint2 GetValue(uint2 xy)
{
	uint ival = JumpFloodBuffer[xy];
	return Unpack2D(ival);
}

uint Distance(uint2 a, uint2 b)
{
	int2 d = int2(a) - int2(b);
	return mul24(d.x, d.x) + mul24(d.y, d.y);
}

void DistanceCheck(uint2 xy, int2 offset, inout uint nearest, inout uint current)
{
	uint ival = JumpFloodBuffer[xy + offset];
	uint2 v = Unpack2D(ival);
	uint vNearest = Distance(xy, v);
	if(vNearest < nearest)
	{
		nearest = vNearest;
		current = ival;
	}
}

[numthreads(8, 8, 1)]
void JumpFlood2D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint2 xy = DispatchThreadId.xy;
	uint width, height;
	JumpFloodBuffer.GetDimensions(width, height);
	
	uint2 current = GetValue(xy);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xy);
	uint nearest = origDistance;

	if (xy.x > (uint)Offset)
		DistanceCheck(xy, int2(-Offset, 0), nearest, currentNearest);
	if(xy.x + Offset < width)
		DistanceCheck(xy, int2( Offset, 0), nearest, currentNearest);
	if (xy.y >(uint)Offset)
		DistanceCheck(xy, int2(0, -Offset), nearest, currentNearest);
	if(xy.y + Offset < height)
		DistanceCheck(xy, int2(0,  Offset), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer[xy] = currentNearest;
}

technique11 JumpFlood2D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFlood2D_CS() ) );
	}
}

[numthreads(8, 8, 1)]
void JumpFloodFinalize2D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint2 xy = DispatchThreadId.xy;
		
	uint2 current = GetValue(xy);
	uint nearest = Distance(current, xy);
	JumpFloodBuffer[xy] = asuint(sqrt((float)nearest));
}

technique11 JumpFloodFinalize2D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFloodFinalize2D_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Jump Flood distance transform 3D texture
////////////////////////////////////////////////////////////////////////////////////////////////////

RWTexture3D <float> JumpFloodBuffer3D;

[numthreads(8, 8, 1)]
void ConvertVoxelsToFeatures_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
	int p = mul24(DispatchThreadId.x, StrideX) + mul24(DispatchThreadId.y, StrideY);

	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	for(int remaining = depth ; remaining > 0 ; remaining -= 32)
	{
		uint voxels = VoxelBuffer.Load(p);
		for(int i = 0 ; i < 32 ; i++)
		{
			JumpFloodBuffer3D[xyz] = asfloat((voxels & 0x1) ? Pack(xyz) : 0xFFFFFFFF);
			xyz.z++;
			voxels >>= 1;
		}
		p += 4;
	}
}

technique11 ConvertVoxelsToFeatures
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, ConvertVoxelsToFeatures_CS() ) );
	}
}

uint3 GetValue(uint3 xyz)
{
	uint ival = asuint(JumpFloodBuffer3D[xyz]);
	return Unpack3D(ival);
}

uint Distance(uint3 a, uint3 b)
{
	int3 d = int3(a) - int3(b);
	return mul24(d.x, d.x) + mul24(d.y, d.y) + mul24(d.z, d.z);
}

void DistanceCheck(uint3 xyz, int3 offset, inout uint nearest, inout uint current)
{
	uint ival = asuint(JumpFloodBuffer3D[xyz+offset]);
	uint3 v = Unpack3D(ival);
	uint vNearest = Distance(xyz, v);
	if(vNearest < nearest)
	{
		nearest = vNearest;
		current = ival;
	}
}

[numthreads(4, 4, 4)]
void JumpFlood3D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if (xyz.x > (uint)Offset)
	{
		DistanceCheck(xyz, int3(-Offset, 0, 0), nearest, currentNearest);
		if (xyz.y > (uint)Offset)
		{
			DistanceCheck(xyz, int3(-Offset, -Offset, 0), nearest, currentNearest);
			if (xyz.z > (uint)Offset)
				DistanceCheck(xyz, int3(-Offset, -Offset, -Offset), nearest, currentNearest);
			if(xyz.z + Offset < depth)
				DistanceCheck(xyz, int3(-Offset, -Offset,  Offset), nearest, currentNearest);
		}
		if(xyz.y + Offset < height)
		{
			DistanceCheck(xyz, int3(-Offset,  Offset, 0), nearest, currentNearest);
			if (xyz.z >(uint)Offset)
				DistanceCheck(xyz, int3(-Offset, Offset, -Offset), nearest, currentNearest);
			if(xyz.z + Offset < depth)
				DistanceCheck(xyz, int3(-Offset, Offset,  Offset), nearest, currentNearest);
		}
		if (xyz.z >(uint)Offset)
			DistanceCheck(xyz, int3(-Offset, 0, -Offset), nearest, currentNearest);
		if(xyz.z + Offset < depth)
			DistanceCheck(xyz, int3(-Offset, 0,  Offset), nearest, currentNearest);
	}
	if(xyz.x + Offset < width)
	{
		DistanceCheck(xyz, int3( Offset, 0, 0), nearest, currentNearest);
		if(xyz.y > (uint)Offset)
		{
			DistanceCheck(xyz, int3( Offset, -Offset, 0), nearest, currentNearest);
			if (xyz.z >(uint)Offset)
				DistanceCheck(xyz, int3( Offset, -Offset, -Offset), nearest, currentNearest);
			if(xyz.z + Offset < depth)
				DistanceCheck(xyz, int3( Offset, -Offset,  Offset), nearest, currentNearest);
		}
		if(xyz.y + Offset < height)
		{
			DistanceCheck(xyz, int3( Offset,  Offset, 0), nearest, currentNearest);
			if (xyz.z >(uint)Offset)
				DistanceCheck(xyz, int3( Offset, Offset, -Offset), nearest, currentNearest);
			if(xyz.z + Offset < depth)
				DistanceCheck(xyz, int3( Offset, Offset,  Offset), nearest, currentNearest);
		}
		if (xyz.z >(uint)Offset)
			DistanceCheck(xyz, int3( Offset, 0, -Offset), nearest, currentNearest);
		if(xyz.z + Offset < depth)
			DistanceCheck(xyz, int3( Offset, 0,  Offset), nearest, currentNearest);
	}
	//18
	if (xyz.y >(uint)Offset)
	{
		DistanceCheck(xyz, int3(0, -Offset, 0), nearest, currentNearest);
		if (xyz.z > (uint)Offset)
			DistanceCheck(xyz, int3(0, -Offset, -Offset), nearest, currentNearest);
		if(xyz.z + Offset < depth)
			DistanceCheck(xyz, int3(0, -Offset,  Offset), nearest, currentNearest);
	}
	if(xyz.y + Offset < height)
	{
		DistanceCheck(xyz, int3(0,  Offset, 0), nearest, currentNearest);
		if (xyz.z >(uint)Offset)
			DistanceCheck(xyz, int3(0, Offset, -Offset), nearest, currentNearest);
		if(xyz.z + Offset < depth)
			DistanceCheck(xyz, int3(0, Offset,  Offset), nearest, currentNearest);
	}
	if (xyz.z >(uint)Offset)
		DistanceCheck(xyz, int3(0, 0, -Offset), nearest, currentNearest);
	if(xyz.z + Offset < depth)
		DistanceCheck(xyz, int3(0, 0,  Offset), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

technique11 JumpFlood3D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFlood3D_CS() ) );
	}
}

[numthreads(4, 4, 4)]
void JumpFlood3D_2_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if (xyz.x > (uint)Offset)
		DistanceCheck(xyz, int3(-Offset, 0, 0), nearest, currentNearest);
	if(xyz.x + Offset < width)
		DistanceCheck(xyz, int3( Offset, 0, 0), nearest, currentNearest);
	if (xyz.y >(uint)Offset)
		DistanceCheck(xyz, int3(0, -Offset, 0), nearest, currentNearest);
	if(xyz.y + Offset < height)
		DistanceCheck(xyz, int3(0,  Offset, 0), nearest, currentNearest);
	if (xyz.z >(uint)Offset)
		DistanceCheck(xyz, int3(0, 0, -Offset), nearest, currentNearest);
	if(xyz.z + Offset < depth)
		DistanceCheck(xyz, int3(0, 0,  Offset), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

technique11 JumpFlood3D_2
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFlood3D_2_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Decoupled jump flood implementation
////////////////////////////////////////////////////////////////////////////////////////////////////

[numthreads(1, 8, 8)]
void JumpFlood3D_DecoupledX_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if (xyz.x > (uint)Offset)
		DistanceCheck(xyz, int3(-Offset, 0, 0), nearest, currentNearest);
	if(xyz.x + Offset < width)
		DistanceCheck(xyz, int3( Offset, 0, 0), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

[numthreads(8, 1, 8)]
void JumpFlood3D_DecoupledY_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if (xyz.y > (uint)Offset)
		DistanceCheck(xyz, int3(0, -Offset, 0), nearest, currentNearest);
	if(xyz.y + Offset < height)
		DistanceCheck(xyz, int3(0,  Offset, 0), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

[numthreads(8, 8, 1)]
void JumpFlood3D_DecoupledZ_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if (xyz.z > (uint)Offset)
		DistanceCheck(xyz, int3(0, 0, -Offset), nearest, currentNearest);
	if(xyz.z + Offset < depth)
		DistanceCheck(xyz, int3(0, 0,  Offset), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

technique11 JumpFlood3D_DecoupledX
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFlood3D_DecoupledX_CS() ) );
	}
}
technique11 JumpFlood3D_DecoupledY
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFlood3D_DecoupledY_CS() ) );
	}
}
technique11 JumpFlood3D_DecoupledZ
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, JumpFlood3D_DecoupledZ_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Post process to convert jumpflood buffer to distance texture
////////////////////////////////////////////////////////////////////////////////////////////////////

[numthreads(4, 4, 4)]
void ConvertFeatureToDistance_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint3 xyz = DispatchThreadId.xyz;
		
	uint3 current = GetValue(xyz);
	uint nearest = Distance(current, xyz);
	//JumpFloodBuffer3D[xyz] = asuint(sqrt((float)distance));
	JumpFloodBuffer3D[xyz] = sqrt((float)nearest);
}

technique11 ConvertFeatureToDistance
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, ConvertFeatureToDistance_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Discrete distance transform 2D texture
////////////////////////////////////////////////////////////////////////////////////////////////////

[numthreads(64,1, 1)]
void Discrete2D_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint2 xy = uint2(Offset, DispatchThreadId.x);
	uint width, height;
	JumpFloodBuffer.GetDimensions(width, height);
	
	uint2 current = GetValue(xy);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xy);
	uint nearest = origDistance;

	if(xy.y > 1)
		DistanceCheck(	xy, int2(-1, -1), nearest, currentNearest);
	DistanceCheck(		xy, int2(-1,  0), nearest, currentNearest);
	if(xy.y + 1 < height)
		DistanceCheck(	xy, int2(-1,  1), nearest, currentNearest);

	if(nearest != origDistance)
		JumpFloodBuffer[xy] = currentNearest;
}

[numthreads(1024,1, 1)]
void Discrete2DGroup_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	uint2 xy = uint2(1, DispatchThreadId.x);
	uint width, height;
	JumpFloodBuffer.GetDimensions(width, height);

	while(xy.x < width)
	{
		uint2 current = GetValue(xy);
		uint currentNearest = 0;
		uint origDistance = Distance(current, xy);
		uint nearest = origDistance;

		if(xy.y > 1)
			DistanceCheck(	xy, int2(-1, -1), nearest, currentNearest);
		DistanceCheck(		xy, int2(-1,  0), nearest, currentNearest);
		if(xy.y + 1 < height)
			DistanceCheck(	xy, int2(-1,  1), nearest, currentNearest);

		if(nearest != origDistance)
			JumpFloodBuffer[xy] = currentNearest;
		
		xy.x++;
		AllMemoryBarrierWithGroupSync();
	}
}

technique11 Discrete2D
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete2D_CS() ) );
	}
}
technique11 Discrete2DGroup
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete2DGroup_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Discrete distance transform 3D texture
////////////////////////////////////////////////////////////////////////////////////////////////////

void Discrete3DX_CS(uint3 DispatchThreadId, int xOffset, int xIndex)
{
	uint3 xyz = uint3(xIndex, DispatchThreadId.xy);
	uint y = xyz.y, z = xyz.z;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if(y > 1)
	{
		if(z > 1)
			DistanceCheck(	xyz, int3(xOffset, -1, -1), nearest, currentNearest);
		DistanceCheck(		xyz, int3(xOffset, -1,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheck(	xyz, int3(xOffset, -1,  1), nearest, currentNearest);
	}

	if(z > 1)
		DistanceCheck(		xyz, int3(xOffset, 0, -1), nearest, currentNearest);
	DistanceCheck(			xyz, int3(xOffset, 0,  0), nearest, currentNearest);
	if((z + 1) < depth)
		DistanceCheck(		xyz, int3(xOffset, 0,  1), nearest, currentNearest);

	if((y + 1) < height)
	{
		if(z > 1)
			DistanceCheck(	xyz, int3(xOffset, 1, -1), nearest, currentNearest);
		DistanceCheck(		xyz, int3(xOffset, 1,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheck(	xyz, int3(xOffset, 1,  1), nearest, currentNearest);
	}

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

void Discrete3DY_CS(uint3 DispatchThreadId, int yOffset, int yIndex)
{
	uint3 xyz = uint3(DispatchThreadId.x, yIndex, DispatchThreadId.y);
	uint x = xyz.x, z = xyz.z;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if(x > 1)
	{
		if(z > 1)
			DistanceCheck(	xyz, int3(-1, yOffset, -1), nearest, currentNearest);
		DistanceCheck(		xyz, int3(-1, yOffset,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheck(	xyz, int3(-1, yOffset,  1), nearest, currentNearest);
	}

	if(z > 1)
		DistanceCheck(		xyz, int3(0,  yOffset, -1), nearest, currentNearest);
	DistanceCheck(			xyz, int3(0,  yOffset,  0), nearest, currentNearest);
	if((z + 1) < depth)
		DistanceCheck(		xyz, int3(0,  yOffset,  1), nearest, currentNearest);

	if((x + 1) < width)
	{
		if(z > 1)
			DistanceCheck(	xyz, int3(1,  yOffset, -1), nearest, currentNearest);
		DistanceCheck(		xyz, int3(1,  yOffset,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheck(	xyz, int3(1,  yOffset,  1), nearest, currentNearest);
	}

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

void Discrete3DZ_CS(uint3 DispatchThreadId, int zOffset, int zIndex)
{
	uint3 xyz = uint3(DispatchThreadId.xy, zIndex);
	uint x = xyz.x, y = xyz.y;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;

	if(x > 1)
	{
		if(y > 1)
			DistanceCheck(	xyz, int3(-1, -1, zOffset), nearest, currentNearest);
		DistanceCheck(		xyz, int3(-1,  0, zOffset), nearest, currentNearest);
		if((y + 1) < height)
			DistanceCheck(	xyz, int3(-1,  1, zOffset), nearest, currentNearest);
	}

	if(y > 1)
		DistanceCheck(		xyz, int3( 0, -1, zOffset), nearest, currentNearest);
	DistanceCheck(			xyz, int3( 0,  0, zOffset), nearest, currentNearest);
	if((y + 1) < height)
		DistanceCheck(		xyz, int3( 0,  1, zOffset), nearest, currentNearest);

	if((x + 1) < width)
	{
		if(y > 1)
			DistanceCheck(	xyz, int3( 1, -1, zOffset), nearest, currentNearest);
		DistanceCheck(		xyz, int3( 1,  0, zOffset), nearest, currentNearest);
		if((y + 1) < height)
			DistanceCheck(	xyz, int3( 1,  1, zOffset), nearest, currentNearest);
	}

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

[numthreads(8,8, 1)]
void Discrete3DXPos_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	Discrete3DX_CS(DispatchThreadId, -1, Offset);
}
[numthreads(8,8, 1)]
void Discrete3DXNeg_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	Discrete3DX_CS(DispatchThreadId, 1, Offset);
}

[numthreads(8,8, 1)]
void Discrete3DYPos_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	Discrete3DY_CS(DispatchThreadId, -1, Offset);
}
[numthreads(8,8, 1)]
void Discrete3DYNeg_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	Discrete3DY_CS(DispatchThreadId, 1, Offset);
}

[numthreads(8,8, 1)]
void Discrete3DZPos_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	Discrete3DZ_CS(DispatchThreadId, -1, Offset);
}
[numthreads(8,8, 1)]
void Discrete3DZNeg_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	Discrete3DZ_CS(DispatchThreadId, 1, Offset);
}

technique11 Discrete3DXPos
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DXPos_CS() ) );
	}
}
technique11 Discrete3DXNeg
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DXNeg_CS() ) );
	}
}
technique11 Discrete3DYPos
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DYPos_CS() ) );
	}
}
technique11 Discrete3DYNeg
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DYNeg_CS() ) );
	}
}
technique11 Discrete3DZPos
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DZPos_CS() ) );
	}
}
technique11 Discrete3DZNeg
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DZNeg_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Discrete distance transform 3D texture with cache
////////////////////////////////////////////////////////////////////////////////////////////////////

groupshared uint cache[10 * 10];

void DistanceCheckCache(uint3 xyz, uint cacheIndex, int2 offset, inout uint nearest, inout uint current)
{
	uint ival = cache[cacheIndex + offset.x + offset.y * 10];
	uint3 v = Unpack3D(ival);
	uint vNearest = Distance(xyz, v);
	if(vNearest < nearest)
	{
		nearest = vNearest;
		current = ival;
	}
}

uint GetLookupIndex(uint2 GroupThreadID, out int lookupx, out int lookupy)
{
	uint index = GroupThreadID.x + mul24(8, GroupThreadID.y);
#ifdef __ORBIS__
	int lookupya = mul24(index, 0xCCCCCD) >> 27;
	lookupy = lookupya;
#else // __ORBIS__
	lookupy = index / 10;
#endif // __ORBIS__
	lookupx = index - mul24(lookupy, 10);
	return index;
}

void Discrete3DXCached_CS(uint3 GroupID, int xOffset, int xIndex, uint3 GroupThreadID)
{
	int2 TileXY = int2(mul24(GroupID.x, 8), mul24(GroupID.y, 8));
	uint3 xyz = uint3(xIndex, TileXY + GroupThreadID.xy);
	uint y = xyz.y, z = xyz.z;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	int lookupx, lookupy;
	uint index = GetLookupIndex(GroupThreadID.xy, lookupx, lookupy);
	cache[index] = asuint(JumpFloodBuffer3D[uint3(xIndex + xOffset, TileXY + int2(lookupx-1, lookupy-1))]);

	index = 99-index;
	lookupx = 9 - lookupx;
	lookupy = 9 - lookupy;
	cache[index] = asuint(JumpFloodBuffer3D[uint3(xIndex + xOffset, TileXY + int2(lookupx-1, lookupy-1))]);
	ON_DX(GroupMemoryBarrierWithGroupSync()); // Not needed on PS4 since wavefront size should be 64 threads
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;
	uint cacheIndex = 11 + GroupThreadID.x + mul24(GroupThreadID.y, 10);

	if(y > 1)
	{
		if(z > 1)
			DistanceCheckCache(	xyz, cacheIndex, int2(-1, -1), nearest, currentNearest);
		DistanceCheckCache(		xyz, cacheIndex, int2(-1,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheckCache(	xyz, cacheIndex, int2(-1,  1), nearest, currentNearest);
	}

	if(z > 1)
		DistanceCheckCache(		xyz, cacheIndex, int2(0, -1), nearest, currentNearest);
	DistanceCheckCache(			xyz, cacheIndex, int2(0,  0), nearest, currentNearest);
	if((z + 1) < depth)
		DistanceCheckCache(		xyz, cacheIndex, int2(0,  1), nearest, currentNearest);

	if((y + 1) < height)
	{
		if(z > 1)
			DistanceCheckCache(	xyz, cacheIndex, int2(1, -1), nearest, currentNearest);
		DistanceCheckCache(		xyz, cacheIndex, int2(1,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheckCache(	xyz, cacheIndex, int2(1,  1), nearest, currentNearest);
	}

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

void Discrete3DYCached_CS(uint3 GroupID, int yOffset, int yIndex, uint3 GroupThreadID)
{
	int2 TileXY = int2(mul24(GroupID.x, 8), mul24(GroupID.y, 8));
	uint3 xyz = uint3(TileXY.x + GroupThreadID.x, yIndex, TileXY.y + GroupThreadID.y);
	uint x = xyz.x, z = xyz.z;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	int lookupx, lookupy;
	uint index = GetLookupIndex(GroupThreadID.xy, lookupx, lookupy);
	cache[index] = asuint(JumpFloodBuffer3D[uint3(TileXY.x + lookupx-1, yIndex + yOffset, TileXY.y + lookupy-1)]);

	index = 99-index;
	lookupx = 9 - lookupx;
	lookupy = 9 - lookupy;
	cache[index] = asuint(JumpFloodBuffer3D[uint3(TileXY.x + lookupx-1, yIndex + yOffset, TileXY.y + lookupy-1)]);
	ON_DX(GroupMemoryBarrierWithGroupSync());
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;
	uint cacheIndex = 11 + GroupThreadID.x + mul24(GroupThreadID.y, 10);

	if(x > 1)
	{
		if(z > 1)
			DistanceCheckCache(	xyz, cacheIndex, int2(-1, -1), nearest, currentNearest);
		DistanceCheckCache(		xyz, cacheIndex, int2(-1,  0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheckCache(	xyz, cacheIndex, int2(-1,  1), nearest, currentNearest);
	}

	if(z > 1)
		DistanceCheckCache(		xyz, cacheIndex, int2(0,  -1), nearest, currentNearest);
	DistanceCheckCache(			xyz, cacheIndex, int2(0,   0), nearest, currentNearest);
	if((z + 1) < depth)
		DistanceCheckCache(		xyz, cacheIndex, int2(0,   1), nearest, currentNearest);

	if((x + 1) < width)
	{
		if(z > 1)
			DistanceCheckCache(	xyz, cacheIndex, int2(1,  -1), nearest, currentNearest);
		DistanceCheckCache(		xyz, cacheIndex, int2(1,   0), nearest, currentNearest);
		if((z + 1) < depth)
			DistanceCheckCache(	xyz, cacheIndex, int2(1,   1), nearest, currentNearest);
	}
	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

void Discrete3DZCached_CS(uint3 GroupID, int zOffset, int zIndex, uint3 GroupThreadID)
{
	int2 TileXY = int2(mul24(GroupID.x, 8), mul24(GroupID.y, 8));
	uint3 xyz = uint3(TileXY + GroupThreadID.xy, zIndex);
	uint x = xyz.x, y = xyz.y;
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	
	int lookupx, lookupy;
	uint index = GetLookupIndex(GroupThreadID.xy, lookupx, lookupy);
	cache[index] = asuint(JumpFloodBuffer3D[uint3(TileXY + int2(lookupx-1, lookupy-1), zIndex + zOffset)]);

	index = 99-index;
	lookupx = 9 - lookupx;
	lookupy = 9 - lookupy;
	cache[index] = asuint(JumpFloodBuffer3D[uint3(TileXY + int2(lookupx-1, lookupy-1), zIndex + zOffset)]);
	ON_DX(GroupMemoryBarrierWithGroupSync());
	
	uint3 current = GetValue(xyz);
	uint currentNearest = 0;
	uint origDistance = Distance(current, xyz);
	uint nearest = origDistance;
	uint cacheIndex = 11 + GroupThreadID.x + mul24(GroupThreadID.y, 10);
	
	if(x > 1)
	{
		if(y > 1)
			DistanceCheckCache(	xyz, cacheIndex, int2(-1, -1), nearest, currentNearest);
		DistanceCheckCache(		xyz, cacheIndex, int2(-1,  0), nearest, currentNearest);
		if((y + 1) < height)
			DistanceCheckCache(	xyz, cacheIndex, int2(-1,  1), nearest, currentNearest);
	}

	if(y > 1)
		DistanceCheckCache(		xyz, cacheIndex, int2( 0, -1), nearest, currentNearest);
	DistanceCheckCache(			xyz, cacheIndex, int2( 0,  0), nearest, currentNearest);
	if((y + 1) < height)
		DistanceCheckCache(		xyz, cacheIndex, int2( 0,  1), nearest, currentNearest);

	if((x + 1) < width)
	{
		if(y > 1)
			DistanceCheckCache(	xyz, cacheIndex, int2( 1, -1), nearest, currentNearest);
		DistanceCheckCache(		xyz, cacheIndex, int2( 1,  0), nearest, currentNearest);
		if((y + 1) < height)
			DistanceCheckCache(	xyz, cacheIndex, int2( 1,  1), nearest, currentNearest);
	}

	if(nearest != origDistance)
		JumpFloodBuffer3D[xyz] = asfloat(currentNearest);
}

[numthreads(8,8, 1)]
void Discrete3DXPosCached_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	Discrete3DXCached_CS(GroupID, -1, Offset, GroupThreadID);
}

[numthreads(8,8, 1)]
void Discrete3DXNegCached_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	Discrete3DXCached_CS(GroupID, 1, Offset, GroupThreadID);
}

[numthreads(8,8, 1)]
void Discrete3DYPosCached_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	Discrete3DYCached_CS(GroupID, -1, Offset, GroupThreadID);
}
[numthreads(8,8, 1)]
void Discrete3DYNegCached_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	Discrete3DYCached_CS(GroupID, 1, Offset, GroupThreadID);
}

[numthreads(8,8, 1)]
void Discrete3DZPosCached_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	Discrete3DZCached_CS(GroupID, -1, Offset, GroupThreadID);
}
[numthreads(8,8, 1)]
void Discrete3DZNegCached_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	Discrete3DZCached_CS(GroupID, 1, Offset, GroupThreadID);
}

technique11 Discrete3DXPosCached
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DXPosCached_CS() ) );
	}
}
technique11 Discrete3DXNegCached
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DXNegCached_CS() ) );
	}
}
technique11 Discrete3DYPosCached
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DYPosCached_CS() ) );
	}
}
technique11 Discrete3DYNegCached
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DYNegCached_CS() ) );
	}
}
technique11 Discrete3DZPosCached
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DZPosCached_CS() ) );
	}
}
technique11 Discrete3DZNegCached
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DZNegCached_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Discrete distance transform 3D texture - one pass per axis
////////////////////////////////////////////////////////////////////////////////////////////////////

[numthreads(8,8, 1)]
void Discrete3DX_All_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	for(uint i = 1 ; i < width ; i++)
	{
		Discrete3DXCached_CS(GroupID, -1, i, GroupThreadID);
		GroupMemoryBarrierWithGroupSync();
		Discrete3DXCached_CS(GroupID, 1, (width - 1) - i, GroupThreadID);
		GroupMemoryBarrierWithGroupSync();
	}
}

[numthreads(8,8, 1)]
void Discrete3DY_All_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	for(uint i = 1 ; i < height ; i++)
	{
		Discrete3DYCached_CS(GroupID, -1, i, GroupThreadID);
		GroupMemoryBarrierWithGroupSync();
		Discrete3DYCached_CS(GroupID, 1, (height - 1) - i, GroupThreadID);
		GroupMemoryBarrierWithGroupSync();
	}
}

[numthreads(8,8, 1)]
void Discrete3DZ_All_CS(uint3 GroupID : SV_GroupID, uint3 GroupThreadID : SV_GroupThreadID)
{
	uint width, height, depth;
	JumpFloodBuffer3D.GetDimensions(width, height, depth);
	for(uint i = 1 ; i < depth ; i++)
	{
		Discrete3DZCached_CS(GroupID, -1, i, GroupThreadID);
		GroupMemoryBarrierWithGroupSync();
		Discrete3DZCached_CS(GroupID, 1, (depth - 1) - i, GroupThreadID);
		GroupMemoryBarrierWithGroupSync();
	}
}

technique11 Discrete3DX
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DX_All_CS() ) );
	}
}

technique11 Discrete3DY
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DY_All_CS() ) );
	}
}

technique11 Discrete3DZ
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, Discrete3DZ_All_CS() ) );
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Validation
////////////////////////////////////////////////////////////////////////////////////////////////////

Texture3D <float> TextureToValidate3D;
AppendStructuredBuffer<uint4> ValidationResults;		// XYZ of error, XYZ at point, actual nearest XYZ, 0

[numthreads(4, 4, 4)]
void ValidateNearestFeature_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	int3 xyz = int3(DispatchThreadId.xyz);
	uint packedNearest = asuint(TextureToValidate3D[xyz]);
	uint3 current = Unpack3D(packedNearest);
	uint nearest = Distance(current, xyz);

	uint width, height, depth;
	TextureToValidate3D.GetDimensions(width, height, depth);
	
#if 1
	int searchRange = int(sqrt((float)nearest)) + 1;
	int startz = max(xyz.z - searchRange, 0);
	int endz = min(xyz.z + searchRange, int(depth));
	for(int z = startz ; z < endz ; z++)
	{
		int nearestremaining = max(nearest - ((z - xyz.z) * (z - xyz.z)), 0);
		int offsety = sqrt(nearestremaining) + 1;
		int starty = max(xyz.y - offsety, 0);
		int endy = min(xyz.y + offsety, int(height));
		for(int y = starty ; y < endy ; y++)
		{
			int nearestremaining2 = max(nearestremaining - ((y - xyz.y) * (y - xyz.y)), 0);
			int offsetx = sqrt(nearestremaining2) + 1;
			int startx = max(xyz.x - offsetx, 0);
			int endx = min(xyz.x + offsetx, int(width));
			for(int x = startx ; x < endx ; x++)
			{
				uint3 otherXYZ = uint3(x, y, z);
				uint otherPacked = asuint(TextureToValidate3D[otherXYZ]);
				if(otherPacked != Pack(otherXYZ))
					continue;
				uint otherDistance = Distance(Unpack3D(otherPacked), xyz);
				if(otherDistance < nearest)
				{
					uint4 result = uint4(Pack(xyz), packedNearest, otherPacked, nearest);
					ValidationResults.Append(result);
					return;
				}
			}
		}
	}
#else
	if(all(xyz < uint3(5,5,5)))
	{
		uint4 result = uint4(xyz, 1);
		ValidationResults.Append(result);
		return;
	}
#endif
}

technique11 ValidateNearestFeature
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, ValidateNearestFeature_CS() ) );
	}
}
