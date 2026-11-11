--!strict
-- Focused movement test, client side (Studio only; delete the MovementTest folders to remove it). Drives the real
-- client: the movement input goes through MovementController's easing (debug input = a held stick), the camera turns
-- through the camera scripts, crouch goes through the intent remote. Everything is judged on the server too
-- (ServerScriptService.MovementTest.Run + MovementDebug).
--   Run({ move = { dir = Vector3, seconds = n, after = n } })      hold a direction, then release; samples
--   Run({ turn = { rate = deg/s, seconds = n, after = n, aim = bool, move = Vector3? } })   constant turn; samples
--   Run({ crouch = bool })                                          press crouch (predicted + intent)
--   Run({ jump = true, seconds = n })                               one engine jump; samples
--   Run({ record = n })                                             samples only
--   Run({ forge = name, ... })                                      one forged input (security)
--   Run({ state = true })                                           MovementController state

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Intent = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"):WaitForChild("MovementIntent") :: RemoteEvent

local function client(cmd: string, arg: any?): any
	local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Movement")
		:WaitForChild("MovementController"):WaitForChild("MovementClientDebug") :: BindableFunction
	return hook:Invoke(cmd, arg)
end

local function weapon(cmd: string, arg: any?): any
	local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
		:WaitForChild("ProductionWeaponDebug") :: BindableFunction
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function parts(): (Model, Humanoid, BasePart)
	local c = player.Character or player.CharacterAdded:Wait()
	return c, c:WaitForChild("Humanoid") :: Humanoid, c:WaitForChild("HumanoidRootPart") :: BasePart
end

local function r3(v: number): number
	return math.round(v * 1000) / 1000
end

-- Compact per-frame samples from MovementController's record.
local function compact(log: { any }?): { any }
	local out = {}
	for _, s in log or {} do
		local look = s.camera.LookVector
		table.insert(out, {
			t = s.t,
			x = r3(s.root.X),
			y = r3(s.root.Y),
			z = r3(s.root.Z),
			vx = r3(s.vel.X),
			vy = r3(s.vel.Y),
			vz = r3(s.vel.Z),
			speed = r3(Vector3.new(s.vel.X, 0, s.vel.Z).Magnitude),
			input = r3(s.smoothed.Magnitude),
			eye = r3(s.eyeAboveFeet),
			feet = r3(s.feetY),
			pitch = r3(math.deg(math.asin(look.Y))),
			roll = r3(s.roll),
			lagYaw = r3(s.lagYaw),
			lagPitch = r3(s.lagPitch),
			bobYaw = r3(s.bobYaw),
			bobPitch = r3(s.bobPitch),
			turn = r3(s.turnRight),
			stance = s.stance,
			server = s.serverStance,
			state = s.serverState,
			fov = r3(s.fov),
			grounded = s.grounded,
		})
	end
	return out
end

-- Horizon roll of the final camera, degrees (+ = the horizon dips to the right, as in the footage analysis).
local function horizonRoll(cf: CFrame): number
	local right = cf.RightVector
	return math.deg(math.asin(math.clamp(right.Y, -1, 1)))
end

local turnRate = 0
local turning = false
RunService:BindToRenderStep("MovementTestTurn", Enum.RenderPriority.Camera.Value - 2, function(dt: number)
	if not turning then
		return
	end
	local cam = workspace.CurrentCamera
	local p = cam.CFrame.Position
	cam.CFrame = CFrame.new(p) * CFrame.Angles(0, -math.rad(turnRate) * dt, 0) * cam.CFrame.Rotation
end)

