/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

//
// Voxelization code
// Based on the GPU Pro 3 article: Practical Binary Surface and Solid Voxelization with Direct3D 11
// Source code available from http://www.crcpress.com/product/isbn/9781439887820
//

#include "../PhyreShaderPlatform.h"
#include "../PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__

	#define nointerpolation
	#define ON_ORBIS(x) x
	#define ON_DX(x)

#else // __ORBIS__

	#define custominterp
	#define ON_ORBIS(x)
	#define ON_DX(x) x

#endif // __ORBIS__

float4x4 World		: World;

//#define DEBUG_COLORS
bool PhyreContextSwitches 
< 
string ContextSwitchNames[] = {"SKINNING_ENABLED"}; 
>;

#ifdef SKINNING_ENABLED

	// This is the structured buffer implementation that uses the structured buffer from PhyreCoreShaderShared.h
	#define BoneTransforms BoneTransformConstantBuffer

	void EvaluateSkinPosition4Bones( inout float3 position, float4 weights, uint4 boneIndices )
	{
		uint indexArray[4] = {boneIndices.x,boneIndices.y,boneIndices.z,boneIndices.w};
		float4 inPosition = float4(position,1);
	
 		position = 
			mul(inPosition, BoneTransforms[indexArray[0]]).xyz * weights.x
		+	mul(inPosition, BoneTransforms[indexArray[1]]).xyz * weights.y
		+	mul(inPosition, BoneTransforms[indexArray[2]]).xyz * weights.z
		+	mul(inPosition, BoneTransforms[indexArray[3]]).xyz * weights.w;
	}

	void EvaluateSkinPositionNormal4Bones( inout float3 position, inout float3 normal, float4 weights, uint4 boneIndices )
	{
		uint indexArray[4] = {boneIndices.x,boneIndices.y,boneIndices.z,boneIndices.w};

		float4 inPosition = float4(position,1);
		float4 inNormal = float4(normal,0);
	
 		position = 
			mul(inPosition, BoneTransforms[indexArray[0]]).xyz * weights.x
		+	mul(inPosition, BoneTransforms[indexArray[1]]).xyz * weights.y
		+	mul(inPosition, BoneTransforms[indexArray[2]]).xyz * weights.z
		+	mul(inPosition, BoneTransforms[indexArray[3]]).xyz * weights.w;
	
		normal = 
			mul(inNormal, BoneTransforms[indexArray[0]]).xyz * weights.x
		+	mul(inNormal, BoneTransforms[indexArray[1]]).xyz * weights.y
		+	mul(inNormal, BoneTransforms[indexArray[2]]).xyz * weights.z
		+	mul(inNormal, BoneTransforms[indexArray[3]]).xyz * weights.w;
	}
#endif //! SKINNING_ENABLED

float4x4 VoxelTransform;
float4x4 VoxelTransformInv;
float3 VoxelOffset;
float3 VoxelScale;
float3 VoxelVolumeOffset;
float3 VoxelVolumeScale;
uint3 GridDimension;
float3 GridDimensionInv;
uint StrideX;
uint StrideY;
#define SCALE_AND_OFFSET(WHAT, FIELDS) ((WHAT.FIELDS * VoxelScale.FIELDS) + VoxelOffset.FIELDS)

RWByteAddressBuffer RWVoxelBuffer;
ByteAddressBuffer VoxelBuffer;

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = solid;
};

BlendState NoBlend
{
	BlendEnable[0] = FALSE;
	RenderTargetWriteMask[0] = 15;
};

DepthStencilState DepthDisabledState
{
	DepthEnable = FALSE;
	DepthWriteMask = Zero;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

DepthStencilState DepthEnabledState
{
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

///////////////////////////////////////////////////////////////////////////////
// Voxel Population
///////////////////////////////////////////////////////////////////////////////

struct VertexIn
{
#ifdef SKINNING_ENABLED
	#ifdef __ORBIS__
		float4 SkinnableVertex : POSITION;
	#else //! __ORBIS__
		float3 SkinnableVertex : POSITION;
	#endif //! __ORBIS__
	uint4	SkinIndices			: BLENDINDICES;
	float4	SkinWeights			: BLENDWEIGHTS;
#else //! SKINNING_ENABLED
	#ifdef __ORBIS__
		float4 Position	: POSITION;
	#else //! __ORBIS__
		float3 Position	: POSITION;
	#endif //! __ORBIS__
#endif //! SKINNING_ENABLED
};

struct VoxelOut
{
	float4 pos				: SV_POSITION;
	float4 gridPos			: TEXCOORD0;
};

VoxelOut VoxelizeVS(VertexIn input)
{
	VoxelOut output = (VoxelOut)0;
	
#ifdef SKINNING_ENABLED
	float3 v = input.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(v.xyz, input.SkinWeights, input.SkinIndices);
#else //! SKINNING_ENABLED
	float3 v = mul(float4(input.Position.xyz, 1.0f), World).xyz;
#endif //! SKINNING_ENABLED
	output.pos = float4(SCALE_AND_OFFSET(v, xy), 0.5f, 1.0f); // Simple Z-axis projection
	output.gridPos = float4(v * VoxelVolumeScale + VoxelVolumeOffset, 1.0f);
	output.gridPos.z += 0.5f;
	return output;
}

float4 VoxelizeFP(VoxelOut In) : FRAG_OUTPUT_COLOR0
{
	int3 p = int3(In.gridPos.xyz);

	if(p.z < int(GridDimension.z))
	{
		uint address = mul24(uint(p.x), StrideX) + mul24(uint(p.y), StrideY) + (p.z >> 5) * 4;
		RWVoxelBuffer.InterlockedXor(address, 0xffffffffu << (p.z & 31));

		for(p.z = (p.z | 31) + 1; p.z < int(GridDimension.z); p.z += 32)
		{
			address += 4;
			RWVoxelBuffer.InterlockedXor(address, 0xffffffffu);
		}
	}

	return float4(1.0f, 0.0f, 0.0f, 1.0f);
}

technique11 VoxelizeSolid
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_5_0, VoxelizeVS()));
		SetPixelShader(CompileShader(ps_5_0, VoxelizeFP()));

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthEnabledState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

///////////////////////////////////////////////////////////////////////////////
// Voxel Visualization
///////////////////////////////////////////////////////////////////////////////

struct RayVertexOut
{
	float4 position		: SV_POSITION;
	float3 ray			: TEXCOORD0;
};

RayVertexOut RenderVoxelsVS(uint vertexId : SV_VertexID)
{
	RayVertexOut output = (RayVertexOut)0;

	float2 uv = float2( ( vertexId << 1 ) & 2, vertexId & 2 );
	output.position = float4( uv * float2( 2.0f, -2.0f ) + float2( -1.0f, 1.0f ), 0.0f, 1.0f );
	output.ray = mul( float4( mul( output.position, ProjInverse ).xyz, 0.0f ), ViewInverse ).xyz;
	return output;
}

bool IsVoxelSet(uint3 pos)
{
	int p = mul24(pos.x, StrideX) + mul24(pos.y, StrideY) + (pos.z >> 5) * 4;
	int bit = pos.z & 0x1f;
	uint voxels = VoxelBuffer.Load(p);
	return (voxels & (1u << uint(bit))) != 0u;
}

float3 Shade( float3 pos, float3 normal )
{
	const float ambient = 0.2f;
	float3 lightPos = normalize( float3(0.8,0.4,0.3) );
	float3 n = mul(float4(normal, 0), VoxelTransformInv).xyz;
	return ((max(0.0f, dot(normalize(n), lightPos))) + ambient).xxx;
}

