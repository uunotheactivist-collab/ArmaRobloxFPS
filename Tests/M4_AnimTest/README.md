# M4 animation test (proof of concept, kept intact)

Reload 1 of the M4 reference (reference frames 34–140) recreated in Blender and played in Roblox.

**In Place1:**
- `Workspace.M4AnimTest` — `M4_ReloadTest_Rig` (anchored `Root`, bone parts `Weapon`/`Magazine`/`LeftArm` with
  Motor6Ds, 11 placeholder box parts, AnimationController + Animator), `ViewingPad` at (30, 0, 0) — standing on it
  puts your first-person camera at the rig's eye point — and `M4AnimTestRunner` (copy here). Folder attributes:
  `AutoPlay` (true), `PauseBetweenPlays` (1.5 s).
- `ServerStorage.M4AnimTest.M4_Reload_Test` — KeyframeSequence, 107 keyframes, 0–3.5333 s, Action, not looped.
  Its data: `Roblox/Animations/M4_Reload_Test/m4_animation_data.luau`.

**Previews:** `m4_reload_preview.mp4` (Blender, first-person camera), `m4_reload_side_by_side.mp4`
(reference | Blender replica).

**Results:** silhouette overlap vs reference 0.715 mean; Roblox length 3.5333 s = Blender; real-time plays
3.532–3.542 s (first play after playtest start runs long from load stall); poses ≤ 0.0002 studs / 0.04° from Blender.

**This is not the production M4.** Remove the test by deleting `Workspace.M4AnimTest` and
`ServerStorage.M4AnimTest`.
