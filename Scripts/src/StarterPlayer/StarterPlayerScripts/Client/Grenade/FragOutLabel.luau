--!strict
-- The footage's grenade label (client presentation only): small light-grey text at the bottom left, "FRAG OUT  xN" at
-- release (N = grenades left, from the server) or "NO FRAGS LEFT", solid for 1.53 s, then a 0.2 s fade
-- (Config.Grenade.Label, measured). Minimal on purpose: no grenade HUD or inventory.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))

local Label = {}

local label: TextLabel? = nil
local token = 0
local shownAt = 0
local fade: Tween? = nil

local function build(): TextLabel
	if label and label.Parent and label.Parent.Parent then
		return label
	end
	local L = Config.Label
	local g = Instance.new("ScreenGui")
	g.Name = "GrenadeHud"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 4
	local t = Instance.new("TextLabel")
	t.Name = "FragOut"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = L.Position
	t.Size = UDim2.fromOffset(240, L.TextSize + 4)
	t.Font = Enum.Font.Code
	t.TextSize = L.TextSize
	t.TextColor3 = L.Color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTransparency = 1
	t.Parent = g
	g.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	label = t
	return t
end

function Label.show(text: string)
	local t = build()
	token += 1
	local mine = token
	shownAt = os.clock()
	if fade then
		fade:Cancel() -- a new label replaces one still fading
		fade = nil
	end
	t.Text = text
	t.TextTransparency = 0
	local L = Config.Label
	task.delay(L.SolidSeconds, function()
		if token == mine then
			local tw = TweenService:Create(t, TweenInfo.new(L.FadeSeconds, Enum.EasingStyle.Linear), { TextTransparency = 1 })
			fade = tw
			tw:Play()
		end
	end)
end

function Label.read(): any
	local t = label
	return { Text = t and t.Text, Visible = t ~= nil and t.TextTransparency < 0.99, Transparency = t and t.TextTransparency,
		Age = os.clock() - shownAt }
end

return Label
