/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "..\..\PhyreShaderPlatform.h"
#include <PhyreComputeParticleShared.h>													// This header file is to be found in $(SCE_PHYRE)/Include/Rendering.

StructuredBuffer<ParticleStateBufferInfoStruct>	particleSystemState;				// The particle system's state for the update (population, capacity, time step, etc).
RWByteAddressBuffer drawIndirectArgs;												// The particle system's draw indirect arguments.

[numthreads(1, 1, 1)]
void CS_DrawIndirectParamUpdate()
{
	// Non instanced, non indexed.  drawIndirectArgs contains:
	//
	// uint32_t m_vertexCountPerInstance;	How many vertices to draw for each instance?
	// uint32_t m_instanceCount;			How many instances to draw?
	// uint32_t m_startVertexLocation;		Currently unsupported; set it to 0.
	// uint32_t m_startInstanceLocation;	Currently unsupported; set it to 0.

	drawIndirectArgs.Store4(0, int4(particleSystemState[0].m_population * 6,		// Trilist - 6 vertices per particle.
									1,												// 1 instance.
									0,
									0));
}

[numthreads(1, 1, 1)]
void CS_DrawIndirectParamUpdateIndexed()
{
	// Non instanced, indexed.  drawIndirectArgs contains:
	//
	// uint32_t m_indexCountPerInstance;	How many indices to draw for each instance?
	// uint32_t m_instanceCount;			How many instances to draw?
	// uint32_t m_startIndexLocation;		An offset into the index buffer where drawing should begin.
	// uint32_t m_baseVertexLocation;		Currently unsupported; set it to 0.
	// uint32_t m_startInstanceLocation;	Currently unsupported; set it to 0.

	drawIndirectArgs.Store4(0, int4(particleSystemState[0].m_population * 6,		// Trilist - 6 vertices per particle.
									1,												// 1 instance.
									0,
									0));
	drawIndirectArgs.Store(16, 0);
}

[numthreads(1, 1, 1)]
void CS_DrawIndirectParamUpdateInstanced()
{
	// Non instanced, indexed.  drawIndirectArgs contains:
	//
	// uint32_t m_vertexCountPerInstance;	How many vertices to draw for each instance?
	// uint32_t m_instanceCount;			How many instances to draw?
	// uint32_t m_startVertexLocation;		Currently unsupported; set it to 0.
	// uint32_t m_startInstanceLocation;	Currently unsupported; set it to 0.

//	drawIndirectArgs[0] was setup on structured buffer allocation to the vertex count of the instanced mesh.
	drawIndirectArgs.Store3(4, int3(particleSystemState[0].m_population,			// Instanced - 1 vertex per instance.
									0,
									0));
}

[numthreads(1, 1, 1)]
void CS_DrawIndirectParamUpdateInstancedIndexed()
{
	// Instanced, indexed.  drawIndirectArgs contains:
	//
	// uint32_t m_indexCountPerInstance;	How many indices to draw for each instance?
	// uint32_t m_instanceCount;			How many instances to draw?
	// uint32_t m_startIndexLocation;		An offset into the index buffer where drawing should begin.
	// uint32_t m_baseVertexLocation;		Currently unsupported; set it to 0.
	// uint32_t m_startInstanceLocation;	Currently unsupported; set it to 0.

//	drawIndirectArgs[0] was setup on structured buffer allocation to the index count of the instanced mesh.
	drawIndirectArgs.Store4(4, int4(particleSystemState[0].m_population,			// Instanced - 1 vertex per instance.
									0,
									0,
									0));
}

#ifndef __ORBIS__

technique11 DrawIndirectParamUpdate
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DrawIndirectParamUpdate() ) );
	}
};

technique11 DrawIndirectParamUpdateIndexed
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DrawIndirectParamUpdateIndexed() ) );
	}
};

technique11 DrawIndirectParamUpdateInstanced
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DrawIndirectParamUpdateInstanced() ) );
	}
};

technique11 DrawIndirectParamUpdateInstancedIndexed
{
	pass p0
	{
		SetComputeShader( CompileShader( cs_5_0, CS_DrawIndirectParamUpdateInstancedIndexed() ) );
	}
};

#endif //! __ORBIS__
