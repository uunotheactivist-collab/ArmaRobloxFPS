--!strict
-- Aim for a weapon carrying an optic (Client.Optics): HIP -> AIMING -> SCOPED and back, timed from the optic's own
-- footage (Config.Optics.<Id>.Aim; ReferenceAnalysis/Optics). Same interface as Client.AimController
-- (SetAiming / Reset / Step -> pose, zoom, alpha), so Client.WeaponController treats both alike; the accepted
-- AimController (M4 ADS, AK raised posture) is not used or changed for optic weapons.
--
-- Poses are relative to the weapon's rest (hip idle) pose, as everywhere in the viewmodel rig:
--   HIP    : Aim.HipPose given: the pose that puts the eyepiece where the footage shows it at the hip (screen position
--            and size), level and uncanted; otherwise the rest pose (de-canted when Aim.HipUpright).
--   SCOPED : the eyepiece centred on the camera axis at the measured eye relief, optical axis = camera axis, no
--            cant. So the reticle sits on the screen centre, which is where shots go (camera centre: unchanged).
--   AIMING : moving between the two (either direction).
-- The left arm holds the rifle at every moment: its hand end stays on the handguard grip point (the weapon data's
-- HandGrip point, under the handguard: the footage shows the arm reaching from the lower left to the handguard under
-- the scope), and the arm reaches there from the rest pose's shoulder point (a one-bone reach; the arm is parented to
-- the camera in the rig, so it is recomputed from the weapon pose every frame and cannot come off).
-- Reload clips (borrowed, authored relative to the M4 rest) are moved rigidly with the hip pose (ClipPoses), so
-- the rifle, magazine and arm keep their relation during a reload.
-- Zoom is always 1: picture-in-picture magnification lives in the lens, never in the main camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Easing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Easing"))

local STUD = 0.28
local IDENTITY = CFrame.identity

local OpticAim = {}
OpticAim.__index = OpticAim

export type State = "HIP" | "AIMING" | "SCOPED"
export type OpticAim = typeof(setmetatable(
	{} :: {
		Aim: any,
		C0: CFrame,
		ArmC0: CFrame,
		ArmRel: CFrame,
		ArmLength: number,
		HandOnWeapon: Vector3,
		Shoulder: Vector3,
		HipWorld: CFrame,
		ScopedWorld: CFrame,
		Aiming: boolean,
		S: number,
		From: number,
		T: number,
		ArrivedAt: number?,
		Clock: number,
		State: State,
		Alpha: number,
	},
	OpticAim
))

-- optic: Config.Optics.<Id>; rig: the weapon's ViewmodelRig; pivot: hip-fire pivot point (weapon space, studs).
function OpticAim.new(optic: any, rig: any, pivot: Vector3): OpticAim
	local c0 = rig.Joints.Weapon.C0
	local armC0 = rig.Joints.LeftArm.C0
	local layout = optic.Layout
	-- Hip: optionally remove the rest cant (roll about the bore relative to camera-up) about the pivot.
	local hipPose = IDENTITY
	if optic.Aim.HipUpright then
		local f, up = c0.LookVector, c0.UpVector
		local level = (Vector3.yAxis - f * f:Dot(Vector3.yAxis)).Unit
		local angle = math.atan2(up:Cross(level):Dot(f), up:Dot(level))
		hipPose = CFrame.new(pivot) * CFrame.fromAxisAngle(Vector3.new(0, 0, -1), angle) * CFrame.new(-pivot)
	end
	-- Scoped: the eye point (on the optical axis, EyeRelief behind the eyepiece rim) at the camera origin.
	local eyeY = layout.EyepieceRearY - layout.EyeRelief -- recipe space, metres
	local eye = Vector3.new(0, layout.AxisHeight, -eyeY) / STUD -- weapon bone space, studs (x, z, -y)
	local hipWorld = c0 * hipPose -- weapon relative to the rig root (camera)
	local hp = optic.Aim.HipPose
	if hp and hp.FromRest then
		-- Sniper slice (optional): the weapon's own data was fitted at the measured eyepiece (place, size and the small
		-- fitted rotation), so its rest pose IS the hip pose; clips authored on that rest then need no shift.
		hipWorld = c0
	elseif hp then
		-- Eyepiece rim centre where the footage shows it: screen offset (tan) and depth from its width (a disc facing
		-- the camera plane spans f * D / depth pixels wherever it is on the screen).
		local rim = Vector3.new(0, layout.AxisHeight, -layout.EyepieceRearY) / STUD
		local tx = (hp.EyepieceScreen[1] - 640) / hp.FocalPx
		local ty = (360 - hp.EyepieceScreen[2]) / hp.FocalPx
		local z = layout.EyepieceDiameter * hp.FocalPx / hp.EyepieceWidthPx / STUD
		local p = Vector3.new(tx * z, ty * z, -z)
		hipWorld = CFrame.new(p - rim) -- level: weapon axes = camera axes
	end
	-- Arm: the block hangs from its bone along -Z (ViewmodelRig); its far end is the hand.
	local armPart = rig.Model:FindFirstChild("LeftArm") :: BasePart?
	local armLength = if armPart then armPart.Size.Z else 2.68
	return setmetatable({
		Aim = optic.Aim,
		C0 = c0,
		ArmC0 = armC0,
		ArmRel = c0:Inverse() * armC0, -- the arm in the weapon's frame at rest
		ArmLength = armLength,
		HandOnWeapon = rig.Points.HandGrip or (c0:Inverse() * armC0) * Vector3.new(0, 0, -armLength), -- weapon space
		Shoulder = armC0.Position, -- rest shoulder point, camera space [BORROWED M4]
		HipWorld = hipWorld,
		ScopedWorld = CFrame.new(-eye),
		Aiming = false,
		S = 0,
		From = 0,
		T = 0,
		ArrivedAt = nil,
		Clock = 0,
		State = "HIP" :: State,
		Alpha = 0,
	}, OpticAim)
