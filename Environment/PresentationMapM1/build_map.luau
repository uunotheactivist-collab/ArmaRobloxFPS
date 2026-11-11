-- M1 presentation map (2026-11-10): an urban Mexican-town district reconstructed from the YouTube reference
-- cM2D-CniPXI (Arma Reforger "MEXICO" community map). Evidence and decisions: Fidelity Audit 2026-11-10\map_m1\
-- (DECISIONS.md D1-D5) and map_reference\MAP_REFERENCE.md.
--
-- Isolated, reversible world layer: everything lives in ONE Model, Workspace.PresentationMap_M1. Run in Studio EDIT mode
-- (command bar / execute_luau); it replaces an existing model of the same name and is built zone by zone (small
-- parent operations, task.wait between). Disable: move the model to ServerStorage or delete it. No scripts, no
-- remotes; the baseplate, SpawnLocation, test ranges and Lighting are not touched. Every part is anchored and unmarked
-- (BallisticSurface unset -> NonPenetrable, the Config.Ballistics default for world geometry).
--
-- Scale (D1): the global project scale (0.28 m / stud) is unchanged. The map uses a map-specific calibration anchored on
-- the camera eye: S = 2.5 studs per reference metre; heights measured as eye-height ratios are built as ratio x 4.05.
-- Layout (D2): the reference deploy map (1260-1269 s) shows the base / deploy area at the south-west corner of a dense
-- grid, where a west arterial, a south highway and the main avenue meet. Rotated so the avenue runs along world -Z;
-- the spawn plaza (origin) is the base. Exact footprints are INFERRED.
-- Tags: [M] measured (reference), [I] inferred, [C] confirmed by eye (frame time in s).

local SPEC = {
	Version = "M1-v3", -- v2: test-range clearances >= 10 studs, avenue-side dry lot (W1R1) [C 285 / 315], V4 corner on the left,
	-- smooth sidewalks; v3: two construction-edge trees moved off the V6 sightline, EB west neighbour roof addition
	-- (tall wall left of the V3 rooftop view [C 225]), EB stair treads / landings thinned (headroom), roof-room band
	-- kept off the door. Saved model content hash 3670:3653972053 (v2 build + the v3 edits applied in place, all
	-- RNG-neutral; this file encodes the same edits, a fresh re-run was not repeated).
	Seed = 20261111,
	S = 2.5, -- studs per reference metre [M via E-ratios, DECISIONS D1]
	E = 4.05, -- camera eye height, studs (Config.Movement)
	Storey = 7.2, -- 1.78 E [M 1.6-1.83 E, 615]
	Parapet = 3.2, -- 0.79 E [M 0.72-0.86 E, 225]
	WallH = 5.3, -- compound wall 1.31 E [M 1.27-1.32 E, 1245] (D3)
	RoofRoomH = 9.6, -- roof access room to slab top, 2.37 E [M 225]
	DoorH = 6.2, DoorW = 4, -- avatar clearance (5.1-stud R15 body + margin) [forced deviation, D1]
	Carriageway = 35, Median = 2.5, Sidewalk = 10, -- 14 m / 1 m / 3.9 m [M ratios, 285]
	SideStreet = 28, -- ~11 m [M 165: 3.5-4 storeys]
	Block = 240, -- building-line block; + street = ~290 pitch (~116 m) [M deploy map; 1 km grid I]
}

local rng = Random.new(SPEC.Seed)
local function c3(r, g, b) return Color3.fromRGB(r, g, b) end
local M = Enum.Material
local PLASTER = { c3(222, 212, 192), c3(205, 198, 184), c3(214, 196, 170), c3(196, 188, 176), c3(230, 222, 205), c3(204, 184, 152), c3(186, 178, 168), c3(218, 204, 186) }
local ROOF, CONCRETE, FRAME, SLABC = c3(168, 152, 136), c3(176, 170, 160), c3(150, 146, 140), c3(150, 146, 138)
local BRICK, GLASS, DARK = c3(146, 84, 62), c3(36, 40, 44), c3(48, 46, 44)
local ASPHALT, PAVEMENT, GRAVEL, SAND, GRASS, DIRT = c3(98, 96, 94), c3(166, 160, 150), c3(178, 164, 146), c3(196, 178, 146), c3(112, 112, 62), c3(126, 114, 94)
local METAL, RUST, YELLOW, BLACK, BARRIER = c3(84, 86, 88), c3(120, 78, 52), c3(214, 180, 40), c3(30, 30, 30), c3(170, 165, 158)
local LEAF, PINE, TRUNK, SHRUB = c3(62, 84, 46), c3(46, 66, 40), c3(88, 70, 52), c3(78, 96, 52)

local old = workspace:FindFirstChild("PresentationMap_M1")
if old then old:Destroy() end
local root = Instance.new("Model")
root.Name = "PresentationMap_M1"
root:SetAttribute("Layer", "M1 presentation map (reference: YouTube cM2D-CniPXI, Arma Reforger MEXICO)")
root:SetAttribute("Version", SPEC.Version)
root:SetAttribute("Seed", SPEC.Seed)
root:SetAttribute("Scale", "map-specific S = 2.5 studs / reference m (eye-anchored); global 0.28 m / stud unchanged")
root:SetAttribute("Builder", "Roblox/Environment/PresentationMapM1/build_map.luau")
root:SetAttribute("Disable", "move this Model to ServerStorage or delete it")
root.Parent = workspace

local count = 0
local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or M.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	count += 1
	return p
end
local function box(parent, x0, y0, z0, x1, y1, z1, color, mat) -- axis-aligned, min / max corners
	if x1 < x0 then x0, x1 = x1, x0 end
	if z1 < z0 then z0, z1 = z1, z0 end
	return part(parent, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat)
end
local function ball(parent, x, y, z, d, color)
	return part(parent, Vector3.new(d, d, d), CFrame.new(x, y, z), color, M.LeafyGrass, Enum.PartType.Ball)
end
local function vcyl(parent, x, y0, y1, z, d, color, mat) -- vertical cylinder
	return part(parent, Vector3.new(y1 - y0, d, d), CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, mat, Enum.PartType.Cylinder)
