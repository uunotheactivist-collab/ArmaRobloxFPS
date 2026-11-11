--!strict
-- Owns the player life cycle: first spawn, death, respawn.
-- Players.CharacterAutoLoads is off, so a character only ever appears when
-- this script calls LoadCharacter. That keeps exactly one respawn per death.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))

Players.CharacterAutoLoads = false

local function spawnPlayer(player: Player)
	if player.Parent ~= Players then
		return -- left while we were waiting
	end
	-- LoadCharacter destroys the previous character (and its corpse) for us.
	player:LoadCharacter()
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.Died:Once(function()
		task.wait(CombatConfig.PlayerRespawnDelay)
		-- Only respawn if this is still their current character; anything else
		-- that respawned them in the meantime wins and we do nothing.
		if player.Character == character then
			spawnPlayer(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	else
		spawnPlayer(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
