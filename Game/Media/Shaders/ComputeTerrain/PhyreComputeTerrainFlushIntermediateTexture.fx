/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#include "../PhyreShaderPlatform.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Terrain flush intermediate texture.

Texture2D			IntermediateTexture;			// The intermediate texture to be commiting data from.
uint2				IntermediateTextureOffset;		// The description of the page to commit from the intermediate texture.
RWTexture2D<float4>	PhysicalTexture;				// The physical texture to be commiting the data into.
uint2				PhysicalTextureOffset;			// The description of the page to be commiting data into the physical texture.
uint2				MaxCopyCoordinates;				// The maximum coordinates for copying the texture data.

[numthreads(8, 8, 1)]
void TerrainFlushIntermediateTextureCs(uint3 In : SV_DispatchThreadID)
{
	const uint2 xy = min(uint2(In.xy), MaxCopyCoordinates);

	PhysicalTexture[(int2)xy + int2(PhysicalTextureOffset)] = IntermediateTexture[(int2)xy + int2(IntermediateTextureOffset)];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Technique declarations.

#ifndef __ORBIS__

technique11 TerrainFlushIntermediateTexture
<
	string PhyreRenderPass = "FlushIntermediateTexture";
>
{
	pass pass0
	{
		SetComputeShader( CompileShader( cs_5_0, TerrainFlushIntermediateTextureCs() ) );
	}
}

#endif //! __ORBIS__
