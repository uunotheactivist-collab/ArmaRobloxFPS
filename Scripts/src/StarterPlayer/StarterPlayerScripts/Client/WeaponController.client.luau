--!strict
-- Production weapon presentation + input (client). One instance per production weapon; every value comes from that
-- weapon's own footage analysis (Shared.Config.Weapons.<Id>, ReferenceAnalysis/<Id>), the systems are shared:
--   viewmodel rig (Shared.Viewmodel), aim (AimController: M4 = ADS with the measured path and 1.16 zoom; AK = the
--   raised posture its footage shows, zoom 1.0), Regular/Stressed sway, fire cadence with predicted ammunition
--   (FireController; the server is authoritative: Server.WeaponServer), recoil (camera climb/recovery/shake +
--   viewmodel kicks, hip de-cant where the footage shows it), muzzle flash/light/brass, the holographic reticle
--   (weapons that have one), reloads (ReloadController + ClipPlayer clips measured per weapon), HUD (Client.Hud).
-- Presentation never waits for the server; the server validates every shot and reload and corrects ammunition.
--
-- Optics slice: a weapon whose config names an Optic (Config.Optics.<Id>; the scoped test rifle ScopeTest) aims
-- with Client.Optics.OpticAim (HIP -> AIMING -> SCOPED) instead of AimController, and its Client.Optics.Optic
-- (housing, lens picture-in-picture, reticle) is updated right after the rig. M4 and AK paths are unchanged.
-- MP7 slice: the MP7 is one more entry in PRODUCTION (Config.Weapons.MP7, ReferenceAnalysis/MP7) on the same path;
-- its ADS posture is a PLACEHOLDER (the footage never aims), its muzzle config adds the streak / sparks / smoke layers.
-- Glock slice: the Glock (Config.Weapons.Glock, ReferenceAnalysis/Glock) on the same path, semi-automatic. Its slide is
-- the rig's ChargingHandle bone, driven by an optional Slide layer (cfg.Slide): it cycles back after each shot and stays
-- LOCKED back whenever no round is chambered - derived from the (server-corrected) ammunition, never set directly.
-- Sniper slice: the bolt-action Sniper (Config.Weapons.Sniper + Config.Optics.SniperScope, ReferenceAnalysis/Sniper) on
-- the same path and the accepted optics framework. Bolt weapons (cfg.Bolt) get a Client.BoltController: after every
-- shot the measured cycle clip plays ADDITIVELY on the aim pose (kick, roll, right arm, bolt; the left arm is re-reached
-- to the forend) and the casing leaves at the bolt's rear stroke; the rounds check (cfg.Check) plays like a reload clip
-- and shows the "5 /5 RDS" panel (Client.Hud.RoundsPanel). Optics with a Zoom step their level with the mouse wheel /
-- D-pad up while aiming [PLACEHOLDER input] and show the zoom label (Client.Hud.ZoomLabel). The bolt's state is the
-- server's; the trigger waits for Fire.CycleTime (FireController).
--
-- M4 audio fidelity slice: Client.WeaponAudio per weapon (sound only where Shared.Config.Audio.<Id> exists - the M4;
-- inert for every other weapon): a sound per predicted shot, the reload clip's sound (via ReloadController), all of it
-- stopped when the weapon is put down (switch / death / respawn). Presentation only, like the muzzle effects.
-- Correction pass: WeaponAudio gets the fire interval (burst continuity) and each shot's Stressed state (sound set).
--
-- Keys: 1 = test blaster, 2 = M4 (default), 3 = AK, 4 = scoped test rifle, 5 = MP7, 6 = Glock, 7 = Sniper, left mouse /
--       R2 = fire, right mouse / L2 = aim (hold), R / X = reload, T = toggle Stressed (Studio dev toggle, set on the
--       server), mouse wheel / D-pad up = scope zoom (Sniper), V = rounds check (Sniper) [PLACEHOLDER keys].

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponRegistry = require(Shared:WaitForChild("WeaponRegistry"))
local ViewmodelRig = require(Shared:WaitForChild("Viewmodel"):WaitForChild("ViewmodelRig"))
local ClipPlayer = require(Shared:WaitForChild("Viewmodel"):WaitForChild("ClipPlayer"))
local Ammo = require(Shared:WaitForChild("Weapon"):WaitForChild("Ammo"))
local Remotes = Shared:WaitForChild("Remotes")
local WeaponFire = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
local WeaponCommand = Remotes:WaitForChild("WeaponCommand") :: RemoteEvent
local WeaponState = Remotes:WaitForChild("WeaponState") :: RemoteEvent
local AimController = require(script.Parent:WaitForChild("AimController"))
local AimHold = require(script.Parent:WaitForChild("AimHold")) -- Glock aim-hold drift (only with ADS.HoldDrift)
local Sway = require(script.Parent:WaitForChild("Sway"))
local FireController = require(script.Parent:WaitForChild("FireController"))
local Recoil = require(script.Parent:WaitForChild("Recoil"))
local MuzzleEffects = require(script.Parent:WaitForChild("MuzzleEffects"))
local HoloReticle = require(script.Parent:WaitForChild("HoloReticle"))
local ReloadController = require(script.Parent:WaitForChild("ReloadController"))
local WeaponAudio = require(script.Parent:WaitForChild("WeaponAudio"))
local BoltController = require(script.Parent:WaitForChild("BoltController"))
local WeaponHud = require(script.Parent:WaitForChild("Hud"):WaitForChild("WeaponHud"))
-- Movement presentation (look lag + walk bob): one rotation of the whole rig in front of the weapon's own layers;
-- the identity when the player is still and not turning (Client.Movement, ReferenceAnalysis/Movement).
local MovementPresentation = require(script.Parent:WaitForChild("Movement"):WaitForChild("MovementPresentation"))
-- first-person fidelity pass: a timed lowering of the whole viewmodel (the grenade throw); identity when idle
local WeaponLowering = require(script.Parent:WaitForChild("FirstPerson"):WaitForChild("WeaponLowering"))
local SeatView = require(script.Parent:WaitForChild("Vehicles"):WaitForChild("SeatView"))
local OpticsFolder = script.Parent:WaitForChild("Optics")
local OpticAim = require(OpticsFolder:WaitForChild("OpticAim"))
local Optic = require(OpticsFolder:WaitForChild("Optic"))
local OpticsConfig = Shared:WaitForChild("Config"):WaitForChild("Optics")

