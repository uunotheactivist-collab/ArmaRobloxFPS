--!strict
-- MP7 audio fidelity test, client side (Studio playtest only; delete the MP7AudioTest folder to remove it). Derived from
-- AKAudioTest / M4AudioTest (same checks, the MP7's own sounds, cadence, variant length, magazine and reload lengths).
-- Checks Client.WeaponAudio in the running game through WeaponController's Studio-only debug hook ("audio" command:
-- play / stop log + the state of every weapon's sounds). Gameplay numbers stay with the accepted suites.
--   Run.assets()          the MP7's 8 sounds (2 voices per shot set, Regular / Stressed sprites, 4 reloads) exist and
--                         load with the built lengths, shot voices with PlaybackRegion; no other weapon has any sound
--   Run.fire(kind)        "single" | "taps" | "sustained" | "ads" (the MP7's aim posture) | "stressed" | "repress": one sound per predicted shot,
--                         the burst position of every shot (1, 2, 3 ... in continuous fire; 1 for a shot after a break;
--                         a re-press within the fire cycle continues the burst), the set for the state, playback inside
--                         the variant's region, at most one shot voice at a time, play delay / spacing vs the shot
--                         schedule, the tail after the last shot plays out and then nothing is left; the server still
--                         counts every shot
--   Run.reloads()         the four reloads: the clip's own sound starts with the clip, runs in step with it
--                         (TimePosition vs clip time) and is over when the reload is
--   Run.interrupt()       weapon switch during a reload / during a shot tail, firing during a reload (refused, no
--                         sound), a reload cancelled by a correction (refill): the sound stops at once
--   Run.death(phase)      "before": fire + start a reload, watch for the death; then on the Server set the humanoid's
--                         Health to 0; "after" (once respawned): nothing played on at death, next shot starts a burst
--   Run.switching()       MP7 -> M4 -> AK -> Glock -> Sniper -> MP7 while firing: nothing of the previous weapon plays
--   Run.perf()            cost of WeaponAudio:Shot, sound memory, frame time in sustained fire (MP7 vs AK, both with audio)
--   Run.timeline(kind)    raw play log of a burst (for the offline render, compare_v2.py)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local hook = client:WaitForChild("WeaponController"):WaitForChild("ProductionWeaponDebug") :: BindableFunction

local Run = {}
local EXPECTED = { ShotRegularA = 51.25, ShotRegularB = 51.25, ShotStressedA = 51.25, ShotStressedB = 51.25,
	ReloadTacticalRegular = 3.2667, ReloadTacticalStressed = 2.1, ReloadEmptyRegular = 4.9333, ReloadEmptyStressed = 3.4 }
local VARIANT = 1.25 -- s per burst position in the shot sprites (Config.Audio.MP7)
local INTERVAL = 60 / 950

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
	return SoundService:FindFirstChild("WeaponAudio_MP7") :: Folder?
end

-- weapon-audio folders (SoundService.WeaponAudio_<Id>): sounds playing in each, by weapon id
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

-- playing sounds: of the MP7's own folder (shot voices / reload), and anywhere else outside the character (which has the
-- default Roblox character sounds - running, jumping - that are not weapon audio) and outside the other weapons' own
-- audio folders (weapons with their own Config.Audio module, the AK since its audio slice: checked separately)
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

function Run.assets(): any
	equip("MP7")
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
			out.sounds[name] = if s then { loaded = s.IsLoaded, length = r3(s.TimeLength), id = s.SoundId, volume = s.Volume,
				looped = s.Looped, regions = s.PlaybackRegionsEnabled } else false
			ok = ok and s ~= nil and s.IsLoaded and math.abs(s.TimeLength - len) < 0.003 and not s.Looped
				and s.PlaybackRegionsEnabled == (string.sub(name, 1, 4) == "Shot")
		end
		out.count = #f:GetChildren()
		ok = ok and out.count == 8
	end
	for _, c in SoundService:GetChildren() do
		if string.sub(c.Name, 1, 12) == "WeaponAudio_" and c ~= f then
			table.insert(out.otherFolders, c.Name)
		end
	end
	local st = w("audio")
	out.perWeapon = {}
	for id, a in st.audio do
		out.perWeapon[id] = { hasAudio = a.hasAudio, sounds = a.sounds }
		if id ~= "MP7" and not a.hasAudio then
			ok = ok and a.sounds == 0 -- a weapon without a Config.Audio module has no sound at all
		end
	end
	-- the only other weapon-audio folders are those of weapons that have their own audio config (the AK)
	local foldersOk = true
	for _, name in out.otherFolders do
		local id = string.sub(name, 13)
		foldersOk = foldersOk and st.audio[id] ~= nil and st.audio[id].hasAudio == true
	end
	out.soundMemoryMb = r3(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds))
	out.pass = ok and foldersOk
	return out
