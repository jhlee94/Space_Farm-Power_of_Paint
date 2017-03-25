-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.

-- Script to provide a simple default implementation of the functionality 
-- required to drive a PCameraControllerComponent.

-- Description:
-- Updates the camera transformation based on the target object.
-- Arguments:
-- app: The game application.
-- controller: The PCameraControllerComponent the script is attached to.
local function updateFromTarget(app, controller)
	if (nil ~= controller.m_followTarget) then
		local elapsedTime = app:getElapsedTime()
		local matrix = controller.m_followTarget:getMatrix()
		local targetPosition = matrix[3]
		local targetDirection = matrix[2]

		controller.m_followPhysics:update(targetPosition, targetDirection, elapsedTime)
		controller:setPosition(controller.m_followPhysics:getCameraPosition())
		controller:lookAt(controller.m_followPhysics:getCameraTarget())
		
		-- The PCameraControllerComponent also provides a helper method to perform a similar simple update.
		-- controller:updateFromFollowTarget(elapsedTime)
	end
end

-- Description:
-- PCameraControllerComponent script function called each frame. 
-- Arguments:
-- controller - The PCameraControllerComponent the script is attached to.
function OnUpdate(controller)
	local app = Phyre.PApplication.GetApplicationForScript()
	local elapsedTime = app:getElapsedTime()

	-- This base functionality is also provided by PApplication::defaultAnimate().
	-- If you unbind this script the core functionality will provide the same functionality with improved performance.

	if (nil ~= controller.m_followTarget) then
		-- Follow target processing.
		updateFromTarget(app, controller)
	else
		-- Freecam processing - call back to the app's updateCamera method.
		app:updateCamera(controller.m_controller, elapsedTime, 1.0, 1.0)
	end
end
