--!strict
-- Glock audio fidelity test, client side (Studio playtest only; delete the GlockAudioTest folder to remove it). Derived from
-- MP7AudioTest (same machinery), with the Glock's own rules: a semi-automatic pistol (one shot per press, 450 RPM cap), a
-- 32-variant cycle (every shot plays the next variant whatever the time since the last one; only a put-down restarts at
-- 1). Glock audio fidelity CORRECTION: overlapping shot voices (a fixed pool of 9 per set), aimed shots centred (variant +
-- 32), the hearing equaliser (inferred model: firing-history dulling + stress-onset muffle). 21 sounds: two shot sets x 9
-- voices (each with a "Hearing" EqualizerSoundEffect) and three reload clips (the Stressed empty reload uses the Regular
-- empty clip). Checks Client.WeaponAudio in the running game through WeaponController's Studio-only debug hook ("audio"
-- command: play / stop log + the state of every weapon's sounds). Gameplay numbers stay with the accepted suites.
--   Run.assets()          the Glock's 21 sounds exist and load with the built lengths, shot voices with PlaybackRegion
--                         and a neutral Hearing equaliser, reloads without one; the config's Hearing numbers are the
--                         fitted ones (data/hearing_fit.json); no weapon without an audio config has any sound
--   Run.fire(kind)        "single" | "taps" (4 presses 0.25 s apart) | "string" (16 presses 0.165 s apart: the footage's
--                         cadence, the whole 15 + 1) | "rapid" (presses every 0.08 s: the 450 RPM cap) | "pause" (3 presses
--                         1.2 s apart) | "ads" (aimed string) | "stressed" (Stressed string) | "cycle" (34 presses 0.2 s
--                         apart, refilled: through the 32 -> 1 wrap): one sound per shot, the variant of every shot =
--                         previous + 1 (32 -> 1), the set for the state and the stance region (hip 1-32, aimed 33-64),
--                         playback inside the region, every shot voice plays its whole region (no shot cuts another:
--                         truncated = 0, recycled = 0), voices bounded by the pool, the tail plays out, the server counts
--                         every shot, the hearing equaliser = the model at every shot start and at every frame
--   Run.stance()          hip -> aim and aim -> hip inside one string: each shot's region follows its own stance, the
--                         playing voices keep theirs (no stale pan, nothing cut)
--   Run.hearing()         the inferred model in the game: isolated shot (no dulling), short / medium / long strings,
--                         pause then fire (1.6 s, then 5.6 s after), the stress onset (rising edge only), stress continuation
--   Run.reloads()         the four reloads (Stressed empty = the Regular empty clip and sound): the clip's own sound
--                         starts with the clip, runs in step with it and is over when the reload is; reload -> fire
--   Run.interrupt()       weapon switch during a reload / during a shot tail, firing during a reload (refused, no
--                         sound), a reload cancelled by a correction: the sound stops at once
--   Run.death(phase)      "before": fire + start a reload, watch for the death; then on the Server set the humanoid's
--                         Health to 0; "after" (once respawned): nothing played on at death, the next shot is variant 1
--   Run.switching()       Glock -> M4 -> AK -> MP7 -> Sniper -> Glock while firing, then Glock <-> Sniper x3: nothing of a
--                         put-down weapon plays, one Glock folder, every re-equip starts the cycle at 1
--   Run.security()        a probe WeaponAudio flooded with 1000 shots in one frame and odd inputs: no instance created,
--                         voices bounded by the pool, the hearing history bounded, regions always inside the sprite
--   Run.perf()            cost of WeaponAudio:Shot / reload, sound objects, frame times (idle, Glock rapid presses, Glock
--                         string, empty reload; M4 / AK / MP7 sustained fire, all with audio)
--   Run.timeline(kind)    raw play log (for the offline comparison)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local hook = client:WaitForChild("WeaponController"):WaitForChild("ProductionWeaponDebug") :: BindableFunction
local AUDIO_CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Audio")
	:WaitForChild("Glock")) :: any
local HCFG = AUDIO_CFG.Hearing

local Run = {}
local POOL = 9 -- ceil(1.0 / (60 / 450)) + 1
local EXPECTED: { [string]: number } = { ReloadTacticalRegular = 2.9667, ReloadTacticalStressed = 2.4333,
	ReloadEmptyRegular = 3.4 }
for _, set in { "Regular", "Stressed" } do
	for i = 1, POOL do
		EXPECTED["Shot" .. set .. i] = 64.0 -- 32 hip variants + the same 32 centred
	end
end
local VARIANT = 1.0 -- s per variant in the shot sprites (Config.Audio.Glock)
local COUNT = 32
local AIMED_OFFSET = 32
local INTERVAL = 60 / 450
local CLIP_OF = { EmptyStressed = "EmptyRegular" } -- Config.Weapons.Glock.Reloads.*.Clip where it differs from the name
-- the fitted hearing model (data/hearing_fit.json, family F1 + stress onset): the config must carry these numbers
local FIT = { Delay = 0.1, Release = 1.5, Saturation = 3.0, Gains = { -0.84, -3.52, -7.72 }, OnsetGains = { 0, -9, -30 },
	OnsetDecay = 0.9 }
local GAIN_TOL = 0.02 -- dB: the game's equaliser vs the test's own evaluation of the model

local function w(cmd: string, arg: any?): any
	return hook:Invoke(cmd, arg)
end

