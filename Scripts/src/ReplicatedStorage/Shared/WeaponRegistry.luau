--!strict
-- Looks up weapon definitions by id. Each weapon is one data-only ModuleScript in
-- Shared/Config/Weapons, named by its id (e.g. "M4"). Systems ask the registry instead of
-- requiring weapon modules directly, so adding a weapon never means editing system code.

local WeaponsFolder = script.Parent:WaitForChild("Config"):WaitForChild("Weapons")

local cache: { [string]: any } = {}

local WeaponRegistry = {}

function WeaponRegistry.get(id: string): any
	local cached = cache[id]
	if cached then
		return cached
	end
	local module = WeaponsFolder:FindFirstChild(id)
	assert(module and module:IsA("ModuleScript"), `unknown weapon '{id}'`)
	local definition = require(module) :: any
	cache[id] = definition
	return definition
end

function WeaponRegistry.ids(): { string }
	local ids = {}
	for _, child in WeaponsFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(ids, child.Name)
		end
	end
	table.sort(ids)
	return ids
end

return WeaponRegistry
