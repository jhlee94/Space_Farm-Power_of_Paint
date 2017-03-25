/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"
#include "../PhyreSceneWideParametersD3D.h"

struct Ray
{
	float3 m_position;
	float3 m_direction;
	uint m_triangleIndex;
	uint m_pixelLocation;
};

Texture3D <uint> BrickIndexTexture;									// The index of the bricks for voxel cells.
StructuredBuffer <uint> BrickOffsetCountBuffer;						// The structured buffer of triangle index offset and counts for each voxel cell.
StructuredBuffer <uint> BrickTriangleIndexBuffer;					// The strucutred buffer of concatenated triangle indices for all cells (indexed by BrickOffsetCountBuffer).

StructuredBuffer <PCapturedTriangle> CapturedTriangleBuffer;		// The structured buffer of all captured triangles.

Texture2D <float4> TrianglePositionTexture;							// The G Buffer containing triangle positions and indices for the rasterized viewpoint.

RWStructuredBuffer <Ray> RWRayBuffer;								// The structured buffer containing the accumulated rays for processing.
StructuredBuffer <Ray> RayBuffer;									// The structured buffer containing the accumulated rays for processing.
StructuredBuffer <uint> RayCountBuffer;								// The structured buffer containing the ray count for RayBuffer.
uint RayBaseIndex;													// The base index for rays being processed by TraceRays.

RWStructuredBuffer <float4> RWOutputBuffer;							// The output buffer containing the raytraced lighting solution for the scene.

#define VoxelResolution 64											// The number of cells across the Voxel grid.
#define BrickSize 4													// The number of cells across the Brickmap cells.
#define TotalSize 256												// The total size of the grid (voxel res * brick size)
#define InvVoxelResolution (1.0f/64.0f)								// The reciprocal of the voxel resolution.
#define InvTotalSize (1.0f/256.0f)									// The reciprocal of the total size.

float CurrentPass;													// The iteration index for the raytracing.

#ifdef __ORBIS__
#define ALLOW_UAV_CONDITION
#else
#define ALLOW_UAV_CONDITION [allow_uav_condition]
#endif

//#define HASH_TRIANGLES

// Description:
// The vertex structure for the full screen render.
struct VsFsOutput
{
    float4 Position  : SV_POSITION;
    float2 Uv : TEXCOORD0;
};

// Description:
// Generate a random float between 0 and 1 from an integer seed.
// Arguments:
// n - The seed from which to generate the random number.
// Returns:
// The random number.
float NormalisedRand( int n )
{
	n = (n << 13) ^ n;
	int randValue = (n * (n*n*15731+789221) + 1376312589) & 0x7fffffff;
	return float(randValue) * (1.0f/2147483647.0f);
}

// Description:
// Generate a random direction.
// Arguments:
// dir - The principal axis for the random direction.
// spread - The amount of spread for the normal away from the principal axis.
// Returns:
// The randomized direction.
float3 GenerateRandomisedDirection(float3 dir, float spread, int seed)
{	
	float r1 = (NormalisedRand(seed + 17) * 6.21f);
	float r2 = NormalisedRand(seed+191) * spread;
	float r2s = sqrt(r2);
	float3 w = dir;
	float3 u = abs(w.x) > 0.3f ? float3(0.0f,1.0f,0.0f) : float3(1.0f,0.0f,0.0f);
	u = normalize(cross(u, w));
	float3 v = normalize(cross(w,u));
	float3 d = normalize( u*cos(r1)*r2s + v*sin(r1)*r2s + w*sqrt(1-r2) ); 
	return d;
}

// Description:
// Vertex positions for a full screen tri-list.
static const float2 SlicePositions[6] = 
{
	float2(-1.0f,1.0f),
	float2(-1.0f,-1.0f),
	float2(1.0f,1.0f),
	float2(1.0f,1.0f),
	float2(-1.0f,-1.0f),
	float2(1.0f,-1.0f)
};

