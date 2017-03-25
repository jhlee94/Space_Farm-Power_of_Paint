-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.

--PhyrePersistentContext
-- Script to provide a simple default implementation of the functionality 
-- required to drive a PCameraControllerComponent.

g_lastCameraDirection = {}
g_cameraMode = {}

-- Description:
-- Updates the camera transformation based on the target object.
-- Arguments:
-- app: The game application.
-- controller: The PCameraControllerComponent the script is attached to.
local function updateFollow(app, controller)
	if (nil ~= controller.m_followTarget) then
		local elapsedTime = app:getElapsedTime()
		local matrix = controller.m_followTarget:getMatrix()
		local targetDirection = matrix[2]
		
		local characterPosition = controller.m_characterController:getCurrentPosition()
		
		controller.m_followPhysics:setTargetDistance(8.0)		
		controller.m_followPhysics:setTargetHeight(3.0 - characterPosition.y)
		controller.m_followPhysics:update(characterPosition, targetDirection, elapsedTime)
		controller:setPosition(controller.m_followPhysics:getCameraPosition())
		controller:lookAt(controller.m_followPhysics:getCameraTarget())
		
		g_lastCameraDirection = controller.m_followPhysics:getCameraTarget() - controller.m_followPhysics:getCameraPosition();
	end
end

-- Description:
-- Updates the camera transformation based on the target object.
-- Arguments:
-- app: The game application.
-- controller: The PCameraControllerComponent the script is attached to.
local function updateFollowFixed(app, controller)
	if (nil ~= controller.m_followTarget) then
		local elapsedTime = app:getElapsedTime()
		local matrix = controller.m_followTarget:getMatrix()
		local targetPosition = matrix[3]

		local characterPosition = controller.m_characterController:getCurrentPosition()
		controller.m_followPhysics:setTargetDistance(5.0)		
		controller.m_followPhysics:setTargetHeight(5.0 - characterPosition.y)
		controller.m_followPhysics:update(targetPosition, g_lastCameraDirection, elapsedTime)
		controller:setPosition(controller.m_followPhysics:getCameraPosition())
		controller:lookAt(controller.m_followPhysics:getCameraTarget())
	end
end

-- Description:
-- Switches to the next camera type.
local function nextCameraMode(controller)
	g_cameraMode = g_cameraMode + 1
	
	if (g_cameraMode >= 3) then
		g_cameraMode = 0
	end
	
	if (g_cameraMode == 0) then		-- Manual.
		controller.m_characterController:suspendScript();
	elseif (g_cameraMode == 1) then		-- Follow.
		controller.m_characterController:resumeScript();
	elseif (g_cameraMode == 2) then		-- Follow at fixed distance.
		controller.m_characterController:resumeScript();
	end
end 

-- Description:
-- PCameraControllerComponent script function called on play. 
-- Arguments:
-- controller - The PCameraControllerComponent the script is attached to.
function OnLoad(controller)
	local app = Phyre.PApplication.GetApplicationForScript()

	local translation = controller:getEntity():getWorldMatrix():getMatrix()[3]
	
	g_cameraMode = 1
	
	if (app:getPlatformId() == "GLES" or app:getPlatformId() == "AGL2" or app:getPlatformId() == "IOS") then
		g_cameraMode = 0
	end
	
	g_lastCameraDirection = Vector(0,0,1,0)
	controller:setPosition(translation)
	controller.m_followPhysics:setCameraPosition(translation)
end

-- Description:
-- PCameraControllerComponent script function called each frame. 
-- Arguments:
-- controller - The PCameraControllerComponent the script is attached to.
function OnUpdate(controller)
	local app = Phyre.PApplication.GetApplicationForScript()

	local forwards = app:getInputToggled("SWITCH_CAMERA2")

	if (forwards == true) then
		nextCameraMode(controller)
	end
	
	g_lastCameraChange = forwards;
	
	if (g_cameraMode == 0) then
		app:updateCamera(controller.m_controller, app:getElapsedTime(), 1.0, 1.0)
	elseif (g_cameraMode == 1) then
		updateFollow(app, controller)
	elseif (g_cameraMode == 2) then
		updateFollowFixed(app, controller)
	end
end