float3 VoxelTrace( in float3 ro, in float3 rd, out bool isHit, out float3 hitNormal, out float3 debugColor, out float3 finalColor )
{
	const float fltMax = 3.402823466e+38;
	const float eps = 0.0001f;
	float3 p = float3( 0.0f, 0.0f, 0.0f );
	isHit = false;
	hitNormal = float3( 0.0f, 0.0f, 0.0f );
	debugColor = float3( 0.0f, 0.0f, 0.0f );
	finalColor = float3( 0.0f, 0.0f, 0.0f );
	float3 gridDim = float3(GridDimension);

	if( abs( rd.x ) < eps ) rd.x = sign(rd.x) * eps;
	if( abs( rd.y ) < eps ) rd.y = sign(rd.y) * eps;
	if( abs( rd.z ) < eps ) rd.z = sign(rd.z) * eps;

	float3 tDelta = 1.0f / rd;
	float3 box0 = ( 0.0f - ro ) * tDelta;
	float3 box1 = ( gridDim - ro ) * tDelta;

	float3 boxMax = max( box0, box1 );
	float3 boxMin = min( box0, box1 );

	float enter = max( boxMin.x, max( boxMin.y, boxMin.z ) );
	float exit = min( boxMax.x, min( boxMax.y, boxMax.z ) );

	if( enter > exit )
	{
#ifdef DEBUG_COLORS
		debugColor = float3( 0.0f, 1.0f, 1.0f );
#endif
		return p;
	}

	if( exit < 0.0f )
	{
#ifdef DEBUG_COLORS
		debugColor = float3( 0.0f, 0.0f, 1.0f );
#endif
		return p;
	}

	tDelta = abs( tDelta );
	float t0 = max( enter - 0.5f * min( tDelta.x, min( tDelta.y, tDelta.z ) ), 0.0f );
	p = ro + t0 * rd;

	int3 cellStep = 1;
	if( rd.x < 0.0f ) cellStep.x = -1;
	if( rd.y < 0.0f ) cellStep.y = -1;
	if( rd.z < 0.0f ) cellStep.z = -1;

	int3 cell;
	cell.x = int(floor(p.x));
	cell.y = int(floor(p.y));
	cell.z = int(floor(p.z));

	if( rd.x < 0.0f && frac( p.x ) == 0.0f ) cell.x--;
	if( rd.y < 0.0f && frac( p.y ) == 0.0f ) cell.y--;
	if( rd.z < 0.0f && frac( p.z ) == 0.0f ) cell.z--;

	float3 tMax = 10000000000.0f;
	if( rd.x > 0.0f ) tMax.x = (float(cell.x+1) - p.x) * tDelta.x;
	if( rd.x < 0.0f ) tMax.x = (p.x - float(cell.x)) * tDelta.x;
	if( rd.y > 0.0f ) tMax.y = (float(cell.y+1) - p.y) * tDelta.y;
	if( rd.y < 0.0f ) tMax.y = (p.y - float(cell.y)) * tDelta.y;
	if( rd.z > 0.0f ) tMax.z = (float(cell.z+1) - p.z) * tDelta.z;
	if( rd.z < 0.0f ) tMax.z = (p.z - float(cell.z)) * tDelta.z;

	int maxSteps = GridDimension.x + GridDimension.y + GridDimension.z + 1;
	float t = 0.0f;
	float3 tMaxPrev = float3( 0.0f, 0.0f, 0.0f );
	for( int i = 0; i < maxSteps; i++ )
	{
		t = min( tMax.x, min( tMax.y, tMax.z ) );
		if( t0 + t >= exit )
		{
			isHit = false;
			return p;
		}

		tMaxPrev = tMax;
		if( tMax.x <= t ){ tMax.x += tDelta.x; cell.x += cellStep.x; }
		if( tMax.y <= t ){ tMax.y += tDelta.y; cell.y += cellStep.y; }
		if( tMax.z <= t ){ tMax.z += tDelta.z; cell.z += cellStep.z; }

		if(min3(cell.x, cell.y, cell.z) < 0)
			continue;
		if( any( cell.xyz >= int3( gridDim ) ) )
			continue;

		if( IsVoxelSet( cell ) )
		{
			isHit = true;
			break;
		}
	}
	
	if( tMaxPrev.x <= t ) hitNormal.x = rd.x > 0.0f ? -1.0f : 1.0f;
	if( tMaxPrev.y <= t ) hitNormal.y = rd.y > 0.0f ? -1.0f : 1.0f;
	if( tMaxPrev.z <= t ) hitNormal.z = rd.z > 0.0f ? -1.0f : 1.0f;
	hitNormal = normalize( hitNormal );

	p = ro + ( t0 + t ) * rd;

	if( isHit )
	{
		finalColor = Shade( p, hitNormal );
	}

	return p;
}

float4 RenderVoxelsFP(RayVertexOut In) : FRAG_OUTPUT_COLOR0
{
	float3 rd = normalize(In.ray);
	float3 ro = EyePosition.xyz;
	ro = ro * VoxelVolumeScale + VoxelVolumeOffset;
	rd *= VoxelVolumeScale;

	bool isHit = false;
	float3 normal = float3( 0.0f, 0.0f, 0.0f );
	float3 color = float3( 0.0f, 0.2f, 0.0f );
	float3 debugColor = float3( 0.0f, 0.0f, 0.0f );

	float3 pos = VoxelTrace( ro, rd, isHit, normal, debugColor, color );

	color.xyz += debugColor;

	return float4( color.xyz, 1.0f );
}

technique11 RenderVoxels
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_5_0, RenderVoxelsVS()));
		SetPixelShader(CompileShader(ps_5_0, RenderVoxelsFP()));

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthDisabledState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

///////////////////////////////////////////////////////////////////////////////
// Voxel Distance Field Based Effects
///////////////////////////////////////////////////////////////////////////////

struct MeshVertexIn
{
#ifdef SKINNING_ENABLED
	#ifdef __ORBIS__
		float4 SkinnableVertex : POSITION;
	#else //! __ORBIS__
		float3 SkinnableVertex : POSITION;
	#endif //! __ORBIS__
	float3	SkinnableNormal		: NORMAL;
	uint4	SkinIndices			: BLENDINDICES;
	float4	SkinWeights			: BLENDWEIGHTS;
#else //! SKINNING_ENABLED
	#ifdef __ORBIS__
		float4 Position	: POSITION;
	#else //! __ORBIS__
		float3 Position	: POSITION;
	#endif //! __ORBIS__
	float3 Normal		:	NORMAL;
#endif //! SKINNING_ENABLED
};

struct MeshOnGrid
{
	float4 pos				: SV_POSITION;
	float3 gridPos			: TEXCOORD0;
	float3 gridNormal		: TEXCOORD1;
};

float4x4 WorldViewProjection		: WorldViewProjection;
Texture3D <float> DistanceField;

sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

MeshOnGrid ApplyDistanceFieldToMesh(MeshVertexIn input)
{
	MeshOnGrid output = (MeshOnGrid)0;
	
#ifdef SKINNING_ENABLED
	float3 v = input.SkinnableVertex.xyz;
	float3 n = input.SkinnableNormal.xyz;
	EvaluateSkinPositionNormal4Bones(v.xyz, n.xyz, input.SkinWeights, input.SkinIndices);
#else //! SKINNING_ENABLED
	float3 v = mul(float4(input.Position.xyz, 1.0f), World).xyz;
	float3 n = mul(float4(input.Normal.xyz, 0.0f), World).xyz;
#endif //! SKINNING_ENABLED

	output.pos = mul(float4(v, 1.0f), ViewProjection);
	output.gridPos = v * VoxelVolumeScale + VoxelVolumeOffset;
	output.gridNormal = n;

	return output;
}

