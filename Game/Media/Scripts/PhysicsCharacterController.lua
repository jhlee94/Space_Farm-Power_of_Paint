-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.

-- PhyreDefault=OnUpdate
-- Script to provide a simple default implementation of the functionality 
-- required to drive a PPhysicsCharacterControllerComponent.

-- Description:
-- PPhysicsCharacterControllerComponent script function called each frame. 
-- Arguments:
-- controller - The PPhysicsCharacterControllerComponent the script is attached to.
function OnUpdate(controller)
	local app = Phyre.PApplication.GetApplicationForScript()

	local forwards = 0.0
	local rotateY = 0.0

	local elapsedTime = app:getElapsedTime()
	local rotateScale = elapsedTime * -1.25
	local translateScale = 0.5
	
	-- Check for reset to start.
	if (app:getInput("RESET1") == 1.0) then
		controller:setStartPosition(controller:getStartPosition())
	end

	-- Check for movement.
	forwards = app:getInput("FORWARD1");
	rotateY = app:getInput("RIGHT1");

	controller:setRotate(rotateScale * rotateY)
	controller:setForward(translateScale * forwards)
	
	if (app:getInput("JUMP1") == 1.0) then
		controller:jump()
	end	

	-- Update the controller.
	controller:update(elapsedTime)
end


