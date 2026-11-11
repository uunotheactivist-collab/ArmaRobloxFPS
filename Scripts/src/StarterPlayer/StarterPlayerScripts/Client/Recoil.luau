--!strict
-- Recoil for one weapon (client). Values: Config.Weapons.<Id>.Recoil / .HipFire (measured in
-- ReferenceAnalysis/M4/M4_Firing_Analysis.md).
--   Camera: per-shot pitch climb (moves the aim) with a recovery that is always active (exponential + a constant
--     rate), plus a random per-shot shake (presentation only) that is mostly gone by the next 30 fps frame.
--   Weapon (presentation): per-shot velocity kicks into underdamped springs - position (side, up, back; studs,
--     camera space) and rotation (pitch, yaw, roll; degrees, about the sight) - plus a firing envelope (0..1)
--     that drives sustained offsets (ADS: the sight rides higher; hip: the rifle comes upright).
--   Optional fields (Glock slice; weapons without them behave exactly as before):
--     Camera.ShakePitchRange = { lo, hi }: the per-shot pitch shake is ShakePitchDeg x random(lo, hi) instead of
--       random(-1, 1) (the Glock's view always kicks UP on the shot frame)
--     Weapon.StressedScale: multiplies the weapon kicks while the player is Stressed (the Glock's Stressed hip kicks
--       are ~1.5-2x the Regular ones)
--     Camera.BurstGapS: a shot this long after the previous one is a burst's first shot (default 0.15 s; the Glock's
--       climb fit uses 0.25 s - its semi-automatic strings are 0.163-0.169 s apart, so 0.15 would make every shot "first")
--   Optional field (Sniper slice; absent = the shake jumps at the shot, exactly as before):
--     Camera.ShakeRiseTau: the shake rises before it decays (shake = kick x (exp(-t / ShakeTau) - exp(-t / ShakeRiseTau))
--       / peak, normalised so that ShakePitchDeg / YawDeg / RollDeg stay the VISIBLE peak): the Sniper's view is as high
--       on the frame after the flash as on the flash frame in every shot of its footage
--   Optional field (Glock aimed-shot recoil, 2026-11-10; absent = exactly as before, the old code path is kept as is):
--     Weapon.Aimed = { BackStuds, SideStuds, UpStuds, UpSpringHz, UpSpringDamping, PitchDeg, PitchSpringHz,
--       PitchSpringDamping }: the viewmodel kick of a Regular aimed shot, blended in by the aim (a = aimAlpha; a Stressed
--       shot keeps a = 0, i.e. the old kick). The random Up / Pitch kicks are scaled by (1 - a); Back and Side move to
--       these values (the same random draws, in the same order: Side keeps its random sign); a muzzle-up PitchDeg and an
--       UpStuds lift are kicked into springs of their own. Presentation only: the camera layers and the shot are untouched.

local Recoil = {}
Recoil.__index = Recoil

export type Recoil = typeof(setmetatable(
	{} :: {
		Cam: any,
		Wpn: any,
		Hip: any,
		Rng: Random,
		Climb: number,
		Shake: Vector3,
		ShakeLag: Vector3,
		ShakeNorm: number,
		Pos: Vector3,
		PosVel: Vector3,
		Rot: Vector3,
		RotVel: Vector3,
		Envelope: number,
		LastShotAt: number,
		AUp: number, -- Weapon.Aimed springs (studs / degrees); stay 0 without Weapon.Aimed
		AUpVel: number,
		APitch: number,
		APitchVel: number,
	},
	Recoil
))

-- 1 / the peak of exp(-t / ShakeTau) - exp(-t / ShakeRiseTau); 1 without ShakeRiseTau (the kick is used as it is).
local function riseNorm(c: any): number
	local t1, t2 = c.ShakeTau, c.ShakeRiseTau
	if not t2 then
		return 1
	end
	if math.abs(t1 - t2) < 1e-4 then
		t2 = t1 * 0.99
	end
	local ts = math.log(t1 / t2) * t1 * t2 / (t1 - t2)
	return 1 / (math.exp(-ts / t1) - math.exp(-ts / t2))