///////////////////////////////////////////////////////////////////////////////
// Voxel Distance Field Based Ambient Occlusion
///////////////////////////////////////////////////////////////////////////////

float StepSize = 1.0f;		// In grid cells.
float OffsetScale = 0.5f;	// Varied based on solid vs surface
float4 AmbientMinFP(MeshOnGrid In) : FRAG_OUTPUT_COLOR0
{
	float3 gridPos = In.gridPos.xyz;
	gridPos *= GridDimensionInv;

	float3 gridNormal = normalize(In.gridNormal.xyz) * GridDimensionInv;
	gridPos += gridNormal * OffsetScale;

	float sum = 0.0f;
	float minimum = 1.0f;
	float expectedDist = 0.0f;
	uint maxSteps = 25;
	for(uint i = 0 ; i < maxSteps ; i++)
	{
		gridPos += gridNormal * StepSize;
		expectedDist += StepSize;
		
		float mx = max3(gridPos.x, gridPos.y, gridPos.z);
		float mn = min3(gridPos.x, gridPos.y, gridPos.z);
		if(mn >= 0.0f && mx <= 1.0f)
		{
			float dist = DistanceField.SampleLevel(LinearClampSampler, gridPos, 0).x;
			minimum = min(minimum, saturate(dist / expectedDist));
		}
	}
	return minimum;
}

technique11 AmbientMin
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_5_0, ApplyDistanceFieldToMesh()));
		SetPixelShader(CompileShader(ps_5_0, AmbientMinFP()));

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthEnabledState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

///////////////////////////////////////////////////////////////////////////////
// Voxel Distance Field Based Ambient Occlusion
///////////////////////////////////////////////////////////////////////////////

float4 AmbientSumRatioFP(MeshOnGrid In) : FRAG_OUTPUT_COLOR0
{
	float3 gridPos = In.gridPos.xyz;
	gridPos *= GridDimensionInv;

	float3 gridNormal = normalize(In.gridNormal.xyz) * GridDimensionInv;
	gridPos += gridNormal * OffsetScale;

	float sum = 0.0f;
	float expectedDist = 0.0f;
	uint maxSteps = 25;
	for(uint i = 0 ; i < maxSteps ; i++)
	{
		gridPos += gridNormal * StepSize;
		expectedDist += StepSize;
		
		float mx = max3(gridPos.x, gridPos.y, gridPos.z);
		float mn = min3(gridPos.x, gridPos.y, gridPos.z);
		if(mn >= 0.0f && mx <= 1.0f)
		{
			float dist = DistanceField.SampleLevel(LinearClampSampler, gridPos, 0).x;

			sum += saturate(dist / expectedDist);
		}
		else
		{
			// Left volume - we have no occlusion info
			sum += 1.0f;
		}
	}
	return sum/maxSteps;
}

technique11 AmbientSumRatio
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_5_0, ApplyDistanceFieldToMesh()));
		SetPixelShader(CompileShader(ps_5_0, AmbientSumRatioFP()));

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthEnabledState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

float AmbientSumScale = 1.0f;
float AmbientSumStepSize = 1.5f;
float4 AmbientSumDistanceFP(MeshOnGrid In) : FRAG_OUTPUT_COLOR0
{
	float3 gridPos = In.gridPos.xyz;
	gridPos *= GridDimensionInv;
	
	float3 gridNormal = normalize(In.gridNormal.xyz) * GridDimensionInv;

	float sum = 0.0f;
	uint maxSteps = 8;
	float weight = 1.0f;
	float totalWeight = 0.0f;
	for(uint i = 0 ; i < maxSteps ; i++)
	{
		float expectedDist = (i+1) * AmbientSumStepSize;
		float3 pos = gridPos + gridNormal * expectedDist;
		
		float mx = max3(pos.x, pos.y, pos.z);
		float mn = min3(pos.x, pos.y, pos.z);
		if(mn >= 0.0f && mx <= 1.0f)
		{
			float dist = DistanceField.SampleLevel(LinearClampSampler, pos, 0).x;
			sum += weight * dist;
			totalWeight += weight * expectedDist;
			weight += 0.2f;
		}
	}
	return sum / (AmbientSumScale * totalWeight);
}

technique11 AmbientSumDistance
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_5_0, ApplyDistanceFieldToMesh()));
		SetPixelShader(CompileShader(ps_5_0, AmbientSumDistanceFP()));

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthEnabledState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

///////////////////////////////////////////////////////////////////////////////
// Voxel Distance Field Based Soft Shadows
///////////////////////////////////////////////////////////////////////////////

int ShadowSoftness = 8;
float ShadowVoxelOffset = 0.8;

float softshadow(float3 ro, float3 rd, float mint, float maxt, float k)
{
    float res = 1.0;
    for(float t=mint; t < maxt;)
    {
		float3 x = ro + rd*t;
		float3 s = x * GridDimensionInv;
		float h = DistanceField.SampleLevel(LinearClampSampler, s, 0).x;
		if(h<0.01)
			return 0.0;
		res = min(res, k*h/t);
		t += h;
    }
    return res;
}

float4 ShadowFromVoxelsFP(MeshOnGrid In) : FRAG_OUTPUT_COLOR0
{
	float3 gridPos = In.gridPos.xyz;

	float3 gridNormal = normalize(In.gridNormal.xyz);
	gridPos += gridNormal * ShadowVoxelOffset;

	float result = softshadow(gridPos, float3(0,1,0), 0.001f, GridDimension.y - gridPos.y, (float)ShadowSoftness);
	return min(result.xxxx, gridNormal.y);
}

technique11 ShadowFromVoxels
{
	pass pass0
	{
		SetVertexShader(CompileShader(vs_5_0, ApplyDistanceFieldToMesh()));
		SetPixelShader(CompileShader(ps_5_0, ShadowFromVoxelsFP()));

		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthEnabledState, 0 );
		SetRasterizerState( DefaultRasterState );
	}
}

///////////////////////////////////////////////////////////////////////////////
// Voxel Population
///////////////////////////////////////////////////////////////////////////////

struct VS_Output
{
	float3 position: POSITION;
};

VS_Output VoxelizeSurface_VS(VertexIn input)
{
	VS_Output output;
#ifdef SKINNING_ENABLED
	float3 position = input.SkinnableVertex.xyz;
	EvaluateSkinPosition4Bones(position.xyz, input.SkinWeights, input.SkinIndices);
	output.position = position;
#else //! SKINNING_ENABLED
	output.position = mul(float4(input.Position.xyz, 1.0f), World).xyz;
	//output.position = input.Position.xyz
#endif //! SKINNING_ENABLED
	//output.position.xyz = output.position.xyz * VoxelVolumeScale + VoxelVolumeOffset;
	return output;
}
 
struct GS_Output
{
	float4 position: SV_POSITION;
	custominterp nointerpolation float4 plane: PLANE;
#ifdef __ORBIS__
	custominterp float3 tri: TRI0;
#else
	int viewIndex : VIEW_INDEX;
	nointerpolation float3 tri0: TRI0;
	nointerpolation float3 tri1: TRI1;
	nointerpolation float3 tri2: TRI2;
#endif
};

