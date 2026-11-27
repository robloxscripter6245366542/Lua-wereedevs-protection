-- Steal an Egg — server bootstrap.
-- Loop: buy eggs off the conveyor -> they incubate in your base and earn cash -> hatch into
-- pets (with mutations) that earn way more -> steal other players' eggs/pets, bonk thieves,
-- lock your base -> rebirth for multipliers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Services = script.Parent:WaitForChild("Services")
local S = {}

-- Remotes
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotesFolder
	return r
end
S.Remotes = {
	Notify = remote("Notify"),
	Effect = remote("Effect"),
	Knockback = remote("Knockback"),
	Rebirth = remote("Rebirth"),
	ClaimGift = remote("ClaimGift"),
}
remotesFolder.Parent = ReplicatedStorage

function S.Notify(player: Player, text: string, color: Color3?)
	S.Remotes.Notify:FireClient(player, text, color or Color3.new(1, 1, 1), false)
end

function S.Announce(text: string, color: Color3?)
	S.Remotes.Notify:FireAllClients(text, color or Color3.new(1, 1, 1), true)
end

function S.Effect(player: Player, kind: string, amount: number)
	S.Remotes.Effect:FireClient(player, kind, amount)
end

local ORDER = { "Data", "Visuals", "Plots", "Monetization", "Events", "Pedestals", "Conveyor", "Steal", "Bat" }
for _, name in ORDER do
	S[name] = require(Services:WaitForChild(name))
end
for _, name in ORDER do
	if S[name].Init then
		S[name].Init(S)
	end
end
for _, name in ORDER do
	if S[name].Start then
		S[name].Start()
	end
end

local function now()
	return workspace:GetServerTimeNow()
end

local function rebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

local function onCharacter(player: Player, character: Model)
	local plot = S.Plots.Get(player)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	humanoid.WalkSpeed = Config.NormalWalkSpeed
	if plot then
		task.defer(function()
			character:PivotTo(plot.SpawnCFrame)
		end)
	end
	S.Bat.Give(player)
end

local function onPlayerAdded(player: Player)
	local data = S.Data.Load(player)
	if not data then
		return
	end
	if not player.Parent then
		S.Data.Release(player) -- left while loading
		return
	end
	S.Monetization.LoadPasses(player)
	local plot = S.Plots.Assign(player)
	if not plot then
		player:Kick("Server is full, please join another server!")
		return
	end
	S.Pedestals.ApplyOffline(player)
	S.Pedestals.RefreshPlot(player)

	player:SetAttribute("NextGiftAt", now() + Config.GiftInterval)
	player:SetAttribute("RebirthCost", rebirthCost(data.Rebirths))

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	S.Notify(player, "🥚 Welcome to " .. Config.GameName .. "! Buy eggs on the conveyor, hatch pets, steal from others!",
		Color3.fromRGB(255, 220, 90))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	S.Steal.OnPlayerRemoving(player)
	local plot = S.Plots.Get(player)
	S.Data.Save(player)
	if plot then
		S.Pedestals.ClearPlot(plot)
	end
	S.Plots.Release(player)
	S.Monetization.Release(player)
	S.Data.Release(player)
end)

game:BindToClose(function()
	S.Data.SaveAll()
end)

S.Remotes.Rebirth.OnServerEvent:Connect(function(player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local cost = rebirthCost(data.Rebirths)
	if data.Cash < cost then
		S.Notify(player, "❌ You need " .. Util.FormatCash(cost) .. " to rebirth!", Color3.fromRGB(255, 90, 90))
		return
	end
	if S.Steal.IsCarrying(player) then
		S.Steal.Drop(player, "rebirth")
	end
	data.Rebirths += 1
	data.Cash = Config.StartingCash
	data.Slots = {}
	S.Data.Sync(player)
	S.Pedestals.RefreshPlot(player)
	player:SetAttribute("RebirthCost", rebirthCost(data.Rebirths))
	S.Announce(("🔁 %s rebirthed! (Rebirth %d — x%.1f income)"):format(player.DisplayName, data.Rebirths,
		1 + data.Rebirths * Config.RebirthIncomeBonus), Color3.fromRGB(200, 120, 255))
	task.spawn(S.Data.Save, player)
end)

S.Remotes.ClaimGift.OnServerEvent:Connect(function(player)
	local data = S.Data.Get(player)
	if not data or (player:GetAttribute("NextGiftAt") or math.huge) > now() then
		return
	end
	if not S.Pedestals.FreeSlot(player) then
		S.Notify(player, "❌ Make room in your base first!", Color3.fromRGB(255, 90, 90))
		return
	end
	-- Flattened odds so free gifts feel generous; capped near your current progress.
	local best = 1
	for _, item in data.Slots do
		local egg = Config.EggsById[item.EggId]
		if egg and egg.Index > best then
			best = egg.Index
		end
	end
	local pool = {}
	for _, egg in Config.Eggs do
		if egg.Index <= best + 2 then
			table.insert(pool, egg)
		end
	end
	local egg = Util.WeightedPick(pool, function(e)
		return e.SpawnWeight ^ 0.6
	end)
	S.Pedestals.PlaceItem(player, S.Pedestals.NewEggItem(player, egg))
	player:SetAttribute("NextGiftAt", now() + Config.GiftInterval)
	S.Notify(player, "🎁 Free gift: " .. egg.Name .. "!", Config.Rarities[egg.Rarity].Color)
end)
