--!strict
-- Viewmodel fill (client presentation only; Client.FirstPerson.ViewmodelFill). v1 2026-11-10 after A3; v2 2026-11-10
-- (fill refinement, Fidelity Audit 2026-11-10\a3_lighting\fill_refine\RESULTS.md).
-- v3 (2026-11-11, under M2 lighting C9): ShadeAlbedo 0.040 -> 0.020 and ShadeTint (1.4, 1.0, 0.44) -> (2.2, 1.0, 0.44)
-- re-fitted by emulation (Fidelity Audit 2026-11-10\m2_lighting\FILL_REFIT.md); the formula and every other value are
-- unchanged. Measured under C9, masked black-part p50 in shade (B - R): fill off M4 12.9 (+11), AK 8.7 (+10), MP7 4.9
-- (+6); v2 over-lifted them to 19.0 / 18.2 / 12.9; v3 fitting views M4 14.1-14.6 (+4.7..+5.1), AK 13.7 (+1.4), MP7 8.9
-- (-0.9); held-out M4 12.9 (+4.4), AK 14.6 (+0.9), MP7 8.7 (-0.9), Sniper 9.6 (+3.9). The fill only adds light, so the
-- M4 (already 12.9 with it off) cannot be both inside 9-14 and neutral: its residual blue cast is the accepted trade-off.
-- The v2 description below still explains the mechanism; its numbers (4 %, gains) are v2's.
-- The camera-attached viewmodel is lit by the world. Under the A3 lighting (YouTube reference: deep shade,
-- OutdoorAmbient 78, exposure +0.75) the weapon's dark finishes (Color luma 27-37, about 1-2 % linear albedo) crush in
-- shade: masked black-part median 3-7 with a sky-blue cast (B - R 11; sky reflection, also indoors). The reference
-- rifle's black parts in shade read 9-14, neutral (B - R -3..0), with strong dark-on-light silhouettes (0.65-0.90).
-- v2 = DARK-FINISH SHADE LIFT, driven by the weapon's own light (not the eye): shade s = (share of SunSamples points on
-- the viewmodel out of the sun) ^ PartialExponent. In shade each dark part's albedo (part Color, in linear light) is
-- raised toward a common black (ShadeAlbedo, about real black plastic, 4 %): per part k = ShadeAlbedo / its linear
-- luminance, gain per channel max(1, k * ShadeTint[c]), applied as 1 + s * (gain - 1). That is a viewmodel-only ambient
-- boost for those parts (the engine's own shading, shadows and specular stay on them); darker finishes get more (M4
-- metal x2.5, MP7 / AK plastic x6.5-9), and the tint cancels the sky-blue cast. Nothing is added to the world; original
-- colours are restored exactly in sun, on detach and when disabled.
-- v1 (a Highlight fill blended over the whole viewmodel, strength 0.18, eye-gated) was REPLACED: masked, it put the
-- black parts at 23-26 (reference 9-14), cut their internal contrast (log-luma SD 0.51-0.59 -> 0.15-0.19) and detail by
-- ~3x, and took the weapon toward the background's level (weapon-vs-background contrast 0.60-0.95 -> 0.01-0.75).
-- Rejected in this refinement (measured): an enclosed-shade Highlight floor (0.05) fixed the darkest room (black 0 -> 8)
-- but overshot window-lit rooms (4 -> 16-17, contrast 0.79-0.88 -> 0.33-0.45), and no ray test separates the two;
-- lights were rejected in v1 (a PointLight lit the ground and walls x6, a SpotLight lit walls but not the weapon).
return table.freeze({
	Enabled = true,
	DarkLumaMax = 40, -- parts whose ORIGINAL Color luma (0-255) is below this get the lift (blacks 14-37; AK wood 43, tan, steel, arms excluded); Neon / Glass / ForceField and partly transparent parts are never touched [implementation]
	ShadeAlbedo = 0.020, -- [tuned v3 under C9, fitting views S1 / S3 (M4), S3 (AK), S1 (MP7)] target linear luminance of a dark finish at full shade: black p50 M4 12.9 -> 14.1-14.6, AK 8.7 -> 13.7, MP7 4.9 -> 8.9 (reference 9-14); v2 0.040 was fitted under A3
	ShadeTint = { 2.2, 1.0, 0.44 }, -- [tuned v3 under C9, same views] per-channel tint of that target (R, G, B): B - R M4 +11 -> +5, AK +10 -> +1, MP7 +6 -> -1 (reference -3..0); on the M4 metal this is the gain (2.72, 1.24, 1); v2 { 1.4, 1.0, 0.44 }
	PartialExponent = 3, -- [tuned, B3] shade share ^ this: a part-sunlit weapon gets little lift (2/3 shaded -> 0.30), so its sunlit side is not tinted or greyed
	SunSamples = 3, -- points on the viewmodel's bounding box (centre + both ends of its long axis) tested against the sun every frame [implementation]
	FadeInTau = 0.25, -- s: lift rising when the weapon goes into shade [PLACEHOLDER]
	FadeOutTau = 0.05, -- s: lift falling when the weapon enters sun (fast, so a sunlit weapon never carries the lift) [PLACEHOLDER]
	FireHold = 0.15, -- s: the lift is off (dropped at once) while a first-person muzzle-flash light is on and this long after it; measured: a lifted MP7 lit by its own flash read 148 vs 88 (accepted look) [PLACEHOLDER]
	SunRayLength = 1500, -- studs [implementation]
	MinStep = 0.004, -- level change below which colours are not rewritten [implementation]
})
