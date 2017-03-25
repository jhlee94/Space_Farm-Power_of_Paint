require "Helpers"
function OnAlarm(timer)
	local pickupEntity = timer:getEntity()
	
	local app = Phyre.PApplication.GetApplicationForScript()
	
	local character = Helpers.GetEntityWithName("Character_1")
	local controller = character:getComponent(Phyre.PPhysicsCharacterControllerComponent)
	if controller then
		app:resetStatus(controller)
	end
	-- We can do something here that we set an alarm for earlier.
	timer:reset()
end