end

-- fire a pattern; returns the shot times, the audio log, per-frame voice counts, region checks and the tail end
local function firePattern(kind: string): any
	equip("MP7")
	w("refill")
	frames(0.5)
	local s0 = serverState(2)
	w("audio", true)
	w("record", true)
	local maxShot, maxOther, maxTotal = 0, 0, 0
	local regionSamples, regionBad = 0, 0
	local function sample()
		local a, b, c = playing()
		maxShot = math.max(maxShot, a)
		maxOther = math.max(maxOther, c)
		maxTotal = math.max(maxTotal, a + b)
		-- a playing shot voice must stay inside its variant's region (one burst position of the sprite)
		local f = ownFolder()
		if f then
			for _, s in f:GetChildren() do
				if s:IsA("Sound") and s.IsPlaying and string.sub(s.Name, 1, 4) == "Shot" then
					regionSamples += 1
					local r = s.PlaybackRegion
					if s.TimePosition < r.Min - 0.001 or s.TimePosition > r.Max + 0.03
						or math.abs((r.Max - r.Min) - VARIANT) > 1e-6 then
						regionBad += 1
					end
				end
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
	if kind == "ads" then
		w("aim", true)
		hold(0.6)
	elseif kind == "stressed" then
		w("stressed", true)
		hold(0.6)
	end
	if kind == "single" then
		w("trigger", true)
		RunService.RenderStepped:Wait()
		w("trigger", false)
	elseif kind == "taps" then
		for _ = 1, 4 do
			w("trigger", true)
			RunService.RenderStepped:Wait()
			w("trigger", false)
			hold(0.25)
		end
	elseif kind == "repress" then
		-- 0.4 s held; released for one frame (inside the 77.9 ms cycle) and pressed again: the burst continues;
		-- then released for 0.3 s (longer than a cycle) and pressed again: a new burst
		w("trigger", true)
		hold(0.4)
		w("trigger", false)
		RunService.RenderStepped:Wait()
		w("trigger", true)
		hold(0.3)
		w("trigger", false)
		hold(0.3)
		w("trigger", true)
		hold(0.3)
		w("trigger", false)
	else
		w("trigger", true)
		hold(3.0) -- a full magazine (40 + 1) at 950 RPM lasts 2.53 s
		w("trigger", false)
	end
	local released = os.clock()
	-- the last shot's tail: until no MP7 shot voice plays any more
	local tailEnd: number? = nil
	while os.clock() - released < 3.2 do
		RunService.RenderStepped:Wait()
		sample()
		local a = playing()
		if a == 0 and not tailEnd then
			tailEnd = os.clock()
		elseif a > 0 then
			tailEnd = nil
		end
	end
	w("aim", false)
	if kind == "stressed" then
		w("stressed", false)
	end
	local rec = w("record", false)
	local logs = w("audio", false)
	local s1 = serverState(2)
	local shotTimes = rec.shots or {}
	local events = {}
	for _, e in logs.logs.MP7 or {} do
		if e.kind == "shot" then
			table.insert(events, e)
		end
	end
	local delays, gapsPlay, gapsShot = {}, {}, {}
	for i, e in events do
		table.insert(delays, e.at - e.t)
		if i > 1 then
			table.insert(gapsPlay, e.at - events[i - 1].at)
			table.insert(gapsShot, e.t - events[i - 1].t)
		end
	end
	local names, positions = {}, {}
	for _, e in events do
		table.insert(names, e.name)
		table.insert(positions, e.position)
	end
	local lastShot = shotTimes[#shotTimes]
	local acc = s0.server and s1.server and (s1.server.Accepted or 0) - (s0.server.Accepted or 0)
	return { kind = kind, shots = #shotTimes, shotSounds = #events, names = names, positions = positions, events = events,
		shotTimes = shotTimes, regionSamples = regionSamples, regionBad = regionBad,
		playDelay = stats(delays), playSpacing = stats(gapsPlay), shotSpacing = stats(gapsShot),
		maxShotVoices = maxShot, maxWeaponVoices = maxTotal, maxOtherSounds = maxOther,
		tailAfterLastShot = if tailEnd and lastShot then r3(tailEnd - lastShot) else nil,
		serverAccepted = acc, otherLog = logs.logs }
end

function Run.fire(kind: string?): any
	local k = kind or "sustained"
	local r = firePattern(k)
	local set = if k == "stressed" then "ShotStressed" else "ShotRegular"
	local firstOk = #r.positions > 0 and r.positions[1] == 1
	-- expected burst positions from the shot schedule: a shot one cycle after the previous one continues the burst,
	-- anything else starts at 1 (taps: all 1; continuous fire 1, 2, 3 ...; "repress": continuous through the one-frame
	-- release, 1 again after the 0.3 s break)
	local expected = {}
	for i = 1, #r.shotTimes do
		local gap = if i > 1 then r.shotTimes[i] - r.shotTimes[i - 1] else math.huge
		if math.abs(gap - INTERVAL) > 0.001 then
			expected[i] = 1
		else
			expected[i] = math.min(expected[i - 1] + 1, 41)
		end
	end
	-- the two voices of the set alternate (which one starts depends on earlier shots in the session; same file)
	local restOk = #r.positions == #expected
	local restarts = 0
	for i = 1, #r.positions do
		restOk = restOk and r.positions[i] == expected[i] and string.sub(r.names[i], 1, #set) == set
			and (i == 1 or r.names[i] ~= r.names[i - 1])
		if i > 1 and expected[i] == 1 then
			restarts += 1
		end
	end
	-- the other weapons' logs must be empty (no sound for them)
	local othersSilent = true
	for id, l in r.otherLog do
		if id ~= "MP7" and l and #l > 0 then
			othersSilent = false
		end
	end
	local out = { kind = k, shots = r.shots, shotSounds = r.shotSounds, firstIsFirst = firstOk, sequenceOk = restOk,
		positions = r.positions, restarts = restarts, regionSamples = r.regionSamples, regionBad = r.regionBad,
		playDelay = r.playDelay, playSpacing = r.playSpacing, shotSpacing = r.shotSpacing, maxShotVoices = r.maxShotVoices,
		maxWeaponVoices = r.maxWeaponVoices, maxOtherSounds = r.maxOtherSounds, tailAfterLastShot = r.tailAfterLastShot,
		serverAccepted = r.serverAccepted, othersSilent = othersSilent }
	out.pass = r.shots > 0 and r.shotSounds == r.shots and firstOk and restOk and r.maxShotVoices <= 1
		and r.maxOtherSounds == 0 and (r.tailAfterLastShot or 99) < 1.5 and r.serverAccepted == r.shots and othersSilent
		and (k ~= "single" or r.shots == 1) and (k ~= "taps" or (r.shots == 4 and restarts == 3))
		and (k == "single" or k == "taps" or k == "repress" or (r.shots >= 40 and restarts == 0))
		and (k ~= "repress" or (restarts == 1 and r.shots >= 10)) and r.regionBad == 0 and r.regionSamples > 0
	return out
end

-- raw timeline for the offline render (shot times, play times, sound names, burst positions)
function Run.timeline(kind: string?): any
	local r = firePattern(kind or "sustained")
	local ev = {}
	for _, e in r.events do
		table.insert(ev, { name = e.name, position = e.position, t = e.t - r.events[1].t, at = e.at - r.events[1].t })
	end
	return { kind = r.kind, events = ev }
end

local function reloadOnce(stressed: boolean, empty: boolean): any
	equip("MP7")
	w("stressed", stressed)
	w("refill")
	frames(0.4)
	if empty then
		w("setAmmo", { Mag = 0, Chambered = false, Reserve = { 30, 30 } })
	else
		w("setAmmo", { Mag = 10, Chambered = true, Reserve = { 30, 30 } })
	end
	frames(0.6)
	w("audio", true)
	local t0 = os.clock()
	local res = w("reload")
	local clip: string? = nil
	local offsets = {}
	local reloadEnd: number? = nil
	local soundEnd: number? = nil
	local soundName: string? = nil
	local maxOther = 0
	while os.clock() - t0 < 5.5 do
		RunService.RenderStepped:Wait()
		local now = os.clock()
		local st = w("sync")
		if st.reloading then
			clip = st.reloading
		elseif clip and not reloadEnd then
			reloadEnd = now
		end
		local f = ownFolder() :: Folder
		local anyPlaying = false
		for _, s in f:GetChildren() do
			if s:IsA("Sound") and s.IsPlaying and string.sub(s.Name, 1, 6) == "Reload" then
				anyPlaying = true
				soundName = s.Name
				if s.TimePosition > 0.05 then -- after the engine has started it
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
	local logs = w("audio", false)
	local starts = 0
	for _, e in logs.logs.MP7 or {} do
		if e.kind == "reload" then
			starts += 1
		end
	end
	return { request = res.result, clip = clip, sound = soundName, starts = starts,
		reloadSeconds = if reloadEnd then r3(reloadEnd - t0) else nil,
		soundSeconds = if soundEnd then r3(soundEnd - t0) else nil,
		syncOffset = stats(offsets), maxOtherSounds = maxOther,
		pass = clip ~= nil and soundName == "Reload" .. clip and starts == 1 and reloadEnd ~= nil and soundEnd ~= nil
			and math.abs((soundEnd :: number) - (reloadEnd :: number)) < 0.1 and maxOther == 0 }
end

function Run.reloads(): any
	local out: any = {
		tacticalRegular = reloadOnce(false, false),
		emptyRegular = reloadOnce(false, true),
		tacticalStressed = reloadOnce(true, false),
		emptyStressed = reloadOnce(true, true),
	}
	w("stressed", false)
	local ok = true
	for _, r in { out.tacticalRegular, out.emptyRegular, out.tacticalStressed, out.emptyStressed } do
		ok = ok and r.pass
	end
	out.pass = ok
	return out
end

-- wait until nothing of the MP7 plays (or timeout); returns the seconds it took
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
	equip("MP7")
	w("refill")
	frames(0.4)
	w("setAmmo", { Mag = 10, Chambered = true, Reserve = { 30, 30 } })
	frames(0.6)
	w("reload")
	frames(1.0)
	local _, rb = playing()
	player:SetAttribute("EquippedWeapon", "Glock") -- switch away from the MP7 (a weapon without audio)
	out.switchDuringReload = { reloadPlayingBefore = rb, stoppedAfter = quietWithin(0.5) }
	frames(0.3)
	-- b) switch during a shot tail
	equip("MP7")
	w("refill")
	frames(0.4)
	w("trigger", true)
	frames(0.5)
	w("trigger", false)
	frames(0.2)
	local sa = playing()
	player:SetAttribute("EquippedWeapon", "Glock") -- switch away from the MP7 (a weapon without audio)
	out.switchDuringTail = { shotPlayingBefore = sa, stoppedAfter = quietWithin(0.5) }
	frames(0.3)
	-- c) firing during a reload: refused by the controller, so no shot sound; the reload sound carries on
	equip("MP7")
	w("refill")
	frames(0.4)
	w("setAmmo", { Mag = 10, Chambered = true, Reserve = { 30, 30 } })
	frames(0.6)
	w("audio", true)
	w("reload")
	frames(0.5)
	w("trigger", true)
	frames(0.8)
	w("trigger", false)
	local _, rb2 = playing()
	frames(2.6)
	local logs = w("audio", false)
	local shotsDuring = 0
	for _, e in logs.logs.MP7 or {} do
		if e.kind == "shot" then
			shotsDuring += 1
		end
	end
	out.fireDuringReload = { shotSounds = shotsDuring, reloadStillPlaying = rb2 }
	-- d) a reload cancelled by a correction (the refill path cancels the reload like ReloadCancelled does)
	w("setAmmo", { Mag = 10, Chambered = true, Reserve = { 30, 30 } })
	frames(0.6)
	w("reload")
	frames(0.8)
	local _, rb3 = playing()
	w("refill")
	out.cancelledReload = { reloadPlayingBefore = rb3, stoppedAfter = quietWithin(0.3) }
	frames(0.5)
	out.pass = out.switchDuringReload.reloadPlayingBefore == 1 and out.switchDuringReload.stoppedAfter ~= nil
		and out.switchDuringReload.stoppedAfter < 0.1 and out.switchDuringTail.shotPlayingBefore == 1
		and out.switchDuringTail.stoppedAfter ~= nil and out.switchDuringTail.stoppedAfter < 0.1
		and out.fireDuringReload.shotSounds == 0 and out.fireDuringReload.reloadStillPlaying == 1
		and out.cancelledReload.reloadPlayingBefore == 1 and out.cancelledReload.stoppedAfter ~= nil
		and out.cancelledReload.stoppedAfter < 0.1
	return out
