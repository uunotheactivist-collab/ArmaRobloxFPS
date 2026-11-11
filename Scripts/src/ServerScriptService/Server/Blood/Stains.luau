--!strict
-- Body stains (server): a blood patch at a wound, drawn on a SurfaceGui on the hit part's own face. No extra parts and
-- no physics: it moves with the part through the fall and the active ragdoll, and goes when the body is destroyed.
-- Stains stay after death [confirmed]. Budget: Config.Blood.Stains.MaxPerBody (the oldest on that body goes first).
-- Works on box parts (the test bots). On mesh parts the SurfaceGui maps to the part's bounding box, so a stain can sit
-- off the visible surface (players are not integrated yet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))
local Canvas = require(script.Parent:WaitForChild("Canvas"))

local Stains = {}

local byBody: { [Model]: { Frame } } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()

function Stains.add(part: BasePart, pos: Vector3, normal: Vector3): Frame?
	if not part:IsDescendantOf(workspace) then
		return nil
	end
	local S = Config.Stains
	local face = Canvas.faceOf(part, normal)
	local uv, faceStuds = Canvas.uv(part, face, pos)
	local gui = Canvas.gui(part, face, "BloodStain", S.PixelsPerStud)
	local color = Config.BloodDark:Lerp(Config.Blood, rng:NextNumber(0.3, 1))
	local frame = Canvas.blob(gui, uv, faceStuds, rng:NextNumber(S.Size[1], S.Size[2]), color, S.Transparency, 3, rng, nil)
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		local list = byBody[model]
		if not list then
			list = {}
			byBody[model] = list
		end
		table.insert(list, frame)
		while #list > S.MaxPerBody do
			local old = table.remove(list, 1) :: Frame
			old:Destroy()
		end
	end
	return frame
end

-- Stain frames on one body (for tests).
function Stains.count(model: Model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") and string.sub(d.Name, 1, 10) == "BloodStain" then
			for _, c in d:GetChildren() do
				if c:IsA("Frame") then
					n += 1
				end
			end
		end
	end
	return n
end

return Stains
