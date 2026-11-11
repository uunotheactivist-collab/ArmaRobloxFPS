--!strict
-- MP7 model fidelity slice: controlled capture harness + model checks (Studio playtest only; delete the folder to remove
-- it). It changes no gameplay: it only drives WeaponController's Studio-only debug hook (equip, "freeze" a reload clip
-- at a time, "record" the rig's frames) and sets LocalTransparencyModifier on the viewmodel's own parts for the
-- mask phases. Companion: Roblox/Tests/Weapons/MP7/MP7ModelFidelity/capture_states.ps1 (PrintWindow poller).
--   Run.capture(states)  spawned schedule. A full-viewport magenta frame first (the poller finds the viewport in the
--                        Studio window from it), then per state: settle, phase 1 = everything drawn, phase 2 = the
--                        weapon's parts hidden (the arm stays), phase 3 = the whole viewmodel hidden. A 40 x 10 px marker
--                        at the top centre encodes the state / phase (R = 10 + state index, G = 60 / 120 / 180 for the
--                        phase, B = 200; G = 240 = finished), so the poller saves each phase once it is on screen.
--                        Phase 1 records the rig's camera-relative frames (debug "record"). Results: _G.MP7MF.
--   Run.status()         progress / results of the last capture
--   Run.parts()          the viewmodel's parts: name, triangles (EditableMesh-built MeshParts report none: counted from
--                        the generated data), size, material, colour, transparency, CastShadow
-- A state is { id = "...", clip = "<ReloadAnimations clip name>" | nil, t = seconds }: clip nil = the rest (hip idle).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local hook = client:WaitForChild("WeaponController"):WaitForChild("ProductionWeaponDebug") :: BindableFunction

local Run = {}

local function w(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function cfList(c: CFrame): { number }
	local out = { c:GetComponents() }
	for i, v in out do
		out[i] = math.round(v * 1e6) / 1e6
	end
	return out
end

local function viewmodel(): Model?
	local cam = workspace.CurrentCamera
	return cam and cam:FindFirstChild("MP7Viewmodel") :: Model?
end

local function setHidden(weaponHidden: boolean, armHidden: boolean)
	local vm = viewmodel()
	if not vm then
		return
	end
	for _, p in vm:GetChildren() do
		if p:IsA("BasePart") then
			local isArm = p.Name == "LeftArm" or p.Name == "RightArm"
			p.LocalTransparencyModifier = if isArm then (if armHidden then 1 else 0) else (if weaponHidden then 1 else 0)
		end
	end
end

local function makeGui(): (ScreenGui, Frame, Frame)
	local old = player.PlayerGui:FindFirstChild("MP7MFMarker")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MP7MFMarker"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10000
	gui.ResetOnSpawn = false
	local cal = Instance.new("Frame")
	cal.Name = "Cal"
	cal.BorderSizePixel = 0
	cal.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
	cal.Size = UDim2.fromScale(1, 1)
	cal.Parent = gui
	local mark = Instance.new("Frame")
	mark.Name = "Mark"
	mark.BorderSizePixel = 0
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.new(0.5, 0, 0, 0)
	mark.Size = UDim2.fromOffset(40, 10)
	mark.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mark.Visible = false
	mark.Parent = gui
	gui.Parent = player.PlayerGui
	return gui, cal, mark
end

local function rel(cam: CFrame, c: CFrame?): { number }?
	return if c then cfList(cam:ToObjectSpace(c)) else nil
end

function Run.capture(states: { any }, opts: any?): string
	local o = opts or {}
	local settle, phaseS = o.settleS or 0.5, o.phaseS or 0.45
	_G.MP7MF = { status = "starting", started = os.clock(), poses = {}, order = {} }
	task.spawn(function()
		local R = _G.MP7MF
		player:SetAttribute("EquippedWeapon", "MP7")
		w("freeze", nil)
		frames(1.0)
		local gui, cal, mark = makeGui()
		local cam = workspace.CurrentCamera
		R.viewport = { cam.ViewportSize.X, cam.ViewportSize.Y }
		R.fov = cam.FieldOfView
		frames(1.6) -- calibration: the poller finds the magenta viewport
		cal.Visible = false
		mark.Visible = true
		for i, s in states do
			R.status = "state " .. i .. "/" .. #states .. " " .. s.id
			w("freeze", if s.clip then { clip = s.clip, t = s.t } else nil)
			setHidden(false, false)
			mark.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			frames(settle)
			for phase = 1, 3 do
				setHidden(phase >= 2, phase >= 3)
				if phase == 1 then
					w("record", true)
				end
				mark.BackgroundColor3 = Color3.fromRGB(10 + i, 60 * phase, 200)
				frames(phaseS)
				if phase == 1 then
					local rec = w("record", false)
					local e = rec.log and rec.log[#rec.log]
					if e then
						local c = e.camera
						R.poses[s.id] = { state = s, camera = cfList(c), fov = e.fov,
							weapon = rel(c, e.weapon), magazine = rel(c, e.magazine), chargingHandle = rel(c, e.chargingHandle),
							leftArm = rel(c, e.arm), muzzle = { c:PointToObjectSpace(e.muzzle).X, c:PointToObjectSpace(e.muzzle).Y,
								c:PointToObjectSpace(e.muzzle).Z }, lower = e.lower, reloadT = e.reloadT, n = #rec.log }
					end
				end
			end
			table.insert(R.order, s.id)
		end
		setHidden(false, false)
		w("freeze", nil)
		mark.BackgroundColor3 = Color3.fromRGB(10, 240, 200)
		frames(1.0)
		gui:Destroy()
		R.status = "done"
		R.seconds = os.clock() - R.started
	end)
	return "spawned " .. #states .. " states"
end

function Run.status(): string
	local R = _G.MP7MF
	if not R then
		return "none"
	end
	if R.status ~= "done" then
		return R.status
	end
	return HttpService:JSONEncode({ status = R.status, seconds = R.seconds, viewport = R.viewport, fov = R.fov,
		poses = R.poses, order = R.order })
end

function Run.parts(): any
	local vm = viewmodel()
	local out = {}
	if vm then
		for _, p in vm:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(out, { name = p.Name, class = p.ClassName, size = { p.Size.X, p.Size.Y, p.Size.Z },
					material = p.Material.Name, color = { math.round(p.Color.R * 255), math.round(p.Color.G * 255),
						math.round(p.Color.B * 255) }, transparency = p.Transparency, castShadow = p.CastShadow })
			end
		end
	end
	return out
end

return Run
