--!strict
-- Picture-in-picture render layer of a magnified optic (Client.Optics). Everything the eye sees IN the lens:
--
--   lens part (on the weapon, at the ocular glass) <- SurfaceGui (in PlayerGui, Adornee = lens part, its rear face)
--     Glass      : the dark glass shown when there is no picture (hip)
--     Picture    : ViewportFrame, round (UICorner), with its own ScopeCamera and the SceneMirror's WorldModel
--     Reticle    : the optic's reticle image, centred = on the optical axis
--     Shadow     : the eye-box shadow (a clear disc that moves / shrinks with the eye's position)
--     Highlight  : the bright spot at the lens upper-left
--     Mask       : rim colour outside the round lens
--
-- The ScopeCamera belongs to the ViewportFrame: it is never workspace.CurrentCamera, never touches the player's
-- camera, and is placed every frame by Client.Optics.Optic from the weapon's optical axis.
-- Roblox notes (measured in Studio, 2026-11-07): a ViewportFrame renders inside a SurfaceGui only when the SurfaceGui
-- sits in PlayerGui with an Adornee (parented under the part it stays blank); UICorner on the ViewportFrame clips it
-- round (a CanvasGroup does not). There is no API to render the real workspace a second time, so the picture shows a
-- mirrored copy of the world (Client.Optics.SceneMirror) - see ReferenceAnalysis/Optics/Optics_Analysis.md.

local Players = game:GetService("Players")

local LensImages = require(script.Parent:WaitForChild("LensImages"))

local ScopeView = {}
ScopeView.__index = ScopeView

export type ScopeView = typeof(setmetatable(
	{} :: {
		Def: any,
		Gui: SurfaceGui,
		Picture: ViewportFrame,
		Camera: Camera,
		WorldModel: WorldModel,
		Glass: Frame,
		Reticle: ImageLabel,
		Shadow: ImageLabel,
		Highlight: ImageLabel,
		Mask: ImageLabel,
		Images: { EditableImage },
		Live: boolean,
		N: number,
	},
	ScopeView
))

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function image(name: string, z: number, parent: Instance): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ZIndex = z
	l.Size = UDim2.fromScale(1, 1)
	l.ScaleType = Enum.ScaleType.Stretch
	l.Parent = parent
	return l
end

function ScopeView.new(def: any, lensPart: BasePart, guiName: string): ScopeView
	local lens = def.Lens
	local n = lens.CanvasPixels
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local stale = playerGui:FindFirstChild(guiName)
	if stale then
		stale:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = guiName
	gui.Adornee = lensPart
	gui.Face = Enum.NormalId.Back -- the weapon looks along -Z, so the rear face looks at the eye
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(n, n)
	gui.LightInfluence = 0 -- the lens picture is not re-lit by the world around the viewmodel
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.Size = UDim2.fromScale(1, 1)
	glass.BorderSizePixel = 0
	glass.BackgroundColor3 = rgb(lens.GlassColor)
	glass.BackgroundTransparency = lens.GlassTransparency
	glass.ZIndex = 1
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0.5, 0)
	gc.Parent = glass
	glass.Parent = gui

	local picture = Instance.new("ViewportFrame")
	picture.Name = "Picture"
	picture.Size = UDim2.fromScale(1, 1)
	picture.BorderSizePixel = 0
	picture.BackgroundColor3 = rgb(lens.Background)
	picture.BackgroundTransparency = 0
	picture.ImageColor3 = rgb(lens.Tint)
	picture.Ambient = rgb(lens.Ambient)
	picture.LightColor = rgb(lens.LightColor)
	picture.ZIndex = 2
	picture.Visible = false
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0.5, 0)
	pc.Parent = picture
	local camera = Instance.new("Camera")
	camera.Name = "ScopeCamera"
	camera.Parent = picture
	picture.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Name = "Mirror"
	world.Parent = picture
	picture.Parent = gui

	local images = {}
	local reticle = image("Reticle", 3, gui)
	local rImg = LensImages.reticle(def.Reticle)
	LensImages.show(reticle, rImg)
	table.insert(images, rImg)
	reticle.Visible = false

	local shadow = image("Shadow", 4, gui)
	local sImg = LensImages.hole(256, lens.EyeBox.Softness)
	LensImages.show(shadow, sImg)
	table.insert(images, sImg)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Visible = false
	-- Black beyond the image's edges, so the shadow layer is unbounded whatever the hole's size and position.
	for _, r in { { -10, -10, 10, 21 }, { 1, -10, 10, 21 }, { 0, -10, 1, 10 }, { 0, 1, 1, 10 } } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.ZIndex = 4
		f.Position = UDim2.fromScale(r[1], r[2])
		f.Size = UDim2.fromScale(r[3], r[4])
		f.Parent = shadow
	end

	local hl = lens.Highlight
	local highlight = image("Highlight", 5, gui)
	local hImg = LensImages.blob(128)
	LensImages.show(highlight, hImg)
	table.insert(images, hImg)
	highlight.AnchorPoint = Vector2.new(0.5, 0.5)
	highlight.Position = UDim2.fromScale(hl.CentreU, hl.CentreV)
	highlight.Size = UDim2.fromScale(2 * hl.Radius, 2 * hl.Radius)
	highlight.ImageTransparency = 1 - hl.Strength

	local mask = image("Mask", 6, gui)
	local mImg = LensImages.mask(n, lens.RimColor)
	LensImages.show(mask, mImg)
	table.insert(images, mImg)

	gui.Parent = playerGui
	return setmetatable({
		Def = def,
		Gui = gui,
		Picture = picture,
		Camera = camera,
		WorldModel = world,
		Glass = glass,
		Reticle = reticle,
		Shadow = shadow,
		Highlight = highlight,
		Mask = mask,
		Images = images,
		Live = false,
		N = n,
	}, ScopeView)
