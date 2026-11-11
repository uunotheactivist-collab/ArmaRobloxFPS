--!strict
-- Easing curves for presentation code (input clamped to 0..1).

local Easing = {}

function Easing.smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Easing.smootherstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (6 * t - 15) + 10)
end

function Easing.outCubic(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

function Easing.inOutSine(t: number): number
	t = math.clamp(t, 0, 1)
	return -(math.cos(math.pi * t) - 1) / 2
end

return Easing
