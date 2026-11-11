--!strict
-- Pulse check result (server): read from the accepted BodyState at the moment the 3.00 s check ends. No medical model:
-- the phase maps to one of the two results the footage shows (Config.BodyInteraction.Pulse.ByPhase, tagged there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BodyInteraction"))
local BodyState = require(script.Parent.Parent:WaitForChild("BodyState"))

local PulseCheck = {}

-- (result key, text, phase). A body BodyState has no record for has never been hit: it is ALIVE (BodyState's own start
-- state).
function PulseCheck.result(model: Model): (string, string, string)
	local s = BodyState.get(model)
	local phase = if s then s.Phase else "ALIVE"
	local key = Config.Pulse.ByPhase[phase]
	assert(key, `no pulse result for phase {phase}`)
	return key, Config.Pulse.Results[key].Text, phase
end

return PulseCheck