end

-- Live = the picture is rendered (aiming / scoped). Not live = dark glass only: no ViewportFrame render cost.
function ScopeView.SetLive(self: ScopeView, live: boolean)
	if live == self.Live then
		return
	end
	self.Live = live
	self.Picture.Visible = live
	self.Reticle.Visible = live
	self.Shadow.Visible = live
	self.Glass.Visible = not live
end

function ScopeView.SetEnabled(self: ScopeView, enabled: boolean)
	self.Gui.Enabled = enabled
end

-- cf: scope camera frame (looks along the optical axis); fovDeg: its vertical (= horizontal) field of view.
function ScopeView.SetCamera(self: ScopeView, cf: CFrame, fovDeg: number)
	self.Camera.CFrame = cf
	self.Camera.FieldOfView = fovDeg
end

-- Clear disc of the eye box: centre (cx, cy) and radius in lens radii (lens centre = 0, 0; +y = up).
function ScopeView.SetShadow(self: ScopeView, cx: number, cy: number, radius: number)
	local size = radius * 0.5 / LensImages.HOLE_FRACTION -- canvas fractions: hole radius = size * HOLE_FRACTION
	self.Shadow.Size = UDim2.fromScale(size, size)
	self.Shadow.Position = UDim2.fromScale(0.5 + cx * 0.5, 0.5 - cy * 0.5)
end

-- First-focal-plane reticles (optional, Sniper slice): the reticle image drawn k times its design size about the lens
-- centre (the lens mask and the canvas clip it). k = 1 keeps the accepted full-lens layout.
function ScopeView.SetReticleScale(self: ScopeView, k: number)
	local r = self.Reticle
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.Size = UDim2.fromScale(k, k)
end

function ScopeView.SetLighting(self: ScopeView, direction: Vector3)
	self.Picture.LightDirection = direction
end

function ScopeView.Destroy(self: ScopeView)
	self.Gui:Destroy()
	for _, img in self.Images do
		img:Destroy()
	end
end

return ScopeView
