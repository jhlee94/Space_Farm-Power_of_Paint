require "Helpers"

g_pickupNodeNameTable = {[0] = "Pickup1"}

function OnLevelLoad(component)
	local app = Phyre.PApplication.GetApplicationForScript()
	local copyCube = Phyre.PSpawner.InstantiateHierarchy("D_Pickups","Pickup1")
    if copyCube then		
		local pickupLocator = Phyre.PNameComponent.FindFirstWithName("Locator_Pickup")
        local rigidBodyComponent = Helpers.findInstanceOfType(copyCube, Phyre.PPhysicsRigidBody)
		if rigidBodyComponent then
			rigidBodyComponent:enable()
		end
		
		local meshInstanceComponent = Helpers.findMesh(copyCube)
		if meshInstanceComponent  == nil then 
			print("MeshInstance Not Cloned!")
		end
		
		--local cubeNode = Helpers.findInstanceOfType(copyCube, Phyre.PNode)
		--if cubeNode then
			--local triggerNode = Helpers.LocateNodeByName(cubeNode, "Trigger")
			--local triggerInCluster = Helpers.GetEntityWithName("Trigger")
			--local triggerInClusterNode = Helpers.findInstanceOfType(triggerInCluster, Phyre.PNode)			
			--if triggerNode == triggerInClusterNode then
				--print("Trigger node found")
				--local triggerEntity = triggerNode:getEntity()
				--local triggerNameComponent = Helpers.getNameForComponent(triggerNode)
				--local triggerName = triggerNode:getName():c_str()
				--print(triggerName)
			--end
		--end
		
		if pickupLocator then
			local entity = pickupLocator:getEntity()
			local pickupLocatorTransform = entity:getWorldMatrix()
			local pickupMesh = meshInstanceComponent:getMesh()
			local nodeIdx = pickupMesh:findMatrix("Transform")
			--local curPos = meshInstanceComponent:getCurrentPosMatrices()
			--local po = pickupLocator:getLocalToWorldMatrix()
			--local pickupLocatorPostion = pickupLocatorTransform.m_matrix[3]
			--pickupLocatorTransform:setTranslation(Vector(0, 20, 0))
			--meshInstanceComponent.m_localToWorldMatrix = pickupLocatorTransform
			--meshInstanceComponent:setPoseTransform(nodeIdx, pickupLocatorTransform)
			local locator_matrix = pickupLocatorTransform:getMatrix()
			local locator_pos = locator_matrix[3]
			local pickup_wm = copyCube:getWorldMatrix()
			local newTransform = Matrix()
			newTransform[3] = locator_pos
			copyCube:getWorldMatrix():setMatrix(pickupLocatorTransform)
			--app:setMeshInstanceLocalToWorldMatrix(copyCube, pickupLocatorTransform)
			print("location updated")
		else
			print("Can't find locator")
		end
    else
        print("nil value of instance")
	end
end

function OnUpdate(component)
	local pickupEntity = Phyre.PSpawner.GetInstance("D_Pickups", 0)
	if pickupEntity then
		local pickupLocator = Phyre.PNameComponent.FindFirstWithName("Locator_Pickup")
		
		local meshInstanceComponent = Helpers.GetInstanceWithName(pickupEntity:getComponent(Phyre.PNameComponent).m_name:c_str(), Phyre.PMeshInstance)
		if meshInstanceComponent  == nil then 
			print("MeshInstance Not Cloned!")
		end
		
		if pickupLocator then
			local entity = pickupLocator:getEntity()
			local pickupLocatorTransform = entity:getWorldMatrix()
			--local po = pickupLocator:getLocalToWorldMatrix()
			--local pickupLocatorPostion = pickupLocatorTransform.m_matrix[3]
			--pickupLocatorTransform:setTranslation(Vector(0, 20, 0))
			--meshInstanceComponent.m_localToWorldMatrix = pickupLocatorTransform
			--meshInstanceComponent:setPoseTransform(nodeIdx, pickupLocatorTransform)
			--pickupEntity:getWorldMatrix():getMatrix():setTranslation(pickupLocatorTransform:getMatrix()[3])
		else
			print("Can't find locator")
		end
	end
end

