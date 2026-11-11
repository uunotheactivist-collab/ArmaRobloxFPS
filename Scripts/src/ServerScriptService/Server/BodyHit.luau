--!strict
-- Body hit location (server only). It turns a ballistic target hit (the part and the point the server's own trace
-- reached) into the reference game's location label and wound. Data: Shared.Config.BodyState.
--   Head → "head" → Brain wound.
--   R6 Torso: hit point's height in the torso's own frame. ≥ 0 → "chest"; the top ThroatBand studs of it are the
--     throat zone (Throat wound), the rest Lung. < 0 → "abdomen" (Gut). R15 UpperTorso / LowerTorso map the same way.
--   Arms / legs → "leftarm" / "rightarm" / "leftleg" / "rightleg" → Limb wound.
-- The client never supplies a part, a point or a label: they come from Server.Ballistics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BodyState"))

local BodyHit = {}

export type Hit = { Location: string, Zone: string?, Wound: string, LocalY: number? }

function BodyHit.locate(part: BasePart, position: Vector3): Hit?
	local name = part.Name
	local location = Config.PartLocation[name]
	local zone: string? = nil
	local localY: number? = nil
	if name == Config.SplitTorso or Config.ChestParts[name] then
		local y = part.CFrame:PointToObjectSpace(position).Y
		localY = y
		if name == Config.SplitTorso then
			location = if y >= 0 then "chest" else "abdomen"
		end
		if location == "chest" and y >= part.Size.Y / 2 - Config.ThroatBand then
			zone = "throat"
		end
	end
	if not location then
		return nil -- a part that is not anatomy (accessory, root, tool): no body hit
	end
	return { Location = location, Zone = zone, Wound = Config.Wound[zone or location], LocalY = localY }
end

return BodyHit
