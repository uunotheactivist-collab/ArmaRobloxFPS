--!strict
-- Pure movement rules (server). No instances, no clock: deterministic and unit-testable. MovementServer feeds them what
-- it observed and applies the results. Values: Shared.Config.Movement.

local MovementRules = {}

export type StateInput = {
	Dead: boolean,
	Grounded: boolean,
	RiseSpeed: number, -- studs/s upward (negative = falling)
	FlatSpeed: number, -- studs/s horizontal
	Stance: string,
	Now: number,
	Settling: boolean?, -- just changed stance: the body is being lowered / raised on purpose (not a fall, not a walk)
}

export type StateMemory = { State: string, LandUntil: number }

-- The walk speed the server gives a stance (the client can't raise it: Humanoid.WalkSpeed is server-owned).
function MovementRules.speedFor(stance: string, cfg: any): number
	if stance == "CROUCH" then
		return cfg.Crouch.Speed
	end
	return cfg.Walk.Speed
end

-- Jump height the server gives a stance.
function MovementRules.jumpFor(stance: string, cfg: any): number
	if not cfg.Jump.Enabled then
		return 0
	end
	if stance == "CROUCH" and not cfg.Crouch.AllowJump then
		return 0
	end
	return cfg.Jump.Height
end

-- Hip height for a stance: crouching lowers the whole body (hit boxes, AI aim points, camera) by the eye-height drop.
function MovementRules.hipFor(stance: string, standHip: number, cfg: any): number
	if stance == "CROUCH" then
		return math.max(0.05, standHip - (cfg.Camera.EyeHeight - cfg.Crouch.EyeHeight))
	end
	return standHip
end

-- Travel budget (leaky bucket): each check adds cap x tolerance x dt (banked up to BankSeconds + BankStuds) and
-- removes the horizontal distance actually moved. Returns the new budget and whether this check is a violation.
-- After a violation the budget restarts at zero: no fresh allowance to spend right after being moved back.
function MovementRules.budgetStep(budget: number, cap: number, dt: number, moved: number, cfg: any): (number, boolean)
	local S = cfg.Server
	local allowance = math.max(0, cap) * S.SpeedTolerance
	local maxBank = allowance * S.BankSeconds + S.BankStuds
	if moved ~= moved or moved == math.huge then
		return 0, true
	end
	local b = math.min(budget + allowance * math.max(0, dt), maxBank) - moved
	if b < -S.OverdraftStuds then
		return 0, true
	end
	return b, false
end

-- Highest legal root height: the last floor it stood on + its standing root height + a jump + margin.
function MovementRules.riseLimit(supportY: number, standRootAboveFeet: number, cfg: any): number
	local jump = if cfg.Jump.Enabled then cfg.Jump.Height else 0
	return supportY + standRootAboveFeet + jump + cfg.Server.RiseMargin
end

-- A position no character can legally have.
function MovementRules.invalidPosition(p: Vector3): boolean
	for _, v in { p.X, p.Y, p.Z } do
		if v ~= v or math.abs(v) > 1e5 then
			return true
		end
	end
	return false
end

-- Deterministic state transitions (evaluated at every server check).
function MovementRules.nextState(mem: StateMemory, i: StateInput, cfg: any): (string, number)
	if i.Dead then
		return "DEAD", 0
	end
	local settling = i.Settling == true
	if not i.Grounded and not settling then
		if i.RiseSpeed > cfg.Server.JumpRiseSpeed then
			return "JUMP", 0
		end
		return "FALL", 0
	end
	if mem.State == "JUMP" or mem.State == "FALL" then
		return "LAND", i.Now + cfg.Server.LandSeconds
	end
	if mem.State == "LAND" and i.Now < mem.LandUntil then
		return "LAND", mem.LandUntil
	end
	if i.Stance == "CROUCH" then
		return "CROUCH", 0
	end
	-- hysteresis: start walking above StartSpeed, keep walking down to MovingSpeed (contact jitter is not walking)
	local threshold = if mem.State == "WALK" and not settling then cfg.Walk.MovingSpeed else cfg.Walk.StartSpeed
	if i.FlatSpeed > threshold then
		return "WALK", 0
	end
	return "IDLE", 0
end

export type IntentContext = {
	Alive: boolean,
	Stance: string,
	Locked: string?,
	StandBlocked: boolean,
}

-- A client's request. Returns (accepted, new stance, reason).
function MovementRules.intent(verb: any, value: any, ctx: IntentContext, cfg: any): (boolean, string, string)
	if verb == "Sprint" then
		return false, ctx.Stance, "sprint not built (UNKNOWN in the footage)"
	end
	if verb ~= "Crouch" then
		return false, ctx.Stance, "unknown request"
	end
	if not cfg.Crouch.Enabled then
		return false, ctx.Stance, "crouch disabled"
	end
	if type(value) ~= "boolean" then
		return false, ctx.Stance, "bad value"
	end
	if not ctx.Alive then
		return false, ctx.Stance, "dead"
	end
	if ctx.Locked then
		return false, ctx.Stance, "locked: " .. ctx.Locked
	end
	local want = if value then "CROUCH" else "STAND"
	if want == ctx.Stance then
		return true, ctx.Stance, "unchanged"
	end
	if want == "STAND" and ctx.StandBlocked then
		return false, ctx.Stance, "no room to stand"
	end
	return true, want, "ok"
end

return MovementRules
