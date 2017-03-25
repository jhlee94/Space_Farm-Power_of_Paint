/* SIE CONFIDENTIAL
PhyreEngine(TM) Package 3.18.0.0
* Copyright (C) 2016 Sony Interactive Entertainment Inc.
* All Rights Reserved.
*/

// A set of 32 bit pairs representing 8x8 bitmaps

static uint2 PhyrePixelChar0 = uint2(0x42422418, 0x1824);
static uint2 PhyrePixelChar1 = uint2( 0x8080808, 0x1c08);
static uint2 PhyrePixelChar2 = uint2(0x1804423c, 0x7e20);
static uint2 PhyrePixelChar3 = uint2(0x1804423c, 0x3c42);
static uint2 PhyrePixelChar4 = uint2(0x48281808, 0x87c);
static uint2 PhyrePixelChar5 = uint2( 0x27c407e, 0x3c42);
static uint2 PhyrePixelChar6 = uint2(0x427c403c, 0x3c42);
static uint2 PhyrePixelChar7 = uint2(0x1008047e, 0x4020);
static uint2 PhyrePixelChar8 = uint2(0x423c423c, 0x3c42);
static uint2 PhyrePixelChar9 = uint2(0x3e42423c, 0x3c02);

// Extracts bit b from n.
float ExtractBit(uint n, uint b)
{
	return ((n >> b) & 0x1) ? 1.0f : 0.0f;
}

// Returns the pixel in the specified bit packed 8x8 character.
float BitMaskForPixel(uint2 chr, uint2 pixel)
{
#ifdef __ORBIS__
	uint bit = (7 - pixel.x) + (7 - pixel.y) * 8;
#else // __ORBIS__
	uint bit = (7 - pixel.x) + pixel.y * 8;
#endif // __ORBIS__
	return bit < 32 ? ExtractBit(chr.x, bit) : ExtractBit(chr.y, bit - 32);
}

float GetPixelMaskForDigit(uint index, uint2 pixel)
{
	switch (index)
	{
	case 0: return BitMaskForPixel(PhyrePixelChar0, pixel);
	case 1: return BitMaskForPixel(PhyrePixelChar1, pixel);
	case 2: return BitMaskForPixel(PhyrePixelChar2, pixel);
	case 3: return BitMaskForPixel(PhyrePixelChar3, pixel);
	case 4: return BitMaskForPixel(PhyrePixelChar4, pixel);
	case 5: return BitMaskForPixel(PhyrePixelChar5, pixel);
	case 6: return BitMaskForPixel(PhyrePixelChar6, pixel);
	case 7: return BitMaskForPixel(PhyrePixelChar7, pixel);
	case 8: return BitMaskForPixel(PhyrePixelChar8, pixel);
	case 9: return BitMaskForPixel(PhyrePixelChar9, pixel);
	}
}