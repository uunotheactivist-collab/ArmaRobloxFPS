--!strict
-- The scope's zoom label ("9x", "12x", "3x"; sniper2.mp4 frames 540 / 553 / 635; ReferenceAnalysis/Sniper H1): the
-- shared bottom-left transient-text style ("CROUCHED", "BIPOD DOWN"), shown when the zoom level changes, solid, then a
-- short fade. Config: Config.Weapons.<Id>.Hud.ZoomLabel. Presentation only: it shows the text it is given.

local TweenService = game:GetService("TweenService")

local ZoomLabel = {}
ZoomLabel.__index = ZoomLabel

export type ZoomLabel = typeof(setmetatable(
	{} :: { Cfg: any, Label: TextLabel, Token: number, ShownAt: number, Fade: Tween? },
	ZoomLabel
))

function ZoomLabel.new(parent: Instance, cfg: any): ZoomLabel
	local t = Instance.new("TextLabel")
	t.Name = "ZoomLabel"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = cfg.Position
	t.Size = UDim2.fromOffset(120, cfg.TextSize + 4)
	t.Font = Enum.Font.Code
	t.TextSize = cfg.TextSize
	t.TextColor3 = cfg.Color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTransparency = 1
	t.Text = ""
	t.Parent = parent
	return setmetatable({ Cfg = cfg, Label = t, Token = 0, ShownAt = -math.huge, Fade = nil }, ZoomLabel)
end

function ZoomLabel.Show(self: ZoomLabel, text: string)
	self.Token += 1
	local mine = self.Token
	self.ShownAt = os.clock()
	if self.Fade then
		self.Fade:Cancel()
		self.Fade = nil
	end
	self.Label.Text = text
	self.Label.TextTransparency = 0
	task.delay(self.Cfg.SolidSeconds, function()
		if self.Token == mine then
			local tw = TweenService:Create(self.Label, TweenInfo.new(self.Cfg.FadeSeconds, Enum.EasingStyle.Linear),
				{ TextTransparency = 1 })
			self.Fade = tw
			tw:Play()
		end
	end)
end

function ZoomLabel.Hide(self: ZoomLabel)
	self.Token += 1
	if self.Fade then
		self.Fade:Cancel()
		self.Fade = nil
	end
	self.Label.TextTransparency = 1
end

function ZoomLabel.State(self: ZoomLabel): any
	return { text = self.Label.Text, visible = self.Label.TextTransparency < 0.99, transparency = self.Label.TextTransparency,
		age = os.clock() - self.ShownAt }
end

return ZoomLabel
