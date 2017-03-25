-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.

-- Script to provide a simple default implementation of the functionality 
-- required to drive a PTriggerReceiverComponent.

require "Helpers"
-- Description:
-- Trigger box entry script function called when the a PQuarryComponent has entered a PTrigger.
-- Arguments:
-- data - The PTriggerReceiverTypeCallbackData containing state about the trigger. This contains the following fields:
--		  m_triggerReceiverComponent is the trigger receiver component (PTriggerReceiverComponent) that is being notified of the trigger entry.
--		  m_trigger is the trigger (PTrigger) that has been entered by the quarry.
--		  m_quarryComponent is the quarry (PQuarryComponent) that has entered the trigger.
--		  m_entryCount is the entry count against the PTriggerReceiverComponent after this callback has occurred.  Eg, this will be 1 for the first entry notification.
function OnEnter(data)
	local trc = data.m_triggerReceiverComponent			-- The trigger receiver component being notified.
	local trigger = data.m_trigger						-- The trigger that was entered.
	local quarryComponent = data.m_quarryComponent		-- The quarry that entered the trigger.
	local entryCount = data.m_entryCount				-- The number of times this receiver has been notified of entries (1 for first entry).

	local app = Phyre.PApplication.GetApplicationForScript()
	--app:onPickupEnter(trc:getEntity())
	local controller = quarryComponent:getEntity():getComponent(Phyre.PPhysicsCharacterControllerComponent)
	if controller then
		app:pickupBoostJump(controller)
		local pickupComponent = trc:getEntity():getComponent(Phyre.PickupComponent)
		pickupComponent.m_controller0 = controller
	end
	trigger:setEnabled(false)
	--Helpers.hideItem(trc:getEntity())
	--print(quarryComponent:getEntity()
	--print("Entered Trigger Volume")
end

-- Description:
-- Trigger box exit script function called when the a PQuarryComponent has left a PTrigger.
-- Arguments:
-- data - The PTriggerReceiverTypeCallbackData containing state about the trigger. This contains the following fields:
--		  m_triggerReceiverComponent is the trigger receiver component (PTriggerReceiverComponent) that is being notified of the trigger exit.
--		  m_trigger is the trigger (PTrigger) that has been left by the quarry.
--		  m_quarryComponent is the quarry (PQuarryComponent) that has left the trigger.
--		  m_entryCount is the entry count against the PTriggerReceiverComponent after this callback has occurred.  Eg, this will be 0 for the last exit notification.
function OnExit(data)
	local trc = data.m_triggerReceiverComponent			-- The trigger receiver component being notified.
	local trigger = data.m_trigger						-- The trigger that was left.
	local quarryComponent = data.m_quarryComponent		-- The quarry that left the trigger.
	local entryCount = data.m_entryCount				-- The number of times this receiver has been notified of entries (0 for last exit).

	local timerComponent = trc:getEntity():getComponent(Phyre.PTimerComponent)
	if timerComponent then
		timerComponent:reset()
	end
	--Helpers.showItem(trc:getEntity())
	print("Exited Trigger Volume")
end
