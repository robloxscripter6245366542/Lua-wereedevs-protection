-- Player save data: load/save with retries, autosave, cash helpers.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Data = {}
local S
local store: DataStore? = nil
local profiles: { [Player]: any } = {}
local noSave: { [Player]: boolean } = {}

local function defaultData()
	return {
		Cash = Config.StartingCash,
		Rebirths = 0,
		Slots = {}, -- ["1"] = { EggId, Pet, Mutation, HatchAt, Stored }
		LastOnline = 0,
		TotalEarned = 0,
		TotalSteals = 0,
		ShieldUntil = 0,
		Receipts = {},
	}
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

function Data.Init(services)
	S = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStores unavailable (enable Studio API access to test saving):", result)
	end
end

function Data.Load(player: Player)
	local loaded = nil
	local success = store == nil
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(keyFor(player))
			end)
			if ok then
				loaded = result
				success = true
				break
			end
			warn(("[Data] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
			task.wait(attempt)
		end
	end
	if not success then
		-- Never overwrite a save we failed to read.
		noSave[player] = true
		player:Kick("Could not load your data. Please rejoin!")
		return nil
	end

	local data = defaultData()
	if type(loaded) == "table" then
		for key, value in loaded do
			data[key] = value
		end
	end
	profiles[player] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats
	leaderstats.Parent = player

	Data.Sync(player)
	return data
end

function Data.Get(player: Player)
	return profiles[player]
end

function Data.Sync(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	player:SetAttribute("Cash", data.Cash)
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("ShieldUntil", data.ShieldUntil)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Cash.Value = Util.FormatCash(data.Cash)
		leaderstats.Rebirths.Value = data.Rebirths
	end
end

function Data.AddCash(player: Player, amount: number)
	local data = profiles[player]
	if not data or amount ~= amount then
		return
	end
	data.Cash += amount
	if amount > 0 then
		data.TotalEarned += amount
	end
	Data.Sync(player)
end

function Data.SpendCash(player: Player, amount: number): boolean
	local data = profiles[player]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	Data.Sync(player)
	return true
end

function Data.Save(player: Player)
	local data = profiles[player]
	if not data or not store or noSave[player] then
		return
	end
	data.LastOnline = os.time()
	local ds = store :: DataStore
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(player), function()
				return data
			end)
		end)
		if ok then
			return
		end
		warn(("[Data] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
end

function Data.Release(player: Player)
	profiles[player] = nil
	noSave[player] = nil
end

function Data.Start()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(Data.Save, player)
			end
		end
	end)
end

function Data.SaveAll()
	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			S.Steal.OnPlayerRemoving(player)
			Data.Save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.2)
	end
end

return Data
