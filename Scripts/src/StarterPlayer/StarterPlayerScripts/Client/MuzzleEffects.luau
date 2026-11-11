--!strict
-- Shot presentation supported by the reference (Config.Weapons.<Id>.Muzzle): a small yellow-white flash at the
-- muzzle for ~1 frame, a warm light placed behind the sight (the footage lights the sight's rear face, the
-- receiver, the arm and the floor ahead) and brass ejected right / up-right, spinning. No tracers or impacts:
-- none are visible in the footage. Client-only; parts are pooled and moved with BulkMoveTo.
-- Optional per-weapon layers, only built when the weapon's Muzzle config has them (MP7 slice; the M4 / AK configs
-- have none, so they are unchanged): Streak (an elongated flame along the bore, shown with the flash), Sparks (a few
-- small fast particles per shot) and Smoke (a puff per shot that rises, grows and fades). All pooled, created once.
-- Brass.AtCycle (Sniper slice, optional): the shot makes no casing; the bolt's rear stroke calls Eject.

local MuzzleEffects = {}
MuzzleEffects.__index = MuzzleEffects

local POOL = 16
local HIDDEN = CFrame.new(0, -10000, 0)

type Casing = { Part: BasePart, Pos: Vector3, Vel: Vector3, Rot: CFrame, Spin: Vector3, Born: number }
type Particle = { Part: BasePart, Pos: Vector3, Vel: Vector3, Born: number }
export type MuzzleEffects = typeof(setmetatable(
	{} :: {
		Cfg: any,
		Folder: Folder,
		Flash: Model,
		FlashParts: { BasePart },
		FlashUntil: number,
		LightPart: BasePart,
		Light: PointLight,
		LightUntil: number,
		Casings: { Casing },
		NextCasing: number,
		Rng: Random,
		Streak: BasePart?,
		Sparks: { Particle },
		NextSpark: number,
		Smoke: { Particle },
		NextSmoke: number,
	},
	MuzzleEffects
))

local function effectPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = HIDDEN
	return p
end

