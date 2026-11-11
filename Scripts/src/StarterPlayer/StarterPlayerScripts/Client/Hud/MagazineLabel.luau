--!strict
-- The one HUD element visible in the M4 reference: a small grey centred label "[TAB] 5.56 MAG" that appears once a
-- reload has discarded a magazine and gains " +N" for each further discarded magazine (frames 344 / 486 / 672 of
-- the footage; ReferenceAnalysis/M4/M4_HUD_Analysis.md). Position, width and colour come from Config.Weapons.<Id>.Hud.
-- Screen-fixed: it does not sway, fade or animate (every change in the footage is instant).
-- Pure presentation: it renders the count it is given and owns no ammunition state.

local TextService = game:GetService("TextService")

local MagazineLabel = {}
MagazineLabel.__index = MagazineLabel

export type View = { visible: boolean, dropped: number }
export type MagazineLabel = typeof(setmetatable(
	{} :: { Cfg: any, Label: TextLabel, Font: Enum.Font, Text: string? },
	MagazineLabel
))

function MagazineLabel.new(parent: Instance, cfg: any): MagazineLabel
	local font = (Enum.Font :: any)[cfg.Font] :: Enum.Font
	local label = Instance.new("TextLabel")
	label.Name = "MagazineLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = font
	label.TextColor3 = Color3.fromRGB(cfg.Color[1], cfg.Color[2], cfg.Color[3])
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.Text = ""
	label.Visible = false
	label.Parent = parent
	return setmetatable({ Cfg = cfg, Label = label, Font = font, Text = nil }, MagazineLabel)
end

-- Size and place the label for the current screen. The base text's ink is WidthOfScreenHeight of the screen height
-- wide (measured on the footage). Text width doesn't scale linearly at small sizes, so the integer TextSize whose
-- real rendered width (TextBounds x InkFraction) is closest is chosen.
function MagazineLabel.Layout(self: MagazineLabel, viewport: Vector2)
	local cfg = self.Cfg
	local target = cfg.WidthOfScreenHeight * viewport.Y
	local size, err = 6, math.huge
	for s = 6, 96 do
		local w = TextService:GetTextSize(cfg.BaseText, s, self.Font, Vector2.new(1e5, 1e5)).X * cfg.InkFraction
		if math.abs(w - target) < err then
			size, err = s, math.abs(w - target)
		end
	end
	self.Label.TextSize = size
	self.Label.Size = UDim2.fromOffset(math.ceil(size * 12), math.ceil(size * 1.4))
	self.Label.Position = UDim2.fromScale(cfg.CentreX, 0.5 + cfg.CentreYFromMiddle)
end

function MagazineLabel.Render(self: MagazineLabel, view: View)
	local cfg = self.Cfg
	local text: string? = nil
	if view.visible and view.dropped >= cfg.MinDropped then
		-- Only weapons whose footage shows a count have a CountSuffix (M4). Without one (AK) the text never changes.
		text = cfg.BaseText
			.. (if cfg.CountSuffix and view.dropped > cfg.MinDropped then string.format(cfg.CountSuffix, view.dropped - cfg.MinDropped) else "")
	end
	if text ~= self.Text then
		self.Text = text
		self.Label.Text = text or ""
		self.Label.Visible = text ~= nil
	end
end

return MagazineLabel
