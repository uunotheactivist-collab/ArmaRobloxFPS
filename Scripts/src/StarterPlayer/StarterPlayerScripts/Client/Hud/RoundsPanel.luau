--!strict
-- The Sniper's "5 /5 RDS" panel (sniper2.mp4 frames 296-346; ReferenceAnalysis/Sniper/Sniper_Analysis.md H2): a small
-- dark translucent box with a thin grey outline, a large round count, a small "/<capacity> RDS" and a white bar along the
-- bottom, riding on the weapon's left side (it moves with the rifle). Config: Config.Weapons.<Id>.Hud.RoundsPanel.
-- Pure presentation: it renders the count and the screen anchor it is given (Client.WeaponController passes a read-only
-- view of the server-corrected ammunition and the projected rig point) and owns no ammunition state.

local RoundsPanel = {}
RoundsPanel.__index = RoundsPanel

export type View = { alpha: number, rounds: number, capacity: number, anchor: Vector2?, viewport: Vector2 }
export type RoundsPanel = typeof(setmetatable(
	{} :: { Cfg: any, Frame: Frame, Big: TextLabel, Small: TextLabel, Bar: Frame, Fill: Frame, Stroke: UIStroke, Alpha: number },
	RoundsPanel
))

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function RoundsPanel.new(parent: Instance, cfg: any): RoundsPanel
	local f = Instance.new("Frame")
	f.Name = "RoundsPanel"
	f.AnchorPoint = Vector2.new(1, 0.5) -- right edge at the anchor point, centred on it
	f.BackgroundColor3 = rgb(cfg.Background)
	f.BorderSizePixel = 0
	f.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(cfg.Border)
	stroke.Thickness = 1
	stroke.Parent = f
	local function text(name: string): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Code
		t.TextColor3 = rgb(cfg.TextColor)
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextYAlignment = Enum.TextYAlignment.Center
		t.Parent = f
		return t
	end
	local big = text("Rounds")
	local small = text("Capacity")
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Parent = f
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = rgb(cfg.TextColor)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	f.Parent = parent
	return setmetatable({ Cfg = cfg, Frame = f, Big = big, Small = small, Bar = bar, Fill = fill, Stroke = stroke, Alpha = 0 },
		RoundsPanel)
end

-- Size everything for the current screen (the footage's pixels are at 720 px height).
function RoundsPanel.Layout(self: RoundsPanel, viewport: Vector2)
	local cfg = self.Cfg
	local k = viewport.Y / 720
	local w, h = cfg.SizePx[1] * k, cfg.SizePx[2] * k
	self.Frame.Size = UDim2.fromOffset(w, h)
	self.Big.TextSize = math.max(8, math.floor(cfg.BigTextPx * k * 1.25 + 0.5))
	self.Big.Position = UDim2.fromOffset(6 * k, 3 * k)
	self.Big.Size = UDim2.fromOffset(w * 0.35, h - 10 * k)
	self.Small.TextSize = math.max(6, math.floor(cfg.SmallTextPx * k * 1.25 + 0.5))
	self.Small.Position = UDim2.fromOffset(w * 0.45, 3 * k)
	self.Small.Size = UDim2.fromOffset(w * 0.5, h - 10 * k)
	self.Bar.Position = UDim2.fromOffset(4 * k, h - 6 * k)
	self.Bar.Size = UDim2.fromOffset(w - 8 * k, math.max(1, cfg.BarHeightPx * k))
end

function RoundsPanel.Render(self: RoundsPanel, view: View)
	local cfg = self.Cfg
	local a = math.clamp(view.alpha, 0, 1)
	self.Alpha = a
	local show = a > 0.001 and view.anchor ~= nil
	self.Frame.Visible = show
	if not show then
		return
	end
	local anchor = view.anchor :: Vector2
	self.Frame.Position = UDim2.fromOffset(anchor.X, anchor.Y)
	self.Frame.BackgroundTransparency = 1 - (1 - cfg.BackgroundTransparency) * a
	self.Stroke.Transparency = 1 - a
	self.Big.TextTransparency = 1 - a
	self.Small.TextTransparency = 1 - a
	self.Fill.BackgroundTransparency = 1 - a
	self.Big.Text = tostring(view.rounds)
	self.Small.Text = string.format("/%d %s", view.capacity, cfg.Suffix)
	self.Fill.Size = UDim2.fromScale(math.clamp(view.rounds / math.max(1, view.capacity), 0, 1), 1)
end

function RoundsPanel.State(self: RoundsPanel): any
	return {
		visible = self.Frame.Visible,
		alpha = self.Alpha,
		rounds = self.Big.Text,
		capacity = self.Small.Text,
		position = self.Frame.AbsolutePosition,
		size = self.Frame.AbsoluteSize,
	}
end

return RoundsPanel
