/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Terrain render.

float4				BlockPosition;								// The position and scale of the rendered block in space.
float				BlockSize;									// The canonical size of a rendered block.
uint4				BlockClip;									// The amount of UV clipping to be applied to the block.
float4				BlockColor;									// The color to be used to render the block with.
uint				BlockAdjacencyMask;							// The adjacency mask for collapsing the edges.
uint				BlockMismatchMask;							// The amount of detail mismatch with the render block.
float3				CameraPosition;								// The camera position in the terrain local space.
float				DepthBias;									// The depth bias for near/far material switching.
float				MipLevelBias;								// The factor for biasing the mip resolution with the distance.
float				MipLevelFactor;								// The factor for decreasing the mip resolution with the distance.
uint				HeightmapMipLevel;							// The mip level for estimating the heightmap position.
uint4				HeightmapPosition;							// The position of the rendered block inside the heightmap.
float				NearToFarMipBias;							// The amount of mip biasing between the near and far materials.
float				MinMipLevel;								// The minimum mip level for estimating the texture blending.
uint				MipLevelDelta;								// The delta between the minimum and the maximum mip levels.
float				NearMaterialDistanceThreshold;				// The distance threshold for the direct splatting.
float				NearMaterialUpsamplingFactor;				// The upsampling factor for the near material.
Texture2D			MeshPRTextureSampler;						// The PRT sampler for the mesh vertex texture.
float4				MeshPRTextureSamplerVirtualToPhysical;		// The sampler virtual to physical translation values.
float3				MeshPRTextureSamplerPhysicalDesc;			// The sampler physical properties description.
Texture2D			MaskPRTextureSampler;						// The PRT sampler for the mask texture.
float4				MaskPRTextureSamplerVirtualToPhysical;		// The sampler virtual to physical translation values.
Texture2D			ProcPRTextureSampler;						// The PRT sampler for the procedural virtual texture.
float4				ProcPRTextureSamplerVirtualToPhysical[4];	// The sampler virtual to physical translation values.
float2				ProcPRTextureSamplerPhysicalDesc;			// The sampler physical properties description.
Texture2D			ProcTextureSampler;							// The PRT sampler for the secondary texture cache.
Texture2DArray		PaletteTextureArray0;						// The first texture array from the terrain palette.
Texture2DArray		PaletteTextureArray1;						// The second texture array from the terrain palette.
float3				VirtualCoordinates;							// The virtual coordinates for the page top-left corner.
float2				VirtualDimensions;							// The dimensions for the procedural virtual texture.
float2				VirtualTileCounts;							// The counts for tiling the procedural virtual texture.

struct TerrainRenderVsOutput
{
	float4	Position			: SV_POSITION;
	float4	HeightmapPosition	: TEXCOORD0;
	float2	Uv					: TEXCOORD1;
#ifdef TEXTURING_ENABLED
	float2	Uv1					: TEXCOORD2;
	float2	Uv2					: TEXCOORD3;
	float2	Uv3					: TEXCOORD4;
	float	MipLevel			: TEXCOORD5;
#endif //! TEXTURING_ENABLED
	float4	WorldPositionDepth	: TEXCOORD6;
	float4	LocalPosition		: TEXCOORD7;

#ifdef VELOCITY_ENABLED
	VelocityBufferVertexInfo VelocityData;
#endif //! VELOCITY_ENABLED
};


// Description:
// Applies the height scaling factor to the height information that was sampled from the elevation map.
// Arguments:
// height - The height sample from the elevation map.
// Returns:
// The height value to be used for positioning the vertex.
float EvaluateHeight(in float height)
{
	return height * 255.0f;
}

// Description:
// Evaluates the vertex for the amount of LOD mismatch inside the current block and between the surrounding blocks.
// Arguments:
// vertex - The vertex to be evaluated.
// Returns:
// The fixed up vertex.
uint2 EvaluateVertex(in uint2 vertex)
{
	// Fix up LOD mismatch between virtual LOD and physical LOD
	vertex &= BlockMismatchMask;

	// Perform the vertex collapsing for each of the four edges
	[flatten] if(vertex.y == 0)					// north edge
		vertex.x &= (BlockAdjacencyMask >> 24) & 0xFF;
	[flatten] if(vertex.x == ((uint)BlockSize))	// east edge
		vertex.y &= (BlockAdjacencyMask >> 16) & 0xFF;
	[flatten] if(vertex.x == 0)					// west edge
		vertex.y &= (BlockAdjacencyMask >> 8) & 0xFF;
	[flatten] if(vertex.y == ((uint)BlockSize))	// south edge
		vertex.x &= BlockAdjacencyMask & 0xFF;

	return vertex;
}

TerrainRenderVsOutput TerrainRenderVs(uint In : SV_VertexID)
{
	TerrainRenderVsOutput Out;

	// Extract the vertex position from the index
	const uint2 vertex = clamp(uint2(In & 0xFF, (In >> 8) & 0xFF), BlockClip.xy, BlockClip.zw);
	const float2 uv = float2(EvaluateVertex(vertex));

	// Calculate the UVs for the various textures
	const float2 uv1 = uv * MeshPRTextureSamplerVirtualToPhysical.zw + MeshPRTextureSamplerVirtualToPhysical.xy;
#ifdef TEXTURING_ENABLED
	const float2 uv2 = (VirtualCoordinates.xy + float2(uint2(uv) << uint(VirtualCoordinates.z)) * NearMaterialUpsamplingFactor) * VirtualTileCounts.x;
	const float2 uv3 = uv * MaskPRTextureSamplerVirtualToPhysical.zw + MaskPRTextureSamplerVirtualToPhysical.xy;
#endif //! TEXTURING_ENABLED

	// Calculate the position in the world
	const float height = MeshPRTextureSampler.Load(int3(int2(uv1), 0)).x;
	const float2 blockPosition = ((uv * BlockPosition.zw) / BlockSize) + BlockPosition.xy;
	const float4 position = float4(blockPosition.x, EvaluateHeight(height), blockPosition.y, 1.0f);

	// Calculate the mip level for this vertex
#ifdef TEXTURING_ENABLED
	const float depth = distance(float3(CameraPosition.xz, max(CameraPosition.y, 255.0f)), float3(position.xz, 255.0f));
	const float mipLevel = log2(max(depth - MipLevelBias, 0.0f) * MipLevelFactor + 1.0f);
#endif //! TEXTURING_ENABLED

	// Populate the output structure
	Out.Position = mul(position, WorldViewProjection);
	Out.HeightmapPosition = float4(((float2)(HeightmapPosition.xy + (vertex << HeightmapMipLevel))) / ((float2)HeightmapPosition.zw), height, 1.0f);
	Out.Uv = (1.0f + 2.0f * uv1) / (2.0f * MeshPRTextureSamplerPhysicalDesc.xy);
#ifdef TEXTURING_ENABLED
	Out.Uv1 = uv;
	Out.Uv2 = uv2 / VirtualDimensions;
	Out.Uv3 = uv3;
	Out.MipLevel = max(mipLevel, MinMipLevel);
#endif //! TEXTURING_ENABLED
	Out.WorldPositionDepth = float4(mul(position, World).xyz, -mul(position, WorldView).z);
	Out.LocalPosition = position;

#ifdef VELOCITY_ENABLED
	Out.VelocityData.PositionCurrent = Out.Position;
	Out.VelocityData.PositionPrev = mul(position, WorldViewProjectionPrev);
#endif //! VELOCITY_ENABLED	

	return Out;
}
