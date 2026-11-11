--!strict
-- Focused M4 HUD test (Studio playtest only; isolated - delete the M4HudTest folder to remove it).
-- Drives StarterPlayerScripts.Client.WeaponController through its Studio-only debug hook and checks the HUD
-- (PlayerGui.M4Hud.MagazineLabel) against the predicted and the server's ammunition state.
-- Usage from the client:
--   local Run = require(game.Players.LocalPlayer.PlayerScripts.M4HudTest.Run)
--   Run("sequence")   -- the footage's reload order: Regular tactical, Regular empty, Stressed tactical, Stressed empty
--   Run("states")     -- idle / firing / full / empty / ADS / weapon switch with the label shown
--   Run("check")      -- one agreement check (HUD text vs client and server dropped-magazine counts)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local hook = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("WeaponController")
	:WaitForChild("ProductionWeaponDebug") :: BindableFunction
local BASE = "[TAB] 5.56 MAG"

local function call(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function server(): any
	call("sync")
	local t0 = os.clock()
	local s = call("state")
	while not s.server and os.clock() - t0 < 2 do
		task.wait(0.03)
		s = call("state")
	end
	return s
end

local function expectedText(dropped: number): string?
	if dropped < 1 then
		return nil
	end
	return BASE .. (if dropped > 1 then " +" .. (dropped - 1) else "")
end

-- HUD vs client prediction vs server, plus duplicate / leftover checks.
local function check(label: string?): any
	local s = server()
	local hud = s.hud
	local serverDropped = s.server and s.server.Dropped and #s.server.Dropped or -1
	local want = if s.active then expectedText(#s.dropped) else nil
	local shown = if hud.visible then hud.text else nil
	local guis = 0
	for _, g in player.PlayerGui:GetChildren() do
		if g.Name == "M4Hud" then
			guis += 1
		end
	end
	return {
		label = label,
		hudText = shown,
		expected = want,
		hudMatches = shown == want,
		clientDropped = #s.dropped,
		serverDropped = serverDropped,
		clientServerAgree = #s.dropped == serverDropped,
		mag = s.mag,
		chambered = s.chambered,
		reserve = s.reserve,
		serverMag = s.server and s.server.Mag,
		m4HudGuis = guis,
		labels = hud.labelCount,
	}
end

local function fireShots(n: number): number
	local before = call("state").shotCount
	call("trigger", true)
	local t0 = os.clock()
	while call("state").shotCount - before < n and os.clock() - t0 < 5 do
		RunService.RenderStepped:Wait()
	end
	call("trigger", false)
	frames(0.3)
	return call("state").shotCount - before
end

-- One reload; returns when the HUD text changed (clip time) and what it showed.
local function reloadAndTime(): any
	call("record", true)
	frames(0.1)
	local started = call("reload").result
	local t0 = os.clock()
	while call("state").reloading and os.clock() - t0 < 6 do
		RunService.RenderStepped:Wait()
	end
	frames(0.3)
	local rec = call("record", false)
	local before, changedAt, after = nil, nil, nil
	local seenReload = false
	for _, e in rec.log do
		if not seenReload then
			before = e.hudText
		end
		if e.reloadT then
			seenReload = true
			if e.hudText ~= before and not changedAt then
				changedAt, after = e.reloadT, e.hudText
			end
		end
	end
	return { clip = started, hudBefore = before, hudChangedAtClipTime = changedAt and math.round(changedAt * 1000) / 1000,
		hudAfter = after or before }
end

local Run = {}

function Run.check(): any
	return check("now")
end

function Run.sequence(): any
	player:SetAttribute("EquippedWeapon", "M4")
	call("aim", false)
	call("trigger", false)
	call("stressed", false)
	call("refill")
	frames(0.6)
	local out = { idle = check("idle after refill") }
	fireShots(4)
	out.tacticalRegular = reloadAndTime()
	out.afterTacticalRegular = check("after Regular tactical")
	fireShots(40)
	out.emptyMagazine = check("empty magazine")
	out.emptyRegular = reloadAndTime()
	out.afterEmptyRegular = check("after Regular empty")
	call("stressed", true)
	frames(0.3)
	fireShots(4)
	out.tacticalStressed = reloadAndTime()
	out.afterTacticalStressed = check("after Stressed tactical")
	fireShots(40)
	out.emptyStressed = reloadAndTime()
	out.afterEmptyStressed = check("after Stressed empty")
	call("stressed", false)
	return out
end

function Run.states(): any
	local out = {}
	out.shown = check("label shown")
	-- firing with the label shown (partly depleted magazine)
	fireShots(6)
	out.partialMagazine = check("after 6 shots")
	-- ADS with the label shown
	call("aim", true)
	frames(0.8)
	out.ads = check("aiming")
	call("aim", false)
	frames(0.3)
	-- full magazine: reload refused, label unchanged
	call("setAmmo", { Mag = 30, Chambered = true, Reserve = { 30, 30 }, Dropped = call("state").dropped })
	frames(0.3)
	out.fullRefused = { reload = call("reload").result, check = check("full magazine, reload refused") }
	-- weapon switch: label hidden while the blaster is out, back afterwards
	player:SetAttribute("EquippedWeapon", "TestBlaster")
	frames(0.4)
	out.switchedAway = check("test blaster equipped")
	player:SetAttribute("EquippedWeapon", "M4")
	frames(0.4)
	out.switchedBack = check("M4 again")
	return out
end

return function(name: string): any
	local f = (Run :: any)[name]
	assert(f, "unknown test " .. tostring(name))
	return f()
end
