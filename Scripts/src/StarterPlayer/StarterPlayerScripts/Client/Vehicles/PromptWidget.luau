--!strict
-- The interaction prompt (truck slice): fixed in screen space just left of the screen centre, no backing panel, one or
-- two lines [CONFIRMED]. The active line carries the orange [F] key box, the other an outline "○" where its box would be
-- and slightly greyer text; line 2 sits +25.4 px right / +26 px down and its text is 0.8× smaller [MEASURED]. It fades
-- in (exponential approach, ≥ 0.9 after 3–4 frames) and out (5 frames) when a target appears / disappears, and swaps text
-- instantly between targets [MEASURED]; the key box goes pale on a press [MEASURED]. Values: Shared.Config.Vehicles.Prompt
-- (1280 × 720 reference pixels, scaled by the viewport height). Presentation only: what is offered is decided by
-- Shared.Vehicles.VehicleActions and checked by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vehicles"))
local P = Config.Prompt

local Widget = {}

local gui: ScreenGui? = nil
local lines: { any } = {}
local alpha = 0 -- 0 hidden … 1 shown
local wanted = false
local pressedUntil = 0
local active = 1
local count = 0
local conn: RBXScriptConnection? = nil
local lastHeight = 0

local function build()
	if gui and gui.Parent then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "VehiclePrompt"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 6
	lines = {}
	for i = 1, 2 do
		local box = Instance.new("Frame")
		box.Name = "Key" .. i
		box.BorderSizePixel = 0
		box.BackgroundColor3 = P.BoxColor
		local corner = Instance.new("UICorner")
		corner.Parent = box
		local letter = Instance.new("TextLabel")
		letter.Name = "Letter"
		letter.BackgroundTransparency = 1
		letter.AnchorPoint = Vector2.new(0.5, 0.5)
		letter.Position = UDim2.fromScale(0.5, 0.5)
		letter.Size = UDim2.fromScale(1, 1)
		letter.Font = Enum.Font.BuilderSansBold
		letter.Text = "F"
		letter.TextColor3 = P.LetterColor
		letter.Parent = box
		box.Parent = g
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0.5, 0)
		rc.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Color = P.RingColor
		stroke.Parent = ring
		ring.Parent = g
		local text = Instance.new("TextLabel")
		text.Name = "Text" .. i
		text.BackgroundTransparency = 1
		text.Font = P.Font
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Center
		text.TextStrokeColor3 = P.TextStrokeColor
		text.Parent = g
		lines[i] = { Box = box, Corner = corner, Letter = letter, Ring = ring, Stroke = stroke, Text = text }
	end
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	lastHeight = 0
end

local function layout()
	local vp = workspace.CurrentCamera.ViewportSize
	if vp.Y == lastHeight then
		return
	end
	lastHeight = vp.Y
	local s = vp.Y / 720
	local cx, cy = vp.X / 2, vp.Y / 2
	for i, l in lines do
		local x = cx + (P.BoxLeftFromCentre + (if i == 2 then P.SecondLineIndent else 0)) * s
		local y = cy + (P.BoxTopFromCentre + (if i == 2 then P.SecondLineDown else 0)) * s
		local b = P.BoxSize * s
		l.Box.Position = UDim2.fromOffset(x, y)
		l.Box.Size = UDim2.fromOffset(b, b)
		l.Corner.CornerRadius = UDim.new(0, P.BoxCorner * s)
		l.Letter.TextSize = P.LetterHeight * s / P.CapPerTextSize
		l.Ring.Position = UDim2.fromOffset(x + b / 2, y + b / 2)
		l.Ring.Size = UDim2.fromOffset(P.RingDiameter * s, P.RingDiameter * s)
		l.Stroke.Thickness = P.RingStroke * s
		local cap = P.CapHeight * (if i == 2 then P.SecondLineScale else 1)
		l.Text.TextSize = cap * s / P.CapPerTextSize
		l.Text.Position = UDim2.fromOffset(x + b + P.TextGap * s, y)
		l.Text.Size = UDim2.fromOffset(600 * s, b)
	end
end

local function paint()
	local pressed = os.clock() < pressedUntil
	for i, l in lines do
		local shown = i <= count and alpha > 0
		local isActive = i == active
		l.Box.Visible = shown and isActive
		l.Ring.Visible = shown and not isActive
		l.Text.Visible = shown
		if shown then
			l.Box.BackgroundColor3 = if pressed then P.BoxPressedColor else P.BoxColor
			l.Box.BackgroundTransparency = 1 - alpha
			l.Letter.TextTransparency = 1 - alpha
			l.Stroke.Transparency = 1 - alpha
			l.Text.TextColor3 = if isActive then P.TextColor else P.InactiveColor
			l.Text.TextTransparency = 1 - alpha
			l.Text.TextStrokeTransparency = 1 - alpha * (1 - P.TextStrokeTransparency)
		end
	end
end

local function step(dt: number)
	if wanted then
		alpha = alpha + (1 - alpha) * (1 - math.exp(-dt / P.FadeInTau))
		if alpha > 0.995 then
			alpha = 1
		end
	else
		alpha = math.max(0, alpha - dt / P.FadeOutSeconds)
	end
	layout()
	paint()
	if alpha == 0 and not wanted and conn then
		conn:Disconnect()
		conn = nil
	end
end

-- options: list of texts (1 or 2); act: the active line. Texts swap at once; the widget fades only in / out.
function Widget.set(texts: { string }, act: number)
	build()
	count = #texts
	if count > 0 then
		active = math.clamp(act, 1, count)
		for i, l in lines do
			if texts[i] then
				l.Text.Text = texts[i]
			end
		end
		wanted = true
	else
		wanted = false
	end
	if not conn and (wanted or alpha > 0) then
		conn = RunService.RenderStepped:Connect(step)
	end
end

-- the key box goes pale for `seconds`
function Widget.press(seconds: number?)
	pressedUntil = os.clock() + (seconds or P.PaleSeconds)
end

-- the prompt goes at once (an enter / move / leave request is on its way: the pale lasts 1–2 frames [MEASURED])
function Widget.withdraw()
	wanted = false
	alpha = 0
	pressedUntil = 0
	paint()
end

function Widget.read(): any
	local out = { Alpha = alpha, Wanted = wanted, Active = active, Count = count, Pressed = os.clock() < pressedUntil, Lines = {} }
	for i = 1, count do
		local l = lines[i]
		table.insert(out.Lines, { Text = l.Text.Text, BoxPos = l.Box.AbsolutePosition, BoxSize = l.Box.AbsoluteSize,
			TextPos = l.Text.AbsolutePosition, TextSize = l.Text.TextSize, HasKey = l.Box.Visible,
			Ring = l.Ring.Visible, Bounds = l.Text.TextBounds })
	end
	return out
end

return Widget
