-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.

-- PhyreDefault=OnAlarm
-- Script to provide a simple default implementation of the functionality 
-- required to drive a PTimerComponent.
require "Helpers"
-- Description:
-- Alarm script function called when the PTimerComponent timer reaches zero.
-- Arguments:
-- timer - The PTimerComponent that has reached zero.
function OnAlarm(timer)
	local pickupEntity = timer:getEntity()
	local app = Phyre.PApplication.GetApplicationForScript();
	timer.m_property0:setEnabled(true)
	local controller = pickupEntity:getComponent(Phyre.PickupComponent).m_controller0
	if controller then
		app:resetBoost(controller)
	end
	--Helpers.showItem(pickupEntity)
	-- We can do something here that we set an alarm for earlier.
	timer:reset()
end
