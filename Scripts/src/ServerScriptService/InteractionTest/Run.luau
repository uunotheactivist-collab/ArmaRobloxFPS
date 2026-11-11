--!strict
-- Focused body-interaction test, server side (Studio only; delete the InteractionTest folders to remove it). It sets
-- the bodies up through BodyState's own hit entry (the same applyHit a ballistic trace reaches) and checks what the
-- server did with the client's requests (StarterPlayerScripts.InteractionTest.Run) through the Studio debug hooks.
--   Run.setup()            fresh REACT1–6, all blood and records cleared, then:
--                            REACT1 ALIVE (untouched) · REACT2 INJURED (right arm) · REACT3 DYING / SHOCK (both legs,
--                            no drain) · REACT4 DYING / CRYING (abdomen, drains) · REACT5 DEAD (head) ·
--                            REACT6 DYING / CHOKE (throat; dies ≈17 s later, as the footage's bot did)
--                          plus BODY3 (R6, debug pose, not physical) down on both legs
--   Run.state(i)           BodyState record, ragdoll status, positions, BodyDraggedBy
--   Run.watch(i, s) / Run.path(i)   sample the body (BodyPresentation's sampler) during a drag
--   Run.trail(i)           the last finished trail of REACTi against the sampled path
--   Run.recent() / Run.status() / Run.orphans() / Run.kill() / Run.reserve(i, on) / Run.blood()

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Run = {}

local function interaction(...: any): any
	return (ServerScriptService.Server.Interaction.BodyInteraction:WaitForChild("InteractionDebug", 5) :: BindableFunction):Invoke(...)
end
local function blood(...: any): any
	return (ServerScriptService.Server.Blood.BloodServer:WaitForChild("BloodDebug", 5) :: BindableFunction):Invoke(...)
end
local function body(...: any): any
	return (ServerScriptService.Server.BodyState:WaitForChild("BodyStateDebug", 5) :: BindableFunction):Invoke(...)
end
local function pres(...: any): any
	return (ServerScriptService.Server.BodyPresentation:WaitForChild("BodyPresentationDebug", 5) :: BindableFunction):Invoke(...)
end

function Run.bot(i: number): Model
	return workspace:WaitForChild("HitReactionTest"):WaitForChild("Bot" .. i):WaitForChild("REACT" .. i) :: Model
end

local function r6(i: number): Model?
	local f = workspace:FindFirstChild("BodyStateTest")
	return f and f:FindFirstChild("BODY" .. i, true) :: Model?
end

local FRONT = Vector3.new(0, 0, -0.5)

function Run.setup(): any
	blood("clear")
	interaction("clear")
	body("clear")
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
	body("hit", Run.bot(2), "RightUpperArm", FRONT)
	body("hit", Run.bot(3), "LeftUpperLeg", FRONT)
	body("hit", Run.bot(3), "RightUpperLeg", FRONT)
	body("hit", Run.bot(4), "LowerTorso", FRONT)
	body("hit", Run.bot(5), "Head", FRONT)
	body("hit", Run.bot(6), "UpperTorso", Vector3.new(0, 0.35, -0.5))
	local b3 = r6(3)
	if b3 then
		body("reset", b3)
		body("hit", b3, "Left Leg", FRONT)
		body("hit", b3, "Right Leg", FRONT)
	end
	task.wait(3.5)
	local out = {}
	for i = 1, 6 do
		local s = body("get", Run.bot(i))
		out["REACT" .. i] = if s then `{s.Phase} {s.Stance} {s.Behaviour or "-"} life {s.Life}` else "ALIVE (no record)"
	end
	if b3 then
		local s = body("get", b3)
		out.BODY3 = s and `{s.Phase} {s.Stance} anchored {(b3:FindFirstChild("HumanoidRootPart") :: BasePart).Anchored}`
	end
	return out
end

function Run.state(i: number): any
	local m = Run.bot(i)
	local st = pres("status", m)
	local upper = m:FindFirstChild("UpperTorso") :: BasePart
	local lower = m:FindFirstChild("LowerTorso") :: BasePart
	local parts, constraints = 0, {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Constraint") or d:IsA("Attachment") then
			local key = d.ClassName .. ":" .. string.gsub(d.Name, "_.*", "")
			constraints[key] = (constraints[key] or 0) + 1
		end
	end
	return {
		Body = body("get", m),
		Ragdoll = st.Ragdoll,
		RootAnchored = st.RootAnchored,
		ClientOwnedParts = st.ClientOwnedParts,
		Upper = upper.Position,
		Lower = lower.Position,
		DraggedBy = m:GetAttribute("BodyDraggedBy"),
		Parts = parts,
		Instances = constraints,
	}
end

function Run.watch(i: number, seconds: number): boolean
	return pres("watch", Run.bot(i), seconds)
end

-- The body's sampled path (UpperTorso x / z, pelvis height, largest part speed) while watched.
function Run.path(i: number): { any }
	local out = {}
	for _, s in pres("samples", Run.bot(i)) do
		table.insert(out, { t = s.t, x = s.torsoX, z = s.torsoZ, y = s.torsoY, pelvisY = s.pelvisY, speed = s.maxSpeed, ragdoll = s.ragdoll })
	end
	return out
end

-- Distance from a point to a polyline (x / z).
local function toPath(p: Vector3, path: { any }): number
	local best = math.huge
	for k = 1, #path - 1 do
		local a = Vector3.new(path[k].x, 0, path[k].z)
		local b = Vector3.new(path[k + 1].x, 0, path[k + 1].z)
		local q = Vector3.new(p.X, 0, p.Z)
		local ab = b - a
		local u = if ab.Magnitude > 1e-6 then math.clamp((q - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		best = math.min(best, (q - (a + ab * u)).Magnitude)
	end
	return best
end

-- The last finished trail of REACTi against the body's sampled path.
function Run.trail(i: number): any
	local name = "REACT" .. i
	local last = nil
	for _, t in interaction("status").Trails.Recent do
		if t.Body == name then
			last = t
		end
	end
	if not last then
		return { Found = false }
	end
	local path = Run.path(i)
	local worst, gaps, prev = 0, {}, nil
	for _, p in last.Points do
		if #path >= 2 then
			worst = math.max(worst, toPath(p, path))
		end
		if prev then
			table.insert(gaps, math.floor(Vector3.new(p.X - prev.X, 0, p.Z - prev.Z).Magnitude * 100 + 0.5) / 100)
		end
		prev = p
	end
	local first, final = last.Points[1], last.Points[#last.Points]
	return {
		Found = true,
		Placed = last.Placed,
		Points = #last.Points,
		Bleeding = last.Bleeding,
		Length = math.floor(Vector3.new(final.X - first.X, 0, final.Z - first.Z).Magnitude * 100 + 0.5) / 100,
		WorstOffPath = math.floor(worst * 100 + 0.5) / 100,
		Spacing = gaps,
	}
end

function Run.recent(): { any }
	return interaction("recent")
end

function Run.status(): any
	return interaction("status")
end

function Run.blood(): any
	local c = blood("counts")
	local folder = workspace:FindFirstChild("BloodMarks")
	local parts, empty = 0, 0
	if folder then
		for _, p in folder:GetChildren() do
			parts += 1
			local frames = 0
			for _, d in p:GetDescendants() do
				if d:IsA("Frame") then
					frames += 1
				end
			end
			if frames == 0 then
				empty += 1
			end
		end
	end
	c.FolderParts = parts
	c.EmptyParts = empty
	return c
end

-- Nothing left over after the drags: no grip / align anywhere, no loop, nobody held, no dragged attribute, walk speed back.
function Run.orphans(): any
	local grips, aligns, attrs = 0, 0, 0
	for _, d in workspace:GetDescendants() do
		if d.Name == "DragGrip" then
			grips += 1
		elseif d.Name == "DragAlign" then
			aligns += 1
		end
		if d:IsA("Model") and d:GetAttribute("BodyDraggedBy") ~= nil then
			attrs += 1
		end
	end
	local st = interaction("status")
	local player = Players:GetPlayers()[1]
	local hum = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return {
		Grips = grips,
		Aligns = aligns,
		DraggedAttributes = attrs,
		Loop = st.Loop,
		Active = #st.Active,
		Held = #st.Held,
		ActiveTrails = #st.Trails.Active,
		WalkSpeed = hum and hum.WalkSpeed,
		pass = grips == 0 and aligns == 0 and attrs == 0 and not st.Loop and #st.Active == 0 and #st.Held == 0
			and #st.Trails.Active == 0 and (hum == nil or hum.WalkSpeed == 16),
	}
end

function Run.kill(): boolean
	local player = Players:GetPlayers()[1]
	local hum = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = 0
		return true
	end
	return false
end

function Run.reserve(i: number, on: boolean): boolean
	return interaction("reserve", Run.bot(i), on)
end

return Run
