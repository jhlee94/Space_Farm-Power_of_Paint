#pragma once

#include <Phyre.h>
#include <Navigation\PhyreNavigation.h>
using namespace Phyre;
using namespace PNavigation;
using namespace Vectormath::Aos;

#include "Floater.h"


// Description:
// The constructor for the Floater class.
Floater::Floater()
	: m_navigationComponent(NULL)
{
}

// Description:
// Checks if the area patrolled by this floater contains the specified target.
// Arguments:
// target : The target to check.
// Return Value List:
// true : The area patrolled by this floater contains the specified target.
// false : The area patrolled by this floater does not contain the specified target.
bool Floater::containsTarget(const PNavigationTargetComponent &target) const
{
	Vector3 targetPosition = target.getPosition();
	Vector3 targetPositionRelative = targetPosition - m_boundsMin;
	PFloatInVec x = targetPositionRelative.getX();
	PFloatInVec z = targetPositionRelative.getZ();
	return (x > 0.0f && z > 0.0f && x < m_boundsSize.getX() && z < m_boundsSize.getZ());
}

// Description:
// Checks if the current target for this floater is valid.
// Return Value List:
// true : The current target for this floater needs to be updated.
// false : The current target is valid.
bool Floater::targetNeedsUpdate() const
{
	const PNavigationTargetComponent *currentTarget = m_navigationComponent->getTarget();
	if (!currentTarget)
		return true;
	return !containsTarget(*currentTarget);
}