// Description:
// Generate tri-list vertices for a full screen quad.
// Arguments:
// vertexIndex - The index of the vertex (0-5) of the tri-list.
// Returns:
// The vertex for the full screen tri-list.
VsFsOutput VS_Fullscreen(uint vertexIndex : SV_VERTEXID)
{
	VsFsOutput Out = (VsFsOutput)0;
	
	Out.Position = float4(SlicePositions[vertexIndex].xy,0,1);
	Out.Uv = Out.Position.xy * 0.5f + 0.5f;
	Out.Uv.y = 1-Out.Uv.y;
	
	return Out;
}

#ifdef __ORBIS__
	//! Set the output format for picking to be 32 bit.
	#ifdef PHYRE_ENTRYPOINT_PS_RaytraceBrickMap
		#pragma PSSL_target_output_format(default FMT_32_ABGR)
	#else //! PHYRE_ENTRYPOINT_PS_RaytraceBrickMap
		#pragma PSSL_target_output_format(default FMT_FP16_ABGR)
	#endif //! PHYRE_ENTRYPOINT_PS_RaytraceBrickMap
#endif //! __ORBIS__

#ifdef HASH_TRIANGLES
	uint hash3(float3 v)
	{
		return asuint(v.x) ^ asuint(v.y) ^ asuint(v.z);
	}
#endif

// Description:
// Populates RWRayBuffer with a list of rays based on the triangles rasterized to TrianglePositionTexture (The G Buffer rendered from PhyreBrickMap.fx)
// Triangle intersections in TrianglePositionTexture stored as position and index into CapturedTriangleBuffer for the triangle.
// 1 ray is generated for each pixel that contains a triangle and added to the ray buffer.
// Arguments:
// GroupID - The group ID of the compute shader invocation.
// DispatchThreadId - The dispatch thread ID of the compute shader invocation.
// GroupThreadId - The group thread IS of the compute shader invocation.
// GroupIndex - The group index of the compute shader invocation.
[numthreads(8, 8, 1)]
void CS_AccumulateRays(uint3 GroupId : SV_GroupID, 
						uint3 DispatchThreadId : SV_DispatchThreadID, 
						uint3 GroupThreadId : SV_GroupThreadID,
						uint GroupIndex : SV_GroupIndex)
{
	uint2 textureWidthHeight;
	TrianglePositionTexture.GetDimensions(textureWidthHeight.x, textureWidthHeight.y);

	uint2 pixelPosition = DispatchThreadId.xy & 0xffff;
	int2 readPosition = int2(pixelPosition);

	if ((pixelPosition.x < textureWidthHeight.x) && (pixelPosition.y < textureWidthHeight.y))
	{
#ifdef __ORBIS__
		readPosition.y = (uint(textureWidthHeight.y) - 1) - readPosition.y;
#endif

		float4 triPos = TrianglePositionTexture.Load(int3(readPosition,0));
		uint triangleIndex = triPos.w >= 0.0f ? asuint(triPos.w) : 0xffffffff;

		if(triangleIndex != 0xffffffff)
		{		
			uint pixelLocation = uint(pixelPosition.x + pixelPosition.y * uint(textureWidthHeight.x));

			// Seed the random ray direction from the pixel location and the pass number.
			uint seed = pixelLocation;
			seed += uint(CurrentPass) * 1337;
			seed = seed & 0xffff;

			float3 normal = normalize( cross( CapturedTriangleBuffer[triangleIndex].m_v2 - CapturedTriangleBuffer[triangleIndex].m_v0,  CapturedTriangleBuffer[triangleIndex].m_v1 - CapturedTriangleBuffer[triangleIndex].m_v0) );
			float3 rayDirection = GenerateRandomisedDirection(-normal, 1.0f, seed ); 
			float3 rayPosition = triPos.xyz; 

			Ray ray;
#ifdef OFFSET_RAYS
			rayPosition += OFFSET_RAYS * rayDirection;
#endif // OFFSET_RAYS
			ray.m_position = rayPosition;
			ray.m_direction = rayDirection;
			ray.m_triangleIndex = triangleIndex;
			ray.m_pixelLocation = pixelLocation;

#ifdef HASH_TRIANGLES
			uint hash = 0;
			hash ^= hash3(CapturedTriangleBuffer[triangleIndex].m_v0);
			hash ^= hash3(CapturedTriangleBuffer[triangleIndex].m_v1);
			hash ^= hash3(CapturedTriangleBuffer[triangleIndex].m_v2);
			ray.m_triangleIndex = hash;
#endif // HASH_TRIANGLES

			uint idx = RWRayBuffer.IncrementCounter();
			RWRayBuffer[idx] = ray;
		}
	}
}

