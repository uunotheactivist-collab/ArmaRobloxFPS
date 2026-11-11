--[[ M2 facade + material pass (2026-11-11). Run in Studio EDIT (command bar / execute_luau) AFTER build_map.luau.
Deterministic (Random seed below) and idempotent: every colour / material is ASSIGNED (not scaled), and the added parts
live in Workspace.PresentationMap_M2.FacadeV4, which is rebuilt on every run. The structural baseline is frozen: no
existing part is moved, resized, re-parented or deleted; only Color / Material of existing parts change, and the new
parts are thin, non-colliding, non-query surface layers. Lighting (C9) and the viewmodel fill (v3) are not touched.
Evidence and measurements: Fidelity Audit 2026-11-10\m2_facade\ (EVIDENCE_DIGEST, reference_materials, RESULTS).
Colours were set with the in-engine response board measured under C9 (m2_facade\metrics\board*.json), so that the
RENDERED relations match the measured reference relations; every value here is a PARAMETER, not a reference fact.
STAGES (set false to skip):
  ground   G1  asphalt / sidewalk / curb / plaza values (MATERIAL)
  palette  G2  per-building paint from evidence-weighted families (MATERIAL)
  shutters G3  storefront shutters: CorrodedMetal -> painted steel (MATERIAL)
  bases    G4  base bands (plinth / painted dado / skirting) on exterior walls, cut around openings (GEOMETRY+MATERIAL)
  patches  G5  asphalt patches and wear (MATERIAL variation, thin parts)
  tower    G6  clock tower as white stone (NL CONFIRMED) ]]
local STAGES = { ground = true, palette = true, shutters = true, bases = true, patches = true, tower = true }
local P = {
	seed = 20261114,
	-- G1 ground [PARAMETER from board calibration]: lit asphalt / lit sidewalk ~0.75 (reference 0.64-0.93);
	-- shaded facade / lit sidewalk ~0.45 (reference 0.40-0.55); asphalt warm grey (reference hue 16-30, S 0.08-0.15)
	asphalt = Color3.new(0.190, 0.175, 0.160), asphaltJitter = 0.010,
	sidewalk = Color3.new(0.520, 0.500, 0.470), sidewalkJitter = 0.018,
	plazaPaving = Color3.new(0.560, 0.530, 0.490), -- FM2: 0.44 read dull mid-grey; NL main plaza (P9) lit paving 204-215 -> lit ~188

	-- G2 paint families: weight, hue range (deg), S range, V range. Warm band 11-47 deg dominates (NL 9/11, MOD 6/6,
	-- VAN all); vivid minority (NL 4/11, MOD 0/6); cool accents rare (NL: blue 197, murals)
	-- (iteration G2b: vivid bases need S >= 0.70 to read as vivid (lit S > 0.35) under C9 exposure; vivid share of
	-- buildings 26 %, between MOD 0/6 and NL 4/11)
	families = {
		{ name = "paleWarm", w = 0.38, h = { 26, 46 }, s = { 0.20, 0.32 }, v = { 0.82, 0.90 } },
		{ name = "moderateWarm", w = 0.30, h = { 12, 40 }, s = { 0.34, 0.50 }, v = { 0.74, 0.84 } },
		{ name = "vividWarm", w = 0.20, h = { 8, 48 }, s = { 0.70, 0.85 }, v = { 0.62, 0.78 } },
		{ name = "vividCool", w = 0.06, h = { 188, 214 }, s = { 0.60, 0.75 }, v = { 0.58, 0.70 } },
		{ name = "paleCool", w = 0.06, h = { 90, 205 }, s = { 0.12, 0.22 }, v = { 0.78, 0.86 } },
	},
	-- G3 shutters: lit shutter / lit wall ~0.5-0.6 (MOD roller shutter 0.55; NL steel door 0.29 lit / 0.48 shaded)
	shutters = { { w = 0.5, c = Color3.new(0.34, 0.34, 0.35) }, { w = 0.2, c = Color3.new(0.30, 0.36, 0.33) },
		{ w = 0.2, c = Color3.new(0.30, 0.33, 0.40) }, { w = 0.1, c = Color3.new(0.44, 0.29, 0.25) } },
	-- G4 base bands (height in studs; S = 2.5 studs / m): NL plinths 0.63-0.89 x wall, 0.09-0.14 storey; MOD / VAN
	-- 0.71-0.79 x wall, ~0.3 storey; NL painted dado ~1 m (dark blue 0.21 x), light skirting 1.06 x
	bases = { { kind = "plinth", w = 0.55, hgt = { 1.4, 2.6 }, mul = { 0.68, 0.80 } },
		{ kind = "dado", w = 0.12, hgt = { 2.4, 2.8 } }, { kind = "skirting", w = 0.08, hgt = { 0.9, 1.3 } },
		{ kind = "none", w = 0.25 } },
	dadoColours = { Color3.new(0.18, 0.26, 0.42), Color3.new(0.45, 0.22, 0.16), Color3.new(0.30, 0.30, 0.30), Color3.new(0.20, 0.36, 0.30) },
	-- G5 asphalt patches: NL P2 patched / cracked; MOD / VAN not seen -> moderate density
	patchPerStuds2 = 1 / 1400, patchSize = { 3, 11 }, patchMul = { 0.80, 1.12 },
	-- G6 clock tower: "white-stone clock tower" [NL CONFIRMED]
	towerStone = Color3.new(0.86, 0.84, 0.79),
}
local M2 = workspace:FindFirstChild("PresentationMap_M2"); assert(M2, "PresentationMap_M2 missing")
local MAT = Enum.Material
local rng = Random.new(P.seed)
local function pick(list)
	local x, acc = rng:NextNumber(), 0
	for _, e in ipairs(list) do acc += e.w; if x <= acc then return e end end
	return list[#list]
end
local function range(r) return r[1] + (r[2] - r[1]) * rng:NextNumber() end
local function sortedDescendants(root, pred)
	local t = {}
	for _, d in root:GetDescendants() do if pred(d) then table.insert(t, d) end end
	table.sort(t, function(a, b) return a:GetFullName() < b:GetFullName() end)
	return t
end
local function isBuilding(m) return m:IsA("Model") and m:GetAttribute("Storeys") ~= nil end
local function jitter(c, j) local k = 1 + (rng:NextNumber() * 2 - 1) * j / math.max(0.05, (c.R + c.G + c.B) / 3)
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1)) end
local report = {}
-- fresh layer for added parts
local old = M2:FindFirstChild("FacadeV4"); if old then old:Destroy() end
local layer = Instance.new("Model"); layer.Name = "FacadeV4"
layer:SetAttribute("Pass", "facade_material_pass 2026-11-11 seed " .. P.seed)
local function addPart(parent, name, size, cf, color, material)
	local p = Instance.new("Part"); p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth; p.Parent = parent
	return p