end

function Recoil.new(cfg: any, rng: Random?): Recoil
	return setmetatable({
		Cam = cfg.Recoil.Camera,
		Wpn = cfg.Recoil.Weapon,
		Hip = cfg.HipFire,
		Rng = rng or Random.new(),
		Climb = 0,
		Shake = Vector3.zero,
		ShakeLag = Vector3.zero,
		ShakeNorm = riseNorm(cfg.Recoil.Camera),
		Pos = Vector3.zero,
		PosVel = Vector3.zero,
		Rot = Vector3.zero,
		RotVel = Vector3.zero,
		Envelope = 0,
		LastShotAt = -math.huge,
		AUp = 0,
		AUpVel = 0,
		APitch = 0,
		APitchVel = 0,
	}, Recoil)
end

-- Initial velocity that makes an underdamped spring (omega, zeta) peak at `peak`.
local function kickVelocity(peak: number, omega: number, zeta: number): number
	local wd = math.sqrt(1 - zeta * zeta)
	return peak * omega / math.exp(-zeta / wd * math.atan(wd / zeta))
end

function Recoil.Shot(self: Recoil, now: number, aimAlpha: number, stressed: boolean?)
	local c, w, r = self.Cam, self.Wpn, self.Rng
	self.Climb += c.PitchPerShotDeg
	if now - self.LastShotAt > (c.BurstGapS or 0.15) then
		self.Climb += c.FirstShotExtraPitchDeg -- first shot of a burst kicks harder (measured in every burst)
	end
	local pr = c.ShakePitchRange
	local kick = Vector3.new(
		(if pr then r:NextNumber(pr[1], pr[2]) else r:NextNumber(-1, 1)) * c.ShakePitchDeg,
		r:NextNumber(-1, 1) * c.ShakeYawDeg,
		r:NextNumber(-1, 1) * c.ShakeRollDeg
	) * self.ShakeNorm
	self.Shake += kick
	if c.ShakeRiseTau then
		self.ShakeLag += kick -- subtracted, decaying faster: the visible shake starts at 0, rises, then decays
	end
	local omega, zeta = 2 * math.pi * w.SpringHz, w.SpringDamping
	local s = 1 + (w.HipScale - 1) * (1 - aimAlpha)
	if stressed and w.StressedScale then
		s *= w.StressedScale
	end
	local function k(peak: number): number
		return kickVelocity(peak, omega, zeta) * s
	end
	local A = w.Aimed
	if not A then
		self.PosVel += Vector3.new(
			k(r:NextNumber(-1, 1) * w.SideStuds),
			k(r:NextNumber(0.2, 1) * w.UpStuds),
			k(r:NextNumber(0.6, 1) * w.BackStuds)
		)
		self.RotVel += Vector3.new(
			k(r:NextNumber(-1, 1) * w.PitchDeg),
			k(r:NextNumber(-1, 1) * w.YawDeg),
			k(r:NextNumber(-1, 1) * w.RollDeg)
		)
	else
		-- Weapon.Aimed (Glock): a = 0 (hip, Stressed) gives exactly the kicks above (x + (y - x) * 0 = x, x * 1 = x)
		local a = if stressed then 0 else aimAlpha
		local side, up, back = r:NextNumber(-1, 1), r:NextNumber(0.2, 1), r:NextNumber(0.6, 1)
		local sideAimed = if side < 0 then -A.SideStuds else A.SideStuds
		self.PosVel += Vector3.new(
			k(side * w.SideStuds + (sideAimed - side * w.SideStuds) * a),
			k(up * w.UpStuds * (1 - a)),
			k(back * w.BackStuds + (A.BackStuds - back * w.BackStuds) * a)
		)
		self.RotVel += Vector3.new(
			k(r:NextNumber(-1, 1) * w.PitchDeg * (1 - a)),
			k(r:NextNumber(-1, 1) * w.YawDeg),
			k(r:NextNumber(-1, 1) * w.RollDeg)
		)
		if a > 0 then
			self.AUpVel += kickVelocity(A.UpStuds, 2 * math.pi * A.UpSpringHz, A.UpSpringDamping) * a
			self.APitchVel += kickVelocity(A.PitchDeg, 2 * math.pi * A.PitchSpringHz, A.PitchSpringDamping) * a
		end
	end
	self.LastShotAt = now
