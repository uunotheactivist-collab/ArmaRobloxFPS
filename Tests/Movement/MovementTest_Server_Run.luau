--!strict
-- Focused movement test, server side (Studio only; delete the MovementTest folders to remove it). Driven by the
-- operator through execute_luau (Server datamodel); the client half is StarterPlayerScripts.MovementTest.Run.
--   Run.unit()                         deterministic rule tests (MovementRules)
--   Run.place(spot, face?)             server placement on a MovementTest spot (resets the validator's baseline)
--   Run.status() / Run.events(since)   MovementServer state / log (Studio hook)
--   Run.watchStart(hz?) / Run.watchStop()   server-side samples of position, state, stance, speed

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config.Movement)
local Rules = require(ServerScriptService.Server.Movement.MovementRules)

local Run = {}

local function dbg(cmd: string, ...: any): any
	local hook = ServerScriptService.Server.Movement.MovementServer:WaitForChild("MovementDebug") :: BindableFunction
	return hook:Invoke(cmd, ...)
end
Run.dbg = dbg

local function r3(v: number?): number?
	return if v then math.round(v * 1000) / 1000 else nil
end
Run.r3 = r3

local function check(list: { any }, name: string, ok: boolean, detail: any?)
	table.insert(list, { name = name, ok = ok, detail = detail })
end
Run.check = check