local player = Players.LocalPlayer
local PRODUCTION = { "M4", "AK", "ScopeTest", "MP7", "Glock", "Sniper" }
local EQUIP_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "TestBlaster",
	[Enum.KeyCode.Two] = "M4",
	[Enum.KeyCode.Three] = "AK",
	[Enum.KeyCode.Four] = "ScopeTest",
	[Enum.KeyCode.Five] = "MP7",
	[Enum.KeyCode.Six] = "Glock",
	[Enum.KeyCode.Seven] = "Sniper",
}
local IDENTITY = CFrame.identity
local Assets = Shared:WaitForChild("Assets"):WaitForChild("Weapons")

type Weapon = {
	Id: string,
	Cfg: any,
	Rig: any,
	Aim: any,
	Sway: any,
	Fire: any,
	Recoil: any,
	Effects: any,
	Reload: any,
	Hud: any,
	Reticle: BasePart?,
	SightGlass: Vector3,
	Muzzle: Vector3,
	Eject: Vector3,
	Pivot: Vector3,
	HipDecant: CFrame,
	HipFov: number,
	TanHalfHip: number,
	Active: boolean,
	ServerState: any,
	Optic: any?,
	AimHold: any?,
	Bolt: any?,
	Audio: any,
}

local function makeWeapon(id: string): Weapon
	local cfg = WeaponRegistry.get(id)
	local data = require(Assets:WaitForChild(cfg.Viewmodel.Data)) :: any
	local rigData = data
	if cfg.Viewmodel.OmitParts then -- e.g. a borrowed body without its own sight (the shared data is not changed)
		rigData = table.clone(data)
		rigData.Parts = {}
		for _, spec in data.Parts do
			if not table.find(cfg.Viewmodel.OmitParts, spec.Name) then
				table.insert(rigData.Parts, spec)
			end
		end
	end
	local rig = ViewmodelRig.new(rigData, id .. "Viewmodel")
	local opticDef = if cfg.Optic then require(OpticsConfig:WaitForChild(cfg.Optic)) :: any else nil
	local reloadData = require(Assets:WaitForChild(cfg.Viewmodel.ReloadAnimations)) :: any
	local pivot = rig.Points[cfg.HipFire.Pivot]
	-- Hip-fire posture: remove the idle cant (roll about the bore relative to camera-up) about the pivot, by the
	-- fraction the footage shows (M4 1.0; AK 0 - its hip bursts stay canted).
	local hipDecant = IDENTITY
	if cfg.HipFire.Upright ~= 0 then
		local c0 = rig.Joints.Weapon.C0
		local f, up = c0.LookVector, c0.UpVector
		local level = (Vector3.yAxis - f * f:Dot(Vector3.yAxis)).Unit
		local angle = math.atan2(up:Cross(level):Dot(f), up:Dot(level)) * cfg.HipFire.Upright
		hipDecant = CFrame.new(pivot) * CFrame.fromAxisAngle(Vector3.new(0, 0, -1), angle) * CFrame.new(-pivot)
	end
	local reticle = if cfg.Viewmodel.HoloReticle == false then nil else rig.Model:FindFirstChild("Weapon_Reticle")
	local audio = WeaponAudio.new(id, 60 / cfg.Fire.RPM) -- inert unless Shared.Config.Audio.<id> exists (M4 audio)
	local reload = ReloadController.new(cfg, reloadData, if audio:HasAudio() then audio else nil)
	return {
		Id = id,
		Cfg = cfg,
		Rig = rig,
		-- M4: ADS; AK: Raised (no zoom, no sight picture); optic weapons: HIP -> AIMING -> SCOPED (Client.Optics)
		Aim = if opticDef then OpticAim.new(opticDef, rig, pivot) else AimController.new(cfg.ADS or cfg.Raised, data),
		Sway = Sway.new(cfg.Sway),
		Fire = FireController.new(cfg.Fire),
		Recoil = Recoil.new(cfg),
		Effects = MuzzleEffects.new(cfg),
		Reload = reload,
		Hud = WeaponHud.new(cfg), -- presentation only: fed a read-only view of Fire.Ammo every frame
		Reticle = reticle :: BasePart?,
		SightGlass = rig.Points.SightGlass,
		Muzzle = rig.Points.Muzzle,
		Eject = rig.Points.Ejection,
		Pivot = pivot,
		HipDecant = hipDecant,
		HipFov = cfg.Viewmodel.HipFieldOfView,
		TanHalfHip = math.tan(math.rad(cfg.Viewmodel.HipFieldOfView) / 2),
		Active = false,
		ServerState = nil,
		Optic = if opticDef then Optic.new(opticDef, rig, data, id) else nil,
		AimHold = if cfg.ADS and cfg.ADS.HoldDrift then AimHold.new(cfg.ADS.HoldDrift) else nil, -- Glock: aim-hold drift
		Bolt = if cfg.Bolt then BoltController.new(cfg, reload.Clips) else nil, -- Sniper slice (bolt action)
		Audio = audio,
	}
