--!strict
-- Client side of the test weapon: first-person viewmodel, fire input, and local
-- feedback (tracer, muzzle flash, recoil kick, hitmarker, respawn notice).
-- CombatServer decides every hit. This script only reports where it aimed.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local FireWeapon = Combat:WaitForChild("FireWeapon") :: RemoteEvent
local HitConfirm = Combat:WaitForChild("HitConfirm") :: RemoteEvent

local Weapon = CombatConfig.Weapon
local player = Players.LocalPlayer

-- Shared with the production weapon controller (StarterPlayerScripts.Client): the blaster is only active while
-- it is the equipped weapon (key 1 equips it, key 2 the production M4).
local function blasterEquipped(): boolean
	local equipped = player:GetAttribute("EquippedWeapon")
	return equipped == nil or equipped == "TestBlaster"
end

local hud = player:WaitForChild("PlayerGui"):WaitForChild("CombatHUD") :: ScreenGui
local crosshair = hud:WaitForChild("Crosshair") :: Frame
local hitmarker = hud:WaitForChild("Hitmarker") :: Frame
local damageLabel = hitmarker:WaitForChild("Damage") :: TextLabel
local deathNotice = hud:WaitForChild("DeathNotice") :: TextLabel

UserInputService.MouseIconEnabled = false -- the HUD draws its own crosshair

---------------------------------------------------------------------------
-- Viewmodel: a client-only blaster that follows the camera.
---------------------------------------------------------------------------

-- Right, down, and forward of the camera, angled slightly in toward the crosshair.
local VIEWMODEL_OFFSET = CFrame.new(0.5, -0.45, -1.7) * CFrame.Angles(0, math.rad(3), 0)

local viewmodel = Instance.new("Model")
viewmodel.Name = "TestBlasterViewmodel"

local function addPart(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- never blocks a raycast
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = viewmodel
	return part
end

local body = addPart("Body", Vector3.new(0.22, 0.3, 0.9), CFrame.new(), Color3.fromRGB(58, 62, 70), Enum.Material.Metal)
addPart(
	"Grip",
	Vector3.new(0.18, 0.42, 0.2),
	CFrame.new(0, -0.3, 0.25) * CFrame.Angles(math.rad(-15), 0, 0),
	Color3.fromRGB(28, 28, 32),
	Enum.Material.SmoothPlastic
)
local barrel = addPart("Barrel", Vector3.new(0.1, 0.1, 0.5), CFrame.new(0, 0.05, -0.7), Color3.fromRGB(90, 94, 104), Enum.Material.Metal)
addPart("Sight", Vector3.new(0.04, 0.07, 0.04), CFrame.new(0, 0.185, -0.3), Color3.fromRGB(255, 140, 40), Enum.Material.Neon)

local flash = addPart("MuzzleFlash", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, 0.05, -1.0), Color3.fromRGB(255, 210, 120), Enum.Material.Neon)
flash.Shape = Enum.PartType.Ball
flash.Transparency = 1

local flashLight = Instance.new("PointLight")
flashLight.Color = flash.Color
flashLight.Range = 8
flashLight.Brightness = 3
flashLight.Enabled = false
flashLight.Parent = flash

local muzzle = Instance.new("Attachment")
muzzle.Name = "Muzzle"
muzzle.Position = Vector3.new(0, 0, -0.25)
muzzle.Parent = barrel

viewmodel.PrimaryPart = body

---------------------------------------------------------------------------
-- Local shot feedback
---------------------------------------------------------------------------