end
-- G1 ground
if STAGES.ground then
	local n = { asphalt = 0, walk = 0, plaza = 0 }
	for _, p in sortedDescendants(M2, function(d) return d:IsA("BasePart") end) do
		local top = p.Parent and p:FindFirstAncestorWhichIsA("Model")
		local sub = p; while sub.Parent ~= M2 do sub = sub.Parent end
		if p.Material == MAT.Asphalt and (sub.Name == "Streets" or sub.Name == "Bridge" or sub.Name == "Tract" or sub.Name == "Logistics" or sub.Name == "Breakup") then
			p.Color = jitter(P.asphalt, P.asphaltJitter); n.asphalt += 1
		elseif p.Material == MAT.Concrete and (sub.Name == "Streets" or sub.Name == "Terrace") and p.Size.Y <= 1.6 and math.max(p.Size.X, p.Size.Z) > 4 then
			p.Color = jitter(P.sidewalk, P.sidewalkJitter); n.walk += 1
		elseif p.Material == MAT.Pavement and sub.Name == "Plaza" then
			p.Color = P.plazaPaving; n.plaza += 1
		end
	end
	table.insert(report, string.format("G1 asphalt %d, sidewalk/curb %d, plaza %d", n.asphalt, n.walk, n.plaza))
end
-- buildings (sorted, deterministic)
local buildings = sortedDescendants(M2, isBuilding)
local paint = {}
if STAGES.palette then
	local fam = {}
	for _, b in ipairs(buildings) do
		local f = pick(P.families)
		local h, s, v = range(f.h) % 360, range(f.s), range(f.v)
		local c = Color3.fromHSV(h / 360, s, v)
		paint[b] = c; fam[f.name] = (fam[f.name] or 0) + 1
		for _, p in b:GetDescendants() do
			if p:IsA("BasePart") and p.Material == MAT.Plaster then p.Color = c end
		end
	end
	local t = {} for k, v in fam do table.insert(t, k .. " " .. v) end table.sort(t)
	table.insert(report, "G2 buildings " .. #buildings .. ": " .. table.concat(t, ", "))
end
if STAGES.shutters then
	local n = 0
	for _, b in ipairs(buildings) do
		local s = pick(P.shutters)
		for _, p in b:GetDescendants() do
			if p:IsA("BasePart") and p.Material == MAT.CorrodedMetal then p.Material = MAT.Metal; p.Color = s.c; p:SetAttribute("FMShutter", true); n += 1 end
		end
	end
	table.insert(report, "G3 shutters " .. n)
end
if STAGES.bases then
	local folder = Instance.new("Folder"); folder.Name = "Bases"; folder.Parent = layer
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local ov = OverlapParams.new(); ov.FilterType = Enum.RaycastFilterType.Exclude
	local nBands, nFaces, kinds = 0, 0, {}
	for _, b in ipairs(buildings) do
		local base = pick(P.bases)
		kinds[base.kind] = (kinds[base.kind] or 0) + 1
		if base.kind ~= "none" then
			-- main wall box: the largest Plaster / Concrete / Brick part of the building standing on the ground
			local box, vol = nil, 0
			for _, p in b:GetDescendants() do
				if p:IsA("BasePart") and (p.Material == MAT.Plaster or p.Material == MAT.Concrete or p.Material == MAT.Brick) and p.Size.Y >= 6
					and math.abs((p.Position.Y - p.Size.Y / 2) - 0) < 0.6 then
					local v = p.Size.X * p.Size.Y * p.Size.Z
					if v > vol then box, vol = p, v end
				end
			end
			if box then
				local wallC = box.Color
				local hgt = range(base.hgt)
				local col, mat
				if base.kind == "plinth" then
					local m = range(base.mul); local hh, ss, vv = wallC:ToHSV()
					col = Color3.fromHSV(hh, ss * 0.85, vv * m); mat = MAT.Concrete
				elseif base.kind == "dado" then
					col = P.dadoColours[rng:NextInteger(1, #P.dadoColours)]; mat = MAT.Plaster
				else
					local hh, ss, vv = wallC:ToHSV(); col = Color3.fromHSV(hh, ss * 0.3, math.min(1, vv * 1.06)); mat = MAT.Plaster
				end
				rp.FilterDescendantsInstances = { b }
				ov.FilterDescendantsInstances = { b, layer }
				local cf, sz = box.CFrame, box.Size
				-- the four side faces: normal, half-depth, face width axis, face width
				for _, f in ipairs({ { cf.LookVector, sz.Z / 2, cf.RightVector, sz.X }, { -cf.LookVector, sz.Z / 2, cf.RightVector, sz.X },
					{ cf.RightVector, sz.X / 2, cf.LookVector, sz.Z }, { -cf.RightVector, sz.X / 2, cf.LookVector, sz.Z } }) do
					local nrm, half, ax, width = f[1], f[2], f[3], f[4]
					local centre = Vector3.new(cf.Position.X, 0, cf.Position.Z) + nrm * half
					-- FM3: exterior runs sampled every ~2 studs along the face (at 2 studs height, above sidewalks): a sample
					-- is exterior when nothing is within 1.2 studs outward and no other queryable part occupies the space
					-- just in front of the wall; bands are built only over exterior runs (FM2 tested 3 points per face and
					-- left 141 bands fully and 526 partly inside neighbouring buildings)
					local nS = math.max(1, math.floor(width / 2))
					local runs, cur = {}, nil
					for i = 0, nS - 1 do
						local a0, a1 = -width / 2 + i * width / nS, -width / 2 + (i + 1) * width / nS
						local o = centre + ax * ((a0 + a1) / 2) + Vector3.new(0, 2, 0) + nrm * 0.05
						local ext = workspace:Raycast(o, nrm * 1.2, rp) == nil
							and #workspace:GetPartBoundsInBox(CFrame.new(o + nrm * 0.3), Vector3.new(0.3, 0.3, 0.3), ov) == 0
						if ext then if cur then cur[2] = a1 else cur = { a0, a1 } end
						elseif cur then table.insert(runs, cur); cur = nil end
					end
					if cur then table.insert(runs, cur) end
					if #runs > 0 then
						nFaces += 1
						-- openings on this face (doors, shutters, ground-floor glass) cut the band
						local cuts = {}
						for _, q in b:GetDescendants() do
							if q:IsA("BasePart") and q ~= box and (q.Material == MAT.Wood or q.Material == MAT.Metal or q.Material == MAT.CorrodedMetal or q.Material == MAT.Glass)
								and (q.Position.Y - q.Size.Y / 2) < hgt and math.abs((q.Position - centre):Dot(nrm)) < 1.0 then
								local along = (q.Position - centre):Dot(ax)
								local ext = math.abs(q.CFrame.RightVector:Dot(ax)) * q.Size.X / 2 + math.abs(q.CFrame.LookVector:Dot(ax)) * q.Size.Z / 2
								if ext > 0.3 then table.insert(cuts, { along - ext - 0.15, along + ext + 0.15 }) end
							end
						end
						table.sort(cuts, function(a, c) return a[1] < c[1] end)
						local segs = {}
						for _, run in ipairs(runs) do
							local x = run[1]
							for _, c in ipairs(cuts) do
								if c[2] > x and c[1] < run[2] then
									if c[1] > x then table.insert(segs, { x, math.min(c[1], run[2]) }) end
									x = math.max(x, c[2])
								end
							end
							if x < run[2] then table.insert(segs, { x, run[2] }) end
						end
						for _, s in ipairs(segs) do
							local len = s[2] - s[1]
							if len > 0.8 then
								-- FM3: a 0.03 layer whose front face is 0.035 off the wall (FM2: 0.12 thick, front 0.14 off),
								-- so wall blood splats (~0.05 off the wall) and impact effects stay in front of it
								local mid = centre + ax * ((s[1] + s[2]) / 2) + nrm * 0.02 + Vector3.new(0, hgt / 2, 0)
								local bandCF = CFrame.fromMatrix(mid, ax, Vector3.yAxis)
								addPart(folder, "Base_" .. base.kind, Vector3.new(len, hgt, 0.03), bandCF, col, mat)
								nBands += 1
							end
						end
					end
				end
			end
		end
	end
	local t = {} for k, v in kinds do table.insert(t, k .. " " .. v) end table.sort(t)
	table.insert(report, string.format("G4 bases: %s; exterior faces %d, band parts %d", table.concat(t, ", "), nFaces, nBands))
end
if STAGES.patches then
	local folder = Instance.new("Folder"); folder.Name = "Patches"; folder.Parent = layer
	local n = 0
	for _, p in sortedDescendants(M2.Streets, function(d) return d:IsA("BasePart") and d.Material == MAT.Asphalt end) do
		local area = p.Size.X * p.Size.Z
		local count = math.floor(area * P.patchPerStuds2 + rng:NextNumber())
		for _ = 1, count do
			local w, d = range(P.patchSize), range(P.patchSize)
			local u, v = (rng:NextNumber() - 0.5) * math.max(0, p.Size.X - w), (rng:NextNumber() - 0.5) * math.max(0, p.Size.Z - d)
			-- FM3: 0.01 thick, top 0.011 above the road (FM2: 0.03 thick, top 0.03): blood pools placed on the road
			-- (patches are CanQuery = false) then sit ~0.02 above the patch instead of 0.002
			local cf = p.CFrame * CFrame.new(u, p.Size.Y / 2 + 0.006, v)
			local m = range(P.patchMul)
			local c = Color3.new(math.clamp(p.Color.R * m, 0, 1), math.clamp(p.Color.G * m, 0, 1), math.clamp(p.Color.B * m, 0, 1))
			addPart(folder, "Patch", Vector3.new(w, 0.01, d), cf, c, MAT.Asphalt)
			n += 1
		end
	end
	table.insert(report, "G5 asphalt patches " .. n)
end
if STAGES.tower then
	local t = M2:FindFirstChild("Landmarks") and M2.Landmarks:FindFirstChild("ClockTower")
	local n = 0
	if t then for _, p in t:GetDescendants() do if p:IsA("BasePart") and p.Material == MAT.Plaster then p.Material = MAT.Limestone; p.Color = P.towerStone; n += 1 end end end
	table.insert(report, "G6 clock tower parts " .. n)
end
layer.Parent = M2
M2:SetAttribute("FacadePass", "facade_material_pass 2026-11-11 seed " .. P.seed)
local np = 0 for _, d in layer:GetDescendants() do if d:IsA("BasePart") then np += 1 end end
table.insert(report, "FacadeV4 parts " .. np)
return table.concat(report, "\n")