end
local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
local function pick(t) return t[rng:NextInteger(1, #t)] end
local zone -- current zone model; built outside the DataModel, parented to root by flush()
local function begin(name)
	zone = Instance.new("Model")
	zone.Name = name
end
local function flush()
	zone.Parent = root
	task.wait()
end

local ST, PAR = SPEC.Storey, SPEC.Parapet

-- faces: outward normal N (-Z), S (+Z), W (-X), E (+X); returns along-range, plane coordinate, outward sign, axis
local function faceInfo(b, f)
	if f == "N" then return b.x0, b.x1, b.z0, -1, "x" end
	if f == "S" then return b.x0, b.x1, b.z1, 1, "x" end
	if f == "W" then return b.z0, b.z1, b.x0, -1, "z" end
	return b.z0, b.z1, b.x1, 1, "z"
end
-- an element on a face: along-centre a, width w, y range, outer surface at `proud` from the face, thickness `depth`
local function onFace(parent, b, f, a, w, y0, y1, proud, depth, color, mat)
	local _, _, c, sgn, ax = faceInfo(b, f)
	local mid = c + sgn * (proud - depth / 2)
	if ax == "x" then
		return part(parent, Vector3.new(w, y1 - y0, depth), CFrame.new(a, (y0 + y1) / 2, mid), color, mat)
	end
	return part(parent, Vector3.new(depth, y1 - y0, w), CFrame.new(mid, (y0 + y1) / 2, a), color, mat)
end

-- street facade: ground floor by style, punched windows above, optional balconies / AC units / awnings
local function facade(m, b, f, style, detail)
	local a0, a1 = faceInfo(b, f)
	local L = a1 - a0
	if not detail then -- distant faces: one dark window band per upper storey, dark ground floor
		for s = 1, b.n - 1 do
			onFace(m, b, f, (a0 + a1) / 2, L * 0.72, s * ST + 2.6, s * ST + 5.6, 0.12, 0.3, GLASS, M.SmoothPlastic)
		end
		onFace(m, b, f, (a0 + a1) / 2, L * 0.8, 0.45, 5.8, 0.12, 0.3, DARK, M.SmoothPlastic)
		return
	end
	local bays = math.max(1, math.floor(L / 9))
	local bw = L / bays
	if style == "arcade" then -- [C 285 arcaded shopfronts]
		onFace(m, b, f, (a0 + a1) / 2, L - 0.4, 0.45, 6.4, 0.12, 0.3, DARK, M.SmoothPlastic)
		onFace(m, b, f, (a0 + a1) / 2, L, 6.4, 7.6, 3.2, 3.2, b.col, M.Plaster)
		for k = 0, bays do
			onFace(m, b, f, math.clamp(a0 + k * bw, a0 + 0.7, a1 - 0.7), 1.4, 0.45, 6.4, 3.2, 1.4, b.col, M.Plaster)
		end
	end
	for k = 0, bays - 1 do
		local a = a0 + (k + 0.5) * bw
		if style == "shop" then
			onFace(m, b, f, a, bw * 0.72, 0.45, 5.9, 0.12, 0.3, DARK, M.SmoothPlastic)
			if rng:NextNumber() < 0.3 then
				onFace(m, b, f, a, bw * 0.8, 6.2, 6.5, 1.6, 1.6, pick({ c3(150, 60, 50), c3(60, 90, 120), METAL }), M.Fabric)
			end
		elseif style == "garage" then -- [C 375 roll-up doors]
			onFace(m, b, f, a, math.min(7.5, bw * 0.8), 0.45, 6.3, 0.12, 0.25, pick({ RUST, METAL, c3(140, 140, 132) }), M.CorrodedMetal)
		elseif style == "plain" then
			if k == math.floor(bays / 2) then
				onFace(m, b, f, a, SPEC.DoorW - 0.6, 0.45, SPEC.DoorH - 0.4, 0.12, 0.25, pick({ c3(150, 40, 36), c3(70, 60, 50), METAL }), M.Wood)
			else
				onFace(m, b, f, a, 3.0, 2.85, 6.05, 0.12, 0.3, GLASS, M.SmoothPlastic)
			end
		end
		for s = 1, b.n - 1 do
			local y = s * ST + 0.45
			onFace(m, b, f, a, math.min(3.2, bw * 0.55), y + 2.2, y + 5.4, 0.12, 0.3, GLASS, M.SmoothPlastic)
			if b.balcony and rng:NextNumber() < 0.55 then -- [C 285 / 465 balconies]
				onFace(m, b, f, a, math.min(5.5, bw * 0.8), y, y + 0.4, 2.4, 2.4, b.col, M.Concrete)
				onFace(m, b, f, a, math.min(5.5, bw * 0.8), y + 0.4, y + 2.6, 2.4, 0.2, METAL, M.Metal)
			elseif rng:NextNumber() < 0.14 then -- window AC unit [C 45 / 435]
				onFace(m, b, f, a + 1.2, 2.0, y + 1.0, y + 2.4, 1.3, 1.3, c3(214, 214, 208), M.SmoothPlastic)
			end
		end
	end
end

-- a flat-roofed street building (solid body; only the EB and the frames are enterable)
local function building(parent, x0, z0, x1, z1, n, faces, style, detail, opts)
	opts = opts or {}
	local m = model(parent, opts.name or "Building")
	local b = { x0 = x0, z0 = z0, x1 = x1, z1 = z1, n = n, col = opts.col or pick(PLASTER), balcony = opts.balcony }
	local H = n * ST + 0.45
	b.H = H
	box(m, x0, 0, z0, x1, H, z1, b.col, M.Plaster)
	box(m, x0 + 0.6, H, z0 + 0.6, x1 - 0.6, H + 0.15, z1 - 0.6, ROOF, M.Concrete)
	box(m, x0, H, z0, x1, H + PAR, z0 + 0.6, b.col, M.Plaster) -- parapet [M 0.79 E]
	box(m, x0, H, z1 - 0.6, x1, H + PAR, z1, b.col, M.Plaster)
	box(m, x0, H, z0 + 0.6, x0 + 0.6, H + PAR, z1 - 0.6, b.col, M.Plaster)
	box(m, x1 - 0.6, H, z0 + 0.6, x1, H + PAR, z1 - 0.6, b.col, M.Plaster)
	for _, f in faces do facade(m, b, f, style, detail) end
	if detail and rng:NextNumber() < 0.45 then -- roof clutter [C 225 / 375 / 1125: antennas, dishes, tanks]
		local rx, rz = rng:NextNumber(x0 + 3, x1 - 3), rng:NextNumber(z0 + 3, z1 - 3)
		local kind = rng:NextInteger(1, 3)
		if kind == 1 then
			box(m, rx - 0.12, H, rz - 0.12, rx + 0.12, H + 9, rz + 0.12, METAL, M.Metal)
			part(m, Vector3.new(5, 0.2, 0.2), CFrame.new(rx, H + 8.5, rz) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0), METAL, M.Metal)
		elseif kind == 2 then
			part(m, Vector3.new(0.3, 3.2, 3.2), CFrame.new(rx, H + 2.2, rz) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(55)), c3(220, 220, 214), M.SmoothPlastic, Enum.PartType.Cylinder)
		else
			vcyl(m, rx, H, H + 4, rz, 3.6, c3(40, 40, 42), M.Plastic) -- water tank
		end
	end
	return b
end

-- one side of a block: a row of buildings along [a0, a1] at the building line; depth / storeys / styles drawn per building
local function row(parent, side, a0, a1, line, depthRange, nRange, styles, detail, opts)
	opts = opts or {}
	local a = a0
	while a1 - a > 8 do
		local w = rng:NextNumber(24, 36)
		if a1 - a - w < 16 then w = a1 - a end
		local d = rng:NextNumber(depthRange[1], depthRange[2])
		local n = rng:NextInteger(nRange[1], nRange[2])
		local x0, z0, x1, z1
		if side == "S" then x0, x1, z0, z1 = a, a + w, line - d, line
		elseif side == "N" then x0, x1, z0, z1 = a, a + w, line, line + d
		elseif side == "E" then z0, z1, x0, x1 = a, a + w, line - d, line
		else z0, z1, x0, x1 = a, a + w, line, line + d end
		building(parent, x0, z0, x1, z1, n, { side }, pick(styles), detail, { balcony = opts.balcony and rng:NextNumber() < 0.5 })
		a += w
	end
