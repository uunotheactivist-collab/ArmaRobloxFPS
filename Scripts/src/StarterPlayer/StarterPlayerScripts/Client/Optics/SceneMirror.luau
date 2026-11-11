--!strict
-- Copy of the visible world inside the optic's ViewportFrame (Client.Optics.ScopeView), because Roblox can't render
-- the real workspace through a second camera. Presentation only: the copies are anchored, non-colliding,
-- non-queryable and live outside the Workspace, so they can never take part in physics, raycasts or hits.
--
-- What is copied: every BasePart in the Workspace except the local player's own character, everything under the
-- camera (viewmodels, client effects), Terrain, invisible parts, parts smaller than Render.MirrorMinSize on every
-- axis, parts farther than Render.MirrorMaxDistance, and parts tagged with the attribute OpticMirrorIgnore.
-- Copies keep only their look (Decal / Texture / SpecialMesh children).
--
-- Cost control (ReferenceAnalysis/Optics, performance section):
--   * built once, the first time the optic is used, Render.BuildPerFrame parts per frame (no hitch); later parts
--     are queued by DescendantAdded and copied the same way. The builder runs only while its queue is non-empty
--     (no permanent Heartbeat).
--   * Sync() runs only on frames where the lens picture is live (called by Client.Optics.Optic). Moving parts
--     (unanchored, or in a character / body model) are followed every live frame; anchored parts are re-checked
--     round-robin, Render.StaticChecksPerFrame per live frame, and promoted to "moving" the first time they move.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SceneMirror = {}
SceneMirror.__index = SceneMirror

type Pair = { Src: BasePart, Copy: BasePart, Moving: boolean, Last: CFrame }
export type SceneMirror = typeof(setmetatable(
	{} :: {
		World: WorldModel,
		Cfg: any,
		Pairs: { [BasePart]: Pair },
		Moving: { Pair },
		Static: { Pair },
		Queue: { BasePart },
		QueueSet: { [BasePart]: boolean },
		Cursor: number,
		Started: boolean,
		Builder: RBXScriptConnection?,
		Conns: { RBXScriptConnection },
		Stats: { Copies: number, Moving: number, Static: number, Queued: number, Skipped: number, Built: boolean,
			LastSyncMs: number, LastMoved: number, BuildFrames: number },
	},
	SceneMirror
))

local KEEP = { Decal = true, Texture = true, SpecialMesh = true, SurfaceAppearance = true }

function SceneMirror.new(world: WorldModel, renderCfg: any): SceneMirror
	return setmetatable({
		World = world,
		Cfg = renderCfg,
		Pairs = {},
		Moving = {},
		Static = {},
		Queue = {},
		QueueSet = {},
		Cursor = 1,
		Started = false,
		Builder = nil,
		Conns = {},
		Stats = { Copies = 0, Moving = 0, Static = 0, Queued = 0, Skipped = 0, Built = false, LastSyncMs = 0,
			LastMoved = 0, BuildFrames = 0 },
	}, SceneMirror)
end

local function isMoving(p: BasePart): boolean
	if not p.Anchored then
		return true
	end
	local m = p:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") or m:GetAttribute("BodyModel") ~= nil then
			return true
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return false
end

function SceneMirror.Eligible(self: SceneMirror, p: Instance): boolean
	if not p:IsA("BasePart") or p:IsA("Terrain") or p.Parent == nil then
		return false
	end
	local camera = workspace.CurrentCamera
	if camera and p:IsDescendantOf(camera) then
		return false
	end
	if not p:IsDescendantOf(workspace) then
		return false
	end
	if p.Transparency >= 0.98 or p:GetAttribute("OpticMirrorIgnore") then
		return false
	end
	local s, min = p.Size, self.Cfg.MirrorMinSize
	if s.X < min and s.Y < min and s.Z < min then
		return false
	end
	local character = Players.LocalPlayer.Character
	if character and p:IsDescendantOf(character) then
		return false
	end
	local model = p:FindFirstAncestorOfClass("Model")
	if model and Players:GetPlayerFromCharacter(model) == Players.LocalPlayer then
		return false
	end
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	if (p.Position - focus).Magnitude > self.Cfg.MirrorMaxDistance then
		return false
	end
	return true
end

local function copyOf(src: BasePart): BasePart?
	local archivable = src.Archivable
	if not archivable then
		src.Archivable = true -- local only: the server's instance is not changed
	end
	local ok, c = pcall(src.Clone, src)
	if not archivable then
		src.Archivable = false
	end
	if not ok or not c then
		return nil
	end
	local copy = c :: BasePart
	for _, child in copy:GetChildren() do
		if not KEEP[child.ClassName] then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	return copy
