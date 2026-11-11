--!strict
-- M4 reload animation test (isolated; not part of the combat foundation).
-- Plays the converted reload (ServerStorage.M4AnimTest.M4_Reload_Test) on the test rig in a loop so it
-- can be watched from the ViewingPad, holding the final pose between plays and logging measured timing.
--
-- Studio-only: the animation uses a temporary ID from KeyframeSequenceProvider. A live game needs the
-- KeyframeSequence published as an Animation asset.
-- Turn off: set Workspace.M4AnimTest's AutoPlay attribute to false.
-- Remove the test: delete Workspace.M4AnimTest and ServerStorage.M4AnimTest.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local folder = script.Parent
local rig = folder:WaitForChild("M4_ReloadTest_Rig")
local animator = rig:WaitForChild("AnimationController"):WaitForChild("Animator") :: Animator
local kfs = ServerStorage:WaitForChild("M4AnimTest"):WaitForChild("M4_Reload_Test") :: KeyframeSequence

if not RunService:IsStudio() then
	warn("[M4AnimTest] temporary animation IDs only work in Studio; publish M4_Reload_Test to use it live")
	return
end

local animation = Instance.new("Animation")
animation.Name = "M4_Reload_Test"
animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
animation.Parent = script

local track = animator:LoadAnimation(animation)
track.Priority = Enum.AnimationPriority.Action -- a reload overrides idle/movement
track.Looped = false -- one-shot; this script replays it for viewing
while track.Length == 0 do
	task.wait() -- LoadAnimation is asynchronous
end

local plays = 0
while folder:GetAttribute("AutoPlay") ~= false do
	plays += 1
	local started = os.clock()
	track:Play(0) -- no fade-in, so timing is exact
	track.Stopped:Wait()
	print(string.format("[M4AnimTest] play %d: length %.3f s, measured %.3f s", plays, track.Length, os.clock() - started))

	-- A stopped track snaps back to the bind pose (every bone at the root), so hold the last frame instead.
	track:Play(0)
	track.TimePosition = track.Length - 0.001
	track:AdjustSpeed(0)
	task.wait(folder:GetAttribute("PauseBetweenPlays") or 1.5)
	track:Stop(0)
end
