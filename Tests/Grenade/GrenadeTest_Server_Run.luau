--!strict
-- Focused grenade test, server side (Studio only; delete the GrenadeTest folders to remove it). It reads what the
-- server did with the client's throws (StarterPlayerScripts.GrenadeTest.Run) through the Studio debug hooks.
--   Run.reset()            clear the grenade / blood / body records, refill the player
--   Run.bodies()           fresh REACT1–6 from their templates (standing, ALIVE)
--   Run.kill(i)            REACTi down and DEAD through BodyState's own hit entry (head)
--   Run.left(n)            the player's grenades left = n
--   Run.detonations()      every detonation: fuse, release vs head, launch speed, categories, timing, hits
--   Run.path(id)           bounces (floor / wall), largest step between 30 Hz samples, server ownership throughout
--   Run.body(i)            BodyState record + ragdoll status + stains of REACTi
--   Run.blood()            blood counts and the last grenade blood batch
--   Run.status() / Run.rejections() / Run.parts()

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Run = {}

local function grenade(...: any): any
	return (ServerScriptService.Server.Grenade.GrenadeServer:WaitForChild("GrenadeDebug", 5) :: BindableFunction):Invoke(...)
end
local function blood(...: any): any
	return (ServerScriptService.Server.Blood.BloodServer:WaitForChild("BloodDebug", 5) :: BindableFunction):Invoke(...)
end
local function bodyHook(...: any): any
	return (ServerScriptService.Server.BodyState:WaitForChild("BodyStateDebug", 5) :: BindableFunction):Invoke(...)
end
local function pres(...: any): any
	return (ServerScriptService.Server.BodyPresentation:WaitForChild("BodyPresentationDebug", 5) :: BindableFunction):Invoke(...)
end

local function player(): Player
	return Players:GetPlayers()[1]
end

function Run.bot(i: number): Model
	return workspace:WaitForChild("HitReactionTest"):WaitForChild("Bot" .. i):WaitForChild("REACT" .. i) :: Model
end

function Run.reset(): any
	grenade("clear")
	blood("clear")
	bodyHook("clear")
	return grenade("refill", player())
end

function Run.left(n: number): any
	return grenade("left", player(), n)
end

function Run.bodies(): boolean
	local templates = ServerStorage:WaitForChild("HitReactionTemplates")
	for i = 1, 6 do
		local f = workspace.HitReactionTest:WaitForChild("Bot" .. i)
		local old = f:FindFirstChild("REACT" .. i)
		if old then
			old:Destroy()
		end
		templates:WaitForChild("REACT" .. i):Clone().Parent = f
	end
	task.wait(0.3)
	return true
end

function Run.kill(i: number): any
	bodyHook("hit", Run.bot(i), "Head", Vector3.new(0, 0, -0.5))
	task.wait(2.5)
	return bodyHook("get", Run.bot(i))
end

local function r2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

function Run.detonations(): { any }
	local out = {}
	for _, r in grenade("recent") do
		if r.Kind == "Detonation" then
			table.insert(out, {
				Id = r.Id,
				Fuse = math.floor(r.Fuse * 10000 + 0.5) / 10000,
				ReleaseFromHead = r2((r.Origin - r.HeadAt).Magnitude),
				LaunchSpeed = r2(r.Velocity.Magnitude),
				At = r.Position,
				Summary = `{r.Fragments} FRAGMENTS / {r.IntoBodies} INTO BODIES   {r.IntoWalls} INTO WALLS   {r.Clear} CLEAR`,
				Fragments = r.Fragments,
				IntoBodies = r.IntoBodies,
				IntoWalls = r.IntoWalls,
				Clear = r.Clear,
				WallStops = r.WallStops,
				Octants = r.Octants,
				MeanLength = math.floor(r.Mean.Magnitude * 100000 + 0.5) / 100000,
				TraceMs = r2(r.TraceMs),
				TotalMs = r2(r.TotalMs),
				Hits = r.Hits,
				BloodTraces = r.BloodTraces,
				PathSamples = #r.Path,
			})
		end
	end
	return out
end

function Run.rejections(): { string }
	local out = {}
	for _, r in grenade("recent") do
		if r.Kind == "Rejected" then
			table.insert(out, `{r.Action}: {r.Reason}`)
		end
	end
	return out
end

-- Bounces from the 30 Hz path: a floor bounce = falling then rising; a wall bounce = the horizontal velocity turning
-- by more than 90°. Also the largest step between samples (no teleport) and server ownership in every sample.
function Run.path(id: number): any
	for _, r in grenade("recent") do
		if r.Kind == "Detonation" and r.Id == id then
			local floor, wall, maxStep, owned = 0, 0, 0, true
			local p = r.Path
			for k = 2, #p do
				local a, b = p[k - 1], p[k]
				if a.v.Y < -1 and b.v.Y > 0.5 then
					floor += 1
				end
				local ha, hb = Vector3.new(a.v.X, 0, a.v.Z), Vector3.new(b.v.X, 0, b.v.Z)
				if ha.Magnitude > 2 and hb.Magnitude > 2 and ha.Unit:Dot(hb.Unit) < 0 then
					wall += 1
				end
				maxStep = math.max(maxStep, (b.p - a.p).Magnitude)
				owned = owned and b.serverOwned
			end
			local first, last = p[1], p[#p]
			return {
				FloorBounces = floor,
				WallBounces = wall,
				MaxStep = r2(maxStep),
				ServerOwnedThroughout = owned,
				Start = first and first.p,
				End = last and last.p,
				Detonated = r.Position,
				Samples = #p,
				Travel = if first and last then r2((last.p - first.p).Magnitude) else 0,
			}
		end
	end
	return { Found = false }
end

function Run.body(i: number): any
	local m = Run.bot(i)
	local st = pres("status", m)
	local stains = 0
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceGui") and string.sub(d.Name, 1, 10) == "BloodStain" then
			for _, f in d:GetChildren() do
				if f:IsA("Frame") then
					stains += 1
				end
			end
		end
	end
	return { State = bodyHook("get", m), Ragdoll = st.Ragdoll ~= nil, Motors = st.Ragdoll and st.Ragdoll.MotorsEnabled,
		Sockets = st.Ragdoll and st.Ragdoll.Sockets, RootAnchored = st.RootAnchored, ClientOwned = st.ClientOwnedParts, Stains = stains }
end

function Run.blood(): any
	local c = blood("counts")
	local last = nil
	for _, s in blood("recent") do
		if s.Weapon == "Grenade" then
			last = s
		end
	end
	local body, bleed = 0, 0
	if last then
		for _, e in last.Events do
			if e.t == "body" then
				body += 1
				if e.bleed then
					bleed += 1
				end
			end
		end
	end
	return { Counts = c, GrenadeBatches = (function()
		local n = 0
		for _, s in blood("recent") do
			if s.Weapon == "Grenade" then
				n += 1
			end
		end
		return n
	end)(), LastBatchBodyEvents = body, LastBatchBleeding = bleed, LastBatchStains = last and last.Stains, LastBatchMarks = last and #last.Placed }
end

function Run.status(): any
	return grenade("status")
end

-- Parts in the world outside characters and the test ranges' own parts: the grenade slice must leave none behind.
function Run.parts(): any
	local n, grenades = 0, 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	local f = workspace:FindFirstChild("Grenades")
	if f then
		grenades = #f:GetDescendants()
	end
	return { BaseParts = n, GrenadesFolder = grenades }
end

return Run
