/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

#ifndef PHYRE_COMPUTE_TERRAIN_COMPRESS_DXT_H
#define PHYRE_COMPUTE_TERRAIN_COMPRESS_DXT_H

// Description:
// Calculates the lookup index for a given alpha value inside the block.
// Arguments:
// alpha - The alpha value to be encoded.
// minAlpha - The minimum alpha value.
// rcpMaxMinusMinAlpha - The inverse of the difference between the minimum and maximum alpha values.
// Returns:
// The calculated index to be stored inside the grid.
uint CalculateAlphaIndex(in float alpha, in float minAlpha, in float rcpMaxMinusMinAlpha)
{
	// Get closest control point
	const float interp = (alpha - minAlpha) * rcpMaxMinusMinAlpha;

	// Calculate the index
	uint index = uint(7.0f * interp + 0.5f);

	// Remap the index
	index = (0x9CBB9 >> (index * 3)) & 0x7;

	// Return the calculated index
	return index;
}

// Description:
// Calculates the lookup index for a given color value inside the block.
// Arguments:
// color - The color value to be encoded.
// minColor - The minimum color value.
// rcpMaxMinusMinColor - The inverse of the difference between the minimum and the maximum color values.
// Returns:
// The calculated index to be stored inside the grid.
uint CalculateColorIndex(in uint color, in uint minColor, in float rcpMaxMinusMinColor)
{
	// Get closest control point
	const float interp = float(color - minColor) * rcpMaxMinusMinColor;

	// Calculate the index
	uint index = uint(3.0f * interp + 0.5f);

	// Remap the index
	index = (0x2D >> (index * 2)) & 0x3;

	// Return the calculated index
	return index;
}

// Description:
// Converts a single precision floating-point number to a single byte unsigned integer.
// Arguments:
// a - The floating-point number to be converted.
// Returns:
// The integer value.
uint FloatToByte(in float a)
{
	return uint(a * 255.0f + 0.5f) & 0xFF;
}

// Description:
// Packs the input RGB color into a 565 color format.
// Arguments:
// c - The color vector to be packed onto 2 bytes.
// Returns:
// The packed color value.
uint FloatTo565(in float3 c)
{
	return (uint(c.x * 31.0f + 0.5f) << 11) |
		   (uint(c.y * 63.0f + 0.5f) << 5)  |
		   (uint(c.z * 31.0f + 0.5f));
}

// Description:
// Returns the DXT5 compressed 64-bit alpha block for the input texels.
// Arguments:
// block - The block of 4x4 texels, which alpha channel is to be compressed.
// Returns:
// The 64-bit alpha block.
uint2 CompressBlock_Alpha(in float4 block[16])
{
	// Compute min and max alphas
	float minAlpha = min(block[0].w, 0.996f),
		  maxAlpha = minAlpha + 0.004f;
	{
		for(uint i = 1; i < 16; ++i)
		{
			float alpha = block[i].w;
			if(alpha < minAlpha)
				minAlpha = alpha;
			else if(alpha > maxAlpha)
				maxAlpha = alpha;
		}
	}

	// Build up the indices
	uint2 indices = uint2(0, 0);
	{
		const float diffRcp = 1.0f / (maxAlpha - minAlpha);
		{
			for(uint i = 0; i < 6; ++i)
			{
				// Calculate the index
				const uint index = CalculateAlphaIndex(block[i].w, minAlpha, diffRcp);
				// Store the index
				indices.x |= index << (3 * i);
			}
		}
		for(uint i = 6; i < 16; i++)
		{
			// Calculate the index
			const uint index = CalculateAlphaIndex(block[i].w, minAlpha, diffRcp);
			// Store the index
			indices.y |= index << (3 * i - 16);
		}
		// Fixup the indices at the 32-bit boundary
		indices.y |= indices.x >> 16;
		indices.x &= 0xFFFF;
	}

	// Construct the 64-bit alpha block
	return uint2((indices.x << 16) | (FloatToByte(minAlpha) << 8) | FloatToByte(maxAlpha), indices.y);
}

// Description:
// Returns the DXT1 compressed 64-bit color block for the input texels.
// Arguments:
// block - The block of 4x4 texels, which color channels are to be compressed.
// Returns:
// The 64-bit color block.
uint2 CompressBlock_Color(in float4 block[16])
{
	const float3 grid = float3(31.0f, 63.0f, 31.0f),
				 gridRcp = float3(1.0f / 31.0f, 1.0f / 63.0f, 1.0f / 31.0f),
				 half_ = float3(0.5f, 0.5f, 0.5f);

	// Build up our points reference
	uint points[16];
	{
		for(uint i = 0; i < 16; ++i)
		{
			float3 c = block[i].xyz;
			// Align to the color grid
			c = trunc(grid * c + half_) * gridRcp;
			// Pack the color
			points[i] = FloatTo565(c);
		}
	}

	// Compute min and max colors
	uint minColor = points[0],
		 maxColor = minColor;
	{
		for(uint i = 1; i < 16; ++i)
		{
			uint c = points[i];
			if(c < minColor)
				minColor = c;
			else if(c > maxColor)
				maxColor = c;
		}
	}

	// Build up the indices
	uint indices = 0;
	{
		const float diffRcp = 1.0f / float(maxColor - minColor);
		for(uint i = 0; i < 16; ++i)
		{
			// Calculate the index
			const uint index = CalculateColorIndex(points[i], minColor, diffRcp);
			// Store the index
			indices |= index << (i << 1);
		}
	}

	// Construct the 64-bit color block
	return uint2((minColor << 16) | maxColor, indices);
}

#endif //! PHYRE_COMPUTE_TERRAIN_COMPRESS_DXT_H
