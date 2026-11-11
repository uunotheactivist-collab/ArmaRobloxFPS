--!strict
-- Manual-action presentation (Sniper slice; client only). Plays the clips measured from the Sniper footage
-- (Shared.Assets.Weapons.SniperAnimations, Blender/Scripts/40_sniper_clips.py; ReferenceAnalysis/Sniper):
--   Cycle : after every shot of a Fire.Action = "Bolt" weapon - the weapon's kick / raised hold / roll for the bolt, the
--           right arm working the bolt and the bolt itself (rig ChargingHandle bone). The hip clip and the scoped clip
--           are blended by the aim alpha and applied ADDITIVELY on the aim pose (Client.WeaponController). The casing
--           leaves at Fire.EjectAt (the bolt's rear stroke).
--   Check : the rounds check (Config.Weapons.<Id>.Check): an absolute clip like a reload clip (relative to the rest pose)
--           with the "5 /5 RDS" panel shown between PanelIn and PanelOut.
-- Presentation only: the bolt's real state (chambered, ready) is the server's (Server.WeaponServer) and the trigger's
-- timing is Client.FireController's (Fire.CycleTime). Cancelling a clip (switch, death, reload) never changes ammunition.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClipPlayer = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Viewmodel"):WaitForChild("ClipPlayer"))

local IDENTITY = CFrame.identity
local CYCLE_JOINTS = { "Weapon", "RightArm", "ChargingHandle" }

local BoltController = {}
BoltController.__index = BoltController

export type BoltController = typeof(setmetatable(
	{} :: {
		Cfg: any,
		Hip: any,
		Scoped: any,
		CheckClip: any?,
		CycleAt: number?,
		Ejected: boolean,
		CheckAt: number?,
		PoseH: { [string]: CFrame },
		PoseS: { [string]: CFrame },
		Out: { [string]: CFrame },
		CheckPose: { [string]: CFrame },
		LastCycleT: number?,
	},
	BoltController
))

-- clips: the compiled clips of the weapon's animation data (Client.ReloadController's Clips).
function BoltController.new(cfg: any, clips: { [string]: any }): BoltController
	return setmetatable({
		Cfg = cfg,
		Hip = clips[cfg.Bolt.HipClip],
		Scoped = clips[cfg.Bolt.ScopedClip],
		CheckClip = if cfg.Check then clips[cfg.Check.Clip] else nil,
		CycleAt = nil,
		Ejected = false,
		CheckAt = nil,
		PoseH = {},
		PoseS = {},
		Out = {},
		CheckPose = {},
		LastCycleT = nil,
	}, BoltController)
end

-- A shot at time t: the cycle clip starts there (and ends any check).
function BoltController.StartCycle(self: BoltController, t: number)
	self.CycleAt = t
	self.Ejected = false
	self.CheckAt = nil
end

function BoltController.StartCheck(self: BoltController, now: number): boolean
	if not self.CheckClip or self.CycleAt or self.CheckAt then
		return false
	end
	self.CheckAt = now
	return true
end

function BoltController.Cancel(self: BoltController)
	self.CycleAt = nil
	self.CheckAt = nil
	self.LastCycleT = nil
end

function BoltController.IsChecking(self: BoltController): boolean
	return self.CheckAt ~= nil
end

-- The cycle clip's transforms for this frame ({ Weapon (additive), RightArm, ChargingHandle }) or nil, and true on the
-- frame the casing leaves.
function BoltController.Cycle(self: BoltController, now: number, aimAlpha: number): ({ [string]: CFrame }?, boolean)
	local at = self.CycleAt
	if not at then
		self.LastCycleT = nil
		return nil, false
	end
	local t = now - at
	if t >= self.Hip.Length then
		self.CycleAt = nil
		self.LastCycleT = nil
		return nil, false
	end
	self.LastCycleT = t
	local eject = false
	if not self.Ejected and t >= self.Cfg.Fire.EjectAt then
		self.Ejected = true
		eject = true
	end
	local h = ClipPlayer.sample(self.Hip, math.max(t, 0), self.PoseH)
	local s = ClipPlayer.sample(self.Scoped, math.max(t, 0), self.PoseS)
	local a = math.clamp(aimAlpha, 0, 1)
	for _, j in CYCLE_JOINTS do
		self.Out[j] = (h[j] or IDENTITY):Lerp(s[j] or IDENTITY, a)
	end
	return self.Out, eject
end

-- The check clip's transforms (absolute, like a reload clip) or nil, its blend weight, and the panel's alpha (0..1).
function BoltController.Check(self: BoltController, now: number): ({ [string]: CFrame }?, number, number)
	local at = self.CheckAt
	local clip = self.CheckClip
	if not at or not clip then
		return nil, 0, 0
	end
	local t = now - at
	if t >= clip.Length then
		self.CheckAt = nil
		return nil, 0, 0
	end
	local c = self.Cfg.Check
	local panel = 0
	if t >= c.PanelIn then
		panel = if t < c.PanelOut then math.clamp((t - c.PanelIn) / c.PanelFade, 0, 1)
			else math.clamp(1 - (t - c.PanelOut) / c.PanelFade, 0, 1)
	end
	ClipPlayer.sample(clip, t, self.CheckPose)
	return self.CheckPose, math.clamp(t / 0.1, 0, 1), panel
end

function BoltController.State(self: BoltController, now: number): any
	return {
		cycling = self.CycleAt ~= nil,
		cycleT = if self.CycleAt then now - self.CycleAt else nil,
		ejected = self.Ejected,
		checking = self.CheckAt ~= nil,
		checkT = if self.CheckAt then now - self.CheckAt else nil,
	}
end

return BoltController