end

function SceneMirror.Add(self: SceneMirror, src: BasePart)
	if self.Pairs[src] or not self:Eligible(src) then
		self.Stats.Skipped += 1
		return
	end
	local copy = copyOf(src)
	if not copy then
		self.Stats.Skipped += 1
		return
	end
	copy.Parent = self.World
	local pair: Pair = { Src = src, Copy = copy, Moving = isMoving(src), Last = src.CFrame }
	self.Pairs[src] = pair
	table.insert(if pair.Moving then self.Moving else self.Static, pair)
	self.Stats.Copies += 1
end

local function removeFrom(list: { Pair }, pair: Pair)
	local i = table.find(list, pair)
	if i then
		list[i] = list[#list]
		list[#list] = nil
	end
end

function SceneMirror.Remove(self: SceneMirror, src: Instance)
	local pair = self.Pairs[src :: any]
	if not pair then
		return
	end
	self.Pairs[src :: any] = nil
	removeFrom(if pair.Moving then self.Moving else self.Static, pair)
	pair.Copy:Destroy()
	self.Stats.Copies -= 1
end

function SceneMirror.Enqueue(self: SceneMirror, inst: Instance)
	if inst:IsA("BasePart") and not self.QueueSet[inst] and not self.Pairs[inst] then
		self.QueueSet[inst] = true
		table.insert(self.Queue, inst)
		self:RunBuilder()
	end
end

-- Copies queued parts, BuildPerFrame per frame; disconnects itself when the queue is empty.
function SceneMirror.RunBuilder(self: SceneMirror)
	if self.Builder then
		return
	end
	self.Builder = RunService.Heartbeat:Connect(function()
		local n = 0
		while #self.Queue > 0 and n < self.Cfg.BuildPerFrame do
			local p = table.remove(self.Queue) :: BasePart
			self.QueueSet[p] = nil
			if p.Parent then
				self:Add(p)
			end
			n += 1
		end
		self.Stats.BuildFrames += 1
		if #self.Queue == 0 then
			self.Stats.Built = true
			if self.Builder then
				self.Builder:Disconnect()
				self.Builder = nil
			end
		end
	end)
end

-- First use: queue the whole Workspace and follow additions / removals from now on.
function SceneMirror.Start(self: SceneMirror)
	if self.Started then
		return
	end
	self.Started = true
	for _, d in workspace:GetDescendants() do
		self:Enqueue(d)
	end
	table.insert(self.Conns, workspace.DescendantAdded:Connect(function(d)
		self:Enqueue(d)
	end))
	table.insert(self.Conns, workspace.DescendantRemoving:Connect(function(d)
		if self.Pairs[d :: any] then
			self:Remove(d)
		end
	end))
end

-- One live frame: follow moving parts, re-check a slice of the anchored ones.
function SceneMirror.Sync(self: SceneMirror)
	local t0 = os.clock()
	local moved = 0
	for _, pair in self.Moving do
		local cf = pair.Src.CFrame
		if cf ~= pair.Last then
			pair.Last = cf
			pair.Copy.CFrame = cf
			moved += 1
		end
	end
	local static = self.Static
	local n = #static
	if n > 0 then
		local promote = {}
		for _ = 1, math.min(self.Cfg.StaticChecksPerFrame, n) do
			if self.Cursor > n then
				self.Cursor = 1
			end
			local pair = static[self.Cursor]
			self.Cursor += 1
			local src, copy = pair.Src, pair.Copy
			if src.CFrame ~= pair.Last then
				pair.Last = src.CFrame
				copy.CFrame = src.CFrame
				table.insert(promote, pair)
				moved += 1
			end
			if src.Size ~= copy.Size then
				copy.Size = src.Size
			end
			if src.Color ~= copy.Color then
				copy.Color = src.Color
			end
			if src.Transparency ~= copy.Transparency then
				copy.Transparency = src.Transparency
			end
		end
		for _, pair in promote do
			removeFrom(self.Static, pair)
			pair.Moving = true
			table.insert(self.Moving, pair)
		end
	end
	local st = self.Stats
	st.Moving, st.Static, st.Queued = #self.Moving, #self.Static, #self.Queue
	st.LastMoved = moved
	st.LastSyncMs = (os.clock() - t0) * 1000
end

function SceneMirror.Destroy(self: SceneMirror)
	for _, c in self.Conns do
		c:Disconnect()
	end
	if self.Builder then
		self.Builder:Disconnect()
	end
	self.World:ClearAllChildren()
end

return SceneMirror
