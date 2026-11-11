--!strict
-- BloodTrail (server): the drag trail. While the server drags a body (Server.Interaction.Drag), it calls begin / step /
-- finish here; each time the body's pelvis has moved SpacingStuds over the floor, the stretch it covered gets trail
-- smears (SurfaceMarks.trail). So the trail follows the body's actual (physical) path, appears only once it moves,
-- and stops when the drag stops. Only wounded bodies bleed (BodyState's own BodyWound); DEAD ones per
-- Config.Blood.Trail.WhenDead. Persistence and budget: the shared mark layer (nothing fades; oldest first beyond
-- MaxMarks). Nothing a client sends reaches this module. Values: Config.Blood.Trail.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))
local Marks = require(script.Parent:WaitForChild("SurfaceMarks"))

local Trails = {}

type Active = { Model: Model, Source: BasePart, Last: Vector3, Placed: number, Points: { Vector3 }, Started: number }

local active: { [Model]: Active } = {}
Trails.Recent = {} :: { any } -- Studio only: finished trails, for the tests

local function bleeds(model: Model): boolean
	if type(model:GetAttribute("BodyWound")) ~= "string" then
		return false -- never wounded: nothing to bleed
	end
	return model:GetAttribute("BodyPhase") ~= "DEAD" or Config.Trail.WhenDead
end

local function sourceOf(model: Model): BasePart?
	for _, name in Config.Trail.SourceParts do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

function Trails.begin(model: Model): boolean
	local src = sourceOf(model)
	if not src then
		return false
	end
	active[model] = { Model = model, Source = src, Last = src.Position, Placed = 0, Points = { src.Position }, Started = os.clock() }
	return true
end

-- Called every server frame while the body is dragged: cheap unless the body has moved a full spacing.
function Trails.step(model: Model)
	local a = active[model]
	if not a or not a.Source.Parent then
		return
	end
	local p = a.Source.Position
	local moved = Vector3.new(p.X - a.Last.X, 0, p.Z - a.Last.Z).Magnitude
	if moved < Config.Trail.SpacingStuds then
		return
	end
	if bleeds(model) then
		a.Placed += Marks.trail(a.Last, p, { model })
	end
	a.Last = p
	if RunService:IsStudio() then
		table.insert(a.Points, p)
	end
end

function Trails.finish(model: Model)
	local a = active[model]
	if not a then
		return
	end
	active[model] = nil
	if RunService:IsStudio() then
		table.insert(Trails.Recent, {
			Body = model.Name,
			Placed = a.Placed,
			Points = a.Points,
			Bleeding = bleeds(model),
			Seconds = os.clock() - a.Started,
		})
		while #Trails.Recent > 32 do
			table.remove(Trails.Recent, 1)
		end
	end
end

function Trails.stats(): any
	local list = {}
	for m, a in active do
		table.insert(list, { Body = m.Name, Placed = a.Placed })
	end
	return { Active = list, Recent = Trails.Recent }
end

return Trails