end

-- straight wall along axis ax ("x": runs along x at z = c; "z": along z at x = c) from a0 to a1, y0..y1, thickness t,
-- with openings { {centre, width, bottom, top} }
local function wallOpen(parent, ax, c, a0, a1, y0, y1, t, openings, color, mat)
	table.sort(openings, function(p, q) return p[1] < q[1] end)
	local function seg(s0, s1, h0, h1)
		if s1 - s0 < 0.05 or h1 - h0 < 0.05 then return end
		if ax == "x" then box(parent, s0, h0, c - t / 2, s1, h1, c + t / 2, color, mat)
		else box(parent, c - t / 2, h0, s0, c + t / 2, h1, s1, color, mat) end
	end
	local cur = a0
	for _, o in openings do
		local o0, o1 = o[1] - o[2] / 2, o[1] + o[2] / 2
		seg(cur, o0, y0, y1)
		seg(o0, o1, y0, o[3])
		seg(o0, o1, o[4], y1)
		cur = o1
	end
	seg(cur, a1, y0, y1)
end

------------------------------------------------------------------------------------------------------------------------
-- layout constants (world studs)
local AV = SPEC.Carriageway * 2 + SPEC.Median + SPEC.Sidewalk * 2 -- 92.5
local avX = AV / 2 -- avenue building lines x = +-46.25
local Z_C1a, Z_C1b = -118, -90 -- cross street C1 = plaza north edge
local Z_C2a, Z_C2b = -386, -358
local Z_C3a, Z_C3b = -654, -626
local Z_END = -900
local SS1a, SS1b = -avX - SPEC.Block - SPEC.SideStreet, -avX - SPEC.Block -- side street x -314.25 .. -286.25
local W1x0, W1x1 = SS1b, -avX -- block column W1: x -286.25 .. -46.25
local W2x0, W2x1 = SS1a - SPEC.Block, SS1a -- W2: x -554.25 .. -314.25
local E1x0, E1x1 = avX, 190 -- E1 (truncated before MovementTest at x 207)

------------------------------------------------------------------------------------------------------------------------
-- ZONE: ground surfaces (plaza = base / deploy area [map], avenue, streets, arterial, lots); top heights differ per
-- layer so no two surfaces are coplanar
begin("Ground")
box(zone, -90, -0.5, -90, 110, 0.04, 52, GRAVEL, M.Ground) -- plaza [C 975 gravel lot]
box(zone, -avX + SPEC.Sidewalk, -0.5, Z_END, -SPEC.Median / 2, 0.08, Z_C1b, ASPHALT, M.Asphalt) -- avenue
box(zone, SPEC.Median / 2, -0.5, Z_END, avX - SPEC.Sidewalk, 0.08, Z_C1b, ASPHALT, M.Asphalt)
box(zone, -SPEC.Median / 2, -0.5, Z_END, SPEC.Median / 2, 0.6, Z_C1b - 100, c3(196, 186, 150), M.Concrete)
for k = 0, 39 do -- striped median curb near the plaza [C 285: black / yellow]
	local z = Z_C1b - k * 2.5
	box(zone, -SPEC.Median / 2, -0.5, z - 2.5, SPEC.Median / 2, 0.6, z, (k % 2 == 0) and YELLOW or BLACK, M.SmoothPlastic)
end
for z = Z_C1b - 6, Z_END + 6, -18 do -- dashed lane lines
	for _, x in { -SPEC.Median / 2 - 17.5, SPEC.Median / 2 + 17.5 } do
		box(zone, x - 0.25, 0.08, z - 7, x + 0.25, 0.1, z, c3(225, 225, 220), M.SmoothPlastic)
	end
end
for _, zz in { { Z_C1a, Z_C1b }, { Z_C2a, Z_C2b }, { Z_C3a, Z_C3b } } do -- cross streets
	box(zone, -600, -0.5, zz[1] + 4, 190, 0.07, zz[2] - 4, ASPHALT, M.Asphalt)
end
box(zone, SS1a + 4, -0.5, Z_END, SS1b - 4, 0.075, Z_C1a, DIRT, M.Ground) -- side street (dirt) [C 165]
local function blockSidewalk(x0, z0, x1, z1, wW, wE)
	box(zone, x0 - wW, -0.5, z0 - 4, x1 + wE, 0.45, z0, PAVEMENT, M.Concrete)
	box(zone, x0 - wW, -0.5, z1, x1 + wE, 0.45, z1 + 4, PAVEMENT, M.Concrete)
	box(zone, x0 - wW, -0.5, z0, x0, 0.45, z1, PAVEMENT, M.Concrete)
	box(zone, x1, -0.5, z0, x1 + wE, 0.45, z1, PAVEMENT, M.Concrete)
	box(zone, x0, -0.5, z0, x1, 0.02, z1, c3(150, 140, 122), M.Ground) -- block interior ground (seen from roofs)
end
for _, r in { { Z_C2b, Z_C1a }, { Z_C3b, Z_C2a } } do
	blockSidewalk(W1x0, r[1], W1x1, r[2], 4, 10)
	blockSidewalk(E1x0, r[1], E1x1, r[2], 10, 4)
	blockSidewalk(W2x0, r[1], W2x1, r[2], 4, 4)
end
box(zone, -650, -0.5, 54, 100, 0.08, 76, ASPHALT, M.Asphalt) -- arterial (west) + plaza south road [map]; >= 10 from BallisticTest
box(zone, -650, -0.5, 76, -95, 0.45, 79, PAVEMENT, M.Concrete)
box(zone, -60, -0.5, 79, 40, 0.06, 150, GRASS, M.Grass) -- verge / mound area [C 975]
do -- grassy mound: two wedges back to back [C 975 / 1095]
	for _, s in { 1, -1 } do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = Vector3.new(60, 7, 18)
		w.CFrame = CFrame.new(-5, 3.5, 110 - s * 9) * CFrame.Angles(0, (s == 1) and 0 or math.pi, 0)
		w.Color = GRASS
		w.Material = M.Grass
		w.Parent = zone
		count += 1
	end
