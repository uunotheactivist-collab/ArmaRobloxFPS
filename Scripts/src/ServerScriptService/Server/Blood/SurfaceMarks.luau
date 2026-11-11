--!strict
-- BloodSurfaceMark (server): persistent blood on world surfaces (drops, splats, drag-trail smears).
-- Marks sit on small invisible patch parts laid on the surface. Each patch carries one SurfaceGui that many marks
-- share, so the part count stays low and huge faces (the Baseplate) still get sharp marks. Patches are lifted a little
-- off the surface, and each new one a little more, so nothing z-fights.
-- Persistence: nothing fades (none does in the footage). Budgets (Config.Blood.Marks): beyond MaxMarks / MaxPatches
-- the oldest goes first. A surface's patches go with it if it is destroyed. Only the server creates marks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))
local Canvas = require(script.Parent:WaitForChild("Canvas"))

local Marks = {}

type Patch = { Part: BasePart, Gui: SurfaceGui, Surface: BasePart, Normal: Vector3, Count: number }
type Mark = { Frame: Frame, Patch: Patch, Kind: string }

local patches: { Patch } = {}
local bySurface: { [BasePart]: { Patch } } = {}
local watched: { [BasePart]: RBXScriptConnection } = {}
local marks: { Mark } = {}
local rng = Random.new()
local layer = 0

function Marks.folder(): Folder
	local f = workspace:FindFirstChild("BloodMarks")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "BloodMarks"
	nf.Parent = workspace
	return nf
end

local function removePatch(p: Patch)
	for i = #marks, 1, -1 do
		if marks[i].Patch == p then
			table.remove(marks, i)
		end
	end
	local i = table.find(patches, p)
	if i then
		table.remove(patches, i)
	end
	local list = bySurface[p.Surface]
	if list then
		local j = table.find(list, p)
		if j then
			table.remove(list, j)
		end
		if #list == 0 then
			bySurface[p.Surface] = nil
			if watched[p.Surface] then
				watched[p.Surface]:Disconnect()
				watched[p.Surface] = nil
			end
		end
	end
	p.Part:Destroy()
end

local function newPatch(surface: BasePart, pos: Vector3, normal: Vector3): Patch
	local M = Config.Marks
	while #patches >= M.MaxPatches do
		removePatch(patches[1])
	end
	layer = layer % 10 + 1
	local part = Canvas.patch("BloodPatch", pos, normal, M.PatchStuds, M.Lift + layer * 0.002)
	local gui = Canvas.gui(part, Enum.NormalId.Top, "BloodMarks", M.PixelsPerStud)
	part.Parent = Marks.folder()
	local p: Patch = { Part = part, Gui = gui, Surface = surface, Normal = normal.Unit, Count = 0 }
	table.insert(patches, p)
	if not bySurface[surface] then
		bySurface[surface] = {}
		-- a destroyed surface takes its blood with it (no floating patches)
		watched[surface] = surface.Destroying:Connect(function()
			for _, q in table.clone(bySurface[surface] or {}) do
				removePatch(q)
			end
		end)
	end
	table.insert(bySurface[surface], p)
	return p
end

-- A patch on this surface whose plane and area hold a mark of radius r at pos.
local function findPatch(surface: BasePart, pos: Vector3, normal: Vector3, r: number): Patch?
	local half = Config.Marks.PatchStuds / 2 - r
	for _, p in bySurface[surface] or {} do
		if p.Normal:Dot(normal) > 0.98 then
			local rel = p.Part.CFrame:PointToObjectSpace(pos)
			if math.abs(rel.Y) < 0.15 and math.abs(rel.X) <= half and math.abs(rel.Z) <= half then
				return p
			end
		end
	end
	return nil
end

