/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"
#include "../PhyreShaderDefsD3D.h"
#include "../PhyreSceneWideParametersD3D.h"

#ifdef __ORBIS__
	//! Set the output format for picking to be 32 bit.
	#ifdef PHYRE_ENTRYPOINT_PS_RenderGBuffer
		#pragma PSSL_target_output_format(default FMT_32_ABGR)
	#else //! PHYRE_ENTRYPOINT_PS_RenderGBuffer
		#pragma PSSL_target_output_format(default FMT_FP16_ABGR)
	#endif //! PHYRE_ENTRYPOINT_PS_RenderGBuffer
#endif //! __ORBIS__

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
	float3 normal = cross(e0,e1);
    if(!PlaneBoxOverlap(normal,v0,boxhalfsize)) 
		return false;
   
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

StructuredBuffer < PCapturedTriangle > CapturedTriangleBuffer;		// The buffer of triangles captured during the initial scene render.
StructuredBuffer <uint> TriangleCountBuffer;						// The structured buffer that contains the total captured triangle count in CapturedTriangleBuffer.

RWStructuredBuffer <float> RWVoxelDataBuffer;						// The structured buffer that contains markers for top level brickmap cells that have triangles in.
StructuredBuffer <float> VoxelDataBuffer;							// The structured buffer that contains markers for top level brickmap cells that have triangles in.

RWStructuredBuffer <uint> RWBrickMapBuffer;							// The structured buffer that contains the header indices for the 64 cells in a brick.
StructuredBuffer <uint> BrickMapBuffer;								// The structured buffer that contains the header indices for the 64 cells in a brick.

RWStructuredBuffer <uint2> RWTriangleLinkedListBuffer;				// The linked list of triangles in each brick cell.
StructuredBuffer <uint2> TriangleLinkedListBuffer;					// The linked list of triangles in each brick cell.
StructuredBuffer <uint> TriangleLinkedListCount;					// The number of used triangles in the linked list of triangles in each brick cell.

RWStructuredBuffer <uint> RWCounterBuffer;							// The counter for managing allocation of the brick triangle index buffer
RWStructuredBuffer <uint> RWBrickOffsetCountBuffer;					// The offset and count of triangles in each brickmap cell. Offsets and sizes relate to the content of RWBrickTriangleIndexBuffer.
StructuredBuffer <uint> BrickOffsetCountBuffer;						// The offset and count of triangles in each brickmap cell. Offsets and sizes relate to the content of RWBrickTriangleIndexBuffer.
RWStructuredBuffer <uint> RWBrickTriangleIndexBuffer;				// The triangle indices for each brickmap cell.
uint BrickOffsetCountBufferBaseIndex;								// The base index for storing the triangles count per cell.

float4x4 GridToWorldTransform;										// The grid space to world space transform.

Texture3D <uint> BrickIndexTexture;									// The index of the allocated brick for each top level brickmap cell.
RWTexture3D <uint> RWBrickIndexTexture;								// The index of the allocated brick for each top level brickmap cell.

Texture2D <float4> LightmapTexture;									// The lightmap texture for rendering the preview geometry.

#define VoxelResolution uint3(64,64,64)								// The resolution of the top level voxels for the brickmap.
#define BrickSize 4													// The resolution of the brickmap cells within the voxel (4x4x4).