local function frames(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		RunService.RenderStepped:Wait()
	end
end

local function r3(x: number?): number?
	return if x then math.round(x * 1000) / 1000 else nil
end

local function equip(id: string)
	player:SetAttribute("EquippedWeapon", id)
	frames(0.5)
end

local function ownFolder(): Folder?
	return SoundService:FindFirstChild("WeaponAudio_Glock") :: Folder?
end

local function glockState(): any
	return w("audio").audio.Glock
end

local function weaponFolderPlaying(): { [string]: number }
	local out = {}
	for _, c in SoundService:GetChildren() do
		if string.sub(c.Name, 1, 12) == "WeaponAudio_" then
			local n = 0
			for _, s in c:GetChildren() do
				if s:IsA("Sound") and s.IsPlaying then
					n += 1
				end
			end
			out[string.sub(c.Name, 13)] = n
		end
	end
	return out
end

local function soundCount(): number
	local n = 0
	for _, d in SoundService:GetDescendants() do
		if d:IsA("Sound") or d:IsA("SoundEffect") then
			n += 1
		end
	end
	return n
end

-- playing sounds: of the Glock's own folder (shot voices / reload), and anywhere else outside the character (default
-- character sounds) and outside the weapons' own audio folders (checked separately)
local function playing(): (number, number, number, { string })
	local shot, reload, other, names = 0, 0, 0, {}
	local f = ownFolder()
	if f then
		for _, s in f:GetChildren() do
			if s:IsA("Sound") and s.IsPlaying then
				if string.sub(s.Name, 1, 4) == "Shot" then
					shot += 1
				else
					reload += 1
				end
				table.insert(names, s.Name)
			end
		end
	end
	for _, root in { SoundService :: Instance, workspace, player:FindFirstChildOfClass("PlayerGui") :: Instance } do
		for _, d in root:GetDescendants() do
			if d:IsA("Sound") and d.IsPlaying and not (f and d:IsDescendantOf(f))
				and not (player.Character and d:IsDescendantOf(player.Character))
				and not (d.Parent and d.Parent.Parent == SoundService and string.sub(d.Parent.Name, 1, 12) == "WeaponAudio_") then
				other += 1
				table.insert(names, d:GetFullName())
			end
		end
	end
	return shot, reload, other, names
end

local function serverState(timeout: number): any
	w("sync")
	local t0 = os.clock()
	local s = w("state")
	while not s.server and os.clock() - t0 < timeout do
		task.wait(0.05)
		s = w("state")
	end
	return s
end

local function stats(xs: { number }): any
	if #xs == 0 then
		return { n = 0 }
	end
	local sum, mx, mn = 0, -math.huge, math.huge
	for _, x in xs do
		sum += x
		mx = math.max(mx, x)
		mn = math.min(mn, x)
	end
	local mean = sum / #xs
	local v = 0
	for _, x in xs do
		v += (x - mean) ^ 2
	end
	return { n = #xs, mean = r3(mean), sd = r3(math.sqrt(v / #xs)), min = r3(mn), max = r3(mx) }
end

local function nextPos(p: number): number
	return if p >= COUNT then 1 else p + 1
end

-- the test's own evaluation of the hearing model (independent of WeaponAudio's code): shots = start times (os.clock),
-- own = the index of the voice's own shot (not counted), h0 = the history left from before the pattern, measured at t0
-- (all of it already past Delay then), onsetAt = the stress onset (or nil)
local function model(t: number, shots: { number }, own: number?, h0: number, t0: number, onsetAt: number?): { number }
	local h = h0 * math.exp(-(t - t0) / HCFG.Release)
	for i, u in shots do
		local age = t - u - HCFG.Delay
		if i ~= own and age >= 0 then
			h += math.exp(-age / HCFG.Release)
		end
	end
	local x = 1 - math.exp(-h / HCFG.Saturation)
	local m = if onsetAt and t >= onsetAt then math.exp(-(t - onsetAt) / HCFG.StressOnset.Decay) else 0
	local g, og = HCFG.Gains, HCFG.StressOnset.Gains
	return { g.Low * x + og.Low * m, g.Mid * x + og.Mid * m, g.High * x + og.High * m }
end

local function gainErr(a: { number }, b: { number }): number
	return math.max(math.abs(a[1] - b[1]), math.abs(a[2] - b[2]), math.abs(a[3] - b[3]))
end

function Run.assets(): any
	equip("Glock")
	local f = ownFolder()
	local out: any = { folder = f ~= nil, sounds = {}, otherFolders = {} }
	local ok = f ~= nil
	if f then
		for name, len in EXPECTED do
			local s = f:FindFirstChild(name) :: Sound?
			local t0 = os.clock()
			while s and not s.IsLoaded and os.clock() - t0 < 5 do
				task.wait(0.05)
			end
			local isShot = string.sub(name, 1, 4) == "Shot"
			local eq = if s then s:FindFirstChildOfClass("EqualizerSoundEffect") else nil
			out.sounds[name] = if s then { loaded = s.IsLoaded, length = r3(s.TimeLength), volume = s.Volume,
				looped = s.Looped, regions = s.PlaybackRegionsEnabled, hearingEq = eq ~= nil } else false
			ok = ok and s ~= nil and s.IsLoaded and math.abs(s.TimeLength - len) < 0.003 and not s.Looped
				and s.PlaybackRegionsEnabled == isShot and (eq ~= nil) == isShot and #s:GetChildren() == (if isShot then 1 else 0)
		end
		out.count = #f:GetChildren()
		ok = ok and out.count == 21
		local sid = (f:FindFirstChild("ShotRegular1") :: Sound).SoundId
		out.shotRegularId = sid
	end
	for _, c in SoundService:GetChildren() do
		if string.sub(c.Name, 1, 12) == "WeaponAudio_" and c ~= f then
			table.insert(out.otherFolders, c.Name)
		end
	end
	local st = w("audio")
	out.perWeapon = {}
	for id, a in st.audio do
		out.perWeapon[id] = { hasAudio = a.hasAudio, sounds = a.sounds, voices = a.voices, overlap = a.overlap,
			hearing = a.hearing ~= nil }
		if id ~= "Glock" and not a.hasAudio then
			ok = ok and a.sounds == 0 -- a weapon without a Config.Audio module has no sound at all
		end
		if id ~= "Glock" then
			ok = ok and a.overlap == false and a.hearing == nil -- M4 / AK / MP7 keep one voice, no equaliser
		end
	end
	ok = ok and st.audio.Glock.overlap == true and st.audio.Glock.voices == POOL
	local foldersOk = true
	for _, name in out.otherFolders do
		local id = string.sub(name, 13)
		foldersOk = foldersOk and st.audio[id] ~= nil and st.audio[id].hasAudio == true
	end
	-- the config's numbers are the fitted model's
	local cfgOk = HCFG.Delay == FIT.Delay and HCFG.Release == FIT.Release and HCFG.Saturation == FIT.Saturation
		and HCFG.Gains.Low == FIT.Gains[1] and HCFG.Gains.Mid == FIT.Gains[2] and HCFG.Gains.High == FIT.Gains[3]
		and HCFG.StressOnset.Gains.Low == FIT.OnsetGains[1] and HCFG.StressOnset.Gains.Mid == FIT.OnsetGains[2]
		and HCFG.StressOnset.Gains.High == FIT.OnsetGains[3] and HCFG.StressOnset.Decay == FIT.OnsetDecay
		and AUDIO_CFG.Shot.Overlap == true and AUDIO_CFG.Shot.AimedOffset == AIMED_OFFSET
	out.configMatchesFit = cfgOk
	out.soundMemoryMb = r3(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds))
	out.pass = ok and foldersOk and cfgOk
	return out
