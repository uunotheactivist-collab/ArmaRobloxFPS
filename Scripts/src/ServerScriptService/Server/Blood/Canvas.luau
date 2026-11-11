--!strict
-- Blood drawing helpers (server). Blood is drawn as soft blobs on SurfaceGuis: no textures, no uploads. A blob is a
-- few overlapping round frames (UICorner); overlaps read as darker, blotchy cores.
-- Face mapping: the part axes a SurfaceGui's canvas X / Y run along, per face. Measured in Studio (2026-11-06): each
-- face reads correctly when seen from outside, and canvas-down is −Y on the four side faces.

local Canvas = {}

local AXES: { [Enum.NormalId]: { Vector3 } } = {
	[Enum.NormalId.Top] = { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0) },
	[Enum.NormalId.Bottom] = { Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0) },
	[Enum.NormalId.Front] = { Vector3.new(-1, 0, 0), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Back] = { Vector3.new(1, 0, 0), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Right] = { Vector3.new(0, 0, -1), Vector3.new(0, -1, 0) },
	[Enum.NormalId.Left] = { Vector3.new(0, 0, 1), Vector3.new(0, -1, 0) },
}

-- The part face a world normal points out of.
function Canvas.faceOf(part: BasePart, worldNormal: Vector3): Enum.NormalId
	local n = part.CFrame:VectorToObjectSpace(worldNormal)
	local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
	if ax >= ay and ax >= az then
		return if n.X > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	elseif ay >= az then
		return if n.Y > 0 then Enum.NormalId.Top else Enum.NormalId.Bottom
	end
	return if n.Z > 0 then Enum.NormalId.Back else Enum.NormalId.Front
end

-- Canvas position (0–1 scale) of a world point on a part face, and the face's size in studs along canvas X / Y.
function Canvas.uv(part: BasePart, face: Enum.NormalId, worldPoint: Vector3): (Vector2, Vector2)
	local a = AXES[face]
	local p = part.CFrame:PointToObjectSpace(worldPoint)
	local s = part.Size
	local function len(v: Vector3): number
		return math.abs(v.X) * s.X + math.abs(v.Y) * s.Y + math.abs(v.Z) * s.Z
	end
	local wu, wv = len(a[1]), len(a[2])
	return Vector2.new(0.5 + p:Dot(a[1]) / wu, 0.5 + p:Dot(a[2]) / wv), Vector2.new(wu, wv)
end

-- A world direction expressed on a part face's canvas (canvas X, canvas Y), not normalised.
function Canvas.canvasDirection(part: BasePart, face: Enum.NormalId, worldDir: Vector3): Vector2
	local a = AXES[face]
	local d = part.CFrame:VectorToObjectSpace(worldDir)
	return Vector2.new(d:Dot(a[1]), d:Dot(a[2]))
end

-- The SurfaceGui holding blood of one kind on a part face (created on first use).
function Canvas.gui(part: BasePart, face: Enum.NormalId, kind: string, pixelsPerStud: number): SurfaceGui
	local key = kind .. "_" .. face.Name
	local existing = part:FindFirstChild(key)
	if existing and existing:IsA("SurfaceGui") then
		return existing
	end
	local g = Instance.new("SurfaceGui")
	g.Name = key
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pixelsPerStud
	g.LightInfluence = 1 -- shaded like the surface it is on
	g.ClipsDescendants = true
	g.Parent = part
	return g
end

local function circle(parent: Instance, pos: Vector2, size: number, color: Color3, transparency: number)
	local c = Instance.new("Frame")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(pos.X, pos.Y)
	c.Size = UDim2.fromScale(size, size)
	c.BackgroundColor3 = color
	c.BackgroundTransparency = transparency
	c.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = c
	c.Parent = parent
end

-- A blob of `studs` across at canvas position uv on a face of faceStuds. pieces = 1: a round drop (plus a short tail
-- in canvas direction `tail`, if given); pieces > 1: an irregular blotch. Returns its holder frame.
function Canvas.blob(parent: Instance, uv: Vector2, faceStuds: Vector2, studs: number, color: Color3, transparency: number,
	pieces: number, rng: Random, tail: Vector2?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Blood"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(uv.X, uv.Y)
	holder.Size = UDim2.fromScale(studs / faceStuds.X, studs / faceStuds.Y)
	if pieces <= 1 then
		circle(holder, Vector2.new(0.5, 0.5), 1, color, transparency)
	else
		circle(holder, Vector2.new(0.5, 0.5), rng:NextNumber(0.6, 0.8), color, transparency)
		for _ = 2, pieces do
			local off = Vector2.new(rng:NextNumber(-0.28, 0.28), rng:NextNumber(-0.28, 0.28))
			circle(holder, Vector2.new(0.5, 0.5) + off, rng:NextNumber(0.3, 0.55), color, transparency)
		end
	end
	if tail and tail.Magnitude > 1e-3 then
		local d = tail.Unit
		local len = rng:NextNumber(0.55, 0.9)
		circle(holder, Vector2.new(0.5, 0.5) + d * len, rng:NextNumber(0.25, 0.4), color, transparency)
		circle(holder, Vector2.new(0.5, 0.5) + d * len * 0.55, rng:NextNumber(0.3, 0.45), color, transparency)
	end
	holder.Parent = parent
	return holder
end

-- An invisible patch part laid on a surface (its Top face = the surface, lifted by `lift`), for blood on world
-- surfaces: anchored, no collision / query / touch, no shadow.
function Canvas.patch(name: string, center: Vector3, normal: Vector3, studs: number, lift: number): BasePart
	local up = normal.Unit
	local ref = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local right = ref:Cross(up).Unit
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(studs, 0.02, studs)
	part.CFrame = CFrame.fromMatrix(center + up * (lift + 0.01), right, up)
	return part
end

return Canvas
