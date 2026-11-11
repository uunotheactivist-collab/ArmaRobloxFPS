--!strict
-- Builds viewmodel MeshParts at runtime from the procedural recipes exported by
-- Blender/Scripts/17_m4_rig_export.py. Mirrors the primitive builders in Blender/Scripts/m4_model.py exactly
-- (same vertices, winding and part frames; Blender's small edge bevels are not reproduced).
--
-- Why: asset uploads are not available for this place yet, and EditableMesh needs no asset. When the FBX
-- (Roblox/Assets/M4/M4_Viewmodel.fbx) can be uploaded, swap these parts for the uploaded MeshParts; the rig,
-- poses and part frames stay the same.
--
-- Recipe space: weapon space in metres (+X right, +Y muzzle, +Z up). Output: Roblox part space in studs
-- (+X right, +Y up, -Z forward): p = (x, z, -y) / 0.28 after subtracting the bone's origin.
--
-- M4 model fidelity slice (2026-11-08): one more recipe op, "mesh": a triangle mesh modelled in Blender, exported to
-- FBX and encoded from the RE-IMPORTED FBX by Blender/Scripts/42_m4_hd_export.py. Binary (little endian, base64):
-- u32 vertex count, u32 triangle count, vertices i16 x3 (metres / 2e-5), normals i8 x3 (/127), triangles u16 x3.
-- `data` is the base64 text, either one string or a list of pieces (concatenated; keeps the generated module editable).
-- Additive: the primitive ops above are unchanged.

local AssetService = game:GetService("AssetService")

local STUD = 0.28

type Mesh = { V: { Vector3 }, T: { { number } }, N: { { Vector3 } } }

local ProceduralMesh = {}

local function newMesh(): Mesh
	return { V = {}, T = {}, N = {} }
end

local function addTri(m: Mesh, a: number, b: number, c: number, normals: { Vector3 }?)
	table.insert(m.T, { a, b, c })
	if normals then
		table.insert(m.N, normals)
	else
		local va = m.V[a]
		local n = (m.V[b] - va):Cross(m.V[c] - va)
		n = if n.Magnitude > 1e-12 then n.Unit else Vector3.zAxis
		table.insert(m.N, { n, n, n })
	end
end

local function area2(pts: { { number } }): number
	local a = 0
	for i = 1, #pts do
		local p, q = pts[i], pts[i % #pts + 1]
		a += p[1] * q[2] - q[1] * p[2]
	end
	return a / 2
end

local function cross2(o: { number }, a: { number }, b: { number }): number
	return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
end

-- Ear clipping for a simple counter-clockwise polygon (the side profiles are concave).
local function earClip(pts: { { number } }): { { number } }
	local idx = {}
	for i = 1, #pts do
		idx[i] = i
	end
	local tris = {}
	while #idx > 3 do
		local m = #idx
		local clipped = false
		for i = 1, m do
			local ia, ib, ic = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
			local a, b, c = pts[ia], pts[ib], pts[ic]
			if cross2(a, b, c) > 1e-12 then
				local ear = true
				for _, j in idx do
					if j ~= ia and j ~= ib and j ~= ic then
						local p = pts[j]
						if cross2(a, b, p) >= 0 and cross2(b, c, p) >= 0 and cross2(c, a, p) >= 0 then
							ear = false
							break
						end
					end
				end
				if ear then
					table.insert(tris, { ia, ib, ic })
					table.remove(idx, i)
					clipped = true
					break
				end
			end
		end
		if not clipped then
			break -- degenerate input: fan the rest
		end
	end
	for i = 2, #idx - 1 do
		table.insert(tris, { idx[1], idx[i], idx[i + 1] })
	end
	return tris
end

local function prism(pts0: { { number } }, axis: string, a0: number, a1: number): Mesh
	local pts = table.clone(pts0)
	if area2(pts) < 0 then
		local r = {}
		for i = #pts, 1, -1 do
			table.insert(r, pts[i])
		end
		pts = r
	end
	local n = #pts
	local m = newMesh()
	local function P(u: number, v: number, w: number): Vector3
		if axis == "x" then
			return Vector3.new(w, u, v)
		elseif axis == "y" then
			return Vector3.new(u, w, v)
		end
		return Vector3.new(u, v, w)
	end
	for i = 1, n do
		m.V[i] = P(pts[i][1], pts[i][2], a0)
		m.V[n + i] = P(pts[i][1], pts[i][2], a1)
	end
	-- (x, z) seen from +Y runs clockwise, so axis "y" reverses every face (as in m4_model.prism).
	local flip = axis == "y"
	local function tri(a: number, b: number, c: number)
		if flip then
			addTri(m, a, c, b)
		else
			addTri(m, a, b, c)
		end
	end
	for _, t in earClip(pts) do
		tri(n + t[1], n + t[2], n + t[3])
		tri(t[1], t[3], t[2])
	end
	for i = 1, n do
		local j = i % n + 1
		tri(i, j, n + j)
		tri(i, n + j, n + i)
	end
	return m
end

local function lathe(r: any): Mesh
	local prof, segs = r.profile, r.segs
	local cx, cz, rx, rz = r.cx or 0, r.cz or 0, r.rx or 1, r.rz or 1
	local ribs = r.ribs
	local m = newMesh()
	local cosT, sinT, kT = {}, {}, {}
	for s = 0, segs - 1 do
		local t = 2 * math.pi * s / segs
		cosT[s], sinT[s] = math.cos(t), math.sin(t)
		kT[s] = if ribs and math.cos(ribs[1] * t) <= ribs[2] then ribs[3] else 1
	end
	for i, pr in prof do
		for s = 0, segs - 1 do
			local rad = pr[2] * kT[s]
			m.V[(i - 1) * segs + s + 1] = Vector3.new(cx + rad * rx * cosT[s], pr[1], cz + rad * rz * sinT[s])
		end
	end
	for i = 1, #prof - 1 do
		-- Smooth around the axis, sharp between profile segments: normal = (dy, -dr) in the (radial, y) plane.
		local dy, dr = prof[i + 1][1] - prof[i][1], prof[i + 1][2] - prof[i][2]
		local len = math.sqrt(dy * dy + dr * dr)
		local nr, ny = 1, 0
		if len > 0 then
			nr, ny = dy / len, -dr / len
		end
		for s = 0, segs - 1 do
			local s1 = (s + 1) % segs
			local a, b = (i - 1) * segs + s + 1, (i - 1) * segs + s1 + 1
			local c, d = b + segs, a + segs
			local na = Vector3.new(nr * cosT[s], ny, nr * sinT[s])
			local nb = Vector3.new(nr * cosT[s1], ny, nr * sinT[s1])
			addTri(m, a, d, c, { na, na, nb })
			addTri(m, a, c, b, { na, nb, nb })
		end
	end
	if r.cap0 then
		for s = 2, segs - 1 do
			addTri(m, 1, s, s + 1)
		end
	end
	if r.cap1 then
		local base = (#prof - 1) * segs
		for s = 2, segs - 1 do
			addTri(m, base + 1, base + s + 1, base + s)
		end
	end
	return m
end

local function cylx(r: any): Mesh
	local cy, cz, rad, segs = r.c[2], r.c[3], r.r, r.segs
	local m = newMesh()
	local cosT, sinT = {}, {}
	for s = 0, segs - 1 do
		local t = 2 * math.pi * s / segs
		cosT[s], sinT[s] = math.cos(t), math.sin(t)
		m.V[s + 1] = Vector3.new(r.x[1], cy + rad * cosT[s], cz + rad * sinT[s])
		m.V[segs + s + 1] = Vector3.new(r.x[2], cy + rad * cosT[s], cz + rad * sinT[s])
	end
	for s = 0, segs - 1 do
		local s1 = (s + 1) % segs
		local a, b = s + 1, s1 + 1
		local na, nb = Vector3.new(0, cosT[s], sinT[s]), Vector3.new(0, cosT[s1], sinT[s1])
		addTri(m, a, b, b + segs, { na, nb, nb })
		addTri(m, a, b + segs, a + segs, { na, nb, na })
	end
	for s = 2, segs - 1 do
		addTri(m, 1, s + 1, s)
		addTri(m, segs + 1, segs + s, segs + s + 1)
	end
	return m
end

-- base64 → buffer
local B64: { [number]: number } = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do
		B64[string.byte(alphabet, i)] = i - 1
	end
end

local function decode64(s: string): buffer
	local n = #s
	local pad = if string.sub(s, -2) == "==" then 2 elseif string.sub(s, -1) == "=" then 1 else 0
	local out = buffer.create(n // 4 * 3 - pad)
	local size = buffer.len(out)
	local o = 0
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = B64[a] * 262144 + B64[b] * 4096 + (B64[c :: number] or 0) * 64 + (B64[d :: number] or 0)
		buffer.writeu8(out, o, v // 65536)
		if o + 1 < size then
			buffer.writeu8(out, o + 1, (v // 256) % 256)
		end
		if o + 2 < size then
			buffer.writeu8(out, o + 2, v % 256)
		end
		o += 3
	end
	return out
end

-- "mesh" recipe: an encoded triangle mesh in weapon space (see the header)
local function decodedMesh(r: any): Mesh
	local buf = decode64(if type(r.data) == "table" then table.concat(r.data) else r.data)
	local nv, nt = buffer.readu32(buf, 0), buffer.readu32(buf, 4)
	local m = newMesh()
	local Q = 2e-5
	local pv, pn, pt = 8, 8 + nv * 6, 8 + nv * 9
	local normals = table.create(nv)
	for i = 0, nv - 1 do
		local o = pv + i * 6
		m.V[i + 1] = Vector3.new(buffer.readi16(buf, o) * Q, buffer.readi16(buf, o + 2) * Q, buffer.readi16(buf, o + 4) * Q)
		local q = pn + i * 3
		local n = Vector3.new(buffer.readi8(buf, q), buffer.readi8(buf, q + 1), buffer.readi8(buf, q + 2))
		normals[i + 1] = if n.Magnitude > 0 then n.Unit else Vector3.zAxis
	end
	for t = 0, nt - 1 do
		local o = pt + t * 6
		local a, b, c = buffer.readu16(buf, o) + 1, buffer.readu16(buf, o + 2) + 1, buffer.readu16(buf, o + 4) + 1
		table.insert(m.T, { a, b, c })
		table.insert(m.N, { normals[a], normals[b], normals[c] })
	end
	return m
end

local function mapMesh(m: Mesh, f: (Vector3) -> Vector3, fn: (Vector3) -> Vector3, mirror: boolean): Mesh
	for i, v in m.V do
		m.V[i] = f(v)
	end
	for i, ns in m.N do
		m.N[i] = if mirror then { fn(ns[1]), fn(ns[3]), fn(ns[2]) } else { fn(ns[1]), fn(ns[2]), fn(ns[3]) }
	end
	if mirror then
		for i, t in m.T do
			m.T[i] = { t[1], t[3], t[2] }
		end
	end
	return m
end

local function merge(into: Mesh, m: Mesh)
	local base = #into.V
	for _, v in m.V do
		table.insert(into.V, v)
	end
	for i, t in m.T do
		table.insert(into.T, { t[1] + base, t[2] + base, t[3] + base })
		table.insert(into.N, m.N[i])
	end
end

local function build(r: any): Mesh
	local op = r.op
	if op == "prism" then
		return prism(r.pts, r.axis, r.a[1], r.a[2])
	elseif op == "box" then
		local c, s = r.c, r.s
		local hx, hy, hz = s[1] / 2, s[2] / 2, s[3] / 2
		return prism({
			{ c[1] - hx, c[2] - hy },
			{ c[1] + hx, c[2] - hy },
			{ c[1] + hx, c[2] + hy },
			{ c[1] - hx, c[2] + hy },
		}, "z", c[3] - hz, c[3] + hz)
	elseif op == "lathe" then
		return lathe(r)
	elseif op == "cylx" then
		return cylx(r)
	elseif op == "mesh" then
		return decodedMesh(r)
	elseif op == "translate" then
		local d = Vector3.new(r.d[1], r.d[2], r.d[3])
		return mapMesh(build(r.geo), function(v)
			return v + d
		end, function(n)
			return n
		end, false)
	elseif op == "rotx" then
		local a = math.rad(r.deg)
		local c, s = math.cos(a), math.sin(a)
		local ay, az = r.about[2], r.about[3]
		return mapMesh(build(r.geo), function(v)
			local y0, z0 = v.Y - ay, v.Z - az
			return Vector3.new(v.X, ay + c * y0 - s * z0, az + s * y0 + c * z0)
		end, function(n)
			return Vector3.new(n.X, c * n.Y - s * n.Z, s * n.Y + c * n.Z)
		end, false)
	elseif op == "mirrorx" then
		local flipX = function(v: Vector3)
			return Vector3.new(-v.X, v.Y, v.Z)
		end
		return mapMesh(build(r.geo), flipX, flipX, true)
	elseif op == "repeaty" then
		local out = newMesh()
		for i = 0, r.count - 1 do
			local dy = i * r.step
			merge(
				out,
				mapMesh(build(r.geo), function(v)
					return v + Vector3.new(0, dy, 0)
				end, function(n)
					return n
				end, false)
			)
		end
		return out
	end
	error("ProceduralMesh: unknown recipe op " .. tostring(op))
end

-- Builds one MeshPart from a list of recipes. `origin` = the bone origin in weapon space (metres).
-- Returns the part (anchored, no collision) and its centre in the bone's frame (studs).
function ProceduralMesh.buildPart(recipes: { any }, origin: { number }): (MeshPart, Vector3)
	local mesh = newMesh()
	for _, r in recipes do
		merge(mesh, build(r))
	end
	local o = Vector3.new(origin[1], origin[2], origin[3])
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for i, v in mesh.V do
		local d = v - o
		local p = Vector3.new(d.X, d.Z, -d.Y) / STUD
		mesh.V[i] = p
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local centre = (lo + hi) / 2

	local em = AssetService:CreateEditableMesh()
	assert(em, "ProceduralMesh: client editable-memory budget exhausted")
	local vids = table.create(#mesh.V)
	for i, p in mesh.V do
		vids[i] = em:AddVertex(p - centre)
	end
	for i, t in mesh.T do
		local ns = mesh.N[i]
		local face = em:AddTriangle(vids[t[1]], vids[t[2]], vids[t[3]])
		local function rn(n: Vector3): number
			return em:AddNormal(Vector3.new(n.X, n.Z, -n.Y))
		end
		em:SetFaceNormals(face, { rn(ns[1]), rn(ns[2]), rn(ns[3]) })
	end
	-- An empty EditableMesh is always resizable and costs far more of the client's editable-memory budget than a
	-- fixed-size one (Studio client: 8 resizable vs 400+ fixed). Keep a fixed-size copy (same data) and free the
	-- resizable original, so several production viewmodels fit at once.
	local fixed = AssetService:CreateEditableMeshAsync(Content.fromObject(em))
	if fixed then
		em:Destroy()
		em = fixed
	end
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(em), {
		CollisionFidelity = Enum.CollisionFidelity.Box,
	})
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	return part, centre
end

return ProceduralMesh