end

local function press()
	w("trigger", true)
	RunService.RenderStepped:Wait()
	w("trigger", false)
end

local function aimAlpha(): number?
	local o = w("optic", "Glock")
	return if o and o.aimAlpha then r3(o.aimAlpha) else nil
end

local function waitAttr(want: boolean, timeout: number): number?
	local t0 = os.clock()
	while (player:GetAttribute("Stressed") == true) ~= want and os.clock() - t0 < timeout do
		RunService.RenderStepped:Wait()
	end
	return if (player:GetAttribute("Stressed") == true) == want then os.clock() else nil
end

local PATTERNS: { [string]: any } = {
	single = { presses = 1, gap = 0 },
	taps = { presses = 4, gap = 0.25 },
	string = { presses = 16, gap = 0.165 },
	short = { presses = 4, gap = 0.165 },
	medium = { presses = 8, gap = 0.165 },
	long = { presses = 16, gap = 0.165 },
	rapid = { rapid = 12 },
	pause = { presses = 3, gap = 1.2 },
	ads = { presses = 16, gap = 0.165, aim = true },
	stressed = { presses = 16, gap = 0.165, stressed = true, setup = 0.6 },
	stressOnset = { presses = 4, gap = 0.165, stressed = true, setup = 0 },
	stressHold = { presses = 4, gap = 0.165, stressed = true, setup = 3.0 },
	-- a full string, then one shot 1.6 s after its last one (the reference's thud probe: still dulled), then one 4.0 s
	-- after that (recovered)
	pauseThenFire = { presses = 16, gap = 0.165, after = { 1.6, 4.0 } },
	cycle = { presses = 34, gap = 0.2, refillEvery = 14 },
	hipToAim = { presses = 6, gap = 0.2, aimAt = 4 },
	aimToHip = { presses = 6, gap = 0.2, aim = true, unaimAt = 4 },
}

-- fire a pattern; returns the shot times, the audio log, per-frame voice counts, region / lifetime checks, the hearing
-- equaliser samples and the tail end
local function firePattern(kind: string, opts: any?): any
	local p = PATTERNS[kind]
	equip("Glock")
	w("refill")
	frames(0.5)
	local s0 = serverState(2)
	local maxShot, maxOther, maxTotal = 0, 0, 0
	local regionSamples, regionBad = 0, 0
	local life: { [string]: any } = {}
	local lives, truncated = {}, 0
	local eqSamples = {}
	local function sample()
		local a, b, c = playing()
		maxShot = math.max(maxShot, a)
		maxOther = math.max(maxOther, c)
		maxTotal = math.max(maxTotal, a + b)
		local f = ownFolder()
		if f then
			for _, s in f:GetChildren() do
				if s:IsA("Sound") and string.sub(s.Name, 1, 4) == "Shot" then
					local L = life[s.Name]
					if s.IsPlaying then
						regionSamples += 1
						local r = s.PlaybackRegion
						if s.TimePosition < r.Min - 0.001 or s.TimePosition > r.Max + 0.03
							or math.abs((r.Max - r.Min) - VARIANT) > 1e-6 then
							regionBad += 1
						end
						local played = s.TimePosition - r.Min
						if L and (math.abs(L.min - r.Min) > 1e-6 or played < L.played - 0.02) then
							-- the voice was restarted while it was playing: its previous life was cut
							if L.played < VARIANT - 0.05 then
								truncated += 1
							end
							table.insert(lives, L.played)
							L = nil
						end
						if not L then
							life[s.Name] = { min = r.Min, played = played }
						else
							L.played = played
						end
					elseif L then
						table.insert(lives, L.played)
						life[s.Name] = nil
					end
				end
			end
		end
		-- every playing voice's equaliser, as last applied, with its own shot (evaluated against the model afterwards)
		local st = glockState()
		for _, v in st.playing do
			if v.eq and v.eqAt and v.shotAt then
				table.insert(eqSamples, { eq = v.eq, eqAt = v.eqAt, shotAt = v.shotAt })
			end
		end
	end
	local function hold(seconds: number)
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			RunService.RenderStepped:Wait()
			sample()
		end
	end
	local onsetSeen: number? = nil
	if p.aim then
		w("aim", true)
		hold(0.6)
	end
	if p.stressed then
		w("stressed", true)
		onsetSeen = waitAttr(true, 2)
		if (p.setup or 0) > 0 then
			hold(p.setup)
		end
	end
	-- the history left from before the pattern (all of it past Delay by now: the last shot was >= 0.1 s ago)
	local st0 = glockState()
	local h0, t0h = st0.hearing.history, st0.hearing.clock
	w("audio", true)
	w("record", true)
	local alphas = {}
	if p.rapid then
		-- a press every 0.08 s, each held 0.07 s: a press that lands inside the fire cycle is held through its end and
		-- fires there (FireController Semi), so the shots come at the 450 RPM cap
		for _ = 1, p.rapid do
			w("trigger", true)
			hold(0.07)
			w("trigger", false)
			hold(0.01)
		end
	else
		for i = 1, p.presses do
			if p.aimAt == i then
				w("aim", true)
				hold(0.6)
			elseif p.unaimAt == i then
				w("aim", false)
				hold(0.6)
			end
			if p.refillEvery and i > 1 and (i - 1) % p.refillEvery == 0 then
				w("refill")
			end
			table.insert(alphas, aimAlpha())
			press()
			if i < p.presses then
				hold(p.gap)
			end
		end
		for _, pause in p.after or {} do
			w("refill") -- the string emptied the 15 + 1 (refill touches no sound)
			hold(pause)
			press()
		end
	end
	local released = os.clock()
	local tailEnd: number? = nil
	while os.clock() - released < 2.0 do
		RunService.RenderStepped:Wait()
		sample()
		local a = playing()
		if a == 0 and not tailEnd then
			tailEnd = os.clock()
		elseif a > 0 then
			tailEnd = nil
		end
	end
	for _, L in life do
		table.insert(lives, L.played)
	end
	local stEnd = glockState()
	w("aim", false)
	if p.stressed and not (opts and opts.keepStressed) then
		w("stressed", false)
		waitAttr(false, 2)
	end
	local rec = w("record", false)
	local logs = w("audio", false)
	local s1 = serverState(2)
	local shotTimes = rec.shots or {}
	local events = {}
	for _, e in logs.logs.Glock or {} do
		if e.kind == "shot" then
			table.insert(events, e)
		end
	end
	local delays, gapsShot = {}, {}
	for i, e in events do
		table.insert(delays, e.at - e.t)
		if i > 1 then
			table.insert(gapsShot, e.t - events[i - 1].t)
		end
	end
	local names, positions, aimedFlags, regionStarts, recycled = {}, {}, {}, {}, 0
	for _, e in events do
		table.insert(names, e.name)
		table.insert(positions, e.position)
		table.insert(aimedFlags, e.aimed)
		table.insert(regionStarts, e.regionStart)
		if e.recycled then
			recycled += 1
		end
	end
	-- the hearing equaliser vs the model: at every shot start (the logged gains) and at every frame (each voice)
	local onsetAt = stEnd.hearing.stressOnsetAt
	-- the shots' start times as WeaponAudio counts them (its os.clock before Play; the log's `at` comes after Play):
	-- taken from the voices' own shotAt, sampled every frame while they played
	local starts, startLag = {}, 0
	for _, e in events do
		local u = e.at
		for _, sm in eqSamples do
			if math.abs(sm.shotAt - e.at) < 5e-3 then
				u = sm.shotAt
				break
			end
		end
		startLag = math.max(startLag, e.at - u)
		table.insert(starts, u)
	end
	local startErr, startGains = 0, {}
	for i, e in events do
		local m = model(starts[i], starts, i, h0, t0h, onsetAt)
		startErr = math.max(startErr, gainErr(e.gains, m))
		table.insert(startGains, { r3(e.gains[1]), r3(e.gains[2]), r3(e.gains[3]) })
	end
	local frameErr, frameN, unmatched = 0, 0, 0
	for _, sm in eqSamples do
		local own = nil
		for i, u in starts do
			if math.abs(u - sm.shotAt) < 1e-3 then
				own = i
			end
		end
		if own then
			frameN += 1
			frameErr = math.max(frameErr, gainErr(sm.eq, model(sm.eqAt, starts, own, h0, t0h, onsetAt)))
		else
			unmatched += 1 -- a voice of an earlier pattern still playing (none expected: the patterns end silent)
		end
	end
	local lastShot = shotTimes[#shotTimes]
	local acc = s0.server and s1.server and (s1.server.Accepted or 0) - (s0.server.Accepted or 0)
	local minLife = math.huge
	for _, l in lives do
		minLife = math.min(minLife, l)
	end
	return { kind = kind, shots = #shotTimes, shotSounds = #events, names = names, positions = positions,
		aimed = aimedFlags, regionStarts = regionStarts, alphas = alphas, events = events, shotTimes = shotTimes,
		regionSamples = regionSamples, regionBad = regionBad, lives = #lives, minLife = r3(minLife), truncated = truncated,
		recycled = recycled, playDelay = stats(delays), shotSpacing = stats(gapsShot),
		maxShotVoices = maxShot, maxWeaponVoices = maxTotal, maxOtherSounds = maxOther,
		tailAfterLastShot = if tailEnd and lastShot then r3(tailEnd - lastShot) else nil,
		serverAccepted = acc, otherLog = logs.logs,
		hearing = { h0 = r3(h0), startErr = r3(startErr), frameErr = r3(frameErr), frameSamples = frameN,
			unmatched = unmatched, startGains = startGains, onsetAt = onsetAt, onsetSeen = onsetSeen,
			historyShots = stEnd.hearing.shots, playLagMs = r3(startLag * 1000) } }
end

local EXPECT_SHOTS = { single = 1, taps = 4, pause = 3, string = 16, ads = 16, stressed = 16, cycle = 34, short = 4,
	medium = 8, long = 16, stressOnset = 4, stressHold = 4, hipToAim = 6, aimToHip = 6, pauseThenFire = 18 }

-- the shot rules every pattern must keep; aimedAt(i) = whether press i was aimed
local function judge(r: any, set: string, aimedAt: (number) -> boolean): any
	local seqOk = #r.positions == r.shots and r.shots > 0
	for i = 1, #r.positions do
		local wantAimed = aimedAt(i)
		seqOk = seqOk and string.sub(r.names[i], 1, #set) == set and (i == 1 or r.names[i] ~= r.names[i - 1])
			and (i == 1 or r.positions[i] == nextPos(r.positions[i - 1]))
			and r.aimed[i] == wantAimed
			and r.regionStarts[i] == (r.positions[i] - 1 + (if wantAimed then AIMED_OFFSET else 0)) * VARIANT
	end
	local othersSilent = true
	for id, l in r.otherLog do
		if id ~= "Glock" and l and #l > 0 then
			othersSilent = false
		end
	end
	local out = { kind = r.kind, shots = r.shots, shotSounds = r.shotSounds, sequenceOk = seqOk, positions = r.positions,
		regionSamples = r.regionSamples, regionBad = r.regionBad, lives = r.lives, minLife = r.minLife,
		truncated = r.truncated, recycled = r.recycled, playDelay = r.playDelay, shotSpacing = r.shotSpacing,
		maxShotVoices = r.maxShotVoices, maxWeaponVoices = r.maxWeaponVoices, maxOtherSounds = r.maxOtherSounds,
		tailAfterLastShot = r.tailAfterLastShot, serverAccepted = r.serverAccepted, othersSilent = othersSilent,
		alphas = r.alphas, hearing = r.hearing }
	local want = EXPECT_SHOTS[r.kind]
	out.pass = r.shots > 0 and r.shotSounds == r.shots and seqOk and r.maxShotVoices <= POOL and r.maxOtherSounds == 0
		and r.truncated == 0 and r.recycled == 0 and r.lives == r.shots and (r.minLife or 0) >= VARIANT - 0.05
		and (r.tailAfterLastShot or 99) < 1.2 and r.serverAccepted == r.shots and othersSilent
		and r.regionBad == 0 and r.regionSamples > 0 and (want == nil or r.shots == want)
		and (r.kind ~= "rapid" or (r.shots >= 6 and (r.shotSpacing.min or 0) >= INTERVAL - 0.002))
		and (r.kind ~= "single" or r.maxShotVoices == 1)
		and r.hearing.startErr <= GAIN_TOL and r.hearing.frameErr <= GAIN_TOL and r.hearing.frameSamples > 0
		and r.hearing.unmatched == 0
	return out
end

function Run.fire(kind: string?): any
	local k = kind or "string"
	local r = firePattern(k)
	local set = if k == "stressed" or k == "stressOnset" or k == "stressHold" then "ShotStressed" else "ShotRegular"
	local out = judge(r, set, function(_i)
		return k == "ads"
	end)
	-- overlap: a string at the footage's cadence keeps several shots sounding at once (the reference: up to 5 - 7)
	if k == "string" or k == "ads" or k == "stressed" or k == "rapid" or k == "cycle" then
		out.pass = out.pass and r.maxShotVoices >= 5
	end
	return out
end

function Run.stance(): any
	local out: any = {}
	-- hip -> aim: presses 1-3 hip, 4-6 aimed; aim -> hip: presses 1-3 aimed, 4-6 hip
	local a = firePattern("hipToAim")
	out.hipToAim = judge(a, "ShotRegular", function(i)
		return i >= 4
	end)
	local b = firePattern("aimToHip")
	out.aimToHip = judge(b, "ShotRegular", function(i)
		return i < 4
	end)
	out.pass = out.hipToAim.pass and out.aimToHip.pass
	return out
end

local function waitQuietHistory(limit: number, timeout: number): number
	local t0 = os.clock()
	local h = glockState().hearing.history
	while h > limit and os.clock() - t0 < timeout do
		task.wait(0.25)
		h = glockState().hearing.history
	end
	return h
end

local function high(r: any, i: number): number?
	local g = r.hearing.startGains[i]
	return if g then g[3] else nil
end

function Run.hearing(): any
	local out: any = {}
	equip("Glock")
	w("stressed", false)
	waitAttr(false, 2)
	-- isolated: after the history has decayed (h < 0.001: < 0.003 dB anywhere), one shot is not dulled at all
	out.historyBeforeIsolated = r3(waitQuietHistory(1e-3, 25))
	local iso = firePattern("single")
	out.isolated = judge(iso, "ShotRegular", function(_i)
		return false
	end)
	out.isolated.gains = iso.hearing.startGains[1]
	local isoOk = out.isolated.pass and math.abs(iso.hearing.startGains[1][3]) < 0.01
	-- strings: the dulling builds up shot by shot (High at shots 1, 2, 4, 8, 16 of each)
	local strOk = true
	for _, k in { "short", "medium", "long" } do
		waitQuietHistory(1e-3, 25)
		local r = firePattern(k)
		local j = judge(r, "ShotRegular", function(_i)
			return false
		end)
		j.highAt = { high(r, 1), high(r, 2), high(r, 4), high(r, 8), high(r, 16) }
		out[k] = j
		strOk = strOk and j.pass
	end
	-- pause then fire: a string, one shot 1.6 s after its last one (still dulled), one 4.0 s after that (recovered)
	waitQuietHistory(1e-3, 25)
	local pt = firePattern("pauseThenFire")
	out.pauseThenFire = judge(pt, "ShotRegular", function(_i)
		return false
	end)
	out.pauseThenFire.highAt = { last = high(pt, 16), after1_6s = high(pt, 17), after5_6s = high(pt, 18) }
	local pauseOk = out.pauseThenFire.pass and (high(pt, 17) or 0) < -2 and (high(pt, 18) or -99) > (high(pt, 17) or 0) + 1.5
	-- the stress onset: fire right after Stressed turns on (the onset muffle), then while it stays on (continuation)
	frames(1.0)
	local before = glockState().hearing.stressOnsetAt
	local so = firePattern("stressOnset", { keepStressed = true })
	out.stressOnset = judge(so, "ShotStressed", function(_i)
		return false
	end)
	out.stressOnset.onsetLag = if so.hearing.onsetAt and so.hearing.onsetSeen then r3(so.hearing.onsetSeen - so.hearing.onsetAt)
		else nil
	out.stressOnset.firstHigh = high(so, 1)
	local onsetOk = out.stressOnset.pass and so.hearing.onsetAt ~= nil and so.hearing.onsetAt ~= before
		and math.abs(out.stressOnset.onsetLag or 99) < 0.05 and (high(so, 1) or 0) < -15
	-- continuation: Stressed stays on (setting it again is not a new onset), 3 s later the muffle has decayed
	local sh = firePattern("stressHold", { keepStressed = true })
	out.stressHold = judge(sh, "ShotStressed", function(_i)
		return false
	end)
	out.stressHold.firstHigh = high(sh, 1)
	local holdOk = out.stressHold.pass and sh.hearing.onsetAt == so.hearing.onsetAt
		and (high(sh, 1) or -99) > (high(so, 1) or 0) + 10
	-- off -> on again: a new onset
	w("stressed", false)
	waitAttr(false, 2)
	frames(0.3)
	w("stressed", true)
	local seen = waitAttr(true, 2)
	frames(0.1)
	local again = glockState().hearing.stressOnsetAt
	out.reOnset = { previous = so.hearing.onsetAt, new = again, lag = if seen and again then r3(seen - again) else nil }
	local reOk = again ~= nil and again ~= so.hearing.onsetAt and math.abs(out.reOnset.lag or 99) < 0.05
	w("stressed", false)
	waitAttr(false, 2)
	-- the hearing state is the player's: a weapon switch keeps it (it decays with time)
	local hA = glockState().hearing
	equip("Sniper")
	local hB = glockState().hearing
	local predicted = hA.history * math.exp(-(hB.clock - hA.clock) / HCFG.Release)
	out.switchKeepsHistory = { before = r3(hA.history), after = r3(hB.history), predicted = r3(predicted) }
	local switchOk = math.abs(hB.history - predicted) < 1e-3 + 1e-3 * predicted
	equip("Glock")
	out.pass = isoOk and strOk and pauseOk and onsetOk and holdOk and reOk and switchOk
	return out
end

function Run.timeline(kind: string?): any
	local r = firePattern(kind or "string")
	local ev = {}
	for _, e in r.events do
		table.insert(ev, { name = e.name, position = e.position, aimed = e.aimed, regionStart = e.regionStart,
			gains = e.gains, t = e.t - r.events[1].t, at = e.at - r.events[1].t })
	end
	return { kind = r.kind, events = ev }
end

local function reloadOnce(stressed: boolean, empty: boolean): any
	equip("Glock")
	w("stressed", stressed)
	waitAttr(stressed, 2)
	w("refill")
	frames(0.4)
	if empty then
		w("setAmmo", { Mag = 0, Chambered = false, Reserve = { 15, 15 } })
	else
		w("setAmmo", { Mag = 5, Chambered = true, Reserve = { 15, 15 } })
	end
	frames(0.6)
	w("audio", true)
	local t0 = os.clock()
	local res = w("reload")
	local spec: string? = nil
	local offsets = {}
	local reloadEnd: number? = nil
	local soundEnd: number? = nil
	local soundName: string? = nil
	local maxOther = 0
	local reloadEqs = 0
	while os.clock() - t0 < 5.0 do
		RunService.RenderStepped:Wait()
		local now = os.clock()
		local st = w("sync")
		if st.reloading then
			spec = st.reloading
		elseif spec and not reloadEnd then
			reloadEnd = now
		end
		local f = ownFolder() :: Folder
		local anyPlaying = false
		for _, s in f:GetChildren() do
			if s:IsA("Sound") and s.IsPlaying and string.sub(s.Name, 1, 6) == "Reload" then
				anyPlaying = true
				soundName = s.Name
				reloadEqs += #s:GetChildren() -- reload sounds carry no equaliser
				if s.TimePosition > 0.05 then
					table.insert(offsets, s.TimePosition - (now - t0))
				end
			end
		end
		if soundName and not anyPlaying and not soundEnd then
			soundEnd = now
		end
		local _, _, o = playing()
		maxOther = math.max(maxOther, o)
		if reloadEnd and soundEnd then
			break
		end
	end
	-- reload -> fire: the next press after the reload plays a shot sound
	frames(0.2)
	press()
	frames(0.3)
	local logs = w("audio", false)
	local starts, shotsAfter = 0, 0
	for _, e in logs.logs.Glock or {} do
		if e.kind == "reload" then
			starts += 1
		elseif e.kind == "shot" then
			shotsAfter += 1
		end
	end
	local clip = if spec then (CLIP_OF[spec] or spec) else nil
	return { request = res.result, spec = spec, clip = clip, sound = soundName, starts = starts,
		reloadSeconds = if reloadEnd then r3(reloadEnd - t0) else nil,
		soundSeconds = if soundEnd then r3(soundEnd - t0) else nil,
		syncOffset = stats(offsets), maxOtherSounds = maxOther, shotSoundsAfterReload = shotsAfter, reloadEqs = reloadEqs,
		pass = clip ~= nil and soundName == "Reload" .. clip and starts == 1 and reloadEnd ~= nil and soundEnd ~= nil
			and math.abs((soundEnd :: number) - (reloadEnd :: number)) < 0.1 and maxOther == 0 and shotsAfter == 1
			and reloadEqs == 0 }
end

function Run.reloads(): any
	local out: any = {
		tacticalRegular = reloadOnce(false, false),
		emptyRegular = reloadOnce(false, true),
		tacticalStressed = reloadOnce(true, false),
		emptyStressed = reloadOnce(true, true),
	}
	w("stressed", false)
	waitAttr(false, 2)
	local ok = true
	for _, r in { out.tacticalRegular, out.emptyRegular, out.tacticalStressed, out.emptyStressed } do
		ok = ok and r.pass
	end
	out.pass = ok
	return out
end

local function quietWithin(seconds: number): number?
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		local a, b = playing()
		if a + b == 0 then
			return r3(os.clock() - t0)
		end
		RunService.RenderStepped:Wait()
	end
	return nil
end

function Run.interrupt(): any
	local out: any = {}
	-- a) switch during a reload
	equip("Glock")
	w("refill")
	frames(0.4)
	w("setAmmo", { Mag = 5, Chambered = true, Reserve = { 15, 15 } })
	frames(0.6)
	w("reload")
	frames(1.0)
	local _, rb = playing()
	player:SetAttribute("EquippedWeapon", "Sniper") -- switch away from the Glock (a weapon without audio)
	out.switchDuringReload = { reloadPlayingBefore = rb, stoppedAfter = quietWithin(0.5) }
	frames(0.3)
	-- b) switch during the shot tails (three overlapping voices)
	equip("Glock")
	w("refill")
	frames(0.4)
	for _ = 1, 3 do
		press()
		frames(0.17)
	end
	local sa = playing()
	player:SetAttribute("EquippedWeapon", "Sniper")
	out.switchDuringTail = { shotPlayingBefore = sa, stoppedAfter = quietWithin(0.5) }
	frames(0.3)
	-- c) firing during a reload: refused by the controller, so no shot sound; the reload sound carries on
	equip("Glock")
	w("refill")
	frames(0.4)
	w("setAmmo", { Mag = 5, Chambered = true, Reserve = { 15, 15 } })
	frames(0.6)
	w("audio", true)
	w("reload")
	frames(0.5)
	for _ = 1, 3 do
		press()
		frames(0.2)
	end
	local _, rb2 = playing()
	frames(1.9)
	local logs = w("audio", false)
	local shotsDuring = 0
	for _, e in logs.logs.Glock or {} do
		if e.kind == "shot" then
			shotsDuring += 1
		end
	end
	out.fireDuringReload = { shotSounds = shotsDuring, reloadStillPlaying = rb2 }
	-- d) a reload cancelled by a correction (the refill path cancels the reload like ReloadCancelled does)
	w("setAmmo", { Mag = 5, Chambered = true, Reserve = { 15, 15 } })
	frames(0.6)
	w("reload")
	frames(0.8)
	local _, rb3 = playing()
	w("refill")
	out.cancelledReload = { reloadPlayingBefore = rb3, stoppedAfter = quietWithin(0.3) }
	frames(0.5)
	out.pass = out.switchDuringReload.reloadPlayingBefore == 1 and out.switchDuringReload.stoppedAfter ~= nil
		and out.switchDuringReload.stoppedAfter < 0.1 and out.switchDuringTail.shotPlayingBefore == 3
		and out.switchDuringTail.stoppedAfter ~= nil and out.switchDuringTail.stoppedAfter < 0.1
		and out.fireDuringReload.shotSounds == 0 and out.fireDuringReload.reloadStillPlaying == 1
		and out.cancelledReload.reloadPlayingBefore == 1 and out.cancelledReload.stoppedAfter ~= nil
		and out.cancelledReload.stoppedAfter < 0.1
	return out
