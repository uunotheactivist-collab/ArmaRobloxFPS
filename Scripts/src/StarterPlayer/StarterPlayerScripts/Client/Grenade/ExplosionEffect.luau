--!strict
-- Grenade detonation effect (client presentation only), from the server's one message per detonation. The footage's
-- sequence (Config.Grenade.Effects; timings measured, looks confirmed, sizes / colours placeholder):
--   frame 0      thin bright spark streaks
--   frames 1–4   white-yellow flash + a long, low, horizontal ground glare + a short warm light
--   then         the glow fades within 2–3 frames
--   from ≈2      brown / tan dust billowing up for ≥ 2 s
-- No camera shake and no screen flash (confirmed). A small pool of effect rigs (one Attachment in Terrain each, with
-- three emitters, a light and a billboard), reused round-robin: nothing is created per detonation, no parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))
local E = Config.Effects

local ExplosionEffect = {}

type Rig = {
	Attachment: Attachment,
	Sparks: ParticleEmitter,
	Flash: ParticleEmitter,
	Dust: ParticleEmitter,
	Light: PointLight,
	Glare: BillboardGui,
	GlareFrame: Frame,
}
local rigs: { Rig } = {}
local index = 0
ExplosionEffect.Played = 0

local function emitter(parent: Instance, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.Enabled = false
	e.LockedToPart = false
	e.Parent = parent
	return e
end

local function make(): Rig
	local a = Instance.new("Attachment")
	a.Name = "GrenadeFx"
	a.Parent = workspace.Terrain

	local sparks = emitter(a, E.SparkTexture)
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Brightness = E.Sparks.Brightness
	sparks.Size = NumberSequence.new(E.Sparks.Size)
	sparks.Squash = NumberSequence.new(-3) -- stretched along the velocity: thin streaks
	sparks.Speed = NumberRange.new(E.Sparks.Speed[1], E.Sparks.Speed[2])
	sparks.Lifetime = NumberRange.new(E.Sparks.Lifetime[1], E.Sparks.Lifetime[2])
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Color = ColorSequence.new(E.Sparks.Color)
	sparks.Transparency = NumberSequence.new(0, 0.6)

	local flash = emitter(a, E.Texture)
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.Brightness = 3
	flash.Speed = NumberRange.new(0)
	flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, E.Flash.Size[1]), NumberSequenceKeypoint.new(1, E.Flash.Size[2]) })
	flash.Lifetime = NumberRange.new(E.FlashSeconds, E.FlashSeconds + E.FadeSeconds)
	flash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.1), NumberSequenceKeypoint.new(1, 1) })
	flash.Color = ColorSequence.new(E.Flash.Color)
	flash.Rotation = NumberRange.new(0, 360)

	local dust = emitter(a, E.Texture)
	dust.LightInfluence = 0.35 -- stays tan in a dark, stormy scene, as in the footage
	dust.Speed = NumberRange.new(E.Dust.Speed[1], E.Dust.Speed[2])
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Acceleration = Vector3.new(0, 0.6, 0)
	dust.Drag = 1.2
	dust.Lifetime = NumberRange.new(E.Dust.Lifetime[1], E.Dust.Lifetime[2])
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, E.Dust.Size[1]), NumberSequenceKeypoint.new(1, E.Dust.Size[2]) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(E.Dust.Color)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-15, 15)

	local light = Instance.new("PointLight")
	light.Brightness = E.Light.Brightness
	light.Range = E.Light.Range
	light.Color = E.Light.Color
	light.Shadows = false
	light.Enabled = false
	light.Parent = a

	local glare = Instance.new("BillboardGui")
	glare.Name = "GroundGlare"
	glare.Size = UDim2.fromScale(E.Glare.WidthStuds, E.Glare.HeightStuds)
	glare.LightInfluence = 0
	glare.Brightness = 2
	glare.AlwaysOnTop = false
	glare.Enabled = false
	glare.Parent = a
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = E.Glare.Color
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.55), NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.65, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = f
	f.Parent = glare

	return { Attachment = a, Sparks = sparks, Flash = flash, Dust = dust, Light = light, Glare = glare, GlareFrame = f }
end

function ExplosionEffect.play(pos: Vector3)
	index = index % E.Pool + 1
	local r = rigs[index]
	if not r or not r.Attachment.Parent then
		r = make()
		rigs[index] = r
	end
	ExplosionEffect.Played += 1
	r.Attachment.WorldPosition = pos + Vector3.new(0, 0.2, 0)
	-- frame 0: sparks
	r.Sparks:Emit(E.Sparks.Count)
	-- frames 1–4: flash, ground glare, warm light; then the fade
	task.delay(E.FlashAt, function()
		r.Flash:Emit(E.Flash.Count)
		r.Light.Enabled = true
		r.Light.Brightness = E.Light.Brightness
		r.Glare.Enabled = true
		r.GlareFrame.BackgroundTransparency = 0
		task.delay(E.FlashSeconds, function()
			TweenService:Create(r.GlareFrame, TweenInfo.new(E.FadeSeconds), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(r.Light, TweenInfo.new(E.FadeSeconds), { Brightness = 0 }):Play()
			task.delay(E.FadeSeconds + 0.02, function()
				r.Glare.Enabled = false
				r.Light.Enabled = false
			end)
		end)
	end)
	-- dust from about frame 2, lasting ≥ 2 s
	task.delay(E.DustAt, function()
		r.Dust:Emit(E.Dust.Count)
	end)
end

function ExplosionEffect.size(): number
	local n = 0
	for _, r in rigs do
		if r.Attachment.Parent then
			n += 1
		end
	end
	return n
end

return ExplosionEffect
