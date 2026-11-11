--!strict
-- The CONTROLS panel at the right edge while seated (truck slice): the verbatim lines of the seat kind [CONFIRMED], in
-- small grey monospaced text with no backing box; every line right-aligned at x 1262, the block centred at y 360.5,
-- 14.7 px apart, three spaces between a control's name and its key; keys ≈ 12 brighter than names [MEASURED]. It appears
-- with the entry cut (back) or 4 frames after it (driver) and stays 11 / 9 frames after the exit cut, then goes without
-- a fade [MEASURED]. Values: Shared.Config.Vehicles.Controls (1280 × 720 reference pixels, scaled by height).
-- Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vehicles"))
local C = Config.Controls

-- the monospace face's advance per unit of TextSize, measured once (so the grid matches the reference's 5.35 px)
local advancePerSize = TextService:GetTextSize(string.rep("M", 20), 100, C.Layout.Font, Vector2.new(1e5, 1e5)).X / 2000

local Panel = {}

local gui: ScreenGui? = nil
local shownKind: string? = nil
local token = 0

local function build(kind: string)
	if gui then
		gui:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "VehicleControls"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 5
	local vp = workspace.CurrentCamera.ViewportSize
	local s = vp.Y / 720
	local L = C.Layout
	local list = C[kind]
	local adv = L.CharAdvance * s
	local size = adv / advancePerSize
	local rightX = vp.X - (1280 - L.RightX) * s -- the reference's right margin, kept from the right edge
	local top = vp.Y / 2 + (L.CentreY - 360) * s - (#list - 1) * L.LineSpacing * s / 2
	for i, line in list do
		local y = top + (i - 1) * L.LineSpacing * s
		local function label(text: string, xRight: number, color: Color3)
			local t = Instance.new("TextLabel")
			t.Name = "L" .. i
			t.BackgroundTransparency = 1
			t.Font = L.Font
			t.TextSize = size
			t.TextColor3 = color
			t.TextXAlignment = Enum.TextXAlignment.Right
			t.TextYAlignment = Enum.TextYAlignment.Center
			t.Text = text
			t.AnchorPoint = Vector2.new(1, 0.5)
			t.Size = UDim2.fromOffset(#text * adv + 4, L.LineSpacing * s)
			t.Position = UDim2.fromOffset(xRight, y)
			t.Parent = g
			return t
		end
		local name, key = string.match(line, "^(.-)   (%S.*)$")
		if i > 1 and name and key then
			label(key, rightX, L.KeyColor)
			label(name, rightX - (utf8.len(key) or #key) * adv - 3 * adv, L.NameColor)
		else
			label(line, rightX, L.TitleColor)
		end
	end
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
end

-- show the panel for a seat kind ("Back" / "Driver") after its delay
function Panel.show(kind: string)
	token += 1
	local my = token
	task.delay(C.ShowDelay[kind] or 0, function()
		if my ~= token then
			return
		end
		build(kind)
		shownKind = kind
	end)
end

-- hide it after the seat kind's linger time
function Panel.hide(kind: string?)
	token += 1
	local my = token
	task.delay(if kind then C.Linger[kind] or 0 else 0, function()
		if my ~= token then
			return
		end
		if gui then
			gui:Destroy()
			gui = nil
		end
		shownKind = nil
	end)
end

function Panel.read(): any
	local lines = {}
	if gui then
		for _, t in gui:GetChildren() do
			if t:IsA("TextLabel") then
				table.insert(lines, { Text = t.Text, Right = t.AbsolutePosition.X + t.AbsoluteSize.X, Y = t.AbsolutePosition.Y
					+ t.AbsoluteSize.Y / 2, Size = t.TextSize, Bounds = t.TextBounds })
			end
		end
	end
	return { Kind = shownKind, Lines = lines }
end

return Panel
