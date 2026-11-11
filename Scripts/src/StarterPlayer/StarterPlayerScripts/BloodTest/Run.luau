--!strict
-- Focused blood / impact test, client side (Studio only; delete the BloodTest folders to remove it). Real shots go
-- through the production controller; the fake attempts below must change nothing on the server (checked by
-- ServerScriptService.BloodTest.Run).
--   Run({ deadHit = true })   one more real shot at the DEAD REACT5's head
--   Run({ floor = true })     a real shot into the floor in front of REACT1 (a surface impact)
--   Run({ security = true })  fake attempts: ImpactFx fired from the client, unknown blood commands, a forged
--                             WeaponFire claiming a body hit, local BodyState writes, a locally drawn stain

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction
local Remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function bot(i: number): Model
	return workspace:WaitForChild("HitReactionTest"):WaitForChild("Bot" .. i):WaitForChild("REACT" .. i) :: Model
end

local function standAt(i: number)
	local spot = (workspace.HitReactionTest:WaitForChild("Bot" .. i):WaitForChild("ShooterSpot") :: BasePart).Position
	local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
	root.CFrame = CFrame.lookAt(spot + Vector3.new(0, 3, 0), Vector3.new(spot.X, spot.Y + 3, spot.Z - 15))
	root.AssemblyLinearVelocity = Vector3.zero
	frames(0.6)
end

local function aimAt(point: Vector3)
	local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
	local cam = workspace.CurrentCamera
	for _ = 1, 2 do
		local dir = (point - head.Position).Unit
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + dir)
		frames(0.12)
	end
end

local function fire(n: number): number
	local before = call("state").shotCount
	call("trigger", true)
	local t0 = os.clock()
	while call("state").shotCount < before + n and os.clock() - t0 < 2 do
		RunService.RenderStepped:Wait()
	end
	call("trigger", false)
	return call("state").shotCount - before
end

return function(opts: any): any
	local out: any = {}
	call("stressed", false)
	call("aim", false)
	player:SetAttribute("EquippedWeapon", opts.weapon or "M4")
	frames(0.4)
	call("refill")
	frames(0.4)
	if opts.deadHit then
		standAt(5)
		aimAt((bot(5):FindFirstChild("Head") :: BasePart).Position)
		out.fired = fire(1)
		frames(0.5)
	elseif opts.floor then
		standAt(1)
		local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
		aimAt(Vector3.new(head.Position.X + 2, 0, head.Position.Z - 5))
		out.fired = fire(1)
		frames(0.5)
	elseif opts.security then
		local m = bot(1)
		local torso = m:FindFirstChild("UpperTorso") :: BasePart
		-- 1 the presentation remote fired from the client, claiming a bleeding hit on REACT1
		;(Remotes:WaitForChild("ImpactFx") :: RemoteEvent):FireServer({ { t = "body", p = torso.Position, n = Vector3.zAxis, part = torso, bleed = true } })
		-- 2 blood commands that don't exist
		;(Remotes.WeaponCommand :: RemoteEvent):FireServer("SpawnBlood", { part = torso, p = torso.Position })
		;(Remotes.WeaponCommand :: RemoteEvent):FireServer("Blood", torso, torso.Position)
		-- 3 a real-looking shot whose extra arguments claim a hit on REACT1, aimed at the floor instead
		standAt(1)
		local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
		local floorPoint = Vector3.new(head.Position.X - 3, 0, head.Position.Z - 4)
		;(Remotes.WeaponFire :: RemoteEvent):FireServer("M4", head.Position, (floorPoint - head.Position).Unit, torso.Position, torso, "UpperTorso")
		-- 4 local BodyState writes (down and dead)
		m:SetAttribute("BodyPhase", "DEAD")
		m:SetAttribute("BodyStance", "DOWN")
		-- 5 a stain drawn locally on the body
		local g = Instance.new("SurfaceGui")
		g.Name = "BloodStain_Front"
		g.Face = Enum.NormalId.Front
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(0.5, 0.5)
		f.Parent = g
		g.Parent = torso
		frames(1.0)
		out.localPhase = m:GetAttribute("BodyPhase")
		out.sent = 5
	end
	return out
end