end

local deathWatch: any = nil

function Run.death(phase: string): any
	if phase == "before" then
		equip("Glock")
		w("refill")
		frames(0.4)
		press()
		frames(0.17)
		press()
		frames(0.1)
		w("setAmmo", { Mag = 5, Chambered = true, Reserve = { 15, 15 } })
		frames(0.2)
		w("reload")
		frames(0.2)
		local a, b = playing()
		deathWatch = { playingBefore = { shot = a, reload = b }, soundsBefore = soundCount() }
		local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.Died:Once(function()
			local t0 = os.clock()
			deathWatch.diedAt = t0
			deathWatch.stoppedAfter = quietWithin(0.5)
		end)
		return deathWatch
	end
	frames(0.8)
	equip("Glock")
	w("refill")
	frames(0.4)
	w("audio", true)
	press()
	frames(0.3)
	local logs = w("audio", false)
	local first = nil
	for _, e in logs.logs.Glock or {} do
		if e.kind == "shot" then
			first = e.position
			break
		end
	end
	local folders = 0
	for _, c in SoundService:GetChildren() do
		if c.Name == "WeaponAudio_Glock" then
			folders += 1
		end
	end
	local out = { watch = deathWatch, firstShotPositionAfterRespawn = first, glockFolders = folders,
		soundsAfter = soundCount() }
	out.pass = deathWatch ~= nil and deathWatch.diedAt ~= nil and deathWatch.stoppedAfter ~= nil
		and deathWatch.stoppedAfter < 0.1 and (deathWatch.playingBefore.shot + deathWatch.playingBefore.reload) >= 2
		and first == 1 and folders == 1 and out.soundsAfter == deathWatch.soundsBefore
	quietWithin(3)
	return out
