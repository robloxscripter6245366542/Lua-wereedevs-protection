-- The egg conveyor: random eggs roll down the belt, players buy them with cash.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Conveyor = {}
local S
local folder: Folder
local active = 0
local rng = Random.new()

local function eggWeight(egg): number
	local weight = egg.SpawnWeight
	if S.Events.IsActive("LuckyHour") then
		weight *= 2 ^ (Config.Rarities[egg.Rarity].Order - 1)
	end
	return weight
end

local function oddsText(egg): string
	local total = 0
	for _, pet in egg.Pets do
		total += pet.Weight
	end
	local parts = {}
	for _, pet in egg.Pets do
		table.insert(parts, ("%s %d%%"):format(pet.Name, math.floor(pet.Weight / total * 100 + 0.5)))
	end
	return table.concat(parts, " • ")
end

local function makeBillboard(egg, parent: Instance)
	local rarity = Config.Rarities[egg.Rarity]
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(230, 120)
	gui.StudsOffset = Vector3.new(0, 6 + egg.Index * 0.25, 0)
	gui.MaxDistance = 90
	gui.Parent = parent
	local rows = {
		{ egg.Name, Color3.new(1, 1, 1), 0.26 },
		{ egg.Rarity, rarity.Color, 0.2 },
		{ Util.FormatCash(egg.Price), Color3.fromRGB(255, 230, 90), 0.24 },
		{ "+" .. Util.FormatCash(egg.Income) .. "/s • hatches in " .. Util.FormatTime(egg.HatchTime), Color3.fromRGB(120, 255, 120), 0.15 },
		{ oddsText(egg), Color3.fromRGB(220, 220, 220), 0.15 },
	}
	local y = 0
	for _, row in rows do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextStrokeTransparency = 0.2
		l.Text = row[1]
		l.TextColor3 = row[2]
		l.Size = UDim2.fromScale(1, row[3])
		l.Position = UDim2.fromScale(0, y)
		l.Parent = gui
		y += row[3]
	end
end

local function spawnEgg()
	if active >= Config.Conveyor.MaxEggs then
		return
	end
	local egg = Util.WeightedPick(Config.Eggs, eggWeight, rng)
	local model = S.Visuals.MakeEgg(egg, nil)
	local root = model.PrimaryPart :: BasePart
	local startCF = CFrame.new(Config.Conveyor.StartX, 1.4, 0) * CFrame.Angles(0, math.pi / 2, 0)
	model:PivotTo(startCF)
	makeBillboard(egg, root)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy " .. Util.FormatCash(egg.Price)
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	model.Parent = folder
	active += 1

	local distance = Config.Conveyor.EndX - Config.Conveyor.StartX
	local tween = TweenService:Create(root, TweenInfo.new(distance / Config.Conveyor.Speed, Enum.EasingStyle.Linear), {
		CFrame = startCF + Vector3.new(distance, 0, 0),
	})
	local sold = false
	local function finish()
		if model.Parent then
			active -= 1
			model:Destroy()
		end
	end
	tween.Completed:Connect(finish)
	tween:Play()

	prompt.Triggered:Connect(function(player)
		if sold then
			return
		end
		local data = S.Data.Get(player)
		if not data or not S.Plots.Get(player) then
			return
		end
		if not S.Pedestals.FreeSlot(player) then
			S.Notify(player, "❌ Your base is full! Sell something or Rebirth for more slots.", Color3.fromRGB(255, 90, 90))
			return
		end
		if not S.Data.SpendCash(player, egg.Price) then
			S.Notify(player, "❌ Not enough cash! You need " .. Util.FormatCash(egg.Price), Color3.fromRGB(255, 90, 90))
			return
		end
		sold = true
		S.Pedestals.PlaceItem(player, S.Pedestals.NewEggItem(player, egg))
		S.Visuals.Burst(root.Position, Config.Rarities[egg.Rarity].Color, 30)
		S.Notify(player, "🥚 Bought " .. egg.Name .. "! It's incubating in your base.", Config.Rarities[egg.Rarity].Color)
		tween:Cancel()
		finish()
	end)

	if Config.Rarities[egg.Rarity].Order >= 5 then
		S.Announce(("🚨 A %s %s is on the conveyor! GO GO GO!"):format(egg.Rarity:upper(), egg.Name), Config.Rarities[egg.Rarity].Color)
	end
end

function Conveyor.Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "ConveyorEggs"
	folder.Parent = workspace
end

function Conveyor.Start()
	task.spawn(function()
		while true do
			local ok, err = pcall(spawnEgg)
			if not ok then
				warn("[Conveyor]", err)
			end
			task.wait(Config.Conveyor.SpawnInterval)
		end
	end)
end

return Conveyor
