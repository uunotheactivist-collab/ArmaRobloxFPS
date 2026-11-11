--!strict
-- Bot perception (server only): which characters a bot may fight, and whether it can see one.
--   valid:   a character with a Humanoid above 0 health, of another team, standing and not DYING / DEAD by the
--            accepted BodyState attributes (BodyPhase / BodyStance) when it is a body; never the bot itself
--   in view: within range (eye to target point) and, for acquiring, inside the field of view about the body's facing
--   visible: a raycast from the bot's eye to a target point (Config.AI.Perception.AimParts in order) reaches it with
--            nothing in between (walls and other bodies block; the bot, its rifle, the target and blood marks don't)
-- Everything is server state: player characters (server positions) and registered models. Every number is a
-- placeholder (Config.AI.Perception): the reference never shows a bot detect anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AI"))
local P = Config.Perception

local Perception = {}
Perception.Stats = { Rays = 0, Looks = 0 }

local registered: { [Model]: boolean } = {}

-- Models with a team (bots and test targets) are fought only once registered; players' characters always count.
function Perception.register(model: Model)
	registered[model] = true
end

function Perception.unregister(model: Model)
	registered[model] = nil
end

function Perception.teamOf(model: Model): string?
	local t = model:GetAttribute(Config.TeamAttribute)
	if type(t) == "string" then
		return t
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		local pt = player:GetAttribute(Config.TeamAttribute)
		return if type(pt) == "string" then pt else Config.PlayerTeam
	end
	return nil
end

-- Able to fight / worth shooting: alive by its Humanoid and, for a body, by BodyState (not DYING / DEAD, standing).
function Perception.alive(model: Model): boolean
	if not model.Parent then
		return false
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then
		return false
	end
	local phase = model:GetAttribute("BodyPhase")
	if phase == "DYING" or phase == "DEAD" then
		return false
	end
	local stance = model:GetAttribute("BodyStance")
	if stance ~= nil and stance ~= "STANDING" then
		return false
	end
	return true
end

function Perception.enemy(self: Model, other: Model): boolean
	if other == self then
		return false
	end
	local a, b = Perception.teamOf(self), Perception.teamOf(other)
	return a ~= nil and b ~= nil and a ~= b
end

-- Every model that could be a target right now (unfiltered by team / sight).
function Perception.candidates(): { Model }
	local out = {}
	for _, player in Players:GetPlayers() do
		local c = player.Character
		if c and c.Parent then
			table.insert(out, c)
		end
	end
	for m in registered do
		if m.Parent then
			table.insert(out, m)
		else
			registered[m] = nil
		end
	end
	return out
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Can a bot with this eye / facing see the target? fov = false skips the field of view (a target already held is
-- tracked while the body turns to it). ignore: the bot's own model and rifle.
-- Returns the visible point and its part, or nil and why not ("range" / "fov" / "blocked" / "no point").
function Perception.look(eye: Vector3, facing: Vector3, target: Model, ignore: { Instance }, fov: boolean): (Vector3?, BasePart?, string?)
	Perception.Stats.Looks += 1
	local reason = "no point"
	local filter = table.clone(ignore)
	table.insert(filter, target)
	local blood = workspace:FindFirstChild("BloodMarks")
	if blood then
		table.insert(filter, blood)
	end
	params.FilterDescendantsInstances = filter
	local cosHalf = math.cos(math.rad(P.FovDeg / 2))
	for _, name in P.AimParts do
		local p = target:FindFirstChild(name)
		if not p or not p:IsA("BasePart") then
			continue
		end
		local d = p.Position - eye
		if d.Magnitude > P.RangeStuds then
			return nil, nil, "range"
		end
		if fov then
			local f, g = flat(facing), flat(d)
			if f.Magnitude > 1e-4 and g.Magnitude > 1e-4 and f.Unit:Dot(g.Unit) < cosHalf then
				return nil, nil, "fov"
			end
		end
		Perception.Stats.Rays += 1
		if not workspace:Raycast(eye, d, params) then
			return p.Position, p, nil
		end
		reason = "blocked"
	end
	return nil, nil, reason
end

return Perception
