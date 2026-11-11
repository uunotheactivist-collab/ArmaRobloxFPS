--!strict
-- Procedural images for the optics framework (no asset uploads): drawn once into EditableImages.
--   reticle(spec)  : the optic's reticle (bars / dot / ring open at the bottom; optional thin centre Lines), sizes in
--                    lens-diameter fractions
--   hole(n)        : the eye-box shadow - transparent disc of radius n / 6 with a soft edge, black outside
--   mask(n, color) : opaque outside the round lens, transparent inside (anti-aliased edge)
--   blob(n)        : soft white highlight
-- Coverage is analytic (signed distance, 1 px anti-aliasing) and composited with straight alpha.

local AssetService = game:GetService("AssetService")

local LensImages = {}

type Canvas = { N: number, Buf: buffer }

local function canvas(n: number): Canvas
	return { N = n, Buf = buffer.create(n * n * 4) }
end

-- "over" compositing of colour (0..255) with coverage a (0..1) at pixel (x, y)
local function put(c: Canvas, x: number, y: number, r: number, g: number, b: number, a: number)
	if a <= 0 then
		return
	end
	local i = (y * c.N + x) * 4
	local buf = c.Buf
	local da = buffer.readu8(buf, i + 3) / 255
	local oa = a + da * (1 - a)
	local k = da * (1 - a)
	buffer.writeu8(buf, i, math.floor((r * a + buffer.readu8(buf, i) * k) / oa + 0.5))
	buffer.writeu8(buf, i + 1, math.floor((g * a + buffer.readu8(buf, i + 1) * k) / oa + 0.5))
	buffer.writeu8(buf, i + 2, math.floor((b * a + buffer.readu8(buf, i + 2) * k) / oa + 0.5))
	buffer.writeu8(buf, i + 3, math.floor(oa * 255 + 0.5))
end

local function toImage(c: Canvas): EditableImage
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(c.N, c.N) })
	assert(img, "LensImages: editable image budget exhausted")
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(c.N, c.N), c.Buf)
	return img
end

-- Axis-aligned rectangle [x0, x1] x [y0, y1] in pixel units (pixel centres at +0.5), anti-aliased.
local function rect(c: Canvas, x0: number, x1: number, y0: number, y1: number, col: { number }, alpha: number)
	for y = math.max(0, math.floor(y0) - 1), math.min(c.N - 1, math.ceil(y1) + 1) do
		local py = y + 0.5
		local cy = math.clamp(math.min(py - y0, y1 - py) + 0.5, 0, 1)
		if cy > 0 then
			for x = math.max(0, math.floor(x0) - 1), math.min(c.N - 1, math.ceil(x1) + 1) do
				local px = x + 0.5
				local cx = math.clamp(math.min(px - x0, x1 - px) + 0.5, 0, 1)
				put(c, x, y, col[1], col[2], col[3], alpha * cx * cy)
			end
		end
	end
end

-- Disc or ring (inner radius ri, outer ro) around (ox, oy), with an optional gap of gapDeg centred straight down.
local function ring(c: Canvas, ox: number, oy: number, ri: number, ro: number, col: { number }, alpha: number, gapDeg: number?)
	local halfGap = math.rad((gapDeg or 0) / 2)
	for y = math.max(0, math.floor(oy - ro) - 1), math.min(c.N - 1, math.ceil(oy + ro) + 1) do
		for x = math.max(0, math.floor(ox - ro) - 1), math.min(c.N - 1, math.ceil(ox + ro) + 1) do
			local dx, dy = x + 0.5 - ox, y + 0.5 - oy
			local d = math.sqrt(dx * dx + dy * dy)
			local cov = math.clamp(ro - d + 0.5, 0, 1)
			if ri > 0 then
				cov = math.min(cov, math.clamp(d - ri + 0.5, 0, 1))
			end
			if cov > 0 and halfGap > 0 then
				-- angle from straight down (image y grows downward)
				local ang = math.abs(math.atan2(dx, dy))
				local edge = (ang - halfGap) * d -- arc-length distance to the gap edge, px
				cov *= math.clamp(edge + 0.5, 0, 1)
			end
			put(c, x, y, col[1], col[2], col[3], alpha * cov)
		end
	end
