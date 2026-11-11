--!strict
-- M4 model fidelity test, client side (Studio playtest only; delete the M4ModelFidelityTest folder to remove it).
-- Checks the M4's visual asset (Shared.Assets.Weapons.M4ViewmodelData, "mesh" recipes from the Blender FBX) in the
-- running game through WeaponController's Studio-only debug hook. Gameplay numbers stay with the accepted suites
-- (M4FiringTest, M4ReloadTest, M4HudTest); this module checks that the new model is built, placed, held, animated
-- and cleaned up correctly. Each function returns its measurements and a pass flag.
--   Run.model()      the M4 viewmodel's parts against the data: names, MeshParts built from the mesh recipes, sizes
--                    (rebuilt independently and compared), materials / colours, triangle totals. Runs with the
--                    viewmodel fill (Client.FirstPerson.ViewmodelFill) switched off and restores it after: in shade
--                    the fill raises the dark parts' Color (presentation only), which the colour check would read
--   Run.fit()        first person at the hip and in ADS: key points on screen against the verified reference framing
--                    (hip front post 0.065 screen heights below centre; ADS reticle centred, hood top 0.116 above)
--   Run.hands()      the left hand on the handguard grip in hip, ADS-in and ADS (hand end vs HandGrip)
--   Run.fire()       a burst: shots counted by the server, recoil moves the viewmodel, the muzzle point on the mesh
--   Run.reloads()    the four reloads: clip length, the magazine / charging-handle parts follow their bones, nothing
--                    detaches, no extra parts
--   Run.switching()  M4 → AK → M4 (and the blaster): one viewmodel at a time, no duplicate parts
--   Run.respawn(s)   "before" (records the parts) / "after" (once respawned: rebuilt once, no duplicates)
--   Run.muzzle()     the Muzzle point (flash / tracer origin) sits at the front of the modelled muzzle device + cap
--   Run.perf()       client build time of the whole viewmodel from the data, frame time at the hip and in ADS

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local hook = client:WaitForChild("WeaponController"):WaitForChild("ProductionWeaponDebug") :: BindableFunction
local Weapons = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("Weapons")
local ProceduralMesh = require(ReplicatedStorage.Shared.Viewmodel.ProceduralMesh)

local Run = {}

