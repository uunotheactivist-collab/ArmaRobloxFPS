--!strict
-- Shared, server-authoritative bullet path for every production weapon (minimum ballistic slice).
--   muzzle -> trajectory -> surface hit -> penetration decision -> exit -> continued trajectory -> target hit
-- Called only by Server.WeaponServer, after it has validated the shot. Data: Shared.Config.Ballistics (surface
-- classes) and the weapon's config (range, penetration budget). Nothing here is weapon-specific.
--
-- Method: instant segment tracing with workspace:Raycast. The reference shows no flight time and no drop over its
-- distances (ReferenceAnalysis/Ballistics/Ballistics_Analysis.md B10, B11). No parts are created per bullet.
--   1. Cast from the current point along the shot for the remaining range.
--   2. At a surface, classify it (Penetrable / NonPenetrable / Target). A Target records a hit on its Humanoid
--      (once per character per shot).
--   3. NonPenetrable: the bullet stops at the entry point.
--   4. Otherwise find the exit point by casting back from MaxThicknessProbe studs beyond the entry, against that part
--      only. thickness = |exit - entry|, cost = thickness x CostPerStud. If the remaining budget covers it, the
--      bullet exits and continues in a straight line from just past the exit; if not (or the part is thicker than
--      the probe), it stops inside.
-- Not modelled (not established by the reference): deflection, ricochet, drop, drag, velocity loss, damage falloff.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ballistics"))

local Ballistics = {}

export type Event = {
	Kind: string, -- "Enter" | "Exit" | "Stop" | "End"
	Position: Vector3,
	Normal: Vector3?, -- Enter / Exit: the raycast's own surface normal there (read by the blood / impact presentation)
	Part: BasePart?,
	Surface: string?,
	Thickness: number?,
	Cost: number?,
	Budget: number, -- penetration budget left after this event
	Reason: string?, -- Stop: "NonPenetrable" | "Budget" | "TooThick" | "MaxSurfaces"
}
export type TargetHit = { Humanoid: Humanoid, Part: BasePart, Position: Vector3, Order: number }
export type Result = {
	Origin: Vector3,
	Direction: Vector3,
	Segments: { { From: Vector3, To: Vector3, Inside: boolean } },
	Events: { Event },
	Targets: { TargetHit },
	StoppedBy: BasePart?,
	EndPosition: Vector3,
	Distance: number,
	Budget: number,
}

local function findHumanoid(part: Instance): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Surface class of a part: its own attribute, else its model's, else Target for characters, else the default.
function Ballistics.classify(part: BasePart): (string, Humanoid?)
	local humanoid = findHumanoid(part)
	local class = part:GetAttribute(Config.Attribute)
	if class == nil then
		local model = part:FindFirstAncestorOfClass("Model")
		class = model and model:GetAttribute(Config.Attribute)
	end
	if typeof(class) == "string" and Config.Surfaces[class] then
		return class, humanoid
	end
	return if humanoid then Config.HumanoidDefault else Config.Default, humanoid
end

-- weapon: { Range: number, PenetrationStuds: number }. ignore: instances the bullet passes (the shooter).
function Ballistics.trace(origin: Vector3, direction: Vector3, weapon: { Range: number, PenetrationStuds: number },
	ignore: { Instance }): Result
	local dir = direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local budget = weapon.PenetrationStuds
	local result: Result = {
		Origin = origin,
		Direction = dir,
		Segments = {},
		Events = {},
		Targets = {},
		StoppedBy = nil,
		EndPosition = origin,
		Distance = 0,
		Budget = budget,
	}
	local hitHumanoids: { [Humanoid]: boolean } = {}
	local pos = origin
	local travelled = 0
	local entered = 0

	local function stop(at: Vector3, part: BasePart?, surface: string?, reason: string)
		table.insert(result.Events, { Kind = "Stop", Position = at, Part = part, Surface = surface, Budget = budget, Reason = reason })
		result.StoppedBy = part
		result.EndPosition = at
	end

	while true do
		local remaining = weapon.Range - travelled
		if remaining <= 0 then
			table.insert(result.Events, { Kind = "End", Position = pos, Budget = budget })
			result.EndPosition = pos
			break
		end
		local hit = workspace:Raycast(pos, dir * remaining, params)
		if not hit then
			local finish = pos + dir * remaining
			table.insert(result.Segments, { From = pos, To = finish, Inside = false })
			table.insert(result.Events, { Kind = "End", Position = finish, Budget = budget })
			travelled += remaining
			result.EndPosition = finish
			break
		end
		local part = hit.Instance :: BasePart
		table.insert(result.Segments, { From = pos, To = hit.Position, Inside = false })
		travelled += (hit.Position - pos).Magnitude
		entered += 1
		local surface, humanoid = Ballistics.classify(part)
		local spec = Config.Surfaces[surface]
		table.insert(result.Events, { Kind = "Enter", Position = hit.Position, Normal = hit.Normal, Part = part, Surface = surface, Budget = budget })
		if spec.Hit and humanoid and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = true
			table.insert(result.Targets, { Humanoid = humanoid, Part = part, Position = hit.Position, Order = #result.Targets + 1 })
		end
		if spec.Stops then
			stop(hit.Position, part, surface, "NonPenetrable")
			break
		end
		if entered >= Config.MaxSurfaces then
			stop(hit.Position, part, surface, "MaxSurfaces")
			break
		end
		-- Exit point: cast back towards the entry from beyond it, against this part only.
		local only = RaycastParams.new()
		only.FilterType = Enum.RaycastFilterType.Include
		only.FilterDescendantsInstances = { part }
		local probe = Config.MaxThicknessProbe
		local back = workspace:Raycast(hit.Position + dir * probe, -dir * probe, only)
		if not back then
			stop(hit.Position, part, surface, "TooThick")
			break
		end
		local thickness = (back.Position - hit.Position).Magnitude
		local cost = thickness * spec.CostPerStud
		if cost > budget then
			stop(hit.Position, part, surface, "Budget")
			break
		end
		budget -= cost
		table.insert(result.Segments, { From = hit.Position, To = back.Position, Inside = true })
		table.insert(result.Events, {
			Kind = "Exit",
			Position = back.Position,
			Normal = back.Normal,
			Part = part,
			Surface = surface,
			Thickness = thickness,
			Cost = cost,
			Budget = budget,
		})
		travelled += thickness + Config.ExitOffset
		pos = back.Position + dir * Config.ExitOffset
	end
	result.Distance = travelled
	result.Budget = budget
	return result
end

-- Studio only: the most recent results (with who fired what), for the focused tests. Never read by gameplay.
-- Tests run in another script context with their own copy of this module, so the running server's copy also
-- answers through a BindableFunction child "RecentResults" (Invoke() -> list, Invoke("clear") -> 0).
Ballistics.Recent = {} :: { any }
function Ballistics.record(entry: any)
	if not RunService:IsStudio() then
		return
	end
	table.insert(Ballistics.Recent, entry)
	while #Ballistics.Recent > Config.RecentResults do
		table.remove(Ballistics.Recent, 1)
	end
end
if RunService:IsStudio() and RunService:IsServer() and RunService:IsRunning() and not script:FindFirstChild("RecentResults") then
	local bf = Instance.new("BindableFunction")
	bf.Name = "RecentResults"
	bf.OnInvoke = function(cmd: string?): any
		if cmd == "clear" then
			table.clear(Ballistics.Recent)
			return 0
		end
		return Ballistics.Recent
	end
	bf.Parent = script
end

return Ballistics
