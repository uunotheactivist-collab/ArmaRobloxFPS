-- A1 presentation arena (2026-11-10): a representative concrete-slab field reverse-engineered from recorded.mp4.
-- Isolated, reversible world layer: everything lives in ONE Model, Workspace.PresentationArena_A1. Run this in Studio
-- EDIT mode (command bar / execute_luau); it replaces an existing arena of the same name. Disable: move the model to
-- ServerStorage or delete it. Nothing else in the place is touched (no scripts, no baseplate / spawn / test ranges).
--
-- Reference measurements: Fidelity Audit 2026-11-10\a1_arena\reference_measurements.md.
-- "Screen-equivalent" sizes: the reference image rows back-projected through THIS game's camera (FOV 70, eye 4.05
-- studs, per-frame pitch from the horizon row). They reproduce the reference's on-screen appearance in this game; the
-- reference's true world scale is UNKNOWN (its FOV and eye height are UNKNOWN).
--
-- Tag per value: [M] MEASURED (screen-equivalent), [I] INFERRED, [C] CONFIRMED by eye.

local SPEC = {
	Version = "A1-v2", -- v2 (2026-11-10): slab width 4-12 -> 6-13 (v1 look-around: large-shape edges 0.14-0.19 vs reference 0.21-0.29)
	Seed = 20261110,
	-- field: an annulus around the spawn (origin), [M] density ~1 piece per 380 studs^2 (about 8 slabs between 8 and 60
	-- studs inside a 100 deg view: f0181 / f0331), min spacing [I]
	InnerRadius = 16, -- [I] spawn-pad clearance
	OuterRadius = 125, -- [I] stays >= 20 studs inside the nearest test area (BallisticTest at r ~ 173)
	AreaPerPiece = 380, -- [M]
	MinSpacing = 10, -- [I]
	-- keep-clear rectangles {xmin, xmax, zmin, zmax} (+ each piece's own radius)
	Clear = {
		{ -14, 24, -66, 8 }, -- the Targets dummy lane in front of the spawn (dummies x -1..11, z -50..-25)
		{ 20, 40, -10, 10 }, -- M4AnimTest rig (x 30, z -2..1)
	},
	-- piece kinds: share, height, width, thickness (studs)
	Kinds = {
		{ name = "Slab", share = 0.67, h = { 8.5, 10.5 }, w = { 6, 13 }, t = { 1.0, 1.5 } }, -- h [M] 9.5 (3 near slabs); w: the only frontal (unforeshortened) slab [M] 12.4; the 4-6 readings were rotated slabs = lower bounds (v1 used 4-12) -> 6-13 [I]; t [I] 0.7-1.2 projected
		{ name = "TallSlab", share = 0.15, h = { 12, 14 }, w = { 3, 6 }, t = { 1.0, 1.5 } }, -- h [M] 13-14 (far, lower confidence)
		{ name = "LowWall", share = 0.10, h = { 2.5, 4 }, w = { 8, 14 }, t = { 2, 3 } }, -- [I] low wide blocks (f0301, f0541)
		{ name = "Cube", share = 0.08, h = { 3.5, 5 }, w = { 0, 0 }, t = { 0, 0 } }, -- [I] white cubes ~ bot height (f0556)
	},
	LeanShare = 0.12, -- [C] leaning slabs exist (f0256, f0391); share and angle [I]
	LeanDeg = { 8, 20 },
	-- distant structures [C] (f0631-0736 tall blocks on the horizon); sizes and places [I], placed in sectors with no
	-- test area (north, west, north-east)
	FarClusters = { { 0, -210 }, { -210, -20 }, { 150, -220 } },
	FarPerCluster = 8,
	FarSpread = 40,
	FarH = { 14, 30 },
	FarW = { 6, 18 },
	FarT = { 4, 10 },
	-- look [I]: light-grey concrete; per-piece grey 188-212
	Material = Enum.Material.Concrete,
	Grey = { 188, 212 },
}

local rng = Random.new(SPEC.Seed)
local function uni(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

local old = workspace:FindFirstChild("PresentationArena_A1")
if old then
	old:Destroy()
end
local model = Instance.new("Model")
model.Name = "PresentationArena_A1"
model:SetAttribute("Layer", "A1 presentation arena (reference: recorded.mp4)")
model:SetAttribute("Version", SPEC.Version)
model:SetAttribute("Seed", SPEC.Seed)
model:SetAttribute("Builder", "Roblox/Environment/PresentationArenaA1/build_arena.luau")
model:SetAttribute("Disable", "move this model to ServerStorage or delete it")

local function piece(name: string, size: Vector3, cf: CFrame, grey: number)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true
	p.CastShadow = true
	p.Material = SPEC.Material
	p.Color = Color3.fromRGB(grey, grey, math.min(255, grey + 2))
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function blocked(x: number, z: number, rad: number): boolean
	for _, c in SPEC.Clear do
		if x > c[1] - rad and x < c[2] + rad and z > c[3] - rad and z < c[4] + rad then
			return true
		end
	end
	return false
end

-- field: dart throwing with a minimum spacing
local area = math.pi * (SPEC.OuterRadius ^ 2 - SPEC.InnerRadius ^ 2)
local target = math.floor(area / SPEC.AreaPerPiece)
local placed: { Vector3 } = {}
local counts = {}
local attempts = 0
while #placed < target and attempts < 50000 do
	attempts += 1
	local r = math.sqrt(rng:NextNumber(SPEC.InnerRadius ^ 2, SPEC.OuterRadius ^ 2))
	local a = rng:NextNumber(0, 2 * math.pi)
	local x, z = r * math.cos(a), r * math.sin(a)
	-- choose the kind first (its size sets the clearance)
	local u, kind = rng:NextNumber(), SPEC.Kinds[1]
	local acc = 0
	for _, k in SPEC.Kinds do
		acc += k.share
		if u <= acc then
			kind = k
			break
		end
	end
	local h = uni(kind.h)
	local w, t = h, h
	if kind.name ~= "Cube" then
		w = uni(kind.w)
		t = uni(kind.t)
	end
	local rad = 0.5 * math.sqrt(w * w + t * t) + 1
	local ok = not blocked(x, z, rad)
	if ok then
		for _, q in placed do
			if (Vector3.new(x, 0, z) - Vector3.new(q.X, 0, q.Z)).Magnitude < SPEC.MinSpacing then
				ok = false
				break
			end
		end
	end
	if ok then
		table.insert(placed, Vector3.new(x, 0, z))
		local yaw = rng:NextNumber(0, math.pi)
		local tilt = 0
		if (kind.name == "Slab" or kind.name == "TallSlab") and rng:NextNumber() < SPEC.LeanShare then
			tilt = math.rad(uni(SPEC.LeanDeg)) * (if rng:NextNumber() < 0.5 then -1 else 1)
		end
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, h / 2, 0)
		piece(kind.name .. (if tilt ~= 0 then "_Lean" else ""), Vector3.new(w, h, t), cf, math.floor(uni(SPEC.Grey)))
		counts[kind.name] = (counts[kind.name] or 0) + 1
		if tilt ~= 0 then
			counts.Lean = (counts.Lean or 0) + 1
		end
	end
end

-- distant clusters
for _, c in SPEC.FarClusters do
	for _ = 1, SPEC.FarPerCluster do
		local x, z = c[1] + rng:NextNumber(-SPEC.FarSpread, SPEC.FarSpread), c[2] + rng:NextNumber(-SPEC.FarSpread, SPEC.FarSpread)
		local h, w, t = uni(SPEC.FarH), uni(SPEC.FarW), uni(SPEC.FarT)
		piece("FarBlock", Vector3.new(w, h, t), CFrame.new(x, h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), math.floor(uni(SPEC.Grey)))
		counts.FarBlock = (counts.FarBlock or 0) + 1
	end
end

model.Parent = workspace
local parts = #model:GetChildren()
local list = {}
for k, v in counts do
	table.insert(list, k .. "=" .. v)
end
table.sort(list)
return string.format("PresentationArena_A1 %s: %d parts (target %d field pieces, %d attempts) %s", SPEC.Version, parts, target, attempts, table.concat(list, " "))
