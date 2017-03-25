#pragma once

#include <Phyre.h>
// A class to represent the viewport configuration settings, such as position and dimensions.
class PViewportConfig
{
public:
	// Description:
	// Configures the viewport.
	// Arguments:
	// xOffset - The offset to the left X value of viewport.
	// yOffset - The offset to the lower Y value of viewport.
	// width - The width of the viewport.
	// height - The height of the viewport.
	void configure(Phyre::PInt32 xOffset, Phyre::PInt32 yOffset, Phyre::PUInt32 width, Phyre::PUInt32 height)
	{
		m_xOffset = xOffset;
		m_yOffset = yOffset;
		m_width = width;
		m_height = height;
	}

	Phyre::PInt32 m_xOffset;	// Offset to the left X value of viewport.
	Phyre::PInt32 m_yOffset;	// Offset to the lower Y value of viewport.
	Phyre::PUInt32 m_width;		// Width of the viewport.
	Phyre::PUInt32 m_height;	// Height of the viewport.
};