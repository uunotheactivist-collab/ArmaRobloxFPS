--!strict
-- Focused Glock test, server side (Studio only; delete the GlockTest folders to remove it). Driven through execute_luau
-- (Server datamodel). Everything generic (placement on the reused Workspace.MP7Test range, bots, the server's own shot
-- traces, blood, network counter, kill) comes from ServerScriptService.MP7Test.Run; this adds the Glock shot cost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Base = require(script.Parent.Parent:WaitForChild("MP7Test"):WaitForChild("Run")) :: any
local Run = setmetatable({}, { __index = Base }) :: any

-- Server cost of a Glock shot: Server.WeaponShot.resolve from the player's head at the WallTarget, n times.
function Run.shotCost(n: number): any
	local WeaponShot = require(ServerScriptService:WaitForChild("Server"):WaitForChild("WeaponShot")) :: any
	local cfg = (require(ReplicatedStorage.Shared.WeaponRegistry) :: any).get("Glock")
	local p = Base.player()
	local c = p.Character :: Model
	local hum = c:FindFirstChildOfClass("Humanoid") :: Humanoid
	local head = c:FindFirstChild("Head") :: BasePart
	local target = workspace.MP7Test.FiringLane.WallTarget :: BasePart
	local times = {}
	for i = 1, n do
		local aim = (target.Position + Vector3.new(((i % 5) - 2) * 0.5, ((i // 5) % 5 - 2) * 0.5, 0) - head.Position).Unit
		local t0 = os.clock()
		WeaponShot.resolve({ Player = p, Character = c, Humanoid = hum, Name = p.Name }, "Glock", cfg, head.Position, aim)
		table.insert(times, (os.clock() - t0) * 1000)
	end
	table.sort(times)
	local sum = 0
	for _, t in times do
		sum += t
	end
	return { n = n, meanMs = sum / n, medianMs = times[n // 2 + 1], maxMs = times[n] }
end

return Run
