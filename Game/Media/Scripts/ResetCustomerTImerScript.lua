function OnAlarm(timer)
	--local pickupEntity = timer:getEntity()
	
	timer.currentTrigger:setEnabled(true)
	local app = Phyre.PApplication.GetApplicationForScript()
	
	local controller = timer:getEntity():getComponentType(Phyre.PQuarryComponent):getEntity():getComponent(Phyre.PPhysicsCharacterControllerComponent)
	if controller then
		app:resetPlayerStatus(controller)
	end

	timer:reset()
end