return function(opts: any): any
	local out: any = {}
	if opts.state then
		out = client("state")
	elseif opts.move then
		local m = opts.move
		client("record", true)
		client("input", m.dir)
		frames(m.seconds or 2)
		client("input", if m.release == false then m.dir else Vector3.zero)
		frames(m.after or 1)
		client("input", nil)
		out.samples = compact(client("record", false))
	elseif opts.turn then
		local tr = opts.turn
		if tr.aim ~= nil then
			weapon("aim", tr.aim)
			frames(0.6)
		end
		weapon("record", true)
		client("record", true)
		if tr.move then
			client("input", tr.move)
		end
		frames(0.2)
		turnRate, turning = tr.rate, true
		frames(tr.seconds or 1.5)
		turning = false
		frames(tr.after or 1.5)
		if tr.move then
			client("input", nil)
		end
		out.samples = compact(client("record", false))
		local wlog = weapon("record", false)
		-- viewmodel attachment: left arm and magazine relative to the weapon (rigid), weapon relative to the camera
		local first = wlog.log[1]
		local relArm0 = first.weapon:Inverse() * first.arm
		local relMag0 = first.weapon:Inverse() * first.magazine
		local maxArm, maxArmDeg, maxMag, maxCamDeg, lastCamDeg = 0, 0, 0, 0, 0
		local ref = first.camera:Inverse() * first.weapon
		for _, s in wlog.log do
			local ra = s.weapon:Inverse() * s.arm
			local rm = s.weapon:Inverse() * s.magazine
			maxArm = math.max(maxArm, (ra.Position - relArm0.Position).Magnitude)
			maxArmDeg = math.max(maxArmDeg, math.deg(math.acos(math.clamp(ra.LookVector:Dot(relArm0.LookVector), -1, 1))))
			maxMag = math.max(maxMag, (rm.Position - relMag0.Position).Magnitude)
			local rel = s.camera:Inverse() * s.weapon
			local ang = math.deg(math.acos(math.clamp(rel.LookVector:Dot(ref.LookVector), -1, 1)))
			maxCamDeg = math.max(maxCamDeg, ang)
			lastCamDeg = ang
		end
		out.attach = {
			frames = #wlog.log,
			maxArmOffset = maxArm,
			maxArmDeg = maxArmDeg,
			maxMagOffset = maxMag,
			maxWeaponVsCameraDeg = r3(maxCamDeg),
			endWeaponVsCameraDeg = lastCamDeg,
			weapon = wlog.log[#wlog.log].weaponId,
			fovs = { r3(wlog.log[1].fov), r3(wlog.log[#wlog.log].fov) },
		}
		local rolls = {}
		for i = 1, #wlog.log, math.max(1, math.floor(#wlog.log / 40)) do
			table.insert(rolls, r3(horizonRoll(wlog.log[i].camera)))
		end
		out.finalRolls = rolls
		if tr.aim ~= nil then
			weapon("aim", false)
		end
	elseif opts.crouch ~= nil then
		out.predicted = client("crouch", opts.crouch)
		out.at = os.clock()
	elseif opts.jump then
		local _, hum = parts()
		client("record", true)
		frames(0.1)
		out.at = os.clock()
		hum.Jump = true
		frames(opts.seconds or 1.6)
		out.samples = compact(client("record", false))
	elseif opts.record then
		client("record", true)
		frames(opts.record)
		out.samples = compact(client("record", false))
	elseif opts.forge then
		local c, hum, root = parts()
		local f = opts.forge
		out.before = root.Position
		if f == "speed" then -- the client raises its own walk speed and runs
			local was = hum.WalkSpeed
			hum.WalkSpeed = 40
			client("input", Vector3.new(1, 0, 0))
			frames(opts.seconds or 1.5)
			client("input", nil)
			hum.WalkSpeed = was
			frames(0.5)
		elseif f == "teleport" then
			root.CFrame = root.CFrame + (opts.offset or Vector3.new(40, 0, 0))
			frames(0.6)
		elseif f == "fly" then
			local t0 = os.clock()
			while os.clock() - t0 < 1.2 do
				root.AssemblyLinearVelocity = Vector3.new(0, 40, 0)
				RunService.Heartbeat:Wait()
			end
			frames(0.8)
		elseif f == "noclip" then
			root.CFrame = root.CFrame + Vector3.new(6, 0, 0) -- through the end wall
			frames(0.6)
		elseif f == "hover" then
			local was = hum.HipHeight
			hum.HipHeight = was + 3
			frames(2.2)
			hum.HipHeight = was
			frames(0.6)
		elseif f == "nan" then
			pcall(function()
				root.CFrame = CFrame.new(0 / 0, 0, 0)
			end)
			frames(0.6)
		elseif f == "attributes" then
			c:SetAttribute("Stance", "CROUCH")
			c:SetAttribute("MoveState", "SPRINT")
			c:SetAttribute("MoveRejections", 0)
			c:SetAttribute("MoveLocked", nil)
			frames(0.5)
			out.localView = { c:GetAttribute("Stance"), c:GetAttribute("MoveState") }
		elseif f == "intents" then
			Intent:FireServer("Sprint", true)
			Intent:FireServer("Crouch", "yes")
			Intent:FireServer("Crouch", 0 / 0)
			Intent:FireServer({}, true)
			Intent:FireServer("Crouch", true, "extra", 1e9)
			frames(1.1) -- a fresh rate window
			for i = 1, 30 do
				Intent:FireServer("Crouch", i % 2 == 1)
			end
			frames(0.6)
		elseif f == "deadMove" then
			client("input", Vector3.new(1, 0, 0))
			Intent:FireServer("Crouch", true)
			frames(1.0)
			client("input", nil)
		end
		out.after = root.Position
		out.walkSpeedLocal = hum.WalkSpeed
	end
	out.clock = os.clock()
	return out
end
