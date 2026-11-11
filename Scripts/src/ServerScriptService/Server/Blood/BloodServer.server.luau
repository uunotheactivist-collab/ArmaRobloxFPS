--!strict
-- Blood state (server): starts a pool under each body that is down. It reads only BodyState's published attributes
-- (BodyStance DOWN with BodyPhase DYING or DEAD) on models with BodyModel, event-driven (no per-frame loop), and
-- never changes them. Stains, drops and splats come from shots (Server.Blood.Impacts).
-- Studio-only test hook: BindableFunction BloodDebug (counts / recent / marks / pools / bodies / clear).

local RunService = game:GetService("RunService")

local Impacts = require(script.Parent:WaitForChild("Impacts"))
local Marks = require(script.Parent:WaitForChild("SurfaceMarks"))
local Pools = require(script.Parent:WaitForChild("Pools"))
local Stains = require(script.Parent:WaitForChild("Stains"))

local bound: { [Model]: { RBXScriptConnection } } = {}

local function check(model: Model)
	if model:GetAttribute("BodyStance") == "DOWN" then
		local phase = model:GetAttribute("BodyPhase")
		if phase == "DYING" or phase == "DEAD" then
			Pools.start(model)
		end
	end
end

local function bind(m: Instance)
	if not m:IsA("Model") or bound[m :: Model] or m:GetAttribute("BodyModel") == nil then
		return
	end
	local model = m :: Model
	bound[model] = {
		model:GetAttributeChangedSignal("BodyStance"):Connect(function()
			check(model)
		end),
		model:GetAttributeChangedSignal("BodyPhase"):Connect(function()
			check(model)
		end),
		model.Destroying:Connect(function()
			for _, c in bound[model] or {} do
				c:Disconnect()
			end
			bound[model] = nil
		end),
	}
	check(model)
end

workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(bind, d)
	end
end)
for _, d in workspace:GetDescendants() do
	bind(d)
end

if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "BloodDebug"
	bf.OnInvoke = function(cmd: string, a: any): any
		if cmd == "counts" then
			local m = Marks.stats()
			local p = Pools.stats()
			local stains = 0
			for model in bound do
				stains += Stains.count(model)
			end
			local patchParts = 0
			local folder = workspace:FindFirstChild("BloodMarks")
			if folder then
				patchParts = #folder:GetChildren()
			end
			return {
				Marks = m.Marks,
				Drops = m.Drops,
				Splats = m.Splats,
				Patches = m.Patches,
				Pools = p.Pools,
				GrowingPools = p.Growing,
				Stains = stains,
				BloodParts = patchParts,
				ClientCalls = Impacts.ClientCalls,
				Shots = #Impacts.Recent,
			}
		elseif cmd == "recent" then
			return Impacts.Recent
		elseif cmd == "marks" then
			return Marks.stats().PatchList
		elseif cmd == "pools" then
			return Pools.stats().List
		elseif cmd == "stains" then
			return if typeof(a) == "Instance" and a:IsA("Model") then Stains.count(a) else 0
		elseif cmd == "clear" then
			Marks.clear()
			Pools.clear()
			table.clear(Impacts.Recent)
			return true
		end
		return nil
	end
	bf.Parent = script
end
