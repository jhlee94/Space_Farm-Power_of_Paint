#pragma once

#include <Phyre.h>
#include <Navigation\PhyreNavigation.h>

#include "Bot.h"
//
// Bot implementation
//
// Description:
// The constructor for the Bot class.
Bot::Bot()
	: m_navigationComponent(NULL)
	, m_navigationTarget(NULL)
	, m_worldMatrix(NULL)
{
}