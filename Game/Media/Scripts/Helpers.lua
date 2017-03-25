-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.

 
require "Trace"

Helpers = {} 

Helpers.PI = 3.14159265

function Helpers.GetMaterials(entity)
	local materials = {}

	local instancesComponent = entity:getComponent(Phyre.PInstancesComponent)
	if instancesComponent == nil then
		return materials
	end
	
	local instancesCount = instancesComponent:getInstanceCount()
	for i = 0, instancesCount - 1 do
		local instance = instancesComponent:getInstance(i)
		if (Phyre.GetTypeOf(instance) == Phyre.PMeshInstance) then
			local materialSet = instance:getMaterialSet()
			local materialsCount = materialSet:getMaterialCount()
			for m = 0, materialsCount - 1 do
				local material = materialSet:getMaterial(m)
				local materialKey = rawptr(material)				
				if materials[materialKey] == nil then
					materials[materialKey] =  material
					
					local assetRef = Phyre.PAssetReference.GetAssetReferenceByAsset(material)
					if assetRef ~= nil then
						local id = assetRef:getID()					
						print("Found material: " .. id :c_str())
					end
					
				end
				
				m = m + 1
			end
		end		
		i = i + 1
	end
	
	return materials

end

function Helpers.RegisterMaterials(name)
	local nc = Phyre.PNameComponent.FindFirstWithName(name)
	if (nc == nil) then		
		--print("Could not find '" ..  instanceType .. "' instance called: '" .. name .. "'.")
		print("Could not find instance called: '" .. name .. "' for material registration.")
		return nil
	end

	local entity = nc:getEntity()	
	if entity == nil then
		--print("Could not find entity for '" ..  instanceType .. "' instance called: '" .. name .. "'.")
		print("Could not find entity for instance called: '" .. name .. "' for material registration.")
		return nil
	end
	
	local materials = Helpers.GetMaterials(entity)
	for materialPtr,material in pairs(materials) do
		Phyre.PSpawner.RegisterMaterialForInstantiation(material)
		print("Registered material: " .. name)
	end

end

-- Description:
--
--
function Helpers.getNameForComponent(component)
	local entity = component:getEntity()
	if entity ~= nil then
		local nameComponent = entity:getComponent(Phyre.PNameComponent)
		return nameComponent.m_name:c_str()
	else
		return ""
	end
end


-- Description:
--
--
function Helpers.getPhysicsInstanceForComponent(component)
	local entity = component:getEntity()
	if entity then
		local instancesComponent = entity:getComponent(Phyre.PInstancesComponent)
		if instancesComponent then
			return instancesComponent:getInstanceOfType(Phyre.PPhysicsRigidBody)
		end
	end
	return nil
end


-- Description:
--
--
function Helpers.getPositionForComponent(component)
	local entity = component:getEntity() 
	local transform = entity:getWorldMatrix()
	return transform.m_matrix[3]
end


-- Description:
--
--
function Helpers.LocateNodeByName(rootNode, nodeName)

	if rootNode:getName():c_str() == nodeName	then
		return rootNode
	end

	local child = rootNode:getFirstChild()
	if child ~= nil then
		local foundNode = Helpers.LocateNodeByName(child, nodeName)
		if foundNode ~= nil then
			return foundNode
		end
	end

	local subling = rootNode:getNextSibling()
	if subling ~= nil then
		local foundNode = Helpers.LocateNodeByName(subling, nodeName)
		if foundNode ~= nil then
			return foundNode
		end
	end

	return nil

end


-- Description:
--
--
function Helpers.findMesh(entity)
	local instancesComponent = entity:getComponent(Phyre.PInstancesComponent)
	local instancesCount = instancesComponent:getInstanceCount()

	for i = 0,instancesCount-1 do
		local instance = instancesComponent:getInstance(i)
		if (Phyre.GetTypeOf(instance) == Phyre.PMeshInstance) then
			return instance
		end
	end
	return nil
end


function Helpers.findInstanceOfType(entity, requestType)
	local instancesComponent = entity:getComponent(Phyre.PInstancesComponent)
	local instancesCount = instancesComponent:getInstanceCount()
	if(instancesCount >0) then
		for i=1,instancesCount do
			local instance = instancesComponent:getInstance(i)
			local instanceType = Phyre.GetTypeOf(instance)
			if(instanceType == requestType) then
				return instance
			end
		end
	end
