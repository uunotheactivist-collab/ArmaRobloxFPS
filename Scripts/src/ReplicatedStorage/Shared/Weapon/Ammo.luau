--!strict
-- Magazine, chamber, reserve and dropped-magazine bookkeeping, shared so the server (authoritative) and the client
-- (prediction) agree. Nothing else may change these numbers (the HUD only reads them).
--   Firing uses the chambered round; the bolt then chambers the next one from the magazine. A full load of a weapon
--   with ChamberRound = true is MagazineSize + 1 (the M4 reference bursts are 31 rounds).
--   Reserve = round counts of the spare magazines (magazine-based, not a loose round pool).
--   Dropped = round counts of the magazines discarded during reloads (they leave the reserve; the M4 HUD label
--     "[TAB] 5.56 MAG +N" shows how many - ReferenceAnalysis/M4/M4_HUD_Analysis.md).
-- A reload has two steps, timed by the clip (Config.Weapons.<Id>.Reloads):
--   swapMagazine at SwapAt: the old magazine is kept (back into the reserve) or dropped, the fullest spare goes in.
--     DropOld = "Never"   - Regular tactical reload: the partly used magazine is retained.
--               "Always"  - Stressed tactical reload: the partly used magazine is dumped [inferred from the HUD label].
--               "IfEmpty" - empty reloads: the empty magazine is dropped (a loaded one, only possible after a
--                           cancelled empty reload, goes back into the reserve).
--   chamber at ChamberAt (empty reloads only): the charging step chambers the first round of the new magazine.
-- LabelMarks: a HUD-label FLAG (0 or 1), NOT tied to any magazine and never a count. Specs with HudMarkAt (the AK's
--   Stressed tactical reload, where its footage shows the label appearing - AK_Analysis.md section 6) set it at that
--   moment. The label's meaning is UNKNOWN, so it has no inventory or ammunition effect. HUD label value =
--   #Dropped + LabelMarks (the AK never drops magazines, so its label is either hidden or "[TAB] 5.45 MAG").

local Ammo = {}

export type State = { Mag: number, Chambered: boolean, Reserve: { number }, Dropped: { number }, LabelMarks: number }

function Ammo.full(fire: any): State
	return {
		Mag = fire.MagazineSize,
		Chambered = fire.ChamberRound == true,
		Reserve = table.create(fire.SpareMagazines or 0, fire.MagazineSize),
		Dropped = {},
		LabelMarks = 0,
	}
end

function Ammo.copy(s: State): State
	return { Mag = s.Mag, Chambered = s.Chambered, Reserve = table.clone(s.Reserve), Dropped = table.clone(s.Dropped),
		LabelMarks = s.LabelMarks }
end

-- HUD label count (see LabelMarks above).
function Ammo.labelCount(s: State): number
	return #s.Dropped + (s.LabelMarks or 0)
end

function Ammo.mark(s: State)
	s.LabelMarks = 1 -- a flag: repeated marks never count up
end

function Ammo.canFire(s: State): boolean
	return s.Chambered
end

-- Call only when canFire(s) is true.
function Ammo.consume(s: State)
	if s.Mag > 0 then
		s.Mag -= 1
		s.Chambered = true
	else
		s.Chambered = false
	end
end

-- Manual action (Fire.Action = "Bolt", the Sniper slice): the fired case stays in the chamber until the bolt is worked;
-- nothing is chambered here. The cycle's chamber step (Ammo.chamber at Fire.ChamberAt) feeds the next round.
-- Call only when canFire(s) is true.
function Ammo.fireManual(s: State)
	s.Chambered = false
end

function Ammo.total(s: State): number
	return s.Mag + (if s.Chambered then 1 else 0)
end

function Ammo.reserveRounds(s: State): number
	local n = 0
	for _, r in s.Reserve do
		n += r
	end
	return n
end

local function fullestSpare(s: State): number?
	local best, bestRounds = nil, 0
	for i, r in s.Reserve do
		if r > bestRounds then
			best, bestRounds = i, r
		end
	end
	return best
end

-- "Empty" | "Tactical", or nil and the reason ("NoReserve" | "Full").
function Ammo.reloadKind(s: State, fire: any): (string?, string?)
	if not fullestSpare(s) then
		return nil, "NoReserve"
	end
	if not s.Chambered then
		return "Empty", nil
	end
	if s.Mag >= fire.MagazineSize then
		return nil, "Full"
	end
	return "Tactical", nil
end

-- The magazine change of a reload. Returns true if a magazine was swapped.
function Ammo.swapMagazine(s: State, dropOld: string): boolean
	local i = fullestSpare(s)
	if not i then
		return false
	end
	local new = table.remove(s.Reserve, i) :: number
	local old = s.Mag
	if dropOld == "Always" or (dropOld == "IfEmpty" and old == 0) then
		table.insert(s.Dropped, old)
	elseif old > 0 then
		table.insert(s.Reserve, old)
	end
	s.Mag = new
	return true
end

-- The charging step of an empty reload: chambers a round from the magazine. Returns true if it did.
function Ammo.chamber(s: State): boolean
	if s.Chambered or s.Mag <= 0 then
		return false
	end
	s.Mag -= 1
	s.Chambered = true
	return true
end

return Ammo
