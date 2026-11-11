--!strict
-- The footage's "CROUCHED" toast (client presentation only): the shared bottom-left transient-text style (as the
-- grenade's "FRAG OUT  xN"), shown when the server confirms a crouch, solid, then a short fade
-- (Config.Movement.Crouch.Toast). Nothing is shown for standing up (UNKNOWN in the footage).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Movement"))

local Toast = {}

local label: TextLabel? = nil
local token = 0
local shownAt = 0
local fade: Tween? = nil

local function build(): TextLabel
	if label and label.Parent and label.Parent.Parent then
		return label
	end
	local T = Config.Crouch.Toast
	local g = Instance.new("ScreenGui")
	g.Name = "MovementHud"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 4
	local t = Instance.new("TextLabel")
	t.Name = "StanceToast"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = T.Position
	t.Size = UDim2.fromOffset(240, T.TextSize + 4)
	t.Font = Enum.Font.Code
	t.TextSize = T.TextSize
	t.TextColor3 = T.Color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTransparency = 1
	t.Parent = g
	g.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	label = t
	return t
end

function Toast.show(text: string)
	local t = build()
	token += 1
	local mine = token
	shownAt = os.clock()
	if fade then
		fade:Cancel()
		fade = nil
	end
	t.Text = text
	t.TextTransparency = 0
	local T = Config.Crouch.Toast
	task.delay(T.SolidSeconds, function()
		if token == mine then
			local tw = TweenService:Create(t, TweenInfo.new(T.FadeSeconds, Enum.EasingStyle.Linear), { TextTransparency = 1 })
			fade = tw
			tw:Play()
		end
	end)
end

function Toast.hide()
	token += 1
	if fade then
		fade:Cancel()
		fade = nil
	end
	if label then
		label.TextTransparency = 1
	end
end

function Toast.read(): any
	local t = label
	return {
		Text = t and t.Text,
		Visible = t ~= nil and t.TextTransparency < 0.99,
		Transparency = t and t.TextTransparency,
		Age = os.clock() - shownAt,
	}
end

return Toast