-- A floor point below pos (a surface facing up), ignoring the given instances, blood and characters.
function Marks.floorBelow(pos: Vector3, ignore: { Instance }): (BasePart?, Vector3?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	table.insert(list, Marks.folder())
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(pos + Vector3.new(0, 0.5, 0), Vector3.new(0, -40, 0), params)
	if not hit or hit.Normal.Y < 0.6 then
		return nil, nil, nil
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return nil, nil, nil -- landed on a character: no floor mark
	end
	return hit.Instance :: BasePart, hit.Position, hit.Normal
end

-- Place one mark: kind "drop" (round, maybe a short tail along `travel`), "splat" (blotchy, semi-transparent) or
-- "trail" (one mottled smear of a drag trail, Config.Trail).
function Marks.place(surface: BasePart, pos: Vector3, normal: Vector3, studs: number, kind: string, travel: Vector3?): boolean
	if not surface:IsDescendantOf(workspace) then
		return false
	end
	local M = Config.Marks
	local up = normal.Unit
	local p = findPatch(surface, pos, up, studs * 0.6) or newPatch(surface, pos, up)
	local uv, faceStuds = Canvas.uv(p.Part, Enum.NormalId.Top, pos)
	local isTrail = kind == "trail"
	local isDrop = kind ~= "splat" and not isTrail
	local tail: Vector2? = nil
	if (isDrop and travel and rng:NextNumber() < M.TailChance) or (isTrail and travel) then
		tail = Canvas.canvasDirection(p.Part, Enum.NormalId.Top, travel) -- a trail smear always reaches toward the next
	end
	local color = if isTrail then Config.Trail.Color:Lerp(Config.BloodDark, rng:NextNumber(0, 0.25))
		else Config.BloodDark:Lerp(Config.Blood, rng:NextNumber())
	local transparency = if isTrail then Config.Trail.Transparency elseif isDrop then M.DropTransparency else M.SplatTransparency
	local pieces = if isTrail then rng:NextInteger(Config.Trail.Pieces[1], Config.Trail.Pieces[2])
		elseif isDrop then 1
		else rng:NextInteger(3, 5)
	local frame = Canvas.blob(p.Gui, uv, faceStuds, studs, color, transparency, pieces, rng, tail)
	p.Count += 1
	table.insert(marks, { Frame = frame, Patch = p, Kind = kind })
	while #marks > M.MaxMarks do
		local m = table.remove(marks, 1) :: Mark
		m.Frame:Destroy()
		m.Patch.Count -= 1
		if m.Patch.Count <= 0 then
			removePatch(m.Patch)
		end
	end
	return true
end

-- Drag trail (called by Server.Blood.Trails while the server drags a wounded body): mottled smears on the floor every
-- SpacingStuds between two points, each about WidthStuds across, overlapping into one band. Returns the number placed.
function Marks.trail(from: Vector3, to: Vector3, ignore: { Instance }): number
	local T = Config.Trail
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local n = math.max(1, math.floor(d.Magnitude / T.SpacingStuds + 0.5))
	local side = if d.Magnitude > 1e-3 then Vector3.yAxis:Cross(d.Unit) else Vector3.xAxis
	local placed = 0
	for i = 1, n do
		local at = from:Lerp(to, i / n) + side * rng:NextNumber(-0.08, 0.08)
		local part, pos, normal = Marks.floorBelow(at, ignore)
		if part and pos and normal then
			if Marks.place(part, pos, normal, T.WidthStuds * rng:NextNumber(0.85, 1.15), "trail", d) then
				placed += 1
			end
		end
	end
	return placed
end

function Marks.stats(): any
	local drops, splats, trails = 0, 0, 0
	for _, m in marks do
		if m.Kind == "splat" then
			splats += 1
		elseif m.Kind == "trail" then
			trails += 1
		else
			drops += 1
		end
	end
	local list = {}
	for _, p in patches do
		table.insert(list, { Surface = p.Surface:GetFullName(), Position = p.Part.Position, Normal = p.Normal, Count = p.Count })
	end
	return { Marks = #marks, Drops = drops, Splats = splats, Trails = trails, Patches = #patches, PatchList = list }
end

function Marks.clear()
	for _, p in table.clone(patches) do
		removePatch(p)
	end
end

return Marks
