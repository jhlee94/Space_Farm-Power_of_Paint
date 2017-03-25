#pragma once

// Description:
// The Floater class represents the class used by the floaters to navigate the mesh.
class Floater
{
public:
	Phyre::PEntity											m_entity;				// The entity representing the floater.
	Phyre::PNavigation::PNavigationPathFollowingComponent	*m_navigationComponent;	// The path following component for navigation.
	Vectormath::Aos::Vector3 								m_boundsMin;			// The minimum point of the bounds representing the area in which this floater follows bots.
	Vectormath::Aos::Vector3 								m_boundsSize;			// The size of the area in which this floater follows bots.

	Floater();
	bool containsTarget(const Phyre::PNavigation::PNavigationTargetComponent &target) const;
	bool targetNeedsUpdate() const;
};