end
box(zone, 110, -0.5, -88, 195, 0.05, 70, SAND, M.Sand) -- construction lot [C 615]; >= 10 from MovementTest
box(zone, -292, -0.5, -88, -92, 0.03, 54, c3(150, 136, 112), M.Ground) -- compound zone [C 1215 / 1245]
box(zone, -196, -0.5, -88, -176, 0.07, 54, c3(120, 116, 110), M.Concrete) -- lane [C 1245]
box(zone, -179, -0.5, -88, -176, 0.35, 54, PAVEMENT, M.Concrete)
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: enterable building EB (block W1R1 south-east corner): 3 storeys, switchback stair to a roof access room
-- [C 195 / 495 stairs, 405 / 495 red doors, 225 roof + room]
begin("EnterableBuilding")
do
	local x0, x1, z0, z1 = -78, -46.5, -148, -118
	local g = 0.45
	local col = c3(214, 200, 176)
	local t = 0.8
	local n = 3
	local roofY = g + n * ST
	box(zone, x0, -0.5, z0, x1, g, z1, SLABC, M.Concrete)
	for s = 1, n do -- slabs with the stair opening x -78..-70, z -148..-136
		local y = g + s * ST
		box(zone, -70, y - 0.6, z0, x1, y, -136, SLABC, M.Concrete)
		box(zone, x0, y - 0.6, -136, x1, y, z1, SLABC, M.Concrete)
	end
	for s = 0, n - 1 do
		local y0, y1 = g + s * ST, g + (s + 1) * ST - 0.6
		local w0, w1 = y0 + 2.4, y0 + 5.6 -- 0.95 m sill, 1.3 m window
		if s == 0 then
			wallOpen(zone, "x", z1 - t / 2, x0, x1, y0, y1, t, { { -66, 9, y0, y0 + 6.2 }, { -55, SPEC.DoorW, y0, y0 + SPEC.DoorH } }, col, M.Plaster)
			wallOpen(zone, "z", x1 - t / 2, z0, z1, y0, y1, t, { { -141, 7, y0, y0 + 6.2 }, { -126, 7, y0, y0 + 6.2 } }, col, M.Plaster)
			wallOpen(zone, "x", z0 + t / 2, x0, x1, y0, y1, t, { { -56, 3, w0, w1 } }, col, M.Plaster)
			wallOpen(zone, "z", x0 + t / 2, z0, z1, y0, y1, t, { { -124, 3, w0, w1 } }, col, M.Plaster)
		else
			wallOpen(zone, "x", z1 - t / 2, x0, x1, y0, y1, t, { { -72, 3, w0, w1 }, { -62, 3, w0, w1 }, { -52, 3, w0, w1 } }, col, M.Plaster)
			wallOpen(zone, "z", x1 - t / 2, z0, z1, y0, y1, t, { { -142, 3, w0, w1 }, { -132, 3, w0, w1 }, { -123, 3, w0, w1 } }, col, M.Plaster)
			wallOpen(zone, "x", z0 + t / 2, x0, x1, y0, y1, t, { { -58, 3, w0, w1 } }, col, M.Plaster)
			wallOpen(zone, "z", x0 + t / 2, z0, z1, y0, y1, t, { { -124, 3, w0, w1 } }, col, M.Plaster)
		end
		box(zone, x0 - 0.1, y1, z1 - 0.1, x1 + 0.1, y1 + 0.6, z1 + 0.25, c3(190, 180, 164), M.Concrete) -- slab bands
		box(zone, x1 - 0.1, y1, z0 - 0.1, x1 + 0.25, y1 + 0.6, z1 + 0.1, c3(190, 180, 164), M.Concrete)
		-- stair-core partition at x -69.6 (door at z -131), floor partition at z -133 (door at x -60)
		wallOpen(zone, "z", -69.6, z0 + t, -128, y0, y1, 0.4, { { -131, SPEC.DoorW, y0, y0 + SPEC.DoorH } }, c3(200, 192, 176), M.Plaster)
		wallOpen(zone, "x", -133, -69.4, x1 - t, y0, y1, 0.4, { { -60, SPEC.DoorW, y0, y0 + SPEC.DoorH } }, c3(206, 198, 182), M.Plaster)
		box(zone, -57.8, y0, -132.8, -57.6, y0 + SPEC.DoorH - 0.2, -129.2, c3(150, 40, 36), M.Wood) -- open red door leaf
	end
	-- switchback stair per storey (rise 0.6, tread 1.0): flight A x -77.2..-74 up toward -Z from z -136, landing
	-- z -147.2..-142, flight B x -74..-70 up toward +Z, arriving at z -136 on the next level. Treads are 1.0 thick and
	-- landings 0.8 (not solid to the floor): ~6.2 studs of headroom over the flight / landing below (walk test).
	local rise, tread = ST / 12, 1.0
	local STC = c3(170, 164, 154)
	for s = 0, n - 1 do
		local y = g + s * ST
		for k = 1, 6 do box(zone, x0 + t, y + k * rise - 1.0, -136 - k * tread, -74, y + k * rise, -136 - (k - 1) * tread, STC, M.Concrete) end
		box(zone, x0 + t, y + 6 * rise - 0.8, z0 + t, -70, y + 6 * rise, -142, STC, M.Concrete)
		for k = 1, 6 do box(zone, -74, y + (6 + k) * rise - 1.0, -142 + (k - 1) * tread, -70, y + (6 + k) * rise, -142 + k * tread, STC, M.Concrete) end
	end
	-- roof surface (stair opening left open), parapet, roof access room over the core with a door to the roof
	box(zone, -70, roofY, z0 + 0.6, x1 - 0.6, roofY + 0.12, -136, ROOF, M.Concrete)
	box(zone, x0 + 0.6, roofY, -136, x1 - 0.6, roofY + 0.12, z1 - 0.6, ROOF, M.Concrete)
	box(zone, x0, roofY, z1 - 0.6, x1, roofY + PAR, z1, col, M.Plaster)
	box(zone, x1 - 0.6, roofY, z0, x1, roofY + PAR, z1 - 0.6, col, M.Plaster)
	box(zone, x0, roofY, z0, x1 - 0.6, roofY + PAR, z0 + 0.6, col, M.Plaster)
	box(zone, x0, roofY, z0 + 0.6, x0 + 0.6, roofY + PAR, z1 - 0.6, col, M.Plaster)
	local rr0, rr1 = roofY, roofY + SPEC.RoofRoomH - 0.6
	local rx0, rx1, rz0, rz1 = -78.6, -66, -148.6, -128.4
	local rc = c3(222, 210, 188)
	wallOpen(zone, "x", rz1 - 0.4, rx0, rx1, rr0, rr1, 0.8, { { -72, SPEC.DoorW, rr0, rr0 + SPEC.DoorH } }, rc, M.Plaster)
	wallOpen(zone, "x", rz0 + 0.4, rx0, rx1, rr0, rr1, 0.8, {}, rc, M.Plaster)
	wallOpen(zone, "z", rx1 - 0.4, rz0 + 0.8, rz1 - 0.8, rr0, rr1, 0.8, {}, rc, M.Plaster)
	wallOpen(zone, "z", rx0 + 0.4, rz0 + 0.8, rz1 - 0.8, rr0, rr1, 0.8, {}, rc, M.Plaster)
	box(zone, rx0 - 1.2, rr1, rz0 - 1.2, rx1 + 1.2, rr1 + 0.6, rz1 + 1.2, c3(176, 168, 156), M.Concrete) -- overhang slab [C 225]
	box(zone, rx1 - 0.02, rr0, rz0 + 0.8, rx1 + 0.06, rr0 + 3.4, rz1 - 0.8, c3(150, 140, 126), M.Concrete) -- stained lower band [C 225]
	box(zone, rx0 + 0.8, rr0, rz1 - 0.02, -74, rr0 + 3.4, rz1 + 0.06, c3(150, 140, 126), M.Concrete) -- left of the door only
	box(zone, -70.12, rr1 + 0.6, -140.12, -69.88, rr1 + 10.6, -139.88, METAL, M.Metal) -- antenna mast
	part(zone, Vector3.new(6, 0.15, 0.15), CFrame.new(-70, rr1 + 9.8, -140) * CFrame.Angles(0, math.rad(30), 0), METAL, M.Metal)
	part(zone, Vector3.new(4, 0.15, 0.15), CFrame.new(-70, rr1 + 8.6, -140) * CFrame.Angles(0, math.rad(30), 0), METAL, M.Metal)