end

-- Description:
--
--
function Helpers.hideItem(itemEntity)
	local instancesComponent = itemEntity:getComponent(Phyre.PInstancesComponent)
	instancesComponent:getInstance(0):getBounds().m_meshInstance = nil	
	Trace.info(itemEntity," is hidden.")
end


-- Description:
--
--
function Helpers.showItem(itemEntity)
	local instancesComponent = itemEntity:getComponent(Phyre.PInstancesComponent)
	instancesComponent:getInstance(0):getBounds().m_meshInstance = instancesComponent:getInstance(0)		
	Trace.info(itemEntity," is shown.")
end


-- Description
--
--
function Helpers.hideMeshInstance(item)
	local entity = item:getEntity()
	Helpers.hideItem(entity) 
end


-- Description
--
--
function Helpers.showMeshInstance(item)
	local entity = item:getEntity() 
	Helpers.showItem(entity)
end


-- Description:
--
--
function Helpers.findSubstringInComponentName(component, substring)
	local entity = component:getEntity()
	if entity ~= nil then
		local nameComponent = entity:getComponent(Phyre.PNameComponent)
		if nameComponent ~= nil then
			local name = nameComponent.m_name:c_str()
			if name then
				local pos = string.find(name, substring)
				if pos ~= nil then
					return pos
				end
			end
		end
	end
	return -1
end


-- Description:
--
--
function Helpers.componentNameContains(component, substring)
	if component ~= nil and substring ~= nil then
		if Helpers.findSubstringInComponentName(component, substring) >= 1 then
			return true
		end
	end
	return false
end


-- Description:
--
--
function Helpers.componentNameStartsWith(component, string)
	if Helpers.findSubstringInComponentName(component,string) == 1 then
		return true
	else
		return false
	end
end


-- Description:
--
--
function Helpers.getEntityByName(name)
	local component = Phyre.PNameComponent.FindFirstWithName(name)
	if component then 
		return component:getEntity()
	else
		return nil
	end
end

-- Description:
--
--
function Helpers.GetEntityWithName(name)
	local nc = Phyre.PNameComponent.FindFirstWithName(name)
	if (nc == nil) then		
		print("Could not find entity called: '" .. name .. "'.")
		return nil
	end

	local entity = nc:getEntity()	
	if entity == nil then
		print("Could not find entity called: '" .. name .. "'.")
		return nil
	end
	
	return entity

end

-- Description:
--
--
function Helpers.GetInstanceWithName(name, instanceType)
	local entity = Helpers.GetEntityWithName(name)
	if entity == nil then
		--print("Could not find entity for '" ..  instanceType .. "' instance called: '" .. name .. "'.")
		print("Could not find entity for instance called: '" .. name .. "'.")
		return nil
	end

	-- Retrieve the first instance of an entity
	local instancesComponent = entity:getComponent(Phyre.PInstancesComponent)
	local instancesCount = instancesComponent:getInstanceCount()

	if (instancesCount > 0) then
		local instance = instancesComponent:getInstance(0)
		local instanceType = Phyre.GetTypeOf(instance)
		if (instanceType == instanceType) then
			return instance
		end
	end
	
	--print("Could not find '" ..  instanceType .. "' instance called: '" .. name .. "'.")
	print("Could not find instance called: '" .. name .. "'.")
	return nil
	
end

function Helpers.FindChildNodeForParent(parent, child)
	local nameComponent = Phyre.PNameComponent.FindFirstWithName(parent)
	if nameComponent then
		local entity = nameComponent:getEntity()
		local instancesComponent = entity:getComponent(Phyre.PInstancesComponent)
		local rootNode = instancesComponent:getInstanceOfType(Phyre.PNode)
		rootNode = rootNode:getFirstChild()
		local foundNode = Helpers.LocateNodeByName(rootNode, child)
		if foundNode then
			local nodeName = foundNode:getName():c_str()
			print(string.format("Found: %s", nodeName))
			return foundNode
		end
	end
end
