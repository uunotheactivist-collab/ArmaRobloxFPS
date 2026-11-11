--!strict
-- Body interaction (pulse check, drag): data only. Basis: ReferenceAnalysis/BodyInteraction/BodyInteraction_Analysis.md
-- (from Library/Videos/Bot_Interaction_System.md I1–I10, D1–D5, B1–B6, M1–M4; Ragdoll.md I1–I2, R11, BL5).
-- Tags: [confirmed] [measured] [inferred] [placeholder] UNKNOWN; nothing [placeholder] is reference data.
-- Every decision is the server's (Server.Interaction.BodyInteraction); a client only asks.

local Config = {
	Remote = "BodyInteract", -- Shared.Remotes.BodyInteract: client → server, requests only (action, target body)
	StateRemote = "BodyInteractState", -- Shared.Remotes.BodyInteractState: server → that client only
	BodyAttribute = "BodyModel", -- only BodyState bodies can be interacted with (players are not BodyState bodies yet)
	DraggedAttribute = "BodyDraggedBy", -- published by the server on a dragged body (the dragger's UserId)

	-- Input / menu. One key, F, activates the selected item [confirmed I1]. How the selection moves is UNKNOWN (I4):
	-- the mouse wheel here is a [placeholder]. "Search body" is shown in the footage but never used: what it does is
	-- UNKNOWN (I10), so it is not built and not listed.
	Key = Enum.KeyCode.F,
	Items = {
		{ Action = "PulseCheck", Label = "Check pulse", Busy = "Checking pulse..." }, -- [confirmed texts]
		{ Action = "Drag", Label = "Drag" }, -- [confirmed text]
	},
	LetGoLabel = "Let go", -- while dragging the menu is "[F] Let go" + the pulse line [confirmed S4]

	-- Ranges (studs). The menu appears with the player ≈1.5–2 m from the body [confirmed I7 by eye]; the exact range and
	-- look-at rule are UNKNOWN. 2 m = 7.1 studs.
	StartStuds = 7, -- a request is accepted within this of the body (closest point to the player's root) [placeholder]
	KeepStuds = 9, -- a pulse check is interrupted beyond this [placeholder]
	LineOfSight = true, -- the player's head must see the body (other bodies don't block) [implementation]
	FacingDot = 0.6, -- client only: the menu offers the nearest body roughly in front of the camera [placeholder]
	RequestInterval = 0.2, -- s between accepted requests per player (spam guard) [implementation]

	Pulse = {
		Seconds = 3.0, -- "Checking pulse..." to the result: 90 frames at 30 fps, both checks [measured I5]
		-- Result from the server's BodyState phase at the moment the check ends. The two texts and colours are confirmed
		-- (S3, S7). The mapping is [inferred]: the "strong, rapid" line was read on a downed, still-living bot (D1) and
		-- "No pulse" on the same bot once dead (D5). Other pulse wordings (weak, slow, …) are UNKNOWN and not invented.
		ByPhase = { ALIVE = "Pulse", INJURED = "Pulse", DYING = "Pulse", DEAD = "NoPulse" },
		Results = {
			Pulse = { Text = "Pulse: strong, rapid · ~100/min", Color = Color3.fromRGB(96, 214, 96) }, -- green [confirmed]
			NoPulse = { Text = "No pulse", Color = Color3.fromRGB(230, 64, 64) }, -- red [confirmed]
		},
	},

	Drag = {
		-- Which bodies: down (BodyState stance DOWN: DYING or DEAD in the current state model) and physical (the accepted
		-- ActiveRagdoll is running) [confirmed: downed and dead bodies are dragged; R11 dying bodies are interactable].
		-- The R6 debug-pose bots (BodyStateTest) are not physical: no drag.
		GripParts = { "UpperTorso", "Torso" }, -- held at the top of the torso: the head / torso end stays next to the
		-- player, legs away [confirmed pose D2]; the grip point itself [inferred]
		-- At the grab the body turns at once (one frame) so its head end points at the player and its legs away
		-- [confirmed D2: "snaps within one frame into a drag pose"]. Done as one rigid turn about the vertical through the
		-- pelvis (joints and pose kept); without it a body lying head-away is pushed into its own legs and jams.
		AlignOnGrab = true,
		AlignMinDeg = 30, -- smaller misalignments are left to the rope [placeholder]
		GripHeight = 1.0, -- grip held this far above the player's feet: shoulders lifted, hips on the floor [placeholder]
		HandForward = 1.0, -- the hand point: this far in front of the player's root [placeholder]
		RopeStuds = 2.0, -- the grip follows the hand like a rope of this length (slack when closer) [placeholder]
		BreakStuds = 8, -- the drag ends if the grip is farther than this from the hand (snagged, teleported) [placeholder]
		Responsiveness = 20, -- AlignPosition [placeholder]
		MaxSpeed = 16, -- studs/s, the grip's speed cap [placeholder]
		ForceOverWeight = 3, -- AlignPosition max force = body mass × project gravity × this [placeholder]
		-- While dragging the player walks slowly backward [confirmed M1]. Footstep-like audio every 0.62 s while dragging
		-- against ≈0.35 s when walking (truck) → ≈0.56 × the walk speed [inferred: the onsets are footsteps; speed itself
		-- UNKNOWN M4]. 0.56 × 16 ≈ 9.
		WalkSpeed = 9,
	},
}

local function freeze(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			freeze(v)
		end
	end
	return table.freeze(t)
end

return freeze(Config)