float simpleSign(float x)
{
	return x >= 0.0f ? 1.0f : -1.0f;
}

uint GetViewIndex(float3 direction)
{
#ifdef __ORBIS__
	return CubeMapFaceID(direction) * 0.5f;
#else // __ORBIS__
	float3 absDirection = abs(direction);
	float maximum = max(max(absDirection.x, absDirection.y), absDirection.z);
	if(maximum == absDirection.x)
		return 0;
	if(maximum == absDirection.y)
		return 1;
	return 2;
#endif // __ORBIS__
}

float4 setVoxel(float3 gridPos)
{
	int3 p = int3(gridPos.xyz);
	if(p.z < int(GridDimension.z))
	{
		uint address = mul24(uint(p.x), StrideX) + mul24(uint(p.y), StrideY) + (p.z >> 5) * 4;
		RWVoxelBuffer.InterlockedOr(address, 1 << (p.z & 31));
	}
	return float4(1.0f, 0.0f, 0.0f, 1.0f);
}

void Determine2dEdge(out float2 ne, out float de, float orientation, float edge_x, float edge_y, float vertex_x, float vertex_y)
{
	ne = float2(-orientation * edge_y, orientation * edge_x);
	de = -(ne.x * vertex_x + ne.y * vertex_y);
	de += max(0.0, ne.x);
	de += max(0.0, ne.y);
}