end

function LensImages.reticle(spec: any): EditableImage
	local n = spec.ImagePixels
	local c = canvas(n)
	local mid = n / 2
	local lines = spec.Lines -- optional (Sniper slice: duplex centre lines); absent for the accepted ReferenceScope
	if lines then
		local len, half = lines.HalfLength * n, lines.Thickness * n / 2
		rect(c, mid - len, mid + len, mid - half, mid + half, lines.Color, lines.Alpha)
		rect(c, mid - half, mid + half, mid - len, mid - half, lines.Color, lines.Alpha)
		rect(c, mid - half, mid + half, mid + half, mid + len, lines.Color, lines.Alpha)
	end
	local bars = spec.Bars
	if bars then
		local inner, outer, half = bars.Inner * n, bars.Outer * n, bars.Thickness * n / 2
		for _, dir in bars.Directions do
			if dir == "Left" then
				rect(c, mid - outer, mid - inner, mid - half, mid + half, bars.Color, bars.Alpha)
			elseif dir == "Right" then
				rect(c, mid + inner, mid + outer, mid - half, mid + half, bars.Color, bars.Alpha)
			elseif dir == "Down" then
				rect(c, mid - half, mid + half, mid + inner, mid + outer, bars.Color, bars.Alpha)
			elseif dir == "Up" then
				rect(c, mid - half, mid + half, mid - outer, mid - inner, bars.Color, bars.Alpha)
			end
		end
	end
	local ringSpec = spec.Ring
	if ringSpec then
		local r, h = ringSpec.Radius * n, ringSpec.Thickness * n / 2
		ring(c, mid, mid, r - h, r + h, ringSpec.Color, ringSpec.Alpha, ringSpec.GapDeg)
	end
	local dot = spec.Dot
	if dot then
		ring(c, mid, mid, 0, dot.Diameter * n / 2, dot.Color, dot.Alpha, nil)
	end
	return toImage(c)
end

-- Clear disc of radius n/6 with a soft edge (softness = edge width / radius), black outside.
LensImages.HOLE_FRACTION = 1 / 6
function LensImages.hole(n: number, softness: number): EditableImage
	local c = canvas(n)
	local r = n * LensImages.HOLE_FRACTION
	local w = math.max(1, r * softness)
	local mid = n / 2
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local dx, dy = x + 0.5 - mid, y + 0.5 - mid
			local d = math.sqrt(dx * dx + dy * dy)
			local t = math.clamp((d - (r - w / 2)) / w, 0, 1)
			local a = t * t * (3 - 2 * t)
			if a > 0 then
				put(c, x, y, 0, 0, 0, a)
			end
		end
	end
	return toImage(c)
end

function LensImages.mask(n: number, color: { number }): EditableImage
	local c = canvas(n)
	local r = n / 2 - 0.5
	local mid = n / 2
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local dx, dy = x + 0.5 - mid, y + 0.5 - mid
			local d = math.sqrt(dx * dx + dy * dy)
			local a = math.clamp(d - r + 0.5, 0, 1)
			if a > 0 then
				put(c, x, y, color[1], color[2], color[3], a)
			end
		end
	end
	return toImage(c)
end

function LensImages.blob(n: number): EditableImage
	local c = canvas(n)
	local mid = n / 2
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local dx, dy = (x + 0.5 - mid) / mid, (y + 0.5 - mid) / mid
			local d = math.sqrt(dx * dx + dy * dy)
			if d < 1 then
				local t = 1 - d
				put(c, x, y, 255, 255, 255, t * t * (3 - 2 * t))
			end
		end
	end
	return toImage(c)
end

-- Shows an EditableImage on an ImageLabel.
function LensImages.show(label: ImageLabel, img: EditableImage)
	(label :: any).ImageContent = Content.fromObject(img)
end

return LensImages