function Run.summary(list: { any }): any
	local pass, fail = 0, {}
	for _, c in list do
		if c.ok then
			pass += 1
		else
			table.insert(fail, c.name)
		end
	end
	return { passed = pass, total = #list, failed = fail, checks = list }
end

-- Spots (feet positions on the MovementTest floor) and the direction to face.
Run.Spots = {
	start = { Vector3.new(210, 0, -100), Vector3.new(1, 0, 0) },
	lane = { Vector3.new(212, 0, -130), Vector3.new(1, 0, 0) },
	slope = { Vector3.new(224, 0, -115), Vector3.new(1, 0, 0) },
	stairs = { Vector3.new(224, 0, -100), Vector3.new(1, 0, 0) },
	ledge = { Vector3.new(247, 6, -100), Vector3.new(1, 0, 0) },
	obstacles = { Vector3.new(224, 0, -85), Vector3.new(1, 0, 0) },
	door = { Vector3.new(232, 0, -70), Vector3.new(1, 0, 0) },
	tunnel = { Vector3.new(224, 0, -55), Vector3.new(1, 0, 0) },
	inTunnel = { Vector3.new(236, 0, -55), Vector3.new(1, 0, 0) },
	wall = { Vector3.new(294, 0, -120), Vector3.new(1, 0, 0) },
}

function Run.place(spot: string, face: Vector3?): CFrame?
	local s = Run.Spots[spot]
	local p = Players:GetPlayers()[1]
	local st = dbg("status", p)
	if not (s and st) then
		return nil
	end
	local c = p.Character :: Model
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart
	local hum = c:FindFirstChildOfClass("Humanoid") :: Humanoid
	local above = hum.HipHeight + root.Size.Y / 2
	local pos = s[1] + Vector3.new(0, above + 0.05, 0)
	local dir = face or s[2]
	local cf = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
	dbg("teleport", p, cf)
	return cf
end

function Run.status(): any
	return dbg("status", Players:GetPlayers()[1])
end

function Run.events(since: number?): { any }
	local out = {}
	for _, e in dbg("events") do
		if not since or e.t >= since then
			table.insert(out, e)
		end
	end
	return out
end

local watching = { On = false, Samples = {} :: { any } }
function Run.watchStart(hz: number?): number
	watching.On = true
	watching.Samples = {}
	local p = Players:GetPlayers()[1]
	task.spawn(function()
		local t0 = os.clock()
		while watching.On and os.clock() - t0 < 30 do
			local c = p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if root and hum then
				table.insert(watching.Samples, {
					t = os.clock(),
					pos = root.Position,
					state = c:GetAttribute(Config.Attributes.MoveState),
					stance = c:GetAttribute(Config.Attributes.Stance),
					walk = hum.WalkSpeed,
					hip = hum.HipHeight,
					rej = c:GetAttribute(Config.Attributes.Rejections),
				})
			end
			task.wait(1 / (hz or 30))
		end
	end)
	return os.clock()
end

function Run.watchStop(): { any }
	watching.On = false
	return watching.Samples
end

------------------------------------------------------------------------------------------------- deterministic rules
function Run.unit(): any
	local list = {}
	local C = Config
	-- speeds per stance
	check(list, "U1 walk speed is the measured 5.6 studs/s", Rules.speedFor("STAND", C) == 5.6, Rules.speedFor("STAND", C))
	check(list, "U2 crouch speed is the placeholder 2.8 studs/s", Rules.speedFor("CROUCH", C) == 2.8, Rules.speedFor("CROUCH", C))
	check(list, "U3 jump: engine default standing, none crouched", Rules.jumpFor("STAND", C) == 7.2 and Rules.jumpFor("CROUCH", C) == 0, nil)
	check(list, "U4 crouch lowers the hip by the eye drop (4.05 - 2.7 = 1.35)", math.abs(Rules.hipFor("CROUCH", 1.8, C) - 0.45) < 1e-9 and Rules.hipFor("STAND", 1.8, C) == 1.8, Rules.hipFor("CROUCH", 1.8, C))
	-- travel budget
	local b, over = C.Server.BankStuds, false
	for _ = 1, 50 do -- 5 s at exactly the walk speed
		b, over = Rules.budgetStep(b, 5.6, 0.1, 0.56, C)
		if over then
			break
		end
	end
	check(list, "U5 walking at the cap for 5 s never violates", not over, r3(b))
	b, over = C.Server.BankStuds, false
	local steps = 0
	for i = 1, 50 do -- 2x speed
		b, over = Rules.budgetStep(b, 5.6, 0.1, 1.12, C)
		if over then
			steps = i
			break
		end
	end
	check(list, "U6 a 2x speed hack is caught within 1.5 s", over and steps <= 15, steps)
	local _, tele = Rules.budgetStep(C.Server.BankStuds, 5.6, 0.1, 40, C)
	check(list, "U7 a 40-stud jump in one check is a violation", tele, nil)
	local _, nanOver = Rules.budgetStep(C.Server.BankStuds, 5.6, 0.1, 0 / 0, C)
	check(list, "U8 NaN travel is a violation", nanOver, nil)
	local bAfter = Rules.budgetStep(C.Server.BankStuds, 5.6, 0.1, 40, C)
	check(list, "U24 no fresh allowance after a violation (budget restarts at 0)", bAfter == 0, bAfter)
	b = C.Server.BankStuds
	local jitter = false
	for i = 1, 40 do -- network jitter: 0.3 s of nothing then a 0.3 s burst, at the cap on average
		local moved = if i % 6 < 3 then 0 else 0.56 * 2
		local o
		b, o = Rules.budgetStep(b, 5.6, 0.1, moved, C)
		jitter = jitter or o
	end
	check(list, "U9 bunched (jittery) updates at the cap on average are not violations", not jitter, r3(b))
	-- rise limit
	check(list, "U10 rise limit = floor + standing root + jump + margin", math.abs(Rules.riseLimit(0, 2.7, C) - (2.7 + 7.2 + 1.5)) < 1e-9, Rules.riseLimit(0, 2.7, C))
	check(list, "U11 invalid positions", Rules.invalidPosition(Vector3.new(0 / 0, 0, 0)) and Rules.invalidPosition(Vector3.new(0, 2e5, 0)) and not Rules.invalidPosition(Vector3.new(250, 3, -100)), nil)
	-- states
	local function ns(state: string, grounded: boolean, rise: number, speed: number, stance: string, now: number, landUntil: number?): string
		local s = Rules.nextState({ State = state, LandUntil = landUntil or 0 }, { Dead = false, Grounded = grounded, RiseSpeed = rise, FlatSpeed = speed, Stance = stance, Now = now }, C)
		return s
	end
	check(list, "U12 still -> IDLE, moving -> WALK", ns("IDLE", true, 0, 0, "STAND", 0) == "IDLE" and ns("IDLE", true, 0, 5, "STAND", 0) == "WALK", nil)
	check(list, "U25 walk hysteresis: 1.0 studs/s neither starts nor ends a walk", ns("IDLE", true, 0, 1.0, "STAND", 0) == "IDLE" and ns("WALK", true, 0, 1.0, "STAND", 0) == "WALK" and ns("WALK", true, 0, 0.3, "STAND", 0) == "IDLE", nil)
	check(list, "U13 crouched (moving or not) -> CROUCH", ns("WALK", true, 0, 2, "CROUCH", 0) == "CROUCH" and ns("IDLE", true, 0, 0, "CROUCH", 0) == "CROUCH", nil)
	check(list, "U14 airborne rising -> JUMP, else FALL", ns("WALK", false, 20, 5, "STAND", 0) == "JUMP" and ns("JUMP", false, -5, 5, "STAND", 0) == "FALL", nil)
	local land, untilT = Rules.nextState({ State = "FALL", LandUntil = 0 }, { Dead = false, Grounded = true, RiseSpeed = -30, FlatSpeed = 0, Stance = "STAND", Now = 10 }, C)
	check(list, "U15 touching down -> LAND for 0.2 s, then IDLE", land == "LAND" and math.abs(untilT - 10.2) < 1e-9 and ns("LAND", true, 0, 0, "STAND", 10.1, untilT) == "LAND" and ns("LAND", true, 0, 0, "STAND", 10.25, untilT) == "IDLE", untilT)
	local settle = Rules.nextState({ State = "IDLE", LandUntil = 0 }, { Dead = false, Grounded = false, RiseSpeed = -8, FlatSpeed = 1.0, Stance = "CROUCH", Now = 0, Settling = true }, C)
	check(list, "U23 lowering into a crouch is not a fall (settling)", settle == "CROUCH", settle)
	check(list, "U16 dead -> DEAD from any state", Rules.nextState({ State = "WALK", LandUntil = 0 }, { Dead = true, Grounded = true, RiseSpeed = 0, FlatSpeed = 5, Stance = "STAND", Now = 0 }, C) == "DEAD", nil)
	-- intents
	local ctx = { Alive = true, Stance = "STAND", Locked = nil, StandBlocked = false }
	local function it(verb: any, value: any, over: any?): (boolean, string, string)
		local c2 = table.clone(ctx)
		if over then
			for k, v in over do
				c2[k] = v
			end
		end
		return Rules.intent(verb, value, c2, C)
	end
	local ok1, s1 = it("Crouch", true)
	check(list, "U17 crouch request accepted", ok1 and s1 == "CROUCH", s1)
	local ok2, _, w2 = it("Sprint", true)
	check(list, "U18 sprint request refused (not built)", not ok2, w2)
	local ok3, _, w3 = it("Crouch", "yes")
	local ok4 = it("Crouch", 0 / 0)
	local ok5 = it({}, true)
	check(list, "U19 malformed requests refused", not ok3 and not ok4 and not ok5, w3)
	local ok6, _, w6 = it("Crouch", true, { Alive = false })
	check(list, "U20 dead player's request refused", not ok6, w6)
	local ok7, _, w7 = it("Crouch", true, { Locked = "Interaction" })
	check(list, "U21 request refused during an interaction (drag)", not ok7, w7)
	local ok8, s8, w8 = it("Crouch", false, { Stance = "CROUCH", StandBlocked = true })
	check(list, "U22 standing up under a low ceiling refused", not ok8 and s8 == "CROUCH", w8)
	return Run.summary(list)
end

return Run
