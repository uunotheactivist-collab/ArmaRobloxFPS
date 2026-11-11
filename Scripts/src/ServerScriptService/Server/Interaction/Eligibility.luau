--!strict
-- Interaction checks (server). Everything is measured on the server's own copies: the player's character, the body's
-- parts. Nothing a client reports (positions, states, results) is used.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BodyInteraction"))

local Eligibility = {}

-- The player's live character: (character, root, humanoid) or an error.
function Eligibility.player(player: Player): (Model?, BasePart?, Humanoid?, string?)
	if not player.Parent then
		return nil, nil, nil, "player left"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") or not character:IsDescendantOf(workspace) then
		return nil, nil, nil, "no character"
	end
	if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return nil, nil, nil, "player dead"
	end
	if character:GetAttribute("VehicleSeat") ~= nil then
		return nil, nil, nil, "in a vehicle" -- truck slice: seated players can't check or drag bodies (not shown: UNKNOWN)
	end
	return character, root, humanoid, nil
end

-- A BodyState body in the world (attribute BodyModel set by the server), or an error. Player characters are not
-- BodyState bodies (not integrated), so no player can be checked or dragged.
function Eligibility.body(target: any): (Model?, string?)
	if typeof(target) ~= "Instance" then
		return nil, "no target"
	end
	local inst = target :: Instance
	if not inst:IsA("Model") then
		return nil, "not a body"
	end
	local model = inst :: Model
	if not model:IsDescendantOf(workspace) then
		return nil, "not in the world"
	end
	if model:GetAttribute(Config.BodyAttribute) ~= true or not model:FindFirstChildOfClass("Humanoid") then
		return nil, "not a body"
	end
	if Players:GetPlayerFromCharacter(model) then
		return nil, "a player"
	end
	return model, nil
end

-- Distance from a point to the body (closest point on any of its parts), and that part.
function Eligibility.distance(model: Model, from: Vector3): (number, BasePart?)
	local best, bestPart = math.huge, nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local rel = d.CFrame:PointToObjectSpace(from)
			local h = d.Size / 2
			local clamped = Vector3.new(math.clamp(rel.X, -h.X, h.X), math.clamp(rel.Y, -h.Y, h.Y), math.clamp(rel.Z, -h.Z, h.Z))
			local dist = (rel - clamped).Magnitude
			if dist < best then
				best, bestPart = dist, d
			end
		end
	end
	return best, bestPart
end

-- The player's head sees the body part (world geometry blocks; other bodies and characters don't).
function Eligibility.lineOfSight(character: Model, model: Model, part: BasePart): boolean
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return false
	end
	local exclude: { Instance } = { character, model }
	local blood = workspace:FindFirstChild("BloodMarks")
	if blood then
		table.insert(exclude, blood)
	end
	local origin = head.Position
	local dir = part.Position - origin
	for _ = 1, 4 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(origin, dir, params)
		if not hit then
			return true
		end
		local other = hit.Instance:FindFirstAncestorOfClass("Model")
		if other and other:FindFirstChildOfClass("Humanoid") then
			table.insert(exclude, other) -- bodies in a pile don't hide each other
		else
			return false
		end
	end
	return false
end

return Eligibility
