/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// You need to declare something like the following for accessing the data:
// StructuredBuffer<uint> HTileData;

#ifdef __ORBIS__

uint getPipeIndexOfTile(uint x, uint y)
{
	uint pipe = 0;
	pipe |= (((x >> 0) ^ (y >> 0) ^ (x >> 1)) & 0x1) << 0;
	pipe |= (((x >> 1) ^ (y >> 1)) & 0x1) << 1;
	pipe |= (((x >> 2) ^ (y >> 2)) & 0x1) << 2;

#ifdef PHYRE_NEO
	pipe |= (((x >> 3) ^ (y >> 2)) & 0x1) << 3;
#endif //! PHYRE_NEO
	return pipe;
}

uint CachelinesWide(uint width)
{
	return (width + 511) / 512;
}

// x = x of tile
// y = y of tile
// width = width of depth buffer containing tile
// Note: Any functions that call this will need to be built aware of the PHYRE_NEO context switch.
uint HTileIndexForTile(uint x, uint y, uint width)
{
	const uint pipe_interleave = 256;

	width = (width + 7) / 8;
	const unsigned cl_size = 512; // 512 DWORDS per PIPE in a CACHELINE
#ifdef PHYRE_NEO
	const unsigned num_pipes = 16;
#else //! PHYRE_NEO
	const unsigned num_pipes = 8;
#endif //! PHYRE_NEO

	const unsigned macro_shift = (16 - num_pipes) >> 3;
	const unsigned cl_width = num_pipes << 3;
	const unsigned cl_height = 64;
	const unsigned cl_x = x / cl_width;
	const unsigned cl_y = y / cl_height;
	const unsigned surf_pitch_cl = (width + cl_width - 1) / cl_width;
	const unsigned cl_offset = ((cl_x + surf_pitch_cl * cl_y) * cl_size);

	const unsigned macro_x = ((x % cl_width)) / 4;
	const unsigned macro_y = ((y % cl_height)) / 4;
	const unsigned macro_pitch = (cl_width) / 4;
	unsigned macro_offset = (macro_y * macro_pitch + macro_x) << macro_shift;

	const uint tile_x = x & 3;
	const uint tile_y = y & 3; 
	macro_offset &= ~3;
	macro_offset |= (((tile_x >> 1) ^ (tile_y >> 0)) & 1) << 0;
	macro_offset |= (((tile_x >> 1)) & 1) << 1;

	const uint tile_number = cl_offset + macro_offset;
	const uint device_address = tile_number * 4;
	const uint pipe = getPipeIndexOfTile(x, y);
	const uint final_address = (device_address % pipe_interleave) + (pipe * pipe_interleave) + (device_address / pipe_interleave) * pipe_interleave * num_pipes;

	return final_address / 4; // convert from bytes to dwords
}

uint MinZOfHtile(uint htile)
{
	return (htile >> 4) & 0x3FFF;
}

uint MaxZOfHtile(uint htile)
{
	return (htile >> 18) & 0x3FFF;
}

float2 HTileToMinMaxZ(uint htile)
{
	return float2(MinZOfHtile(htile), MaxZOfHtile(htile) + 1) / 16384.0;
}

#endif // __ORBIS__
