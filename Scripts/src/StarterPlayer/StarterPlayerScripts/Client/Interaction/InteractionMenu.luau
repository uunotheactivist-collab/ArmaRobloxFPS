--!strict
-- Temporary body-interaction menu (client presentation only; the final HUD will replace it). Layout from the footage:
-- a small list just left of / below the screen centre, the selected line with an orange "F" key cap, the others with a
-- hollow circle, the first line larger; "Checking pulse..." with an orange underline that fills linearly; a result line
-- with a coloured dot. Shows only what it is given; decides nothing.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Menu = {}

local ORANGE = Color3.fromRGB(240, 150, 40)
local WHITE = Color3.fromRGB(235, 235, 235)
local LINE_H = 20

local gui: ScreenGui? = nil
local root: Frame? = nil
local lines: { TextLabel } = {}
local caps: { TextLabel } = {}
local underline: Frame? = nil
local resultLabel: TextLabel? = nil
local tween: Tween? = nil

local function build()
	if gui and gui.Parent then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "BodyInteractionHud"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 5
	local f = Instance.new("Frame")
	f.Name = "Menu"
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromScale(0.455, 0.49)
	f.Size = UDim2.fromOffset(320, LINE_H * 4)
	f.Visible = false
	f.Parent = g
	table.clear(lines)
	table.clear(caps)
	for i = 1, 3 do
		local cap = Instance.new("TextLabel")
		cap.Name = "Cap" .. i
		cap.BackgroundTransparency = 1
		cap.Position = UDim2.fromOffset(0, (i - 1) * LINE_H)
		cap.Size = UDim2.fromOffset(16, 16)
		cap.Font = Enum.Font.GothamBold
		cap.TextSize = 11
		cap.Parent = f
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = cap
		local l = Instance.new("TextLabel")
		l.Name = "Line" .. i
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(22, (i - 1) * LINE_H)
		l.Size = UDim2.fromOffset(290, 16)
		l.Font = Enum.Font.Gotham
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = WHITE
		l.TextStrokeTransparency = 0.6
		l.Parent = f
		table.insert(caps, cap)
		table.insert(lines, l)
	end
	local u = Instance.new("Frame")
	u.Name = "Progress"
	u.BorderSizePixel = 0
	u.BackgroundColor3 = ORANGE
	u.Position = UDim2.fromOffset(22, 16)
	u.Size = UDim2.fromOffset(0, 2)
	u.Visible = false
	u.Parent = f
	local r = Instance.new("TextLabel")
	r.Name = "Result"
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromOffset(300, 16)
	r.Font = Enum.Font.Gotham
	r.TextSize = 13
	r.TextXAlignment = Enum.TextXAlignment.Left
	r.TextStrokeTransparency = 0.6
	r.Visible = false
	r.Parent = f
	g.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	gui, root, underline, resultLabel = g, f, u, r
end

-- view = { items = { text }, selected = n, busy = bool, result = { Text, Color }? }; nil hides the menu.
function Menu.show(view: any?)
	build()
	local f = root :: Frame
	if not view then
		f.Visible = false
		return
	end
	f.Visible = true
	local n = #view.items
	for i = 1, 3 do
		local l, cap = lines[i], caps[i]
		local text = view.items[i]
		l.Visible = text ~= nil
		cap.Visible = text ~= nil
		if text then
			local sel = i == view.selected
			l.Text = text
			l.TextSize = if i == 1 then 15 else 13
			cap.Text = if sel then "F" else "○"
			cap.BackgroundTransparency = if sel then 0 else 1
			cap.BackgroundColor3 = ORANGE
			cap.TextColor3 = if sel then Color3.new(0, 0, 0) else WHITE
		end
	end
	local r = resultLabel :: TextLabel
	if view.result then
		r.Visible = true
		r.Position = UDim2.fromOffset(0, n * LINE_H)
		r.Text = "●  " .. view.result.Text
		r.TextColor3 = view.result.Color
	else
		r.Visible = false
	end
	if not view.busy then
		Menu.stopProgress()
	end
end

-- The underline under line 1 fills linearly over `seconds` (the text's width), starting `elapsed` seconds in.
function Menu.startProgress(seconds: number, elapsed: number)
	build()
	local u = underline :: Frame
	local width = math.max((lines[1] :: TextLabel).TextBounds.X, 80)
	if tween then
		tween:Cancel()
	end
	local u0 = math.clamp(elapsed / seconds, 0, 1)
	u.Size = UDim2.fromOffset(width * u0, 2)
	u.Visible = true
	local t = TweenService:Create(u, TweenInfo.new(math.max(seconds - elapsed, 0), Enum.EasingStyle.Linear),
		{ Size = UDim2.fromOffset(width, 2) })
	t:Play()
	tween = t
end

function Menu.stopProgress()
	if tween then
		tween:Cancel()
		tween = nil
	end
	if underline then
		underline.Visible = false
	end
end

-- For tests: what is on screen.
function Menu.read(): any
	if not root or not root.Visible then
		return { Visible = false }
	end
	local out = { Visible = true, Lines = {}, Selected = nil :: number?, Result = nil :: string?, Progress = nil :: number? }
	for i, l in lines do
		if l.Visible then
			table.insert(out.Lines, l.Text)
			if caps[i].Text == "F" then
				out.Selected = i
			end
		end
	end
	if resultLabel and resultLabel.Visible then
		out.Result = resultLabel.Text
	end
	if underline and underline.Visible then
		out.Progress = underline.Size.X.Offset
	end
	return out
end

return Menu
