--!strict
-- Weapon audio (client, presentation only; M4 audio fidelity slice + correction pass; Glock audio fidelity correction).
-- A weapon has sound only when Shared.Config.Audio.<Id> exists. For every other weapon the object is inert: it creates
-- no instance and plays nothing - there are no generic fallback sounds.
--   Shots (default, M4 / AK / MP7): one voice per weapon - starting a shot's sound stops the previous one (measured in
--   the M4 reference). The k-th shot of a burst plays variant k of the set for the player's state (Regular / Stressed):
--   a region of one sprite file (PlaybackRegion). A shot continues the burst when it comes exactly one fire interval
--   after the previous one (the weapon's automatic cycle); any later shot starts a new burst at position 1. Two Sound
--   instances per set are used in turn, so a restart never reuses the instance being stopped.
--   Shot.Overlap (optional, the Glock): every shot is its own voice and keeps playing under the next ones (measured in
--   the Glock reference). Each set gets a pool of ceil(VariantLength / interval) + 1 voices used in turn: a voice is
--   reused only after that many shots, i.e. after more than VariantLength at the fastest legal cadence, so its region has
--   always ended (a voice still playing when reused would be stopped and logged as "recycled" - the tests require none).
--   The pool is fixed: no instance is ever created per shot.
--   Shot.AimedOffset (optional, the Glock): a shot fired aimed (aim >= 0.5) plays its variant AimedOffset variants
--   further on (the sprite's centred copy; hip shots are panned in the reference, aimed ones centred).
--   Hearing (optional, the Glock): an inferred presentation model of the reference's hearing effect - every shot voice
--   carries an EqualizerSoundEffect whose gains follow the firing history (shots count from Delay after their start,
--   decay with Release, saturate with Saturation) and the stress onset (the player's Stressed attribute turning on;
--   decays with StressOnset.Decay). Every playing shot voice is updated at every frame from the history of every shot
--   but its own (the recordings were cut from the reference, so their tails already carry the dulling their own shot
--   caused), i.e. the whole shot mix is dulled, as the reference shows (a sound 1.6 s after a string is still dulled).
--   Reload sounds are not equalised: they are the reference's own recordings, which already carry the effect of their
--   own moment.
--   Reloads: the clip's own sound starts with the clip (Client.ReloadController) and stops on cancel.
--   Stop(): everything stops at once (weapon switch, death, respawn) - nothing of a put-down weapon keeps playing, and
--   the next shot starts a new burst / cycle. The hearing state is the player's and is kept (it decays with time).
-- Audio decides nothing and grants nothing: it only follows the client's own predicted presentation events (the
-- server stays authoritative for shots, hits and ammunition), and the sounds are local, non-positional 2D sounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local AudioConfig = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Audio")

-- the hearing history's hard bound: at the fastest legal cadence (450 RPM) a shot is forgotten after
-- Delay + 12 * Release (18.1 s for the Glock), i.e. at most 136 remembered shots
local MAX_HISTORY = 256

local WeaponAudio = {}
WeaponAudio.__index = WeaponAudio

export type WeaponAudio = typeof(setmetatable(
	{} :: {
		Id: string,
		Def: any?,
		Interval: number,
		Folder: Folder?,
		Shots: { [string]: { Sound } },
		NextVoice: number,
		Voice: Sound?,
		LastShotAt: number?,
		Position: number,
		Reloads: { [string]: Sound },
		ReloadVoice: Sound?,
		Log: { any }?,
		Overlap: boolean,
		Voices: number,
		Eq: { [Sound]: EqualizerSoundEffect },
		VoiceShotAt: { [Sound]: number },
		EqAt: { [Sound]: number },
		HearingShots: { number },
		StressOnsetAt: number?,
		Gains: { number },
		Connections: { RBXScriptConnection },
	},
	WeaponAudio
))

-- an uploaded asset when the config lists one for the file, otherwise the local Studio content copy
local function soundId(def: any, file: string): string
	local asset = def.AssetIds and def.AssetIds[file]
	if asset then
		return "rbxassetid://" .. tostring(asset)
	end
	return "rbxasset://sounds/" .. def.Folder .. "/" .. file
end

local function makeSound(folder: Folder, def: any, file: string, name: string, regions: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = soundId(def, file)
	s.Volume = def.Volume
	s.Looped = false
	s.PlaybackRegionsEnabled = regions
	s.Parent = folder
	return s
end

-- one shot's contribution to the firing history at time t (it counts from Delay after its start)
local function contribution(hdef: any, t: number, u: number): number
	local age = t - u - hdef.Delay
	return if age >= 0 then math.exp(-age / hdef.Release) else 0
end

-- the firing history at time t: every remembered shot's contribution
local function history(self: WeaponAudio, t: number): number
	local hdef = (self.Def :: any).Hearing
	local h = 0
	for _, u in self.HearingShots do
		h += contribution(hdef, t, u)
	end
	return h
end

-- the hearing model's equaliser gains (dB: Low, Mid, High) at time t for a voice whose own shot started at `own`:
-- its own shot does not count (the recordings were cut from the reference, so their tails already carry the dulling
-- their own shot caused). h: history(self, t), when the caller has it already.
local function hearingGains(self: WeaponAudio, t: number, own: number?, h: number?): { number }
	local hdef = (self.Def :: any).Hearing
	local hv = h or history(self, t)
	if own then
		hv = math.max(hv - contribution(hdef, t, own), 0)
	end
	local x = 1 - math.exp(-hv / hdef.Saturation)
	local m = 0
	local onset = hdef.StressOnset
	if onset and self.StressOnsetAt and t >= self.StressOnsetAt then
		m = math.exp(-(t - self.StressOnsetAt) / onset.Decay)
	end
	local g = hdef.Gains
	local og = if onset then onset.Gains else { Low = 0, Mid = 0, High = 0 }
	local function clamp(v: number): number
		return math.clamp(v, -80, 10)
	end
	return { clamp(g.Low * x + og.Low * m), clamp(g.Mid * x + og.Mid * m), clamp(g.High * x + og.High * m) }
end

local function applyGains(eq: EqualizerSoundEffect, g: { number })
	eq.LowGain = g[1]
	eq.MidGain = g[2]
	eq.HighGain = g[3]
end

-- interval: the weapon's automatic fire interval (60 / RPM), which tells a continued burst from a new one (and, with
-- Shot.Overlap, the shortest time between two shots: it sizes the voice pool)
function WeaponAudio.new(id: string, interval: number?): WeaponAudio
	local module = AudioConfig:FindFirstChild(id)
	local def = if module and module:IsA("ModuleScript") then require(module) :: any else nil
	local self = setmetatable({
		Id = id,
		Def = def,
		Interval = interval or 0,
		Folder = nil :: Folder?,
		Shots = {},
		NextVoice = 1,
		Voice = nil :: Sound?,
		LastShotAt = nil :: number?,
		Position = 0,
		Reloads = {},
		ReloadVoice = nil :: Sound?,
		Log = nil :: { any }?,
		Overlap = false,
		Voices = 2,
		Eq = {},
		VoiceShotAt = {},
		EqAt = {},
		HearingShots = {},
		StressOnsetAt = nil :: number?,
		Gains = { 0, 0, 0 },
		Connections = {},
	}, WeaponAudio)
	if def then
		local folder = Instance.new("Folder")
		folder.Name = "WeaponAudio_" .. id
		self.Folder = folder
		if def.Shot.Overlap then
			self.Overlap = true
			local longest = 0
			for _, set in def.Shot.Sets do
				longest = math.max(longest, set.VariantLength)
			end
			self.Voices = math.ceil(longest / math.max(self.Interval, 1e-3)) + 1
			for setName, set in def.Shot.Sets do
				local pool = {}
				for i = 1, self.Voices do
					local s = makeSound(folder, def, set.File, "Shot" .. setName .. i, true)
					if def.Hearing then
						local eq = Instance.new("EqualizerSoundEffect")
						eq.Name = "Hearing"
						applyGains(eq, { 0, 0, 0 })
						eq.Parent = s
						self.Eq[s] = eq
					end
					table.insert(pool, s)
				end
				self.Shots[setName] = pool
			end
		else
			for setName, set in def.Shot.Sets do
				self.Shots[setName] = { makeSound(folder, def, set.File, "Shot" .. setName .. "A", true),
					makeSound(folder, def, set.File, "Shot" .. setName .. "B", true) }
			end
		end
		for clip, file in def.Reloads do
			self.Reloads[clip] = makeSound(folder, def, file, "Reload" .. clip, false)
		end
		folder.Parent = SoundService -- client-created: local to this player, never replicated
		if def.Hearing then
			local player = Players.LocalPlayer
			if def.Hearing.StressOnset and player then
				local was = player:GetAttribute("Stressed") == true
				table.insert(self.Connections, player:GetAttributeChangedSignal("Stressed"):Connect(function()
					local now = player:GetAttribute("Stressed") == true
					if now and not was then
						self.StressOnsetAt = os.clock()
					end
					was = now
				end))
			end
			-- every frame while a shot voice plays: each playing voice follows the hearing state (every shot but its own)
			table.insert(self.Connections, RunService.Heartbeat:Connect(function()
				local t = os.clock()
				-- forget shots whose contribution is negligible (exp(-12) < 1e-5; they keep the list short)
				local hdef = def.Hearing
				while #self.HearingShots > 0 and t - self.HearingShots[1] > hdef.Delay + 12 * hdef.Release do
					table.remove(self.HearingShots, 1)
				end
				local h = nil
				for s, eq in self.Eq do
					if s.IsPlaying then
						h = h or history(self, t)
						applyGains(eq, hearingGains(self, t, self.VoiceShotAt[s], h))
						self.EqAt[s] = t
					end
				end
				if h then
					self.Gains = hearingGains(self, t, nil, h)
				end
			end))
		end
	end
	return self
end

function WeaponAudio.HasAudio(self: WeaponAudio): boolean
	return self.Def ~= nil
end

local function log(self: WeaponAudio, kind: string, name: string, t: number?, position: number?, extra: any?)
	if self.Log then
		local e: any = { kind = kind, name = name, t = t, position = position, at = os.clock() }
		if extra then
			for k, v in extra do
				e[k] = v
			end
		end
		table.insert(self.Log, e)
	end
end

-- t: the shot's scheduled time (FireController); stressed: the player's Stressed state; aim: the aim blend (0 hip ..
-- 1 aimed; used only with Shot.AimedOffset). The sound starts now (this frame).
function WeaponAudio.Shot(self: WeaponAudio, t: number, stressed: boolean?, aim: number?)
	local def = self.Def
	if not def then
		return
	end
	local shot = def.Shot
	local last = self.LastShotAt
	local continued = last ~= nil and math.abs(t - last - self.Interval) <= shot.CycleTolerance
	self.LastShotAt = t
	local setName = if stressed then "Stressed" else "Regular"
	local set = shot.Sets[setName]
	local position = if continued then self.Position + 1 else 1
	if position > set.Count then -- past the recorded burst: continue through its plateau, in order
		position = shot.PlateauFrom + (position - shot.PlateauFrom) % (set.Count - shot.PlateauFrom + 1)
	end
	self.Position = position
	if not self.Overlap then
		local s = self.Shots[setName][self.NextVoice]
		self.NextVoice = 3 - self.NextVoice
		if self.Voice and self.Voice ~= s then
			self.Voice:Stop()
		end
		s:Stop()
		local start = (position - 1) * set.VariantLength
		s.PlaybackRegion = NumberRange.new(start, start + set.VariantLength)
		s.TimePosition = start
		s:Play()
		self.Voice = s
		log(self, "shot", s.Name, t, position)
		return
	end
	-- overlapping voices (Shot.Overlap): the next voice of the pool; no other voice is touched
	local aimed = shot.AimedOffset ~= nil and (aim or 0) >= 0.5
	local variant = position + (if aimed then shot.AimedOffset else 0)
	local pool = self.Shots[setName]
	local s = pool[self.NextVoice]
	self.NextVoice = self.NextVoice % self.Voices + 1
	local recycled = s.IsPlaying
	if recycled then
		s:Stop()
	end
	if def.Hearing then
		-- the history counts sound starts (os.clock, the Heartbeat's clock); it is bounded (MAX_HISTORY) even if shots
		-- were ever requested faster than the weapon can fire - only the oldest, least audible ones are dropped
		local now = os.clock()
		table.insert(self.HearingShots, now)
		while #self.HearingShots > MAX_HISTORY do
			table.remove(self.HearingShots, 1)
		end
		self.VoiceShotAt[s] = now
		local g = hearingGains(self, now, now)
		self.Gains = g
		applyGains(self.Eq[s], g)
		self.EqAt[s] = now
	end
	local start = (variant - 1) * set.VariantLength
	s.PlaybackRegion = NumberRange.new(start, start + set.VariantLength)
	s.TimePosition = start
	s:Play()
	self.Voice = s
	log(self, "shot", s.Name, t, position, { aimed = aimed, regionStart = start, recycled = recycled,
		gains = if def.Hearing then { self.Gains[1], self.Gains[2], self.Gains[3] } else nil })
end

function WeaponAudio.ReloadStart(self: WeaponAudio, clip: string)
	if not self.Def then
		return
	end
	self:ReloadStop()
	local s = self.Reloads[clip]
	if s then
		s.TimePosition = 0
		s:Play()
		self.ReloadVoice = s
		log(self, "reload", s.Name, nil, nil)
	end
end

function WeaponAudio.ReloadStop(self: WeaponAudio)
	local s = self.ReloadVoice
	if s then
		if s.IsPlaying then
			log(self, "reloadStop", s.Name, nil, nil)
		end
		s:Stop()
		self.ReloadVoice = nil
	end
end

function WeaponAudio.Stop(self: WeaponAudio)
	if not self.Def then
		return
	end
	self:ReloadStop()
	if self.Overlap then
		for _, pool in self.Shots do
			for _, s in pool do
				if s.IsPlaying then
					log(self, "shotStop", s.Name, nil, nil)
					s:Stop()
				end
			end
		end
		self.Voice = nil
	elseif self.Voice then
		if self.Voice.IsPlaying then
			log(self, "shotStop", self.Voice.Name, nil, nil)
		end
		self.Voice:Stop()
		self.Voice = nil
	end
	self.LastShotAt = nil -- the next shot after a put-down starts a new burst
	self.Position = 0
end

-- releases everything: stops the sounds, disconnects the hearing listeners, destroys the folder; the object is inert
-- afterwards. The game keeps one WeaponAudio per weapon for the session and never calls it (Studio test probes do).
function WeaponAudio.Destroy(self: WeaponAudio)
	self:Stop()
	for _, c in self.Connections do
		c:Disconnect()
	end
	table.clear(self.Connections)
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
	table.clear(self.Eq)
	table.clear(self.VoiceShotAt)
	table.clear(self.EqAt)
	table.clear(self.Shots)
	table.clear(self.Reloads)
	self.Def = nil
end

-- Studio test hook support: which sounds are playing, and the play / stop log when recording
function WeaponAudio.State(self: WeaponAudio): any
	local playing = {}
	if self.Folder then
		for _, c in self.Folder:GetChildren() do
			if c:IsA("Sound") and c.IsPlaying then
				local eq = self.Eq[c]
				table.insert(playing, { name = c.Name, timePosition = c.TimePosition, length = c.TimeLength, loaded = c.IsLoaded,
					region = if c.PlaybackRegionsEnabled then { c.PlaybackRegion.Min, c.PlaybackRegion.Max } else nil,
					-- Hearing: the voice's equaliser as last applied (at eqAt), and its own shot's start (os.clock)
					eq = if eq then { eq.LowGain, eq.MidGain, eq.HighGain } else nil, eqAt = self.EqAt[c],
					shotAt = self.VoiceShotAt[c] })
			end
		end
	end
	local hearing = nil
	if self.Def and self.Def.Hearing then
		local t = os.clock()
		hearing = { gains = self.Gains, now = hearingGains(self, t), history = history(self, t), clock = t,
			shots = #self.HearingShots, stressOnsetAt = self.StressOnsetAt }
	end
	return { id = self.Id, hasAudio = self.Def ~= nil, playing = playing, position = self.Position,
		sounds = if self.Folder then #self.Folder:GetChildren() else 0, voices = self.Voices, overlap = self.Overlap,
		hearing = hearing }
end

return WeaponAudio
