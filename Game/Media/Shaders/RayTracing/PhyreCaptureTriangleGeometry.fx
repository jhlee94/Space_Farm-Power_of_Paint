/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"
#include "../PhyreDefaultShaderSharedCodeD3D.h"

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Global shader parameters.

// Always capture UVs.
#define USE_UVS

// Vertex data buffers
ByteAddressBuffer ObjectVertexPositionBuffer;
ByteAddressBuffer ObjectIndexBuffer;
#ifdef USE_UVS
	ByteAddressBuffer ObjectVertexTexCoord2Buffer;		// TexCoord2 to match the PhyreDefaultLitShader's lightmap input in the case of multiple UVs.
#endif //USE_UVS

RWStructuredBuffer <PCapturedTriangle> RWOutputCapturedTriangleBuffer;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Compute shaders

[numthreads(64, 1, 1)]
void CS_CaptureTriangleGeometry(uint3 GroupId : SV_GroupID, 
						uint3 DispatchThreadId : SV_DispatchThreadID, 
						uint3 GroupThreadId : SV_GroupThreadID,
						uint GroupIndex : SV_GroupIndex)
{
	// We can't capture skinned geometry atm.
#ifndef SKINNING_ENABLED
	uint triangleIndex = DispatchThreadId.x;

#ifdef INDICES_16BIT
	uint3 indices;

	// 16 bit indices
	uint indexByteLocation = triangleIndex * 3 * 2;
	uint2 indices16;
	
	if((indexByteLocation & 2) != 0)
	{
		indices16 = ObjectIndexBuffer.Load2(indexByteLocation & ~2);
		indices = uint3( indices16.x >> 16, indices16.y, indices16.y >> 16 ) & 0xffff;
	}
	else
	{
		indices16 = ObjectIndexBuffer.Load2(indexByteLocation);
		indices = uint3( indices16.x, indices16.x >> 16, indices16.y ) & 0xffff;
	}
#else // INDICES_16BIT
	uint3 indices = ObjectIndexBuffer.Load3(triangleIndex * 4 * 3);
#endif // INDICES_16BIT

	// If not degenerate...
	if(indices.x != indices.y && indices.x != indices.z && indices.y != indices.z)
	{
		float3 v0 = asfloat(ObjectVertexPositionBuffer.Load3(indices.x * 4 * 3));
		float3 v1 = asfloat(ObjectVertexPositionBuffer.Load3(indices.y * 4 * 3));
		float3 v2 = asfloat(ObjectVertexPositionBuffer.Load3(indices.z * 4 * 3));

		v0 = mul(float4(v0,1.0f), WorldView).xyz;
		v1 = mul(float4(v1,1.0f), WorldView).xyz;
		v2 = mul(float4(v2,1.0f), WorldView).xyz;

		float3 normal = normalize( cross( v1 - v0, v2 - v0) );
		
		uint idx = RWOutputCapturedTriangleBuffer.IncrementCounter();

		PCapturedTriangle tri;
		tri.m_v0 = v0;
		tri.m_v1 = v1;
		tri.m_v2 = v2;
		tri.m_normal0 = indices.x;
		tri.m_normal1 = indices.y;
		tri.m_normal2 = indices.z;
#ifdef USE_UVS
		tri.m_uv0 = asfloat(ObjectVertexTexCoord2Buffer.Load2(indices.x * 4 * 2));
		tri.m_uv1 = asfloat(ObjectVertexTexCoord2Buffer.Load2(indices.y * 4 * 2));
		tri.m_uv2 = asfloat(ObjectVertexTexCoord2Buffer.Load2(indices.z * 4 * 2));
#else // USE_UVS
		tri.m_uv0 = 0;
		tri.m_uv1 = 0;
		tri.m_uv2 = 0;
#endif // USE_UVS

		RWOutputCapturedTriangleBuffer[idx] = tri;
	}
#endif //! SKINNING_ENABLED
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Techniques.

#ifndef __ORBIS__

// Capture triangle geometry from the mesh into a structured buffer.
technique11 CaptureTriangleGeometry
<
string IgnoreContextSwitches[] = { "NUM_LIGHTS", "LOD_BLEND", "INSTANCING_ENABLED", "LOW_RES_PARTICLES" };
>
{
    pass p0
    {   
        SetComputeShader( CompileShader( cs_5_0, CS_CaptureTriangleGeometry() ) );
    }    
}

#endif //! __ORBIS__