local function w(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function r3(x: number?): number?
	return if x then math.round(x * 1000) / 1000 else nil
end

local function data(): any
	return require(Weapons:WaitForChild("M4ViewmodelData")) :: any
end

local function equip(id: string)
	player:SetAttribute("EquippedWeapon", id)
	frames(0.5)
end

local function viewmodel(name: string): Model?
	return workspace.CurrentCamera:FindFirstChild(name) :: Model?
end

local function countViewmodels(): (number, { string })
	local n, names = 0, {}
	for _, c in workspace.CurrentCamera:GetChildren() do
		if string.sub(c.Name, -9) == "Viewmodel" then
			n += 1
			table.insert(names, c.Name)
		end
	end
	return n, names
end

-- every M4 weapon model anywhere (a leak would show up here)
local function m4Models(): number
	local n = 0
	for _, root in { workspace, player:FindFirstChildOfClass("PlayerGui") :: Instance } do
		for _, d in root:GetDescendants() do
			if d:IsA("Model") and d.Name == "M4Viewmodel" then
				n += 1
			end
		end
	end
	return n
end

local function modelCheck(): any
	equip("M4")
	local d = data()
	local vm = viewmodel("M4Viewmodel")
	local out: any = { parts = {}, viewmodel = vm ~= nil }
	if not vm then
		out.pass = false
		return out
	end
	local ok = true
	local tris = 0
	for _, spec in d.Parts do
		local p = vm:FindFirstChild(spec.Name) :: BasePart?
		local row: any = { exists = p ~= nil }
		if p and spec.Kind ~= "Block" then
			local mp = p :: MeshPart
			row.meshPart = mp:IsA("MeshPart")
			row.recipeOps = {}
			for _, r in spec.Recipes do
				table.insert(row.recipeOps, r.op)
			end
			-- rebuild the part independently from the same data: same size (no stretching, nothing lost)
			local ref = ProceduralMesh.buildPart(spec.Recipes, d.PartOrigins[spec.Bone])
			row.sizeErr = r3((ref.Size - mp.Size).Magnitude)
			ref:Destroy()
			local mat = d.Materials[spec.Material]
			row.color = mp.Color == Color3.fromRGB(mat.Color[1], mat.Color[2], mat.Color[3])
			row.material = mp.Material.Name == mat.Material
			row.triangles = spec.Triangles
			tris += spec.Triangles or 0
			ok = ok and row.meshPart and (row.sizeErr or 1) < 0.001 and row.color and row.material
		elseif p then
			row.block = true
		else
			ok = false
		end
		out.parts[spec.Name] = row
	end
	out.partCount = #vm:GetChildren()
	out.specCount = #d.Parts
	out.triangles = tris
	out.usesMesh = (function()
		for _, spec in d.Parts do
			for _, r in spec.Recipes or {} do
				if r.op == "mesh" then
					return true
				end
			end
		end
		return false
	end)()
	out.pass = ok and out.partCount == out.specCount and out.usesMesh
	return out
end

-- the viewmodel fill's LocalScript (fill v2); nil when it is not installed
local function fillScript(): Instance?
	local fp = client:FindFirstChild("FirstPerson")
	return if fp then fp:FindFirstChild("ViewmodelFill") else nil
end

function Run.model(): any
	-- fill v2 lifts the dark parts' Color in shade; the colour check compares Color with the model data, so the fill is
	-- switched off for the check (it restores the original colours on its next frame; equip waits 0.5 s) and restored
	local fill = fillScript()
	local was = if fill then fill:GetAttribute("Enabled") else nil
	if fill then
		fill:SetAttribute("Enabled", false)
	end
	local ok, out = pcall(modelCheck)
	if fill then
		fill:SetAttribute("Enabled", was)
	end
	if not ok then
		error(out, 0)
	end
	out.fillSwitchedOff = fill ~= nil
	return out
end

-- screen position of a weapon point (fractions of the viewport; y down)
local function screen(cf: CFrame, p: Vector3): Vector2
	local cam = workspace.CurrentCamera
	local v = cam:WorldToViewportPoint(cf * p)
	local vp = cam.ViewportSize
	return Vector2.new(v.X / vp.X, v.Y / vp.Y)
end

local function partTop(part: BasePart): number
	-- the highest corner of the part's box on screen (fraction of height, y down)
	local cam = workspace.CurrentCamera
	local best = math.huge
	local h = part.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local v = cam:WorldToViewportPoint(part.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
				best = math.min(best, v.Y / cam.ViewportSize.Y)
			end
		end
	end
	return best
end

function Run.fit(): any
	equip("M4")
	w("aim", false)
	frames(0.6)
	local d = data()
	local vm = viewmodel("M4Viewmodel") :: Model
	local pts = d.Points
	local function P(name: string): Vector3
		return Vector3.new(pts[name][1], pts[name][2], pts[name][3])
	end
	-- weapon bone frame: the debug log records it per frame
	w("record", true)
	frames(0.3)
	local hipLog = w("record", false).log
	local hipW = hipLog[#hipLog].weapon :: CFrame
	local hip = { frontPost = screen(hipW, P("FrontPostTip")), muzzle = screen(hipW, P("Muzzle")),
		sightGlass = screen(hipW, P("SightGlass")) }
	w("aim", true)
	frames(0.8)
	w("record", true)
	frames(0.3)
	local adsLog = w("record", false).log
	local adsW = adsLog[#adsLog].weapon :: CFrame
	local optic = vm:FindFirstChild("Weapon_Optic") :: BasePart
	local ads = { sightGlass = screen(adsW, P("SightGlass")), frontPost = screen(adsW, P("FrontPostTip")),
		hoodTop = optic and partTop(optic), fov = workspace.CurrentCamera.FieldOfView }
	w("aim", false)
	frames(0.5)
	local out = {
		hipFrontPostBelowCentre = r3(hip.frontPost.Y - 0.5),
		hipMuzzle = { r3(hip.muzzle.X), r3(hip.muzzle.Y) },
		adsSightGlass = { r3(ads.sightGlass.X), r3(ads.sightGlass.Y) },
		adsFrontPost = { r3(ads.frontPost.X), r3(ads.frontPost.Y) },
		adsHoodTopAboveCentre = r3(0.5 - (ads.hoodTop or 0.5)),
		adsFov = r3(ads.fov),
	}
	-- reference framing (ReferenceAnalysis/M4; verified in the M4 slice's playtest): hip front post 0.065 below centre;
	-- ADS: sight centred, hood top 0.116 above centre, FOV 62.23
	out.pass = math.abs((out.hipFrontPostBelowCentre :: number) - 0.065) < 0.02
		and math.abs((out.adsSightGlass[1] :: number) - 0.5) < 0.01 and math.abs((out.adsSightGlass[2] :: number) - 0.5) < 0.01
		and math.abs((out.adsHoodTopAboveCentre :: number) - 0.116) < 0.02 and math.abs((out.adsFov :: number) - 62.23) < 0.1
	return out
end

function Run.hands(): any
	equip("M4")
	local d = data()
	local g = d.Points.HandGrip
	local grip = Vector3.new(g[1], g[2], g[3])
	local len = 0
	for _, p in d.Parts do
		if p.Name == "LeftArm" then
			len = p.Size[3]
		end
	end
	local function window(seconds: number): (number, number)
		w("record", true)
		frames(seconds)
		local log = w("record", false).log
		local maxD, n = 0, 0
		for _, s in log do
			if s.arm and s.weapon then
				maxD = math.max(maxD, (s.arm * Vector3.new(0, 0, -len) - s.weapon * grip).Magnitude)
				n += 1
			end
		end
		return maxD, n
	end
	w("aim", false)
	frames(0.6)
	local hip, n1 = window(0.4)
	w("aim", true)
	local trans, n2 = window(0.45) -- ADS-in (the accepted keys; the model does not move the hand or the grip)
	frames(0.3)
	local ads, n3 = window(0.4)
	w("aim", false)
	frames(0.5)
	-- the accepted rig (unchanged joints / poses / HandGrip): the fitted hand sits 0.039 m (hip) / 0.020 m (ADS) from
	-- the grip = 0.139 / 0.070 studs; the ADS-in transition peaks at ~0.21 studs (rig property, reported only)
	return { frames = n1 + n2 + n3, hipStuds = r3(hip), adsStuds = r3(ads), transitionPeakStuds = r3(trans),
		pass = n1 > 5 and n3 > 5 and hip < 0.15 and ads < 0.08 }
end

-- the server's view of the ammo (WeaponState after a sync request), as M4FiringTest reads it
local function serverState(timeout: number): any
	w("sync")
	local t0 = os.clock()
	local s = w("state")
	while not s.server and os.clock() - t0 < timeout do
		task.wait(0.05)
		s = w("state")
	end
	return s
end

function Run.fire(): any
	equip("M4")
	w("refill")
	frames(0.4)
	local vm = viewmodel("M4Viewmodel") :: Model
	local metal = vm:FindFirstChild("Weapon_Metal") :: BasePart
	local s0 = serverState(2)
	local rest = metal.CFrame
	w("record", true)
	w("trigger", true)
	frames(0.6)
	local moved = (metal.CFrame.Position - rest.Position).Magnitude
	w("trigger", false)
	frames(0.5)
	local log = w("record", false)
	frames(0.3)
	local s1 = serverState(2)
	local shots = #(log.shots or {})
	local acc = s0.server and s1.server and (s1.server.Accepted or 0) - (s0.server.Accepted or 0)
	local rej = s0.server and s1.server and (s1.server.Rejected or 0) - (s0.server.Rejected or 0)
	return { shots = shots, clientShots = s1.shotCount - s0.shotCount, serverMagBefore = s0.server and s0.server.Mag,
		serverMagAfter = s1.server and s1.server.Mag, serverAccepted = acc, serverRejected = rej,
		viewmodelMovedStuds = r3(moved),
		pass = shots > 3 and s0.server ~= nil and s1.server ~= nil and (s0.server.Mag - s1.server.Mag) == shots
			and acc == shots and rej == 0 and moved > 0.001 }
end

-- one reload with per-frame samples of the magazine / charging-handle parts relative to the weapon body
local function reloadOnce(stressed: boolean, empty: boolean): any
	w("stressed", stressed)
	w("refill")
	frames(0.4)
	if empty then
		w("setAmmo", { Mag = 0, Chambered = false, Reserve = { 30, 30 } })
	else
		w("setAmmo", { Mag = 10, Chambered = true, Reserve = { 30, 30 } })
	end
	frames(0.5)
	local vm = viewmodel("M4Viewmodel") :: Model
	local metal = vm:FindFirstChild("Weapon_Metal") :: BasePart
	local mag = vm:FindFirstChild("Magazine_Tan") :: BasePart
	local feed = vm:FindFirstChild("Magazine_Metal") :: BasePart? -- the magazine's dark feed end (same bone)
	local ch = vm:FindFirstChild("ChargingHandle_Metal") :: BasePart
	local restMag = metal.CFrame:ToObjectSpace(mag.CFrame)
	local restCh = metal.CFrame:ToObjectSpace(ch.CFrame)
	local feedRel = feed and mag.CFrame:ToObjectSpace(feed.CFrame)
	local partsBefore = #vm:GetChildren()
	local res = w("reload")
	local t0 = os.clock()
	local maxMag, maxCh, samples, maxFeedDrift = 0, 0, 0, 0
	local clip: string? = nil
	while os.clock() - t0 < 5 do
		RunService.RenderStepped:Wait()
		local st = w("sync")
		if st.reloading then
			clip = st.reloading
		elseif clip then
			break
		end
		maxMag = math.max(maxMag, (metal.CFrame:ToObjectSpace(mag.CFrame).Position - restMag.Position).Magnitude)
		maxCh = math.max(maxCh, (metal.CFrame:ToObjectSpace(ch.CFrame).Position - restCh.Position).Magnitude)
		if feed and feedRel then
			maxFeedDrift = math.max(maxFeedDrift, (mag.CFrame:ToObjectSpace(feed.CFrame).Position - feedRel.Position).Magnitude)
		end
		samples += 1
	end
	local seconds = os.clock() - t0
	frames(0.4)
	local endMag = (metal.CFrame:ToObjectSpace(mag.CFrame).Position - restMag.Position).Magnitude
	return { request = res.result, clip = clip, seconds = r3(seconds), magMovedStuds = r3(maxMag),
		chargingMovedStuds = r3(maxCh), magBackStuds = r3(endMag), partsBefore = partsBefore, partsAfter = #vm:GetChildren(),
		samples = samples, feedPart = feed ~= nil, feedDriftStuds = r3(maxFeedDrift) }
end

function Run.reloads(): any
	equip("M4")
	local out: any = {
		tacticalRegular = reloadOnce(false, false),
		emptyRegular = reloadOnce(false, true),
		tacticalStressed = reloadOnce(true, false),
		emptyStressed = reloadOnce(true, true),
	}
	w("stressed", false)
	local ok = true
	for _, r in { out.tacticalRegular, out.emptyRegular, out.tacticalStressed, out.emptyStressed } do
		ok = ok and r.clip ~= nil and (r.magMovedStuds or 0) > 0.05 and (r.magBackStuds or 1) < 0.002
			and r.partsBefore == r.partsAfter and r.feedPart and (r.feedDriftStuds or 1) < 0.001
	end
	ok = ok and (out.emptyRegular.chargingMovedStuds or 0) > 0.01
	out.pass = ok
	return out
end

function Run.switching(): any
	local seen = {}
	for _, id in { "M4", "AK", "M4", "TestBlaster", "M4" } do
		equip(id)
		local n, names = countViewmodels()
		table.insert(seen, { equipped = id, viewmodels = n, names = names, m4Models = m4Models() })
	end
	local ok = true
	for _, s in seen do
		ok = ok and s.m4Models <= 1
		if s.equipped ~= "TestBlaster" then
			ok = ok and s.viewmodels == 1
		end
	end
	return { steps = seen, pass = ok }
end

local before: any = nil
function Run.respawn(stage: string): any
	if stage == "before" then
		equip("M4")
		local vm = viewmodel("M4Viewmodel")
		before = { model = vm, parts = vm and #vm:GetChildren() }
		return before
	end
	local t0 = os.clock()
	while (player.Character == nil or (player.Character :: any).Humanoid.Health <= 0) and os.clock() - t0 < 12 do
		frames(0.2)
	end
	frames(1.5)
	equip("M4")
	local vm = viewmodel("M4Viewmodel")
	local n = countViewmodels()
	return { sameModel = before ~= nil and vm == before.model, parts = vm and #vm:GetChildren(), viewmodels = n,
		m4Models = m4Models(), pass = vm ~= nil and n == 1 and m4Models() == 1 and (before == nil or #vm:GetChildren() == before.parts) }
end

function Run.muzzle(): any
	equip("M4")
	w("aim", false)
	frames(0.5)
	local d = data()
	local vm = viewmodel("M4Viewmodel") :: Model
	local steel = vm:FindFirstChild("Weapon_Steel") :: BasePart -- the light-grey muzzle device
	w("record", true)
	frames(0.2)
	local log = w("record", false).log
	local wcf = log[#log].weapon :: CFrame
	local m = d.Points.Muzzle
	local p = steel.CFrame:PointToObjectSpace(wcf * Vector3.new(m[1], m[2], m[3]))
	-- the dark end cap is 30 mm long in front of the grey device [measured, frame 100]
	local ahead = -p.Z - steel.Size.Z / 2
	return { localPoint = { r3(p.X), r3(p.Y), r3(p.Z) }, aheadOfDeviceM = r3(ahead * 0.28),
		pass = math.abs(p.X) < 0.01 and math.abs(p.Y) < 0.01 and math.abs(ahead * 0.28 - 0.030) < 0.003 }
end

function Run.perf(): any
	equip("M4")
	local ViewmodelRig = require(ReplicatedStorage.Shared.Viewmodel.ViewmodelRig)
	local d = data()
	local times = {}
	for _ = 1, 3 do
		local t0 = os.clock()
		local rig = ViewmodelRig.new(d, "M4PerfProbe")
		table.insert(times, r3((os.clock() - t0) * 1000))
		rig.Model:Destroy()
		frames(0.1)
	end
	local function frameMs(seconds: number): number
		local n, t0 = 0, os.clock()
		while os.clock() - t0 < seconds do
			RunService.RenderStepped:Wait()
			n += 1
		end
		return (os.clock() - t0) * 1000 / n
	end
	w("aim", false)
	frames(0.5)
	local hip = frameMs(2)
	w("aim", true)
	frames(0.8)
	local ads = frameMs(2)
	w("aim", false)
	frames(0.4)
	local tris = 0
	for _, s in d.Parts do
		tris += s.Triangles or 0
	end
	return { buildMs = times, hipFrameMs = r3(hip), adsFrameMs = r3(ads), triangles = tris, parts = #d.Parts,
		pass = times[#times] < 250 }
end

return Run
