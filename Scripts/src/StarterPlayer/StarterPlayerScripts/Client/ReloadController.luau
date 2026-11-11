--!strict
-- Client side of a reload: picks the clip measured for the situation, plays it immediately (no round trip), and
-- predicts the ammunition change at the same moment the server commits it. The server (Server.WeaponServer) makes
-- the same decision from its own state and timing and is authoritative; WeaponState corrections win.
--   Tactical (a round chambered) vs Empty (bolt locked back), each in a Regular and a Stressed version - four clips
--   measured separately from the reference (Config.Weapons.<Id>.Reloads, ReferenceAnalysis/M4/M4_Reload_Analysis.md).
--   While reloading: no firing, no aiming (the footage only shows reloads from the hip).
--   Ammunition steps: Shared.Weapon.Ammo.swapMagazine at SwapAt (old magazine kept or dropped by the spec's DropOld),
--   Ammo.chamber at ChamberAt (empty reloads).
--   Audio (M4 audio fidelity slice): an optional Client.WeaponAudio starts the clip's sound with the clip and stops
--   it on Cancel (server correction, weapon switch, death, respawn); without one nothing changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ammo = require(Shared:WaitForChild("Weapon"):WaitForChild("Ammo"))
local ClipPlayer = require(Shared:WaitForChild("Viewmodel"):WaitForChild("ClipPlayer"))

local BLEND_IN = 0.1 -- s: from whatever pose the weapon was in (e.g. leaving ADS) into the clip's first frame

local ReloadController = {}
ReloadController.__index = ReloadController

export type Active = { Spec: any, Clip: any, StartedAt: number, Swapped: boolean, Chambered: boolean, Marked: boolean }
export type ReloadController = typeof(setmetatable(
	{} :: { Cfg: any, Clips: { [string]: any }, Active: Active?, Pose: { [string]: CFrame }, LastFinished: string?,
		Audio: any? },
	ReloadController
))

function ReloadController.new(cfg: any, animationData: any, audio: any?): ReloadController
	return setmetatable({
		Cfg = cfg,
		Clips = ClipPlayer.compile(animationData),
		Active = nil,
		Pose = {},
		LastFinished = nil,
		Audio = audio,
	}, ReloadController)
end

-- Starts a reload if the predicted ammunition allows it. Returns the spec name or nil and a reason.
function ReloadController.Start(self: ReloadController, ammo: Ammo.State, stressed: boolean, now: number): (string?, string?)
	if self.Active then
		return nil, "Busy"
	end
	local kind, why = Ammo.reloadKind(ammo, self.Cfg.Fire)
	if not kind then
		return nil, why
	end
	local specName = kind .. (if stressed then "Stressed" else "Regular")
	local spec = self.Cfg.Reloads[specName]
	self.Active = { Spec = spec, Clip = self.Clips[spec.Clip], StartedAt = now, Swapped = false, Chambered = false,
		Marked = spec.HudMarkAt == nil }
	if self.Audio then
		self.Audio:ReloadStart(spec.Clip)
	end
	return specName, nil
end

function ReloadController.Cancel(self: ReloadController)
	if self.Active and self.Audio then
		self.Audio:ReloadStop()
	end
	self.Active = nil
end

function ReloadController.IsActive(self: ReloadController): boolean
	return self.Active ~= nil
end

-- Advances the reload. Returns the joint transforms of the clip (or nil when idle) and the blend weight.
-- Predicts the server's ammunition steps at the same clip times: the magazine swap at SwapAt and, for empty
-- reloads, the chambering at ChamberAt (the server's WeaponState marks them done so they never apply twice).
-- Finishes after Duration.
function ReloadController.Step(self: ReloadController, now: number, ammo: Ammo.State): ({ [string]: CFrame }?, number)
	local a = self.Active
	if not a then
		return nil, 0
	end
	local t = now - a.StartedAt
	local spec = a.Spec
	if not a.Swapped and t >= spec.SwapAt then
		Ammo.swapMagazine(ammo, spec.DropOld)
		a.Swapped = true
	end
	if spec.ChamberAt and a.Swapped and not a.Chambered and t >= spec.ChamberAt then
		Ammo.chamber(ammo)
		a.Chambered = true
	end
	if not a.Marked and t >= spec.HudMarkAt then
		Ammo.mark(ammo)
		a.Marked = true
	end
	if t >= a.Spec.Duration then
		self.LastFinished = a.Spec.Clip
		self.Active = nil
		return nil, 0
	end
	ClipPlayer.sample(a.Clip, t, self.Pose)
	return self.Pose, math.clamp(t / BLEND_IN, 0, 1)
end

function ReloadController.Elapsed(self: ReloadController, now: number): number?
	return if self.Active then now - self.Active.StartedAt else nil
end

return ReloadController