sampler LinearClampSampler
{
	Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VS_OUTPUT
{
    float4 Position  : SV_POSITION;
};

struct GS_SLICE_OUTPUT
{
    float4 Position : SV_POSITION;		// Projection coord
    float3 V0 : TEXCOORD0;				// Triangle position 0
    float3 V1 : TEXCOORD1;				// Triangle position 1
    float3 V2 : TEXCOORD2;				// Triangle position 2
    float2 ZExtents : TEXCOORD3;		// z slice extents
	float PrimitiveId : TEXCOORD4;
};

struct PS_SLICE_INPUT
{
    float4 Position : SV_POSITION;		// Projection coord
    float3 V0 : TEXCOORD0;				// Triangle position 0
    float3 V1 : TEXCOORD1;				// Triangle position 1
    float3 V2 : TEXCOORD2;				// Triangle position 2
    float2 ZExtents : TEXCOORD3;		// z slice extents
	float PrimitiveId : TEXCOORD4;
};

struct GS_GBUFFER_OUTPUT
{
    float4 Position : SV_POSITION;		// Projection coord
	float3 GridPos : TEXCOORD0;
	float PrimitiveId : TEXCOORD1;
};

struct GS_DEBUG_BRICKS_OUTPUT
{
	float4 Position : SV_POSITION;		// Projection coord
	float3 Color : TEXCOORD0;
};

struct PS_GBUFFER_INPUT
{
    float4 Position : SV_POSITION;		// Projection coord
	float3 GridPos : TEXCOORD0;
	float PrimitiveId : TEXCOORD1;
};

struct GS_DEBUG_OUTPUT
{
	float4 Position : SV_POSITION;		// Projection coord
	float3 Color : TEXCOORD0;			// Triangle color
	float3 GridPos : TEXCOORD1;			// Position in grid
};

// Description:
// Generate a dummy vertex to pass to the next stage. The actual geometry will be fetched by the subsequent geometry shader using the primitive ID.
// Returns:
// The dummy vertex.
VS_OUTPUT VS_RenderCapturedGeometry()
{
 	VS_OUTPUT Out = (VS_OUTPUT)0;
  	Out.Position = 0;
	return Out;    
}

// Description:
// Generate and output a quad that encloses the flattened bounds of the triangle in XY, with slice bounds in Z.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The triangle stream to which to add the output triangle.
// TriangelIndex - The index of the triangle to render.
[maxvertexcount(4)] void GS_RenderVoxelGeometry( triangle VS_OUTPUT input[3], inout TriangleStream<GS_SLICE_OUTPUT> OutputSliceStream, uint TriangleIndex : SV_PRIMITIVEID )
{
	uint maxTriCount = TriangleCountBuffer[0];
	if(TriangleIndex < maxTriCount)
	{
		PCapturedTriangle tri = CapturedTriangleBuffer[TriangleIndex];

		GS_SLICE_OUTPUT Out;
		Out.V0 = tri.m_v0;
		Out.V1 = tri.m_v1;
		Out.V2 = tri.m_v2;

		float3 invSize = 1.0f / float3(VoxelResolution);
	
		// Calculate the bounds for the triangle.
		float3 boundsMin = min(tri.m_v0, min(tri.m_v1, tri.m_v2));
		float3 boundsMax = max(tri.m_v0, max(tri.m_v1, tri.m_v2));
	
		// Scale XY up to projected viewport coordinates (-1 to +1)
		boundsMin.xy = boundsMin.xy * 2.0f - 1.0f;
		boundsMax.xy = boundsMax.xy * 2.0f - 1.0f;

		// Generate slice bounds - these will be iterated inclusively by the pixel shader.
		int sliceIndex0 = (int)(boundsMin.z * float(VoxelResolution.z));
		int sliceIndex1 = (int)(boundsMax.z * float(VoxelResolution.z));
	
		// Clamp slice bounds to voxel cells available.
		sliceIndex0 = max(sliceIndex0,0);
		sliceIndex1 = min(sliceIndex1,int(VoxelResolution.z-1));
	
		// Increase size of XY bounds in each direction.
		boundsMin.xy -= invSize.xy * 1.0f;
		boundsMax.xy += invSize.xy * 1.0f;
	
		Out.ZExtents = float2( sliceIndex0, sliceIndex1);
		Out.PrimitiveId = float(TriangleIndex);
	
#ifndef __ORBIS__		
		boundsMin.y = -boundsMin.y;
		boundsMax.y = -boundsMax.y;
#endif

		// Emit tri-strip for bounds of triangle.
		Out.Position = float4(boundsMin.x, boundsMax.y, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(boundsMin.xy, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(boundsMax.xy, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(boundsMax.x, boundsMin.y, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		OutputSliceStream.RestartStrip();
	}
}

// Description:
// Generate and output a quad that encloses the flattened bounds of the triangle in XY, with slice bounds in Z.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The triangle stream to which to add the triangle.
// TriangleIndex - The index of the triangle to render.
[maxvertexcount(4)] void GS_RenderBrickGeometry( triangle VS_OUTPUT input[3], inout TriangleStream<GS_SLICE_OUTPUT> OutputSliceStream, uint TriangleIndex : SV_PRIMITIVEID )
{
	uint maxTriCount = TriangleCountBuffer[0];
	if(TriangleIndex < maxTriCount)
	{
		PCapturedTriangle tri = CapturedTriangleBuffer[TriangleIndex];

		GS_SLICE_OUTPUT Out;
		Out.V0 = tri.m_v0;
		Out.V1 = tri.m_v1;
		Out.V2 = tri.m_v2;
	
		uint3 res = VoxelResolution * BrickSize;
		float3 invSize = 1.0f / float3(res);

		// Calculate the bounds for the triangle.
		float3 boundsMin = min(tri.m_v0, min(tri.m_v1, tri.m_v2));
		float3 boundsMax = max(tri.m_v0, max(tri.m_v1, tri.m_v2));	

		// Scale XY up to projected viewport coordinates (-1 to +1)
		boundsMin.xy = boundsMin.xy * 2.0f - 1.0f;
		boundsMax.xy = boundsMax.xy * 2.0f - 1.0f;
			
		// Generate slice bounds - these will be iterated inclusively by the pixel shader.
		int sliceIndex0 = (int)(boundsMin.z * float(res.z));// - 1;
		int sliceIndex1 = (int)(boundsMax.z * float(res.z)) + 1;
	
		// Clamp slice bounds to voxel cells available.
		sliceIndex0 = max(sliceIndex0,0);
		sliceIndex1 = min(sliceIndex1, int(res.z-1));
	
		// Increase size of XY bounds in each direction.
		boundsMin.xy -= invSize.xy * 2.0f;
		boundsMax.xy += invSize.xy * 2.0f;
	
		Out.ZExtents = float2( sliceIndex0, sliceIndex1);
		Out.PrimitiveId = float(TriangleIndex);
		
#ifndef __ORBIS__		
		boundsMin.y = -boundsMin.y;
		boundsMax.y = -boundsMax.y;
#endif
	
		// Emit tri-strip for bounds of triangle.
		Out.Position = float4(boundsMin.x, boundsMax.y, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(boundsMin.xy, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(boundsMax.xy, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(boundsMax.x, boundsMin.y, 0.0f, 1.0f);
		OutputSliceStream.Append( Out );
		
		OutputSliceStream.RestartStrip();
	}
}

uint hash3(float3 v)
{
	return asuint(v.x) ^ asuint(v.y) ^ asuint(v.z);
}

// Description:
// Generates a triangle for the element in the triangle linked lists.
// Calculates the color from a hash of the vertices and provides the grid space positions to allow voxel visualization.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The triangle stream to which to add the triangle.
// TriangleIndex - The index of the triangle to render.
[maxvertexcount(4)] void GS_RenderBrickGeometryDebug(triangle VS_OUTPUT input[3], inout TriangleStream<GS_DEBUG_OUTPUT> OutputSliceStream, uint TriangleIndex : SV_PRIMITIVEID)
{
	uint maxTriCount = TriangleLinkedListCount[0];
	if (TriangleIndex < maxTriCount)
	{
		uint2 listElement = TriangleLinkedListBuffer[TriangleIndex];
		PCapturedTriangle tri = CapturedTriangleBuffer[listElement.x];

		GS_DEBUG_OUTPUT Out;
		uint hash = 0;
		hash ^= hash3(tri.m_v0);
		hash ^= hash3(tri.m_v1);
		hash ^= hash3(tri.m_v2);

		Out.Color = float3(((hash >> 0) & 0xFF) / 255.0f, ((hash >> 8) & 0xFF) / 255.0f, ((hash >> 16) & 0xFF) / 255.0f);

		Out.Position = mul(mul(float4(tri.m_v0, 1.0f), GridToWorldTransform), ViewProjection);
		Out.GridPos = tri.m_v0;
		OutputSliceStream.Append(Out);

		Out.Position = mul(mul(float4(tri.m_v1, 1.0f), GridToWorldTransform), ViewProjection);
		Out.GridPos = tri.m_v1;
		OutputSliceStream.Append(Out);

		Out.Position = mul(mul(float4(tri.m_v2, 1.0f), GridToWorldTransform), ViewProjection);
		Out.GridPos = tri.m_v2;
		OutputSliceStream.Append(Out);

		OutputSliceStream.RestartStrip();
	}
}

// Description:
// Intersect all the 1st-level bricks in the triangle bounds with the triangle, and mark any that intersect the triangle so that a brick can be allocated.
// Arguments:
// In - The input pixel - this relates to a cell on the first level brick map.
// Returns:
// Grey if no brickmap cells have been intersected, or white if at least one cell was intersected.
float4 PS_RenderFilledCells(PS_SLICE_INPUT In) : FRAG_OUTPUT_COLOR0
{
	int slice0 = int(In.ZExtents.x);				// The minimum Z-slice extents (inclusive).
	int slice1 = int(In.ZExtents.y);				// The maixmum Z-slice extents (inclusive).
	
	float rsltOutput = 0.4f;						// Grey if we intersected no cells.

	for(int slice = slice0; slice <= slice1; ++slice)
	{
		// evaluate octree
		uint3 pos = uint3(In.Position.xy, slice);
				
		float3 levelSizeInv = 1.0f / float3(VoxelResolution);
        float3 levelPos = (float3(pos)) * levelSizeInv;
    	
		// If the triangle intersects this brick...
		if(TriBoxOverlap(levelPos + (levelSizeInv * 0.5f), levelSizeInv*0.5f, In.V0,In.V1,In.V2))
		{
			// Generate the cell index.
			uint cellIndex = pos.x + pos.y * VoxelResolution.x + pos.z * VoxelResolution.x * VoxelResolution.y;
								
			RWVoxelDataBuffer[cellIndex] = 1.0f;	// And mark the cell as needing a brick.
			rsltOutput = 1.0f;						// Mark the cell as white if we intersected at least one cell.
		}
	}
	
	return rsltOutput;
}

// Description:
// For all 1st-level bricks that have been tagged as requiring a brick allocated, allocate one and initialize the 64 linked list head pointers.
// Arguments:
// GroupID - The group ID of the compute shader invocation.
// DispatchThreadId - The dispatch thread ID of the compute shader invocation.
// GroupThreadId - The group thread IS of the compute shader invocation.
// GroupIndex - The group index of the compute shader invocation.
[numthreads(4, 4, 4)]
void CS_AllocateBricks(uint3 GroupId : SV_GroupID, 
						uint3 DispatchThreadId : SV_DispatchThreadID, 
						uint3 GroupThreadId : SV_GroupThreadID,
						uint GroupIndex : SV_GroupIndex)
{
	uint3 pos = DispatchThreadId.xyz;

	// Fetch the voxel data buffer that has been marked for all populated 1st-level bricks.
	uint addr = pos.x + pos.y * VoxelResolution.x + pos.z * VoxelResolution.x * VoxelResolution.y;
	float voxelData = VoxelDataBuffer[addr];
	
	uint brickIndex = 0xffffffff;											// "No-brick" index by default.
	if(voxelData > 0.005f)													// If the cell was marked as needing a brick.
	{
		brickIndex = RWBrickMapBuffer.IncrementCounter();					// Allocate a brick index.

		// Initialize all of the head pointers in the allocated brick (4x4x4 = 64).
		for(uint i = 0; i < 64; ++i)
			RWBrickMapBuffer[brickIndex * 64 + i] = 0xffffffff;
	}

	RWBrickIndexTexture[pos] = brickIndex;									// Insert the brick index in the 3D index texture.
}

// Description:
// For all 2nd-level brick intersections with rendered triangles, add the triangle onto the front of the linked list for that cell.
// Arguments:
// In - The input pixel - this relates to a cell on the second level brick map.
// Returns:
// Grey if no brickmap cells have been intersected, or white if at least one cell was intersected.
float4 PS_RenderBricks(PS_SLICE_INPUT In) : FRAG_OUTPUT_COLOR0
{
	int slice0 = int(In.ZExtents.x);
	int slice1 = int(In.ZExtents.y);

	uint3 res = VoxelResolution * BrickSize;
	float3 levelSizeInv = 1.0f / float3(res);
	
	float floatIntBias = 0.2f;
	uint triangleIndex = uint(In.PrimitiveId + floatIntBias);

	float rsltOutput = 0.4f;				// Grey if no cells intersected a triangle.
	
	for(int slice = slice0; slice <= slice1; ++slice)
	{
		// evaluate octree
		uint3 pos = uint3(In.Position.xy, slice);
		uint3 parentPos = pos / BrickSize;
				
		float3 levelPos = (float3(pos)) * levelSizeInv;		
		
    	// determine if triangle actually intersects this cell
		if(TriBoxOverlap(levelPos + (levelSizeInv * 0.5f), levelSizeInv*0.5f, In.V0,In.V1,In.V2))
		{
			uint brickIndex = BrickIndexTexture.Load(int4(parentPos, 0));
			uint3 brickPos = pos & (BrickSize-1);
									
			uint brickCellAddress = brickPos.x + brickPos.y * BrickSize + brickPos.z * BrickSize * BrickSize;
			brickCellAddress += brickIndex * (BrickSize * BrickSize * BrickSize);
			
			// add the triangle onto the head of the linked list.
			uint triListIdx = RWTriangleLinkedListBuffer.IncrementCounter();
			uint prevValue;
			InterlockedExchange(RWBrickMapBuffer[brickCellAddress], triListIdx, prevValue);

			// Populate the list entry. prevValue is the previous head pointer.
			RWTriangleLinkedListBuffer[triListIdx] = uint2(triangleIndex,  prevValue);
			
			rsltOutput = 1.0f;				// White if at least one cell intersected a triangle.
		}
	}
	
	return rsltOutput;
}


// Description:
// Visualizes the triangle from the linked list. The color is based on a hash then darkened to show voxel boundaries.
// Arguments:
// In - The input pixel - this relates to the triangle.
// Returns:
// The hash color of the triangle darkened for odd voxels.
float4 PS_RenderBricksDebug(GS_DEBUG_OUTPUT In) : FRAG_OUTPUT_COLOR0
{
	float3 res = float3(VoxelResolution * BrickSize);
	float3 brick = In.GridPos * res;
	uint dark = (uint(brick.x) ^ uint(brick.y) ^ uint(brick.z)) & 0x1;
	if (dark)
		return float4(In.Color * 0.5f, 1);
	return float4(In.Color, 1);
}

// Description:
// Count triangles in each cell, and gather their indices so that they are contiguous in the brick triangle index buffer.
// Arguments:
// GroupID - The group ID of the compute shader invocation.
// DispatchThreadId - The dispatch thread ID of the compute shader invocation.
// GroupThreadId - The group thread IS of the compute shader invocation.
// GroupIndex - The group index of the compute shader invocation.
[numthreads(64, 1, 1)]
void CS_CountTrianglesPerCell(uint3 GroupId : SV_GroupID, 
						uint3 DispatchThreadId : SV_DispatchThreadID, 
						uint3 GroupThreadId : SV_GroupThreadID,
						uint GroupIndex : SV_GroupIndex)
{
	uint addr = DispatchThreadId.x + BrickOffsetCountBufferBaseIndex;
	uint listIndex = BrickMapBuffer[addr];

	if(listIndex == 0xffffffff)
	{
		// Special case - there are no triangles in this cell.
		RWBrickOffsetCountBuffer[addr] = 0;
	}
	else
	{
		// There are triangles, count them.
		uint triangleCount = 0;
		do
		{
			++triangleCount;
			listIndex = TriangleLinkedListBuffer[listIndex].y;			// Next in the list.
		}
		while(listIndex != 0xffffffff);

		// Allocate space in the brick triangle index buffer for the triangle indices.
		uint offset = 0;
		InterlockedAdd(RWCounterBuffer[0], triangleCount, offset);

		// Store the address and triangle count.
		RWBrickOffsetCountBuffer[addr] = offset | (triangleCount << 22);

		// And copy the triangle indices across.
		triangleCount = 0;
		listIndex = BrickMapBuffer[addr];
		do
		{
			RWBrickTriangleIndexBuffer[offset + triangleCount] = TriangleLinkedListBuffer[listIndex].x;

			++triangleCount;
			listIndex = TriangleLinkedListBuffer[listIndex].y;			// Next in the list.
		}
		while(listIndex != 0xffffffff);

	}
}

// Description:
// Render the captured triangles to the G buffer for rendering to the screen.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The triangle stream to which to add the triangle.
// TriangleIndex - The index of the triangle to render.
[maxvertexcount(4)] void GS_RenderGBufferGeometry( triangle VS_OUTPUT input[3], inout TriangleStream<GS_GBUFFER_OUTPUT> OutputSliceStream, uint TriangleIndex : SV_PRIMITIVEID )
{
	uint maxTriCount = TriangleCountBuffer[0];
	if(TriangleIndex < maxTriCount)
	{
		PCapturedTriangle tri = CapturedTriangleBuffer[TriangleIndex];
	
		GS_GBUFFER_OUTPUT Out;
		Out.PrimitiveId = float(TriangleIndex);															// Triangle index for the G buffer.
	
		Out.Position = mul(mul(float4(tri.m_v0,1.0f), GridToWorldTransform), ViewProjection);			// Target position is view projected position.
		Out.GridPos = tri.m_v0;																			// Vertex grid position for the G buffer
		OutputSliceStream.Append( Out );
		
		Out.Position = mul(mul(float4(tri.m_v1,1.0f), GridToWorldTransform), ViewProjection);			// Target position is view projected position.
		Out.GridPos = tri.m_v1;																 			// Vertex grid position for the G buffer.
		OutputSliceStream.Append( Out );
		
		Out.Position = mul(mul(float4(tri.m_v2,1.0f), GridToWorldTransform), ViewProjection);			// Target position is view projected position.
		Out.GridPos = tri.m_v2;																 			// Vertex grid position for the G buffer.
		OutputSliceStream.Append( Out );
		
		OutputSliceStream.RestartStrip();
	}
}

// Description:
// Render the captured triangles to the G buffer for rendering to the lightmap.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The triangle stream to which to add the triangle.
// TriangleIndex - The index of the triangle to render.
[maxvertexcount(4)] void GS_RenderGBufferLightmapGeometry( triangle VS_OUTPUT input[3], inout TriangleStream<GS_GBUFFER_OUTPUT> OutputSliceStream, uint TriangleIndex : SV_PRIMITIVEID )
{
	uint maxTriCount = TriangleCountBuffer[0];
	if(TriangleIndex < maxTriCount)
	{
		PCapturedTriangle tri = CapturedTriangleBuffer[TriangleIndex];
			
		GS_GBUFFER_OUTPUT Out;
		Out.PrimitiveId = float(TriangleIndex);

		Out.Position = float4(tri.m_uv0 * 2.0f - 1.0f, 0.0f, 1.0f);										// Target position is the lightmap texture position.
		Out.GridPos = tri.m_v0;																			// Vertex grid position for the G buffer.
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(tri.m_uv1 * 2.0f - 1.0f, 0.0f, 1.0f);										// Target position is the lightmap texture position.
		Out.GridPos = tri.m_v1;									   										// Vertex grid position for the G buffer.
		OutputSliceStream.Append( Out );
		
		Out.Position = float4(tri.m_uv2 * 2.0f - 1.0f, 0.0f, 1.0f);										// Target position is the lightmap texture position.
		Out.GridPos = tri.m_v2;									   										// Vertex grid position for the G buffer.
		OutputSliceStream.Append( Out );
		
		OutputSliceStream.RestartStrip();
	}
}

// Description:
// Render to the G-buffer the nearest polygon grid position and its primitive ID (position in the captured triangle buffer).
// Arguments:
// In - The input pixel location to render.
// Returns:
// The output pixel to render to the G buffer.
float4 PS_RenderGBuffer(PS_GBUFFER_INPUT In) : FRAG_OUTPUT_COLOR0
{
	float floatIntBias = 0.2f;
	uint triangleIndex = uint(In.PrimitiveId + floatIntBias);

	return float4(In.GridPos,asfloat(triangleIndex));
	
}

// Description:
// Render the captured triangle buffer to the screen using the generated lightmap.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The triangle stream to which to add the output triangle.
// TriangleIndex - The index of the triangle to render.
[maxvertexcount(4)] void GS_RenderPreviewGeometry( triangle VS_OUTPUT input[3], inout TriangleStream<GS_GBUFFER_OUTPUT> OutputSliceStream, uint TriangleIndex : SV_PRIMITIVEID )
{
	uint maxTriCount = TriangleCountBuffer[0];
	if(TriangleIndex < maxTriCount)
	{
		PCapturedTriangle tri = CapturedTriangleBuffer[TriangleIndex];
	
		GS_GBUFFER_OUTPUT Out;
		Out.PrimitiveId = float(TriangleIndex);
	
		Out.Position = mul(mul(float4(tri.m_v0,1.0f), GridToWorldTransform), ViewProjection);
		Out.GridPos = float3(tri.m_uv0,0);
		OutputSliceStream.Append( Out );
		
		Out.Position = mul(mul(float4(tri.m_v1,1.0f), GridToWorldTransform), ViewProjection);
		Out.GridPos = float3(tri.m_uv1,0);
		OutputSliceStream.Append( Out );
		
		Out.Position = mul(mul(float4(tri.m_v2,1.0f), GridToWorldTransform), ViewProjection);
		Out.GridPos = float3(tri.m_uv2,0);
		OutputSliceStream.Append( Out );
		
		OutputSliceStream.RestartStrip();
	}
}

// Description:
// The pixel shader for rendering the preview geometry with the generated lightmap.
// Arguments:
// In - The interpolated input pixel to be rasterized.
// Returns:
// The color to render to the screen.
float4 PS_RenderPreview(PS_GBUFFER_INPUT In) : FRAG_OUTPUT_COLOR0
{
	float2 uv = In.GridPos.xy;

	float4 textureValue = LightmapTexture.SampleLevel(LinearClampSampler, uv, 0);
	return textureValue;
}

uint3 GetXYZ(uint packedBits, uint bits)
{
	uint mask = (1 << bits) - 1;
	uint3 XYZ;
	XYZ.x = packedBits & mask;
	XYZ.y = (packedBits >> bits) & mask;
	XYZ.z = (packedBits >> (bits * 2)) & mask;
	return XYZ;
}

// Description:
// Render the captured bricks to the screen as wireframe boxes.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The line stream to which to add the output lines.
// BrickIndex - The index of the brick to render.
[maxvertexcount(24)] void GS_RenderBricksDebug(line VS_OUTPUT input[2], inout LineStream<GS_DEBUG_BRICKS_OUTPUT> OutputSliceStream, uint BrickIndex : SV_PRIMITIVEID)
{
	uint3 brickXYZ = GetXYZ(BrickIndex, 6);
	uint brickIndex = BrickIndexTexture[brickXYZ];
	if (brickIndex != 0xFFFFFFFF)
	{
		float4 xOffset = mul(mul(float4(1.0 / 64, 0, 0, 0.0f), GridToWorldTransform), ViewProjection);
		float4 yOffset = mul(mul(float4(0, 1.0 / 64, 0, 0.0f), GridToWorldTransform), ViewProjection);
		float4 zOffset = mul(mul(float4(0, 0, 1.0 / 64, 0.0f), GridToWorldTransform), ViewProjection);
		float4 origin = mul(mul(float4(brickXYZ / 64.0, 1.0f), GridToWorldTransform), ViewProjection);

		GS_DEBUG_BRICKS_OUTPUT Out;
		Out.Color = float3(1, 0, 0);

		// Bottom loop
		Out.Position = origin;
		OutputSliceStream.Append(Out);
		Out.Position += xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position += zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position -= xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position -= zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		// Top loop
		Out.Position = origin + yOffset;
		OutputSliceStream.Append(Out);
		Out.Position += xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position += zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position -= xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position -= zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		// Verticals
		Out.Position = origin;
		OutputSliceStream.Append(Out);
		Out.Position += yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		Out.Position = origin + xOffset;
		OutputSliceStream.Append(Out);
		Out.Position += yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		Out.Position = origin + zOffset;
		OutputSliceStream.Append(Out);
		Out.Position += yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		Out.Position = origin + xOffset + zOffset;
		OutputSliceStream.Append(Out);
		Out.Position += yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();
	}
}

// Description:
// Render the captured cells to the screen as wireframe boxes.
// Arguments:
// input - The input vertices (ignored).
// OutputSliceStream - The line stream to which to add the output lines.
// CellIndex - The index of the cells to render.
[maxvertexcount(24)] void GS_RenderCellsDebug(point VS_OUTPUT input[1], inout LineStream<GS_DEBUG_BRICKS_OUTPUT> OutputSliceStream, uint CellIndex : SV_PRIMITIVEID)
{
	uint BrickIndex = CellIndex >> 6;
	uint3 cellXYZ = GetXYZ(CellIndex, 2);
	uint3 brickXYZ = GetXYZ(BrickIndex, 6);
	uint brickIndex = BrickIndexTexture[brickXYZ];
	if (brickIndex != 0xFFFFFFFF)
	{
		uint brickCellAddress = (CellIndex & 0x3f) + brickIndex * 64;
		uint triangleOffsetCount = BrickOffsetCountBuffer[brickCellAddress];
		uint triangleCount = triangleOffsetCount >> 22;
		if (triangleCount == 0)
			return;

		float4 xOffset = 0.5f * mul(mul(float4(1.0 / 256, 0, 0, 0.0f), GridToWorldTransform), ViewProjection);
		float4 yOffset = 0.5f * mul(mul(float4(0, 1.0 / 256, 0, 0.0f), GridToWorldTransform), ViewProjection);
		float4 zOffset = 0.5f * mul(mul(float4(0, 0, 1.0 / 256, 0.0f), GridToWorldTransform), ViewProjection);
		float4 origin = mul(mul(float4((4 * brickXYZ + cellXYZ) / 256.0, 1.0f), GridToWorldTransform), ViewProjection);
		origin += (xOffset + yOffset + zOffset);

		GS_DEBUG_BRICKS_OUTPUT Out;
#if 1
		// Color based on number of triangles to suggest performance
		Out.Color = float3(1, 0, 1);
		if(triangleCount < 4)
			Out.Color = float3(0, 1, 0);
		else if (triangleCount < 8)
			Out.Color = float3(0, 0, 1);
		else if (triangleCount < 16)
			Out.Color = float3(1, 1, 0);
#else
		// Color based on number of triangles to verify when count changes
		float scale = 0.5f;
		Out.Color = float3(0, 0, 0);
		while (triangleCount)
		{
			if (triangleCount & 0x1)
				Out.Color.x += scale;
			if (triangleCount & 0x2)
				Out.Color.y += scale;
			if (triangleCount & 0x4)
				Out.Color.z += scale;
			triangleCount >>= 3;
			scale *= 0.5f;
		}
#endif

		// Z plane loop
		Out.Position = origin + xOffset;
		OutputSliceStream.Append(Out);
		Out.Position = origin + yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin - xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin - yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin + xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		// X plane loop
		Out.Position = origin + zOffset;
		OutputSliceStream.Append(Out);
		Out.Position = origin + yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin - zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin - yOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin + zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		// Y plane loop
		Out.Position = origin + zOffset;
		OutputSliceStream.Append(Out);
		Out.Position = origin + xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin - zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin - xOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();

		OutputSliceStream.Append(Out);
		Out.Position = origin + zOffset;
		OutputSliceStream.Append(Out);
		OutputSliceStream.RestartStrip();
	}
}

// Description:
// The pixel shader for rendering the preview geometry with a color from the GS.
// Arguments:
// In - The interpolated input pixel to be rasterized.
// Returns:
// The color to render to the screen.
float4 PS_RenderDebugGSOutput(GS_DEBUG_BRICKS_OUTPUT In) : FRAG_OUTPUT_COLOR0
{
	return float4(In.Color,1);
}

#ifndef __ORBIS__

BlendState NoBlend {
  AlphaToCoverageEnable = FALSE;
  BlendEnable[0] = FALSE;
};
DepthStencilState NoDepthState {
  DepthEnable = FALSE;
  DepthWriteMask = 0;
  DepthFunc = Always;
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

// Capture information as to which top level brickmap cells are filled (and require bricks to be allocated).
technique11 RenderFilledCellGeometry
{
    pass p0
    {   
        SetVertexShader( CompileShader( vs_5_0, VS_RenderCapturedGeometry() ) );
        SetGeometryShader( CompileShader( gs_5_0, GS_RenderVoxelGeometry() ) );
        SetPixelShader( CompileShader( ps_5_0, PS_RenderFilledCells() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
    }    
};

// Allocate bricks based on the results of the RenderFilledCellGeometry pass.
technique11 AllocateBricks
{
    pass p0
    {   
        SetComputeShader( CompileShader( cs_5_0, CS_AllocateBricks() ) );
    }    
};

// Render the triangles into the brickmap.
technique11 RenderBrickMapGeometry
{
    pass p0
    {   
        SetVertexShader( CompileShader( vs_5_0, VS_RenderCapturedGeometry() ) );
        SetGeometryShader( CompileShader( gs_5_0, GS_RenderBrickGeometry() ) );
        SetPixelShader( CompileShader( ps_5_0, PS_RenderBricks() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( NoDepthState, 0);
		SetRasterizerState( DefaultRasterState );
    }    
};

// Render the triangles in the linked list as a hashed color visualization showing voxel edges.
technique11 RenderBrickMapGeometryDebug
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_RenderCapturedGeometry()));
		SetGeometryShader(CompileShader(gs_5_0, GS_RenderBrickGeometryDebug()));
		SetPixelShader(CompileShader(ps_5_0, PS_RenderBricksDebug()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(TestDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
};

// Couunt and aggregate triangle indices per brickmap cell so that they are contiguous for subsequent access.
technique11 CountTrianglesPerCell
{
    pass p0
    {   
        SetComputeShader( CompileShader( cs_5_0, CS_CountTrianglesPerCell() ) );
    }    
};

// Render the captured triangles out to the G buffer for a direct screen render.
technique11 RenderTriangleGBuffer
{
    pass p0
    {   
        SetVertexShader( CompileShader( vs_5_0, VS_RenderCapturedGeometry() ) );
        SetGeometryShader( CompileShader( gs_5_0, GS_RenderGBufferGeometry() ) );
        SetPixelShader( CompileShader( ps_5_0, PS_RenderGBuffer() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( TestDepthState, 0);
		SetRasterizerState( DefaultRasterState );
    }    
};

// Render the captured triangles out to a G buffer for a lightmap generation render.
technique11 RenderTriangleLightmapGBuffer
{
    pass p0
    {   
        SetVertexShader( CompileShader( vs_5_0, VS_RenderCapturedGeometry() ) );
        SetGeometryShader( CompileShader( gs_5_0, GS_RenderGBufferLightmapGeometry() ) );
        SetPixelShader( CompileShader( ps_5_0, PS_RenderGBuffer() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( TestDepthState, 0);
		SetRasterizerState( DefaultRasterState );
    }    
};

// Render the geometry out using the generated lightmap.
technique11 RenderPreviewGeometry
{
    pass p0
    {   
        SetVertexShader( CompileShader( vs_5_0, VS_RenderCapturedGeometry() ) );
        SetGeometryShader( CompileShader( gs_5_0, GS_RenderPreviewGeometry() ) );
        SetPixelShader( CompileShader( ps_5_0, PS_RenderPreview() ) );
		
		SetBlendState( NoBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
		SetDepthStencilState( TestDepthState, 0);
		SetRasterizerState( DefaultRasterState );
    }    
};

technique11 RenderBricksDebug
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_RenderCapturedGeometry()));
		SetGeometryShader(CompileShader(gs_5_0, GS_RenderBricksDebug()));
		SetPixelShader(CompileShader(ps_5_0, PS_RenderDebugGSOutput()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(TestDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
};

technique11 RenderCellsDebug
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_RenderCapturedGeometry()));
		SetGeometryShader(CompileShader(gs_5_0, GS_RenderCellsDebug()));
		SetPixelShader(CompileShader(ps_5_0, PS_RenderDebugGSOutput()));

		SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
		SetDepthStencilState(TestDepthState, 0);
		SetRasterizerState(DefaultRasterState);
	}
};

#endif //! __ORBIS__