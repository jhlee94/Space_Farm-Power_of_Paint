#pragma once

#include <Phyre.h>
#include <Navigation\PhyreNavigation.h>

class Target
{
public:
	Phyre::PEntity                                            m_entity;                // The entity representing the floater.
	Phyre::PNavigation::PNavigationTargetComponent            *m_navigationTarget;    // The target to allow floaters to follow the agent.
	Target() {}
};