end

local deathWatch: any = nil

function Run.death(phase: string): any
	if phase == "before" then
		equip("MP7")
		w("refill")
		frames(0.4)
		w("trigger", true)
		frames(0.4)
		w("trigger", false)
		frames(0.1)
		w("setAmmo", { Mag = 10, Chambered = true, Reserve = { 30, 30 } })
		frames(0.3)
		w("reload")
		frames(0.2)
		local a, b = playing()
		deathWatch = { playingBefore = { shot = a, reload = b } }
		local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.Died:Once(function()
			local t0 = os.clock()
			deathWatch.diedAt = t0
			deathWatch.stoppedAfter = quietWithin(0.5)
		end)
		return deathWatch
	end
	-- after: respawned
	frames(0.8)
	equip("MP7")
	w("refill")
	frames(0.4)
	w("audio", true)
	w("trigger", true)
	RunService.RenderStepped:Wait()
	w("trigger", false)
	frames(0.3)
	local logs = w("audio", false)
	local first = nil
	for _, e in logs.logs.MP7 or {} do
		if e.kind == "shot" then
			first = e.position
			break
		end
	end
	local folders = 0
	for _, c in SoundService:GetChildren() do
		if c.Name == "WeaponAudio_MP7" then
			folders += 1
		end
	end
	local out = { watch = deathWatch, firstShotPositionAfterRespawn = first, mp7Folders = folders }
	out.pass = deathWatch ~= nil and deathWatch.diedAt ~= nil and deathWatch.stoppedAfter ~= nil
		and deathWatch.stoppedAfter < 0.1 and (deathWatch.playingBefore.shot + deathWatch.playingBefore.reload) >= 1
		and first == 1 and folders == 1
	quietWithin(3)
	return out