end
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: town blocks [C 285 / 435 / 462 / 465 frontages; 165 side street; 225 roofscape]
local AVS = { "arcade", "shop", "shop", "plain", "shop" }
local SIDE = { "plain", "garage", "shop", "plain" }
begin("Block_W1R1") -- x -286..-46, z -358..-118; EB at the south-east corner
do
	local m = model(zone, "W1R1")
	-- avenue side: dry lot with scrub, a low block wall and a kiosk; the block's back buildings stand behind it
	-- [C 285 / 315: open dirt lot with sparse trees opposite the frontage; 585 concrete-block walls]
	box(m, -120, -0.5, -326, W1x1, 0.035, -148, c3(160, 146, 120), M.Ground)
	for z = -320, -156, -16 do
		if rng:NextNumber() < 0.8 then box(m, W1x1 - 0.8, 0, z - 6, W1x1 - 0.2, 2.6, z + 6, CONCRETE, M.Concrete) end
	end
	building(m, -72, -232, -56, -220, 1, { "E" }, "shop", true, { name = "Kiosk" })
	row(m, "S", W1x0 + 30, -110, Z_C1a, { 30, 34 }, { 2, 4 }, SIDE, true)
	building(m, -110, -152, -78, -118, 4, { "S" }, "shop", true, { name = "EB_West_Neighbour" }) -- [C 225 taller wall left]
	building(m, W1x0, -148, W1x0 + 30, -118, 3, { "S", "W" }, "plain", true)
	row(m, "W", -358 + 32, -148, W1x0, { 30, 34 }, { 3, 4 }, SIDE, true) -- side-street frontage (V2 right)
	row(m, "N", W1x0, W1x1, Z_C2b, { 28, 32 }, { 3, 5 }, SIDE, false)
	for _, r in { { -150, -210, -112, -160, 3 }, { -112, -200, -86, -156, 2 }, { -200, -230, -152, -170, 3 }, { -120, -250, -86, -205, 3 }, { -240, -300, -190, -250, 2 }, { -170, -300, -120, -255, 4 } } do
		building(m, r[1], r[2], r[3], r[4], r[5], {}, "plain", false) -- block interior roofscape
	end
	do -- v3: set-back added floor on the EB west neighbour, flush with its east face (no RNG) [C 225 tall wall left]
		local add = model(m, "EB_West_Neighbour_RoofAddition")
		local col = c3(205, 198, 184)
		local H = 4 * ST + 0.45
		box(add, -104, H, -148, -78, H + ST, -121, col, M.Plaster)
		box(add, -103.4, H + ST, -147.4, -78.6, H + ST + 0.15, -121.6, ROOF, M.Concrete)
		box(add, -104, H + ST, -148, -78, H + ST + PAR, -147.4, col, M.Plaster)
		box(add, -104, H + ST, -121.6, -78, H + ST + PAR, -121, col, M.Plaster)
		box(add, -104, H + ST, -147.4, -103.4, H + ST + PAR, -121.6, col, M.Plaster)
		box(add, -78.6, H + ST, -147.4, -78, H + ST + PAR, -121.6, col, M.Plaster)
	end
end
flush()
begin("Block_E1R1") -- x 46..190, z -358..-118
do
	local m = model(zone, "E1R1")
	row(m, "W", -358 + 32, -152, E1x0, { 30, 36 }, { 3, 4 }, AVS, true, { balcony = true }) -- V1 right frontage
	building(m, E1x0, -152, E1x0 + 34, -118, 3, { "S", "W" }, "shop", true)
	building(m, 84, -156, 150, -118, 6, { "S", "W" }, "plain", true, { name = "Apartments", col = c3(190, 186, 178) }) -- [C 435]
	building(m, 150, -150, 190, -118, 2, { "S", "E" }, "garage", true)
	row(m, "E", -358 + 32, -150, E1x1, { 26, 30 }, { 2, 3 }, SIDE, false)
	row(m, "N", E1x0, E1x1, Z_C2b, { 28, 32 }, { 3, 4 }, SIDE, false)
end
flush()
begin("Block_W2R1") -- east frontage on the side street (V2 left) with the unfinished frame FB1
do
	local m = model(zone, "W2R1")
	row(m, "E", -358 + 32, -205, SS1a, { 30, 34 }, { 3, 5 }, SIDE, true)
	row(m, "E", -142, -118, SS1a, { 24, 24 }, { 3, 3 }, SIDE, true)
	row(m, "S", W2x0, SS1a - 34, Z_C1a, { 30, 34 }, { 2, 3 }, SIDE, false)
	row(m, "N", W2x0, W2x1, Z_C2b, { 28, 32 }, { 3, 4 }, SIDE, false)
end
flush()
begin("Block_R2") -- z -626..-386: apartment blocks close the side-street vista [C 165 end]
do
	local m = model(zone, "R2")
	row(m, "S", W2x0, SS1a - 6, Z_C2a, { 34, 40 }, { 5, 6 }, { "plain" }, true)
	building(m, SS1a - 6, -430, SS1b + 6, -386, 6, { "S" }, "plain", true, { name = "SideStreetEnd_Apartments", col = c3(214, 210, 200) })
	row(m, "S", W1x0 + 6, W1x1 - 40, Z_C2a, { 34, 40 }, { 4, 6 }, { "plain", "shop" }, true)
	building(m, W1x1 - 40, -426, W1x1, -386, 4, { "S", "E" }, "arcade", true)
	row(m, "E", -626 + 32, -426, W1x1, { 30, 36 }, { 3, 4 }, AVS, true, { balcony = true })
	row(m, "W", -626 + 32, -386, E1x0, { 30, 36 }, { 3, 4 }, AVS, true, { balcony = true })
	row(m, "S", E1x0 + 36, E1x1, Z_C2a, { 30, 34 }, { 3, 5 }, SIDE, false)
	row(m, "N", W1x0, W1x1, Z_C3b, { 28, 32 }, { 3, 4 }, SIDE, false)
	row(m, "N", E1x0, E1x1, Z_C3b, { 28, 32 }, { 3, 4 }, SIDE, false)
	row(m, "W", -626 + 32, -426, W1x0 + 6, { 30, 34 }, { 3, 4 }, SIDE, false)
end
flush()
begin("Block_R3") -- far frontages along the avenue (simplified)
do
	local m = model(zone, "R3")
	row(m, "E", -894, -654, W1x1, { 30, 36 }, { 3, 5 }, AVS, false)
	row(m, "W", -894, -654, E1x0, { 30, 36 }, { 3, 5 }, AVS, false)
	row(m, "S", W1x0, W1x1 - 40, Z_C3a, { 30, 34 }, { 3, 5 }, SIDE, false)