#ifdef __ORBIS__
#define PE_RAYTRACER_GROUP_THREAD_COUNT 64
#define PE_MAX_TRIANGLE_LISTS_PER_GROUP 64
#else //! __ORBIS__
#define PE_RAYTRACER_GROUP_THREAD_COUNT 32
#define PE_MAX_TRIANGLE_LISTS_PER_GROUP 32
#endif //! __ORBIS__

groupshared uint ThreadRayIndices[PE_RAYTRACER_GROUP_THREAD_COUNT];

groupshared uint TriangleThreads[PE_MAX_TRIANGLE_LISTS_PER_GROUP];
groupshared uint NumTriangleThreads;
groupshared uint NumTrianglesToTest;
groupshared uint ThreadHits[PE_RAYTRACER_GROUP_THREAD_COUNT];

#define MAX_ITERATIONS 32

#define BRICK_INDEX_SCALE (BrickSize*BrickSize*BrickSize)

// Description:
// Test if the ray intersects the specified triangle.
// Arguments:
// v0 - The first vertex of the triangle to test against.
// v1 - The second vertex of the triangle to test against.
// v2 - The third vertex of the triangle to test against.
// rayOrigin - The origin of the ray to test.
// rayDir - The direction of the ray to test.
bool RayTriangleIntersectionTest(float3 v0, float3 v1, float3 v2, float3 rayOrigin, float3 rayDir)		 
{  
	float3 tvec = rayOrigin - v0;  
	float3 pvec = cross(rayDir, v2 - v0);  
	float3 qvec = cross(tvec, v1 - v0); 

	float  det  = 1.0f / dot(v1 - v0, pvec);  

	float u = dot(tvec, pvec) * det;  
	float v = dot(rayDir, qvec) * det;  
	float t = dot(v2 - v0, qvec) * det;  
	
	return u >= 0.0f && u <= 1.0f && v >= 0.0f && (u+v) <= 1.0f && t >= 0.0f;
}  