local TRACER_LIFETIME = 0.08
local IMPACT_LIFETIME = 0.2
local fadeTracer = TweenInfo.new(TRACER_LIFETIME, Enum.EasingStyle.Linear)
local fadeImpact = TweenInfo.new(IMPACT_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function makeEffectPart(name: string, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	return part
end

local function drawShot(from: Vector3, to: Vector3, didHit: boolean)
	local length = (to - from).Magnitude
	if length > 0.1 then
		local tracer = makeEffectPart("Tracer", Color3.fromRGB(255, 220, 140))
		tracer.Size = Vector3.new(0.06, 0.06, length)
		tracer.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
		tracer.Parent = workspace
		TweenService:Create(tracer, fadeTracer, { Transparency = 1 }):Play()
		task.delay(TRACER_LIFETIME, tracer.Destroy, tracer)
	end

	if didHit then
		local impact = makeEffectPart("Impact", Color3.fromRGB(255, 240, 200))
		impact.Shape = Enum.PartType.Ball
		impact.Size = Vector3.new(0.35, 0.35, 0.35)
		impact.CFrame = CFrame.new(to)
		impact.Parent = workspace
		TweenService:Create(impact, fadeImpact, { Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		task.delay(IMPACT_LIFETIME, impact.Destroy, impact)
	end
end

local function flashMuzzle()
	flash.Transparency = 0.2
	flashLight.Enabled = true
	task.delay(0.04, function()
		flash.Transparency = 1
		flashLight.Enabled = false
	end)
end

local HIT_COLOR = Color3.new(1, 1, 1)
local HEADSHOT_COLOR = Color3.fromRGB(255, 210, 60)
local KILL_COLOR = Color3.fromRGB(255, 60, 60)
local hitmarkerShownAt = 0

HitConfirm.OnClientEvent:Connect(function(info: any)
	if typeof(info) ~= "table" then
		return
	end
	local color = if info.killed then KILL_COLOR elseif info.headshot then HEADSHOT_COLOR else HIT_COLOR
	for _, child in hitmarker:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
		end
	end
	damageLabel.TextColor3 = color
	damageLabel.Text = tostring(math.round(tonumber(info.damage) or 0))
		.. (if info.killed then "  KILL" elseif info.headshot then "  HEADSHOT" else "")
	hitmarker.Visible = true

	local shownAt = os.clock()
	hitmarkerShownAt = shownAt
	task.delay(0.25, function()
		if hitmarkerShownAt == shownAt then
			hitmarker.Visible = false
		end
	end)
end)

---------------------------------------------------------------------------
-- Firing
---------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local lastShotAt = -math.huge
local triggerHeld = false
local recoil = 0
local diedAt: number? = nil

local function getLiveCharacter(): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character
	end
	return nil
end

local function fire()
	local character = getLiveCharacter()
	if not character then
		return
	end
	local now = os.clock()
	if now - lastShotAt < Weapon.FireInterval then
		return
	end
	lastShotAt = now

	-- Shoot from the camera through the centre of the screen, where the crosshair is.
	local cameraCFrame = (workspace.CurrentCamera :: Camera).CFrame
	local origin = cameraCFrame.Position
	local direction = cameraCFrame.LookVector
	FireWeapon:FireServer(origin, direction)

	-- This ray only places the tracer. The server runs its own to decide the hit.
	rayParams.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(origin, direction * Weapon.Range, rayParams)
	local hitPoint = if result then result.Position else origin + direction * Weapon.Range
	drawShot(muzzle.WorldPosition, hitPoint, result ~= nil)
	flashMuzzle()
	recoil = 1
end

local function onFireAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if not blasterEquipped() then
		triggerHeld = false
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		triggerHeld = true
		fire()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		triggerHeld = false
	end
	return Enum.ContextActionResult.Sink
end

-- Mouse, gamepad right trigger, and an on-screen button on touch devices.
ContextActionService:BindAction("FireWeapon", onFireAction, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle("FireWeapon", "Fire")

---------------------------------------------------------------------------
-- Life cycle
---------------------------------------------------------------------------

local function onCharacterAdded(character: Model)
	diedAt = nil
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(function()
		diedAt = os.clock()
		triggerHeld = false
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

-- Runs right after the camera updates, so the viewmodel never lags a frame behind.
RunService:BindToRenderStep("TestBlasterViewmodel", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = workspace.CurrentCamera :: Camera
	local alive = getLiveCharacter() ~= nil and blasterEquipped()
	crosshair.Visible = alive
	if not alive then
		triggerHeld = false
	end

	if alive then
		if triggerHeld and Weapon.Automatic then
			fire()
		end
		recoil *= math.exp(-dt * 18)
		local kick = CFrame.new(0, 0, recoil * 0.25) * CFrame.Angles(math.rad(recoil * 6), 0, 0)
		viewmodel:PivotTo(camera.CFrame * VIEWMODEL_OFFSET * kick)
		if viewmodel.Parent ~= camera then
			viewmodel.Parent = camera
		end
	elseif viewmodel.Parent then
		viewmodel.Parent = nil
	end

	if diedAt then
		local remaining = CombatConfig.PlayerRespawnDelay - (os.clock() - diedAt)
		deathNotice.Text = if remaining > 0 then string.format("Respawning in %.1f", remaining) else "Respawning..."
		deathNotice.Visible = true
	elseif deathNotice.Visible then
		deathNotice.Visible = false
	end
end)
