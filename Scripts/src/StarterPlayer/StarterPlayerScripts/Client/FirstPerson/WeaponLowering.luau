--!strict
-- Shared first-person weapon lowering (first-person fidelity pass; client presentation only). A short, timed lowering of
-- the whole viewmodel out of view, requested by another first-person action. The only user so far is the grenade throw:
-- the reference's rifle leaves the view as the throw starts and comes back after it (ReferenceAnalysis/FirstPerson).
-- Client.WeaponController multiplies offset(now) into the viewmodel root (camera space); it is the identity when nothing
-- is playing, so every weapon pose is unchanged then. Profile (seconds from the request):
--   DownSeconds  the weapon goes down over [0, DownSeconds]
--   HiddenUntil  stays out of view until then
--   BackBy       is back in place by then
--   ReturnPower  the way back is (1 - u) ^ ReturnPower (ease-out); without it a smoothstep
--   DropStuds / PitchDeg / BackStuds  the fully lowered offset (down, pitched down about the camera, pulled back)
-- The curves are fitted to the reference's on-screen frame counts (what is visible), not measured motion.
-- It changes no weapon state: firing, aiming and reloading keep their own rules.

local WeaponLowering = {}

local active: any = nil
local startedAt = 0
WeaponLowering.Count = 0

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

function WeaponLowering.play(profile: any, now: number?)
	active = profile
	startedAt = now or os.clock()
	WeaponLowering.Count += 1
end

function WeaponLowering.reset()
	active = nil
end

-- 0 (in place) .. 1 (fully lowered)
function WeaponLowering.amount(now: number): number
	local p = active
	if not p then
		return 0
	end
	local t = now - startedAt
	if t < 0 then
		return 0
	elseif t < p.DownSeconds then
		return smooth(t / p.DownSeconds)
	elseif t < p.HiddenUntil then
		return 1
	elseif t < p.BackBy then
		local u = (t - p.HiddenUntil) / (p.BackBy - p.HiddenUntil)
		if p.ReturnPower then
			return (1 - u) ^ p.ReturnPower -- ease-out: the off-screen part of the way back goes fast
		end
		return 1 - smooth(u)
	end
	active = nil
	return 0
end

function WeaponLowering.offset(now: number): CFrame
	local p = active
	if not p then
		return CFrame.identity
	end
	local a = WeaponLowering.amount(now)
	if a <= 0 then
		return CFrame.identity
	end
	return CFrame.Angles(-math.rad(p.PitchDeg) * a, 0, 0) * CFrame.new(0, -p.DropStuds * a, (p.BackStuds or 0) * a)
end

return WeaponLowering
