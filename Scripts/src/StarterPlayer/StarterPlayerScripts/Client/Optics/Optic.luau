--!strict
-- Optics framework (client presentation only; ReferenceAnalysis/Optics/Optics_Analysis.md).
--
-- One Optic per weapon that carries one (Config.Weapons.<Id>.Optic -> Config.Optics.<Optic>). It is built on the
-- weapon's viewmodel rig and is three separate things:
--   housing : the optic body / mount meshes (Shared.Viewmodel.ProceduralMesh recipes), riding on the Weapon bone;
--   lens    : a glass part at the ocular, on the Weapon bone, carrying the render layer (Client.Optics.ScopeView);
--   reticle : drawn in the lens on the optical axis (ScopeView), so it moves with the optic, never fixed to the screen.
--
-- Kinds:
--   "Magnified" : picture-in-picture. The main camera is untouched (its FOV included); the lens shows the scene
--                 from a separate ScopeCamera that lies on the optical axis at the eye and looks along it, with a
--                 field of view set every frame so that the lens image is Magnification x the unscoped view:
--                 tan(fov / 2) = tan(beta) / M, beta = half the angle the lens subtends at the eye.
--   "Reflex"    : red dot / holographic window, Magnification 1: no lens picture; a reticle at infinity is placed
--                 where the eye-to-axis line crosses the window (as the accepted M4 HoloReticle). Supported by the
--                 framework, not used by any weapon in this slice.
--
-- Optional per-optic capabilities (Sniper slice; an optic without these fields behaves exactly as before):
--   def.Zoom = { Levels, DefaultIndex, Wrap, ChangeTime, LabelFormat }: variable magnification. StepZoom(dir) moves
--     one level (wrapping), the picture's magnification follows over ChangeTime; the level persists across ADS.
--   def.Reticle.ScalesWithZoom: first-focal-plane reticle, drawn (level / default level) times its design size.
--   def.Lens.EyeBox.ObjectiveDiameter: exit pupil = objective / magnification (instead of the fixed ExitPupilRadius).
--
-- Order each frame (Client.WeaponController, RenderPriority.Camera + 2): movement camera layer (Camera + 1) ->
-- weapon offsets (sway / recoil climb / shake) on the camera -> viewmodel rig update -> Optic:Update. The optic only
-- READS the camera and the rig: it never writes workspace.CurrentCamera, never changes recoil and never touches the
-- shot (shots keep leaving from the camera centre: Client.WeaponController / Server.WeaponServer).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProceduralMesh = require(Shared:WaitForChild("Viewmodel"):WaitForChild("ProceduralMesh"))
local ScopeView = require(script.Parent:WaitForChild("ScopeView"))
local SceneMirror = require(script.Parent:WaitForChild("SceneMirror"))

local STUD = 0.28

local Optic = {}
Optic.__index = Optic

export type Optic = typeof(setmetatable(
	{} :: {
		Def: any,
		Rig: any,
		Housing: { BasePart },
		Lens: BasePart,
		LensOffset: CFrame,
		LensRadius: number,
		IdealEyeDistance: number,
		View: any,
		Mirror: any,
		Active: boolean,
		Live: boolean,
		Last: any,
		Dot: BasePart?,
		Window: any,
		ZoomIndex: number,
		ZoomFrom: number,
		ZoomTo: number,
		ZoomAt: number,
		ReticleScale: number,
	},
	Optic
))

-- Adds a part to the rig on a bone, so ViewmodelRig:Update moves it with the weapon (one BulkMoveTo).
local function attach(rig: any, part: BasePart, bone: string, offset: CFrame)
	part.Parent = rig.Model
	table.insert(rig.Parts, part)
	table.insert(rig.PartBones, bone)
	table.insert(rig.PartOffsets, offset)
end

