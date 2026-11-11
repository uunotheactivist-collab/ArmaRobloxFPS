--[[ M2 FM4 storefront pass (2026-11-11). Run in Studio EDIT after build_map.luau and facade_material_pass.luau.
Scope: street-facing frontages of commercial buildings (Use "shop", "shop + flats"; "(enterable)" buildings with interiors
are excluded). Real recesses, not painted rectangles: each target building's main wall box is replaced by
  - an UPPER block (full footprint, from the storefront head height hSplit to the original top),
  - a ground CORE block set back by `recess` studs on every frontage face,
  - PIERS (end piers + piers between bays) that fill the recess slab back to the original facade plane,
so the storefront openings are true voids `recess` deep, framed by piers (jambs), the upper block (head) and a fascia
(sign band). The new structural parts copy the box's material, colour, collision, query, shadow and attributes, and
their union equals the original envelope minus the recesses. Openings are filled by one of two archetypes at the back of
the recess: CLOSED roller shutter (painted steel + wall-coloured housing) or DARK GLAZED front (dark interior panel on the
core, glass 0.45 in front of it, mullion on bays wider than 6 studs).
FM4-F/G: a closed bay is filled by two SOLID blocks (CanCollide / CanQuery / CastShadow on), the painted shutter and
the wall-coloured housing above it, each from the core to 0.05 behind the facade plane (flush, as in the references),
so the bay holds no cavity; glazed infill stays CanCollide = false / CanQuery = false (shots pass the glass into the
dark interior and stop at the core); a threshold slab raises each recess floor to 0.004 below the sidewalk top (never
coplanar). Glass and mullions carry OpticMirrorIgnore (the scope mirror skips them).
Existing doors and text / GUI signs are preserved (bays avoid them); ground-storey decor inside bay intervals (legacy
windows, legacy shutters, sign boards, v3 Breakup strips, FM3 base bands, downpipes) is MOVED, not deleted, to
ServerStorage.FM4_Holder with an ObjectValue `FM4Parent` -> original parent, and FM3 base bands are rebuilt on the pier
fronts with the building's FM3 band kind / colour / height.
Deterministic (seed below), idempotent (a rerun first restores everything from the holder and removes FM4 geometry),
rollback: `_G.FM4_ROLLBACK()` or MODE = "rollback". Lighting (C9), fill (v3) and every script are untouched.
All values are PARAMETERS (Fidelity Audit 2026-11-10\m2_facade\storefront_reference.md for the evidence). ]]
local MODE = "apply" -- "apply" | "rollback"
local P = {
	seed = 20261115,
	uses = { ["shop"] = true, ["shop + flats"] = true },
	openHeightRatio = { 0.76, 0.86 }, -- opening head / ground storey, per building (MOD 375: 0.81 [M]); FM4-B: varied per building
	recess = 1.2, -- studs (0.48 m at S = 2.5): PARAMETER (recess depth UNKNOWN in the references)
	bayPitch = { 10.5, 15 }, -- studs between pier centres, per face (FM4-D: reference bay spacing 1.3-1.8 x storey, storefront_reference.md)
	pier = { 2.2, 3.0 }, -- studs between bays, per building (FM4-E: 0.27-0.36 x storey; reference pier 0.30-0.55 x storey is MOD-only / FOV-dependent; FM4-D 2.4-3.4 gave area share 0.576 < the NL-backed 0.645)
	endPier = 1.4, -- studs at each face end (corner face ends: owned by the first frontage face)
	minFace = 7, -- faces narrower than this get no bays
	closedShare = 0.5, -- NL: ~50 % of downtown shops closed (2013) [CONFIRMED]
	shutterColours = { Color3.new(0.34, 0.34, 0.35), Color3.new(0.30, 0.36, 0.33), Color3.new(0.30, 0.33, 0.40), Color3.new(0.44, 0.29, 0.25) },
	housingH = 0.55, -- studs, minimum; the housing is max(housingH, 0.12 x storey) (MOD 375: flush, wall-coloured, ~0.12 of storey)
	glass = Color3.new(0.16, 0.18, 0.19), glassTransparency = 0.12, interior = Color3.new(0.26, 0.26, 0.27), -- FM4-D: reference glass / wall 0.25-0.55 (same light) -- FM4-C: FM4-A/B read glass / wall 0.04-0.15 (NL 0.13-0.30); FM4-C 0.06-0.18 (shaded fronts compare against sunlit walls)
	frameCol = Color3.new(0.18, 0.18, 0.19), mullion = 0.15,
	thresholdColour = Color3.new(0.52, 0.50, 0.47), -- = FM3 sidewalk colour
	fasciaShare = 0.6, canopyShare = 0.35, canopyDepth = { 2.6, 3.4 }, -- FM4-D: NL sign bands on 0.5-0.75 of frontages; canopies / slabs on 0.3-0.6 (MOD 2-4 of 5, NL ~3 of 8); FM4-F: shutters flush, 0.05 behind the plane (reference <= 0.03 of bay)
	fasciaColours = { Color3.new(0.86, 0.85, 0.81), Color3.new(0.80, 0.78, 0.72), Color3.new(0.30, 0.30, 0.31) },
}
local ServerStorage = game:GetService("ServerStorage")
local M2 = workspace:FindFirstChild("PresentationMap_M2"); assert(M2, "PresentationMap_M2 missing")
local MAT = Enum.Material
local function holder()
	local h = ServerStorage:FindFirstChild("FM4_Holder")
	if not h then h = Instance.new("Folder"); h.Name = "FM4_Holder"; h.Parent = ServerStorage end
	return h