end

function Run.switching(): any
	local out: any = { steps = {} }
	local ok = true
	for _, id in { "MP7", "M4", "AK", "Glock", "Sniper", "MP7" } do
		equip(id)
		w("refill")
		frames(0.3)
		local a0, b0 = playing()
		w("trigger", true)
		frames(0.4)
		local a1, _, o1 = playing()
		-- other weapons' own audio folders: only the equipped weapon's may play
		local third = 0
		for wid, n in weaponFolderPlaying() do
			if wid ~= "MP7" and wid ~= id then
				third += n
			end
		end
		w("trigger", false)
		frames(0.2)
		table.insert(out.steps, { weapon = id, ownPlayingOnEquip = a0 + b0, ownShotVoicesWhileFiring = a1, otherSounds = o1,
			otherWeaponFolderSounds = third })
		if id == "MP7" then
			ok = ok and a1 == 1 and o1 == 0 and third == 0
		else
			ok = ok and a0 + b0 == 0 and a1 == 0 and o1 == 0 and third == 0
		end
	end
	quietWithin(3)
	out.pass = ok
	return out
end

function Run.perf(): any
	-- frame time in sustained fire: MP7 and AK (both with audio; every automatic weapon without audio is gone)
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
		table.sort(dts)
		local s = stats(dts)
		s.p95 = r3(dts[math.max(1, math.floor(#dts * 0.95))])
		return s
	end
	local memBefore = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds)
	local mp7F = burstFrames("MP7")
	local akF = burstFrames("AK")
	-- cost of the play call itself: a separate test instance of WeaponAudio (its own folder, removed afterwards)
	local WeaponAudio = require(client:WaitForChild("WeaponAudio")) :: any
	local wa = WeaponAudio.new("MP7", INTERVAL)
	local f = wa.Folder :: Folder
	f.Name = "WeaponAudio_MP7_perfprobe"
	for _, s in f:GetChildren() do
		(s :: Sound).Volume = 0
	end
	local t0 = os.clock()
	local base = os.clock()
	for i = 1, 200 do
		wa:Shot(base + i * INTERVAL, i % 2 == 0) -- continuous: through the plateau wrap, both sets
	end
	local perShotUs = (os.clock() - t0) / 200 * 1e6
	t0 = os.clock()
	for _ = 1, 50 do
		wa:ReloadStart("TacticalRegular")
		wa:ReloadStop()
	end
	local perReloadUs = (os.clock() - t0) / 50 * 1e6
	wa:Stop()
	f:Destroy()
	frames(0.3)
	return { mp7SustainedFireFrameMs = mp7F, akSustainedFireFrameMs = akF, shotCallMicroseconds = r3(perShotUs),
		reloadStartStopMicroseconds = r3(perReloadUs), soundMemoryMb = r3(memBefore),
		soundMemoryMbAfter = r3(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds)),
		pass = perShotUs < 500 and mp7F.mean ~= nil }
end

return Run