end

function Run.switching(): any
	local out: any = { steps = {}, reequip = {} }
	local ok = true
	local soundsBefore = soundCount()
	for _, id in { "Glock", "M4", "AK", "MP7", "Sniper", "Glock" } do
		equip(id)
		w("refill")
		frames(0.3)
		local a0, b0 = playing()
		if id == "Glock" then
			press()
		else
			w("trigger", true)
		end
		frames(0.4)
		local a1, _, o1 = playing()
		local third = 0
		for wid, n in weaponFolderPlaying() do
			if wid ~= "Glock" and wid ~= id then
				third += n
			end
		end
		w("trigger", false)
		frames(0.2)
		table.insert(out.steps, { weapon = id, ownPlayingOnEquip = a0 + b0, ownShotVoicesWhileFiring = a1, otherSounds = o1,
			otherWeaponFolderSounds = third })
		if id == "Glock" then
			ok = ok and a1 == 1 and o1 == 0 and third == 0
		else
			ok = ok and a0 + b0 == 0 and a1 == 0 and o1 == 0 and third == 0
		end
	end
	quietWithin(3)
	-- repeated equip: Sniper -> Glock (2 presses), three times: the cycle restarts at 1 on every equip, one folder
	for _ = 1, 3 do
		equip("Sniper")
		frames(0.2)
		equip("Glock")
		w("refill")
		frames(0.3)
		w("audio", true)
		press()
		frames(0.2)
		press()
		frames(0.3)
		local logs = w("audio", false)
		local pos = {}
		for _, e in logs.logs.Glock or {} do
			if e.kind == "shot" then
				table.insert(pos, e.position)
			end
		end
		local folders = 0
		for _, c in SoundService:GetChildren() do
			if c.Name == "WeaponAudio_Glock" then
				folders += 1
			end
		end
		table.insert(out.reequip, { positions = pos, folders = folders })
		ok = ok and #pos == 2 and pos[1] == 1 and pos[2] == 2 and folders == 1
	end
	-- rapid switching: Glock string, switched away and back every 0.15 s while presses continue
	local rapidSwitch = { maxGlockVoicesAway = 0 }
	for i = 1, 10 do
		player:SetAttribute("EquippedWeapon", if i % 2 == 1 then "Glock" else "Sniper")
		frames(0.15)
		if i % 2 == 1 then
			press()
		else
			rapidSwitch.maxGlockVoicesAway = math.max(rapidSwitch.maxGlockVoicesAway, (playing()))
		end
	end
	out.rapidSwitch = rapidSwitch
	ok = ok and rapidSwitch.maxGlockVoicesAway == 0
	quietWithin(3)
	out.soundsBefore, out.soundsAfter = soundsBefore, soundCount()
	ok = ok and out.soundsBefore == out.soundsAfter
	out.pass = ok
	return out