end
local function stash(p)
	local ov = Instance.new("ObjectValue"); ov.Name = "FM4Parent"; ov.Value = p.Parent; ov.Parent = p
	p.Parent = holder()
end
local function rollback()
	local h = ServerStorage:FindFirstChild("FM4_Holder")
	local restored = 0
	if h then
		for _, p in h:GetChildren() do
			local ov = p:FindFirstChild("FM4Parent")
			if ov and ov.Value then p.Parent = ov.Value; ov:Destroy(); restored += 1 end
		end
		if #h:GetChildren() == 0 then h:Destroy() end
	end
	local removed = 0
	for _, d in M2:GetDescendants() do
		if d:IsA("Folder") and (d.Name == "FM4Storefront" or d.Name == "FM4Bases") then removed += 1; d:Destroy() end
	end
	M2:SetAttribute("StorefrontPass", nil)
	return restored, removed
end
_G.FM4_ROLLBACK = rollback
if MODE == "rollback" then local r, d = rollback(); return "rolled back: restored " .. r .. ", removed folders " .. d end
local restored, removedFolders = rollback()
local rng = Random.new(P.seed)
local function range(r) return r[1] + (r[2] - r[1]) * rng:NextNumber() end
local function topSub(p) local a = p while a and a.Parent ~= M2 do a = a.Parent end return a end
local function streetBelow(pos, filter)
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = filter
	local r = workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), rp)
	if not r then return false end
	local s = topSub(r.Instance)
	return s and (s.Name == "Streets" or s.Name == "Plaza")
end
local function hasGui(p) for _, c in p:GetChildren() do if c:IsA("SurfaceGui") or c:IsA("Decal") or c:IsA("Texture") or c:IsA("BillboardGui") then return true end end return false end
local function copyProps(src, dst)
	dst.Anchored = true; dst.Material = src.Material; dst.Color = src.Color; dst.Reflectance = src.Reflectance; dst.Transparency = src.Transparency
	dst.CanCollide = src.CanCollide; dst.CanQuery = src.CanQuery; dst.CanTouch = src.CanTouch; dst.CastShadow = src.CastShadow
	dst.CollisionGroup = src.CollisionGroup; dst.TopSurface = src.TopSurface; dst.BottomSurface = src.BottomSurface
	for k, v in src:GetAttributes() do dst:SetAttribute(k, v) end
end
local function part(parent, name, size, cf, colour, material, infill)
	local p = Instance.new("Part"); p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Size = size; p.CFrame = cf; p.Color = colour; p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if infill then p:SetAttribute("FM4Infill", true) end
	p.Parent = parent
	return p
end
local function sorted(root, pred) local t = {} for _, d in root:GetDescendants() do if pred(d) then table.insert(t, d) end end table.sort(t, function(a, b) return a:GetFullName() < b:GetFullName() end) return t end
local buildings = sorted(M2, function(d) return d:IsA("Model") and d:GetAttribute("Storeys") ~= nil and P.uses[tostring(d:GetAttribute("Use"))] == true end)
-- candidate decor parts outside the building models that can sit on a facade
local outside = {}
for _, sub in { "Breakup", "FacadeV4" } do
	local s = M2:FindFirstChild(sub)
	if s then for _, d in s:GetDescendants() do if d:IsA("BasePart") then table.insert(outside, d) end end end
