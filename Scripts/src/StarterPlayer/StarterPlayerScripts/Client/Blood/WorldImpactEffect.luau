--!strict
-- World impact effect (client): presentation of one authoritative surface entry or exit from the server
-- (Shared.Remotes.ImpactFx). A grey / white puff and a few chips at the traced point, along the surface normal; a puff
-- along the bullet where it leaves a penetrable surface. Penetrable and NonPenetrable look the same (a difference is
-- UNKNOWN in the footage); no bullet holes, no ricochet (none seen). Values: Config.Blood.World.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))
local EmitterPool = require(script.Parent:WaitForChild("EmitterPool"))

local WorldImpactEffect = {}

local CHIPS = Color3.fromRGB(120, 120, 118)

function WorldImpactEffect.play(ev: any)
	local W = Config.World
	local p: Vector3 = ev.p
	local n: Vector3 = if typeof(ev.n) == "Vector3" then ev.n else Vector3.yAxis
	if ev.out == true then
		EmitterPool.burst(p, if typeof(ev.d) == "Vector3" then ev.d else n, W.Puff, Config.Dust, nil, true)
		return
	end
	EmitterPool.burst(p, n, W.Puff, Config.Dust, nil, true)
	EmitterPool.burst(p, n, W.Chips, CHIPS, nil, false)
end

return WorldImpactEffect
