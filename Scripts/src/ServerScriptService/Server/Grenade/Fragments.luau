--!strict
-- Grenade fragments (server). All of them, at once, at the detonation: Config.Grenade.Fragments.Count (600, the
-- reference's "GRENADE: 600 FRAGMENTS") straight server traces from the detonation point, in directions spread evenly
-- over the whole sphere (a Fibonacci lattice, turned at random per grenade). Each trace is the accepted shared tracer
-- (Server.Ballistics.trace) with the fragment's own values: range, and a penetration budget of 0, so it stops at the
-- first wall or body (penetration is not established). No parts, no flight, nothing from a client.
-- Result: the reference's categories (into bodies / into walls / clear) and the body hits grouped per body part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))
local Ballistics = require(script.Parent.Parent:WaitForChild("Ballistics"))

local Fragments = {}

export type PartHit = { Humanoid: Humanoid, Part: BasePart, Count: number, Position: Vector3, Normal: Vector3?, Traces: { any } }
export type Result = {
	Origin: Vector3,
	Count: number,
	IntoBodies: number,
	IntoWalls: number,
	Clear: number,
	Hits: { PartHit }, -- one entry per body part reached, in the order first reached
	Octants: { number }, -- fragments per direction octant (spread check)
	Mean: Vector3, -- mean direction (≈ 0 for an even spread)
	WallStops: number, -- traces that ended at a surface entry point
	Seconds: number, -- server time spent tracing
}

-- n directions spread evenly over the unit sphere (Fibonacci lattice), turned by a random rotation.
function Fragments.directions(n: number, rng: Random): { Vector3 }
	local golden = math.pi * (3 - math.sqrt(5))
	local turn = CFrame.fromEulerAnglesXYZ(rng:NextNumber(0, 2 * math.pi), rng:NextNumber(0, 2 * math.pi), rng:NextNumber(0, 2 * math.pi))
	local out = table.create(n)
	for i = 0, n - 1 do
		local y = 1 - (i + 0.5) * 2 / n
		local r = math.sqrt(math.max(0, 1 - y * y))
		local a = golden * i
		out[i + 1] = turn:VectorToWorldSpace(Vector3.new(math.cos(a) * r, y, math.sin(a) * r))
	end
	return out
end

function Fragments.trace(origin: Vector3, seed: number, ignore: { Instance }): Result
	local F = Config.Fragments
	local t0 = os.clock()
	local dirs = Fragments.directions(F.Count, Random.new(seed))
	local spec = { Range = F.Range, PenetrationStuds = F.PenetrationStuds }
	local result: Result = {
		Origin = origin,
		Count = #dirs,
		IntoBodies = 0,
		IntoWalls = 0,
		Clear = 0,
		Hits = {},
		Octants = { 0, 0, 0, 0, 0, 0, 0, 0 },
		Mean = Vector3.zero,
		WallStops = 0,
		Seconds = 0,
	}
	local byPart: { [BasePart]: PartHit } = {}
	local sum = Vector3.zero
	for _, d in dirs do
		sum += d
		local o = 1 + (if d.X > 0 then 1 else 0) + (if d.Y > 0 then 2 else 0) + (if d.Z > 0 then 4 else 0)
		result.Octants[o] += 1
		local tr = Ballistics.trace(origin, d, spec, ignore)
		local target = tr.Targets[1]
		if target then
			result.IntoBodies += 1
			local h = byPart[target.Part]
			if not h then
				local enter = nil
				for _, e in tr.Events do
					if e.Kind == "Enter" and e.Part == target.Part then
						enter = e
						break
					end
				end
				h = { Humanoid = target.Humanoid, Part = target.Part, Count = 0, Position = target.Position,
					Normal = enter and enter.Normal, Traces = {} }
				byPart[target.Part] = h
				table.insert(result.Hits, h)
			end
			h.Count += 1
			table.insert(h.Traces, tr)
		elseif tr.StoppedBy then
			result.IntoWalls += 1
			local last = tr.Events[#tr.Events]
			local enterBefore = tr.Events[#tr.Events - 1]
			if last and enterBefore and enterBefore.Kind == "Enter" and (last.Position - enterBefore.Position).Magnitude < 1e-4 then
				result.WallStops += 1
			end
		else
			result.Clear += 1
		end
	end
	result.Mean = sum / math.max(#dirs, 1)
	result.Seconds = os.clock() - t0
	return result
end

return Fragments