end
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: unfinished concrete frames (FB1 side street, FB2 site) + tower crane + rubble [C 165 / 615 / 645 / 1095 / 1125]
begin("Construction")
local function frameBuilding(name, x0, z0, x1, z1, levels, pitch)
	local m = model(zone, name)
	local nx = math.max(2, math.floor((x1 - x0) / pitch + 0.5))
	local nz = math.max(2, math.floor((z1 - z0) / pitch + 0.5))
	local H = levels * ST + 0.45
	for i = 0, nx do
		for j = 0, nz do
			local x, z = x0 + (x1 - x0) * i / nx, z0 + (z1 - z0) * j / nz
			local top = H + ((rng:NextNumber() < 0.45) and 3.6 or 0) -- next level started [C 615 column stubs]
			box(m, x - 0.6, 0, z - 0.6, x + 0.6, top, z + 0.6, FRAME, M.Concrete)
		end
	end
	box(m, x0 - 0.4, -0.5, z0 - 0.4, x1 + 0.4, 0.45, z1 + 0.4, c3(166, 160, 150), M.Concrete) -- ground slab
	for s = 1, levels do
		local y = s * ST + 0.45
		box(m, x0 - 0.4, y - 1.4, z0 - 0.4, x1 + 0.4, y, z1 + 0.4, c3(166, 160, 150), M.Concrete) -- slab + edge beam [M 165]
	end
	for s = 0, 1 do -- partial brick infill on the lower two levels [C 165 / 645]
		local y0 = s * ST + 0.45
		for i = 0, nx - 1 do
			local xa, xb = x0 + (x1 - x0) * i / nx + 0.6, x0 + (x1 - x0) * (i + 1) / nx - 0.6
			if rng:NextNumber() < 0.6 then box(m, xa, y0, z1 - 0.7, xb, y0 + ST - 1.4 - ((rng:NextNumber() < 0.3) and 2.5 or 0), z1 - 0.1, BRICK, M.Brick) end
			if rng:NextNumber() < 0.5 then box(m, xa, y0, z0 + 0.1, xb, y0 + ST - 1.4, z0 + 0.7, BRICK, M.Brick) end
		end
		for j = 0, nz - 1 do
			local za, zb = z0 + (z1 - z0) * j / nz + 0.6, z0 + (z1 - z0) * (j + 1) / nz - 0.6
			if rng:NextNumber() < 0.5 then box(m, x1 - 0.7, y0, za, x1 - 0.1, y0 + ST - 1.4, zb, BRICK, M.Brick) end
		end
	end
	return H
end
frameBuilding("FB1_SideStreet", -346, -205, -314.6, -142, 6, 10.5)
frameBuilding("FB2_Site", 140, -35, 190, 2, 6, 12.5)
do -- tower crane ~2x the frame [C 615 / 1095 / 1125]
	local m = model(zone, "Crane")
	local cx, cz, Hc = 120, 6, 96
	local w = 2.8
	local CR, YEL = c3(56, 56, 58), c3(200, 170, 40)
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(m, cx + o[1] * w / 2 - 0.25, 0, cz + o[2] * w / 2 - 0.25, cx + o[1] * w / 2 + 0.25, Hc, cz + o[2] * w / 2 + 0.25, CR, M.Metal)
	end
	for y = 4, Hc - 7, 7 do
		part(m, Vector3.new(0.18, 0.18, w * 1.41), CFrame.new(cx - w / 2, y + 3.5, cz) * CFrame.Angles(math.rad(45), 0, 0), CR, M.Metal)
		part(m, Vector3.new(0.18, 0.18, w * 1.41), CFrame.new(cx + w / 2, y + 3.5, cz) * CFrame.Angles(math.rad(-45), 0, 0), CR, M.Metal)
		part(m, Vector3.new(w * 1.41, 0.18, 0.18), CFrame.new(cx, y + 3.5, cz + w / 2) * CFrame.Angles(0, 0, math.rad(45)), CR, M.Metal)
		part(m, Vector3.new(w * 1.41, 0.18, 0.18), CFrame.new(cx, y + 3.5, cz - w / 2) * CFrame.Angles(0, 0, math.rad(-45)), CR, M.Metal)
	end
	box(m, cx - 2, Hc, cz - 2, cx + 2, Hc + 3, cz + 2, YEL, M.Metal) -- slewing unit / cab
	box(m, cx - 60, Hc + 3, cz - 0.9, cx + 2, Hc + 5, cz + 0.9, YEL, M.Metal) -- jib (toward -X)
	box(m, cx + 2, Hc + 3, cz - 1, cx + 22, Hc + 4.5, cz + 1, YEL, M.Metal) -- counter-jib
	box(m, cx + 16, Hc - 1, cz - 1.6, cx + 21, Hc + 3, cz + 1.6, CONCRETE, M.Concrete) -- counterweight
	box(m, cx - 0.4, Hc + 3, cz - 0.4, cx + 0.4, Hc + 14, cz + 0.4, YEL, M.Metal) -- apex
	local apex = Vector3.new(cx, Hc + 14, cz)
	for _, tip in { Vector3.new(cx - 40, Hc + 5, cz), Vector3.new(cx + 20, Hc + 4.5, cz) } do
		local d = (tip - apex).Magnitude
		part(m, Vector3.new(0.12, 0.12, d), CFrame.lookAt(apex, tip) * CFrame.new(0, 0, -d / 2), METAL, M.Metal)
	end
	box(m, cx - 34.05, Hc - 37, cz - 0.05, cx - 33.95, Hc + 3, cz + 0.05, c3(40, 40, 40), M.Metal) -- hook cable
end
do
	local m = model(zone, "Rubble")
	for _, pile in { { 160, 30 }, { 128, -62 }, { -304, -185 }, { 176, -72 } } do
		for _ = 1, 7 do
			local s = rng:NextNumber(1.2, 3.2)
			part(m, Vector3.new(s * rng:NextNumber(1, 2), s, s * rng:NextNumber(1, 2)), CFrame.new(pile[1] + rng:NextNumber(-4, 4), s * 0.3, pile[2] + rng:NextNumber(-4, 4)) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6)), pick({ c3(170, 160, 146), c3(150, 140, 128), BRICK, c3(186, 176, 160) }), M.Concrete)
		end
	end
end
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: compounds, lane, guard post [C 1215 / 1245 plastered walls with pilasters, 1-2 storey houses; 975 corner]
begin("Compounds")
local function compoundWall(m, x0, z0, x1, z1, gate)
	local H, t = SPEC.WallH, 0.8
	local col = pick({ c3(200, 192, 176), c3(190, 182, 166), c3(210, 200, 182) })
	local function run(ax, c, a0, a1)
		local isGate = gate and gate.ax == ax and gate.c == c
		wallOpen(m, ax, c, a0, a1, 0, H, t, isGate and { { gate.a, 7, 0, H } } or {}, col, M.Plaster)
		local a = a0
		while a <= a1 + 0.01 do -- pilasters every ~10 studs, slightly taller [C 1245]
			if not (isGate and math.abs(a - gate.a) < 4.2) then
				if ax == "x" then box(m, a - 0.7, 0, c - 0.7, a + 0.7, H + 0.5, c + 0.7, col, M.Plaster)
				else box(m, c - 0.7, 0, a - 0.7, c + 0.7, H + 0.5, a + 0.7, col, M.Plaster) end
			end
			a += 10
		end
	end
	run("x", z0, x0, x1); run("x", z1, x0, x1); run("z", x0, z0, z1); run("z", x1, z0, z1)