end

local weapons: { [string]: Weapon } = {}
for _, id in PRODUCTION do
	weapons[id] = makeWeapon(id)
end
local lastWeapon: Weapon = weapons.M4 -- the weapon the debug hook reports on when none is equipped

local aimHeld = false
local triggerHeld = false
local cameraOffset: CFrame? = nil -- presentation offsets applied to the camera last frame
local fovOwned = false

-- Studio-only instrumentation for the focused tests (Tests/M4_*, Tests/AK).
local debugLog: { any }? = nil
local debugFreeze: { clip: string, t: number, panel: number? }? = nil -- Studio test hook: hold a reload clip at a time
local debugBolt: number? = nil -- Studio test hook (Sniper slice): hold the bolt cycle clip at a time (screenshots)
local debugKick: { slide: number }? = nil -- Studio test hook (Glock aimed recoil): hold the recoil and slide (screenshots)
local debugAimed: any = nil -- Studio test hook (Glock aimed recoil): Recoil.Weapon.Aimed while switched off for a BEFORE capture
local debugShots: { number } = {}

if player:GetAttribute("EquippedWeapon") == nil then
	player:SetAttribute("EquippedWeapon", "M4")
end

local function equipped(): Weapon?
	return weapons[player:GetAttribute("EquippedWeapon") :: any]
end

-- Slide layer (weapons with cfg.Slide, the Glock): travel back along the bore (studs, +Z in the weapon frame) as a
-- fraction of the lock-back travel. Locked back whenever no round is chambered (after the last shot, and through an
-- empty reload until its ChamberAt = the slide release); otherwise one cycle after each shot: fully back for HoldTime,
-- then forward over ReturnTime.
local function slideFraction(w: Weapon, now: number): number
	local sc = w.Cfg.Slide
	if not w.Fire.Ammo.Chambered then
		return 1
	end
	local dt = now - w.Fire.LastShotAt
	if dt < 0 or dt >= sc.HoldTime + sc.ReturnTime then
		return 0
	elseif dt < sc.HoldTime then
		return sc.CycleFraction
	end
	return sc.CycleFraction * (1 - (dt - sc.HoldTime) / sc.ReturnTime)
end

local function isAlive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- truck slice: stowed in the driver seat (no rifle, no fire / aim / reload [CONFIRMED]) and down in a bench seat
	-- until FIRE / AIM / RELOAD raises it (Client.Vehicles.SeatView)
	return humanoid ~= nil and humanoid.Health > 0 and not SeatView.weaponsStowed()
end

local function syncEquip()
	WeaponCommand:FireServer("Equip", player:GetAttribute("EquippedWeapon"))