// Description:
// Raytrace one ray from the ray buffer. This affects a single pixel in the output buffer.
// Arguments:
// rayIndex - The index of the ray in the ray buffer.
// threadIndex - The index of the thread being used to process the ray.
void RayBrickMapQueueSimple(uint rayIndex, uint threadIndex)
{		
	float3 rayPosition = RayBuffer[rayIndex].m_position; 
	float3 rayDirection = RayBuffer[rayIndex].m_direction;
	float3 absRayInvDirection = rcp(abs(rayDirection));
	float3 rayDirSign = saturate(rayDirection * 1000000.0f);

	uint rayAlive = 1;
	float outputUpdate = 0.0f;

	ALLOW_UAV_CONDITION [loop] for(int iterations = 0; iterations < MAX_ITERATIONS; ++iterations)
	{
		NumTrianglesToTest = 0;						// The total number of accumulated triangles to test.
		NumTriangleThreads = 0;						// The number of threads that contributed to the accumulated triangles (number of entries in the TriangleThreads array).
		uint triThreadIndex = 0xffffffff;

		{
			// Grab the brick index from the top level volume texture (64x64x64).
			uint brickIndex = BrickIndexTexture.Load(int4(rayPosition * float(VoxelResolution),0));
		
			// If we have a brick then find the element in the 4x4x4 for the triangles.
			[branch] if(brickIndex != 0xffffffff && rayAlive)
			{
				uint3 brickSubPos = uint3(rayPosition * float(TotalSize)) & (BrickSize-1);
				// calculate brick index
				uint brickCellAddress = dot(brickSubPos, uint3(1, BrickSize, BrickSize * BrickSize));
				brickCellAddress += brickIndex * BRICK_INDEX_SCALE;

				// See if this brick cell has any triangles, and if so, append them to the list of triangles to process (along with the index of the ray that hit them).
				uint triangleOffsetCount = BrickOffsetCountBuffer[brickCellAddress];
				uint triangleCount = triangleOffsetCount >> 22;

				if(triangleCount)
				{
					// Add the triangle cell to the intersection test list. Accumulate the number of triangles.
					InterlockedAdd(NumTrianglesToTest, triangleCount);							// Add ot the triangle total.
					InterlockedAdd(NumTriangleThreads, 1, triThreadIndex);						// Allocate an entry in the bricks-to-process list.

					TriangleThreads[triThreadIndex] = triangleOffsetCount;						// The offset and count of the triangles in the brick to process.
					ThreadRayIndices[triThreadIndex] = rayIndex;								// The ray index that hit the triangles in the brick.
					ThreadHits[triThreadIndex] = 0;												// Reset the hit count for this processing thread.
				}

				// After all of the triangles have been processed, this thread will add the result of triThreadIndex to the result buffer.
			}

			{
				// Step the ray along to the next cell.
				float cellRes = brickIndex == 0xffffffff ? float(VoxelResolution) : float(TotalSize);
				float cellSize = brickIndex == 0xffffffff ? float(InvVoxelResolution) : float(InvTotalSize);
		
				// Scale the ray position up so that integer boundaries lie on the cell boundaries. Ie, for empty top level cell 0-64, for a brick underneath 0-256.
				// The the fractional part gets us the proportion across our curent cell in X,Y,Z so that we can figure out how much to step to reach the nearest boundary.
				// This is the distance to the integer above or below, depending on the ray direction.
				float3 rayPosScaled = rayPosition * cellRes; 
				rayPosScaled = frac(rayPosScaled);	

				// Using the ray's direction work out far to our nearest cell edge based on direction in each component.  Calculated as proportion of cell size.
				rayPosScaled = lerp(rayPosScaled, 1.0f-rayPosScaled, rayDirSign);

				// Calculate minimum step (as proportion of rayDirection) to carry the ray to the next cell boundary.
				float3 tmaxScaled = rayPosScaled * absRayInvDirection;
				float stepDelta  = min3(tmaxScaled.x, tmaxScaled.y, tmaxScaled.z);
				
				// Apply the ray step, adding a small epsilon to make sure we bump across the cell boundary.
				// Otherwise there's a danger that moving the ray forward doesnt actually move it into the next cell.
				const float rayEps = 0.00005f;
				rayPosition += rayDirection * (stepDelta*cellSize + rayEps);
			}
		}
		
		// TriangleThreads contains offset and counts of triangles.
		// tcounter manages a running tally of index into the TriangleThreads array (upper 16 bits) and the total triangle count (lower 16 bits).

		// Built list of rays against lists of triangles
		// Need to test ray ID ThreadRayIndices[x] against all(TriangleThreads[x]) and write to TriangleThreads[x]
		// x = 0 to NumTriangleThreads
		// TriangleThreads[x] represents a block of triangles to test
		// Each thread T should be reading the triangle where Triangle ID % PE_RAYTRACER_GROUP_THREAD_COUNT == Thread ID

		{	
			uint tcounter = 0;		// Upper 16 = TriangleThreads index, Lower 16 = Tri in current block

			ALLOW_UAV_CONDITION for(uint triI = threadIndex; triI < NumTrianglesToTest; triI += PE_RAYTRACER_GROUP_THREAD_COUNT)
			{
				uint triangleIndex = 0;
				uint triThread = 0;

				// Skip down the TriangleThreads list to the block that contains the the triangle index triI.
				ALLOW_UAV_CONDITION while(tcounter < (NumTriangleThreads << 16))
				{
					uint triThreadData = TriangleThreads[(tcounter >> 16)];
					uint triCountInBrick = triThreadData >> 22;
					if(((tcounter&0xffff)+triCountInBrick) > triI) // Does brick contain next triangle?
					{
						// This brick contains triangle triI.
						uint toff = triThreadData & ((1<<22)-1);											// Offset of triangles in BrickTriangleIndexBuffer.
						triangleIndex = BrickTriangleIndexBuffer[toff + (triI - (tcounter&0xffff))];		// Get index of triangle triI.
						triThread = (tcounter >> 16);														// And the index of the triThread.
						break;
					}
					else
					{
						// This brick does not contain triI.
						tcounter += triCountInBrick + (1<<16);												// Skip to the next brick.												
					}
				}

				// Don't test a ray against the triangle that emitted that ray (otherwise triangles would contribute to their own ambient occlusion).
				uint threadRayIndex = ThreadRayIndices[triThread];
#ifdef HASH_TRIANGLES

				PCapturedTriangle tri = CapturedTriangleBuffer[triangleIndex];
				uint hash = 0;
				hash ^= hash3(tri.m_v0);
				hash ^= hash3(tri.m_v1);
				hash ^= hash3(tri.m_v2);
				if(RayBuffer[threadRayIndex].m_triangleIndex != hash)
				{

#else // HASH_TRIANGLES

				if(RayBuffer[threadRayIndex].m_triangleIndex != triangleIndex)
				{
					PCapturedTriangle tri = CapturedTriangleBuffer[triangleIndex];

#endif // HASH_TRIANGLES
					bool hit = RayTriangleIntersectionTest(tri.m_v0, tri.m_v1, tri.m_v2, RayBuffer[threadRayIndex].m_position, RayBuffer[threadRayIndex].m_direction);
					InterlockedAdd(ThreadHits[triThread], hit ? 1u : 0u);
				}
			}
		}
		
		// Only check the ray if a brick was checked
		if(triThreadIndex < PE_RAYTRACER_GROUP_THREAD_COUNT)
		{
			//rayDead = min(ThreadHits[triThreadIndex], 1u);	
			if(ThreadHits[triThreadIndex])
			{
				// Ray hit something - update result with dark.
				outputUpdate = 0.0f;
				rayAlive = 0;
			}
		}
		
		// Ray position will be outside of the 0-1 range in any of x, y or z for outside the grid.
		float3 f = min(rayPosition, 1.0f - rayPosition);
		float minf = min3(f.x, f.y, f.z);				// Negative for outside of grid.
		if( (minf < 0 // Left grid
			|| iterations == (MAX_ITERATIONS - 1))
			&& rayAlive)
		{
			// Ray left the volume or didn't hit anything in the prescribed number of iterations - update result with light.
			outputUpdate = 1.0f;
			rayAlive = 0;
		}
	}
	
	// Update the output buffer with the result.
	if(!rayAlive)
		RWOutputBuffer[ RayBuffer[rayIndex].m_pixelLocation ] += float4(outputUpdate.xxx, 1);
}

// Description:
// Trace the rays that were accumulated in the ray buffer.
// Arguments:
// GroupID - The group ID of the compute shader invocation.
// DispatchThreadId - The dispatch thread ID of the compute shader invocation.
// GroupThreadId - The group thread IS of the compute shader invocation.
// GroupIndex - The group index of the compute shader invocation.
[numthreads(PE_RAYTRACER_GROUP_THREAD_COUNT, 1, 1)]
void CS_TraceRays(uint3 GroupId : SV_GroupID, 
						uint3 DispatchThreadId : SV_DispatchThreadID, 
						uint3 GroupThreadId : SV_GroupThreadID,
						uint GroupIndex : SV_GroupIndex)
{
	uint rayIndex = DispatchThreadId.x + RayBaseIndex;
	uint rayCount = RayCountBuffer[0];

	// Each thread group processes PE_RAYTRACER_GROUP_THREAD_COUNT rays.
	if ((GroupId.x * PE_RAYTRACER_GROUP_THREAD_COUNT) < rayCount)
	{
		RayBrickMapQueueSimple(rayIndex, GroupIndex);
	}
}

// Description:
// Copy the raytracing results to the screen.
// Arguments:
// In - The pixel in the screen to copy the raytracing result for.
// Returns:
// The value to write to the screen.
float4 PS_CopyResultsToScreen( VsFsOutput In ) : FRAG_OUTPUT_COLOR0
{ 	
	int2 pixelPosition = int2(In.Position.xy);
	float4 val = RWOutputBuffer[pixelPosition.y * uint(screenWidthHeight.x) + pixelPosition.x];
	
	val.xyz /= (val.w + 0.00001f); // Offset to allow for zero
	return float4(val.xyzz);
}

// Description:
// Copy the raytracing results to the lightmap.
// Arguments:
// In - The pixel in the lightmap to copy the raytracing result for.
// Returns:
// The value to write to the lightmap.
float4 PS_CopyResultsToLightmap( VsFsOutput In ) : FRAG_OUTPUT_COLOR0
{ 	
	int2 pixelPosition = int2(In.Position.xy);
	pixelPosition.y = ViewportWidthHeight.y - (pixelPosition.y + 1);

	float4 val = 0.0f;

	// Expand to fill gutter around UV map
	const int gutter = 2;
	for(int y = -gutter; y <= gutter; ++y)
	{
		for(int x = -gutter; x <= gutter; ++x)
		{
			float4 val2 = RWOutputBuffer[(pixelPosition.y+y) * int(ViewportWidthHeight.x) + pixelPosition.x + x];
			int2 fxy = int2(x, y);
			float w = 9.0f - dot(fxy, fxy);
			val2 *= w;

			val += val2;
		}
	}
	
	val.xyz /= (val.w + 0.00001f); // Offset to allow for zero
	return float4(val.xyzz);
}

// Description:
// Copy the raytracing results to the lightmap.
// Arguments:
// In - The pixel in the lightmap to copy the raytracing result for.
// Returns:
// The value to write to the lightmap.
float4 PS_CopyResultsToLightmapWrapped(VsFsOutput In) : FRAG_OUTPUT_COLOR0
{
	int2 pixelPosition = int2(In.Position.xy);
	pixelPosition.y = ViewportWidthHeight.y - (pixelPosition.y + 1);

	int2 iViewportWidthHeight = int2(ViewportWidthHeight);
	pixelPosition += iViewportWidthHeight;

	float4 val = 0.0f;

	// Expand to fill gutter around UV map
	const int gutter = 2;
	for (int y = -gutter; y <= gutter; ++y)
	{
		int posy = (pixelPosition.y + y) & (iViewportWidthHeight.y - 1);
		posy *= iViewportWidthHeight.x;
		for (int x = -gutter; x <= gutter; ++x)
		{
			int posx = (pixelPosition.x + x) & (iViewportWidthHeight.x - 1);
			float4 val2 = RWOutputBuffer[posy + posx];
				int2 fxy = int2(x, y);
				float w = 9.0f - dot(fxy, fxy);
			val2 *= w;

			val += val2;
		}
	}

	val.xyz /= (val.w + 0.00001f); // Offset to allow for zero
	return float4(val.xyzz);
}

#ifndef __ORBIS__

BlendState NoBlend {
	AlphaToCoverageEnable = FALSE;
	BlendEnable[0] = FALSE;
};
   
DepthStencilState NoDepthState {
	DepthEnable = FALSE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

DepthStencilState TestDepthState {
	DepthEnable = TRUE;
	DepthWriteMask = All;
	DepthFunc = Less;
	StencilEnable = FALSE; 
};

RasterizerState DefaultRasterState 
{
	CullMode = None;
	FillMode = Solid;
	DepthBias = 0;
	ScissorEnable = false;
};

technique11 CopyResultsToScreen
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_5_0, VS_Fullscreen() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_CopyResultsToScreen() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 CopyResultsToLightmap
{
	pass p0
	{
		SetVertexShader( CompileShader( vs_5_0, VS_Fullscreen() ) );
		SetPixelShader( CompileShader( ps_5_0, PS_CopyResultsToLightmap() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
	}
}

technique11 CopyResultsToLightmapWrapped
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Fullscreen()));
		SetPixelShader(CompileShader(ps_5_0, PS_CopyResultsToLightmapWrapped()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(NoDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
}

technique11 AccumulateRays
{
    pass p0
    {   
        SetComputeShader( CompileShader( cs_5_0, CS_AccumulateRays() ) );
    }    
};
technique11 TraceRays
{
    pass p0
    {   
        SetComputeShader( CompileShader( cs_5_0, CS_TraceRays() ) );
    }    
};

#endif //! __ORBIS__
