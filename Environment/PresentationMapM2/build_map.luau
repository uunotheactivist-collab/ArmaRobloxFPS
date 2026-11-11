-- M2 presentation map (2026-11-10): Nuevo Laredo district rebase. Authoritative design:
-- Fidelity Audit 2026-11-10\map_m2\DESIGN_SPEC.md (S = 2.5 studs / reference m, north = -Z, east = +X, plain y = 0).
--
-- Edit-mode builder (command bar / execute_luau). Creates Workspace.PresentationMap_M2 (an existing M2 is destroyed
-- first), retires Workspace.PresentationMap_M1 to ServerStorage with attribute Retired = "M2" (never deleted) and touches
-- nothing else: no Lighting, SpawnLocation, Baseplate, test ranges or scripts. Parts only (Part / WedgePart): no Terrain,
-- decals, textures, unions or meshes; at most SPEC.MaxSigns SurfaceGui text signs with fictional generic Spanish words.
-- Every part is anchored; structures carry no BallisticSurface attribute (NonPenetrable, as M1). Decorative-only parts
-- (markings, wires, stains, sign faces, grime, leaves) are CanCollide / CanQuery off, thin ones also CastShadow off.
--
-- Passes (spec section 7): A skeleton, B massing, C street level, D materials / breakup (E = lighting evaluation only,
-- not built). SPEC.PASSES selects a subset. The layout plan always runs first from Random.new(SPEC.Seed); every pass
-- draws from its own Random.new(SPEC.Seed + k), so a subset builds exactly the geometry of the full run. A caller may set
-- _G.M2_BUILD_OVERRIDE = { PASSES = {...}, Fresh = bool } before running to build in several calls (cleared on read).
-- Labels: [SPEC x] = value fixed by the spec section x; "-- PARAMETER" = chosen here where the spec is silent.
-- v2 (coordinator refinement after tuning views V1-V8): organic ball crowns (plaza trees, mesquite, shrubs), individual
-- windows instead of storey bands (bars on ~60 % of ground-floor residential windows), terrace lip = 1.0 kerb wall + open
-- railing (was a solid 3.0 parapet, spec 4.2), sign bands on ~30 % of shops + painted boards, mid-tone sidewalks.
-- Layout, grid, scale and clear zones are unchanged (the plan draws are identical to v1).
-- v3 (coordinator, user-approved presentation pass): pass V adds a facade-detail kit on detailed buildings, two river
-- stairways down the scarp (railing openings), Persistent streaming on Bridge / Terrace / Backdrop and a 6.2-clear EB
-- roof-room door. Pass V draws only from Random.new(SPEC.SeedV3); every v3 container has attribute M2v3 = true. With
-- SPEC.V3 = false the file rebuilds v2 exactly; with V3 = true all v2 parts are unchanged except the replaced lip railing
-- and the EB roof-room south wall (both rebuilt inside M2v3 models).

local SPEC = {
	Version = "M2-v3",
	Seed = 20261112,
	PASSES = { A = true, B = true, C = true, D = true, V = true },
	V3 = true, SeedV3 = 20261113, -- v3 presentation pass (own RNG); V3 = false rebuilds v2 exactly
	Persistent = { "Bridge", "Terrace", "Backdrop" }, -- v3 ModelStreamingMode = Persistent (far content on the long axis)
	StairX = { -180, 230 }, StairW = 6, StairTread = 2.4, StairFlight = 10, StairFlights = 8, StairLanding = 2.5, StairTopLanding = 3.0, LipOpening = 8, -- PARAMETER v3 river stairs (80 risers of 0.599)
	Kit = { Coping = 0.6, Cornice = 0.4, Sills = 0.5, Door = 0.7, AC = 0.1, Pipe = 0.25, Balcony = 0.08 }, -- PARAMETER v3 facade-kit shares per detailed street face (AC per upper window)
	Fresh = true, -- destroy an existing M2 before building (an override may set false to add passes)
	S = 2.5, E = 4.05, -- studs per reference metre, eye height [SPEC 2]
	GF = 9.0, UF = 7.5, Parapet = 2.5, Barda = 5.5, -- ground / upper storey, parapet, perimeter wall [SPEC 4.3]
	DoorH = 6.2, DoorW = 4, -- [SPEC 2 / 5]
	Walk = 0.45, -- sidewalk / kerb top [SPEC 4.2 kerb 0.45]
	C1 = { cw = 16, sw = 5 }, Spine = { cw = 16, sw = 6 }, AVW = { cw = 24, med = 21, sw = 6 }, -- [SPEC 4.2]
	NS = { -- N-S street centrelines [SPEC 4.1]
		{ id = "AVW", x = -565, k = "avw" }, { id = "X410", x = -410, k = "c1" }, { id = "X255", x = -255, k = "c1" },
		{ id = "X100", x = -100, k = "c1" }, { id = "SPINE", x = 55, k = "spine" }, { id = "E1", x = 210, k = "c1" },
	},
	EW = { 60, -160, -380, -600, -810, -1000 }, -- E-W street centrelines Z0..Z5 [SPEC 4.1]
	Lip = -1024, ScarpFoot = -1224, Drop = 47.5, RiverNear = -1260, RiverFar = -1460, BridgeEnd = -1520, Deck = 32, -- [SPEC 4.1]
	Plaza = { x0 = -238, x1 = 36, z0 = -145, z1 = 45 }, -- [SPEC 4.1]
	TestArea = { x0 = -6, x1 = 36, z0 = -56, z1 = 6 }, -- flat paving only, top <= 0.1 [brief]
	TowerH = 130, -- tallest building 52 m [SPEC 4.3]
	Rail = { -640, -615 }, Yard = { x0 = -900, x1 = -660, z0 = -700, z1 = -120 }, -- [SPEC 4.1]
	Tract = { cx = 600, cz = -700, rot = 15, w = 115, l = 428, n = 3 }, -- [SPEC 4.1]
	Frontage = { 20, 37 }, Depth = { 40, 55 }, Setback = 1.0, -- plot frontage / depth [SPEC 4.3], setback 0-1 [brief]
	Tinaco = 0.35, Shutter = 0.5, Awning = 0.3, Bars = 0.6, ShedRoof = 0.10, -- [SPEC 4.3]
	MaxSigns = 80, -- SurfaceGui text cap [brief]
	-- PARAMETERS (the spec is silent; deliberate implementation choices, not Nuevo Laredo facts)
	E2Width = 128, -- PARAMETER east edge block column x 223..351 (core block width), no street on its east side
	E1R1East = 190, -- PARAMETER east edge of block E1R1 (MovementTest clearance: nothing in x 197-311 with z > -150)
	CornerDepth = 55, -- PARAMETER corner plots take the full depth so side-street frontages stay continuous
	RoofRoomH = 9.0, -- PARAMETER EB roof access room height to slab top
	LotShare = { plaza = 0.03, spine = 0.03, avw = 0.10, c1 = 0.13, edgeBlock = 0.28 }, -- PARAMETER walled lot / courtyard share
	ShopShare = { plaza = 0.85, spine = 0.8, avw = 0.7, c1d = 0.55, c1 = 0.35, edgeBlock = 0.2 }, -- PARAMETER ground-floor commercial
	EdgeStoreys = { 65, 30, 5, 0 }, -- PARAMETER 1:2:3:4 % for the east edge blocks (E2)
	MaterialMix = { block = 0.08, brick = 0.06, concrete = 0.08 }, -- PARAMETER share of exposed block / brick / grey concrete
	TowerFoot = { 100, -140, 136, -104 }, -- PARAMETER tower footprint 36 x 36 (14.4 m), 7 back from the Z1 facade line
	ChurchH = 30, ChurchTowerH = 70, -- PARAMETER nave 12 m, tower 28 m to the cross
	KioskD = 20, ClockTowerH = 36, -- PARAMETER kiosk platform diameter 8 m, clock tower 14.4 m
	WarehouseH = { 14, 20 }, -- PARAMETER logistics sheds 5.6-8 m eaves
	TractStreet = 24, TractHouseH = 7.5, -- PARAMETER tract street 9.6 m, 1-storey 3.0 m houses
	ParkingShare = 0.6, -- PARAMETER curb slots occupied by parked cars
	DashLen = 10, DashGap = 15, -- PARAMETER lane dash 4 m / gap 6 m (width 0.25 is [SPEC 4.2])
	PoleStep = 90, PoleH = 22.5, -- [SPEC 4.4]
	LipKerb = 1.0, LipRails = { 2.0, 3.0 }, LipPostStep = 8, -- PARAMETER v2 lip: kerb wall + open railing (coordinator; replaces the spec 4.2 solid 3.0 parapet)
	WinBay = { 9, 11 }, WinW = { 3.0, 3.75 }, WinH = { 3.5, 4.0 }, -- PARAMETER v2 individual windows (1.2-1.5 x 1.4-1.6 m) per bay
	WinFrameAll = false, -- PARAMETER v2 thin frames on detailed street faces only (true: every street face; budget)
	TowerWin = 3, -- PARAMETER v2 tower: individual windows per face and storey
	SignMix = { band = 0.3, board = 0.35 }, -- PARAMETER v2 shops: full-width band 30 %, painted board 35 %, nothing 35 %
	SignBottom = 5.5, -- [SPEC 4.2]
	BridgeWalk = 8, -- PARAMETER bridge walkways 8 + carriageway 16 = deck 32 [SPEC]
	PierStep = 62, -- PARAMETER 8 spans of 62 over scarp and river
}
local OV = _G.M2_BUILD_OVERRIDE
if type(OV) == "table" then
	if OV.PASSES then SPEC.PASSES = OV.PASSES end
	if OV.Fresh ~= nil then SPEC.Fresh = OV.Fresh end
	if OV.V3 ~= nil then SPEC.V3 = OV.V3 end
	_G.M2_BUILD_OVERRIDE = nil
end

local function c3(r, g, b) return Color3.fromRGB(r, g, b) end
local M = Enum.Material
local CALICHE, FLOOD, ASPHALT, PATCHC = c3(156, 146, 130), c3(102, 93, 80), c3(84, 84, 82), c3(64, 64, 62) -- ground [SPEC 4.3]
local SIDEWALK, KERB, PAVE, BEDC, LOTC = c3(158, 152, 140), c3(172, 168, 160), c3(184, 170, 150), c3(122, 118, 78), c3(150, 138, 118) -- v2 mid-tone walk, kerb lighter (PARAMETER)
local ROOF, SLAB, DARK, GLASS = c3(150, 144, 134), c3(160, 154, 144), c3(40, 38, 36), c3(46, 52, 56)
local METAL, RUST, BLACK, WHITE, LINE, YELLOW = c3(92, 94, 96), c3(116, 80, 58), c3(28, 28, 28), c3(232, 230, 222), c3(226, 224, 214), c3(214, 176, 46)
local TRUNK, MESQ, SHRUBC, NOPALC, DRYG, LAUREL = c3(84, 70, 56), c3(104, 112, 70), c3(112, 114, 76), c3(98, 120, 86), c3(170, 150, 104), c3(66, 92, 52)
local CONC, BLOCKG, BRICKC, WATER, BEDR = c3(168, 164, 156), c3(150, 148, 142), c3(150, 92, 70), c3(84, 96, 86), c3(70, 64, 56)
local SIGNC = { { c3(228, 224, 212), BLACK }, { c3(212, 182, 78), BLACK }, { c3(164, 58, 48), WHITE }, { c3(52, 84, 128), WHITE }, { c3(62, 108, 72), WHITE }, { c3(200, 118, 52), BLACK }, { c3(120, 40, 60), WHITE } }
local SHUTTERC = { c3(150, 150, 146), c3(124, 126, 128), c3(112, 84, 64), c3(96, 110, 104) }
local ZOCALO = { c3(120, 48, 40), c3(60, 76, 66), c3(92, 90, 86), c3(140, 100, 60), c3(50, 60, 84) }
local CARC = { c3(214, 214, 210), c3(160, 30, 30), c3(40, 42, 46), c3(150, 152, 156), c3(36, 60, 110), c3(220, 220, 214), c3(120, 110, 90), c3(90, 30, 30) }
local WORDS = { "FARMACIA", "CAMBIO", "ABARROTES", "LLANTERA", "REFACCIONES", "TORTILLERIA", "PAPELERIA", "FERRETERIA", "CARNICERIA",
	"ZAPATERIA", "MUEBLERIA", "OPTICA", "PANADERIA", "LAVANDERIA", "TALLER", "CREMERIA", "FRUTERIA", "TAQUERIA", "REGALOS", "ESTETICA",
	"CONSULTORIO", "MERCERIA", "DULCERIA", "CERRAJERIA", "VIDRIERIA", "PURIFICADORA", "LONCHERIA", "PELUQUERIA", "PINTURAS", "MATERIALES",
	"CELULARES", "IMPRENTA", "SE RENTA", "BILLAR", "MARISCOS", "COCINA ECONOMICA" }
-- fictional street plates: generic Spanish nouns (no real street or person names)
local STREETNAME = { AVW = "AV. PONIENTE", X410 = "CALLE ENCINO", X255 = "CALLE MEZQUITE", X100 = "CALLE NOGAL", SPINE = "AV. CENTRAL",
	E1 = "CALLE SAUCE", Z0 = "CALLE ARENA", Z1 = "CALLE CANTERA", Z2 = "CALLE ADOBE", Z3 = "CALLE TEJA", Z4 = "CALLE CAL", Z5 = "CALLE RIBERA" }

------------------------------------------------------------------------------------------------------------------------
-- helpers (from M1, adapted)
local count, lastYield = 0, 0
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
	if count - lastYield >= 500 then lastYield = count; task.wait() end
	return p
end
local function wedge(parent, size, cf, color, mat)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = mat or M.Concrete
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	count += 1
	return w
end
local function deco(p, thin) -- decorative only: ignored by movement, ballistics and LOS rays [SPEC 5]
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if thin then p.CastShadow = false end
	return p
end
local function box(parent, x0, y0, z0, x1, y1, z1, color, mat) -- axis-aligned, min / max corners
	if x1 < x0 then x0, x1 = x1, x0 end
	if z1 < z0 then z0, z1 = z1, z0 end
	return part(parent, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, mat)
end
local function vcyl(parent, x, y0, y1, z, d, color, mat) -- vertical cylinder
	return part(parent, Vector3.new(y1 - y0, d, d), CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, mat, Enum.PartType.Cylinder)
end
local function ball(parent, x, y, z, d, color)
	return part(parent, Vector3.new(d, d, d), CFrame.new(x, y, z), color, M.LeafyGrass, Enum.PartType.Ball)
