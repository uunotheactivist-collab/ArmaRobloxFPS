--!strict
-- Pooled world-space particle emitters (client). A fixed number of sets (Config.Blood.EmitterPool), each an
-- Attachment in workspace.Terrain with one ParticleEmitter, reused round-robin and reconfigured per burst. Emitted
-- particles are not locked to the emitter, so moving a set never drags earlier particles along. Nothing is created per
-- shot. Bursts only (Rate 0): no emitter runs on its own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))

local EmitterPool = {}

type Set = { Attachment: Attachment, Emitter: ParticleEmitter }
local sets: { Set } = {}
local index = 0

local function make(): Set
	local a = Instance.new("Attachment")
	a.Name = "ImpactFx"
	a.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = Config.Texture
	e.Rate = 0
	e.Enabled = false
	e.LightInfluence = 1
	e.LockedToPart = false
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = a
	return { Attachment = a, Emitter = e }
end

-- An attachment frame at pos whose +Y (the emission direction) points along dir.
function EmitterPool.frame(pos: Vector3, dir: Vector3): CFrame
	local up = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
	local ref = if math.abs(up.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local right = up:Cross(ref).Unit
	return CFrame.fromMatrix(pos, right, up)
end

-- Configure an emitter from a Config.Blood spec. grow: size grows from Size[1] to Size[2] over the lifetime (puffs,
-- mist); otherwise each particle takes a size within Size.
function EmitterPool.configure(e: ParticleEmitter, spec: any, color: Color3, colorEnd: Color3?, grow: boolean)
	e.Color = ColorSequence.new(color, colorEnd or color)
	local s0, s1 = spec.Size[1], spec.Size[2]
	if grow then
		e.Size = NumberSequence.new(s0, s1)
	else
		local mid, env = (s0 + s1) / 2, (s1 - s0) / 2
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, mid, env), NumberSequenceKeypoint.new(1, mid, env) })
	end
	local t0 = spec.Transparency or 0
	-- soft particles hold their opacity for most of their life, then fade (a linear fade left the mist nearly invisible)
	e.Transparency = if grow
		then NumberSequence.new({
			NumberSequenceKeypoint.new(0, t0),
			NumberSequenceKeypoint.new(0.6, math.min(t0 + 0.15, 1)),
			NumberSequenceKeypoint.new(1, 1),
		})
		else NumberSequence.new(t0, math.min(t0 + 0.3, 1))
	e.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	e.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	e.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
	e.Acceleration = Vector3.new(0, -Config.ParticleGravity * (spec.Gravity or 0), 0)
	e.Drag = if grow then 3 else 0
	-- soft puffs / mist stay readable in shade (fully lit soft particles go nearly black there); drops are lit fully
	e.LightInfluence = if grow then 0.4 else 1
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Rotation = NumberRange.new(0, 360)
end

-- One burst of spec.Count particles at pos, aimed along dir.
function EmitterPool.burst(pos: Vector3, dir: Vector3, spec: any, color: Color3, colorEnd: Color3?, grow: boolean)
	index = index % Config.EmitterPool + 1
	local s = sets[index]
	if not s or not s.Attachment.Parent then
		s = make()
		sets[index] = s
	end
	s.Attachment.WorldCFrame = EmitterPool.frame(pos, dir)
	EmitterPool.configure(s.Emitter, spec, color, colorEnd, grow)
	s.Emitter:Emit(spec.Count)
end

function EmitterPool.size(): number
	local n = 0
	for _, s in sets do
		if s.Attachment.Parent then
			n += 1
		end
	end
	return n
end

return EmitterPool
