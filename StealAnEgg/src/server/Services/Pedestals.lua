-- Slots in each base: placing items, incubation -> hatching, income, collecting, selling.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Pedestals = {}
local S

local function now()
	return workspace:GetServerTimeNow()
end

local function petConfig(egg, petName)
	for _, pet in egg.Pets do
		if pet.Name == petName then
			return pet
		end
	end
	return nil
end

-- Base $/sec of an item before player multipliers.
function Pedestals.ItemIncome(item): number
	local egg = Config.EggsById[item.EggId]
	if not egg then
		return 0
	end
	if not item.Pet then
		return egg.Income
	end
	local pet = petConfig(egg, item.Pet)
	local mutation = S.Visuals.FindMutation(item.Mutation)
	return egg.Income * (pet and pet.Mult or 1) * mutation.Mult
end

function Pedestals.ItemValue(item): number
	local egg = Config.EggsById[item.EggId]
	if not egg then
		return 0
	end
	if item.Pet then
		return math.max(egg.Price, Pedestals.ItemIncome(item) * 60)
	end
	return math.floor(egg.Price * 0.5)
end

function Pedestals.ItemName(item): string
	local egg = Config.EggsById[item.EggId]
	if not egg then
		return "???"
	end
	if item.Pet then
		local prefix = if item.Mutation and item.Mutation ~= "Normal" then item.Mutation .. " " else ""
		return prefix .. item.Pet
	end
	return egg.Name
end

function Pedestals.PlayerMultiplier(player: Player): number
	local data = S.Data.Get(player)
	local mult = 1 + (data and data.Rebirths or 0) * Config.RebirthIncomeBonus
	if S.Monetization.HasPass(player, "VIP") then
		mult *= 1.5
	end
	if S.Monetization.HasPass(player, "DoubleCash") then
		mult *= 2
	end
	if S.Events.IsActive("CashFrenzy") then
		mult *= 2
	end
	return mult
end

function Pedestals.SlotCount(player: Player): number
	local data = S.Data.Get(player)
	local count = Config.Plot.BaseSlots + (data and data.Rebirths or 0) * Config.Plot.SlotsPerRebirth
	if S.Monetization.HasPass(player, "ExtraSlots") then
		count += Config.ExtraSlotsAmount
	end
	return math.min(count, Config.Plot.MaxSlots)
end

function Pedestals.FreeSlot(player: Player): number?
	local data = S.Data.Get(player)
	if not data then
		return nil
	end
	for i = 1, Pedestals.SlotCount(player) do
		if data.Slots[tostring(i)] == nil then
			return i
		end
	end
	return nil
end

function Pedestals.NewEggItem(player: Player, egg)
	local hatchTime = egg.HatchTime
	if S.Monetization.HasPass(player, "FastHatch") then
		hatchTime /= 2
	end
	return { EggId = egg.Id, HatchAt = now() + hatchTime, Stored = 0 }
end

-- Puts an item into the first free slot. Returns slot index or nil.
function Pedestals.PlaceItem(player: Player, item): number?
	local data = S.Data.Get(player)
	local index = Pedestals.FreeSlot(player)
	if not data or not index then
		return nil
	end
	item.Stored = 0
	data.Slots[tostring(index)] = item
	Pedestals.RefreshSlot(player, index)
	return index
end

-- Removes the item from a slot, paying out its stored cash to the owner first.
function Pedestals.TakeItem(player: Player, index: number)
	local data = S.Data.Get(player)
	local item = data and data.Slots[tostring(index)]
	if not item then
		return nil
	end
	if item.Stored and item.Stored > 0 then
		S.Data.AddCash(player, item.Stored)
		item.Stored = 0
	end
	data.Slots[tostring(index)] = nil
	Pedestals.RefreshSlot(player, index)
	return item
end

