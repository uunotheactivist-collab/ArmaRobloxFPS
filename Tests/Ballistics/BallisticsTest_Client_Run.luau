--!strict
-- Focused ballistic test, client side (Studio only; delete the BallisticsTest folders to remove it).
-- Fires REAL shots through the production pipeline (client controller -> WeaponFire -> Server.WeaponServer ->
-- shared Server.Ballistics) on the range Workspace.BallisticTest. The client only stands on a lane's shooter spot,
-- aims at the lane target's torso and pulls the trigger once; everything that is hit is decided on the server and
-- checked there (ServerScriptService.BallisticsTest.Run: arm() before, report() after).
--   Run({ weapons = { "M4", "AK" }, lanes = { "A", "B", "C" }, shots = 5 })

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function standAt(laneName: string): (Vector3, Vector3)
	local lane = workspace:WaitForChild("BallisticTest"):WaitForChild("Lane" .. laneName)
	local spot = (lane:WaitForChild("ShooterSpot") :: BasePart).Position
	local aim = (lane:WaitForChild("Target"):WaitForChild("Torso") :: BasePart).Position
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	assert(root, "no character")
	local flatAim = Vector3.new(aim.X, spot.Y + 3, aim.Z)
	root.CFrame = CFrame.lookAt(spot + Vector3.new(0, 3, 0), flatAim)
	root.AssemblyLinearVelocity = Vector3.zero
	frames(0.6) -- let the server see the new position (it validates the shot origin against its head copy)
	local camera = workspace.CurrentCamera
	camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aim)
	frames(0.2)
	return camera.CFrame.Position, aim
end

local function fireOne(): boolean
	local before = call("state").shotCount
	call("trigger", true)
	local t0 = os.clock()
	while call("state").shotCount == before and os.clock() - t0 < 1 do
		RunService.RenderStepped:Wait()
	end
	call("trigger", false)
	return call("state").shotCount > before
end

return function(opts: any): any
	local out = { fired = 0, perWeapon = {} }
	call("stressed", false)
	call("aim", false)
	for _, id in opts.weapons do
		player:SetAttribute("EquippedWeapon", id)
		frames(0.4)
		call("refill")
		frames(0.6)
		local n = 0
		for _, laneName in opts.lanes do
			standAt(laneName)
			for _ = 1, opts.shots do
				if fireOne() then
					n += 1
				end
				frames(0.45) -- recoil recovers, the server restores the target's health
			end
		end
		out.perWeapon[id] = n
		out.fired += n
	end
	return out
end