end
player:GetAttributeChangedSignal("EquippedWeapon"):Connect(syncEquip)
syncEquip()

WeaponState.OnClientEvent:Connect(function(state: any)
	if typeof(state) ~= "table" then
		return
	end
	local w = weapons[state.Weapon]
	if not w then
		return
	end
	w.Fire:SetAmmo(state.Mag, state.Chambered, state.Reserve, state.Dropped, state.LabelMarks)
	local reason = tostring(state.Reason)
	local a = w.Reload.Active
	if reason == "ReloadSwapped" and a then
		a.Swapped = true -- the server's magazine change is in; don't apply it twice
	elseif reason == "ReloadChambered" and a then
		a.Swapped, a.Chambered = true, true
	elseif reason == "ReloadMarked" and a then
		a.Marked = true
	elseif reason == "ReloadCancelled" or string.sub(reason, 1, 13) == "ReloadRefused" then
		w.Reload:Cancel() -- the server disagreed with the prediction
	end
	w.ServerState = state
end)

player.CharacterAdded:Connect(function()
	WeaponLowering.reset()
	for _, w in weapons do
		w.Fire:Refill() -- the server sends the authoritative state too ("Respawn")
		w.Recoil:Reset()
		w.Reload:Cancel()
		w.Audio:Stop()
		if w.Bolt then
			w.Bolt:Cancel()
		end
	end
end)

local function requestReload(): string?
	local w = equipped()
	if not (w and isAlive()) then
		return "NotReady"
	end
	if w.Bolt then
		if os.clock() < w.Fire.NextShotAt then
			return "Cycling" -- the bolt is still being worked (the server refuses it too)
		end
		w.Bolt:Cancel() -- a reload ends a rounds check
	end
	local spec, why = w.Reload:Start(w.Fire.Ammo, player:GetAttribute("Stressed") == true, os.clock())
	if spec then
		triggerHeld, aimHeld = false, false
		WeaponCommand:FireServer("Reload")
	end
	return spec or why
end