local function updateLabels(player: Player?, slot, item, unlocked: boolean)
	if not item then
		slot.NameLabel.Text = if unlocked then "" else "🔒"
		slot.RarityLabel.Text = if unlocked then "" else "Rebirth / Gamepass"
		slot.RarityLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		slot.IncomeLabel.Text = ""
		slot.TimerLabel.Text = if unlocked and player then "Empty slot" else ""
		slot.PadLabel.Text = ""
		return
	end
	local egg = Config.EggsById[item.EggId]
	local rarity = Config.Rarities[egg.Rarity]
	local mult = if player then Pedestals.PlayerMultiplier(player) else 1
	slot.NameLabel.Text = Pedestals.ItemName(item)
	slot.RarityLabel.Text = if item.Pet then egg.Rarity else egg.Rarity .. " Egg"
	slot.RarityLabel.TextColor3 = rarity.Color
	slot.IncomeLabel.Text = Util.FormatCash(Pedestals.ItemIncome(item) * mult) .. "/s"
	if item.Pet then
		slot.TimerLabel.Text = ""
	else
		slot.TimerLabel.Text = "🐣 Hatching in " .. Util.FormatTime(item.HatchAt - now())
	end
	slot.PadLabel.Text = if (item.Stored or 0) > 0 then Util.FormatCash(item.Stored) else ""
end

function Pedestals.RefreshSlot(player: Player, index: number)
	local plot = S.Plots.Get(player)
	local data = S.Data.Get(player)
	if not plot or not data then
		return
	end
	local slot = plot.Slots[index]
	if slot.ItemModel then
		slot.ItemModel:Destroy()
		slot.ItemModel = nil
	end
	local item = data.Slots[tostring(index)]
	local unlocked = index <= Pedestals.SlotCount(player)
	slot.Pedestal.Color = if unlocked then Color3.fromRGB(90, 90, 105) else Color3.fromRGB(40, 40, 45)
	slot.Pad.Transparency = if unlocked then 0 else 0.8
	slot.StealPrompt:SetAttribute("Occupied", item ~= nil)
	slot.SellPrompt:SetAttribute("Occupied", item ~= nil)
	if item then
		local model = S.Visuals.MakeItem(item)
		if model then
			model:PivotTo(slot.TopCFrame)
			model.Parent = plot.Model
			slot.ItemModel = model
		end
		slot.StealPrompt.ObjectText = Pedestals.ItemName(item)
		slot.SellPrompt.ObjectText = "Sell for " .. Util.FormatCash(Pedestals.ItemValue(item))
	end
	updateLabels(player, slot, item, unlocked)
end

function Pedestals.RefreshPlot(player: Player)
	local plot = S.Plots.Get(player)
	if not plot then
		return
	end
	for index in plot.Slots do
		Pedestals.RefreshSlot(player, index)
	end
end

function Pedestals.ClearPlot(plot)
	for _, slot in plot.Slots do
		if slot.ItemModel then
			slot.ItemModel:Destroy()
			slot.ItemModel = nil
		end
		slot.StealPrompt:SetAttribute("Occupied", false)
		slot.SellPrompt:SetAttribute("Occupied", false)
		slot.Pedestal.Color = Color3.fromRGB(90, 90, 105)
		slot.Pad.Transparency = 0
		updateLabels(nil, slot, nil, true)
	end
end

function Pedestals.Hatch(player: Player, index: number)
	local data = S.Data.Get(player)
	local item = data and data.Slots[tostring(index)]
	if not item or item.Pet then
		return
	end
	local egg = Config.EggsById[item.EggId]
	local pet = Util.WeightedPick(egg.Pets, function(p)
		return p.Weight
	end)
	local rush = S.Events.IsActive("GoldenRush")
	local mutation = Util.WeightedPick(Config.Mutations, function(m)
		if rush and m.Name ~= "Normal" then
			return m.Weight * 4
		end
		return m.Weight
	end)
	item.Pet = pet.Name
	item.Mutation = mutation.Name
	item.HatchAt = nil
	Pedestals.RefreshSlot(player, index)

	local plot = S.Plots.Get(player)
	local rarity = Config.Rarities[egg.Rarity]
	if plot then
		S.Visuals.Burst(plot.Slots[index].TopCFrame.Position + Vector3.new(0, 3, 0), rarity.Color, 60)
	end
	local name = Pedestals.ItemName(item)
	S.Notify(player, ("🐣 Your %s hatched a %s! (%s/s)"):format(egg.Name, name,
		Util.FormatCash(Pedestals.ItemIncome(item) * Pedestals.PlayerMultiplier(player))), rarity.Color)
	if rarity.Order >= 5 or mutation.Mult >= 5 or pet.Mult >= 10 then
		S.Announce(("🌟 %s hatched a %s %s!"):format(player.DisplayName, name, egg.Rarity), rarity.Color)
	end
