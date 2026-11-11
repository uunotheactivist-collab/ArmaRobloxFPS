--!strict
-- Red screen-edge pulse (grenade fidelity slice; client presentation only). The reference shows an edge-only red tint
-- that is at full strength in the detonation frame and fades over ≈ 2.1 s (ReferenceAnalysis/GrenadeFidelity C9, M12).
-- Shown when the server reports that fragments reached this player's character (GrenadeState "FragmentsHit"; the
-- trigger is INFERRED). Four edge frames with a red-to-clear gradient, made once; a render callback runs only while a
-- pulse is visible. Values: Config.Grenade.Effects.RedEdge.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grenade"))
local R = Config.Effects.RedEdge

local RedEdge = {}
RedEdge.Count = 0

local gui: ScreenGui? = nil
local frames: { Frame } = {}
local startedAt = -math.huge
local conn: RBXScriptConnection? = nil
local current = 0

-- One edge: a red frame along `side`, transparent inward (UIGradient across its depth).
local function edge(parent: Instance, side: string): Frame
	local f = Instance.new("Frame")
	f.Name = side
	f.BorderSizePixel = 0
	f.BackgroundColor3 = R.Color
	f.BackgroundTransparency = 1
	local d = R.DepthScale
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(R.Color)
	-- opaque at the outer edge (gradient start), clear at the inner end, along the measured profile
	local keys = {}
	for _, k in R.Profile do
		table.insert(keys, NumberSequenceKeypoint.new(k[1], 1 - k[2]))
	end
	grad.Transparency = NumberSequence.new(keys)
	if side == "Top" then
		f.Size = UDim2.fromScale(1, d)
		f.Position = UDim2.fromScale(0, 0)
		grad.Rotation = 90
	elseif side == "Bottom" then
		f.Size = UDim2.fromScale(1, d)
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.fromScale(0, 1)
		grad.Rotation = -90
	elseif side == "Left" then
		f.Size = UDim2.new(0, 0, 1, 0) -- width set from the height in build() (same depth in pixels on every side)
		f.Position = UDim2.fromScale(0, 0)
		grad.Rotation = 0
	else
		f.Size = UDim2.new(0, 0, 1, 0)
		f.AnchorPoint = Vector2.new(1, 0)
		f.Position = UDim2.fromScale(1, 0)
		grad.Rotation = 180
	end
	grad.Parent = f
	f.Parent = parent
	return f
end

local function build()
	if gui and gui.Parent then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "GrenadeRedEdge"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 3
	g.Enabled = false
	frames = { edge(g, "Top"), edge(g, "Bottom"), edge(g, "Left"), edge(g, "Right") }
	g.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	gui = g
end

-- strength of the pulse t seconds after its start (1 at t = 0)
function RedEdge.strength(t: number): number
	if t < 0 then
		return 0
	end
	return R.Fast * math.exp(-math.max(0, t - (R.Hold or 0)) / R.FastTau) + (1 - R.Fast) * math.max(0, 1 - t / R.TailSeconds)
end

local held: number? = nil -- Studio test hook: a fixed strength (captures)

local function step()
	local g = gui :: ScreenGui
	local t = os.clock() - startedAt
	local s = if held then held else RedEdge.strength(t)
	current = s
	local h = g.AbsoluteSize.Y
	local depthPx = math.floor(h * R.DepthScale + 0.5)
	for _, f in frames do
		if f.Name == "Left" or f.Name == "Right" then
			f.Size = UDim2.new(0, depthPx, 1, 0)
		end
		f.BackgroundTransparency = 1 - R.PeakAlpha * s
	end
	if s <= 0.002 then
		g.Enabled = false
		current = 0
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
end

function RedEdge.pulse()
	build()
	startedAt = os.clock()
	RedEdge.Count += 1
	local g = gui :: ScreenGui
	g.Enabled = true
	step()
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

-- Studio test hook: hold the tint at strength s (0..1); nil returns to the normal decay
function RedEdge.hold(s: number?)
	held = s
	if s then
		RedEdge.pulse()
	end
end

function RedEdge.read(): any
	return { Count = RedEdge.Count, Strength = current, Visible = gui ~= nil and gui.Enabled, Age = os.clock() - startedAt }
end

return RedEdge