end
local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
local function pick(r, t) return t[r:NextInteger(1, #t)] end
local function rn(r, a, b) return a + (b - a) * r:NextNumber() end
local function coverModel(parent, name, h) -- every cover-relevant prop: CoverHeight + ENV-01 class (1.4 / 2.9 / 4.6) [SPEC 2]
	local m = model(parent, name)
	m:SetAttribute("CoverHeight", math.floor(h * 100 + 0.5) / 100)
	m:SetAttribute("CoverClass", (h >= 4.6 and "standing") or (h >= 2.9 and "crouched") or (h >= 1.4 and "prone") or "none")
	return m
end

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
local FACEID = { N = Enum.NormalId.Front, S = Enum.NormalId.Back, W = Enum.NormalId.Left, E = Enum.NormalId.Right }
local signCount = 0
local function label(p, face, text, fg) -- SurfaceGui text on a sign face (capped)
	if signCount >= SPEC.MaxSigns then return false end
	signCount += 1
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 14
	g.LightInfluence = 1
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.SourceSansBold
	t.TextColor3 = fg
	t.Parent = g
	return true
end
local function H(n) return SPEC.GF + SPEC.UF * (n - 1) end -- roof slab top for n storeys (ground y = 0)

------------------------------------------------------------------------------------------------------------------------
-- layout (world studs) [SPEC 4.1 / 4.2]
local function HW(k) -- centreline -> facade line
	if k == "spine" then return SPEC.Spine.cw / 2 + SPEC.Spine.sw end
	if k == "avw" then return SPEC.AVW.cw + SPEC.AVW.med / 2 + SPEC.AVW.sw end -- 40.5
	return SPEC.C1.cw / 2 + SPEC.C1.sw -- 13
end
local function SWW(k) return (k == "spine" and SPEC.Spine.sw) or (k == "avw" and SPEC.AVW.sw) or SPEC.C1.sw end
local CWH = SPEC.C1.cw / 2 -- 8: half carriageway of every C1 / spine street
local NSX = {}
for _, s in SPEC.NS do NSX[s.id] = s end
local SPX = NSX.SPINE.x -- 55
local AVW_IN = SPEC.AVW.med / 2 -- 10.5: median half-width
local AVW_OUT = SPEC.AVW.med / 2 + SPEC.AVW.cw -- 34.5: outer kerb offset
local XW = NSX.AVW.x - AVW_OUT -- -599.5: west end of every E-W carriageway (AV-W west kerb)
local XWW = XW - SPEC.AVW.sw -- -605.5: AV-W west facade line
local ROWS, COLS = {}, {}
for i = 1, #SPEC.EW - 1 do
	ROWS[i] = { id = "R" .. i, z0 = SPEC.EW[i + 1] + HW("c1"), z1 = SPEC.EW[i] - HW("c1"), zs = SPEC.EW[i], zn = SPEC.EW[i + 1] }
end
local COLID = { "W4", "W3", "W2", "W1", "E1" }
for i = 1, #SPEC.NS - 1 do
	local w, e = SPEC.NS[i], SPEC.NS[i + 1]
	COLS[i] = { id = COLID[i], x0 = w.x + HW(w.k), x1 = e.x - HW(e.k), kW = w.k, kE = e.k }
end
COLS[6] = { id = "E2", x0 = NSX.E1.x + HW("c1"), x1 = NSX.E1.x + HW("c1") + SPEC.E2Width, kW = "c1", kE = "edge" }
local XE = { SPEC.E1R1East, COLS[6].x1, COLS[6].x1, COLS[6].x1, COLS[6].x1, COLS[6].x1 } -- east ends of Z0..Z5
local EWDIR = { 1, -1, 1, -1, 1, -1 } -- one-way E-W streets alternate (+1 eastbound) [SPEC 4.1 >= 85 % one-way]
local NSDIR = { AVW = 0, X410 = -1, X255 = 1, X100 = -1, SPINE = 1, E1 = -1 } -- +1 southbound (+Z); spine N->S [SPEC]
local NSROWS = { AVW = { 1, 5 }, X410 = { 1, 5 }, X255 = { 1, 5 }, X100 = { 2, 5 }, SPINE = { 1, 5 }, E1 = { 2, 5 } } -- X100 interrupted by the plaza
-- landmarks
local EB = { x0 = 9.5, x1 = 41, z0 = -203, z1 = -173, dx = 87.5, dz = -55 } -- M1 EB (x -78..-46.5, z -148..-118) moved to the Z1 x spine corner
local TF = SPEC.TowerFoot
local TOWER = { x0 = TF[1], z0 = TF[2], x1 = TF[3], z1 = TF[4] }
local CH = { nave = { -58, -920, 5, -890 }, tower = { -5, -932, 7, -920 }, atrium = { 7, -930, 41, -880 }, dome = { -40, -905 } } -- block W1R5, facing the spine
local KIOSK = { x = (SPEC.Plaza.x0 + SPEC.Plaza.x1) / 2, z = -50 } -- plaza centre (-101, -50)
local CLOCK = { x = -214, z = -50 } -- PARAMETER clock tower on the plaza's west axis
local BEDS = { { -210, -128, -130, -72 }, { -210, -28, -130, 28 }, { -72, -128, -14, -72 }, { -72, -28, -14, 28 } } -- PARAMETER plaza beds (x0, z0, x1, z1), clear of the test area
local PLAZAB = { id = "PLAZA", x0 = -242, x1 = 41, z0 = -147, z1 = 47, sw = { N = 5, S = 5, W = 5, E = 6 }, ext = { N = 2, S = 2, W = 4, E = 5 } }
local TRACT_C = Vector3.new(645, 0, SPEC.Tract.cz) -- PARAMETER centre x 645 (spec ~600) so the rotated tract clears block E2 (x <= 351)
local function groundY(z) -- terrain height on the terrace / scarp / bank / river bed
	if z >= SPEC.Lip then return 0 end
	if z >= SPEC.ScarpFoot then return -SPEC.Drop * (SPEC.Lip - z) / (SPEC.Lip - SPEC.ScarpFoot) end
	if z >= SPEC.RiverNear then return -SPEC.Drop end
	if z >= SPEC.RiverFar then return -54 end
	return -SPEC.Drop
end

------------------------------------------------------------------------------------------------------------------------
-- PLAN: blocks, plots, edges (no parts; always runs; Random.new(SPEC.Seed))
local rng = Random.new(SPEC.Seed)
local BLOCKS, PLOTS, EDGES, LOTS = {}, {}, {}, {}
local CLSP = { plaza = 5, spine = 4, avw = 3, c1 = 2, edge = 1 }
local DIST_P, DIST_O = { 20, 50, 25, 5 }, { 45, 40, 15, 0 } -- storeys 1:2:3:4 % spine/plaza vs other centro [SPEC 4.3]
for ri = 1, #ROWS do
	for ci = 1, #COLS do
		local R, C = ROWS[ri], COLS[ci]
		if not (ri == 1 and (C.id == "W1" or C.id == "W2" or C.id == "E2")) then -- W1/W2 x R1 = plaza; E2 starts at R2
			local b = { id = "B_" .. C.id .. "_" .. R.id, col = C.id, row = ri, x0 = C.x0, x1 = C.x1, z0 = R.z0, z1 = R.z1, plots = {},
				cls = { N = "c1", S = "c1", W = C.kW, E = C.kE }, edgeBlock = (C.id == "E2"),
				sw = { N = SPEC.C1.sw, S = SPEC.C1.sw, W = (C.kW == "edge") and 0 or SWW(C.kW), E = (C.kE == "edge") and 0 or SWW(C.kE) } }
			if b.id == "B_E1_R1" then b.x1 = SPEC.E1R1East; b.cls.E = "edge"; b.sw.E = 0 end
			if b.id == "B_W1_R2" or b.id == "B_W2_R2" then b.cls.S = "plaza" end
			if b.id == "B_W3_R1" then b.cls.E = "plaza" end
			table.insert(BLOCKS, b)
		end
	end
end
local function faceDetail(b, f) -- full street-level detail: spine, plaza, Z1 (V7/V8) and X255 by the plaza (V3)
	local c = b.cls[f]
	if c == "plaza" or c == "spine" then return true end
	if (f == "N" and b.row == 1) or (f == "S" and b.row == 2) then return true end
	if (b.col == "W3" and f == "E" and b.row <= 2) or (b.col == "W2" and f == "W" and b.row == 2) then return true end
	return false
end
local function storeys(dist)
	local u = rng:NextNumber() * 100
	for n = 1, 4 do
		u -= dist[n]
		if u < 0 then return n end
	end
	return 1
end
local HUES = { { 0.09, 0.13 }, { 0.04, 0.07 }, { 0.11, 0.15 }, { 0.96, 1.0 }, { 0.22, 0.32 }, { 0.52, 0.60 }, { 0.07, 0.10 }, { 0, 0 } }
local function plaster(r) -- muted painted plaster, saturation <= 0.35 [SPEC 4.3]
	local h = pick(r, HUES)
	if h[2] == 0 then return Color3.fromHSV(0.1, 0.03, rn(r, 0.72, 0.9)) end
	return Color3.fromHSV(rn(r, h[1], h[2]) % 1, rn(r, 0.10, 0.35), rn(r, 0.62, 0.88))
end
local nameIdx = {}
local function makePlot(b, f, a0, a1, corner, dR)
	local r = rng
	local side = corner and ((corner == "lo") and "W" or "E") or nil
	local d = corner and SPEC.CornerDepth or rn(r, dR[1], dR[2])
	local s = rn(r, 0, SPEC.Setback)
	local p = { b = b, f = f, faces = { f } }
	if f == "N" then p.x0, p.x1, p.z0, p.z1 = a0, a1, b.z0 + s, b.z0 + d
	elseif f == "S" then p.x0, p.x1, p.z0, p.z1 = a0, a1, b.z1 - d, b.z1 - s
	elseif f == "W" then p.x0, p.x1, p.z0, p.z1 = b.x0 + s, b.x0 + d, a0, a1
	else p.x0, p.x1, p.z0, p.z1 = b.x1 - d, b.x1 - s, a0, a1 end
	if side then
		local s2 = rn(r, 0, SPEC.Setback)
		if side == "W" then p.x0 = b.x0 + s2 else p.x1 = b.x1 - s2 end
		if b.cls[side] ~= "edge" then table.insert(p.faces, side) end
	end
	local cls = "edge"
	p.detail = {}
	p.anyDetail = false
	for _, ff in p.faces do
		if CLSP[b.cls[ff]] > CLSP[cls] then cls = b.cls[ff] end
		p.detail[ff] = faceDetail(b, ff)
		p.anyDetail = p.anyDetail or p.detail[ff]
	end
	p.cls = cls
	local key = b.edgeBlock and "edgeBlock" or ((cls == "edge") and "c1" or cls)
	p.kind = "building"
	if not corner and r:NextNumber() < SPEC.LotShare[key] then p.kind = (r:NextNumber() < 0.5) and "lot" or "court" end
	p.n = storeys((cls == "plaza" or cls == "spine") and DIST_P or (b.edgeBlock and SPEC.EdgeStoreys or DIST_O))
	local shopKey = (key == "c1" and p.anyDetail) and "c1d" or key
	p.shop = r:NextNumber() < SPEC.ShopShare[shopKey]
	if p.kind == "lot" then p.n, p.shop, p.use = 0, false, "walled lot"
	elseif p.kind == "court" then p.n, p.shop, p.use = 1, false, "courtyard house"
	else p.use = p.shop and ((p.n >= 2) and "shop + flats" or "shop") or "house" end
	p.H = (p.kind == "lot") and SPEC.Barda or H(math.max(p.n, 1))
	if p.kind ~= "building" then -- gate in the street barda (planned here so passes B and C agree)
		p.gw = (p.kind == "court") and 4.5 or 7.5
		local g0, g1 = (f == "N" or f == "S") and p.x0 or p.z0, (f == "N" or f == "S") and p.x1 or p.z1
		p.gate = rn(r, g0 + p.gw / 2 + 2, g1 - p.gw / 2 - 2)
	end
	local u, mm = r:NextNumber(), SPEC.MaterialMix
	local t = r:NextNumber()
	if u < mm.block then p.mat, p.col = M.Concrete, BLOCKG:Lerp(c3(128, 126, 120), t) -- exposed block
	elseif u < mm.block + mm.brick then p.mat, p.col = M.Brick, BRICKC:Lerp(c3(168, 118, 94), t)
	elseif u < mm.block + mm.brick + mm.concrete then p.mat, p.col = M.Concrete, CONC:Lerp(c3(190, 184, 172), t)
	else p.mat, p.col = M.Plaster, plaster(r) end
	-- ~10 % sheet-metal sheds, all on 1-2 storey buildings (~2/3 of the stock) [SPEC 4.3]
	p.roof = (p.kind == "building" and p.n <= 2 and r:NextNumber() < 0.15) and "shed" or "flat"
	-- tinacos on ~35 % of houses / shops; only flat roofs carry them, hence 0.39 on flat roofs [SPEC 4.3]
	p.tinaco = (p.kind == "building" and p.roof == "flat" and r:NextNumber() < 0.39)
	p.tf = { rn(r, 0.25, 0.75), rn(r, 0.55, 0.8) }
	nameIdx[b.id] = (nameIdx[b.id] or 0) + 1
	p.name = string.format("P%02d_%s", nameIdx[b.id], table.concat(p.faces))
	table.insert(b.plots, p)
	table.insert(PLOTS, p)
	if p.kind ~= "building" then table.insert(LOTS, p) end
end
local function genFace(b, f, a0, a1, cLo, cHi, dR)
	local cuts, a = {}, a0
	local F = SPEC.Frontage
	while a1 - a > 0.01 do
		local rem = a1 - a
		-- PARAMETER: a remainder of 37-40 cannot split into two >= 20 plots and stays one plot (<= 40)
		local w = (rem < 40) and rem or rn(rng, F[1], math.min(F[2], rem - F[1]))
		table.insert(cuts, { a, a + w })
		a += w
	end
	for i, c in cuts do
		makePlot(b, f, c[1], c[2], (i == 1 and cLo) and "lo" or ((i == #cuts and cHi) and "hi" or nil), dR)
	end
end
local D, CD = SPEC.Depth, SPEC.CornerDepth
for _, b in BLOCKS do
	local dW = (b.x1 - b.x0 < 110) and { 36, 46 } or D -- PARAMETER narrow AV-W column (101.5 wide)
	if b.id == "B_W1_R2" then -- EB holds the Z1 x spine corner [SPEC 5]
		genFace(b, "N", b.x0, b.x1, true, true, D)
		genFace(b, "S", b.x0, EB.x0, true, false, D)
		genFace(b, "W", b.z0 + CD, b.z1 - CD, false, false, dW)
		genFace(b, "E", b.z0 + CD, EB.z0, false, false, dW)
	elseif b.id == "B_W1_R5" then -- church + atrium face the spine [SPEC 4.1]
		genFace(b, "N", b.x0, b.x1, true, true, D)
		genFace(b, "S", b.x0, b.x1, true, true, D)
		genFace(b, "W", b.z0 + CD, b.z1 - CD, false, false, { 22, 25 })
	elseif b.id == "B_E1_R1" then -- the tower stands on the Z1 frontage [SPEC 4.3]
		genFace(b, "N", b.x0, TOWER.x0 - 2, true, false, D)
		genFace(b, "N", TOWER.x1 + 2, b.x1, false, true, D)
		genFace(b, "S", b.x0, b.x1, true, true, D)
		genFace(b, "W", b.z0 + CD, b.z1 - CD, false, false, dW)
	else
		genFace(b, "N", b.x0, b.x1, true, true, D)
		genFace(b, "S", b.x0, b.x1, true, true, D)
		genFace(b, "W", b.z0 + CD, b.z1 - CD, false, false, dW)
		if b.cls.E ~= "edge" then genFace(b, "E", b.z0 + CD, b.z1 - CD, false, false, dW) end
	end
	if b.cls.E == "edge" then table.insert(EDGES, { b = b, x = b.x1, z0 = b.z0 + CD, z1 = b.z1 - CD }) end
end

------------------------------------------------------------------------------------------------------------------------
-- root, groups
local GROUPS = { "Ground", "Streets", "Plaza", "Terrace", "Bridge", "Blocks", "Landmarks", "Logistics", "Tract", "Backdrop",
	"Utilities", "Signage", "Vegetation", "Props", "Breakup" }
local SS = game:GetService("ServerStorage")
local root = workspace:FindFirstChild("PresentationMap_M2")
if root and SPEC.Fresh then root:Destroy(); root = nil end
local m1 = workspace:FindFirstChild("PresentationMap_M1")
if m1 then -- retired, not deleted; rollback = move it back to Workspace [SPEC 1]
	m1:SetAttribute("Retired", "M2")
	m1.Parent = SS
end
if not root then
	root = Instance.new("Model")
	root.Name = "PresentationMap_M2"
	root.Parent = workspace
end
root:SetAttribute("Layer", "M2 presentation map: Nuevo Laredo centro district rebase (parts only, Edit-mode builder)")
root:SetAttribute("Version", SPEC.Version)
root:SetAttribute("Seed", SPEC.Seed)
root:SetAttribute("Scale", "S = 2.5 studs / reference m (eye-anchored)")
root:SetAttribute("Builder", "Roblox/Environment/PresentationMapM2/build_map.luau")
root:SetAttribute("Spec", "Fidelity Audit 2026-11-10/map_m2/DESIGN_SPEC.md")
root:SetAttribute("Disable", "move this Model to ServerStorage")
root:SetAttribute("MapLayer", "M2")
local G = {}
for _, n in GROUPS do G[n] = root:FindFirstChild(n) or model(root, n) end
if SPEC.V3 then -- v3: far content on the long axis always streamed (Workspace streaming settings untouched)
	for _, n in SPEC.Persistent do G[n].ModelStreamingMode = Enum.ModelStreamingMode.Persistent end
end
local function newm(name) -- off-DataModel chunk
	local m = Instance.new("Model")
	m.Name = name
	return m
end
local function flush(m, group) -- parent one chunk (kept well under 1,000 parts) and yield
	m.Parent = G[group]
	task.wait()
end
local function setB(m, n, h, use)
	m:SetAttribute("Storeys", n)
	m:SetAttribute("Height", math.floor(h * 100 + 0.5) / 100)
	m:SetAttribute("Use", use)
end
local function plotModel(p, create) -- the building / lot model (Blocks/<block>/<plot>)
	local bm = G.Blocks:FindFirstChild(p.b.id)
	if not bm then
		if not create then return nil end
		bm = model(G.Blocks, p.b.id)
	end
	local m = bm:FindFirstChild(p.name)
	if not m and create then
		m = model(bm, p.name)
		setB(m, p.n, p.H, p.use)
	end
	return m
end

------------------------------------------------------------------------------------------------------------------------
-- PASS A: geographic skeleton (ground, streets, sidewalks, kerbs, plaza, terrace / scarp, river, bridge, parcels)
local function passA()
	local r = Random.new(SPEC.Seed + 1)
	local Y = SPEC.Walk
	-- plain: caliche slabs at top 0.02 over the Baseplate, kept out of the MovementTest / MP7Test clearances
	local g = newm("Plain")
	box(g, -1024, -1, SPEC.Lip, SPEC.E1R1East, 0.02, 76, CALICHE, M.Ground)
	box(g, SPEC.E1R1East, -1, SPEC.Lip, 400, 0.02, -152, CALICHE, M.Ground)
	box(g, 400, -1, SPEC.Lip, 1024, 0.02, -350, CALICHE, M.Ground)
	flush(g, "Ground")
	local pc = newm("Parcels") -- block interiors (seen from roofs), top 0.035
	for _, b in BLOCKS do
		box(pc, b.x0 + 1, -0.4, b.z0 + 1, b.x1 - ((b.sw.E > 0) and 1 or 0), 0.035, b.z1 - 1, LOTC:Lerp(CALICHE, r:NextNumber()), M.Ground)
	end
	box(pc, TOWER.x0 - 2, -0.4, -146, TOWER.x1 + 2, Y, TOWER.z0, SIDEWALK, M.Concrete) -- tower forecourt
	flush(pc, "Ground")

	-- carriageways: E-W tops 0.08 (continuous through intersections), N-S segments 0.07 between them
	local cw = newm("Carriageways")
	for i, z in SPEC.EW do box(cw, XW, -0.4, z - CWH, XE[i], 0.08, z + CWH, ASPHALT, M.Asphalt) end
	for _, s in SPEC.NS do
		local rr = NSROWS[s.id]
		for ri = rr[1], rr[2] do
			local R = ROWS[ri]
			if s.k == "avw" then
				box(cw, s.x - AVW_OUT, -0.4, R.zn + CWH, s.x - AVW_IN, 0.07, R.zs - CWH, ASPHALT, M.Asphalt)
				box(cw, s.x + AVW_IN, -0.4, R.zn + CWH, s.x + AVW_OUT, 0.07, R.zs - CWH, ASPHALT, M.Asphalt)
				box(cw, s.x - AVW_IN, -0.4, R.zn + CWH, s.x + AVW_IN, 0.6, R.zs - CWH, BEDC:Lerp(CALICHE, 0.4), M.Ground) -- median
			else
				box(cw, s.x - CWH, -0.4, R.zn + CWH, s.x + CWH, 0.07, R.zs - CWH, ASPHALT, M.Asphalt)
			end
		end
	end
	box(cw, SPX - CWH, -0.4, SPEC.Lip, SPX + CWH, 0.07, SPEC.EW[6] - CWH, ASPHALT, M.Asphalt) -- spine to the bridgehead
	box(cw, SPEC.Yard.x1, -0.4, SPEC.EW[3] - CWH, XW, 0.08, SPEC.EW[3] + CWH, ASPHALT, M.Asphalt) -- yard access road
	box(cw, COLS[6].x1, -0.4, SPEC.EW[6] - CWH, COLS[6].x1 + 15, 0.05, SPEC.EW[2] + CWH, c3(132, 120, 100), M.Ground) -- unpaved edge track
	flush(cw, "Streets")

	-- sidewalks (top 0.45) + kerbs (0.3 band, 0.02 proud and higher: no coplanar faces) around every block
	local sw = newm("Sidewalks")
	local K = 0.3
	local function swc() -- v2: per-segment mid concrete tone, RGB ~150-166 grey-tan (PARAMETER)
		return c3(150, 146, 136):Lerp(c3(166, 158, 144), r:NextNumber())
	end
	local function ring(b, ext)
		local w = b.sw
		local X0, X1, Z0, Z1 = b.x0 - w.W, b.x1 + w.E, b.z0 - w.N, b.z1 + w.S
		if w.N > 0 then box(sw, X0, -0.4, Z0, X1, Y, b.z0 + ext.N, swc(), M.Concrete) end
		if w.S > 0 then box(sw, X0, -0.4, b.z1 - ext.S, X1, Y, Z1, swc(), M.Concrete) end
		local za, zb = (w.N > 0) and (b.z0 + ext.N) or b.z0, (w.S > 0) and (b.z1 - ext.S) or b.z1
		if w.W > 0 then box(sw, X0, -0.4, za, b.x0 + ext.W, Y, zb, swc(), M.Concrete) end
		if w.E > 0 then box(sw, b.x1 - ext.E, -0.4, za, X1, Y, zb, swc(), M.Concrete) end
		if w.N > 0 then box(sw, X0 - (w.W > 0 and 0.02 or 0), -0.4, Z0 - 0.02, X1 + (w.E > 0 and 0.02 or 0), Y + 0.02, Z0 + K, KERB, M.Concrete) end
		if w.S > 0 then box(sw, X0 - (w.W > 0 and 0.02 or 0), -0.4, Z1 - K, X1 + (w.E > 0 and 0.02 or 0), Y + 0.02, Z1 + 0.02, KERB, M.Concrete) end
		local ka, kb = Z0 + ((w.N > 0) and K or 0), Z1 - ((w.S > 0) and K or 0)
		if w.W > 0 then box(sw, X0 - 0.02, -0.4, ka, X0 + K, Y + 0.02, kb, KERB, M.Concrete) end
		if w.E > 0 then box(sw, X1 - K, -0.4, ka, X1 + 0.02, Y + 0.02, kb, KERB, M.Concrete) end
	end
	local one = { N = 1, S = 1, W = 1, E = 1 }
	for _, b in BLOCKS do ring(b, one) end
	ring(PLAZAB, PLAZAB.ext)
	local z0s = SPEC.EW[1] + CWH -- Z0 south side (the slice's south edge, <= 76) [SPEC 5]
	box(sw, XWW, -0.4, z0s, SPEC.E1R1East, Y, z0s + SPEC.C1.sw, swc(), M.Concrete)
	box(sw, XWW, -0.4, z0s - 0.02, SPEC.E1R1East, Y + 0.02, z0s + K, KERB, M.Concrete)
	for _, zz in { { SPEC.EW[6] - CWH, SPEC.EW[3] - CWH }, { SPEC.EW[3] + CWH, z0s } } do -- AV-W west sidewalk (yard road gap)
		box(sw, XWW, -0.4, zz[1], XW, Y, zz[2], swc(), M.Concrete)
		box(sw, XW - K, -0.4, zz[1], XW + 0.02, Y + 0.02, zz[2], KERB, M.Concrete)
	end
	for _, xx in { { SPX - SPEC.Deck / 2, SPX - CWH }, { SPX + CWH, SPX + SPEC.Deck / 2 } } do -- spine sidewalks to the bridge
		box(sw, xx[1], -0.4, SPEC.Lip, xx[2], Y, SPEC.EW[6] - CWH, swc(), M.Concrete)
	end
	flush(sw, "Streets")

	-- plaza: paving (top 0.06, test area flat) + four raised beds [SPEC 4.1]
	local pl = newm("Paving")
	local P = SPEC.Plaza
	box(pl, P.x0, -0.3, P.z0, P.x1, 0.06, P.z1, PAVE, M.Pavement)
	for _, bd in BEDS do box(pl, bd[1], -0.3, bd[2], bd[3], 0.5, bd[4], BEDC, M.Grass) end
	flush(pl, "Plaza")

	-- terrace: lip promenade + low kerb wall and open railing (v2), scarp (47.5 over 200 = 13.4 deg), bank, river, far bank
	-- [SPEC 4.1 / 4.2; the spec's solid 3.0 parapet hid the drop from eye height (V6) and was replaced on coordinator request]
	local t = newm("Terrace_A")
	local zn = SPEC.EW[6] - CWH -- -1008
	for _, xx in { { XWW, SPX - SPEC.Deck / 2 }, { SPX + SPEC.Deck / 2, COLS[6].x1 } } do
		box(t, xx[1], -0.4, SPEC.Lip + 0.6, xx[2], Y, zn, swc(), M.Concrete)
		box(t, xx[1], -0.4, zn - K, xx[2], Y + 0.02, zn + 0.02, KERB, M.Concrete)
		if not SPEC.V3 then -- v2 lip railing (v3 rebuilds it with the river-stair openings in pass V)
			box(t, xx[1], -0.4, SPEC.Lip, xx[2], Y + SPEC.LipKerb, SPEC.Lip + 0.6, CONC, M.Concrete) -- kerb wall (prone cover)
			local zr = SPEC.Lip + 0.3
			local n = math.max(1, math.floor((xx[2] - xx[1]) / SPEC.LipPostStep + 0.5))
			for k = 0, n do -- posts (thin: ignored by LOS / ballistics)
				local x = math.clamp(xx[1] + (xx[2] - xx[1]) * k / n, xx[1] + 0.15, xx[2] - 0.15)
				box(t, x - 0.12, Y + SPEC.LipKerb, zr - 0.12, x + 0.12, Y + SPEC.LipRails[2] + 0.12, zr + 0.12, METAL, M.Metal).CanQuery = false
			end
			for _, hr in SPEC.LipRails do -- rails: collide (barrier), not queryable
				box(t, xx[1], Y + hr - 0.06, zr - 0.06, xx[2], Y + hr + 0.06, zr + 0.06, METAL, M.Metal).CanQuery = false
			end
		end
	end
	local scarpD = SPEC.Lip - SPEC.ScarpFoot
	wedge(t, Vector3.new(2048, SPEC.Drop, scarpD), CFrame.new(0, -SPEC.Drop / 2, (SPEC.Lip + SPEC.ScarpFoot) / 2), CALICHE:Lerp(FLOOD, 0.3), M.Ground)
	box(t, -1024, -56, SPEC.RiverNear, 1024, -SPEC.Drop, SPEC.ScarpFoot, FLOOD, M.Ground) -- near bank
	box(t, -1024, -SPEC.Drop, -1250, 1024, -SPEC.Drop + 0.06, -1238, FLOOD:Lerp(BEDR, 0.4), M.Ground) -- floodplain track (unpaved)
	box(t, -1024, -62, SPEC.RiverFar - 2, 1024, -54, SPEC.RiverNear + 2, BEDR, M.Mud) -- river bed
	local wtr = deco(box(t, -1024, -50.5, SPEC.RiverFar, 1024, -49, SPEC.RiverNear, WATER, M.SmoothPlastic), false)
	wtr.Transparency, wtr.Reflectance = 0.12, 0.08
	box(t, -1024, -56, -1490, 1024, -SPEC.Drop, SPEC.RiverFar, FLOOD, M.Ground) -- far floodplain
	wedge(t, Vector3.new(2048, SPEC.Drop, 150), CFrame.new(0, -SPEC.Drop / 2, -1565) * CFrame.Angles(0, math.pi, 0), CALICHE:Lerp(FLOOD, 0.3), M.Ground)
	box(t, -1024, -4, -2000, 1024, 0, -1640, CALICHE:Lerp(FLOOD, 0.15), M.Ground) -- far terrace (Laredo side)
	flush(t, "Terrace")

	-- bridge: 32 deck at y 0 from the lip to z -1520 on piers over scarp and river [SPEC 4.1]
	local br = newm("Deck")
	local bx0, bx1 = SPX - SPEC.Deck / 2, SPX + SPEC.Deck / 2
	local zA, zB = SPEC.BridgeEnd, SPEC.Lip
	box(br, bx0, -3, zA, bx1, 0, zB, CONC, M.Concrete)
	box(br, SPX - CWH, 0, zA, SPX + CWH, 0.08, zB, ASPHALT, M.Asphalt)
	box(br, bx0, 0, zA, SPX - CWH, Y, zB, swc(), M.Concrete)
	box(br, SPX + CWH, 0, zA, bx1, Y, zB, swc(), M.Concrete)
	for _, s in { -1, 1 } do
		local xo = (s < 0) and bx0 or bx1 - 0.8
		box(br, xo, Y, zA, xo + 0.8, Y + 1.5, zB, CONC, M.Concrete) -- parapet
		box(br, xo + 0.2, Y + 2.2, zA, xo + 0.6, Y + 2.45, zB, METAL, M.Metal) -- top rail (1.17 m)
		for z = zB - 15.5, zA + 1, -31 do box(br, xo + 0.25, Y + 1.5, z - 0.15, xo + 0.55, Y + 2.2, z + 0.15, METAL, M.Metal) end
	end
	for k = 1, math.floor((zB - zA) / SPEC.PierStep) - 1 do
		local z = zB - k * SPEC.PierStep
		local base = groundY(z) - 1
		for _, x in { SPX - 9, SPX + 9 } do vcyl(br, x, base, -4.5, z, 4, CONC, M.Concrete) end
		box(br, bx0 + 1, -4.5, z - 1.6, bx1 - 1, -3, z + 1.6, CONC, M.Concrete)
	end
	box(br, SPX - 24, -SPEC.Drop, -1640, SPX + 24, 0, zA, CALICHE:Lerp(CONC, 0.4), M.Concrete) -- far abutment / embankment
	box(br, SPX - CWH, 0, -1700, SPX + CWH, 0.08, zA, ASPHALT, M.Asphalt)
	flush(br, "Bridge")

	-- logistics skeleton: double track, level crossing, unpaved yard [SPEC 4.1]
	local lg = newm("Rail_Yard")
	local RZ0, RZ1 = -990, 40 -- PARAMETER rail extent
	local Ra = SPEC.Rail
	box(lg, Ra[1], -0.4, RZ0, Ra[2], 0.6, RZ1, c3(122, 114, 102), M.Slate) -- ballast bed
	for _, tx in { -632, -622 } do
		for _, s in { -1.8, 1.8 } do box(lg, tx + s - 0.2, 0.6, RZ0, tx + s + 0.2, 1.0, RZ1, METAL, M.Metal) end
		box(lg, tx - 2.6, 0.6, RZ0, tx + 2.6, 2.6, RZ0 + 1.5, YELLOW, M.Metal) -- buffer stop
	end
	box(lg, Ra[1], 0.6, SPEC.EW[3] - CWH, Ra[2], 0.95, SPEC.EW[3] + CWH, c3(90, 88, 84), M.Asphalt) -- crossing deck
	local Yd = SPEC.Yard
	box(lg, Yd.x0, -0.4, Yd.z0, Yd.x1, 0.03, Yd.z1, c3(146, 132, 110), M.Ground)
	box(lg, Yd.x0, -0.4, SPEC.EW[3] - CWH, Yd.x1, 0.045, SPEC.EW[3] + CWH, c3(126, 114, 96), M.Ground)
	flush(lg, "Logistics")

	-- tract (backdrop): 3 blocks 115 x 428 rotated 15 deg, streets between [SPEC 4.1]
	local tr = newm("Tract_A")
	local T = SPEC.Tract
	local base = CFrame.new(TRACT_C) * CFrame.Angles(0, math.rad(T.rot), 0)
	local pitch = T.w + SPEC.TractStreet
	for i = -1, 1 do part(tr, Vector3.new(T.w, 0.43, T.l), base * CFrame.new(i * pitch, -0.18, 0), CALICHE:Lerp(LOTC, 0.5), M.Ground) end
	for k = 0, 3 do part(tr, Vector3.new(SPEC.TractStreet, 0.48, T.l + 24), base * CFrame.new((k - 1.5) * pitch, -0.16, 0), ASPHALT, M.Asphalt) end
	flush(tr, "Tract")
end

------------------------------------------------------------------------------------------------------------------------
-- PASS B: massing (building volumes, walls, roofs, tower, church, EB, kiosk, clock tower, warehouses, tract, backdrop)
local function depthOf(p) return (p.f == "N" or p.f == "S") and (p.z1 - p.z0) or (p.x1 - p.x0) end
local function band(p, d0, d1) -- footprint band between depths d0..d1 behind the main face
	local f = p.f
	if f == "N" then return p.x0, p.z0 + d0, p.x1, p.z0 + d1 end
	if f == "S" then return p.x0, p.z1 - d1, p.x1, p.z1 - d0 end
	if f == "W" then return p.x0 + d0, p.z0, p.x0 + d1, p.z1 end
	return p.x1 - d1, p.z0, p.x1 - d0, p.z1
end
local function backPoint(p, fa, fd) -- along fraction fa, depth fraction fd from the main face
	local f = p.f
	if f == "N" then return p.x0 + (p.x1 - p.x0) * fa, p.z0 + (p.z1 - p.z0) * fd end
	if f == "S" then return p.x0 + (p.x1 - p.x0) * fa, p.z1 - (p.z1 - p.z0) * fd end
	if f == "W" then return p.x0 + (p.x1 - p.x0) * fd, p.z0 + (p.z1 - p.z0) * fa end
	return p.x1 - (p.x1 - p.x0) * fd, p.z0 + (p.z1 - p.z0) * fa
end
local YAW = { N = 0, S = math.pi, W = math.rad(90), E = math.rad(-90) } -- wedge local +Z (tall side) -> away from face f
local function massing(m, p, r)
	local Ht, P = p.H, SPEC.Parapet
	box(m, p.x0, 0, p.z0, p.x1, Ht, p.z1, p.col, p.mat)
	if p.roof == "shed" then -- mono-pitch sheet-metal roof rising away from the street [SPEC 4.3]
		local along = (p.f == "N" or p.f == "S") and (p.x1 - p.x0) or (p.z1 - p.z0)
		local dep = depthOf(p)
		local rise = math.clamp(dep * 0.06, 1.5, 3.2)
		local cf = CFrame.new((p.x0 + p.x1) / 2, Ht + rise / 2, (p.z0 + p.z1) / 2) * CFrame.Angles(0, YAW[p.f], 0)
		wedge(m, Vector3.new(along, rise, dep), cf, p.col, p.mat)
		local a = math.atan2(rise, dep)
		part(m, Vector3.new(along + 0.6, 0.2, math.sqrt(dep * dep + rise * rise) + 1.2), cf * CFrame.Angles(-a, 0, 0) * CFrame.new(0, 0.1, 0),
			pick(r, { RUST, c3(150, 150, 146), c3(122, 126, 128) }), M.CorrodedMetal)
		return
	end
	box(m, p.x0 + 0.6, Ht, p.z0 + 0.6, p.x1 - 0.6, Ht + 0.15, p.z1 - 0.6, ROOF, M.Concrete)
	-- parapet 2.5 (1.0 m) below the standing shoot-over 3.1: rooftops are firing positions [SPEC 4.3]; street faces always,
	-- plus both sides on detailed buildings (roof views from the EB / tower); the back stays open (v2 budget)
	local want = {}
	if p.anyDetail then
		want = { N = true, S = true, W = true, E = true }
		want[({ N = "S", S = "N", W = "E", E = "W" })[p.f]] = false
	end
	for _, f in p.faces do want[f] = true end
	if want.N then box(m, p.x0, Ht, p.z0, p.x1, Ht + P, p.z0 + 0.6, p.col, p.mat) end
	if want.S then box(m, p.x0, Ht, p.z1 - 0.6, p.x1, Ht + P, p.z1, p.col, p.mat) end
	local za, zb = p.z0 + (want.N and 0.6 or 0), p.z1 - (want.S and 0.6 or 0)
	if want.W then box(m, p.x0, Ht, za, p.x0 + 0.6, Ht + P, zb, p.col, p.mat) end
	if want.E then box(m, p.x1 - 0.6, Ht, za, p.x1, Ht + P, zb, p.col, p.mat) end
	if p.tinaco then -- tinaco 2.75 x 3.5 [SPEC 4.3]
		local tx, tz = backPoint(p, p.tf[1], p.tf[2])
		tx = math.clamp(tx, p.x0 + 2.2, p.x1 - 2.2)
		tz = math.clamp(tz, p.z0 + 2.2, p.z1 - 2.2)
		vcyl(m, tx, Ht + 0.15, Ht + 3.65, tz, 2.75, c3(34, 34, 36), M.Plastic)
	end
end
local function lotMassing(m, p, r) -- walled lot / courtyard: barda 5.5 on the street line with a gate [SPEC 4.3]
	local a0, a1, c, sgn, ax = faceInfo(p, p.f)
	wallOpen(m, ax, c - sgn * 0.4, a0, a1, 0, SPEC.Barda, 0.8, { { p.gate, p.gw, 0, SPEC.Barda } }, p.col, p.mat)
	if p.kind == "court" then -- 1-storey house at the back of the courtyard
		local x0, z0, x1, z1 = band(p, depthOf(p) - 16, depthOf(p))
		box(m, x0, 0, z0, x1, H(1), z1, p.col, p.mat)
		box(m, x0, H(1), z0, x1, H(1) + 0.4, z1, ROOF, M.Concrete)
	end
end

local function buildEB(parent) -- M1 enterable building pattern (switchback stair, roof room), 3 storeys [SPEC 5]
	local m = model(parent, "EB")
	local dx, dz = EB.dx, EB.dz
	local function X(x) return x + dx end
	local function Z(z) return z + dz end
	local x0, x1, z0, z1 = EB.x0, EB.x1, EB.z0, EB.z1
	local g, t = 0.47, 0.8
	local LV = { g, g + SPEC.GF, g + SPEC.GF + SPEC.UF, g + SPEC.GF + 2 * SPEC.UF } -- floors 1-3 and roof
	local roofY, P = LV[4], SPEC.Parapet
	setB(m, 3, roofY, "shop + flats (enterable)")
	m:SetAttribute("Enterable", true)
	local col = c3(214, 200, 176)
	local zs = Z(-136) -- stair opening edge (flight A start / flight B arrival)
	box(m, x0, -0.5, z0, x1, g, z1, SLAB, M.Concrete)
	for s = 2, 4 do -- slabs with the stair opening x x0..X(-70), z z0..zs
		local y = LV[s]
		box(m, X(-70), y - 0.6, z0, x1, y, zs, SLAB, M.Concrete)
		box(m, x0, y - 0.6, zs, x1, y, z1, SLAB, M.Concrete)
	end
	for s = 1, 3 do
		local y0, y1 = LV[s], LV[s + 1] - 0.6
		local w0, w1 = y0 + 2.4, y0 + 5.6
		if s == 1 then -- shop opening + door on Z1, two openings on the spine
			wallOpen(m, "x", z1 - t / 2, x0, x1, y0, y1, t, { { X(-66), 9, y0, y0 + 6.2 }, { X(-55), SPEC.DoorW, y0, y0 + SPEC.DoorH } }, col, M.Plaster)
			wallOpen(m, "z", x1 - t / 2, z0, z1, y0, y1, t, { { Z(-141), 7, y0, y0 + 6.2 }, { Z(-126), 7, y0, y0 + 6.2 } }, col, M.Plaster)
			wallOpen(m, "x", z0 + t / 2, x0, x1, y0, y1, t, { { X(-56), 3, w0, w1 } }, col, M.Plaster)
		else
			wallOpen(m, "x", z1 - t / 2, x0, x1, y0, y1, t, { { X(-72), 3, w0, w1 }, { X(-62), 3, w0, w1 }, { X(-52), 3, w0, w1 } }, col, M.Plaster)
			wallOpen(m, "z", x1 - t / 2, z0, z1, y0, y1, t, { { Z(-142), 3, w0, w1 }, { Z(-132), 3, w0, w1 }, { Z(-123), 3, w0, w1 } }, col, M.Plaster)
			wallOpen(m, "x", z0 + t / 2, x0, x1, y0, y1, t, { { X(-58), 3, w0, w1 } }, col, M.Plaster)
		end
		wallOpen(m, "z", x0 + t / 2, z0, z1, y0, y1, t, {}, col, M.Plaster) -- west party wall (neighbour)
		box(m, x0 - 0.1, y1, z1 - 0.1, x1 + 0.1, y1 + 0.6, z1 + 0.25, c3(190, 180, 164), M.Concrete) -- slab bands
		box(m, x1 - 0.1, y1, z0 - 0.1, x1 + 0.25, y1 + 0.6, z1 + 0.1, c3(190, 180, 164), M.Concrete)
		wallOpen(m, "z", X(-69.6), z0 + t, Z(-128), y0, y1, 0.4, { { Z(-131), SPEC.DoorW, y0, y0 + SPEC.DoorH } }, c3(200, 192, 176), M.Plaster)
		wallOpen(m, "x", Z(-133), X(-69.4), x1 - t, y0, y1, 0.4, { { X(-60), SPEC.DoorW, y0, y0 + SPEC.DoorH } }, c3(206, 198, 182), M.Plaster)
		box(m, X(-57.8), y0, Z(-132.8), X(-57.6), y0 + SPEC.DoorH - 0.2, Z(-129.2), c3(150, 40, 36), M.Wood) -- open red door leaf
	end
	-- switchback stair per storey (M1 pattern, tread 1.0, treads 1.0 thick, landings 0.8): 14 risers of 0.643 in the 9.0
	-- ground storey, 12 of 0.625 above; flight A x 10.3..13.5 toward -Z from zs, landing at the back, flight B 13.5..17.5
	local STC = c3(170, 164, 154)
	local xa0, xa1, xb1 = x0 + t, X(-74), X(-70)
	for s = 1, 3 do
		local y = LV[s]
		local N = (s == 1) and 14 or 12
		local rise, half = (LV[s + 1] - y) / N, N // 2
		for k = 1, half do box(m, xa0, y + k * rise - 1.0, zs - k, xa1, y + k * rise, zs - (k - 1), STC, M.Concrete) end
		box(m, xa0, y + half * rise - 0.8, z0 + t, xb1, y + half * rise, zs - half, STC, M.Concrete)
		for k = 1, half do box(m, xa1, y + (half + k) * rise - 1.0, zs - half + (k - 1), xb1, y + (half + k) * rise, zs - half + k, STC, M.Concrete) end
	end
	-- roof (stair opening left open), parapet, roof access room over the core with a door to the roof
	box(m, X(-70), roofY, z0 + 0.6, x1 - 0.6, roofY + 0.12, zs, ROOF, M.Concrete)
	box(m, x0 + 0.6, roofY, zs, x1 - 0.6, roofY + 0.12, z1 - 0.6, ROOF, M.Concrete)
	local rx0, rx1, rz0, rz1 = x0, X(-66), Z(-148.6), Z(-128.4) -- room flush with the west party wall (taller neighbour possible)
	box(m, x0, roofY, z1 - 0.6, x1, roofY + P, z1, col, M.Plaster)
	box(m, x1 - 0.6, roofY, z0, x1, roofY + P, z1 - 0.6, col, M.Plaster)
	box(m, rx1, roofY, z0, x1 - 0.6, roofY + P, z0 + 0.6, col, M.Plaster)
	box(m, x0, roofY, rz1, x0 + 0.6, roofY + P, z1 - 0.6, col, M.Plaster)
	local rr0, rr1 = roofY, roofY + SPEC.RoofRoomH - 0.6
	local rc = c3(222, 210, 188)
	local dw, doorTop = m, rr0 + SPEC.DoorH
	if SPEC.V3 then -- v3: 6.2 clear above the 0.12 roof finish (v2 measured 6.08); wall rebuilt in an M2v3 model
		dw = model(m, "RoofRoomDoorV3")
		dw:SetAttribute("M2v3", true)
		doorTop = rr0 + 0.12 + SPEC.DoorH
	end
	wallOpen(dw, "x", rz1 - 0.4, rx0, rx1, rr0, rr1, 0.8, { { X(-72), SPEC.DoorW, rr0, doorTop } }, rc, M.Plaster)
	wallOpen(m, "x", rz0 + 0.4, rx0, rx1, rr0, rr1, 0.8, {}, rc, M.Plaster)
	wallOpen(m, "z", rx1 - 0.4, rz0 + 0.8, rz1 - 0.8, rr0, rr1, 0.8, {}, rc, M.Plaster)
	wallOpen(m, "z", rx0 + 0.4, rz0 + 0.8, rz1 - 0.8, rr0, rr1, 0.8, {}, rc, M.Plaster)
	box(m, rx0, rr1, rz0 - 1.2, rx1 + 1.2, rr1 + 0.6, rz1 + 1.2, c3(176, 168, 156), M.Concrete)
	box(m, X(-70.12), rr1 + 0.6, Z(-140.12), X(-69.88), rr1 + 10.6, Z(-139.88), METAL, M.Metal) -- antenna mast
	part(m, Vector3.new(6, 0.15, 0.15), CFrame.new(X(-70), rr1 + 9.8, Z(-140)) * CFrame.Angles(0, math.rad(30), 0), METAL, M.Metal)
	return m
end

local function buildTower(parent) -- tallest building 130 (52 m) [SPEC 4.3]; 17 storeys: ground 10 (PARAMETER) + 16 x 7.5
	local m = model(parent, "Tower")
	local x0, z0, x1, z1 = TOWER.x0, TOWER.z0, TOWER.x1, TOWER.z1
	local Ht = SPEC.TowerH
	setB(m, 17, Ht, "offices / hotel")
	local col = c3(190, 184, 172)
	box(m, x0, 0, z0, x1, Ht, z1, col, M.Concrete)
	box(m, x0 + 0.6, Ht, z0 + 0.6, x1 - 0.6, Ht + 0.15, z1 - 0.6, ROOF, M.Concrete)
	box(m, x0, Ht, z0, x1, Ht + SPEC.Parapet, z0 + 0.6, col, M.Concrete)
	box(m, x0, Ht, z1 - 0.6, x1, Ht + SPEC.Parapet, z1, col, M.Concrete)
	box(m, x0, Ht, z0 + 0.6, x0 + 0.6, Ht + SPEC.Parapet, z1 - 0.6, col, M.Concrete)
	box(m, x1 - 0.6, Ht, z0 + 0.6, x1, Ht + SPEC.Parapet, z1 - 0.6, col, M.Concrete)
	box(m, x0 + 12, Ht, z0 + 14, x0 + 26, Ht + 8, z0 + 24, c3(176, 170, 160), M.Concrete) -- machine room
	box(m, x0 + 25.8, Ht + 8, z0 + 18.8, x0 + 26.2, Ht + 20, z0 + 19.2, METAL, M.Metal) -- mast
	return m
end

local function buildChurch(parent) -- parish church + tower + atrium, one block from Bridge I [SPEC 4.1]
	local m = model(parent, "Church")
	setB(m, 1, SPEC.ChurchTowerH, "church (civic)")
	local n, tw, at = CH.nave, CH.tower, CH.atrium
	local col, trim = c3(210, 194, 164), c3(188, 172, 144)
	local Hn = SPEC.ChurchH
	box(m, n[1], 0, n[2], n[3], Hn, n[4], col, M.Plaster) -- nave
	box(m, n[1], Hn, n[2], n[3], Hn + 1.6, n[2] + 0.8, trim, M.Plaster)
	box(m, n[1], Hn, n[4] - 0.8, n[3], Hn + 1.6, n[4], trim, M.Plaster)
	box(m, n[3], 0, n[2] - 2, n[3] + 2, Hn + 8, n[4] + 2, col, M.Plaster) -- frontispiece facing the spine
	box(m, n[3], Hn + 8, n[2] + 6, n[3] + 2, Hn + 13, n[4] - 6, trim, M.Plaster)
	box(m, tw[1], 0, tw[2], tw[3], 50, tw[4], col, M.Plaster) -- tower shaft
	for _, o in { { tw[1], tw[2] }, { tw[3] - 2, tw[2] }, { tw[1], tw[4] - 2 }, { tw[3] - 2, tw[4] - 2 } } do
		box(m, o[1], 50, o[2], o[1] + 2, 58, o[2] + 2, col, M.Plaster) -- bell-stage piers
	end
	box(m, tw[1] - 0.4, 58, tw[2] - 0.4, tw[3] + 0.4, 59, tw[4] + 0.4, trim, M.Plaster)
	local tcx, tcz = (tw[1] + tw[3]) / 2, (tw[2] + tw[4]) / 2
	vcyl(m, tcx, 59, 61, tcz, 8, trim, M.Plaster)
	part(m, Vector3.new(6.5, 6.5, 6.5), CFrame.new(tcx, 61.2, tcz), c3(176, 160, 132), M.Plaster, Enum.PartType.Ball)
	box(m, tcx - 0.2, 64, tcz - 0.2, tcx + 0.2, SPEC.ChurchTowerH, tcz + 0.2, METAL, M.Metal) -- cross
	box(m, tcx - 0.2, SPEC.ChurchTowerH - 2, tcz - 1, tcx + 0.2, SPEC.ChurchTowerH - 1.6, tcz + 1, METAL, M.Metal)
	vcyl(m, CH.dome[1], Hn, Hn + 6, CH.dome[2], 16, trim, M.Plaster) -- drum + dome
	part(m, Vector3.new(15.5, 15.5, 15.5), CFrame.new(CH.dome[1], Hn + 6, CH.dome[2]), c3(196, 180, 150), M.Plaster, Enum.PartType.Ball)
	vcyl(m, CH.dome[1], Hn + 13.5, Hn + 16.5, CH.dome[2], 2.4, trim, M.Plaster)
	-- atrium: raised paving and a low wall with a gate on the spine (shoot-over / crouched cover 3.6, PARAMETER)
	box(m, at[1], -0.4, at[2], at[3], 0.6, at[4], PAVE:Lerp(SIDEWALK, 0.5), M.Pavement)
	wallOpen(m, "z", at[3] - 0.4, at[2], at[4], 0, 3.6, 0.8, { { (at[2] + at[4]) / 2, 10, 0, 3.6 } }, col, M.Plaster)
	wallOpen(m, "x", at[2] + 0.4, at[1], at[3] - 0.8, 0, 3.6, 0.8, {}, col, M.Plaster)
	wallOpen(m, "x", at[4] - 0.4, at[1], at[3] - 0.8, 0, 3.6, 0.8, {}, col, M.Plaster)
	return m
end

local function buildKiosk(parent) -- plaza kiosk (bandstand) at the plaza centre [SPEC 4.1]
	local m = coverModel(parent, "Kiosk", 4.0)
	setB(m, 1, 13.6, "kiosk")
	local x, z, R = KIOSK.x, KIOSK.z, 8.6
	local IRON = c3(52, 74, 60)
	vcyl(m, x, -0.2, 0.8, z, SPEC.KioskD + 3, c3(170, 160, 146), M.Concrete) -- step ring
	vcyl(m, x, -0.2, 1.6, z, SPEC.KioskD, c3(190, 180, 164), M.Concrete) -- platform
	for k = 0, 7 do
		local a, a2 = k * math.pi / 4 + math.pi / 8, (k + 1) * math.pi / 4 + math.pi / 8
		vcyl(m, x + math.cos(a) * R, 1.6, 9.6, z + math.sin(a) * R, 0.8, IRON, M.Metal)
		if k ~= 6 then -- railing panels (cover), entrance gap toward the north-west path
			local pa = Vector3.new(x + math.cos(a) * R, 2.8, z + math.sin(a) * R)
			local pb = Vector3.new(x + math.cos(a2) * R, 2.8, z + math.sin(a2) * R)
			part(m, Vector3.new(0.25, 2.4, (pb - pa).Magnitude - 0.8), CFrame.lookAt((pa + pb) / 2, pb), IRON, M.Metal)
		end
	end
	vcyl(m, x, 9.6, 10.2, z, SPEC.KioskD + 1, c3(150, 70, 56), M.Concrete) -- roof
	vcyl(m, x, 10.2, 11.4, z, 15, c3(150, 70, 56), M.Concrete)
	vcyl(m, x, 11.4, 12.4, z, 9, c3(150, 70, 56), M.Concrete)
	vcyl(m, x, 12.4, 13.6, z, 3.5, IRON, M.Metal)
	return m
end

local function buildClock(parent) -- public clock tower (PARAMETER position / height)
	local m = model(parent, "ClockTower")
	setB(m, 1, SPEC.ClockTowerH, "clock tower (civic)")
	local x, z = CLOCK.x, CLOCK.z
	local col = c3(206, 194, 170)
	box(m, x - 4, 0, z - 4, x + 4, 3, z + 4, c3(170, 160, 146), M.Concrete)
	box(m, x - 2.75, 3, z - 2.75, x + 2.75, 28, z + 2.75, col, M.Plaster)
	box(m, x - 3.25, 28, z - 3.25, x + 3.25, 34, z + 3.25, col:Lerp(c3(180, 168, 146), 0.5), M.Plaster)
	box(m, x - 3.6, 34, z - 3.6, x + 3.6, 34.6, z + 3.6, c3(170, 160, 146), M.Concrete)
	vcyl(m, x, 34.6, SPEC.ClockTowerH, z, 4.5, c3(150, 70, 56), M.Concrete)
	return m
end

local WH = { -- PARAMETER logistics sheds: x0, z0, x1, z1, eaves, roof, dock face
	{ -760, -290, -680, -150, 18, "gable", "N" }, { -880, -300, -790, -160, 16, "gable", "N" },
	{ -780, -560, -680, -420, 20, "gable", "S" }, { -885, -600, -800, -430, 14, "shed", "S" },
}
local function passB()
	local r = Random.new(SPEC.Seed + 2)
	for _, b in BLOCKS do -- one sub-model per block, one model per building / lot
		local bm = newm(b.id)
		for _, p in b.plots do
			local m = model(bm, p.name)
			setB(m, p.n, p.H, p.use)
			if p.kind == "building" then massing(m, p, r) else lotMassing(m, p, r) end
		end
		for _, e in EDGES do
			if e.b == b then -- town edge: barda with a gate between the corner plots
				local m = model(bm, "EdgeWall")
				setB(m, 0, SPEC.Barda, "perimeter wall")
				wallOpen(m, "z", e.x - 0.4, e.z0, e.z1, 0, SPEC.Barda, 0.8, { { rn(r, e.z0 + 8, e.z1 - 8), 7, 0, SPEC.Barda } }, c3(186, 178, 164), M.Plaster)
			end
		end
		flush(bm, "Blocks")
	end
	local lm = newm("Landmarks_B")
	buildEB(lm)
	buildTower(lm)
	buildChurch(lm)
	buildKiosk(lm)
	buildClock(lm)
	for _, c in lm:GetChildren() do c.Parent = G.Landmarks end
	task.wait()

	local lg = newm("Buildings")
	for i, w in WH do
		local m = model(lg, "Warehouse" .. i)
		setB(m, 1, w[5], "warehouse")
		local x0, z0, x1, z1, Hw = w[1], w[2], w[3], w[4], w[5]
		local col = pick(r, { c3(196, 192, 182), c3(176, 178, 176), c3(200, 188, 164) })
		box(m, x0, 0, z0, x1, Hw, z1, col, M.Metal)
		local W, L = x1 - x0, z1 - z0
		if w[6] == "gable" then -- ridge along z
			wedge(m, Vector3.new(L, 4, W / 2), CFrame.new(x0 + W / 4, Hw + 2, (z0 + z1) / 2) * CFrame.Angles(0, math.rad(90), 0), c3(150, 154, 156), M.CorrodedMetal)
			wedge(m, Vector3.new(L, 4, W / 2), CFrame.new(x1 - W / 4, Hw + 2, (z0 + z1) / 2) * CFrame.Angles(0, math.rad(-90), 0), c3(150, 154, 156), M.CorrodedMetal)
		else
			wedge(m, Vector3.new(L, 3, W), CFrame.new((x0 + x1) / 2, Hw + 1.5, (z0 + z1) / 2) * CFrame.Angles(0, math.rad(-90), 0), c3(150, 154, 156), M.CorrodedMetal)
		end
		local dz = (w[7] == "N") and z0 or z1
		box(m, x0 + 6, 0, dz - ((w[7] == "N") and 5 or 0), x1 - 6, 4, dz + ((w[7] == "S") and 5 or 0), CONC, M.Concrete) -- dock
	end
	do -- open canopy shed, customs office, yard walls (barda east, chain-link elsewhere)
		local m = model(lg, "Canopy")
		setB(m, 1, 15, "warehouse (open)")
		for _, x in { -848, -775, -702 } do for _, z in { -688, -632 } do box(m, x - 0.6, 0, z - 0.6, x + 0.6, 15, z + 0.6, METAL, M.Metal) end end
		box(m, -852, 15, -692, -698, 15.6, -628, c3(150, 154, 156), M.CorrodedMetal)
		local o = model(lg, "CustomsOffice")
		setB(o, 2, H(2), "office")
		box(o, -700, 0, -362, -670, H(2), -340, c3(200, 196, 184), M.Plaster)
		box(o, -700, H(2), -362, -670, H(2) + SPEC.Parapet, -361.4, c3(200, 196, 184), M.Plaster)
		local wl = model(lg, "YardWalls")
		setB(wl, 0, SPEC.Barda, "perimeter wall")
		local Yd = SPEC.Yard
		wallOpen(wl, "z", Yd.x1 + 0.4, Yd.z0, Yd.z1, 0, SPEC.Barda, 0.8, { { SPEC.EW[3], 18, 0, SPEC.Barda } }, c3(186, 178, 164), M.Plaster)
		for _, f in { { "x", Yd.z0, Yd.x0, Yd.x1 }, { "x", Yd.z1, Yd.x0, Yd.x1 }, { "z", Yd.x0, Yd.z0, Yd.z1 } } do
			local fp
			if f[1] == "x" then fp = box(wl, f[3], 0, f[2] - 0.08, f[4], 6, f[2] + 0.08, c3(150, 152, 150), M.DiamondPlate)
			else fp = box(wl, f[2] - 0.08, 0, f[3], f[2] + 0.08, 6, f[4], c3(150, 152, 150), M.DiamondPlate) end
			fp.Transparency, fp.CanQuery = 0.6, false -- chain-link: blocks movement, not bullets
		end
	end
	flush(lg, "Logistics")

	local tr = newm("Houses") -- tract: 1-storey 15 x 25 houses (60 m2), two rows per block [SPEC 4.1 / 4.3]
	local T = SPEC.Tract
	local base = CFrame.new(TRACT_C) * CFrame.Angles(0, math.rad(T.rot), 0)
	local pitch, hh = T.w + SPEC.TractStreet, SPEC.TractHouseH
	local per = math.floor(T.l / 15.25)
	for bi = -1, 1 do
		for _, side in { -1, 1 } do
			for k = 0, per - 1 do
				local lz = -T.l / 2 + (k + 0.5) * (T.l / per)
				local lx = bi * pitch + side * (T.w / 2 - 6 - 12.5)
				local m = model(tr, string.format("H%d%s%02d", bi + 2, (side < 0) and "a" or "b", k))
				setB(m, 1, hh, "house (tract)")
				part(m, Vector3.new(25, hh, 15), base * CFrame.new(lx, hh / 2, lz), plaster(r):Lerp(c3(214, 206, 190), 0.3), M.Plaster)
			end
		end
	end
	flush(tr, "Tract")

	local bd = newm("Context") -- low-detail context: far bank (Laredo, TX) and the west edge [SPEC 6]
	for i = 1, 34 do
		local x, z = rn(r, -940, 940), rn(r, -1950, -1665)
		if math.abs(x - SPX) < 40 then x += 90 end
		local w, d = rn(r, 30, 90), rn(r, 25, 70)
		local n = (r:NextNumber() < 0.65) and 1 or ((r:NextNumber() < 0.8) and 2 or 3)
		local m = model(bd, "FarBank" .. i)
		setB(m, n, H(n), "context (far bank)")
		box(m, x - w / 2, 0, z - d / 2, x + w / 2, H(n), z + d / 2, plaster(r):Lerp(c3(200, 196, 188), 0.4), M.Concrete)
	end
	local hm = model(bd, "FarBankHotel")
	setB(hm, 10, H(10), "context (far bank)")
	box(hm, -200, 0, -1745, -160, H(10), -1715, c3(196, 188, 172), M.Concrete)
	vcyl(bd, 260, 0, 34, -1760, 1.4, METAL, M.Metal) -- water tower
	vcyl(bd, 260, 32, 41, -1760, 10, c3(196, 196, 192), M.Metal)
	for i = 1, 12 do
		local z = -680 + (i - 1) * 60 + rn(r, -12, 12)
		local w, d = rn(r, 40, 80), rn(r, 25, 45)
		local m = model(bd, "WestEdge" .. i)
		setB(m, 1, rn(r, 9, 14), "context (west edge)")
		box(m, -1000, 0, z - d / 2, -1000 + w, m:GetAttribute("Height"), z + d / 2, pick(r, { c3(176, 170, 160), c3(196, 186, 168), c3(160, 158, 152) }), M.Concrete)
	end
	flush(bd, "Backdrop")
end

------------------------------------------------------------------------------------------------------------------------
-- PASS C: street level (openings, shutters, awnings, sign bands, bars, markings, signage, utilities, vegetation, props)
local function thin(p, tr) deco(p, true); if tr then p.Transparency = tr end; return p end
local DOORC = { c3(90, 60, 40), c3(70, 60, 50), METAL, c3(120, 40, 36), c3(46, 70, 60) }
local AWNC = { c3(150, 60, 50), c3(60, 90, 120), c3(70, 110, 80), c3(190, 150, 70), METAL }
local function shopGround(m, p, f, a0, a1, r, detail) -- shopfronts: open / glazed / workshop door, shutters 50 %, awnings 30 %, sign band
	local L, Y = a1 - a0, SPEC.Walk
	local top = Y + 6.6
	local sc = pick(r, SIGNC)
	local k = (detail and L >= 30) and 2 or 1
	local seg = L / k
	for i = 0, k - 1 do
		local c = a0 + (i + 0.5) * seg
		local ow = detail and math.min(seg - 2.6, 13) or L * 0.76
		local t = r:NextNumber()
		if t < 0.14 then
			thin(onFace(m, p, f, c, ow, Y, top, 0.12, 0.25, pick(r, SHUTTERC), M.CorrodedMetal)) -- workshop roll-up (llantera / taller)
		else
			thin(onFace(m, p, f, c, ow, Y, top, 0.08, 0.3, DARK, M.SmoothPlastic))
			if detail and t < 0.5 then thin(onFace(m, p, f, c, ow - 0.8, Y + 0.5, top - 0.4, 0.14, 0.08, GLASS, M.Glass)).Reflectance = 0.08 end
			if r:NextNumber() < SPEC.Shutter then
				local hs = (r:NextNumber() < 0.3) and 6.6 or rn(r, 0.8, 3.2)
				thin(onFace(m, p, f, c, ow, top - hs, top, 0.2, 0.1, pick(r, SHUTTERC), M.CorrodedMetal))
			end
		end
		if r:NextNumber() < SPEC.Awning then
			thin(onFace(m, p, f, c, ow + 1.2, top - 0.05, top + 0.2, 1.9, 1.9, pick(r, AWNC), M.Fabric))
		end
	end
	-- v2 signage mix: full-width painted band on ~30 % of shops, a raised painted board over the first opening on ~35 %,
	-- nothing on the rest; text (capped) on the main face of detailed shops
	local u, word = r:NextNumber(), pick(r, WORDS)
	if f ~= p.f then u = 1 end -- signs on the main face only, so the shares hold per shop
	local wantText = detail and f == p.f and r:NextNumber() < 0.8
	local bw0, bh0 = rn(r, 6, 11), rn(r, 1.4, 2.0)
	local sb
	if u < SPEC.SignMix.band then
		sb = thin(onFace(m, p, f, (a0 + a1) / 2, L - 1.2, top + 0.3, top + 1.8, 0.22, 0.12, sc[1], M.SmoothPlastic))
	elseif u < SPEC.SignMix.band + SPEC.SignMix.board then
		sb = thin(onFace(m, p, f, a0 + 0.5 * seg, math.min(seg - 1.5, bw0), top + 0.4, top + 0.4 + bh0, 0.32, 0.2, sc[1], M.SmoothPlastic))
	end
	if sb and wantText then label(sb, FACEID[f], word, sc[2]) end
end
local FRAMEC = { c3(226, 222, 212), c3(150, 146, 138), c3(96, 72, 54), c3(60, 62, 64), c3(186, 176, 150) } -- PARAMETER window frames
local BARC = c3(44, 44, 46)
local function window(m, p, f, a, y0, ww, ws, framed) -- v2 individual window: thin frame + glass (frame on street faces)
	if framed then thin(onFace(m, p, f, a, ww + 0.36, y0 - 0.18, y0 + ws.h + 0.18, 0.06, 0.1, ws.fc, M.SmoothPlastic)) end
	thin(onFace(m, p, f, a, ww, y0, y0 + ws.h, framed and 0.1 or 0.07, 0.08, GLASS, M.Glass))
end
local function bars(m, p, f, a, y0, ww, wh) -- iron bars: 2-3 thin verticals + 1 horizontal (CanQuery off)
	local nv = (ww >= 3.6) and 3 or 2
	for i = 1, nv do thin(onFace(m, p, f, a - ww / 2 + ww * i / (nv + 1), 0.12, y0 - 0.1, y0 + wh + 0.1, 0.32, 0.12, BARC, M.Metal)) end
	thin(onFace(m, p, f, a, ww + 0.2, y0 + wh * 0.5 - 0.06, y0 + wh * 0.5 + 0.06, 0.32, 0.12, BARC, M.Metal))
end
local function bayGrid(L, ws) -- bays of ~8-11 along a face; window width fits the bay
	local nb = math.max(1, math.floor(L / ws.bay + 0.5))
	local bw = L / nb
	return nb, bw, math.max(2.0, math.min(ws.w, bw - 1.6))
end
local function houseGround(m, p, f, a0, a1, r, detail, ws) -- door / car gate in one bay, a window in each other bay, bars 60 %
	local L, Y = a1 - a0, SPEC.Walk
	local nb, bw, ww = bayGrid(L, ws)
	local db = r:NextInteger(0, nb - 1)
	local dpos = a0 + (db + 0.5) * bw
	if detail and L > 22 and r:NextNumber() < 0.25 then
		thin(onFace(m, p, f, dpos, math.min(8, bw - 0.8), Y, Y + 6.2, 0.14, 0.2, pick(r, SHUTTERC), M.Metal)) -- cochera gate
	else
		thin(onFace(m, p, f, dpos, SPEC.DoorW - 0.6, Y, Y + SPEC.DoorH - 0.4, 0.1, 0.25, pick(r, DOORC), M.Wood))
	end
	for k = 0, nb - 1 do
		if k ~= db then
			local a = a0 + (k + 0.5) * bw
			window(m, p, f, a, Y + 2.4, ww, ws, detail or SPEC.WinFrameAll)
			if r:NextNumber() < SPEC.Bars then bars(m, p, f, a, Y + 2.4, ww, ws.h) end -- [SPEC 4.3 60 %]
		end
	end
end
local function upperFloors(m, p, f, a0, a1, r, detail, ws) -- one window per bay and storey; balconies / AC on detailed faces
	local L = a1 - a0
	local nb, bw, ww = bayGrid(L, ws)
	for s = 1, p.n - 1 do
		local y = H(s)
		for k = 0, nb - 1 do
			local a = a0 + (k + 0.5) * bw
			window(m, p, f, a, y + 2.0, ww, ws, detail or SPEC.WinFrameAll)
			if detail then
				local u = r:NextNumber()
				if u < 0.1 then -- balcony (slab solid, rail decorative)
					onFace(m, p, f, a, math.min(5.5, bw * 0.8), y, y + 0.35, 2.2, 2.2, p.col, M.Concrete)
					thin(onFace(m, p, f, a, math.min(5.5, bw * 0.8), y + 0.35, y + 2.6, 2.2, 0.15, METAL, M.Metal))
				elseif u < 0.16 then
					deco(onFace(m, p, f, a + ww / 2 + 1.1, 2.0, y + 1.0, y + 2.4, 1.3, 1.3, c3(214, 214, 208), M.SmoothPlastic), false) -- AC unit
				end
			end
		end
	end
end
local LEAFV = { c3(98, 108, 70), c3(112, 118, 80), c3(86, 98, 62), c3(124, 124, 88), c3(92, 106, 74), c3(104, 100, 66) } -- PARAMETER dusty olive greens
local function crown(m, cx, cy, cz, n, d0, d1, sxz, sy, r, base) -- organic crown: n overlapping balls, per-ball colour
	for _ = 1, n do
		local d, a, rr = rn(r, d0, d1), rn(r, 0, 6.283), rn(r, 0, sxz)
		local col = pick(r, LEAFV):Lerp(base, rn(r, 0, 0.4)):Lerp(c3(150, 146, 112), rn(r, 0, 0.18))
		deco(part(m, Vector3.new(d, d, d), CFrame.new(cx + math.cos(a) * rr, cy + rn(r, -sy, sy), cz + math.sin(a) * rr), col, M.LeafyGrass, Enum.PartType.Ball), false)
	end
end
local SCRUBMIX = { { "mesquite", 60 }, { "shrub", 20 }, { "nopal", 10 }, { "tuft", 10 } } -- thornscrub mix [SPEC 4.4]
local function scrub(m, x, y, z, r, kind)
	if not kind then
		local u = r:NextNumber() * 100
		for _, e in SCRUBMIX do
			u -= e[2]
			if u < 0 then kind = e[1]; break end
		end
		kind = kind or "mesquite"
	end
	if kind == "mesquite" then -- v2: short leaning trunk, low wide irregular crown of 3-4 balls offset sideways; 10-15 total
		local h = rn(r, 10, 15)
		local tl, lean, yaw = h * 0.55, rn(r, 0.15, 0.4), rn(r, 0, 6.283)
		local tr = part(m, Vector3.new(tl, 0.8, 0.8), CFrame.new(x, y + tl * 0.46, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(90) + lean), TRUNK, M.Wood, Enum.PartType.Cylinder)
		local top = (tr.CFrame * CFrame.new(tl / 2, 0, 0)).Position
		crown(m, top.X, y + h * 0.62, top.Z, r:NextInteger(3, 4), 3.5, 6, rn(r, 3, 5), h * 0.12, r, MESQ)
	elseif kind == "shrub" then -- 2-3 small balls
		for _ = 1, r:NextInteger(2, 3) do
			local d = rn(r, 1.6, 3)
			deco(part(m, Vector3.new(d, d, d), CFrame.new(x + rn(r, -1.2, 1.2), y + d * 0.4, z + rn(r, -1.2, 1.2)), SHRUBC:Lerp(DRYG, r:NextNumber() * 0.4), M.LeafyGrass, Enum.PartType.Ball), false)
		end
	elseif kind == "nopal" then -- prickly pear clump: 3-4 flat pads
		for k = 1, r:NextInteger(3, 4) do
			deco(part(m, Vector3.new(0.35, rn(r, 1.6, 2.2), rn(r, 1.3, 1.8)), CFrame.new(x + rn(r, -0.8, 0.8), y + 0.8 + (k - 1) * 0.8, z + rn(r, -0.8, 0.8)) * CFrame.Angles(rn(r, -0.4, 0.4), rn(r, 0, 6.28), 0), NOPALC, M.LeafyGrass, Enum.PartType.Cylinder), false)
		end
	else
		thin(part(m, Vector3.new(rn(r, 1.5, 3), 0.6, rn(r, 1.5, 3)), CFrame.new(x, y + 0.3, z) * CFrame.Angles(0, rn(r, 0, 6.28), 0), DRYG, M.Grass))
	end
end
local function plazaTree(m, x, z, r) -- v2: plaza tree 7.5-10 tall [SPEC 4.4], crown of 4-6 overlapping balls
	local h = rn(r, 7.5, 10)
	vcyl(m, x, 0.06, h - 3.0, z, 0.7, TRUNK, M.Wood)
	crown(m, x, h - 2.6, z, r:NextInteger(4, 6), 2.6, 4.2, 1.6, 0.6, r, LAUREL)
end
local function car(parent, x, z, yaw, r) -- parked car shells: sedan / pickup / van, cover classes by top height
	local u = r:NextNumber()
	local kind = (u < 0.6) and "sedan" or ((u < 0.85) and "pickup" or "van")
	local col = pick(r, CARC)
	local L = (kind == "sedan") and 11.25 or ((kind == "pickup") and 13.5 or 12)
	local m = coverModel(parent, "Car_" .. kind, (kind == "sedan") and 3.65 or ((kind == "pickup") and 4.4 or 4.6))
	local cf = CFrame.new(x, 0.08, z) * CFrame.Angles(0, yaw, 0)
	if kind == "van" then
		part(m, Vector3.new(4.6, 3.9, L), cf * CFrame.new(0, 2.65, 0), col, M.SmoothPlastic)
		thin(part(m, Vector3.new(4.66, 1.1, L - 3.2), cf * CFrame.new(0, 3.5, 0.6), GLASS, M.Glass))
	else
		part(m, Vector3.new(4.5, 1.9, L), cf * CFrame.new(0, 1.65, 0), col, M.SmoothPlastic)
		if kind == "sedan" then part(m, Vector3.new(4.2, 1.05, L * 0.48), cf * CFrame.new(0, 3.125, -0.3), GLASS, M.Glass)
		else part(m, Vector3.new(4.4, 1.8, 4.8), cf * CFrame.new(0, 3.5, -L / 2 + 4.4), col, M.SmoothPlastic) end
	end
	for _, wz in { -L / 2 + 2.3, L / 2 - 2.3 } do part(m, Vector3.new(4.7, 1.7, 1.7), cf * CFrame.new(0, 0.85, wz), c3(26, 26, 26), M.Rubber, Enum.PartType.Cylinder) end
end
local function truck(parent, x, z, yaw) -- tractor-trailer; origin = trailer rear centre, cab toward local +Z
	local m = coverModel(parent, "Truck", 10.2)
	local cf = CFrame.new(x, 0.03, z) * CFrame.Angles(0, yaw, 0)
	part(m, Vector3.new(6.5, 7.2, 40), cf * CFrame.new(0, 6.6, 20), c3(214, 212, 206), M.Metal)
	part(m, Vector3.new(6.5, 7.0, 7.5), cf * CFrame.new(0, 4.7, 45.3), pick(Random.new(math.floor(x * 7 + z)), { c3(150, 30, 30), c3(40, 60, 110), WHITE, c3(60, 62, 64) }), M.SmoothPlastic)
	thin(part(m, Vector3.new(6.3, 1.8, 0.2), cf * CFrame.new(0, 6.6, 49.1), GLASS, M.Glass))
	part(m, Vector3.new(2.4, 1.0, 47), cf * CFrame.new(0, 1.9, 24), DARK, M.Metal)
	for _, wz in { 3, 6.4, 44 } do part(m, Vector3.new(7.0, 2.6, 2.6), cf * CFrame.new(0, 1.3, wz), c3(26, 26, 26), M.Rubber, Enum.PartType.Cylinder) end
end
-- disc / plate orientation by facing (N = faces -Z): cylinder axis, visible end face
local DISC = { N = { math.rad(90), Enum.NormalId.Right }, S = { math.rad(90), Enum.NormalId.Left }, E = { 0, Enum.NormalId.Right }, W = { 0, Enum.NormalId.Left } }
local FDIR = { N = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1), W = Vector3.new(-1, 0, 0), E = Vector3.new(1, 0, 0) }
local ALTOS = { -- stop signs on cross-street approaches: x, z, facing, stop-line box (x0, z0, x1, z1) [SPEC 4.4]
	{ 44.8, 45.8, "N", { 47, 43.8, 63, 44.3 } }, { 38.8, -370.8, "W", { 33.3, -388, 33.8, -372 } }, { 38.8, -800.8, "W", { 33.3, -818, 33.8, -802 } },
	{ -90.8, -365.8, "S", { -108, -366.3, -92, -365.8 } }, { -264.2, -394.2, "N", { -263, -394.5, -247, -394 } },
	{ -400.8, -585.8, "S", { -418, -586.3, -402, -585.8 } }, { -264.2, -824.2, "N", { -263, -824.5, -247, -824 } },
	{ -90.8, -795.8, "S", { -108, -796.3, -92, -795.8 } }, { 219.2, -365.8, "S", { 202, -366.3, 218, -365.8 } },
	{ 219.2, -795.8, "S", { 202, -796.3, 218, -795.8 } }, { -523.3, -609.2, "E", { -529, -608, -528.5, -592 } },
}
local PLATES = { -- corner poles: street plate (fictional name) + one-way arrow, x, z
	{ "SPINE", 45.8, -389.2 }, { "X100", -90.8, -370.8 }, { "X255", -264.2, -150.8 }, { "X410", -400.8, -609.2 }, { "AVW", -529.3, -169.2 },
	{ "E1", 200.8, -370.8 }, { "Z0", 64.2, 50.8 }, { "Z1", -90.8, -150.8 }, { "Z2", -245.8, -389.2 }, { "Z3", 45.8, -590.8 },
	{ "Z4", -419.2, -819.2 }, { "Z5", 64.2, -990.8 },
}
local function nearEW(z, d)
	for _, zc in SPEC.EW do if math.abs(z - zc) < d then return true end end
	return false
end
local function nearNS(x, d)
	for _, s in SPEC.NS do if math.abs(x - s.x) < d + ((s.k == "avw") and AVW_OUT or CWH) then return true end end
	return false
end

local function passC()
	local r = Random.new(SPEC.Seed + 3)
	local Y = SPEC.Walk
	local SB = SPEC.SignBottom
	-- signage first: street plates and ALTO get the SurfaceGui budget before shop sign bands
	local sg = newm("Signs")
	for i, a in ALTOS do
		local m = model(sg, "Alto" .. i)
		vcyl(m, a[1], Y, Y + SB + 2.6, a[2], 0.25, METAL, M.Metal)
		local d = DISC[a[3]]
		local pos = Vector3.new(a[1], Y + SB + 1.05, a[2]) + FDIR[a[3]] * 0.2
		local disc = thin(part(m, Vector3.new(0.1, 2.1, 2.1), CFrame.new(pos) * CFrame.Angles(0, d[1], 0), c3(176, 30, 30), M.SmoothPlastic, Enum.PartType.Cylinder))
		label(disc, d[2], "ALTO", WHITE)
		local s = a[4]
		thin(box(m, s[1], 0.07, s[2], s[3], 0.1, s[4], LINE, M.SmoothPlastic)) -- stop line
	end
	for _, pl in PLATES do
		local id, x, z = pl[1], pl[2], pl[3]
		local m = model(sg, "Plate_" .. id)
		vcyl(m, x, Y, Y + SB + 3.4, z, 0.25, METAL, M.Metal)
		local ns = NSX[id]
		local f, dir
		if ns then f = (x > ns.x) and "W" or "E"; dir = NSDIR[id]
		else local zi = tonumber(string.sub(id, 2)) + 1; f = (z > SPEC.EW[zi]) and "N" or "S"; dir = EWDIR[zi] end
		local alongX = (f == "N" or f == "S")
		local o = FDIR[f] * 0.18
		local function plate(y0, y1, len, col)
			return thin(part(m, alongX and Vector3.new(len, y1 - y0, 0.08) or Vector3.new(0.08, y1 - y0, len), CFrame.new(x + o.X, (y0 + y1) / 2, z + o.Z), col, M.SmoothPlastic))
		end
		local nameP = plate(Y + SB + 1.75, Y + SB + 2.65, 4.2, c3(24, 54, 104))
		label(nameP, FACEID[f], STREETNAME[id], WHITE)
		if dir ~= 0 then -- one-way arrow plate (black, white arrow along the travel direction)
			plate(Y + SB, Y + SB + 0.8, 2.4, BLACK)
			local u = alongX and Vector3.new(dir, 0, 0) or Vector3.new(0, 0, dir)
			local c = Vector3.new(x, Y + SB + 0.4, z) + FDIR[f] * 0.24
			thin(part(m, alongX and Vector3.new(1.4, 0.16, 0.04) or Vector3.new(0.04, 0.16, 1.4), CFrame.new(c - u * 0.2), WHITE, M.SmoothPlastic))
			thin(part(m, Vector3.new(0.04, 0.42, 0.42), CFrame.new(c + u * 0.55) * CFrame.Angles(0, alongX and math.rad(90) or 0, 0) * CFrame.Angles(math.rad(45), 0, 0), WHITE, M.SmoothPlastic))
		end
	end
	for _, zi in { 2, 4, 6 } do -- traffic lights at 3 of 6 spine intersections [SPEC 4.1]
		local zc = SPEC.EW[zi]
		local m = model(sg, "Signal_Z" .. (zi - 1))
		vcyl(m, 44.8, Y, 17.4, zc - 9.2, 0.6, METAL, M.Metal) -- spine approach (southbound), arm over the carriageway
		box(m, 44.8, 16.6, zc - 9.4, 59, 17.0, zc - 9.0, METAL, M.Metal)
		box(m, 50.4, 13.2, zc - 9.8, 51.6, 16.6, zc - 8.6, BLACK, M.SmoothPlastic)
		thin(box(m, 50.6, 13.5, zc - 9.95, 51.4, 14.3, zc - 9.8, c3(60, 220, 120), M.Neon))
		vcyl(m, 64.2, Y, 17.4, zc - 9.2, 0.6, METAL, M.Metal) -- cross-street approach (westbound), arm over Z
		box(m, 64.0, 16.6, zc - 9.2, 64.4, 17.0, zc + 4, METAL, M.Metal)
		box(m, 63.6, 13.2, zc - 2.6, 64.8, 16.6, zc - 1.4, BLACK, M.SmoothPlastic)
		thin(box(m, 64.8, 15.6, zc - 2.4, 64.95, 16.4, zc - 1.6, c3(220, 50, 40), M.Neon))
		thin(box(m, SPX - CWH, 0.07, zc - 16.2, SPX + CWH, 0.1, zc - 15.7, LINE, M.SmoothPlastic)) -- stop lines
		thin(box(m, SPX + 15, 0.08, zc - CWH, SPX + 15.5, 0.1, zc + CWH, LINE, M.SmoothPlastic))
	end
	flush(sg, "Signage")

	-- markings: lane dashes (0.25), crosswalks (1.0 / 1.0 bars), topes (40 / 40 stripes at 45 deg) [SPEC 4.2]
	local mk = newm("Markings")
	local per = SPEC.DashLen + SPEC.DashGap
	for z = SPEC.EW[1] - CWH - 18, SPEC.BridgeEnd + 12, -per do
		if not nearEW(z, 18) and not nearEW(z - SPEC.DashLen, 18) then
			local y = (z > SPEC.Lip) and 0.07 or 0.08
			thin(box(mk, SPX - 0.125, y, z - SPEC.DashLen, SPX + 0.125, y + 0.02, z, LINE, M.SmoothPlastic))
		end
	end
	for _, lx in { NSX.AVW.x - (AVW_IN + AVW_OUT) / 2, NSX.AVW.x + (AVW_IN + AVW_OUT) / 2 } do
		for z = SPEC.EW[1] - CWH - 14, SPEC.EW[6] + CWH + 6, -(2 * per) do
			if not nearEW(z, 14) and not nearEW(z - SPEC.DashLen, 14) then thin(box(mk, lx - 0.125, 0.07, z - SPEC.DashLen, lx + 0.125, 0.09, z, LINE, M.SmoothPlastic)) end
		end
	end
	for _, zc in SPEC.EW do -- crosswalks at every spine intersection: across the spine (north side) and across the cross street (west)
		for k = 0, 7 do
			local x = SPX - CWH + 0.5 + 2 * k
			thin(box(mk, x - 0.5, 0.07, zc - 15, x + 0.5, 0.09, zc - 9, LINE, M.SmoothPlastic))
			local z = zc - CWH + 0.5 + 2 * k
			thin(box(mk, SPX - 21, 0.08, z - 0.5, SPX - 15, 0.1, z + 0.5, LINE, M.SmoothPlastic))
		end
	end
	for _, tp in { { "ns", NSX.X255.x, -270 }, { "ew", -330, SPEC.EW[4] } } do -- topes on two secondary streets
		local m = model(mk, "Tope")
		local x, z = tp[2], tp[3]
		if tp[1] == "ns" then box(m, x - CWH, 0.07, z - 1.2, x + CWH, 0.37, z + 1.2, c3(110, 104, 92), M.Asphalt)
		else box(m, x - 1.2, 0.08, z - CWH, x + 1.2, 0.37, z + CWH, c3(110, 104, 92), M.Asphalt) end
		for k = 0, 7 do
			local o = -CWH + 1 + 2 * k
			local c = (tp[1] == "ns") and Vector3.new(x + o, 0.38, z) or Vector3.new(x, 0.38, z + o)
			thin(part(m, Vector3.new(1.0, 0.02, 2.2), CFrame.new(c) * CFrame.Angles(0, math.rad(45), 0), YELLOW, M.SmoothPlastic))
		end
	end
	flush(mk, "Streets")

	-- facades: every building face on a street (detail per face), lots: gate leaves
	for i, p in PLOTS do
		local m = plotModel(p, true)
		local ws = { bay = rn(r, SPEC.WinBay[1], SPEC.WinBay[2]), w = rn(r, SPEC.WinW[1], SPEC.WinW[2]), h = rn(r, SPEC.WinH[1], SPEC.WinH[2]), fc = pick(r, FRAMEC) }
		if p.kind == "building" then
			for _, f in p.faces do
				local a0, a1 = faceInfo(p, f)
				local d = p.detail[f]
				if p.shop then shopGround(m, p, f, a0, a1, r, d) else houseGround(m, p, f, a0, a1, r, d, ws) end
				upperFloors(m, p, f, a0, a1, r, d, ws)
			end
		elseif r:NextNumber() < 0.5 then -- closed sheet-metal gate (half of the lots)
			onFace(m, p, p.f, p.gate, p.gw - 0.2, 0, SPEC.Barda - 0.5, -0.2, 0.15, pick(r, SHUTTERC), M.Metal)
		end
		if i % 60 == 0 then task.wait() end
	end
	do -- landmark street-level detail: tower glazing, church portal / windows, clock faces, EB sign
		local L = G.Landmarks
		local tm = L:FindFirstChild("Tower") or model(L, "Tower")
		for s = 1, 16 do -- v2: individual windows (no storey bands)
			local y = 10 + SPEC.UF * (s - 1)
			for _, f in { "N", "S", "W", "E" } do
				local a0, a1 = faceInfo(TOWER, f)
				local bw = (a1 - a0) / SPEC.TowerWin
				for k = 0, SPEC.TowerWin - 1 do thin(onFace(tm, TOWER, f, a0 + (k + 0.5) * bw, 3.6, y + 1.8, y + 5.6, 0.08, 0.25, GLASS, M.Glass)) end
			end
		end
		for _, f in { "N", "W" } do
			local a0, a1 = faceInfo(TOWER, f)
			thin(onFace(tm, TOWER, f, (a0 + a1) / 2, (a1 - a0) * 0.7, Y, 8.4, 0.1, 0.3, GLASS, M.Glass))
		end
		onFace(tm, TOWER, "N", (TOWER.x0 + TOWER.x1) / 2, 14, 8.6, 9.2, 4.5, 4.5, CONC, M.Concrete) -- entrance canopy
		local cm = L:FindFirstChild("Church") or model(L, "Church")
		local fr = { x0 = CH.nave[3], x1 = CH.nave[3] + 2, z0 = CH.nave[2] - 2, z1 = CH.nave[4] + 2 }
		thin(onFace(cm, fr, "E", -905, 6, 0.6, 12, 0.1, 0.3, DARK, M.Wood))
		thin(onFace(cm, fr, "E", -905, 8.4, 12, 13.2, 0.25, 0.4, c3(176, 160, 132), M.Plaster))
		thin(part(cm, Vector3.new(0.3, 4, 4), CFrame.new(CH.nave[3] + 2.1, 22, -905), DARK, M.Glass, Enum.PartType.Cylinder))
		local nv = { x0 = CH.nave[1], x1 = CH.nave[3], z0 = CH.nave[2], z1 = CH.nave[4] }
		for _, f in { "N", "S" } do
			for k = 0, 3 do thin(onFace(cm, nv, f, CH.nave[1] + 10 + k * 14, 2, 13, 20, 0.08, 0.3, DARK, M.Glass)) end
		end
		box(cm, CH.tower[1] + 1.5, 50, CH.tower[2] + 1.5, CH.tower[3] - 1.5, 58, CH.tower[4] - 1.5, DARK, M.SmoothPlastic) -- belfry void
		local ck = L:FindFirstChild("ClockTower") or model(L, "ClockTower")
		for _, f in { "N", "S", "W", "E" } do
			local d = DISC[f]
			local c = Vector3.new(CLOCK.x, 31, CLOCK.z) + FDIR[f] * 3.3
			thin(part(ck, Vector3.new(0.12, 4.2, 4.2), CFrame.new(c) * CFrame.Angles(0, d[1], 0), c3(236, 230, 210), M.SmoothPlastic, Enum.PartType.Cylinder))
			local alongX = (f == "N" or f == "S")
			thin(part(ck, alongX and Vector3.new(0.2, 1.7, 0.05) or Vector3.new(0.05, 1.7, 0.2), CFrame.new(c + FDIR[f] * 0.1 + Vector3.new(0, 0.7, 0)), BLACK, M.SmoothPlastic))
			thin(part(ck, alongX and Vector3.new(1.3, 0.2, 0.05) or Vector3.new(0.05, 0.2, 1.3), CFrame.new(c + FDIR[f] * 0.1 + (alongX and Vector3.new(0.55, 0, 0) or Vector3.new(0, 0, 0.55))), BLACK, M.SmoothPlastic))
		end
		local em = L:FindFirstChild("EB") or model(L, "EB")
		local ebs = thin(box(em, 16.5, 7.2, EB.z1 + 0.1, 26.5, 8.6, EB.z1 + 0.3, c3(212, 182, 78), M.SmoothPlastic))
		label(ebs, Enum.NormalId.Back, "ABARROTES", BLACK)
	end
	task.wait()

	-- utilities: concrete poles 22.5 every ~90 along every E-W street (north side), 2-3 wires, transformer 1 in 4,
	-- street light on every third pole [SPEC 4.4]
	local ut = newm("Poles")
	for i, zc in SPEC.EW do
		local zp = zc - CWH - 1.2
		local xs, x = {}, XW + 25
		while x < XE[i] - 10 do
			local xx = x + rn(r, -8, 8)
			for _, s in SPEC.NS do
				local hw = (s.k == "avw") and AVW_OUT or CWH
				if math.abs(xx - s.x) < hw + 3 then xx = s.x + hw + 3.5 end
			end
			table.insert(xs, math.min(xx, XE[i] - 4))
			x += SPEC.PoleStep
		end
		for k, px in xs do
			vcyl(ut, px, Y, Y + SPEC.PoleH, zp, 1.0, c3(150, 148, 142), M.Concrete)
			box(ut, px - 0.2, 21.4, zp - 2.2, px + 0.2, 21.8, zp + 2.2, c3(140, 138, 132), M.Concrete) -- crossarm
			if k % 4 == 2 then vcyl(ut, px + 0.95, 16.2, 19.0, zp, 1.6, c3(120, 124, 126), M.Metal) end
			if k % 3 == 1 then
				thin(box(ut, px - 0.12, 18.5, zp, px + 0.12, 18.75, zp + 5.6, METAL, M.Metal))
				thin(box(ut, px - 0.5, 18.1, zp + 5.0, px + 0.5, 18.5, zp + 6.4, c3(222, 222, 212), M.SmoothPlastic))
			end
			local nx = xs[k + 1]
			if nx then
				for _, wz in { zp - 1.9, zp + 1.9 } do thin(box(ut, px, 21.85, wz - 0.05, nx, 21.95, wz + 0.05, BLACK, M.SmoothPlastic)) end
				if r:NextNumber() < 0.2 then thin(box(ut, px, 18.9, zp + 0.55, nx, 19.0, zp + 0.65, BLACK, M.SmoothPlastic)) end
			end
		end
	end
	flush(ut, "Utilities")
	local lt = newm("StreetLights")
	for z = 40, SPEC.EW[6] + 10, -80 do -- spine (east sidewalk)
		if not nearEW(z, 20) then
			vcyl(lt, SPX + CWH + 3.8, Y, 20, z, 0.5, METAL, M.Metal)
			thin(box(lt, SPX + 2, 19.3, z - 0.12, SPX + CWH + 3.8, 19.55, z + 0.12, METAL, M.Metal))
			thin(box(lt, SPX + 1.4, 18.9, z - 0.5, SPX + 3.2, 19.3, z + 0.5, c3(222, 222, 212), M.SmoothPlastic))
		end
	end
	for z = 30, SPEC.EW[6] + 20, -110 do -- AV-W median, double arm
		if not nearEW(z, 24) then
			vcyl(lt, NSX.AVW.x, 0.6, 22, z, 0.6, METAL, M.Metal)
			thin(box(lt, NSX.AVW.x - 10, 21.3, z - 0.12, NSX.AVW.x + 10, 21.6, z + 0.12, METAL, M.Metal))
			for _, s in { -1, 1 } do thin(box(lt, NSX.AVW.x + s * 9.2 - 0.8, 20.9, z - 0.45, NSX.AVW.x + s * 9.2 + 0.8, 21.3, z + 0.45, c3(222, 222, 212), M.SmoothPlastic)) end
		end
	end
	for _, q in { { -126, -76 }, { -76, -76 }, { -126, -24 }, { -76, -24 }, { -222, -135 }, { -222, 35 }, { -101, -137 }, { -101, 37 } } do -- plaza lamps
		vcyl(lt, q[1], 0.06, 11, q[2], 0.35, c3(40, 46, 44), M.Metal)
		box(lt, q[1] - 0.6, 11, q[2] - 0.6, q[1] + 0.6, 12.2, q[2] + 0.6, c3(236, 232, 214), M.SmoothPlastic)
	end
	flush(lt, "Utilities")

	-- vegetation: plaza rows, atrium, thornscrub on lots / edges / scarp / bank, AV-W median, block interiors [SPEC 4.4]
	local vp = newm("PlazaTrees")
	for k = 0, 8 do
		local x = -226 + 26 * k
		plazaTree(vp, x, -137, r)
		plazaTree(vp, x, 37, r)
	end
	for _, bd in BEDS do
		for _, q in { { bd[1] + 8, bd[2] + 8 }, { bd[3] - 8, bd[2] + 8 }, { bd[1] + 8, bd[4] - 8 }, { bd[3] - 8, bd[4] - 8 } } do plazaTree(vp, q[1], q[2], r) end
	end
	for _, q in { { 14, -922 }, { 14, -888 }, { 33, -922 }, { 33, -888 } } do plazaTree(vp, q[1], q[2], r) end -- church atrium
	flush(vp, "Vegetation")
	local vs = newm("Thornscrub")
	for _, p in LOTS do
		local x0, z0, x1, z1 = band(p, 2.5, depthOf(p) - ((p.kind == "court") and 18 or 2))
		for _ = 1, 2 do scrub(vs, rn(r, x0 + 1, x1 - 1), 0.03, rn(r, z0 + 1, z1 - 1), r) end
	end
	for _, b in BLOCKS do
		if b.row <= 3 then scrub(vs, (b.x0 + b.x1) / 2 + rn(r, -5, 5), 0.035, (b.z0 + b.z1) / 2 + rn(r, -20, 20), r, "mesquite") end
		if b.edgeBlock then for _ = 1, 4 do scrub(vs, rn(r, b.x1 - 50, b.x1 - 4), 0.035, rn(r, b.z0 + 60, b.z1 - 60), r) end end
	end
	for _ = 1, 4 do scrub(vs, rn(r, 132, 186), 0.035, rn(r, -88, -12), r) end -- E1R1 edge lot
	for _ = 1, 5 do scrub(vs, rn(r, -657, -644), 0.02, rn(r, -980, 30), r) end -- rail margin
	for _, s in SPEC.NS do
		if s.k == "avw" then
			for ri = 1, 5 do
				local R = ROWS[ri]
				for z = R.zs - CWH - 14, R.zn + CWH + 14, -63 do scrub(vs, s.x + rn(r, -3, 3), 0.6, z, r, "mesquite") end
			end
		end
	end
	flush(vs, "Vegetation")
	local vt = newm("ScarpAndBanks")
	for _ = 1, 22 do
		local x, z = rn(r, -950, 950), rn(r, -1215, -1035)
		if math.abs(x - SPX) < 30 then x += 70 end
		scrub(vt, x, groundY(z) - 0.2, z, r)
	end
	for _ = 1, 10 do scrub(vt, rn(r, -950, 950), -SPEC.Drop, rn(r, -1256, -1228), r, (r:NextNumber() < 0.6) and "shrub" or "mesquite") end
	for _ = 1, 6 do scrub(vt, rn(r, -950, 950), -SPEC.Drop, rn(r, -1488, -1464), r) end
	for _ = 1, 8 do scrub(vt, rn(r, -900, 900), 0, rn(r, -1950, -1660), r, "mesquite") end -- far bank
	flush(vt, "Vegetation")

	-- props: parked cars on one curb (spine west curb R1-R3), plaza benches / bins, frontage clusters, bollards, carts,
	-- bus stop, bridgehead canopy + queue railings, booth, atrium cross; none on carriageways / plaza centre [SPEC 4.4]
	local pr = newm("ParkedCars")
	local function parkLine(axis, c, a0, a1, share, yaw)
		local a = a0
		while a < a1 - 12.5 do
			if r:NextNumber() < share then
				if axis == "z" then car(pr, c, a + 6.25, yaw, r) else car(pr, a + 6.25, c, yaw, r) end
			end
			a += 12.5 + rn(r, 1.5, 6)
		end
	end
	for ri = 1, 3 do -- spine west curb, R1-R3 [SPEC 4.2]
		local R = ROWS[ri]
		parkLine("z", SPX - CWH + 2.6, R.zn + CWH + 4, R.zs - CWH - 10, SPEC.ParkingShare, 0)
	end
	for ri = 1, 3 do
		local R = ROWS[ri]
		local z0, z1 = R.zn + CWH + 4, R.zs - CWH - 6
		if ri == 2 then -- skip the tope at z -270
			parkLine("z", NSX.X255.x - CWH + 2.6, z0, -284, 0.25, 0)
			parkLine("z", NSX.X255.x - CWH + 2.6, -256, z1, 0.25, 0)
		else parkLine("z", NSX.X255.x - CWH + 2.6, z0, z1, 0.25, 0) end
	end
	-- PARAMETER C1 curbs: 25 % of the slots occupied (spine west curb: SPEC.ParkingShare)
	for ri = 2, 4 do local R = ROWS[ri]; parkLine("z", NSX.X410.x + CWH - 2.6, R.zn + CWH + 12, R.zs - CWH - 20, 0.25, math.pi) end
	for ri = 2, 3 do local R = ROWS[ri]; parkLine("z", NSX.E1.x - CWH + 2.6, R.zn + CWH + 12, R.zs - CWH - 20, 0.25, math.pi) end
	for _, seg in { { -390, -268 }, { -242, -114 }, { -86, 28 } } do parkLine("x", SPEC.EW[2] - CWH + 2.6, seg[1] + 6, seg[2] - 6, 0.25, math.rad(90)) end
	for _, seg in { { -242, -114 }, { -86, 28 } } do parkLine("x", SPEC.EW[3] - CWH + 2.6, seg[1] + 6, seg[2] - 6, 0.25, math.rad(-90)) end
	flush(pr, "Props")
	local pp = newm("StreetProps")
	local benches = { { -190, -70, 0 }, { -150, -70, 0 }, { -190, -30, 1 }, { -150, -30, 1 }, { -56, -70, 0 }, { -30, -70, 0 }, { -56, -30, 1 }, { -30, -30, 1 },
		{ -127.6, -100, 2 }, { -74.4, -100, 3 }, { -127.6, 0, 2 }, { -74.4, 0, 3 } }
	for _, bq in benches do -- solid concrete benches facing the paths (back toward the bed)
		local m = coverModel(pp, "Bench", 3.2)
		local x, z, o = bq[1], bq[2], bq[3]
		if o <= 1 then
			box(m, x - 2.5, 0.06, z - 0.8, x + 2.5, 1.7, z + 0.8, c3(176, 168, 156), M.Concrete)
			local bz = (o == 0) and (z - 0.8) or (z + 0.5)
			box(m, x - 2.5, 1.7, bz, x + 2.5, 3.2, bz + 0.3, c3(176, 168, 156), M.Concrete)
		else
			box(m, x - 0.8, 0.06, z - 2.5, x + 0.8, 1.7, z + 2.5, c3(176, 168, 156), M.Concrete)
			local bx = (o == 2) and (x - 0.8) or (x + 0.5)
			box(m, bx, 1.7, z - 2.5, bx + 0.3, 3.2, z + 2.5, c3(176, 168, 156), M.Concrete)
		end
	end
	for _, q in { { -123, -74 }, { -79, -74 }, { -123, -26 }, { -79, -26 }, { -219, -135 }, { -109, 37 } } do
		vcyl(coverModel(pp, "Bin", 2.6), q[1], 0.06, 2.66, q[2], 1.6, c3(60, 92, 70), M.Metal)
	end
	local nClusters = 0
	for _, p in PLOTS do -- frontage clusters at detailed shopfronts (main face)
		if p.kind == "building" and p.shop and p.detail[p.f] then
			local u = r:NextNumber()
			local a0, a1, c, sgn, ax = faceInfo(p, p.f)
			local a = a0 + (a1 - a0) * rn(r, 0.15, 0.85)
			if u < 0.55 then -- PARAMETER 55 % of detailed shopfronts carry a cover cluster
				nClusters += 1
				local kind = r:NextInteger(1, 4)
				local hgt = ({ 2.2, 3.4, 4.4, 3.4 })[kind]
				local m = coverModel(pp, ({ "Planter", "GasCylinders", "Crates", "WaterBarrel" })[kind], hgt)
				local function at(off, w, d) -- centre along a, off from the facade, size w along / d across
					local q = c + sgn * off
					if ax == "x" then return a - w / 2, q - d / 2, a + w / 2, q + d / 2 end
					return q - d / 2, a - w / 2, q + d / 2, a + w / 2
				end
				if kind == 1 then
					local x0, z0, x1, z1 = at(1.3 + 0.8, 3.2, 1.6)
					box(m, x0, Y, z0, x1, Y + 2.2, z1, c3(160, 150, 136), M.Concrete)
					deco(part(m, Vector3.new(2.2, 2.2, 2.2), CFrame.new((x0 + x1) / 2, Y + 2.9, (z0 + z1) / 2), SHRUBC, M.LeafyGrass, Enum.PartType.Ball), false)
				elseif kind == 2 then
					for k = -1, 1, 2 do
						local x0, z0, x1, z1 = at(1.9, 1.1, 1.1)
						local dx, dz = (ax == "x") and k * 0.7 or 0, (ax == "z") and k * 0.7 or 0
						vcyl(m, (x0 + x1) / 2 + dx, Y, Y + 3.4, (z0 + z1) / 2 + dz, 1.1, pick(r, { c3(200, 200, 196), c3(120, 130, 140) }), M.Metal)
					end
				elseif kind == 3 then
					local x0, z0, x1, z1 = at(1.3 + 1.2, 2.4, 2.4)
					box(m, x0, Y, z0, x1, Y + 2.2, z1, c3(150, 120, 84), M.WoodPlanks)
					box(m, x0 + 0.2, Y + 2.2, z0 + 0.2, x1 - 0.2, Y + 4.4, z1 - 0.2, c3(140, 110, 78), M.WoodPlanks)
				else
					local x0, z0, x1, z1 = at(1.3 + 1.1, 2.2, 2.2)
					vcyl(m, (x0 + x1) / 2, Y, Y + 3.4, (z0 + z1) / 2, 2.2, c3(50, 80, 130), M.Plastic)
				end
			end
		end
	end
	for _, zi in { 2, 4, 6 } do -- bollards at the signalled spine corners
		local zc = SPEC.EW[zi]
		local m = coverModel(pp, "Bollards", 2.2)
		for _, xb in { SPX - CWH - 0.8, SPX + CWH + 0.8 } do
			for k = 0, 2 do vcyl(m, xb, Y, Y + 2.2, zc - CWH - 2.5 - k * 1.6, 0.6, c3(70, 70, 72), M.Metal) end
		end
	end
	for _, q in { { -160, -140.5 }, { -60, -140.5 }, { -101, 41 } } do -- vendor carts at the plaza edge paths
		local m = coverModel(pp, "VendorCart", 3.0)
		box(m, q[1] - 2, 0.06, q[2] - 1.1, q[1] + 2, 3.0, q[2] + 1.1, pick(r, { c3(200, 60, 50), c3(220, 220, 214), c3(60, 110, 160) }), M.Metal)
		vcyl(m, q[1], 3.0, 7.0, q[2], 0.15, METAL, M.Metal)
		thin(part(m, Vector3.new(0.15, 5, 5), CFrame.new(q[1], 7.0, q[2]) * CFrame.Angles(0, 0, math.rad(90)), pick(r, AWNC), M.Fabric, Enum.PartType.Cylinder))
	end
	do -- bridgehead (Bridge I): pedestrian canopy + queue railings on the east walkway, booth, bus stop [SPEC 4.1]
		local m = model(pp, "BridgeheadCanopy")
		for _, x in { SPX + CWH + 0.5, SPX + 14.7 } do for _, z in { -1015, -1036, -1057 } do vcyl(m, x, Y, 9.2, z, 0.5, METAL, M.Metal) end end
		box(m, SPX + 7.6, 9.2, -1060, SPX + 15.6, 9.6, -1012, c3(196, 196, 190), M.Metal)
		for _, x in { SPX + 10.6, SPX + 12.6 } do
			local q = model(m, "QueueRail")
			local rl = box(q, x - 0.08, Y + 2.45, -1058, x + 0.08, Y + 2.7, -1013, METAL, M.Metal)
			rl.CanQuery = false
			for z = -1013, -1058, -9 do box(q, x - 0.08, Y, z - 0.08, x + 0.08, Y + 2.45, z + 0.08, METAL, M.Metal).CanQuery = false end
		end
		local bt = model(pp, "Booth")
		setB(bt, 1, 9.5, "booth")
		box(bt, 26, Y, -1021.5, 36, 9.0, -1014, c3(214, 208, 194), M.Plaster)
		box(bt, 25.4, 9.0, -1022.1, 36.6, 9.5, -1013.4, c3(150, 150, 146), M.Metal)
		thin(onFace(bt, { x0 = 26, x1 = 36, z0 = -1021.5, z1 = -1014 }, "S", 31, 6, 3.4, 6.6, 0.08, 0.2, GLASS, M.Glass))
		local bs = coverModel(pp, "BusStop", 2.0)
		box(bs, 84, 8.2, -1017.2, 100, 8.5, -1011.6, c3(150, 150, 146), M.Metal)
		thin(box(bs, 85, Y, -1016.7, 99, 7.4, -1016.5, c3(170, 190, 200), M.Glass), 0.5)
		for _, x in { 85, 99 } do vcyl(bs, x, Y, 8.2, -1016.6, 0.3, METAL, M.Metal) end
		box(bs, 87, Y, -1016.2, 97, 2.0, -1014.8, c3(120, 120, 118), M.Metal)
	end
	do
		local m = coverModel(pp, "AtriumCross", 2.0)
		local x, z = (CH.atrium[1] + CH.atrium[3]) / 2, -905
		box(m, x - 1, 0.6, z - 1, x + 1, 2.6, z + 1, c3(180, 170, 150), M.Concrete)
		box(m, x - 0.3, 2.6, z - 0.3, x + 0.3, 8.6, z + 0.3, c3(196, 186, 166), M.Concrete)
		box(m, x - 0.3, 6.4, z - 1.6, x + 0.3, 7.0, z + 1.6, c3(196, 186, 166), M.Concrete)
	end
	flush(pp, "Props")

	-- logistics and tract street level: ties at the crossing, trucks, containers, yard masts, tinacos
	local lc = newm("YardProps")
	for _, tx in { -632, -622 } do
		for z = -420, -340, 5 do
			if math.abs(z - SPEC.EW[3]) > 9 then box(lc, tx - 2.8, 0.55, z - 0.4, tx + 2.8, 0.72, z + 0.4, c3(90, 80, 70), M.Wood) end
		end
	end
	truck(lc, -740, -295, math.pi); truck(lc, -700, -295, math.pi); truck(lc, -835, -305, math.pi)
	truck(lc, -705, -668, -math.pi / 2); truck(lc, -705, -650, -math.pi / 2); truck(lc, -800, -380, math.pi / 2)
	for k = 0, 3 do
		local m = coverModel(lc, "Container", (k < 2) and 13 or 6.5)
		local z = -470 + k * 17
		box(m, -897.5, 0.03, z - 7.6, -891.4, 6.53, z + 7.6, pick(r, { c3(150, 60, 40), c3(40, 80, 120), c3(60, 110, 70), c3(170, 150, 110) }), M.Metal)
		if k < 2 then box(m, -897.5, 6.53, z - 7.6, -891.4, 13.03, z + 7.6, pick(r, { c3(150, 60, 40), c3(40, 80, 120), c3(200, 196, 186) }), M.Metal) end
	end
	for _, q in { { -668, -128 }, { -892, -128 }, { -892, -692 }, { -668, -560 } } do
		vcyl(lc, q[1], 0, 40, q[2], 0.8, METAL, M.Metal)
		box(lc, q[1] - 1.5, 40, q[2] - 1.5, q[1] + 1.5, 41, q[2] + 1.5, c3(222, 222, 212), M.SmoothPlastic)
	end
	flush(lc, "Logistics")
	local tt = newm("Tinacos")
	local T = SPEC.Tract
	local base = CFrame.new(TRACT_C) * CFrame.Angles(0, math.rad(T.rot), 0)
	local pitch, per = T.w + SPEC.TractStreet, math.floor(T.l / 15.25)
	for bi = -1, 1 do
		for _, side in { -1, 1 } do
			for k = 0, per - 1 do
				if r:NextNumber() < SPEC.Tinaco then
					local lz = -T.l / 2 + (k + 0.5) * (T.l / per)
					local lx = bi * pitch + side * (T.w / 2 - 6 - 12.5 - 6)
					part(tt, Vector3.new(3.5, 2.75, 2.75), base * CFrame.new(lx, SPEC.TractHouseH + 1.75, lz) * CFrame.Angles(0, 0, math.rad(90)), c3(34, 34, 36), M.Plastic, Enum.PartType.Cylinder)
				end
			end
		end
	end
	flush(tt, "Tract")
	return nClusters
end

------------------------------------------------------------------------------------------------------------------------
-- PASS D: materials / breakup (palette variation, base grime / painted socles, drain stains, patched asphalt, cracked
-- sidewalks, dirt at kerbs). Pass E (lighting) is evaluation only and builds nothing.
local function near(a, b) return math.abs(a.R - b.R) < 0.006 and math.abs(a.G - b.G) < 0.006 and math.abs(a.B - b.B) < 0.006 end
local function passD()
	local r = Random.new(SPEC.Seed + 4)
	local Y = SPEC.Walk
	for _, p in PLOTS do -- palette variation on the Pass B volumes (recolour only, no new parts)
		local dh, ds, dv = rn(r, -0.012, 0.012), rn(r, -0.03, 0.03), rn(r, -0.05, 0.04)
		local m = plotModel(p, false)
		if m and p.kind == "building" then
			for _, d in m:GetChildren() do
				if d:IsA("BasePart") and near(d.Color, p.col) then
					local h, s, v = d.Color:ToHSV()
					s = (p.mat == M.Plaster) and math.clamp(s + ds, 0, 0.35) or math.clamp(s + ds, 0, 1)
					d.Color = Color3.fromHSV((h + dh) % 1, s, math.clamp(v + dv, 0.2, 0.95))
				end
			end
		end
	end
	local bk = newm("Facades")
	for _, p in PLOTS do
		local zoc, stain, zc, sa = r:NextNumber() < 0.35, r:NextNumber() < 0.3, pick(r, ZOCALO), r:NextNumber()
		if p.kind == "building" then
			for _, f in p.faces do
				if p.detail[f] then
					local a0, a1 = faceInfo(p, f)
					local L = a1 - a0
					if zoc then thin(onFace(bk, p, f, (a0 + a1) / 2, L, Y, Y + 1.9, 0.05, 0.05, zc, M.Plaster)) -- painted socle
					else thin(onFace(bk, p, f, (a0 + a1) / 2, L, Y, Y + 1.1, 0.04, 0.04, p.col:Lerp(c3(60, 54, 48), 0.45), M.Plaster)) end -- base grime
					if stain and f == p.f and p.roof == "flat" then
						thin(onFace(bk, p, f, a0 + L * (0.1 + 0.8 * sa), 0.9, p.H - 6, p.H + SPEC.Parapet - 0.2, 0.03, 0.03, p.col:Lerp(c3(70, 66, 60), 0.35), M.Plaster))
					end
				end
			end
		end
	end
	flush(bk, "Breakup")
	local ap = newm("AsphaltPatches")
	for _ = 1, 30 do
		local w, d = rn(r, 3, 8), rn(r, 2, 5)
		local col = PATCHC:Lerp(ASPHALT, r:NextNumber() * 0.5)
		if r:NextNumber() < 0.55 then
			local i = r:NextInteger(1, 6)
			local x, z = rn(r, XW + 10, XE[i] - 10), SPEC.EW[i] + rn(r, -CWH + d / 2 + 0.3, CWH - d / 2 - 0.3)
			if not nearNS(x, 12) then thin(box(ap, x - w / 2, 0.08, z - d / 2, x + w / 2, 0.092, z + d / 2, col, M.Asphalt)) end
		else
			local s = SPEC.NS[r:NextInteger(1, 6)]
			local rr = NSROWS[s.id]
			local R = ROWS[r:NextInteger(rr[1], rr[2])]
			local side = (r:NextNumber() < 0.5) and -1 or 1
			local cx, hx = s.x, CWH
			if s.k == "avw" then cx, hx = s.x + side * (AVW_IN + AVW_OUT) / 2, SPEC.AVW.cw / 2 end
			local x, z = cx + rn(r, -hx + d / 2 + 0.3, hx - d / 2 - 0.3), rn(r, R.zn + CWH + 18, R.zs - CWH - 18)
			thin(box(ap, x - d / 2, 0.07, z - w / 2, x + d / 2, 0.082, z + w / 2, col, M.Asphalt))
		end
	end
	flush(ap, "Breakup")
	local cs = newm("SidewalkPatches")
	for _ = 1, 60 do -- v2: 60 patched / cracked segments, 75 % darker than the walk (PARAMETER)
		local b = BLOCKS[r:NextInteger(1, #BLOCKS)]
		local f = pick(r, { "N", "S", "W", "E" })
		local w = b.sw[f]
		local L, D = rn(r, 2.5, 7), rn(r, 1.2, 2.6)
		local col = SIDEWALK:Lerp((r:NextNumber() < 0.75) and c3(116, 110, 100) or c3(178, 172, 160), rn(r, 0.35, 0.8))
		local ua, uc = r:NextNumber(), r:NextNumber()
		if w > 0 then
			local c0, c1 = 0.6, math.max(0.6 + D, w - 0.6) -- across: from the facade line toward the kerb
			local off = c0 + D / 2 + (c1 - c0 - D) * uc
			if f == "N" or f == "S" then
				local x = b.x0 + 3 + L / 2 + (b.x1 - b.x0 - 6 - L) * ua
				local z = (f == "N") and (b.z0 - off) or (b.z1 + off)
				thin(box(cs, x - L / 2, Y, z - D / 2, x + L / 2, Y + 0.012, z + D / 2, col, M.Concrete))
			else
				local z = b.z0 + 3 + L / 2 + (b.z1 - b.z0 - 6 - L) * ua
				local x = (f == "W") and (b.x0 - off) or (b.x1 + off)
				thin(box(cs, x - D / 2, Y, z - L / 2, x + D / 2, Y + 0.012, z + L / 2, col, M.Concrete))
			end
		end
	end
	flush(cs, "Breakup")
	local kd = newm("KerbDirt")
	for _, b in BLOCKS do
		for _, f in { "N", "S", "W", "E" } do
			local w = b.sw[f]
			local col = CALICHE:Lerp(ASPHALT, rn(r, 0.2, 0.5))
			if w > 0 and r:NextNumber() < 0.45 then
				if f == "N" then thin(box(kd, b.x0, 0.08, b.z0 - w - 0.9, b.x1, 0.092, b.z0 - w, col, M.Ground))
				elseif f == "S" then thin(box(kd, b.x0, 0.08, b.z1 + w, b.x1, 0.092, b.z1 + w + 0.9, col, M.Ground))
				elseif f == "W" then thin(box(kd, b.x0 - w - 0.9, 0.07, b.z0, b.x0 - w, 0.082, b.z1, col, M.Ground))
				else thin(box(kd, b.x1 + w, 0.07, b.z0, b.x1 + w + 0.9, 0.082, b.z1, col, M.Ground)) end
			end
		end
	end
	flush(kd, "Breakup")
end

------------------------------------------------------------------------------------------------------------------------
-- PASS V (v3 presentation): lip railing with river-stair openings, two stairways down the scarp, facade-detail kit on
-- detailed buildings. Draws only from Random.new(SPEC.SeedV3); reads the v2 facades back from the built models, so no
-- v2 part or draw changes. Every container is tagged M2v3 = true.
local STAIRC, PATHC = c3(150, 146, 138), c3(126, 116, 100)
local function lipAndStairs()
	local Y = SPEC.Walk
	local t = newm("LipAndStairsV3")
	t:SetAttribute("M2v3", true)
	local zr = SPEC.Lip + 0.3
	for _, xx in { { XWW, SPX - SPEC.Deck / 2 }, { SPX + SPEC.Deck / 2, COLS[6].x1 } } do -- kerb wall + railing, split at the stair openings
		local segs, a = {}, xx[1]
		for _, xc in SPEC.StairX do
			local o0, o1 = xc - SPEC.LipOpening / 2, xc + SPEC.LipOpening / 2
			if o0 > xx[1] and o1 < xx[2] then table.insert(segs, { a, o0 }); a = o1 end
		end
		table.insert(segs, { a, xx[2] })
		for _, sg in segs do
			box(t, sg[1], -0.4, SPEC.Lip, sg[2], Y + SPEC.LipKerb, SPEC.Lip + 0.6, CONC, M.Concrete)
			local n = math.max(1, math.floor((sg[2] - sg[1]) / SPEC.LipPostStep + 0.5))
			for k = 0, n do
				local x = math.clamp(sg[1] + (sg[2] - sg[1]) * k / n, sg[1] + 0.15, sg[2] - 0.15)
				box(t, x - 0.12, Y + SPEC.LipKerb, zr - 0.12, x + 0.12, Y + SPEC.LipRails[2] + 0.12, zr + 0.12, METAL, M.Metal).CanQuery = false
			end
			for _, hr in SPEC.LipRails do
				box(t, sg[1], Y + hr - 0.06, zr - 0.06, sg[2], Y + hr + 0.06, zr + 0.06, METAL, M.Metal).CanQuery = false
			end
		end
	end
	-- stairways: top landing in the opening, 8 flights of 10 risers (0.599) x 2.4 treads (14.0 deg) with 2.5 landings (12.7
	-- deg overall vs the 13.4 deg scarp: every tread stays above the slope), solid treads down into the slope, low side
	-- walls, path across the bank to the floodplain track
	local yBot = -SPEC.Drop + 0.06 -- floodplain path top
	local rise = (Y - yBot) / (SPEC.StairFlights * SPEC.StairFlight)
	local hw = SPEC.StairW / 2
	for _, xc in SPEC.StairX do
		local m = model(t, (xc < SPX) and "RiverStair_W" or "RiverStair_E")
		local function block(za, zb, ytop) -- za nearer the lip
			box(m, xc - hw, math.min(groundY(za), groundY(zb)) - 1.5, zb, xc + hw, ytop, za, STAIRC, M.Concrete)
		end
		local function walls(za, ya, zb, yb) -- 1.0 above the nosing line, 2.0 into the steps
			for _, s in { -1, 1 } do
				local x = xc + s * (hw + 0.25)
				local p0, p1 = Vector3.new(x, ya, za), Vector3.new(x, yb, zb)
				local len = (p1 - p0).Magnitude
				part(m, Vector3.new(0.5, 3.0, len), CFrame.lookAt(p0, p1) * CFrame.new(0, -0.5, -len / 2), STAIRC:Lerp(CONC, 0.5), M.Concrete)
			end
		end
		local z, y = SPEC.Lip + 0.6, Y
		block(z, z - SPEC.StairTopLanding, y)
		walls(z, y, z - SPEC.StairTopLanding, y)
		z -= SPEC.StairTopLanding
		for fl = 1, SPEC.StairFlights do
			local z0, y0 = z, y
			for _ = 1, SPEC.StairFlight do
				y -= rise
				block(z, z - SPEC.StairTread, y)
				z -= SPEC.StairTread
			end
			walls(z0, y0, z, y)
			if fl < SPEC.StairFlights then
				block(z, z - SPEC.StairLanding, y)
				walls(z, y, z - SPEC.StairLanding, y)
				z -= SPEC.StairLanding
			end
		end
		if z > -1238 then box(m, xc - hw, -SPEC.Drop - 0.5, -1238, xc + hw, yBot, z, PATHC, M.Ground) end -- to the floodplain track
	end
	return t
end
local function shade(col, r) -- muted: slightly darker or lighter than the wall
	local u = rn(r, -1, 1)
	if u < 0 then return col:Lerp(c3(70, 64, 56), -u * 0.3) end
	return col:Lerp(c3(236, 230, 216), u * 0.35)
end
local function faceParts(m, p, f) -- read the v2 facade back: upper windows, house doors, v2 balcony present
	local _, _, c, _, ax = faceInfo(p, f)
	local wins, doors, balc = {}, {}, false
	for _, q in m:GetChildren() do
		if q:IsA("BasePart") then
			local pos, sz = q.Position, q.Size
			local thinA = (ax == "x") and sz.Z or sz.X
			local along = (ax == "x") and pos.X or pos.Z
			local width = (ax == "x") and sz.X or sz.Z
			local d = (ax == "x") and math.abs(pos.Z - c) or math.abs(pos.X - c)
			if q.Material == M.Glass and sz.Y > 3.45 and sz.Y < 4.05 and pos.Y > 9 and thinA < 0.2 and d < 0.4 then
				table.insert(wins, { a = along, w = width, y0 = pos.Y - sz.Y / 2 })
			elseif q.Material == M.Wood and math.abs(sz.Y - (SPEC.DoorH - 0.4)) < 0.05 and thinA < 0.3 and d < 0.4 then
				table.insert(doors, { a = along, w = width })
			elseif q.Material == M.Concrete and math.abs(thinA - 2.2) < 0.01 and math.abs(sz.Y - 0.35) < 0.01 and d < 1.3 then
				balc = true
			end
		end
	end
	table.sort(wins, function(u, v) if math.abs(u.y0 - v.y0) > 0.01 then return u.y0 < v.y0 end return u.a < v.a end)
	table.sort(doors, function(u, v) return u.a < v.a end)
	return wins, doors, balc
end
local function passV()
	local r = Random.new(SPEC.SeedV3)
	flush(lipAndStairs(), "Terrace")
	local KIT, Y, P = SPEC.Kit, SPEC.Walk, SPEC.Parapet
	local ORDER = { "pipe", "door", "cornice", "sills", "coping", "balcony" }
	local last, nKit = {}, 0
	for _, p in PLOTS do
		local m = (p.kind == "building" and p.anyDetail) and plotModel(p, false) or nil
		if m then
			local km = model(m, "V3Detail")
			km:SetAttribute("M2v3", true)
			local has = {}
			for _, ff in p.faces do has[ff] = true end
			for _, f in p.faces do
				local a0, a1, c, sgn, ax = faceInfo(p, f)
				local L = a1 - a0
				local wins, doors, v2balc = faceParts(m, p, f)
				local fl = {
					coping = p.roof == "flat" and r:NextNumber() < KIT.Coping,
					cornice = p.n >= 2 and r:NextNumber() < KIT.Cornice,
					sills = #wins > 0 and r:NextNumber() < KIT.Sills,
					door = #doors > 0 and r:NextNumber() < KIT.Door,
					pipe = r:NextNumber() < KIT.Pipe,
					balcony = (p.n == 2 or p.n == 3) and #wins > 0 and not v2balc and r:NextNumber() < KIT.Balcony,
				}
				local cnt, i = 0, 1
				for _, k in ORDER do if fl[k] then cnt += 1 end end
				while cnt > 4 do -- never the whole kit on one facade
					if fl[ORDER[i]] then fl[ORDER[i]] = false; cnt -= 1 end
					i += 1
				end
				local function key() local s = ""; for _, k in ORDER do s ..= fl[k] and "1" or "0" end; return s end
				local lk = p.b.id .. f
				if last[lk] == key() then -- never identical to the previous plot on the same block face
					if #wins > 0 then fl.sills = not fl.sills elseif p.roof == "flat" then fl.coping = not fl.coping else fl.pipe = not fl.pipe end
				end
				last[lk] = key()
				local col = shade(p.col, r)
				if fl.coping then -- parapet coping 0.3 high, 0.3 proud (side faces 0.03 lower: no coplanar tops at corners)
					deco(onFace(km, p, f, (a0 + a1) / 2, L, p.H + P, p.H + P + 0.3 - ((f == p.f) and 0 or 0.03), 0.3, 0.9, col, M.Concrete), false)
					nKit += 1
				end
				if fl.cornice then -- floor-line bands
					for s = 1, p.n - 1 do
						deco(onFace(km, p, f, (a0 + a1) / 2, L, H(s) - 0.15, H(s) + 0.2, 0.25, 0.3, col, M.Concrete), false)
						nKit += 1
					end
				end
				local balWin
				if fl.balcony then -- small balcony at a first-floor window: slab + simple rail
					local cand = {}
					for _, w in wins do if w.y0 < H(1) + 2.5 then table.insert(cand, w) end end
					if #cand > 0 then
						balWin = cand[r:NextInteger(1, #cand)]
						local fy = balWin.y0 - 2.0
						deco(onFace(km, p, f, balWin.a, 4.6, fy, fy + 0.3, 1.6, 1.6, col, M.Concrete), false)
						thin(onFace(km, p, f, balWin.a, 4.6, fy + 2.4, fy + 2.52, 1.55, 0.12, METAL, M.Metal))
						for _, s in { -1, 1 } do thin(onFace(km, p, f, balWin.a + s * 2.2, 0.12, fy + 0.3, fy + 2.4, 1.55, 0.12, METAL, M.Metal)) end
						nKit += 4
					end
				end
				for _, w in wins do
					if fl.sills then
						deco(onFace(km, p, f, w.a, w.w + 0.5, w.y0 - 0.42, w.y0 - 0.2, 0.35, 0.4, col, M.Concrete), false)
						nKit += 1
					end
					if w ~= balWin and r:NextNumber() < KIT.AC then -- window AC box 1.6 x 1.0 x 1.2
						deco(onFace(km, p, f, w.a, 1.6, w.y0 + 0.1, w.y0 + 1.1, 1.2, 1.3, c3(206, 206, 200), M.SmoothPlastic), false)
						nKit += 1
					end
				end
				if fl.door then -- door surround: larger contrasting plate behind the door
					for _, d in doors do
						deco(onFace(km, p, f, d.a, d.w + 0.9, Y, Y + SPEC.DoorH + 0.1, 0.06, 0.1, col, M.Concrete), false)
						nKit += 1
					end
				end
				if fl.pipe then -- downpipe at a party-wall end of the face (never at the street corner)
					local c0 = (ax == "x") and has.W or has.N
					local c1 = (ax == "x") and has.E or has.S
					local ea
					if c0 and not c1 then ea = a1 - 0.35 elseif c1 and not c0 then ea = a0 + 0.35
					elseif not c0 and not c1 then ea = (r:NextNumber() < 0.5) and (a0 + 0.35) or (a1 - 0.35) end
					if ea then
						local top = p.H + ((p.roof == "flat") and (P - 0.4) or -0.3)
						local pc = c + sgn * 0.2
						local pos = (ax == "x") and Vector3.new(ea, (Y + top) / 2, pc) or Vector3.new(pc, (Y + top) / 2, ea)
						thin(part(km, Vector3.new(top - Y, 0.3, 0.3), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), col:Lerp(c3(90, 88, 84), 0.5), M.Plastic, Enum.PartType.Cylinder))
						nKit += 1
					end
				end
			end
			if #km:GetChildren() == 0 then km:Destroy() end
		end
	end
	return nKit
end

------------------------------------------------------------------------------------------------------------------------
-- RUN
local t0 = os.clock()
local P = SPEC.PASSES
local nClusters, nKit = 0, 0
if P.A then passA() end
if P.B then passB() end
if P.C then nClusters = passC() end
if P.D then passD() end
if P.V and SPEC.V3 then nKit = passV() end
local parts, scripts, v3n = 0, 0, 0
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		local a = d.Parent
		while a and a ~= root do
			if a:GetAttribute("M2v3") then v3n += 1; break end
			a = a.Parent
		end
	elseif d:IsA("LuaSourceContainer") then scripts += 1 end
end
root:SetAttribute("Parts", parts)
local per = {}
for _, n in GROUPS do
	local c = 0
	for _, d in G[n]:GetDescendants() do if d:IsA("BasePart") then c += 1 end end
	table.insert(per, n .. "=" .. c)
end
local hist, nB, nLot, nShed, nTank, nShop = { 0, 0, 0, 0 }, 0, 0, 0, 0, 0
for _, p in PLOTS do
	if p.kind == "building" then
		nB += 1
		hist[p.n] += 1
		if p.roof == "shed" then nShed += 1 end
		if p.tinaco then nTank += 1 end
		if p.shop then nShop += 1 end
	else nLot += 1 end
end
local pass = (P.A and "A" or "") .. (P.B and "B" or "") .. (P.C and "C" or "") .. (P.D and "D" or "") .. ((P.V and SPEC.V3) and "V" or "")
return string.format("%s passes %s in %.1f s: %d parts (counter %d; v3 additions %d, facade kit %d), %d scripts, %d SurfaceGui signs\n%s\nplots %d: buildings %d (1/2/3/4 storeys %d/%d/%d/%d, shops %d, shed roofs %d, tinacos %d), lots/courtyards %d; frontage clusters %d",
	SPEC.Version, pass, os.clock() - t0, parts, count, v3n, nKit, scripts, signCount, table.concat(per, " "), #PLOTS, nB, hist[1], hist[2], hist[3], hist[4], nShop, nShed, nTank, nLot, nClusters)