end

function Pedestals.Collect(player: Player, index: number)
	local data = S.Data.Get(player)
	local item = data and data.Slots[tostring(index)]
	if not item or (item.Stored or 0) < 1 then
		return
	end
	local amount = math.floor(item.Stored)
	item.Stored -= amount
	S.Data.AddCash(player, amount)
	S.Effect(player, "Collect", amount)
end

function Pedestals.Sell(player: Player, index: number)
	local data = S.Data.Get(player)
	local item = data and data.Slots[tostring(index)]
	if not item then
		return
	end
	local value = Pedestals.ItemValue(item)
	Pedestals.TakeItem(player, index)
	S.Data.AddCash(player, value)
	S.Notify(player, ("💰 Sold %s for %s"):format(Pedestals.ItemName(item), Util.FormatCash(value)), Color3.fromRGB(120, 255, 120))
end

-- Offline earnings for pets/eggs while the player was away.
function Pedestals.ApplyOffline(player: Player)
	local data = S.Data.Get(player)
	if not data or (data.LastOnline or 0) <= 0 then
		return
	end
	local elapsed = math.clamp(os.time() - data.LastOnline, 0, Config.OfflineMaxSeconds)
	if elapsed < 60 then
		return
	end
	local mult = Pedestals.PlayerMultiplier(player) * Config.OfflineEarningRate
	local total = 0
	for _, item in data.Slots do
		local earned = Pedestals.ItemIncome(item) * mult * elapsed
		item.Stored = (item.Stored or 0) + earned
		total += earned
	end
	if total > 0 then
		task.delay(3, function()
			if player.Parent then
				S.Notify(player, ("🌙 Welcome back! Your pets earned %s while you were away. Walk on the green pads to collect!")
					:format(Util.FormatCash(total)), Color3.fromRGB(150, 200, 255))
			end
		end)
	end
end

function Pedestals.Start()
	-- Collect pads + prompts
	for _, plot in S.Plots.All() do
		for index, slot in plot.Slots do
			slot.Pad.Touched:Connect(function(hit)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if player and player == plot.Owner then
					Pedestals.Collect(player, index)
				end
			end)
			slot.SellPrompt.Triggered:Connect(function(player)
				if player == plot.Owner then
					Pedestals.Sell(player, index)
				end
			end)
			slot.StealPrompt.Triggered:Connect(function(player)
				if plot.Owner and player ~= plot.Owner then
					S.Steal.TrySteal(player, plot.Owner, index)
				end
			end)
		end
	end

	-- Income / hatch tick
	task.spawn(function()
		while true do
			local dt = 1
			for _, player in Players:GetPlayers() do
				local data = S.Data.Get(player)
				local plot = S.Plots.Get(player)
				if data and plot then
					local mult = Pedestals.PlayerMultiplier(player)
					local auto = S.Monetization.HasPass(player, "AutoCollect")
					local perSecond = 0
					for key, item in data.Slots do
						local index = tonumber(key)
						if not item.Pet and item.HatchAt and now() >= item.HatchAt then
							Pedestals.Hatch(player, index)
						end
						local income = Pedestals.ItemIncome(item) * mult
						perSecond += income
						if auto then
							S.Data.AddCash(player, income * dt)
						else
							item.Stored = (item.Stored or 0) + income * dt
						end
						updateLabels(player, plot.Slots[index], item, true)
					end
					player:SetAttribute("IncomePerSecond", perSecond)
				end
			end
			task.wait(dt)
		end
	end)
end

return Pedestals