void VS_CS(float3 v0, float3 v1, float3 v2)
{
	// determine bounding box
	const float3 vMin = float3(min(v0.x, min(v1.x, v2.x)),
	                           min(v0.y, min(v1.y, v2.y)),
	                           min(v0.z, min(v1.z, v2.z)));
	const float3 vMax = float3(max(v0.x, max(v1.x, v2.x)),
	                           max(v0.y, max(v1.y, v2.y)),
	                           max(v0.z, max(v1.z, v2.z)));

	const float3 voxOrigMin = float3(floor(vMin.x),
	                                 floor(vMin.y),
	                                 floor(vMin.z));
	const float3 voxOrigMax = float3(floor(vMax.x + 1.0),
	                                 floor(vMax.y + 1.0),
	                                 floor(vMax.z + 1.0));

	const float3 voxOrigExtent = voxOrigMax - voxOrigMin;

	// determine bounding box clipped to voxel grid
	const float3 voxMin = float3(max(0.0, voxOrigMin.x),
	                             max(0.0, voxOrigMin.y),
	                             max(0.0, voxOrigMin.z));
	const float3 voxMax = float3(min(float(GridDimension.x), voxOrigMax.x),
	                             min(float(GridDimension.y), voxOrigMax.y),
	                             min(float(GridDimension.z), voxOrigMax.z));

	const float3 voxExtent = voxMax - voxMin;

	// check if any voxels are covered at all
// 	if(min3(voxExtent.x, voxExtent.y, voxExtent.z) <= 0.0) // slightly faster on CS, slower on GS
	if(any(voxExtent <= 0.0))
		return;

	// determine dimensions of unclipped extent
	const uint FLATDIM_X = 4;
	const uint FLATDIM_Y = 8;
	const uint FLATDIM_Z = 16;

	uint flatDimensions = 0;
	if(voxOrigExtent.x == 1.0) flatDimensions += 1 | FLATDIM_X;
	if(voxOrigExtent.y == 1.0) flatDimensions += 1 | FLATDIM_Y;
	if(voxOrigExtent.z == 1.0) flatDimensions += 1 | FLATDIM_Z;

	//---- 1D: set all voxels in bounding box ----
	if((flatDimensions & 3) >= 2) {
		//uint address = uint(voxMin.x) * StrideX + uint(voxMin.y) * StrideY + (uint(voxMin.z) >> 5) * 4;
		uint address = mul24(uint(voxMin.x), StrideX) + mul24(uint(voxMin.y), StrideY) + (uint(voxMin.z) >> 5) * 4;

		// 1x1xN: set all voxels, up to 32 consecutive ones at a time
		if((flatDimensions & FLATDIM_Z) == 0) {
			const uint voxMax_z = uint(voxMin.z);

			uint voxels = (~0u) << (uint(voxMin.z) & 31);
			uint lastZ = (uint(voxMax_z) & (~31));

			for(uint z = uint(voxMin.z); z < lastZ; z += 32) {
				RWVoxelBuffer.InterlockedOr(address, voxels);
				address += 4;
				voxels = ~0;
			}

			uint restCount = uint(voxMax_z) & 31;
			if(restCount > 0) {
				voxels &= ~(0xffffffff << restCount);
				RWVoxelBuffer.InterlockedOr(address, voxels);
			}
		}

		// Nx1x1 or 1xNx1: set all voxels, one at a time
		else {
			const uint stride = (flatDimensions & FLATDIM_X) == 0 ? StrideX : StrideY;
			const uint count = uint(max(voxExtent.x, voxExtent.y));
			const uint voxels = 1u << (uint(voxMin.z) & 31);

			for(uint i = 0; i < count; i++) {
				RWVoxelBuffer.InterlockedOr(address, voxels);
				address += stride;
			}
		}
	}

	//---- 2D or 3D ----
	else {
		// triangle setup
		const float3 e0 = v1-v0;
		const float3 e1 = v2-v1;
		const float3 e2 = v0-v2;
		float3 n = cross(e2, e0);

		//---- 2D: test only for 2D triangle/voxel overlap ----
		if((flatDimensions & 3) == 1) {
			//uint address0 = uint(voxMin.x) * StrideX + uint(voxMin.y) * StrideY + (uint(voxMin.z) >> 5) * 4;
			uint address0 = mul24(uint(voxMin.x), StrideX) + mul24(uint(voxMin.y), StrideY) + (uint(voxMin.z) >> 5) * 4;

			// NxMx1
			if(flatDimensions & FLATDIM_Z) {
				float2 ne0, ne1, ne2;
				float  de0, de1, de2;

				const float orientation = n.z < 0.0 ? -1.0 : 1.0;
				Determine2dEdge(ne0, de0, orientation, e0.x, e0.y, v0.x, v0.y);
				Determine2dEdge(ne1, de1, orientation, e1.x, e1.y, v1.x, v1.y);
				Determine2dEdge(ne2, de2, orientation, e2.x, e2.y, v2.x, v2.y);

				const uint voxels = 1 << (int(voxMin.z) & 31);

				float2 p;
				for(p.y = voxMin.y; p.y < voxMax.y; p.y++) {
					uint address = address0;
					for(p.x = voxMin.x; p.x < voxMax.x; p.x++) {
						if((dot(ne0, p) + de0 > 0.0) &&
						   (dot(ne1, p) + de1 > 0.0) &&
						   (dot(ne2, p) + de2 > 0.0))
						{
							RWVoxelBuffer.InterlockedOr(address, voxels);
						}
						address += StrideX;
					}
					address0 += StrideY;
				}
			}

			// 1xNxM or Nx1xM: inner loop along z such that updates to voxels stored in the same 32-bit buffer value result in only one buffer update
			else {
				float2 ne0, ne1, ne2;
				float  de0, de1, de2;

				uint stride;
				float2 p;
				float pxMax;

				if(flatDimensions & FLATDIM_X) {
					const float orientation = n.x < 0.0 ? -1.0 : 1.0;
					Determine2dEdge(ne0, de0, orientation, e0.y, e0.z, v0.y, v0.z);
					Determine2dEdge(ne1, de1, orientation, e1.y, e1.z, v1.y, v1.z);
					Determine2dEdge(ne2, de2, orientation, e2.y, e2.z, v2.y, v2.z);
					stride = StrideY;
					p.x = voxMin.y;
					pxMax = voxMax.y;
				} else {
					const float orientation = n.y > 0.0 ? -1.0 : 1.0;
					Determine2dEdge(ne0, de0, orientation, e0.x, e0.z, v0.x, v0.z);
					Determine2dEdge(ne1, de1, orientation, e1.x, e1.z, v1.x, v1.z);
					Determine2dEdge(ne2, de2, orientation, e2.x, e2.z, v2.x, v2.z);
					stride = StrideX;
					p.x = voxMin.x;
					pxMax = voxMax.x;
				}

				for(; p.x < pxMax; p.x++) {
					uint address = address0;
					uint voxels = 0;
					for(p.y = voxMin.z; p.y < voxMax.z; p.y++) {
						const uint z31 = uint(p.y) & 31;

						if((dot(ne0, p) + de0 > 0.0) &&
						   (dot(ne1, p) + de1 > 0.0) &&
						   (dot(ne2, p) + de2 > 0.0))
						{
							voxels |= 1 << z31;
						}

						if(z31 == 31) {
							if(voxels) {
								RWVoxelBuffer.InterlockedOr(address, voxels);
								voxels = 0;
							}
							address += 4;
						}
					}

					if((uint(voxMax.z) & 31) && voxels != 0)
						RWVoxelBuffer.InterlockedOr(address, voxels);

					address0 += stride;
				}
			}
		}

		//---- 3D ----
		else {
			// determine edge equations and offsets
			float2 ne0_xy, ne1_xy, ne2_xy;
			float de0_xy, de1_xy, de2_xy;
			const float orientation_xy = n.z < 0.0 ? -1.0 : 1.0;
			Determine2dEdge(ne0_xy, de0_xy, orientation_xy, e0.x, e0.y, v0.x, v0.y);
			Determine2dEdge(ne1_xy, de1_xy, orientation_xy, e1.x, e1.y, v1.x, v1.y);
			Determine2dEdge(ne2_xy, de2_xy, orientation_xy, e2.x, e2.y, v2.x, v2.y);

			float2 ne0_xz, ne1_xz, ne2_xz;
			float de0_xz, de1_xz, de2_xz;
			const float orientation_xz = n.y > 0.0 ? -1.0 : 1.0;
			Determine2dEdge(ne0_xz, de0_xz, orientation_xz, e0.x, e0.z, v0.x, v0.z);
			Determine2dEdge(ne1_xz, de1_xz, orientation_xz, e1.x, e1.z, v1.x, v1.z);
			Determine2dEdge(ne2_xz, de2_xz, orientation_xz, e2.x, e2.z, v2.x, v2.z);

			float2 ne0_yz, ne1_yz, ne2_yz;
			float de0_yz, de1_yz, de2_yz;
			const float orientation_yz = n.x < 0.0 ? -1.0 : 1.0;
			Determine2dEdge(ne0_yz, de0_yz, orientation_yz, e0.y, e0.z, v0.y, v0.z);
			Determine2dEdge(ne1_yz, de1_yz, orientation_yz, e1.y, e1.z, v1.y, v1.z);
			Determine2dEdge(ne2_yz, de2_yz, orientation_yz, e2.y, e2.z, v2.y, v2.z);

			const float maxComponentValue = max(abs(n.x), max(abs(n.y), abs(n.z)));
			
#if 0	// Only align with Z axis since this better aligns with writes to the Voxel Buffer
			// triangle aligns best to yz
			if(maxComponentValue == abs(n.x)) {
				// make normal point in +x direction
				if(n.x < 0.0) {
					n.x = -n.x;
					n.y = -n.y;
					n.z = -n.z;
				}

				// determine triangle plane equation and offset
				const float dTri = -dot(n, v0);

				float dTriProjMin = dTri;
				dTriProjMin += max(0.0, n.y);
				dTriProjMin += max(0.0, n.z);

				float dTriProjMax = dTri;
				dTriProjMax += min(0.0, n.y);
				dTriProjMax += min(0.0, n.z);

				const float nxInv = 1.0 / n.x;

				uint address0 = mul24(uint(voxMin.y), StrideY);

				float3 p;
				for(p.y = voxMin.y; p.y < voxMax.y; p.y++) {
					for(p.z = voxMin.z; p.z < voxMax.z; p.z++) {
						if((ne0_yz.x * p.y + ne0_yz.y * p.z + de0_yz >= 0.0) &&
						   (ne1_yz.x * p.y + ne1_yz.y * p.z + de1_yz >= 0.0) &&
						   (ne2_yz.x * p.y + ne2_yz.y * p.z + de2_yz >= 0.0))
						{
							// determine x range: project adjusted p onto plane along x axis (ray/plane intersection)
							float x = -(p.y * n.y + p.z * n.z + dTriProjMin) * nxInv;
							float minX = floor(x);
							if(x == minX) minX--;
							minX = max(voxMin.x, minX);

							x = -(p.y * n.y + p.z * n.z + dTriProjMax) * nxInv + 1.0;
							float maxX = floor(x);
							if(x == maxX) maxX++;
							maxX = min(voxMax.x, maxX);

							// test voxels in x range
							uint address = address0 + mul24(uint(minX), StrideX) + (uint(p.z) >> 5) * 4;
							const uint voxels = 1 << (uint(p.z) & 31);

							for(p.x = minX; p.x < maxX; p.x++) {
								if((ne0_xy.x * p.x + ne0_xy.y * p.y + de0_xy >= 0.0) &&
								   (ne1_xy.x * p.x + ne1_xy.y * p.y + de1_xy >= 0.0) &&
								   (ne2_xy.x * p.x + ne2_xy.y * p.y + de2_xy >= 0.0) &&
								   (ne0_xz.x * p.x + ne0_xz.y * p.z + de0_xz >= 0.0) &&
								   (ne1_xz.x * p.x + ne1_xz.y * p.z + de1_xz >= 0.0) &&
								   (ne2_xz.x * p.x + ne2_xz.y * p.z + de2_xz >= 0.0))
								{
									RWVoxelBuffer.InterlockedOr(address, voxels);
								}
								address += StrideX;
							}
						}
					}
					address0 += StrideY;
				}
			}

			// triangle aligns best to xz
			else if(maxComponentValue == abs(n.y)) {
				// make normal point in +y direction
				if(n.y < 0.0) {
					n.x = -n.x;
					n.y = -n.y;
					n.z = -n.z;
				}

				// determine triangle plane equation and offset
				const float dTri = -dot(n, v0);

				float dTriProjMin = dTri;
				dTriProjMin += max(0.0, n.x);
				dTriProjMin += max(0.0, n.z);

				float dTriProjMax = dTri;
				dTriProjMax += min(0.0, n.x);
				dTriProjMax += min(0.0, n.z);

				const float nyInv = 1.0 / n.y;

				uint address0 = mul24(uint(voxMin.x), StrideX);

				float3 p;
				for(p.x = voxMin.x; p.x < voxMax.x; p.x++) {
					for(p.z = voxMin.z; p.z < voxMax.z; p.z++) {
						if((ne0_xz.x * p.x + ne0_xz.y * p.z + de0_xz >= 0.0) &&
						   (ne1_xz.x * p.x + ne1_xz.y * p.z + de1_xz >= 0.0) &&
						   (ne2_xz.x * p.x + ne2_xz.y * p.z + de2_xz >= 0.0))
						{
							// determine y range: project adjusted p onto plane along y axis (ray/plane intersection)
							float y = -(p.x * n.x + p.z * n.z + dTriProjMin) * nyInv;
							float minY = floor(y);
							if(y == minY) minY--;
							minY = max(voxMin.y, minY);

							y = -(p.x * n.x + p.z * n.z + dTriProjMax) * nyInv + 1.0;
							float maxY = floor(y);
							if(y == maxY) maxY++;
							maxY = min(voxMax.y, maxY);

							// test voxels in y range
							uint address = address0 + mul24(uint(minY), StrideY) + (uint(p.z) >> 5) * 4;
							const uint voxels = 1 << (uint(p.z) & 31);

							for(p.y = minY; p.y < maxY; p.y++) {
								if((ne0_xy.x * p.x + ne0_xy.y * p.y + de0_xy >= 0.0) &&
								   (ne1_xy.x * p.x + ne1_xy.y * p.y + de1_xy >= 0.0) &&
								   (ne2_xy.x * p.x + ne2_xy.y * p.y + de2_xy >= 0.0) &&
								   (ne0_yz.x * p.y + ne0_yz.y * p.z + de0_yz >= 0.0) &&
								   (ne1_yz.x * p.y + ne1_yz.y * p.z + de1_yz >= 0.0) &&
								   (ne2_yz.x * p.y + ne2_yz.y * p.z + de2_yz >= 0.0))
								{
									RWVoxelBuffer.InterlockedOr(address, voxels);
								}
								address += StrideY;
							}
						}
					}
					address0 += StrideX;
				}
			}

			// triangle aligns best to xy
			else
			{
#else
			{
#endif
				// make normal point in +z direction
				if(n.z < 0.0) {
					n.x = -n.x;
					n.y = -n.y;
					n.z = -n.z;
				}

				// determine triangle plane equation and offset
				const float dTri = -dot(n, v0);

				float dTriProjMin = dTri;
				dTriProjMin += max(0.0, n.x);
				dTriProjMin += max(0.0, n.y);

				float dTriProjMax = dTri;
				dTriProjMax += min(0.0, n.x);
				dTriProjMax += min(0.0, n.y);

				const float nzInv = 1.0 / n.z;

				uint address0 = mul24(uint(voxMin.x), StrideX) + mul24(uint(voxMin.y), StrideY);

				float3 p;
				for(p.y = voxMin.y; p.y < voxMax.y; p.y++) {
					uint address1 = address0;
					for(p.x = voxMin.x; p.x < voxMax.x; p.x++) {
						if((ne0_xy.x * p.x + ne0_xy.y * p.y + de0_xy >= 0.0) &&
						   (ne1_xy.x * p.x + ne1_xy.y * p.y + de1_xy >= 0.0) &&
						   (ne2_xy.x * p.x + ne2_xy.y * p.y + de2_xy >= 0.0))
						{
							// determine z range: project adjusted p onto plane along z axis (ray/plane intersection)
							float z = -(p.x * n.x + p.y * n.y + dTriProjMin) * nzInv;
							float minZ = floor(z);
							if(z == minZ) minZ--;
							minZ = max(voxMin.z, minZ);

							z = -(p.x * n.x + p.y * n.y + dTriProjMax) * nzInv + 1.0;
							float maxZ = floor(z);
							if(z == maxZ) maxZ++;
							maxZ = min(voxMax.z, maxZ);

							// test voxels in z range
							uint address = address1 + (uint(minZ) >> 5) * 4;
							uint voxels = 0;

							for(p.z = minZ; p.z < maxZ; p.z++) {
								const uint z31 = uint(p.z) & 31;

								if((ne0_xz.x * p.x + ne0_xz.y * p.z + de0_xz >= 0.0) &&
								   (ne1_xz.x * p.x + ne1_xz.y * p.z + de1_xz >= 0.0) &&
								   (ne2_xz.x * p.x + ne2_xz.y * p.z + de2_xz >= 0.0) &&
								   (ne0_yz.x * p.y + ne0_yz.y * p.z + de0_yz >= 0.0) &&
								   (ne1_yz.x * p.y + ne1_yz.y * p.z + de1_yz >= 0.0) &&
								   (ne2_yz.x * p.y + ne2_yz.y * p.z + de2_yz >= 0.0))
								{
									voxels |= 1 << z31;
								}

								if(z31 == 31) {
									if(voxels) {
										RWVoxelBuffer.InterlockedOr(address, voxels);
										voxels = 0;
									}
									address += 4;
								}
							}

							if(voxels != 0)
								RWVoxelBuffer.InterlockedOr(address, voxels);
						}
						address1 += StrideX;
					}
					address0 += StrideY;
				}
			}
		}
	}
}

void VoxelizeSurface(VS_Output input[3], inout TriangleStream<GS_Output> outputStream)
{
	GS_Output output[3];

#ifdef __ORBIS__

	[unroll]
	for (uint i = 0; i<3; i++)
		output[i].tri = input[i].position.xyz * VoxelVolumeScale + VoxelVolumeOffset;

	// Early out for triangles occupying a single voxel - unsupported before DX11.1 since we can't use the UAV for setting the voxel
	float3 mini = min(min(output[0].tri, output[1].tri), output[2].tri);
		float3 maxi = max(max(output[0].tri, output[1].tri), output[2].tri);
	if (all(int3(mini) == int3(maxi)))
	{
		setVoxel(mini);
		return;
	}

#else // __ORBIS__

	[unroll]
	for (uint i = 0; i<3; i++)
	{
		output[i].tri0 = input[0].position.xyz * VoxelVolumeScale + VoxelVolumeOffset;
		output[i].tri1 = input[1].position.xyz * VoxelVolumeScale + VoxelVolumeOffset;
		output[i].tri2 = input[2].position.xyz * VoxelVolumeScale + VoxelVolumeOffset;
	}

#endif // __ORBIS__

	float3 faceNormal = cross(input[1].position.xyz - input[0].position.xyz, input[2].position.xyz - input[0].position.xyz);

	// Get view, at which the current triangle is most visible, in order to achieve highest
	// possible rasterization of the primitive.
	uint viewIndex = GetViewIndex(faceNormal);
	float dir = 1.0f;
	if (viewIndex == 0)
		dir = simpleSign(faceNormal.x);
	else if (viewIndex == 1)
		dir = -simpleSign(faceNormal.y);
	else // if(viewIndex == 2)
		dir = simpleSign(faceNormal.z);

	{
		[unroll]
		for (uint i = 0; i<3; i++)
		{
			float3 position = input[i].position.xyz;
			if (viewIndex == 0)
				output[i].position = float4(SCALE_AND_OFFSET(position, yz), SCALE_AND_OFFSET(position, x), 1.0f);
			else if (viewIndex == 1)
				output[i].position = float4(SCALE_AND_OFFSET(position, xz), SCALE_AND_OFFSET(position, y), 1.0f);
			else // if(viewIndex == 2)
				output[i].position = float4(SCALE_AND_OFFSET(position, xy), SCALE_AND_OFFSET(position, z), 1.0f);
			ON_DX(output[i].position.z = output[i].position.z * 0.5f + 0.5f;)
		}
	}

	// Based on https://github.com/otaku690/SparseVoxelOctree/blob/master/WIN/SVO/shader/voxelize.geom.glsl
	// Note: Doesn't handle Z so triangle is relatively flattened and we need to compensate in the Pixel Shader and AABB clip
	float3 e0 = float3(output[1].position.xy - output[0].position.xy, 0);
	float3 e1 = float3(output[2].position.xy - output[1].position.xy, 0);
	float3 e2 = float3(output[0].position.xy - output[2].position.xy, 0);
	float3 n0 = cross(e0, float3(0, 0, dir));
	float3 n1 = cross(e1, float3(0, 0, dir));
	float3 n2 = cross(e2, float3(0, 0, dir));
	float pl = 1.4142135637309 * GridDimensionInv.z;
	//dilate the triangle
	output[0].position.xy += pl*((e2.xy / dot(e2.xy, n0.xy)) + (e0.xy / dot(e0.xy, n2.xy)));
	output[1].position.xy += pl*((e0.xy / dot(e0.xy, n1.xy)) + (e1.xy / dot(e1.xy, n0.xy)));
	output[2].position.xy += pl*((e1.xy / dot(e1.xy, n2.xy)) + (e2.xy / dot(e2.xy, n1.xy)));

	faceNormal = normalize(faceNormal);
	faceNormal = mul(float4(faceNormal, 0.0f), VoxelTransform).xyz;
	float4 plane = float4(faceNormal, dot(faceNormal, mul(float4(input[0].position.xyz, 1.0f), VoxelTransform).xyz));
	[unroll]
	for (uint p = 0; p<3; p++)
		output[p].plane = plane;

#ifndef __ORBIS__
	[unroll]
	for (uint v = 0; v<3; v++)
		output[v].viewIndex = viewIndex;
#endif // __ORBIS__

	[unroll]
	for (uint j = 0; j<3; j++)
		outputStream.Append(output[j]);

	outputStream.RestartStrip();
}

[maxvertexcount(3)]
void VoxelizeSurface_GS(triangle VS_Output input[3], inout TriangleStream<GS_Output> outputStream)
{
	VoxelizeSurface(input, outputStream);
}

ON_ORBIS([maxvertexcount(1)])
ON_DX([maxvertexcount(3)])
void VoxelizeSurfaceCompute_GS(triangle VS_Output input[3], inout TriangleStream<GS_Output> outputStream)
{
#ifdef __WAVE__

	float3 tri[3];

	[unroll]
	for(uint i=0; i<3; i++)
		tri[i] = input[i].position.xyz * VoxelVolumeScale + VoxelVolumeOffset;

	// Force full rasterization in GS
	VS_CS(tri[0], tri[1], tri[2]);

#else // __WAVE__
	VoxelizeSurface(input, outputStream);
#endif // __WAVE__
}

///////////////////////////////////////////////////////////////////////////////
// Plane Box Overlap code from RayTracing
///////////////////////////////////////////////////////////////////////////////

// Description:
// Determine if the axis aligned box intersects with the specified plane.
// Arguments:
// normal - The normal of the plane to intersect.
// vert - A point on the plane to intersect.
// maxbox - The half size of the axis aligned box to intersect. The center of the box is at the origin.
// Return Value List:
// true - The box intersects the plane.
// false - The box does not intersect the plane.
bool PlaneBoxOverlap(float3 normal, float3 vert, float3 maxbox)	
{
	// Generate box min and max. Translate plane to origin (-vert), translate box the same.
	float3 v0 = -maxbox - vert;
	float3 v1 = maxbox - vert;
	
	// Generate min and max verts of the box in the acis of the plane's normal.
	float3 vmin = normal > 0.0f ? v0 : v1;
	float3 vmax = normal > 0.0f ? v1 : v0;
	
	// If the box is entirely one side or the other of the box then it doesn't intersect.
	if(dot(normal, vmin) > 0.0f || dot(normal, vmax) < 0.0f)
		return false;
	else
		return true;
}

//======================== X-tests ========================

#define AXISTEST_X01(a, b, fa, fb)			   \
	p0 = a*v0.y - b*v0.z;			       	   \
	p2 = a*v2.y - b*v2.z;			       	   \
	rad = fa * boxhalfsize.y + fb * boxhalfsize.z;   \
	if(min(p0,p2) > rad || max(p0,p2) < -rad) \
		return false; 

#define AXISTEST_X2(a, b, fa, fb)			   \
	p0 = a*v0.y - b*v0.z;			           \
	p1 = a*v1.y - b*v1.z;			       	   \
	rad = fa * boxhalfsize.y + fb * boxhalfsize.z;   \
	if(min(p0,p1) > rad || max(p0,p1) < -rad) \
		return false;


//======================== Y-tests ========================

#define AXISTEST_Y02(a, b, fa, fb)			   \
	p0 = -a*v0.x + b*v0.z;		      	   \
	p2 = -a*v2.x + b*v2.z;	       	       	   \
	rad = fa * boxhalfsize.x + fb * boxhalfsize.z;   \
	if(min(p0,p2) > rad || max(p0,p2) < -rad) \
		return false;

#define AXISTEST_Y1(a, b, fa, fb)			   \
	p0 = -a*v0.x + b*v0.z;		      	   \
	p1 = -a*v1.x + b*v1.z;	     	       	   \
	rad = fa * boxhalfsize.x + fb * boxhalfsize.z;   \
	if(min(p0,p1) > rad || max(p0, p1) < -rad) \
		return false;



//======================== Z-tests ========================



#define AXISTEST_Z12(a, b, fa, fb)			   \
	p1 = a*v1.x - b*v1.y;			           \
	p2 = a*v2.x - b*v2.y;			       	   \
	rad = fa * boxhalfsize.x + fb * boxhalfsize.y;   \
	if(min(p1,p2) > rad || max(p1, p2) < -rad) \
		return false;

#define AXISTEST_Z0(a, b, fa, fb)			   \
	p0 = a*v0.x - b*v0.y;				   \
	p1 = a*v1.x - b*v1.y;			           \
    rad = fa * boxhalfsize.x + fb * boxhalfsize.y;   \
	if(min(p0, p1) > rad || max(p0, p1) < -rad) \
		return false;

// Description:
// Test a triangle for intersection with an axis aligned box.
// Arguments:
// bexcenter - The center of the axis aligned box.
// boxhalfsize - The half size of the axis aligned box.
// triVert0 - The first vertex of the triangle.
// triVert1 - The second vertex of the triangle.
// triVert2 - The third vertex of the triangle.
// Return Value List:
// true - The triangle does intersect the axis aligned box.
// false - The triangle does not intersect the axis aligned box.
bool TriBoxOverlap(float3 boxcenter,float3 boxhalfsize, float3 triVert0, float3 triVert1, float3 triVert2)
{
	// use separating axis theorem to test overlap between triangle and box 
	// need to test for overlap in these directions: 
	// 1) the {x,y,z}-directions (actually, since we use the AABB of the triangle we do not even need to test these) 
	// 2) normal of the triangle 
	// 3) crossproduct(edge from tri, {x,y,z}-direction).. this gives 3x3=9 more tests 

	float p0,p1,p2,rad;		
   
	 // move everything so that the boxcenter is in (0,0,0) 
	float3 v0 = triVert0 - boxcenter;
	float3 v1 = triVert1 - boxcenter;
	float3 v2 = triVert2 - boxcenter;

	// compute triangle edges 
	float3 e0 = v1 - v0;
	float3 e1 = v2 - v1;
	float3 e2 = v0 - v2;
  
	// Bullet 1: 
	// first test overlap in the {x,y,z}-directions 
	// find min, max of the triangle each direction, and test for overlap in that direction -- this is equivalent to testing a minimal AABB around the triangle against the AABB
	
	float3 axisMin = min(v0,min(v1,v2));
	float3 axisMax = max(v0,max(v1,v2));
	 
	if(any(axisMin > boxhalfsize) || any(axisMax < -boxhalfsize))
		return false;

	// Bullet 2: 
	//  test if the box intersects the plane of the triangle 
	//  compute plane equation of triangle: normal*x+d=0 
#if 0 // Skipping since plane test was done earlier
	float3 normal = cross(e0,e1);
    if(!PlaneBoxOverlap(normal,v0,boxhalfsize)) 
		return false;
#endif
   
	//  test the 9 tests first (this was faster) 
	float3 fe = abs(e0);
	AXISTEST_X01(e0.z, e0.y, fe.z, fe.y);
	AXISTEST_Y02(e0.z, e0.x, fe.z, fe.x);
	AXISTEST_Z12(e0.y, e0.x, fe.y, fe.x);

	fe = abs(e1);
	AXISTEST_X01(e1.z, e1.y, fe.z, fe.y);
	AXISTEST_Y02(e1.z, e1.x, fe.z, fe.x);
	AXISTEST_Z0(e1.y, e1.x, fe.y, fe.x);

	fe = abs(e2);
	AXISTEST_X2(e2.z, e2.y, fe.z, fe.y);
	AXISTEST_Y1(e2.z, e2.x, fe.z, fe.x);
	AXISTEST_Z12(e2.y, e2.x, fe.y, fe.x);

	return true;
}

float DistanceFromPlane(float3 pos, float3 dir, float4 plane)
{
	float pointDistFromPlane = dot(pos, plane.xyz) - plane.w;
	float dirToPlane = -dot(plane.xyz, dir);
	return pointDistFromPlane / dirToPlane;
}

float4 VoxelizeSurface_PS(GS_Output input) : FRAG_OUTPUT_COLOR0
{
#ifdef __ORBIS__
	float4 plane = GetParameterP0(input.plane);
	uint viewIndex = GetViewIndex(plane.xyz);
#else
	float4 plane = input.plane;
	uint viewIndex = input.viewIndex;
#endif
	// Pick out axis and convert input.position to an address in the buffer
	float3 gridPos;
	if(viewIndex == 0)
	{
		ON_DX(gridPos = float3(GridDimension.x * input.position.z, input.position.x, GridDimension.z - input.position.y);)
		ON_ORBIS(gridPos = float3(GridDimension.x * input.position.z, input.position.x, input.position.y);)
		gridPos.x = DistanceFromPlane(float3(0.0f, gridPos.yz), float3(1, 0, 0), plane);
	}
	else if(viewIndex == 1)
	{
		ON_DX(gridPos = float3(input.position.x, GridDimension.y * input.position.z, GridDimension.z - input.position.y);)
		ON_ORBIS(gridPos = float3(input.position.x, GridDimension.y * input.position.z, input.position.y);)
		gridPos.y = DistanceFromPlane(float3(gridPos.x, 0.0f, gridPos.z), float3(0, 1, 0), plane);
	}
	else
	{
		ON_DX(gridPos = float3(input.position.x, GridDimension.y - input.position.y, GridDimension.z * input.position.z);)
		ON_ORBIS(gridPos = float3(input.position.x, input.position.y, GridDimension.z * input.position.z);)
		gridPos.z = DistanceFromPlane(float3(gridPos.xy, 0.0f), float3(0, 0, 1), plane);
	}

	// Skip the voxel if not overlapping
	float3 mid = float3(0.5f, 0.5f, 0.5f);
#ifdef __ORBIS__
	if(!TriBoxOverlap(floor(gridPos.xyz) + mid, mid, GetParameterP0(input.tri), GetParameterP1(input.tri), GetParameterP2(input.tri)))
#else
	if(!TriBoxOverlap(floor(gridPos.xyz) + mid, mid, input.tri0, input.tri1, input.tri2))
#endif
		discard;
	return setVoxel(gridPos);
}

technique11 VoxelizeSurfaceGeometry
{
    pass p0
    {
		SetVertexShader( CompileShader( vs_5_0, VoxelizeSurface_VS() ) );
		SetGeometryShader( CompileShader( gs_5_0, VoxelizeSurface_GS() ) );
		SetPixelShader( CompileShader( ps_5_0, VoxelizeSurface_PS() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthDisabledState, 0);
		SetRasterizerState( DefaultRasterState );
    }
};

technique11 VoxelizeSurfaceGSVoxels
{
    pass p0
    {
		SetVertexShader( CompileShader( vs_5_0, VoxelizeSurface_VS() ) );
		SetGeometryShader( CompileShader( gs_5_0, VoxelizeSurfaceCompute_GS() ) );
		SetPixelShader( CompileShader( ps_5_0, VoxelizeSurface_PS() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( DepthDisabledState, 0);
		SetRasterizerState( DefaultRasterState );
    }
};

///////////////////////////////////////////////////////////////////////////////
// Voxel Population via Compute
///////////////////////////////////////////////////////////////////////////////

ByteAddressBuffer VertexData : DataBlock;			// Assumed float3
ByteAddressBuffer IndexData : IndexDataBlock;		// Parsed as uint or ushort based on format
 
float4x4 ModelToVoxel;
uint VertexStrideInBytes;
uint NumTriangles;

void VoxelizeSurface_Common(uint3 indices)
{
	float3 v0, v1, v2;
	v0 = asfloat(VertexData.Load3(mul24(indices.x, VertexStrideInBytes)));
	v1 = asfloat(VertexData.Load3(mul24(indices.y, VertexStrideInBytes)));
	v2 = asfloat(VertexData.Load3(mul24(indices.z, VertexStrideInBytes)));

	// transform vertices to voxel space
	v0 = mul(float4(v0, 1.0), ModelToVoxel).xyz;
	v1 = mul(float4(v1, 1.0), ModelToVoxel).xyz;
	v2 = mul(float4(v2, 1.0), ModelToVoxel).xyz;

	VS_CS(v0, v1, v2);
}

[numthreads(64, 1, 1)]
void VoxelizeSurface_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	const uint tri = DispatchThreadId.x;
	if(tri >= NumTriangles)
		return;

	uint3 indices;
	indices = IndexData.Load3(mul24(tri, 3 * 4));

	VoxelizeSurface_Common(indices);
}

[numthreads(64, 1, 1)]
void VoxelizeSurface_ShortIndices_CS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
	const uint tri = DispatchThreadId.x;
	if(tri >= NumTriangles)
		return;

	uint3 indices;
	int tri3 = (tri*3) / 2;
	uint a = IndexData.Load(mul24(tri3, 4));
	uint b = IndexData.Load(mul24((tri3+1), 4));
	if(tri & 0x1)
	{
		indices.x = (a >> 16) & 0xFFFF;
		indices.y = (b      ) & 0xFFFF;
		indices.z = (b >> 16) & 0xFFFF;
	}
	else
	{
		indices.x = (a      ) & 0xFFFF;
		indices.y = (a >> 16) & 0xFFFF;
		indices.z = (b      ) & 0xFFFF;
	}
	
	VoxelizeSurface_Common(indices);
}

technique11 VoxelizeSurfaceCS
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, VoxelizeSurface_CS() ) );
	}
}

technique11 VoxelizeSurfaceCS_ShortIndices
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, VoxelizeSurface_ShortIndices_CS() ) );
	}
}