end
do
	local m = model(zone, "CompoundA")
	compoundWall(m, -176, -84, -100, 48, { ax = "x", c = 48, a = -140 })
	building(m, -160, -60, -122, -28, 2, { "S", "W", "E" }, "plain", true, { name = "HouseA" })
	building(m, -150, 0, -120, 24, 1, { "S", "W" }, "plain", true, { name = "HouseA2" })
end
do
	local m = model(zone, "CompoundB")
	building(m, -290, -84, -197, -24, 2, { "E" }, "garage", true, { name = "LongBuilding", col = c3(176, 168, 156) }) -- [C 1245 left]
	compoundWall(m, -290, -20, -197, 48, { ax = "x", c = 48, a = -245 })
	building(m, -270, 0, -232, 30, 2, { "S", "E" }, "plain", true, { name = "HouseB" })
end
do -- guard post on the plaza's west side: the V4 corner with a rusty pipe [C 975]
	local m = model(zone, "GuardPost")
	building(m, -64, -20, -44, 6, 1, { "S", "E" }, "plain", true, { col = c3(170, 162, 150) })
	vcyl(m, -64.7, 0, 11, 7.4, 0.8, RUST, M.CorrodedMetal) -- at the south-west corner: on the left when looking +Z
end
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: highway (south-east), barriers, vehicles, street lights [C 255 / 975 / 285 / 615 / 435]
begin("RoadsProps")
do -- divided highway: median with double-arm lights, guardrails on posts, sand shoulders [C 255]
	local m = model(zone, "Highway")
	local a = Vector3.new(95, 0, 85)
	local dir = Vector3.new(0.72, 0, 0.69).Unit
	local L = 380
	local base = CFrame.lookAt(a, a + dir)
	local function seg(off, w, y0, y1, color, mat)
		part(m, Vector3.new(w, y1 - y0, L), base * CFrame.new(off, (y0 + y1) / 2, -L / 2), color, mat)
	end
	seg(-21, 30, -0.5, 0.085, ASPHALT, M.Asphalt)
	seg(21, 30, -0.5, 0.085, ASPHALT, M.Asphalt)
	seg(0, 12, -0.5, 0.1, SAND, M.Sand)
	seg(-44, 16, -0.5, 0.055, SAND, M.Sand)
	seg(44, 16, -0.5, 0.055, SAND, M.Sand)
	seg(-36.5, 0.3, 1.0, 1.8, c3(190, 190, 186), M.Metal)
	seg(36.5, 0.3, 1.0, 1.8, c3(190, 190, 186), M.Metal)
	for k = 0, 18 do
		for _, off in { -36.7, 36.7 } do part(m, Vector3.new(0.3, 1.8, 0.3), base * CFrame.new(off, 0.9, -10 - k * 20), METAL, M.Metal) end
	end
	for k = 1, 4 do
		local p = base * CFrame.new(0, 0, -k * 80)
		part(m, Vector3.new(0.5, 21, 0.5), p * CFrame.new(0, 10.5, 0), METAL, M.Metal)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(9, 0.3, 0.3), p * CFrame.new(s * 4.5, 20.5, 0), METAL, M.Metal)
			part(m, Vector3.new(1.6, 0.5, 0.8), p * CFrame.new(s * 8.6, 20.2, 0), c3(230, 230, 220), M.SmoothPlastic)
		end
	end
end
local function barrierRow(m, x0, z0, x1, z1) -- jersey barriers ~0.8 m x 3 m, gaps ~1 m [M 975]
	local d = Vector3.new(x1 - x0, 0, z1 - z0)
	local u = d.Unit
	for k = 0, math.floor(d.Magnitude / 10) - 1 do
		local c = Vector3.new(x0, 0, z0) + u * (k * 10 + 5)
		local cf = CFrame.lookAt(c, c + u)
		part(m, Vector3.new(1.6, 0.9, 7.5), cf * CFrame.new(0, 0.45, 0), BARRIER, M.Concrete)
		part(m, Vector3.new(0.7, 1.15, 7.5), cf * CFrame.new(0, 1.45, 0), BARRIER, M.Concrete)
	end
end
local function vehicle(m, x, z, yaw, kind, color) -- static shells at reference E-ratios (pickup ~1.2 E)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local L = (kind == "pickup") and 14.5 or 12.5
	part(m, Vector3.new(5, 2.4, L), cf * CFrame.new(0, 2.3, 0), color, M.SmoothPlastic)
	if kind == "pickup" then
		part(m, Vector3.new(4.8, 2.2, 5.2), cf * CFrame.new(0, 4.6, -1.2), color, M.SmoothPlastic)
		part(m, Vector3.new(4.9, 1.2, 4.6), cf * CFrame.new(0, 4.5, -1.1), GLASS, M.Glass)
	else
		part(m, Vector3.new(4.9, 2.4, 9.2), cf * CFrame.new(0, 4.7, 0.6), color, M.SmoothPlastic)
		part(m, Vector3.new(5.0, 1.3, 8.6), cf * CFrame.new(0, 4.6, 0.6), GLASS, M.Glass)
	end
	for _, o in { { -2.3, -L / 2 + 2.8 }, { 2.3, -L / 2 + 2.8 }, { -2.3, L / 2 - 2.8 }, { 2.3, L / 2 - 2.8 } } do
		part(m, Vector3.new(1.0, 2.4, 2.4), cf * CFrame.new(o[1], 1.2, o[2]), c3(28, 28, 28), M.Rubber, Enum.PartType.Cylinder)
	end
end
local function light(m, x, z, double, h)
	box(m, x - 0.25, 0, z - 0.25, x + 0.25, h, z + 0.25, METAL, M.Metal)
	for _, s in (double and { -1, 1 } or { 1 }) do
		box(m, x + s * 0.25, h - 0.65, z - 0.15, x + s * 6, h - 0.35, z + 0.15, METAL, M.Metal)
		box(m, x + s * 5.2, h - 1.05, z - 0.4, x + s * 6.8, h - 0.55, z + 0.4, c3(230, 230, 220), M.SmoothPlastic)
	end
