--!strict
-- First-person viewmodel rig built from generated weapon data (Shared.Assets.Weapons.<Id>ViewmodelData).
--
-- Bones: Root (= camera CFrame) -> Weapon -> { Magazine, ChargingHandle }; Root -> LeftArm.
-- Optional (Glock slice): Weapon -> RightArm, a second block arm whose hand holds the grip; it is only built when the
-- weapon's data has a RightArm joint, and it follows the weapon (recoil, aim, reloads) without a pose of its own.
-- The rest pose is the hip idle fitted to the reference footage, so an empty pose = hip idle.
-- Parts are anchored and moved together with workspace:BulkMoveTo every frame (no physics joints), so the rig
-- behaves the same under the camera, in any place, and without uploaded animation assets.

local ProceduralMesh = require(script.Parent:WaitForChild("ProceduralMesh"))

local IDENTITY = CFrame.identity
local BONE_ORDER = { "Weapon", "RightArm", "LeftArm", "Magazine", "ChargingHandle" } -- parents before children

local ViewmodelRig = {}
ViewmodelRig.__index = ViewmodelRig

export type Joint = { Parent: string, C0: CFrame }
export type Rig = typeof(setmetatable(
	{} :: {
		Model: Model,
		Joints: { [string]: Joint },
		Parts: { BasePart },
		PartBones: { string },
		PartOffsets: { CFrame },
		Points: { [string]: Vector3 },
		World: { [string]: CFrame },
		CFrames: { CFrame },
	},
	ViewmodelRig
))

local function cf(t: { number }): CFrame
	return CFrame.new(table.unpack(t))
end

function ViewmodelRig.new(data: any, name: string): Rig
	local model = Instance.new("Model")
	model.Name = name

	local joints = {}
	for jointName, j in data.Joints do
		joints[jointName] = { Parent = j.Parent, C0 = cf(j.C0) }
	end

	local parts, bones, offsets = {}, {}, {}
	for _, spec in data.Parts do
		local part: BasePart
		local offset: Vector3
		if spec.Kind == "Block" then
			local p = Instance.new("Part")
			p.Size = Vector3.new(table.unpack(spec.Size))
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			part, offset = p, Vector3.new(table.unpack(spec.Offset))
		else
			part, offset = ProceduralMesh.buildPart(spec.Recipes, data.PartOrigins[spec.Bone])
		end
		local mat = data.Materials[spec.Material]
		part.Name = spec.Name
		part.Color = Color3.fromRGB(mat.Color[1], mat.Color[2], mat.Color[3])
		part.Material = (Enum.Material :: any)[mat.Material]
		part.Transparency = mat.Transparency
		part.Parent = model
		table.insert(parts, part)
		table.insert(bones, spec.Bone)
		table.insert(offsets, CFrame.new(offset))
	end

	local points = {}
	for pointName, p in data.Points do
		points[pointName] = Vector3.new(p[1], p[2], p[3])
	end

	return setmetatable({
		Model = model,
		Joints = joints,
		Parts = parts,
		PartBones = bones,
		PartOffsets = offsets,
		Points = points,
		World = {},
		CFrames = table.create(#parts),
	}, ViewmodelRig)
end

-- root: the CFrame the rig hangs from (the camera, plus any presentation offset).
-- transforms: per-bone pose relative to the rest pose (missing = rest).
function ViewmodelRig.Update(self: Rig, root: CFrame, transforms: { [string]: CFrame })
	local world = self.World
	world.Root = root
	for _, bone in BONE_ORDER do
		local j = self.Joints[bone]
		if j then
			world[bone] = world[j.Parent] * j.C0 * (transforms[bone] or IDENTITY)
		end
	end
	for i, bone in self.PartBones do
		self.CFrames[i] = world[bone] * self.PartOffsets[i]
	end
	workspace:BulkMoveTo(self.Parts, self.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- World position of a named point on the weapon (Muzzle, Ejection, SightGlass...) after the last Update.
function ViewmodelRig.GetPoint(self: Rig, pointName: string): Vector3
	return (self.World.Weapon or self.World.Root) * self.Points[pointName]
end

return ViewmodelRig
