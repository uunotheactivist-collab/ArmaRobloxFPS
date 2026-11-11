--!strict
-- BloodPool (server): one pool on the floor under a body once it is down (DYING or DEAD) [confirmed: pools under and
-- around bodies, persisting]. It grows from StartRadius to MaxRadius over GrowSeconds (fast at first), then stays.
-- Size and growth are [placeholder] (not measurable in the footage). Started only from BodyState's own published state
-- (Server.Blood.BloodServer), never from client data. One loop updates every growing pool and stops when none grows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Blood"))
local Canvas = require(script.Parent:WaitForChild("Canvas"))
local Marks = require(script.Parent:WaitForChild("SurfaceMarks"))

local Pools = {}

type Pool = { Model: Model, Part: BasePart, Holder: Frame, Studs: number, Start: number, Radius: number }

local all: { Pool } = {}
local growing: { Pool } = {}
local started: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local looping = false
local rng = Random.new()

local function loop()
	local P = Config.Pool
	while #growing > 0 do
		local now = os.clock()
		for i = #growing, 1, -1 do
			local p = growing[i]
			local u = math.clamp((now - p.Start) / P.GrowSeconds, 0, 1)
			local eased = 1 - (1 - u) * (1 - u)
			p.Radius = P.StartRadius + (P.MaxRadius - P.StartRadius) * eased
			local s = 2 * p.Radius / p.Studs
			p.Holder.Size = UDim2.fromScale(s, s)
			if u >= 1 or not p.Part.Parent then
				table.remove(growing, i)
			end
		end
		task.wait(P.StepSeconds)
	end
	looping = false
end

-- Start the pool for a downed body (once per body). Returns true if a pool was started.
function Pools.start(model: Model): boolean
	if started[model] then
		return false
	end
	local torso = (model:FindFirstChild("LowerTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")) :: BasePart?
	if not torso then
		return false
	end
	local floor, pos, normal = Marks.floorBelow(torso.Position, { model })
	if not floor or not pos or not normal then
		return false
	end
	started[model] = true
	local P = Config.Pool
	while #all >= P.MaxPools do
		local old = table.remove(all, 1) :: Pool
		local gi = table.find(growing, old)
		if gi then
			table.remove(growing, gi)
		end
		old.Part:Destroy()
	end
	local studs = P.MaxRadius * 2 + 1
	local part = Canvas.patch("BloodPool", pos, normal, studs, P.Lift)
	local gui = Canvas.gui(part, Enum.NormalId.Top, "BloodPool", P.PixelsPerStud)
	local holder = Instance.new("Frame")
	holder.Name = "Pool"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	local s0 = 2 * P.StartRadius / studs
	holder.Size = UDim2.fromScale(s0, s0)
	-- an irregular pool: overlapping round lobes inside the growing holder
	for i = 1, 5 do
		local c = Instance.new("Frame")
		local size = if i == 1 then 0.75 else rng:NextNumber(0.4, 0.6)
		local off = if i == 1 then Vector2.zero else Vector2.new(rng:NextNumber(-0.22, 0.22), rng:NextNumber(-0.22, 0.22))
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5 + off.X, 0.5 + off.Y)
		c.Size = UDim2.fromScale(size, size)
		c.BackgroundColor3 = Config.BloodDark
		c.BackgroundTransparency = P.Transparency
		c.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = c
		c.Parent = holder
	end
	holder.Parent = gui
	part.Parent = Marks.folder()
	local pool: Pool = { Model = model, Part = part, Holder = holder, Studs = studs, Start = os.clock(), Radius = P.StartRadius }
	table.insert(all, pool)
	table.insert(growing, pool)
	if not looping then
		looping = true
		task.spawn(loop)
	end
	return true
end

function Pools.stats(): any
	local list = {}
	for _, p in all do
		table.insert(list, { Body = p.Model.Name, Position = p.Part.Position, Radius = p.Radius, Growing = table.find(growing, p) ~= nil })
	end
	return { Pools = #all, Growing = #growing, List = list }
end

function Pools.clear()
	for _, p in all do
		p.Part:Destroy()
	end
	table.clear(all)
	table.clear(growing)
	table.clear(started)
end

return Pools
