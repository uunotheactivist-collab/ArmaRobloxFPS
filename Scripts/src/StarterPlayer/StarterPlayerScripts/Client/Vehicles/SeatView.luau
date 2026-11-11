--!strict
-- The local player's seat, as the server set it (character attributes; truck slice). Read-only for the shared
-- first-person code:
--   eye()             the seat's eye point (Attachment "Eye" on the seat part) while seated, else nil. Client.Movement
--                     puts the camera there instead of "eye height above the floor" (seated eye heights MEASURED,
--                     ReferenceAnalysis/Truck §2).
--   weaponsStowed()   no rifle is shown and the weapon controller stands down:
--                       * driver seat: always; its CONTROLS list has no fire / aim lines and no rifle is ever seen there
--                         [CONFIRMED] (the server refuses shots and reloads from that seat too);
--                       * bench seat: while the rifle is down. Looking level no rifle or arm is visible there [CONFIRMED];
--                         FIRE / AIM / RELOAD are on its CONTROLS list [CONFIRMED text], so pressing one of them raises
--                         it and the existing weapon system runs as on foot until Config.SeatBody.RaiseHoldSeconds
--                         after the last such input [PLACEHOLDER: never used in the clip].
--   grenadesStowed()  in any seat (a grenade is on neither CONTROLS list [INFERRED]); the server refuses throws too.
--   seat()            { Vehicle = Model, Seat = BasePart, Id, Kind } or nil.
--   busy()            seated, or a vehicle prompt is on screen (VehicleClient sets PromptActive): other F interactions
--                     (the body menu) stand down, so one F press never does two things [implementation rule].
--   consumeSnap(cf)   the view turn of a cut, once (see below).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vehicles"))
local A = Config.Attributes

local SeatView = {}

local player = Players.LocalPlayer
local cache: any = nil -- { VehicleId, SeatId, Vehicle, Part }
local raisedAt = -math.huge

local function findVehicle(id: string): Model?
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("VehicleId") == id then
			return d
		end
	end
	return nil
end

function SeatView.seat(): any
	local c = player.Character
	local vid = c and c:GetAttribute(A.Vehicle)
	local sid = c and c:GetAttribute(A.Seat)
	if typeof(vid) ~= "string" or typeof(sid) ~= "string" then
		cache = nil
		return nil
	end
	if not (cache and cache.VehicleId == vid and cache.SeatId == sid and cache.Part.Parent) then
		local v = findVehicle(vid)
		local part: BasePart? = nil
		if v then
			for _, d in v:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("SeatId") == sid then
					part = d
					break
				end
			end
		end
		if not (v and part) then
			cache = nil
			return nil
		end
		cache = { VehicleId = vid, SeatId = sid, Vehicle = v, Part = part }
	end
	return { Vehicle = cache.Vehicle, Seat = cache.Part, Id = sid, Kind = c and c:GetAttribute(A.SeatKind) }
end

function SeatView.eye(): CFrame?
	local s = SeatView.seat()
	local eye = s and s.Seat:FindFirstChild("Eye") :: Attachment?
	return if eye then eye.WorldCFrame else nil
end

-- a bench seat's rifle comes up on FIRE / AIM / RELOAD (the inputs its CONTROLS panel lists)
local function raiseInput(): boolean
	return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or UserInputService:IsKeyDown(Enum.KeyCode.R)
end

function SeatView.weaponsStowed(): boolean
	local c = player.Character
	local kind = c and c:GetAttribute(A.SeatKind)
	if kind == "Driver" then
		return true
	elseif kind == "Back" then
		if raiseInput() and not SeatView.PromptActive then
			raisedAt = os.clock()
		end
		return os.clock() - raisedAt > Config.SeatBody.RaiseHoldSeconds
	end
	raisedAt = -math.huge
	return false
end

-- Studio test hook (VehicleClientDebug "raise"): as if FIRE / AIM / RELOAD had just been pressed in a bench seat
function SeatView.raise()
	raisedAt = os.clock()
end

function SeatView.grenadesStowed(): boolean
	local c = player.Character
	return c ~= nil and c:GetAttribute(A.Seat) ~= nil
end

local function flatLook(v: Vector3): Vector3?
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else nil
end

-- The view turn of a cut, once (Client.Movement applies it in the frame the seat changes), given the camera's rotation
-- this frame: into a seat, yaw = the seat's facing (its Eye attachment) and the pitch is KEPT [MEASURED at the driver
-- entry; INFERRED for the bench cuts]; out of a seat, yaw = the way the server placed the body (the exit point's facing)
-- and looking steeply down [MEASURED ≈ 49–56°].
local lastKey: string? = nil
local zeroOnRelease: BasePart? = nil -- after an exit: the body's velocity is cleared once the server lets it go
function SeatView.consumeSnap(current: CFrame): CFrame?
	if zeroOnRelease then
		if not zeroOnRelease.Parent then
			zeroOnRelease = nil
		elseif not zeroOnRelease.Anchored then
			zeroOnRelease.AssemblyLinearVelocity = Vector3.zero
			zeroOnRelease = nil
		end
	end
	local s = SeatView.seat()
	local key = if s then (s.Vehicle:GetAttribute("VehicleId") :: string) .. "/" .. s.Id else nil
	if key == lastKey then
		return nil
	end
	local prev = lastKey
	lastKey = key
	if s then
		local eye = s.Seat:FindFirstChild("Eye") :: Attachment?
		local yaw = eye and flatLook(eye.WorldCFrame.LookVector)
		if not yaw then
			return nil
		end
		local pitch = math.asin(math.clamp(current.LookVector.Y, -1, 1))
		return CFrame.lookAt(Vector3.zero, yaw) * CFrame.Angles(pitch, 0, 0)
	elseif prev then
		raisedAt = -math.huge
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			-- standing again where the server placed the body: nothing carried over from the seat (this client's copy);
			-- cleared now and again when the server releases the body (it holds it anchored for a few frames)
			root.AssemblyLinearVelocity = Vector3.zero
			zeroOnRelease = root
		end
		local yaw = root and flatLook(root.CFrame.LookVector)
		if yaw then
			return CFrame.lookAt(Vector3.zero, yaw) * CFrame.Angles(math.rad(Config.Exit.PitchDeg), 0, 0)
		end
	end
	return nil
end

SeatView.PromptActive = false

function SeatView.busy(): boolean
	local c = player.Character
	return SeatView.PromptActive or (c ~= nil and c:GetAttribute(A.Seat) ~= nil)
end

return SeatView