function Optic.new(def: any, rig: any, data: any, weaponId: string): Optic
	local housing = {}
	for name, spec in def.Housing or {} do
		local part, centre = ProceduralMesh.buildPart(spec.Recipes, data.PartOrigins.Weapon)
		local mat = data.Materials[spec.Material]
		part.Name = "Optic_" .. name
		part.Color = Color3.fromRGB(mat.Color[1], mat.Color[2], mat.Color[3])
		part.Material = (Enum.Material :: any)[mat.Material]
		part.Transparency = mat.Transparency
		attach(rig, part, "Weapon", CFrame.new(centre))
		table.insert(housing, part)
	end
	-- The lens glass (at the ocular for a magnified optic; a reflex optic's window glass belongs to its housing).
	local layout = def.Layout or { EyepieceRearY = 0, LensRecess = 0, AxisHeight = 0, LensDiameter = 0.01, EyeRelief = 0 }
	local lensY = layout.EyepieceRearY + layout.LensRecess -- recipe space, metres (+Y = muzzle)
	local lensCentre = Vector3.new(0, layout.AxisHeight, -lensY) / STUD -- weapon bone space, studs
	local d = layout.LensDiameter / STUD
	local lens = Instance.new("Part")
	lens.Name = "Optic_Lens"
	lens.Size = Vector3.new(d, d, 0.002)
	lens.Anchored = true
	lens.CanCollide = false
	lens.CanQuery = false
	lens.CanTouch = false
	lens.CastShadow = false
	lens.Transparency = 1 -- the SurfaceGui draws the glass / picture
	local lensOffset = CFrame.new(lensCentre)
	attach(rig, lens, "Weapon", lensOffset)

	local self = setmetatable({
		Def = def,
		Rig = rig,
		Housing = housing,
		Lens = lens,
		LensOffset = lensOffset,
		LensRadius = d / 2,
		IdealEyeDistance = (layout.EyeRelief + layout.LensRecess) / STUD,
		View = nil :: any,
		Mirror = nil :: any,
		Active = false,
		Live = false,
		Last = {},
		Dot = nil :: BasePart?,
		Window = nil :: any,
		ZoomIndex = if def.Zoom then def.Zoom.DefaultIndex else 0,
		ZoomFrom = def.Magnification or 1,
		ZoomTo = def.Magnification or 1,
		ZoomAt = -math.huge,
		ReticleScale = 1,
	}, Optic)
	if def.Kind == "Magnified" then
		self.View = ScopeView.new(def, lens, weaponId .. "Optic")
		self.View:SetEnabled(false)
		self.Mirror = SceneMirror.new(self.View.WorldModel, def.Render)
	elseif def.Kind == "Reflex" then
		-- Window (recipe metres): Centre {x, y, z}, HalfWidth, HalfHeight; the dot is placed per frame in Update.
		local w = def.Window
		self.Window = {
			Centre = Vector3.new(w.Centre[1], w.Centre[3], -w.Centre[2]) / STUD,
			HalfWidth = w.HalfWidth / STUD,
			HalfHeight = w.HalfHeight / STUD,
		}
		local dot = Instance.new("Part")
		dot.Name = "Optic_ReflexDot"
		local s = def.Reticle.Dot.Diameter / STUD
		dot.Size = Vector3.new(s, s, 0.002)
		dot.Shape = Enum.PartType.Block
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(def.Reticle.Dot.Color[1], def.Reticle.Dot.Color[2], def.Reticle.Dot.Color[3])
		dot.Anchored, dot.CanCollide, dot.CanQuery, dot.CanTouch, dot.CastShadow = true, false, false, false, false
		dot.Transparency = 1
		dot.Parent = rig.Model
		self.Dot = dot
	end
	return self
end

-- Equipped and alive (Active) or put away (the render layer is disabled and the mirror stops syncing).
function Optic.SetActive(self: Optic, active: boolean)
	if active == self.Active then
		return
	end
	self.Active = active
	if self.View then
		self.View:SetEnabled(active)
		if not active then
			self.View:SetLive(false)
			self.Live = false
		end
	end
	if active and self.Mirror then
		self.Mirror:Start() -- first use builds the copy of the world (time-sliced); later calls do nothing
	end
end

-- Variable zoom (def.Zoom only): one level up (dir > 0) or down, wrapping as the footage (12x -> 3x). Returns the new
-- level (the label value) or nil when the optic has no zoom.
function Optic.StepZoom(self: Optic, dir: number, now: number?): number?
	local z = self.Def.Zoom
	if not z then
		return nil
	end
	local n = #z.Levels
	local i = self.ZoomIndex + (if dir > 0 then 1 else -1)
	if i > n then
		i = if z.Wrap then 1 else n
	elseif i < 1 then
		i = if z.Wrap then n else 1
	end
	self.ZoomFrom = self:Magnification(now)
	self.ZoomIndex = i
	self.ZoomTo = z.Levels[i]
	self.ZoomAt = now or os.clock()
	return z.Levels[i]
end

-- Current picture magnification (eased over Zoom.ChangeTime after a change; the fixed def.Magnification otherwise).
function Optic.Magnification(self: Optic, now: number?): number
	local z = self.Def.Zoom
	if not z then
		return self.Def.Magnification
	end
	local u = math.clamp(((now or os.clock()) - self.ZoomAt) / math.max(z.ChangeTime, 1e-3), 0, 1)
	return self.ZoomFrom + (self.ZoomTo - self.ZoomFrom) * u
end

-- The zoom level shown on the label (nil without a zoom).
function Optic.ZoomLevel(self: Optic): number?
	local z = self.Def.Zoom
	return if z then z.Levels[self.ZoomIndex] else nil
end

-- After the rig update. camera: the player's camera (read only); aimAlpha 0 hip .. 1 scoped; state: OpticAim state.
function Optic.Update(self: Optic, camera: Camera, aimAlpha: number, state: string)
	local t0 = os.clock()
	local def = self.Def
	local weapon: CFrame = self.Rig.World.Weapon
	local lensCF = weapon * self.LensOffset
	local eye = camera.CFrame.Position
	local last = self.Last
	last.State, last.Alpha, last.LensCF, last.Eye = state, aimAlpha, lensCF, eye
	if def.Kind == "Reflex" then
		-- Reticle at infinity: where the line from the eye along the optic axis crosses the window; hidden outside it.
		local win, dot = self.Window, self.Dot :: BasePart
		local axis = weapon.LookVector
		local centre = weapon * win.Centre
		local p = eye + axis * (centre - eye):Dot(axis)
		local q = weapon:PointToObjectSpace(p) - win.Centre
		local inside = math.abs(q.X) <= win.HalfWidth and math.abs(q.Y) <= win.HalfHeight
		dot.CFrame = weapon.Rotation + p
		dot.Transparency = if inside then 0 else 1
		last.DotVisible, last.DotPosition = inside, p
		last.UpdateMs = (os.clock() - t0) * 1000
		return
	elseif def.Kind ~= "Magnified" then
		return
	end
	local live = aimAlpha > 0
	if live ~= self.Live then
		self.Live = live
		self.View:SetLive(live)
	end
	if not live then
		last.UpdateMs = (os.clock() - t0) * 1000
		return
	end
	-- Scope camera: on the optical axis at the point nearest the eye, looking along the axis, rolled with the weapon.
	local axis = weapon.LookVector
	local along = (eye - lensCF.Position):Dot(axis)
	local camPos = lensCF.Position + axis * along
	local scopeCF = CFrame.fromMatrix(camPos, weapon.RightVector, weapon.UpVector)
	local dist = (lensCF.Position - eye).Magnitude
	local tanBeta = self.LensRadius / math.max(dist, 1e-3)
	local mag = if def.Zoom then self:Magnification(t0) else def.Magnification
	local fov = math.deg(2 * math.atan(tanBeta / mag))
	self.View:SetCamera(scopeCF, fov)
	self.View:SetLighting(-Lighting:GetSunDirection())
	if def.Reticle.ScalesWithZoom and def.Zoom then
		local k = mag / def.Zoom.Levels[def.Zoom.DefaultIndex]
		if math.abs(k - self.ReticleScale) > 1e-4 then
			self.ReticleScale = k
			self.View:SetReticleScale(k)
		end
	end
	-- Eye box: the eye's offset from the axis (lens frame: +x right, +y up, +z toward the eye).
	local eb = def.Lens.EyeBox
	local rel = lensCF:PointToObjectSpace(eye)
	local pupil = (if eb.ObjectiveDiameter then eb.ObjectiveDiameter / (2 * mag) else eb.ExitPupilRadius) / STUD
	local cx = -rel.X / pupil * eb.ShiftGain
	local cy = -rel.Y / pupil * eb.ShiftGain
	local depthErr = math.abs(rel.Z - self.IdealEyeDistance) * STUD -- metres
	local radius = math.max(eb.MinRadius, eb.ClearRadius * (1 - eb.DepthShrink * depthErr / eb.DepthTolerance))
	if rel.Z <= 0 then
		radius = eb.MinRadius -- eye in front of the glass (cannot see through): dark
		cx, cy = 10, 10
	end
	self.View:SetShadow(cx, cy, radius)
	self.Mirror:Sync()
	last.ScopeCF, last.ScopeFov, last.EyeDistance, last.Shadow = scopeCF, fov, dist, { cx, cy, radius }
	last.Magnification = mag
	last.UpdateMs = (os.clock() - t0) * 1000
end

-- Read-only view for the Studio tests (Client.WeaponController debug hook "optic").
function Optic.Debug(self: Optic, camera: Camera): any
	local last = self.Last
	local out: any = {
		kind = self.Def.Kind,
		active = self.Active,
		live = self.Live,
		state = last.State,
		alpha = last.Alpha,
		magnification = if self.Def.Zoom then last.Magnification or self.Def.Magnification else self.Def.Magnification,
		zoomLevel = self:ZoomLevel(),
		reticleScale = self.ReticleScale,
		scopeFov = last.ScopeFov,
		eyeDistance = last.EyeDistance,
		shadow = last.Shadow,
		updateMs = last.UpdateMs,
		lensDiameter = self.LensRadius * 2,
		housingParts = #self.Housing,
		cameraFov = camera.FieldOfView,
	}
	if last.LensCF then
		local lensCF: CFrame = last.LensCF
		out.lensCF = lensCF
		-- lens on screen: centre and diameter (pixels) from the projected rim points
		local c, onC = camera:WorldToViewportPoint(lensCF.Position)
		local l = camera:WorldToViewportPoint(lensCF * Vector3.new(-self.LensRadius, 0, 0))
		local r = camera:WorldToViewportPoint(lensCF * Vector3.new(self.LensRadius, 0, 0))
		local u = camera:WorldToViewportPoint(lensCF * Vector3.new(0, self.LensRadius, 0))
		local b = camera:WorldToViewportPoint(lensCF * Vector3.new(0, -self.LensRadius, 0))
		local function d2(p: Vector3, q: Vector3): number
			return (Vector2.new(p.X, p.Y) - Vector2.new(q.X, q.Y)).Magnitude
		end
		out.lensScreen = { x = c.X, y = c.Y, onScreen = onC, w = d2(r, l), h = d2(u, b) }
		-- where the optical axis points at infinity, on the main screen
		local far = camera:WorldToViewportPoint(lensCF.Position + lensCF.LookVector * 10000)
		out.axisScreen = { x = far.X, y = far.Y }
		out.viewport = camera.ViewportSize
	end
	if last.ScopeCF then
		out.scopeCF = last.ScopeCF
	end
	if self.Mirror then
		out.mirror = table.clone(self.Mirror.Stats)
		out.mirrorStarted = self.Mirror.Started
	end
	if self.View then
		out.gui = {
			enabled = self.View.Gui.Enabled,
			pictureVisible = self.View.Picture.Visible,
			reticleVisible = self.View.Reticle.Visible,
			glassVisible = self.View.Glass.Visible,
			currentCameraIsScope = workspace.CurrentCamera == self.View.Camera,
			adornee = self.View.Gui.Adornee == self.Lens,
		}
	end
	return out
end

return Optic
