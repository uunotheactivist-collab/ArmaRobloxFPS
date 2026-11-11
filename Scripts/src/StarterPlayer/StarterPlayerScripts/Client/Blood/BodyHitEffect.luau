--!strict
-- Body hit effect (client): presentation of one authoritative body entry from the server (Shared.Remotes.ImpactFx).
-- At the entry point the server traced: a bright red spot, then a short red puff, a little red mist and small
-- droplets thrown out of the entry, away from the body (along the entry surface's normal). If the bullet left the
-- part: a droplet spray out of the exit along the bullet. Unless the body is DEAD: a slow mist that follows the wound
-- for a few seconds. All values: Config.Blood.Body (tagged).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))
local EmitterPool = require(script.Parent:WaitForChild("EmitterPool"))

local BodyHitEffect = {}

local activeBleeds = 0

-- A slow mist at the wound that rides on the body part (through the fall and the ragdoll), then removes itself.
local function bleed(part: BasePart, at: Vector3, normal: Vector3)
	local B = Config.Body
	if activeBleeds >= B.MaxBleeds or not part:IsDescendantOf(workspace) then
		return
	end
	activeBleeds += 1
	local a = Instance.new("Attachment")
	a.Name = "BleedFx"
	a.Parent = part
	-- at the wound, emitting out of the body (the wound face's normal), so the mist hangs beside the body
	a.WorldCFrame = EmitterPool.frame(at, normal)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Config.Texture
	e.LightInfluence = 1
	e.LockedToPart = false
	EmitterPool.configure(e, B.Bleed, Config.Mist, nil, true)
	e.Rate = B.Bleed.Rate
	e.Parent = a
	task.delay(B.Bleed.Seconds, function()
		e.Enabled = false
	end)
	task.delay(B.Bleed.Seconds + B.Bleed.Lifetime[2] + 0.1, function()
		a:Destroy()
		activeBleeds -= 1
	end)
end

function BodyHitEffect.play(ev: any)
	local B = Config.Body
	local p: Vector3 = ev.p
	local away: Vector3 = if typeof(ev.n) == "Vector3" then ev.n else -ev.d
	EmitterPool.burst(p, away, B.Spot, Config.Spot, nil, false)
	EmitterPool.burst(p, away, B.Puff, Config.Spot, Config.Mist, true)
	EmitterPool.burst(p, away, B.Mist, Config.Mist, nil, true)
	EmitterPool.burst(p, away, B.Droplets, Config.Blood, nil, false)
	EmitterPool.burst(p, away, B.LargeDrops, Config.BloodDark, nil, false)
	if typeof(ev.x) == "Vector3" and typeof(ev.d) == "Vector3" then
		EmitterPool.burst(ev.x, ev.d, B.ExitSpray, Config.Blood, nil, false)
	end
	if ev.bleed == true and typeof(ev.part) == "Instance" and ev.part:IsA("BasePart") then
		bleed(ev.part, p, away)
	end
end

function BodyHitEffect.activeBleeds(): number
	return activeBleeds
end

return BodyHitEffect