end

function OpticAim.SetAiming(self: OpticAim, aiming: boolean)
	if aiming == self.Aiming then
		return
	end
	self.Aiming = aiming
	self.From = self.S -- continue from where the weapon is (no pops when reversing mid-way)
	self.T = 0
	self.ArrivedAt = nil
end

function OpticAim.Reset(self: OpticAim)
	self.Aiming = false
	self.S, self.From, self.T = 0, 0, 0
	self.ArrivedAt = nil
	self.State = "HIP"
	self.Alpha = 0
end

-- Arm pose (relative to its rest) holding a weapon placed at `world` (relative to the rig root).
function OpticAim.ArmFor(self: OpticAim, world: CFrame): CFrame
	local hand = world * self.HandOnWeapon
	local dir = hand - self.Shoulder
	if dir.Magnitude < 1e-3 then
		return IDENTITY
	end
	local rear = hand - dir.Unit * self.ArmLength
	return self.ArmC0:Inverse() * CFrame.lookAt(rear, hand, Vector3.yAxis)
end

-- Weapon pose (relative to rest) for progress s in [0, 1] and an extra camera-space offset.
function OpticAim.PoseAt(self: OpticAim, s: number, extra: CFrame?): (CFrame, CFrame)
	local target = (extra or IDENTITY) * self.ScopedWorld
	local world = self.HipWorld:Lerp(target, s)
	local weaponPose = self.C0:Inverse() * world
	return weaponPose, self:ArmFor(world)
end

-- A reload clip frame authored relative to the M4 rest, moved rigidly onto this weapon's hip pose.
function OpticAim.ClipPoses(self: OpticAim, clipWeapon: CFrame, clipArm: CFrame): (CFrame, CFrame)
	local shift = self.HipWorld * self.C0:Inverse() -- maps the authored rest frame onto the optic hip frame
	return self.C0:Inverse() * self.HipWorld * clipWeapon, self.ArmC0:Inverse() * shift * self.ArmC0 * clipArm
end

-- Returns the pose ({ Weapon, LeftArm }), the camera zoom (always 1) and the aim alpha (0 hip .. 1 scoped).
function OpticAim.Step(self: OpticAim, dt: number): ({ Weapon: CFrame, LeftArm: CFrame }, number, number)
	local a = self.Aim
	self.T += dt
	self.Clock += dt
	local t = self.T
	if self.Aiming then
		local span = a.InTime * (1 - self.From)
		local k = if span > 1e-6 then math.clamp(t / span, 0, 1) else 1
		local e = if a.InEase == "Smooth" then Easing.smoothstep(k) else k
		self.S = self.From + (1 - self.From) * e
		if self.S >= 1 and not self.ArrivedAt then
			self.ArrivedAt = self.Clock
		end
	else
		local span = a.OutTime * self.From
		local k = if span > 1e-6 then math.clamp(t / span, 0, 1) else 1
		local e = if a.OutEase == "Accelerate" then k * k else k
		self.S = self.From * (1 - e)
	end
	-- Settle after arriving: the eyepiece comes in slightly low and rises to rest (measured once).
	local settle = IDENTITY
	if self.Aiming and self.ArrivedAt and a.SettleTime > 0 then
		local u = math.clamp((self.Clock - self.ArrivedAt) / a.SettleTime, 0, 1)
		settle = CFrame.new(0, -a.SettleStuds * (1 - Easing.smoothstep(u)), 0)
	elseif self.Aiming and not self.ArrivedAt then
		settle = CFrame.new(0, -a.SettleStuds, 0)
	end
	self.State = if self.S <= 0 then "HIP" elseif self.S >= 1 and self.Aiming then "SCOPED" else "AIMING"
	self.Alpha = self.S
	local weaponPose, armPose = self:PoseAt(self.S, settle)
	return { Weapon = weaponPose, LeftArm = armPose }, 1, self.S
end

return OpticAim