end

-- Advances recovery, springs and the firing envelope. `interval` = 60 / RPM.
function Recoil.Step(self: Recoil, now: number, dt: number, interval: number)
	local c, w = self.Cam, self.Wpn
	self.Climb = math.max(0, self.Climb * math.exp(-dt / c.RecoveryTau) - c.RecoveryRateDegPerSec * dt)
	self.Shake *= math.exp(-dt / c.ShakeTau)
	if c.ShakeRiseTau then
		self.ShakeLag *= math.exp(-dt / c.ShakeRiseTau)
	end
	local omega, zeta = 2 * math.pi * w.SpringHz, w.SpringDamping
	local n = math.max(1, math.ceil(dt * 240))
	local h = dt / n
	for _ = 1, n do
		self.PosVel += (-omega * omega * self.Pos - 2 * zeta * omega * self.PosVel) * h
		self.Pos += self.PosVel * h
		self.RotVel += (-omega * omega * self.Rot - 2 * zeta * omega * self.RotVel) * h
		self.Rot += self.RotVel * h
	end
	local A = w.Aimed
	if A then -- Weapon.Aimed springs (same integration as above)
		local wu, zu = 2 * math.pi * A.UpSpringHz, A.UpSpringDamping
		local wp, zp = 2 * math.pi * A.PitchSpringHz, A.PitchSpringDamping
		for _ = 1, n do
			self.AUpVel += (-wu * wu * self.AUp - 2 * zu * wu * self.AUpVel) * h
			self.AUp += self.AUpVel * h
			self.APitchVel += (-wp * wp * self.APitch - 2 * zp * wp * self.APitchVel) * h
			self.APitch += self.APitchVel * h
		end
	end
	if now - self.LastShotAt < interval * 1.5 then
		self.Envelope += (1 - self.Envelope) * (1 - math.exp(-dt / (self.Hip.AttackTime / 3)))
	else
		self.Envelope *= math.exp(-dt / self.Hip.ReleaseTau)
	end
end

-- Viewmodel kick: position (studs, camera space) and rotation (deg, about the pivot). Without Weapon.Aimed these are the
-- spring states Pos / Rot themselves.
function Recoil.KickPos(self: Recoil): Vector3
	if self.Wpn.Aimed then
		return self.Pos + Vector3.new(0, self.AUp, 0)
	end
	return self.Pos
end

function Recoil.KickRot(self: Recoil): Vector3
	if self.Wpn.Aimed then
		return self.Rot + Vector3.new(self.APitch, 0, 0)
	end
	return self.Rot
end

-- Camera climb (moves the aim: shots include it).
function Recoil.ClimbOffset(self: Recoil): CFrame
	return CFrame.Angles(math.rad(self.Climb), 0, 0)
end

-- Camera shake (presentation only: shots exclude it).
function Recoil.ShakeOffset(self: Recoil): CFrame
	local s = self.Shake - self.ShakeLag -- ShakeLag stays zero without Camera.ShakeRiseTau
	return CFrame.Angles(math.rad(s.X), math.rad(s.Y), math.rad(s.Z))
end

function Recoil.Reset(self: Recoil)
	self.Climb, self.Shake, self.ShakeLag = 0, Vector3.zero, Vector3.zero
	self.Pos, self.PosVel, self.Rot, self.RotVel = Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero
	self.Envelope, self.LastShotAt = 0, -math.huge
	self.AUp, self.AUpVel, self.APitch, self.APitchVel = 0, 0, 0, 0
end

return Recoil