end
do
	local m = model(zone, "Props")
	barrierRow(m, -85, 54, 105, 54) -- [C 975 / 1125 row along the road edge]
	barrierRow(m, 112, -84, 112, -20)
	vehicle(m, -58, 44, 90, "pickup", c3(232, 232, 228)) -- white pickup [C 15 / 975]
	vehicle(m, 128, 22, 15, "suv", c3(34, 34, 36)) -- dark SUV at the frame [C 615]
	vehicle(m, 30, -168, 0, "pickup", c3(210, 120, 30)) -- orange pickup at the curb [C 435 / 462]
	vehicle(m, -30, -262, 180, "suv", c3(60, 64, 70))
	vehicle(m, -186, -62, 0, "pickup", c3(150, 30, 30))
	light(m, 34, 50, false, 16) -- [C 975 streetlight]
	vcyl(m, 30, 0, 2.6, 51, 1.1, c3(190, 40, 30), M.SmoothPlastic) -- red bollard [C 975]
	light(m, -80, -80, false, 16)
	light(m, 100, -80, false, 16)
	for z = Z_C1b - 30, Z_END + 30, -72 do light(m, 0, z, true, 20) end -- avenue median [C 255 / 285]
end
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: vegetation [C 255 pines, 135 palms, 975 / 1005 / 1215 broadleaf, 1215 cypress + shrubs]
begin("Vegetation")
local function tree(m, x, z, kind)
	if kind == "pine" then
		local h = rng:NextNumber(26, 38)
		vcyl(m, x, 0, h, z, 1.2, TRUNK, M.Wood)
		ball(m, x, h * 0.55, z, 13, PINE); ball(m, x, h * 0.72, z, 9.5, PINE); ball(m, x, h * 0.88, z, 6, PINE)
	elseif kind == "palm" then
		local h = rng:NextNumber(18, 26)
		vcyl(m, x, 0, h, z, 0.9, TRUNK, M.Wood)
		for k = 0, 4 do
			part(m, Vector3.new(1.8, 0.2, 9), CFrame.new(x, h, z) * CFrame.Angles(0, k * 1.256, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, -4.2), c3(70, 96, 50), M.LeafyGrass)
		end
	elseif kind == "cypress" then
		local h = rng:NextNumber(22, 30)
		vcyl(m, x, 0.5, h - 2, z, 4.5, PINE, M.LeafyGrass)
		ball(m, x, h - 2, z, 4.5, PINE)
	elseif kind == "shrub" then
		local d = rng:NextNumber(5, 9)
		ball(m, x, d * 0.35, z, d, SHRUB)
	else
		local h = rng:NextNumber(14, 22)
		vcyl(m, x, 0, h * 0.7, z, 1.3, TRUNK, M.Wood)
		for _ = 1, 3 do ball(m, x + rng:NextNumber(-3, 3), h * 0.68 + rng:NextNumber(-1, 3), z + rng:NextNumber(-3, 3), rng:NextNumber(10, 15), LEAF) end
	end
end
do
	local m = model(zone, "Trees")
	for _, t in { { -40, 100, "broad" }, { -20, 128, "pine" }, { 5, 106, "broad" }, { 25, 135, "pine" }, { 32, 100, "broad" }, { -55, 135, "pine" }, { -10, 146, "broad" }, { 60, 150, "pine" }, { 78, 128, "broad" } } do tree(m, t[1], t[2], t[3]) end
	for _, t in { { -150, -10, "cypress" }, { -135, 35, "broad" }, { -112, -75, "cypress" }, { -170, 30, "shrub" }, { -165, -20, "shrub" }, { -258, 38, "broad" }, { -282, 12, "cypress" }, { -210, 40, "shrub" }, { -230, -10, "shrub" }, { -118, 40, "shrub" } } do tree(m, t[1], t[2], t[3]) end
	for z = -130, -340, -42 do tree(m, -41, z, "palm"); tree(m, 41, z - 20, "palm") end -- [C 135 palm-lined road]
	for _, t in { { 104, -70, "broad" }, { 104, -40, "pine" }, { 64, -80, "broad" }, { 84, -80, "pine" }, { 196, 60, "pine" }, { 180, -80, "broad" } } do tree(m, t[1], t[2], t[3]) end
	for _, t in { { -70, -172, "broad" }, { -64, -300, "broad" }, { -60, -190, "shrub" }, { -78, -255, "shrub" }, { -58, -290, "shrub" }, { -100, -310, "shrub" } } do tree(m, t[1], t[2], t[3]) end -- W1R1 lot [C 285 / 315 scrub]
	-- outskirts tree line north of the arterial, clear of the test ranges (z 89+) [C 255 / 1155]
	for k = 0, 14 do tree(m, -640 + k * 22 + rng:NextNumber(-6, 6), 30 + rng:NextNumber(-8, 8), (k % 2 == 0) and "pine" or "broad") end
end
flush()

------------------------------------------------------------------------------------------------------------------------
-- ZONE: skyline ring (non-enterable boxes, one window face toward the town) and distant hills [C 15 / 225 / 375 / 1215]
begin("Skyline")
do
	local m = model(zone, "FarBlocks")
	local function cluster(cx, cz, nb, spread, nRange)
		for _ = 1, nb do
			local w, d = rng:NextNumber(26, 60), rng:NextNumber(26, 50)
			local x, z = cx + rng:NextNumber(-spread, spread), cz + rng:NextNumber(-spread, spread)
			local face = (math.abs(x) > math.abs(z + 200)) and ((x > 0) and "W" or "E") or ((z > -200) and "N" or "S")
			building(m, x - w / 2, z - d / 2, x + w / 2, z + d / 2, rng:NextInteger(nRange[1], nRange[2]), { face }, "plain", false)
		end
	end
	cluster(0, -990, 9, 150, { 3, 6 })
	cluster(-780, -430, 8, 140, { 3, 5 })
	cluster(-770, -780, 7, 130, { 3, 6 })
	cluster(330, -570, 7, 80, { 3, 6 })
	cluster(380, 500, 6, 100, { 2, 4 })
	cluster(-430, -930, 5, 110, { 4, 7 })
	vcyl(m, -520, 0, 30, -760, 1.2, METAL, M.Metal) -- water tower [C 225]
	vcyl(m, -520, 28, 37, -760, 9, c3(190, 190, 186), M.Metal)
	box(m, 280, 0, -700, 288, 52, -692, c3(196, 186, 168), M.Plaster) -- a tower [C 225]
	box(m, 278, 52, -702, 290, 56, -690, c3(176, 166, 150), M.Concrete)
end
do
	local m = model(zone, "Hills")
	for _, h in { { -1700, -500, 600, 140 }, { -1600, -1300, 700, 180 }, { -900, -1700, 800, 120 }, { 600, -1700, 700, 150 }, { 1600, -900, 600, 110 } } do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = Vector3.new(h[3], h[4], h[3] * 0.5)
		w.CFrame = CFrame.lookAt(Vector3.new(h[1], h[4] / 2, h[2]), Vector3.new(0, h[4] / 2, 0)) * CFrame.new(0, 0, h[3] * 0.25)
		w.Color = c3(150, 140, 112)
		w.Material = M.Ground
		w.Parent = m
		local w2 = w:Clone()
		w2.CFrame = w.CFrame * CFrame.new(0, 0, h[3] * 0.5) * CFrame.Angles(0, math.pi, 0)
		w2.Parent = m
		count += 2
	end
end
flush()

local parts = 0
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then parts += 1 end
end
return string.format("%s built: %d parts (counter %d)", SPEC.Version, parts, count)