local function onAim(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if not equipped() then
		aimHeld = false
		return Enum.ContextActionResult.Pass
	end
	aimHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("ProductionAim", onAim, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)

local function onFire(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if not equipped() then
		triggerHeld = false
		return Enum.ContextActionResult.Pass
	end
	triggerHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("ProductionFire", onFire, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

-- Rounds check (weapons with cfg.Check, the Sniper): from the hip, not while reloading or while the bolt cycles.
local function requestCheck(): string
	local w = equipped()
	if not (w and w.Bolt and w.Cfg.Check and isAlive()) then
		return "NotReady"
	end
	if w.Reload:IsActive() then
		return "Reloading"
	end
	if os.clock() < w.Fire.NextShotAt then
		return "Cycling"
	end
	aimHeld, triggerHeld = false, false
	return if w.Bolt:StartCheck(os.clock()) then "Started" else "Busy"
end

-- Scope zoom (optics with def.Zoom, the Sniper's scope): one level per wheel notch / D-pad press while aiming.
local function stepZoom(dir: number): number?
	local w = equipped()
	if not (w and w.Optic and w.Optic.Def.Zoom and isAlive()) or (w.Aim :: any).State == "HIP" then
		return nil
	end
	local level = w.Optic:StepZoom(dir, os.clock())
	if level then
		w.Hud:ShowZoom(string.format(w.Optic.Def.Zoom.LabelFormat, level))
	end
	return level
end

local function onZoom(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local dir = 0
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		dir = if input.Position.Z > 0 then 1 elseif input.Position.Z < 0 then -1 else 0
	elseif state == Enum.UserInputState.Begin then
		dir = 1
	end
	if dir ~= 0 and stepZoom(dir) then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end
ContextActionService:BindAction("ProductionZoom", onZoom, false, Enum.UserInputType.MouseWheel, Enum.KeyCode.DPadUp)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local equipId = EQUIP_KEYS[input.KeyCode]
	local current = equipped()
	if equipId then
		player:SetAttribute("EquippedWeapon", equipId)
	elseif current and current.Cfg.Check and input.KeyCode == current.Cfg.Check.Key then
		requestCheck()
	elseif input.KeyCode == Enum.KeyCode.T and RunService:IsStudio() then
		WeaponCommand:FireServer("DevSetStressed", not player:GetAttribute("Stressed")) -- dev toggle, server-owned
	elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
		requestReload()
	end
end)

-- Put a weapon down cleanly (switch / death): ammunition is kept (the server owns it), presentation is reset.
local function deactivate(w: Weapon)
	if not w.Active then
		return
	end
	w.Active = false
	aimHeld, triggerHeld = false, false
	w.Fire:SetTrigger(false, os.clock())
	w.Reload:Cancel() -- weapon switch / death cancels the reload (the server cancels it too)
	w.Audio:Stop() -- M4 audio fidelity slice: no sound of a put-down weapon keeps playing
	w.Aim:Reset()
	if w.AimHold then
		w.AimHold:Reset()
	end
	w.Recoil:Reset()
	w.Effects:Clear()
	if w.Bolt then
		w.Bolt:Cancel() -- presentation only: the server's cycle (and the trigger's wait) carry on
	end
	if w.Optic then
		w.Optic:SetActive(false) -- lens layer off, scene copy stops following
	end
	w.Rig.Model.Parent = nil
	w.Effects.Folder.Parent = nil
end

-- Remove last frame's camera offsets before the camera scripts run, so they never build on them.
RunService:BindToRenderStep("ProductionCameraRestore", Enum.RenderPriority.Camera.Value - 1, function()
	if cameraOffset then
		local camera = workspace.CurrentCamera
		camera.CFrame = camera.CFrame * cameraOffset:Inverse()
		cameraOffset = nil
	end
end)

RunService:BindToRenderStep("ProductionViewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
	local camera = workspace.CurrentCamera
	local now = os.clock()
	local alive = isAlive()
	local w = equipped()
	for _, other in weapons do
		if other ~= w or not alive then
			deactivate(other)
			other.Hud:Update({ visible = false, dropped = Ammo.labelCount(other.Fire.Ammo) }) -- nothing left on screen
		end
	end
	if not (w and alive) then
		if fovOwned then
			camera.FieldOfView = lastWeapon.HipFov
			fovOwned = false
		end
		return
	end
	w.Active = true
	lastWeapon = w
	local cfg = w.Cfg
	local rig = w.Rig
	if w.Optic then
		w.Optic:SetActive(true)
	end

	local reloading = w.Reload:IsActive()
	local checking = w.Bolt ~= nil and w.Bolt:IsChecking() -- Sniper slice: the rounds check holds the aim and trigger
	w.Aim:SetAiming(aimHeld and not reloading and not checking)
	w.Fire:SetTrigger(triggerHeld and not reloading and not checking, now)
	local pose, zoom, aimAlpha = w.Aim:Step(dt)
	local camSway, weaponSway = w.Sway:Step(dt, player:GetAttribute("Stressed") == true, aimAlpha)
	if not debugKick then
		w.Recoil:Step(now, dt, w.Fire.Interval)
	end
	local clip, clipW = w.Reload:Step(now, w.Fire.Ammo)
	local panelAlpha = 0
	if not clip and w.Bolt then
		local checkPose, checkW, pa = w.Bolt:Check(now) -- the rounds check plays like a reload clip
		if checkPose then
			clip, clipW, panelAlpha = checkPose, checkW, pa
		end
	end
	if debugFreeze and w.Reload.Clips[debugFreeze.clip] then
		clip, clipW = ClipPlayer.sample(w.Reload.Clips[debugFreeze.clip], debugFreeze.t), 1
		if debugFreeze.panel then
			panelAlpha = debugFreeze.panel
		end
	end

	local shake = w.Recoil:ShakeOffset()
	local clipCamera = if clip and clip.Camera then IDENTITY:Lerp(clip.Camera, clipW) else IDENTITY
	local offset = camSway * w.Recoil:ClimbOffset() * shake * clipCamera
	camera.CFrame = camera.CFrame * offset
	cameraOffset = offset
	camera.FieldOfView = math.deg(2 * math.atan(w.TanHalfHip / zoom))
	fovOwned = true

	-- Shots due this frame go where the camera points with sway and recoil climb (not the transient shake).
	local shots = w.Fire:Step(now)
	local shotCF = camera.CFrame * shake:Inverse()
	for _, t in shots do
		WeaponFire:FireServer(w.Id, shotCF.Position, shotCF.LookVector)
		w.Recoil:Shot(t, aimAlpha, player:GetAttribute("Stressed") == true)
		w.Audio:Shot(t, player:GetAttribute("Stressed") == true, aimAlpha) -- M4 audio (inert for weapons without audio); the aim blend (Glock correction: aimed shots centred)
		if w.Bolt then
			w.Bolt:StartCycle(t) -- Sniper slice: the bolt is worked after every shot
		end
		if debugLog then
			table.insert(debugShots, t)
		end
	end

	-- Viewmodel: aim pose, hip-fire de-cant, spring kicks (rotation about the pivot, translation in camera space).
	local env = w.Recoil.Envelope
	local rot = w.Recoil:KickRot() -- = Recoil.Rot unless the config has Recoil.Weapon.Aimed (Glock aimed shots)
	local kickRot = CFrame.new(w.Pivot)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		* CFrame.new(-w.Pivot)
	local weaponPose = pose.Weapon * IDENTITY:Lerp(w.HipDecant, env * (1 - aimAlpha)) * kickRot
	local armPose, magPose, chPose = pose.LeftArm, IDENTITY, IDENTITY
	local rightArmPose: CFrame? = nil
	local eject = false
	if w.Bolt then
		-- Sniper slice: the measured bolt cycle, additive on the aim pose (hip / scoped clips blended by the aim)
		if debugBolt then
			w.Bolt.CycleAt = now - debugBolt
			w.Bolt.Ejected = true
		end
		local cycle, ej = w.Bolt:Cycle(now, aimAlpha)
		eject = ej
		if cycle and not clip then
			weaponPose = weaponPose * cycle.Weapon
			if w.Optic then -- the left hand stays on the forend while the rifle rolls
				armPose = (w.Aim :: any):ArmFor(rig.Joints.Weapon.C0 * weaponPose)
			end
			chPose = cycle.ChargingHandle
			rightArmPose = cycle.RightArm
		end
	end
	if clip then
		-- Reload clip (measured from the reference) drives every joint; blend in from the current pose.
		local clipWeapon, clipArm = clip.Weapon, clip.LeftArm
		if w.Optic then -- borrowed clips, moved rigidly onto the optic weapon's own hip pose (Client.Optics.OpticAim)
			clipWeapon, clipArm = (w.Aim :: any):ClipPoses(clipWeapon, clipArm)
		end
		weaponPose = weaponPose:Lerp(clipWeapon, clipW)
		armPose = armPose:Lerp(clipArm, clipW)
		magPose, chPose = clip.Magazine, clip.ChargingHandle
	end
	local slide = 0
	if cfg.Slide then
		slide = if debugKick then debugKick.slide else slideFraction(w, now)
		chPose = chPose * CFrame.new(0, 0, cfg.Slide.LockTravelStuds * slide)
	end
	local kickPos = w.Recoil:KickPos() + Vector3.new(0, cfg.Recoil.Weapon.FiringUpStuds * env * aimAlpha, 0)
	if rig.Model.Parent ~= camera then
		rig.Model.Parent = camera
		w.Effects.Folder.Parent = camera
	end
	local root = camera.CFrame * MovementPresentation.viewmodelOffset(aimAlpha) * WeaponLowering.offset(now) * weaponSway * CFrame.new(kickPos)
	local hold = if w.AimHold then w.AimHold:Step((w.Aim :: any).Aiming, (w.Aim :: any).T, aimAlpha) else nil
	if hold then -- Glock aim-hold drift: the whole viewmodel, after every other offset (no other weapon has one)
		root = root * hold
	end
	rig:Update(
		root,
		{ Weapon = weaponPose, LeftArm = armPose, Magazine = magPose, ChargingHandle = chPose,
			-- Glock slice: a clip may drive the weapon-parented right arm (the hand stays on the grip while the pistol turns)
			-- Sniper slice: so does the bolt cycle (the right hand works the bolt)
			RightArm = if clip and clip.RightArm then IDENTITY:Lerp(clip.RightArm, clipW) else rightArmPose }
	)
	if w.Reticle then
		HoloReticle.Update(rig, w.Reticle, w.SightGlass, camera.CFrame.Position, cfg.Viewmodel.ReticleWindow, cfg.Viewmodel.ReticlePitch)
	end
	if w.Optic then
		-- reads the final camera and rig of this frame; writes only the optic's own lens layer
		w.Optic:Update(camera, aimAlpha, (w.Aim :: any).State or "")
	end

	if #shots > 0 then
		local weaponCF = rig.World.Weapon
		w.Effects:Shot(now, weaponCF * CFrame.new(w.Muzzle), weaponCF * CFrame.new(w.Eject), camera.CFrame)
	end
	if eject then -- Sniper slice: the casing leaves at the bolt's rear stroke (Muzzle.Brass.AtCycle)
		w.Effects:Eject(now, rig.World.Weapon * CFrame.new(w.Eject))
	end
	w.Effects:Step(now, dt)

	-- HUD (after the rig, so the Sniper's rounds panel can ride on the weapon's projected anchor point)
	local panelView = nil
	local panelCfg = cfg.Hud and cfg.Hud.RoundsPanel
	if panelCfg then
		local sp, onScreen = camera:WorldToViewportPoint(rig.World.Weapon * rig.Points[panelCfg.Anchor])
		panelView = {
			alpha = panelAlpha,
			rounds = w.Fire.Ammo.Mag + (if panelCfg.CountsChamber and w.Fire.Ammo.Chambered then 1 else 0),
			capacity = cfg.Fire.MagazineSize,
			anchor = if onScreen then Vector2.new(sp.X, sp.Y) else nil,
			viewport = camera.ViewportSize,
		}
	end
	w.Hud:Update({ visible = true, dropped = Ammo.labelCount(w.Fire.Ammo), panel = panelView })

	if debugLog then
		table.insert(debugLog, {
			t = now,
			weaponId = w.Id,
			climb = w.Recoil.Climb,
			shake = w.Recoil.Shake - w.Recoil.ShakeLag, -- the visible shake (ShakeLag is zero without ShakeRiseTau)
			camSway = camSway,
			env = env,
			aim = aimAlpha,
			shots = #shots,
			weapon = rig.World.Weapon, -- weapon CFrame (the M4 tests read it under this key)
			camera = camera.CFrame,
			fov = camera.FieldOfView,
			reticleVisible = if w.Reticle then w.Reticle.Transparency < 0.5 else false,
			reticle = if w.Reticle then w.Reticle.Position else nil,
			reloadT = w.Reload:Elapsed(now),
			magazine = rig.World.Magazine,
			arm = rig.World.LeftArm,
			rightArm = rig.World.RightArm,
			chargingHandle = rig.World.ChargingHandle,
			slide = slide, -- Glock slice: slide travel fraction (1 = locked back)
			aimHold = if w.AimHold then { w.AimHold.Pitch, w.AimHold.Drop } else nil, -- Glock aim-hold drift (deg, studs)
			lower = WeaponLowering.amount(now), -- first-person fidelity pass: 0 in place … 1 out of view
			muzzle = (rig.World.Weapon * CFrame.new(w.Muzzle)).Position,
			dropped = Ammo.labelCount(w.Fire.Ammo),
			hudText = if w.Hud.Label then w.Hud.Label.Text else nil,
			boltT = if w.Bolt then w.Bolt.LastCycleT else nil, -- Sniper slice: time into the bolt cycle clip
			eject = eject,
			panelAlpha = panelAlpha,
			zoomLevel = if w.Optic then w.Optic:ZoomLevel() else nil,
			magnification = if w.Optic and w.Optic.Live then w.Optic.Last.Magnification else nil,
			reticleScale = if w.Optic then w.Optic.ReticleScale else nil,
			chamberedPredicted = w.Fire.Ammo.Chambered,
			opticState = if w.Optic then w.Optic.Last.State else nil,
			opticLive = if w.Optic then w.Optic.Live else nil,
			lensCF = if w.Optic then w.Optic.Last.LensCF else nil,
			scopeCF = if w.Optic and w.Optic.Live then w.Optic.Last.ScopeCF else nil,
			scopeFov = if w.Optic and w.Optic.Live then w.Optic.Last.ScopeFov else nil,
			shadow = if w.Optic and w.Optic.Live then w.Optic.Last.Shadow else nil,
			opticMs = if w.Optic then w.Optic.Last.UpdateMs else nil,
			mirrorMs = if w.Optic and w.Optic.Live and w.Optic.Mirror then w.Optic.Mirror.Stats.LastSyncMs else nil,
		})
	end
end)

-- Studio-only debug hook used by the focused tests (never created in a live game). Commands act on the equipped
-- production weapon, or on the last one used when another weapon is out.
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "ProductionWeaponDebug"
	hook.OnInvoke = function(cmd: string, arg: any): any
		local w = equipped() or lastWeapon
		if cmd == "trigger" then
			triggerHeld = arg == true
		elseif cmd == "aim" then
			aimHeld = arg == true
		elseif cmd == "record" then
			if arg then
				debugLog, debugShots = {}, {}
			else
				local log, shots = debugLog, debugShots
				debugLog = nil
				return { log = log, shots = shots }
			end
		elseif cmd == "refill" then
			w.Reload:Cancel()
			w.Fire:Refill()
			WeaponCommand:FireServer("DevRefill")
		elseif cmd == "reload" then
			return { result = requestReload() }
		elseif cmd == "freeze" then
			debugFreeze = arg -- { clip = "TacticalRegular", t = 1.9 } or nil
		elseif cmd == "clipInfo" then
			local info = {}
			for name, c in w.Reload.Clips do
				info[name] = { Length = c.Length, Frames = c.Frames, Events = c.Events }
			end
			return info
		elseif cmd == "stressed" then
			WeaponCommand:FireServer("DevSetStressed", arg == true)
		elseif cmd == "setAmmo" then
			w.ServerState = nil
			WeaponCommand:FireServer("DevSetAmmo", arg) -- Studio-only; the server's state comes back via WeaponState
		elseif cmd == "sync" then
			w.ServerState = nil
			WeaponCommand:FireServer("Sync", w.Id)
		elseif cmd == "optic" then
			-- optics slice: read-only state of a weapon's optic (arg = weapon id, default the equipped / last one)
			local ow = if typeof(arg) == "string" then weapons[arg] else w
			if not (ow and ow.Optic) then
				return { optic = false }
			end
			local d = ow.Optic:Debug(workspace.CurrentCamera)
			d.aimState = (ow.Aim :: any).State
			d.aimAlpha = (ow.Aim :: any).Alpha
			return d
		elseif cmd == "zoom" then
			-- Sniper slice: the zoom input (arg = +1 / -1); nil when not aiming or no zoom
			return { level = stepZoom(if typeof(arg) == "number" then arg else 1) }
		elseif cmd == "check" then
			return { result = requestCheck() }
		elseif cmd == "audio" then
			-- M4 audio fidelity slice: arg true = start the play/stop log, false = stop it and return it; the state of
			-- every weapon's audio (arg "all") or of the equipped / last one
			if arg == true then
				for _, ow in weapons do
					ow.Audio.Log = {}
				end
			elseif arg == false then
				local logs = {}
				for id, ow in weapons do
					logs[id] = ow.Audio.Log
					ow.Audio.Log = nil
				end
				return { logs = logs, shots = table.clone(debugShots) }
			end
			local states = {}
			for id, ow in weapons do
				states[id] = ow.Audio:State()
			end
			return { weapon = w.Id, audio = states, now = os.clock() }
		elseif cmd == "holdKick" then
			-- Glock aimed recoil: arg true = stop the recoil springs / camera kick decay and the slide where they are now
			-- (to screenshot a shot phase), false releases
			debugKick = if arg then { slide = if w.Cfg.Slide then slideFraction(w, os.clock()) else 0 } else nil
		elseif cmd == "aimedRecoil" then
			-- Glock aimed recoil, BEFORE / AFTER captures: arg false = run without Recoil.Weapon.Aimed (the old kick), true restores
			local wc = w.Cfg.Recoil.Weapon
			if arg == false and wc.Aimed then
				debugAimed = wc.Aimed
				wc.Aimed = nil
			elseif arg == true and debugAimed then
				wc.Aimed = debugAimed
			end
			return { aimed = wc.Aimed ~= nil }
		elseif cmd == "freezeHold" then
			-- Glock aim-hold drift: show the drift of hold time arg (s since the aim input) while aimed; nil releases
			if w.AimHold then
				w.AimHold.DebugT = if typeof(arg) == "number" then arg else nil
			end
		elseif cmd == "freezeBolt" then
			debugBolt = if typeof(arg) == "number" then arg else nil -- hold the bolt cycle at t (s), nil releases
			if debugBolt == nil and w.Bolt then
				w.Bolt:Cancel()
			end
		end
		return {
			weapon = w.Id,
			mag = w.Fire.Ammo.Mag,
			chambered = w.Fire.Ammo.Chambered,
			reserve = table.clone(w.Fire.Ammo.Reserve),
			dropped = table.clone(w.Fire.Ammo.Dropped),
			labelMarks = w.Fire.Ammo.LabelMarks,
			hud = w.Hud:State(),
			reloading = if w.Reload.Active then w.Reload.Active.Spec.Clip else nil,
			reloadSwapped = if w.Reload.Active then w.Reload.Active.Swapped else nil,
			lastReload = w.Reload.LastFinished,
			stressed = player:GetAttribute("Stressed") == true,
			shotCount = w.Fire.ShotCount,
			interval = w.Fire.Interval,
			climb = w.Recoil.Climb,
			envelope = w.Recoil.Envelope,
			kickPos = w.Recoil:KickPos(),
			kickRot = w.Recoil:KickRot(),
			server = w.ServerState,
			pivot = w.Pivot,
			sightGlass = w.SightGlass,
			sightRear = w.Rig.Points.SightRear,
			slide = if w.Cfg.Slide then slideFraction(w, os.clock()) else nil, -- Glock slice (1 = locked back)
			lastShotAt = w.Fire.LastShotAt,
			nextShotAt = w.Fire.NextShotAt, -- Sniper slice: the trigger waits for the bolt cycle
			chamberDueAt = w.Fire.ChamberDueAt,
			bolt = if w.Bolt then w.Bolt:State(os.clock()) else nil,
			zoomLevel = if w.Optic then w.Optic:ZoomLevel() else nil,
			now = os.clock(),
			active = w.Active,
			viewmodelParented = w.Rig.Model.Parent ~= nil,
			viewmodels = (function()
				local n = 0
				for _, c in workspace.CurrentCamera:GetChildren() do
					if string.sub(c.Name, -9) == "Viewmodel" then
						n += 1
					end
				end
				return n
			end)(),
		}
	end
	hook.Parent = script
end
