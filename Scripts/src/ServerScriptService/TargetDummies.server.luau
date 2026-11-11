--!strict
-- Keeps every model tagged "TargetDummy" in play. When one dies, its corpse
-- is removed after a delay and a pristine copy appears in the same spot.
-- To add more targets, put any model with a Humanoid in Workspace and give it
-- the TargetDummy tag.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))

local TAG = "TargetDummy"

local FULL_COLOR = Color3.fromRGB(90, 220, 110)
local EMPTY_COLOR = Color3.fromRGB(230, 60, 50)

-- A billboard health bar over the head. Built in code so any model you tag
-- gets one automatically. It's created before the respawn snapshot is taken,
-- so replacements already carry it.
local function ensureHealthBar(dummy: Model, humanoid: Humanoid)
	local head = dummy:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local bar = head:FindFirstChild("HealthBar") :: BillboardGui?
	if not bar then
		local gui = Instance.new("BillboardGui")
		gui.Name = "HealthBar"
		gui.Size = UDim2.fromOffset(110, 30)
		gui.StudsOffset = Vector3.new(0, 2, 0)
		gui.MaxDistance = 200
		gui.AlwaysOnTop = true
		gui.ResetOnSpawn = false

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 14)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 12
		title.TextColor3 = Color3.new(1, 1, 1)
		title.TextStrokeTransparency = 0.4
		title.Text = humanoid.DisplayName ~= "" and humanoid.DisplayName or dummy.Name
		title.Parent = gui

		local back = Instance.new("Frame")
		back.Name = "Back"
		back.Position = UDim2.fromOffset(0, 16)
		back.Size = UDim2.new(1, 0, 0, 12)
		back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		back.BackgroundTransparency = 0.25
		back.BorderSizePixel = 0
		back.Parent = gui

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = FULL_COLOR
		fill.BorderSizePixel = 0
		fill.Parent = back

		local amount = Instance.new("TextLabel")
		amount.Name = "Amount"
		amount.Size = UDim2.fromScale(1, 1)
		amount.BackgroundTransparency = 1
		amount.Font = Enum.Font.GothamBold
		amount.TextSize = 10
		amount.TextColor3 = Color3.new(1, 1, 1)
		amount.TextStrokeTransparency = 0.3
		amount.ZIndex = 2
		amount.Parent = back

		gui.Parent = head
		bar = gui
	end

	-- Our bar replaces the engine's overhead name/health display.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local back = (bar :: BillboardGui):FindFirstChild("Back") :: Frame
	local fill = back:FindFirstChild("Fill") :: Frame
	local amount = back:FindFirstChild("Amount") :: TextLabel

	local function refresh()
		local fraction = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.BackgroundColor3 = EMPTY_COLOR:Lerp(FULL_COLOR, fraction)
		amount.Text = `{math.ceil(humanoid.Health)} / {math.ceil(humanoid.MaxHealth)}`
	end

	humanoid.HealthChanged:Connect(refresh)
	refresh()
end

local function watch(instance: Instance)
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
		return
	end
	local dummy = instance
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[TargetDummies] {dummy:GetFullName()} is tagged {TAG} but has no Humanoid`)
		return
	end

	ensureHealthBar(dummy, humanoid)

	-- Snapshot now, before any damage, so the replacement is at full health.
	local replacement = dummy:Clone()
	local parent = dummy.Parent

	humanoid.Died:Once(function()
		task.wait(CombatConfig.DummyRespawnDelay)
		dummy:Destroy()
		-- The clone keeps the tag, so parenting it fires the added signal and
		-- watch() takes a fresh snapshot of it.
		replacement.Parent = parent
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
for _, instance in CollectionService:GetTagged(TAG) do
	watch(instance)
end