end
local stats = { buildings = 0, faces = 0, bays = 0, closed = 0, glazed = 0, structural = 0, infill = 0, fascia = 0, bands = 0, moved = 0, frontW = 0, openA = 0, frontA = 0, skipped = 0 }
local faceLog = {}
for bi, b in ipairs(buildings) do
	local sh = (b:GetAttribute("Height") or 9) / math.max(1, b:GetAttribute("Storeys") or 1)
	local box, vol = nil, 0
	for _, p in b:GetDescendants() do
		if p:IsA("BasePart") and (p.Material == MAT.Plaster or p.Material == MAT.Concrete or p.Material == MAT.Brick) and p.Size.Y >= 6 and math.abs(p.Position.Y - p.Size.Y / 2) < 0.6 then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > vol then box, vol = p, v end
		end
	end
	local shutterC = P.shutterColours[rng:NextInteger(1, #P.shutterColours)]
	local hRatio, pierW = range(P.openHeightRatio), range(P.pier)
	local fasciaC = P.fasciaColours[rng:NextInteger(1, #P.fasciaColours)]
	if box and math.abs(box.CFrame.RightVector.Y) < 1e-3 and math.abs(box.CFrame.UpVector.Y - 1) < 1e-3 then
		local cf, sz = box.CFrame, box.Size
		local faces = {}
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { b }
		local defs = { { "F", cf.LookVector, sz.Z / 2, cf.RightVector, sz.X }, { "B", -cf.LookVector, sz.Z / 2, cf.RightVector, sz.X },
			{ "R", cf.RightVector, sz.X / 2, cf.LookVector, sz.Z }, { "L", -cf.RightVector, sz.X / 2, cf.LookVector, sz.Z } }
		for _, f in ipairs(defs) do
			local id, nrm, half, ax, width = f[1], f[2], f[3], f[4], f[5]
			local centre = Vector3.new(cf.Position.X, 0, cf.Position.Z) + nrm * half
			if width >= P.minFace and workspace:Raycast(centre + Vector3.new(0, 3, 0) + nrm * 0.05, nrm * 3, rp) == nil and streetBelow(centre + nrm * 6, { b }) then
				table.insert(faces, { id = id, nrm = nrm, half = half, ax = ax, width = width, centre = centre })
			end
		end
		if #faces > 0 then
			stats.buildings += 1
			-- per face: keep-intervals (doors, GUI signs at ground level), head height cap (GUI signs low on the face)
			local hSplit = hRatio * sh
			for _, f in ipairs(faces) do
				f.keep = {}
				for _, q in b:GetDescendants() do
					if q:IsA("BasePart") and q ~= box and math.abs((q.Position - f.centre):Dot(f.nrm)) < 1.2 then
						local along = (q.Position - f.centre):Dot(f.ax)
						local ext = math.abs(q.CFrame.RightVector:Dot(f.ax)) * q.Size.X / 2 + math.abs(q.CFrame.LookVector:Dot(f.ax)) * q.Size.Z / 2
						local bot, top = q.Position.Y - q.Size.Y / 2, q.Position.Y + q.Size.Y / 2
						if q.Material == MAT.Wood and q.Size.Y > 3 and bot < 1 then table.insert(f.keep, { along - ext - 0.6, along + ext + 0.6 })
						elseif hasGui(q) and bot < hSplit then
							if bot < 2 then table.insert(f.keep, { along - ext - 0.4, along + ext + 0.4 }) else hSplit = math.min(hSplit, bot - 0.1) end
						end
					end
				end
			end
			hSplit = math.max(hSplit, 4.5)
			-- corner ownership: the first frontage face owns both of its end squares
			local owned = {}
			for _, f in ipairs(faces) do
				local function cornerKey(sgn) local c = f.centre + f.ax * (f.width / 2 * sgn) return string.format("%.1f,%.1f", c.X, c.Z) end
				f.insetNeg = owned[cornerKey(-1)] and P.recess or 0
				f.insetPos = owned[cornerKey(1)] and P.recess or 0
				owned[cornerKey(-1)] = true; owned[cornerKey(1)] = true
			end
			local folder = Instance.new("Folder"); folder.Name = "FM4Storefront"
			local d = P.recess
			-- structural replacement: upper block + recessed core
			local top = box.Position.Y + sz.Y / 2
			local upper = Instance.new("Part"); copyProps(box, upper); upper.Name = box.Name
			upper.Size = Vector3.new(sz.X, top - hSplit, sz.Z); upper.CFrame = CFrame.fromMatrix(Vector3.new(cf.Position.X, (top + hSplit) / 2, cf.Position.Z), cf.RightVector, Vector3.yAxis)
			upper.Parent = folder
			local shrink = { F = 0, B = 0, R = 0, L = 0 }
			for _, f in ipairs(faces) do shrink[f.id] = d end
			local cx, cz = sz.X - shrink.R - shrink.L, sz.Z - shrink.F - shrink.B
			local coreCentre = cf.Position + cf.RightVector * ((shrink.L - shrink.R) / 2) + cf.LookVector * ((shrink.B - shrink.F) / 2)
			local core = Instance.new("Part"); copyProps(box, core); core.Name = box.Name
			core.Size = Vector3.new(cx, hSplit, cz); core.CFrame = CFrame.fromMatrix(Vector3.new(coreCentre.X, hSplit / 2, coreCentre.Z), cf.RightVector, Vector3.yAxis)
			core.Parent = folder
			stats.structural += 2
			for _, f in ipairs(faces) do
				stats.faces += 1; stats.frontW += f.width; stats.frontA += f.width * sh
				local a0, a1 = -f.width / 2 + f.insetNeg, f.width / 2 - f.insetPos
				-- free intervals for bays: [a0 + endPier, a1 - endPier] minus keep intervals
				local free, x = {}, a0 + P.endPier
				table.sort(f.keep, function(p, q) return p[1] < q[1] end)
				for _, k in ipairs(f.keep) do
					if k[1] > x then table.insert(free, { x, math.min(k[1], a1 - P.endPier) }) end
					x = math.max(x, k[2])
				end
				if x < a1 - P.endPier then table.insert(free, { x, a1 - P.endPier }) end
				-- bays: openings separated by piers of width P.pier
				local openings = {}
				for _, iv in ipairs(free) do
					local L = iv[2] - iv[1]
					if L >= 3.5 then
						local n = math.max(1, math.floor((L + pierW) / range(P.bayPitch) + 0.5))
						local ow = (L - (n - 1) * pierW) / n
						if ow < 2.6 and n > 1 then n -= 1; ow = (L - (n - 1) * pierW) / n end
						for k = 0, n - 1 do local s = iv[1] + k * (ow + pierW) table.insert(openings, { s, s + ow }) end
					end
				end
				-- piers: everything in [a0, a1] that is not an opening (doors keep their wall section)
				local piers, px = {}, a0
				for _, o in ipairs(openings) do if o[1] > px + 0.01 then table.insert(piers, { px, o[1] }) end px = o[2] end
				if a1 > px + 0.01 then table.insert(piers, { px, a1 }) end
				local planeC = f.centre -- original facade plane, y = 0
				for _, pr in ipairs(piers) do
					local len = pr[2] - pr[1]
					local mid = planeC + f.ax * ((pr[1] + pr[2]) / 2) - f.nrm * (d / 2) + Vector3.new(0, hSplit / 2, 0)
					local pp = Instance.new("Part"); copyProps(box, pp); pp.Name = box.Name
					pp.Size = Vector3.new(len, hSplit, d); pp.CFrame = CFrame.fromMatrix(mid, f.ax, Vector3.yAxis)
					pp.Parent = folder; stats.structural += 1
				end
				-- move ground-storey decor that lies on this face inside an opening interval
				local function inOpening(q)
					local along = (q.Position - planeC):Dot(f.ax)
					local ext = math.abs(q.CFrame.RightVector:Dot(f.ax)) * q.Size.X / 2 + math.abs(q.CFrame.LookVector:Dot(f.ax)) * q.Size.Z / 2 + math.abs(q.CFrame.UpVector:Dot(f.ax)) * q.Size.Y / 2
					for _, o in ipairs(openings) do if along + ext > o[1] + 0.05 and along - ext < o[2] - 0.05 then return true end end
					return false
				end
				local function onFace(q)
					local off = (q.Position - planeC):Dot(f.nrm)
					return off > -0.4 and off < 1.6 and (q.Position.Y - q.Size.Y / 2) < hSplit - 0.05
				end
				local bandStyle
				for _, q in ipairs(outside) do
					if q.Parent and q:IsDescendantOf(M2) and onFace(q) and math.abs((q.Position - planeC):Dot(f.ax)) < f.width / 2 + 1 then
						if q.Name:match("^Base_") then
							bandStyle = bandStyle or { kind = q.Name, colour = q.Color, material = q.Material, h = q.Size.Y }
							stash(q); stats.moved += 1
						elseif inOpening(q) then stash(q); stats.moved += 1 end
					end
				end
				for _, q in b:GetDescendants() do
					if q:IsA("BasePart") and q ~= box and not q:IsDescendantOf(folder) and onFace(q) and not (q.Material == MAT.Wood and q.Size.Y > 3) and not hasGui(q) and inOpening(q) then
						stash(q); stats.moved += 1
					end
				end
				-- FM4-D threshold: the recess floor raised to the sidewalk in front (FM4-C left a strip 0.415 below the sidewalk
				-- in 563 / 568 bays). Its front face sits 0.02 behind the facade plane so it never shares a plane with the piers.
				local corePlane = planeC - f.nrm * d
				local yb = 0
				do
					local rpd = RaycastParams.new(); rpd.FilterType = Enum.RaycastFilterType.Exclude; rpd.FilterDescendantsInstances = { b }
					local hit = workspace:Raycast(planeC + f.nrm * 1.5 + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0), rpd)
					if hit and hit.Position.Y > 0.02 and hit.Position.Y < 1.0 then yb = hit.Position.Y end
					if yb > 0 then
						local th = Instance.new("Part"); copyProps(box, th); th.Name = "Threshold"; th.Material = MAT.Concrete; th.Color = P.thresholdColour
						th.Size = Vector3.new(a1 - a0, yb - 0.004, d - 0.02) -- FM4-F: 0.004 below the sidewalk top (FM4-E tops were coplanar with the sidewalk that runs under part of the recess)
						th.CFrame = CFrame.fromMatrix(planeC + f.ax * ((a0 + a1) / 2) - f.nrm * (d / 2 + 0.01) + Vector3.new(0, (yb - 0.004) / 2, 0), f.ax, Vector3.yAxis)
						th.Parent = folder; stats.structural += 1
					end
				end
				for _, o in ipairs(openings) do
					local w = o[2] - o[1]
					local mx = (o[1] + o[2]) / 2
					local closed = rng:NextNumber() < P.closedShare
					stats.bays += 1; stats.openA += w * (hSplit - yb)
					local function at(off, y) return CFrame.fromMatrix(corePlane + f.ax * mx + f.nrm * off + Vector3.new(0, y, 0), f.ax, Vector3.yAxis) end
					local hIn = hSplit - yb
					if closed then
						stats.closed += 1
						-- FM4-D: shutter near the facade plane and SOLID (CanCollide / CanQuery on: shots,
						-- impacts and blood stop on the steel, FM4-C hid them on the core behind); housing flush and wall-coloured,
						-- ~0.12 of the storey (reference: shutters flush <= 0.03 of bay; housing flush, wall-coloured, ~0.12 storey)
						local hh = math.max(P.housingH, 0.12 * sh)
						-- FM4-F: the shutter is a SOLID block from the core to 0.05 behind the facade plane (FM4-E: a 0.06 panel 0.35 back let 1 of 4 grenades tunnel and trap in the gap behind it)
						local sp = part(folder, "Shutter", Vector3.new(w, hIn - hh, d - 0.05), at((d - 0.05) / 2, yb + (hIn - hh) / 2), shutterC, MAT.Metal, true)
						sp:SetAttribute("FMShutter", true); sp.CanCollide = true; sp.CanQuery = true; sp.CastShadow = true
						-- FM4-G: the housing is a SOLID block over the same depth as the shutter (core to 0.05 behind the plane), so the
						-- shutter + housing fill the whole opening: FM4-F's 0.4-thick non-colliding housing left a 1.15 x 0.96 slot behind
						-- it where grenades lodged and shots / blood were hidden. It stays in the scope mirror (opaque, cheap).
						local hs = part(folder, "ShutterHousing", Vector3.new(w, hh, d - 0.05), at((d - 0.05) / 2, hSplit - hh / 2), box.Color, box.Material, true)
						hs.CanCollide = true; hs.CanQuery = true; hs.CastShadow = true
						stats.infill += 2
					else
						stats.glazed += 1
						-- FM4-D: simpler glazed front (no kick plate / transom; mullion only on wide bays), lighter interior
						part(folder, "Interior", Vector3.new(w, hIn, 0.02), at(0.02, yb + hIn / 2), P.interior, MAT.SmoothPlastic, true)
						local g = part(folder, "Glass", Vector3.new(w, hIn - 0.4, 0.05), at(0.45, yb + 0.4 + (hIn - 0.4) / 2), P.glass, MAT.Glass, true)
						g.Transparency = P.glassTransparency; g:SetAttribute("OpticMirrorIgnore", true) -- FM4-F: transparent panes kept out of the scope mirror (FM4-E scoped GPU +1.44 ms); the dark interior panel stays mirrored
						stats.infill += 2
						if w > 6 then
							local m = part(folder, "Mullion", Vector3.new(P.mullion, hIn - 0.4, 0.1), at(0.47, yb + 0.4 + (hIn - 0.4) / 2), P.frameCol, MAT.Metal, true)
							m:SetAttribute("OpticMirrorIgnore", true); stats.infill += 1
						end
					end
				end
				-- fascia / sign band on the face, from the head up to the storey line (neutral, no text)
				local fh = sh - hSplit - 0.2
				local hasFascia, hasCanopy = rng:NextNumber() < P.fasciaShare, rng:NextNumber() < P.canopyShare
				if hasCanopy then
					local cd = range(P.canopyDepth)
					local cp = part(folder, "Canopy", Vector3.new(a1 - a0, 0.25, cd), CFrame.fromMatrix(planeC + f.ax * ((a0 + a1) / 2) + f.nrm * (cd / 2) + Vector3.new(0, hSplit + 0.25, 0), f.ax, Vector3.yAxis), Color3.new(0.62, 0.60, 0.56), MAT.Concrete, false)
					cp.CastShadow = true; stats.canopy = (stats.canopy or 0) + 1
				end
				if fh > 0.5 and hasFascia then
					part(folder, "Fascia", Vector3.new(a1 - a0 - 0.4, fh, 0.03), CFrame.fromMatrix(planeC + f.ax * ((a0 + a1) / 2) + f.nrm * 0.02 + Vector3.new(0, hSplit + 0.1 + fh / 2, 0), f.ax, Vector3.yAxis), fasciaC, MAT.SmoothPlastic, false)
					stats.fascia += 1
				end
				-- FM3 base band rebuilt on the pier fronts (same kind / colour / height as this face had)
				if bandStyle then
					local bf = M2:FindFirstChild("FacadeV4") and M2.FacadeV4:FindFirstChild("FM4Bases")
					if not bf then bf = Instance.new("Folder"); bf.Name = "FM4Bases"; bf.Parent = M2.FacadeV4 end
					for _, pr in ipairs(piers) do
						local len = pr[2] - pr[1]
						if len > 0.6 then
							part(bf, bandStyle.kind, Vector3.new(len, bandStyle.h, 0.03), CFrame.fromMatrix(planeC + f.ax * ((pr[1] + pr[2]) / 2) + f.nrm * 0.02 + Vector3.new(0, bandStyle.h / 2, 0), f.ax, Vector3.yAxis), bandStyle.colour, bandStyle.material, false)
							stats.bands += 1
						end
					end
				end
				local fw = 0 for _, o in ipairs(openings) do fw += o[2] - o[1] end
				table.insert(faceLog, { name = b:GetFullName(), face = f.id, width = f.width, bays = #openings, share = fw * (hSplit - yb) / (f.width * sh), openW = fw, hOpen = hSplit - yb, sh = sh, fascia = hasFascia and fh > 0.5, canopy = hasCanopy, yb = yb, hSplit = hSplit, pierW = pierW, fh = (hasFascia and fh > 0.5) and fh or 0 })
			end
			stash(box); stats.moved += 1
			folder.Parent = b
		else
			stats.skipped += 1
		end
	end
	if bi % 25 == 0 then task.wait() end
end
M2:SetAttribute("StorefrontPass", "facade_storefront_pass 2026-11-11 seed " .. P.seed)
_G.FM4_FACELOG = faceLog
return string.format("restored %d / removed %d first; buildings %d, frontage faces %d (width %.0f), bays %d (closed %d, glazed %d); structural parts %d, infill %d, fascia %d, rebuilt band parts %d, moved to holder %d; frontage opening share (area) %.3f",
	restored, removedFolders, stats.buildings, stats.faces, stats.frontW, stats.bays, stats.closed, stats.glazed, stats.structural, stats.infill, stats.fascia, stats.bands, stats.moved, stats.openA / math.max(1, stats.frontA))
