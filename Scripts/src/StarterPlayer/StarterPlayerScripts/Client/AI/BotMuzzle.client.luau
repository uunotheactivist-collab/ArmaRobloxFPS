--!strict
-- Bot muzzle flash (client, presentation only; AI combat slice). Each bot rifle (tag AIRifle) carries a server shot
-- counter (attribute AIShots); when it rises, a brief flash and light show at the rifle's Muzzle attachment. No remote
-- message per shot, and nothing here can affect a shot: the server traced it already (Server.WeaponShot), and its
-- impacts / blood arrive through the existing Blood effects.
-- Values: Config.AI.Muzzle (placeholders: no bot is ever seen firing in the reference).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AI"))
local M = Config.Muzzle

local FlashCount = 0

local function flash(rifle: Instance)
	local body = rifle:IsA("Model") and rifle.PrimaryPart or nil
	local muzzle = body and body:FindFirstChild("Muzzle") :: Attachment?
	if not body or not muzzle then
		return
	end
	FlashCount += 1
	local color = Color3.fromRGB(M.LightColor[1], M.LightColor[2], M.LightColor[3])
	local light = Instance.new("PointLight")
	light.Name = "BotMuzzleLight"
	light.Color = color
	light.Brightness = M.LightBrightness
	light.Range = M.LightRange
	light.Shadows = false
	light.Parent = muzzle
	local p = Instance.new("Part")
	p.Name = "BotMuzzleFlash"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * M.FlashSizeStuds
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = muzzle.WorldCFrame
	p.Parent = workspace.CurrentCamera
	task.delay(M.FlashSeconds, function()
		light:Destroy()
		p:Destroy()
	end)
end

local function watch(rifle: Instance)
	local last = rifle:GetAttribute(Config.ShotsAttribute) or 0
	rifle:GetAttributeChangedSignal(Config.ShotsAttribute):Connect(function()
		local n = rifle:GetAttribute(Config.ShotsAttribute) or 0
		if n > last then
			flash(rifle)
		end
		last = n
	end)
end

CollectionService:GetInstanceAddedSignal(Config.RifleTag):Connect(watch)
for _, r in CollectionService:GetTagged(Config.RifleTag) do
	watch(r)
end

-- Studio-only: how many flashes this client showed (AI tests).
if game:GetService("RunService"):IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "BotMuzzleDebug"
	bf.OnInvoke = function(): any
		return { Flashes = FlashCount, Rifles = #CollectionService:GetTagged(Config.RifleTag) }
	end
	bf.Parent = script
end
