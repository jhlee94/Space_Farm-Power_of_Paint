-- Description:
-- PPhysicsCharacterControllerComponent script function called each frame. 
-- Arguments:
-- controller - The PPhysicsCharacterControllerComponent the script is attached to.
function OnUpdate(controller)
	local app = Phyre.PApplication.GetApplicationForScript()

	local forwards = 0.0
	local rotateY = 0.0

	local fire2 = 0.0
	
	local elapsedTime = app:getElapsedTime()
	local rotateScale = elapsedTime * -1.25
	local translateScale = 0.25

	-- Check for reset to start.
	if (app:getInput("RESET2") == 1.0) then
		controller:setStartPosition(controller:getStartPosition())
	end

	-- Check for movement.
	forwards = app:getInput("FORWARD2")
	rotateY = app:getInput("RIGHT2")

	fire2 = app:getInput("FIRE2")
	
	if fire2 ~= 0.0 then
		print(fire2)
		app:firePaint(1)
	
	end

	controller:setRotate(rotateScale * rotateY)
	controller:setForward(translateScale * forwards)
	
	if (app:getInput("JUMP2") == 1.0) then
		controller:jump()
	end	

	-- Update the controller.
	controller:update(elapsedTime)
end

