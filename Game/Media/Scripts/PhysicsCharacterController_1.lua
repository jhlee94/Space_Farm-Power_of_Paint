-- Description:
-- PPhysicsCharacterControllerComponent script function called each frame. 
-- Arguments:
-- controller - The PPhysicsCharacterControllerComponent the script is attached to.
function OnUpdate(controller)
	local app = Phyre.PApplication.GetApplicationForScript()

	local forwards = 0.0
	local rotateY = 0.0
	
	local fire = 0.0
	
	local elapsedTime = app:getElapsedTime()
	local rotateScale = elapsedTime * -1.25
	local translateScale = 0.25

	-- Check for reset to start.
	if (app:getInput("RESET1") == 1.0) then
		controller:setStartPosition(controller:getStartPosition())
	end

	-- Check for movement.
	forwards = app:getInput("FORWARD1")
	rotateY = app:getInput("RIGHT1")
	
	fire = app:getInput("FIRE1")
	
	if fire ~= 0.0 then
	
		app:firePaint(0)
	
	end
	
	controller:setRotate(rotateScale * rotateY)
	controller:setForward(translateScale * forwards)
	
	if (app:getInput("JUMP1") == 1.0) then
		controller:jump()
	end	

	-- Update the controller.
	controller:update(elapsedTime)
end