end

-- a probe WeaponAudio (its folder renamed and muted), released with WeaponAudio:Destroy() after use (its folder,
-- sounds and hearing listeners go; nothing is left for the other weapons' audio tests to see)
local function newProbe(): any
	local WeaponAudio = require(client:WaitForChild("WeaponAudio")) :: any
	local probe = WeaponAudio.new("Glock", INTERVAL)
	local f = probe.Folder :: Folder
	f.Name = "WeaponAudio_Glock_probe"
	for _, s in f:GetChildren() do
		(s :: Sound).Volume = 0
	end
	return probe
end

function Run.security(): any
	local out: any = {}
	local global0 = soundCount()
	local pr = newProbe()
	local f = pr.Folder :: Folder
	local function count(): (number, number)
		local n, e = 0, 0
		for _, d in f:GetDescendants() do
			if d:IsA("Sound") then
				n += 1
			elseif d:IsA("SoundEffect") then
				e += 1
			end
		end
		return n, e
	end
	local n0, e0 = count()
	-- 1000 shots in one frame (far beyond the 450 RPM cap the game enforces), alternating sets and stances
	pr.Log = {}
	local t0 = os.clock()
	local base = os.clock()
	for i = 1, 1000 do
		pr:Shot(base + i * 1e-4, i % 3 == 0, if i % 2 == 0 then 1 else 0)
	end
	local floodMs = (os.clock() - t0) * 1000
	local n1, e1 = count()
	local st = pr:State()
	local playingShots = 0
	for _, v in st.playing do
		if string.sub(v.name, 1, 4) == "Shot" then
			playingShots += 1
		end
	end
	local recycled, badRegion = 0, 0
	for _, e in pr.Log do
		if e.kind == "shot" then
			if e.recycled then
				recycled += 1
			end
			if e.regionStart < 0 or e.regionStart > 63 or e.regionStart % 1 ~= 0 then
				badRegion += 1
			end
		end
	end
	out.flood = { shots = 1000, ms = r3(floodMs), soundsBefore = n0, soundsAfter = n1, effectsBefore = e0, effectsAfter = e1,
		playingShotVoices = playingShots, recycledInFlood = recycled, historyShots = st.hearing.shots,
		badRegions = badRegion }
	-- odd inputs: aim nil / NaN / huge / negative, stressed as a non-boolean value
	pr.Log = {}
	local odd = { { false, nil }, { true, 0 / 0 }, { false, 1e9 }, { true, -5 }, { "yes" :: any, 0.49 }, { nil :: any, 0.5 } }
	for i, o in odd do
		pr:Shot(os.clock() + i, o[1], o[2])
	end
	local oddOut = {}
	for _, e in pr.Log do
		table.insert(oddOut, { name = e.name, aimed = e.aimed, regionStart = e.regionStart })
		if e.regionStart < 0 or e.regionStart > 63 then
			badRegion += 1
		end
	end
	out.oddInputs = oddOut
	pr.Log = nil
	-- cleanup: Destroy releases the probe's folder, sounds, equalisers and listeners; the object is inert afterwards
	pr:Destroy()
	frames(0.1)
	pr:Shot(os.clock(), false, 0)
	out.afterDestroy = { folderGone = f.Parent == nil, connections = #pr.Connections, hasAudio = pr:HasAudio() }
	out.globalSoundsBefore, out.globalSoundsAfter = global0, soundCount()
	out.pass = n1 == n0 and e1 == e0 and n0 == 21 and e0 == 18 and playingShots <= 2 * POOL and st.hearing.shots <= 256
		and badRegion == 0 and out.globalSoundsBefore == out.globalSoundsAfter and out.afterDestroy.folderGone
		and out.afterDestroy.connections == 0 and out.afterDestroy.hasAudio == false
	return out
end

function Run.perf(): any
	local function frameStats(dts: { number }): any
		table.sort(dts)
		local s = stats(dts)
		s.p95 = r3(dts[math.max(1, math.floor(#dts * 0.95))])
		return s
	end
	local function burstFrames(id: string): any
		equip(id)
		w("refill")
		frames(0.4)
		local dts = {}
		w("trigger", true)
		local t0 = os.clock()
		while os.clock() - t0 < 1.5 do
			table.insert(dts, RunService.RenderStepped:Wait() * 1000)
		end
		w("trigger", false)
		frames(0.3)
		return frameStats(dts)
	end
	local function glockFrames(mode: string): any
		equip("Glock")
		w("refill")
		frames(0.4)
		if mode == "reload" then
			w("setAmmo", { Mag = 0, Chambered = false, Reserve = { 15, 15 } })
			frames(0.4)
			w("reload")
		end
		local dts = {}
		local t0 = os.clock()
		local lastPress = -1
		local gap = if mode == "rapid" then 0.08 elseif mode == "string" then 0.165 else math.huge
		local maxVoices = 0
		while os.clock() - t0 < 2.0 do
			if os.clock() - lastPress >= gap then
				w("trigger", true)
				lastPress = os.clock()
			elseif mode == "rapid" or mode == "string" then
				w("trigger", false)
			end
			table.insert(dts, RunService.RenderStepped:Wait() * 1000)
			-- the Glock folder only (playing() walks the workspace: ~0.5 ms a frame, which would be test overhead)
			local n = 0
			for _, s in (ownFolder() :: Folder):GetChildren() do
				if (s :: Sound).IsPlaying and string.sub(s.Name, 1, 4) == "Shot" then
					n += 1
				end
			end
			maxVoices = math.max(maxVoices, n)
		end
		w("trigger", false)
		frames(if mode == "reload" then 1.6 else 1.2)
		local s = frameStats(dts)
		s.maxShotVoices = maxVoices
		return s
	end
	local memBefore = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds)
	local idle = glockFrames("idle")
	local rapid = glockFrames("rapid")
	local str = glockFrames("string")
	local reload = glockFrames("reload")
	local m4F = burstFrames("M4")
	local akF = burstFrames("AK")
	local mp7F = burstFrames("MP7")
	equip("Glock")
	local pr = newProbe()
	local t0 = os.clock()
	local base = os.clock()
	for i = 1, 200 do
		pr:Shot(base + i * 0.17, i % 2 == 0, if i % 4 < 2 then 1 else 0) -- through the 32 -> 1 wrap, both sets, both stances
	end
	local perShotUs = (os.clock() - t0) / 200 * 1e6
	t0 = os.clock()
	for _ = 1, 50 do
		pr:ReloadStart("TacticalRegular")
		pr:ReloadStop()
	end
	local perReloadUs = (os.clock() - t0) / 50 * 1e6
	t0 = os.clock()
	for _ = 1, 200 do
		pr:State()
	end
	local perStateUs = (os.clock() - t0) / 200 * 1e6
	pr:Destroy()
	local soundObjects = 0
	for _, c in SoundService:GetChildren() do
		if string.sub(c.Name, 1, 12) == "WeaponAudio_" then
			soundObjects += #c:GetChildren()
		end
	end
	frames(0.3)
	return { idleFrameMs = idle, glockRapidPressFrameMs = rapid, glockStringFrameMs = str, glockEmptyReloadFrameMs = reload,
		m4SustainedFireFrameMs = m4F, akSustainedFireFrameMs = akF, mp7SustainedFireFrameMs = mp7F,
		shotCallMicroseconds = r3(perShotUs), reloadStartStopMicroseconds = r3(perReloadUs),
		stateCallMicroseconds = r3(perStateUs), weaponAudioSoundObjects = soundObjects, soundMemoryMb = r3(memBefore),
		soundMemoryMbAfter = r3(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds)),
		pass = perShotUs < 500 and rapid.mean ~= nil }
end

return Run
