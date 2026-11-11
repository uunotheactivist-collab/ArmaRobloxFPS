--!strict
-- Samples viewmodel animation clips exported from Blender (Shared.Assets.Weapons.<Id>ReloadAnimations, generated
-- by Blender/Scripts/23_m4_reload_export.py from the FBX). Each joint track holds key frames (30 fps) with the joint
-- transform relative to its rest pose; keys are linear (the exporter reduced them under that assumption), rotations
-- are slerped. No Animator or uploaded animation asset is involved, so this works in any place, uploaded or not.

local ClipPlayer = {}

type Track = { Times: { number }, CFrames: { CFrame } }
export type Clip = { Name: string, Length: number, Frames: number, Events: { [string]: number }, Joints: { [string]: Track } }

local function rv(x: number, y: number, z: number): CFrame
	local a = math.sqrt(x * x + y * y + z * z)
	if a < 1e-9 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(Vector3.new(x / a, y / a, z / a), a)
end

-- Converts the generated data into ready-to-sample clips.
function ClipPlayer.compile(data: any): { [string]: Clip }
	local fps = data.FPS
	local clips = {}
	for name, c in data.Clips do
		local joints = {}
		for jointName, j in c.Joints do
			local times, cfs = {}, {}
			for i, k in j.K do
				local p = 3 * (i - 1)
				times[i] = k / fps
				cfs[i] = CFrame.new(j.P[p + 1], j.P[p + 2], j.P[p + 3]) * rv(j.R[p + 1], j.R[p + 2], j.R[p + 3])
			end
			joints[jointName] = { Times = times, CFrames = cfs }
		end
		clips[name] = { Name = name, Length = c.Length, Frames = c.Frames, Events = c.Events, Joints = joints }
	end
	return clips
end

local function sampleTrack(track: Track, t: number): CFrame
	local times = track.Times
	local n = #times
	if t <= times[1] then
		return track.CFrames[1]
	elseif t >= times[n] then
		return track.CFrames[n]
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local a = (t - times[lo]) / (times[hi] - times[lo])
	return track.CFrames[lo]:Lerp(track.CFrames[hi], a)
end

-- Joint transforms (relative to rest) at time t; `out` is reused to avoid allocations.
function ClipPlayer.sample(clip: Clip, t: number, out: { [string]: CFrame }?): { [string]: CFrame }
	local result = out or {}
	for jointName, track in clip.Joints do
		result[jointName] = sampleTrack(track, t)
	end
	return result
end

return ClipPlayer
