--!strict
-- Impact effects (client): renders the server's authoritative impact events (Shared.Remotes.ImpactFx) — body hits
-- (Client.Blood.BodyHitEffect) and surface impacts (Client.Blood.WorldImpactEffect). Presentation only: it never sends
-- anything to the server and creates no persistent blood (the server does that).
-- Studio-only test hook: BindableFunction ImpactFxDebug (received counts, recent events, pool / bleed counts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Blood"))
local BodyHitEffect = require(script.Parent:WaitForChild("BodyHitEffect"))
local WorldImpactEffect = require(script.Parent:WaitForChild("WorldImpactEffect"))
local EmitterPool = require(script.Parent:WaitForChild("EmitterPool"))

local remote = Shared:WaitForChild("Remotes"):WaitForChild(Config.Remote) :: RemoteEvent

local received = { body = 0, world = 0, shots = 0 }
local recent: { any } = {}

remote.OnClientEvent:Connect(function(list: any)
	if type(list) ~= "table" then
		return
	end
	received.shots += 1
	for _, ev in list do
		if type(ev) == "table" and typeof(ev.p) == "Vector3" then
			if ev.t == "body" then
				received.body += 1
				BodyHitEffect.play(ev)
			elseif ev.t == "world" then
				received.world += 1
				WorldImpactEffect.play(ev)
			end
			if RunService:IsStudio() then
				table.insert(recent, {
					t = ev.t,
					p = ev.p,
					n = ev.n,
					part = if typeof(ev.part) == "Instance" then ev.part.Name else nil,
					x = ev.x,
					bleed = ev.bleed,
					c = ev.c,
					out = ev.out,
					loc = ev.loc,
				})
				while #recent > 64 do
					table.remove(recent, 1)
				end
			end
		end
	end
end)

if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "ImpactFxDebug"
	bf.OnInvoke = function(cmd: string): any
		if cmd == "clear" then
			table.clear(recent)
			received.body, received.world, received.shots = 0, 0, 0
			return true
		end
		return {
			Received = table.clone(received),
			Recent = recent,
			PoolSets = EmitterPool.size(),
			ActiveBleeds = BodyHitEffect.activeBleeds(),
			TerrainAttachments = #workspace.Terrain:GetChildren(),
		}
	end
	bf.Parent = script
end