function MuzzleEffects.new(cfg: any): MuzzleEffects
	local m = cfg.Muzzle
	local folder = Instance.new("Folder")
	folder.Name = "ProductionWeaponEffects"

	local flash = Instance.new("Model")
	flash.Name = "MuzzleFlash"
	local size = m.FlashSizeStuds
	local core = effectPart("Core", Enum.PartType.Ball, Vector3.one * size * 0.55, Color3.fromRGB(255, 244, 205), Enum.Material.Neon)
	core.Parent = flash
	local parts = { core }
	for i = 1, 3 do
		local petal = effectPart(`Petal{i}`, Enum.PartType.Block, Vector3.new(size * 0.16, size * 0.16, size), Color3.fromRGB(255, 205, 120), Enum.Material.Neon)
		petal.Transparency = 0.15
		petal.Parent = flash
		table.insert(parts, petal)
	end
	local streak: BasePart? = nil
	if m.Streak then
		local st = m.Streak
		local p = effectPart("Streak", Enum.PartType.Block, Vector3.new(st.WidthStuds, st.WidthStuds, st.LengthStuds),
			Color3.fromRGB(st.Color[1], st.Color[2], st.Color[3]), Enum.Material.Neon)
		p.Transparency = 0.2
		p.Parent = flash
		table.insert(parts, p) -- moved and hidden together with the flash
		streak = p
	end
	flash.Parent = folder

	local sparks: { Particle } = {}
	if m.Sparks then
		for i = 1, m.Sparks.Count * 4 do
			local p = effectPart(`Spark{i}`, Enum.PartType.Ball, Vector3.one * m.Sparks.SizeStuds, Color3.fromRGB(255, 250, 235), Enum.Material.Neon)
			p.Parent = folder
			table.insert(sparks, { Part = p, Pos = Vector3.zero, Vel = Vector3.zero, Born = -math.huge })
		end
	end
	local smoke: { Particle } = {}
	if m.Smoke then
		for i = 1, m.Smoke.Pool do
			local p = effectPart(`Smoke{i}`, Enum.PartType.Ball, Vector3.one * m.Smoke.SizeStuds, Color3.fromRGB(225, 225, 225), Enum.Material.SmoothPlastic)
			p.Transparency = 1
			p.Parent = folder
			table.insert(smoke, { Part = p, Pos = Vector3.zero, Vel = Vector3.zero, Born = -math.huge })
		end
	end

	local lightPart = effectPart("FlashLight", Enum.PartType.Block, Vector3.one * 0.05, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(m.LightColor[1], m.LightColor[2], m.LightColor[3])
	light.Brightness = m.LightBrightness
	light.Range = m.LightRange
	light.Shadows = false
	light.Enabled = false
	light.Parent = lightPart
	lightPart.Parent = folder

	local casings = {}
	for i = 1, POOL do
		local c = effectPart(`Casing{i}`, Enum.PartType.Cylinder, Vector3.new(0.161, 0.034, 0.034), Color3.fromRGB(198, 156, 74), Enum.Material.Metal)
		c.Parent = folder
		table.insert(casings, { Part = c, Pos = Vector3.zero, Vel = Vector3.zero, Rot = CFrame.identity, Spin = Vector3.zero, Born = -math.huge })
	end

	return setmetatable({
		Cfg = m,
		Folder = folder,
		Flash = flash,
		FlashParts = parts,
		FlashUntil = -math.huge,
		LightPart = lightPart,
		Light = light,
		LightUntil = -math.huge,
		Casings = casings,
		NextCasing = 1,
		Rng = Random.new(),
		Streak = streak,
		Sparks = sparks,
		NextSpark = 1,
		Smoke = smoke,
		NextSmoke = 1,
	}, MuzzleEffects)
end

-- muzzle: CFrame at the muzzle looking along the bore; eject: CFrame at the ejection port (weapon orientation).
function MuzzleEffects.Shot(self: MuzzleEffects, now: number, muzzle: CFrame, eject: CFrame, camera: CFrame)
	local m, r = self.Cfg, self.Rng
	local s = r:NextNumber(0.8, 1.2)
	local base = muzzle * CFrame.Angles(0, 0, r:NextNumber(0, math.pi * 2))
	local cfs = { base }
	for i = 1, 3 do
		local a = (i - 1) * math.pi * 2 / 3
		local tilt = CFrame.Angles(0, 0, a) * CFrame.Angles(math.rad(r:NextNumber(18, 32)), 0, 0)
		table.insert(cfs, base * tilt * CFrame.new(0, 0, -m.FlashSizeStuds * 0.45 * s))
	end
	if self.Streak then -- along the bore, starting at the muzzle
		local len = m.Streak.LengthStuds * r:NextNumber(0.75, 1.15)
		table.insert(cfs, base * CFrame.Angles(math.rad(r:NextNumber(-4, 4)), math.rad(r:NextNumber(-4, 4)), 0)
			* CFrame.new(0, 0, -len / 2))
	end
	workspace:BulkMoveTo(self.FlashParts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	self.FlashUntil = now + m.FlashTime
	if m.Sparks then
		for _ = 1, m.Sparks.Count do
			local p = self.Sparks[self.NextSpark]
			self.NextSpark = self.NextSpark % #self.Sparks + 1
			local dir = (muzzle * CFrame.Angles(math.rad(r:NextNumber(-25, 25)), math.rad(r:NextNumber(-25, 25)), 0)).LookVector
			p.Pos = muzzle.Position
			p.Vel = dir * m.Sparks.SpeedStuds * r:NextNumber(0.6, 1.2)
			p.Born = now
		end
	end
	if m.Smoke then
		local p = self.Smoke[self.NextSmoke]
		self.NextSmoke = self.NextSmoke % #self.Smoke + 1
		p.Pos = muzzle.Position + muzzle.LookVector * m.Smoke.SizeStuds * 0.5
		p.Vel = muzzle.LookVector * r:NextNumber(0.5, 1.5) + Vector3.new(r:NextNumber(-0.3, 0.3), m.Smoke.RiseStudsPerSec, r:NextNumber(-0.3, 0.3))
		p.Born = now
	end

	local o = m.LightOffset
	self.LightPart.CFrame = camera * CFrame.new(o[1], o[2], o[3])
	self.Light.Enabled = true
	self.LightUntil = now + m.LightTime

	if not m.Brass.AtCycle then
		self:Eject(now, eject)
	end
end

-- One casing from the ejection port. Called by Shot, or - for a manual action whose config has Brass.AtCycle (the
-- Sniper slice) - by Client.WeaponController at the bolt's rear stroke.
function MuzzleEffects.Eject(self: MuzzleEffects, now: number, eject: CFrame)
	local r = self.Rng
	local b = self.Cfg.Brass
	local c = self.Casings[self.NextCasing]
	self.NextCasing = self.NextCasing % #self.Casings + 1
	c.Pos = eject.Position
	c.Vel = eject.RightVector * b.SpeedRight * r:NextNumber(0.85, 1.15)
		+ eject.UpVector * b.SpeedUp * r:NextNumber(0.7, 1.2)
		- eject.LookVector * b.SpeedBack * r:NextNumber(0.5, 1.5)
	c.Rot = eject.Rotation * CFrame.Angles(0, math.rad(90), 0) -- casing axis (part X) along the bore
	local spin = math.rad(b.SpinDegPerSec)
	c.Spin = Vector3.new(r:NextNumber(-0.3, 0.3), r:NextNumber(0.6, 1), r:NextNumber(-0.5, 0.5)) * spin
	c.Born = now
end

function MuzzleEffects.Step(self: MuzzleEffects, now: number, dt: number)
	if now >= self.FlashUntil and self.FlashUntil > -math.huge then
		local hidden = table.create(#self.FlashParts, HIDDEN)
		workspace:BulkMoveTo(self.FlashParts, hidden, Enum.BulkMoveMode.FireCFrameChanged)
		self.FlashUntil = -math.huge
	end
	if now >= self.LightUntil then
		self.Light.Enabled = false
	end
	local b = self.Cfg.Brass
	local parts, cfs = {}, {}
	for _, c in self.Casings do
		local age = now - c.Born
		if age >= 0 and age < b.Lifetime then
			c.Vel -= Vector3.new(0, b.Gravity * dt, 0)
			c.Pos += c.Vel * dt
			c.Rot = c.Rot * CFrame.Angles(c.Spin.X * dt, c.Spin.Y * dt, c.Spin.Z * dt)
			table.insert(parts, c.Part)
			table.insert(cfs, CFrame.new(c.Pos) * c.Rot)
		elseif c.Born > -math.huge then
			c.Born = -math.huge
			table.insert(parts, c.Part)
			table.insert(cfs, HIDDEN)
		end
	end
	local m = self.Cfg
	if m.Sparks then
		for _, p in self.Sparks do
			local age = now - p.Born
			if age >= 0 and age < m.Sparks.Lifetime then
				p.Pos += p.Vel * dt
				table.insert(parts, p.Part)
				table.insert(cfs, CFrame.new(p.Pos))
			elseif p.Born > -math.huge then
				p.Born = -math.huge
				table.insert(parts, p.Part)
				table.insert(cfs, HIDDEN)
			end
		end
	end
	if m.Smoke then
		local sm = m.Smoke
		for _, p in self.Smoke do
			local age = now - p.Born
			if age >= 0 and age < sm.Lifetime then
				local k = age / sm.Lifetime
				p.Vel *= math.exp(-dt / 0.25) -- the forward push dies out; the rise is kept by the buoyancy below
				p.Vel += Vector3.new(0, sm.RiseStudsPerSec * dt * 3, 0)
				p.Pos += p.Vel * dt
				p.Part.Size = Vector3.one * (sm.SizeStuds + sm.GrowStuds * k)
				p.Part.Transparency = sm.Transparency + (1 - sm.Transparency) * k
				table.insert(parts, p.Part)
				table.insert(cfs, CFrame.new(p.Pos))
			elseif p.Born > -math.huge then
				p.Born = -math.huge
				p.Part.Transparency = 1
				table.insert(parts, p.Part)
				table.insert(cfs, HIDDEN)
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function MuzzleEffects.Clear(self: MuzzleEffects)
	self.FlashUntil = 0
	self.LightUntil = 0
	for _, c in self.Casings do
		c.Born = -math.huge
		c.Part.CFrame = HIDDEN
	end
	for _, list in { self.Sparks, self.Smoke } do
		for _, p in list do
			p.Born = -math.huge
			p.Part.CFrame = HIDDEN
			if list == self.Smoke then
				p.Part.Transparency = 1
			end
		end
	end
	self:Step(math.huge, 0)
end

return MuzzleEffects
