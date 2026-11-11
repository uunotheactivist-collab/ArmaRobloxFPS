--!strict
-- Production weapon HUD (client presentation only). Built from what the reference footage shows and nothing more:
-- for the M4 that is a single element, the magazine label (MagazineLabel). There is deliberately no round counter,
-- crosshair, hit marker or reload indicator - none appears in the footage (ReferenceAnalysis/M4/M4_HUD_Analysis.md).
-- Sniper slice: the elements a weapon has are the ones its config lists (all optional; every earlier weapon lists only
-- the MagazineLabel, so it is unchanged): Hud.MagazineLabel, Hud.RoundsPanel ("5 /5 RDS", Client.Hud.RoundsPanel),
-- Hud.ZoomLabel (the scope's "9x" label, Client.Hud.ZoomLabel). The Sniper's footage has no magazine label.
--
-- Data flow: Client.WeaponController passes a read-only view of the weapon state each frame
-- ({ visible, dropped } from FireController.Ammo, which the server corrects through WeaponState; the Sniper adds the
-- panel's alpha, round count and projected anchor). The HUD never writes ammunition, so it can't become a second
-- source of truth.
-- One ScreenGui per weapon HUD ("<Id>Hud"), created once (a stale copy is replaced), kept across respawns
-- (ResetOnSpawn = false) and hidden whenever the weapon is not equipped or the player is dead.

local Players = game:GetService("Players")

local MagazineLabel = require(script.Parent:WaitForChild("MagazineLabel"))
local RoundsPanel = require(script.Parent:WaitForChild("RoundsPanel"))
local ZoomLabel = require(script.Parent:WaitForChild("ZoomLabel"))

local WeaponHud = {}
WeaponHud.__index = WeaponHud

export type View = { visible: boolean, dropped: number, panel: RoundsPanel.View? }
export type WeaponHud = typeof(setmetatable(
	{} :: {
		Gui: ScreenGui,
		Label: MagazineLabel.MagazineLabel?,
		Panel: RoundsPanel.RoundsPanel?,
		Zoom: ZoomLabel.ZoomLabel?,
		Viewport: Vector2,
	},
	WeaponHud
))

function WeaponHud.new(cfg: any): WeaponHud
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local name = cfg.Id .. "Hud"
	local stale = playerGui:FindFirstChild(name)
	if stale then
		stale:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- positions are fractions of the full screen, whose centre is the camera centre
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
	gui.Parent = playerGui
	local hud = cfg.Hud or {}
	local self = setmetatable({
		Gui = gui,
		Label = if hud.MagazineLabel then MagazineLabel.new(gui, hud.MagazineLabel) else nil,
		Panel = if hud.RoundsPanel then RoundsPanel.new(gui, hud.RoundsPanel) else nil,
		Zoom = if hud.ZoomLabel then ZoomLabel.new(gui, hud.ZoomLabel) else nil,
		Viewport = Vector2.zero,
	}, WeaponHud)
	return self
end

-- view: { visible = equipped and alive, dropped = number of discarded magazines, panel = rounds panel view (Sniper) }
function WeaponHud.Update(self: WeaponHud, view: View)
	local viewport = workspace.CurrentCamera.ViewportSize
	if viewport ~= self.Viewport then
		self.Viewport = viewport
		if self.Label then
			self.Label:Layout(viewport)
		end
		if self.Panel then
			self.Panel:Layout(viewport)
		end
	end
	if self.Label then
		self.Label:Render(view)
	end
	if self.Panel then
		local p = view.panel
		self.Panel:Render(if view.visible and p then p else { alpha = 0, rounds = 0, capacity = 0, anchor = nil, viewport = viewport })
	end
	if self.Zoom and not view.visible then
		self.Zoom:Hide()
	end
end

-- The scope's zoom label (weapons whose config has Hud.ZoomLabel).
function WeaponHud.ShowZoom(self: WeaponHud, text: string)
	if self.Zoom then
		self.Zoom:Show(text)
	end
end

function WeaponHud.State(self: WeaponHud): any
	local copies = 0
	for _, c in (self.Gui.Parent :: Instance):GetChildren() do
		if c.Name == self.Gui.Name then
			copies += 1
		end
	end
	local out: any = {
		guiCopies = copies,
		labelCount = #self.Gui:GetChildren(),
		viewport = self.Viewport,
	}
	local label = self.Label
	if label then
		local l = label.Label
		out.visible = l.Visible
		out.text = l.Text
		out.textSize = l.TextSize
		out.textBounds = l.TextBounds
		out.centre = l.AbsolutePosition + l.AbsoluteSize / 2
	else
		out.visible = false
	end
	if self.Panel then
		out.panel = self.Panel:State()
	end
	if self.Zoom then
		out.zoom = self.Zoom:State()
	end
	return out
end

return WeaponHud
