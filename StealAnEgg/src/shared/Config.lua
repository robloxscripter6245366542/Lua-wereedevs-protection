-- Steal an Egg: all tuning lives here. Prices, hatch times, odds and Robux IDs.
local Config = {}

Config.GameName = "Steal an Egg"
Config.DataStoreName = "StealAnEgg_v1"
Config.StartingCash = 100
Config.AutosaveInterval = 60

Config.Plot = {
	Count = 8,
	Width = 70,
	Depth = 56,
	BaseSlots = 6,
	MaxSlots = 12,
	SlotsPerRebirth = 1,
}

Config.LockDuration = 60 -- seconds the laser door stays up after pressing the lock pad
Config.StealHoldDuration = 1.2
Config.CarryWalkSpeed = 11
Config.NormalWalkSpeed = 20
Config.BatCooldown = 0.8
Config.BatRange = 8
Config.BatKnockback = 70

Config.OfflineEarningRate = 0.5 -- pets earn 50% while you are offline
Config.OfflineMaxSeconds = 8 * 3600
Config.GiftInterval = 600 -- free egg every 10 minutes of play

Config.RebirthBaseCost = 1_000_000
Config.RebirthCostGrowth = 4
Config.RebirthIncomeBonus = 0.5 -- +50% income per rebirth

Config.Conveyor = {
	SpawnInterval = 2.2,
	Speed = 9,
	StartX = -190,
	EndX = 190,
	MaxEggs = 45,
}

Config.EventInterval = 8 * 60
Config.EventDuration = 3 * 60

Config.Rarities = {
	Common = { Order = 1, Color = Color3.fromRGB(210, 210, 210) },
	Uncommon = { Order = 2, Color = Color3.fromRGB(90, 225, 90) },
	Rare = { Order = 3, Color = Color3.fromRGB(70, 160, 255) },
	Epic = { Order = 4, Color = Color3.fromRGB(180, 90, 255) },
	Legendary = { Order = 5, Color = Color3.fromRGB(255, 185, 40) },
	Mythic = { Order = 6, Color = Color3.fromRGB(255, 60, 100) },
	Secret = { Order = 7, Color = Color3.fromRGB(255, 255, 255) },
}

-- Rolled when an egg hatches. Weights are relative.
Config.Mutations = {
	{ Name = "Normal", Mult = 1, Weight = 1000 },
	{ Name = "Golden", Mult = 2, Weight = 60, Color = Color3.fromRGB(255, 200, 40) },
	{ Name = "Diamond", Mult = 3, Weight = 20, Color = Color3.fromRGB(120, 230, 255) },
	{ Name = "Rainbow", Mult = 5, Weight = 6, Color = Color3.fromRGB(255, 120, 220) },
	{ Name = "Galaxy", Mult = 10, Weight = 1, Color = Color3.fromRGB(90, 40, 200) },
}

-- Income is $/sec. An incubating egg earns Income; a hatched pet earns Income * pet Mult * mutation Mult.
-- Pet names double as model names: drop a model called e.g. "Penguin" into ServerStorage.Models.Pets.
Config.Eggs = {
	{
		Id = "Dirt", Name = "Dirt Egg", Rarity = "Common", Price = 50, Income = 1, HatchTime = 30,
		SpawnWeight = 400, Color = Color3.fromRGB(130, 90, 60),
		Pets = {
			{ Name = "Worm", Weight = 60, Mult = 3 },
			{ Name = "Slime", Weight = 30, Mult = 5 },
			{ Name = "Mole", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Grass", Name = "Grass Egg", Rarity = "Common", Price = 250, Income = 4, HatchTime = 45,
		SpawnWeight = 260, Color = Color3.fromRGB(90, 190, 70),
		Pets = {
			{ Name = "Bunny", Weight = 60, Mult = 3 },
			{ Name = "Fox", Weight = 30, Mult = 5 },
			{ Name = "Cat", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Spotted", Name = "Spotted Egg", Rarity = "Uncommon", Price = 1_000, Income = 12, HatchTime = 60,
		SpawnWeight = 150, Color = Color3.fromRGB(240, 230, 200),
		Pets = {
			{ Name = "Cow", Weight = 60, Mult = 3 },
			{ Name = "Dalmatian", Weight = 30, Mult = 5 },
			{ Name = "Giraffe", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Ice", Name = "Ice Egg", Rarity = "Rare", Price = 5_000, Income = 40, HatchTime = 90,
		SpawnWeight = 80, Color = Color3.fromRGB(160, 220, 255),
		Pets = {
			{ Name = "Penguin", Weight = 60, Mult = 3 },
			{ Name = "Arctic Fox", Weight = 30, Mult = 5 },
			{ Name = "Yeti", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Lava", Name = "Lava Egg", Rarity = "Epic", Price = 25_000, Income = 150, HatchTime = 120,
		SpawnWeight = 40, Color = Color3.fromRGB(255, 90, 30),
		Pets = {
			{ Name = "Fire Lizard", Weight = 60, Mult = 3 },
			{ Name = "Hellhound", Weight = 30, Mult = 5 },
			{ Name = "Dragon", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Crystal", Name = "Crystal Egg", Rarity = "Epic", Price = 120_000, Income = 600, HatchTime = 180,
		SpawnWeight = 20, Color = Color3.fromRGB(200, 120, 255),
		Pets = {
			{ Name = "Crystal Bat", Weight = 60, Mult = 3 },
			{ Name = "Gem Golem", Weight = 30, Mult = 5 },
			{ Name = "Unicorn", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Golden", Name = "Golden Egg", Rarity = "Legendary", Price = 600_000, Income = 2_500, HatchTime = 240,
		SpawnWeight = 8, Color = Color3.fromRGB(255, 205, 50),
		Pets = {
			{ Name = "Golden Lion", Weight = 60, Mult = 3 },
			{ Name = "Pegasus", Weight = 30, Mult = 5 },
			{ Name = "Phoenix", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Cosmic", Name = "Cosmic Egg", Rarity = "Mythic", Price = 3_000_000, Income = 10_000, HatchTime = 300,
		SpawnWeight = 3, Color = Color3.fromRGB(60, 40, 140),
		Pets = {
			{ Name = "Star Whale", Weight = 60, Mult = 3 },
			{ Name = "Nebula Cat", Weight = 30, Mult = 5 },
			{ Name = "Galaxy Dragon", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Rainbow", Name = "Rainbow Egg", Rarity = "Mythic", Price = 20_000_000, Income = 50_000, HatchTime = 420,
		SpawnWeight = 1, Color = Color3.fromRGB(255, 120, 200),
		Pets = {
			{ Name = "Rainbow Unicorn", Weight = 60, Mult = 3 },
			{ Name = "Prism Fox", Weight = 30, Mult = 5 },
			{ Name = "Rainbow Phoenix", Weight = 10, Mult = 10 },
		},
	},
	{
		Id = "Void", Name = "??? Void Egg", Rarity = "Secret", Price = 150_000_000, Income = 300_000, HatchTime = 600,
		SpawnWeight = 0.25, Color = Color3.fromRGB(15, 10, 25),
		Pets = {
			{ Name = "Void Serpent", Weight = 70, Mult = 4 },
			{ Name = "The Egg King", Weight = 30, Mult = 12 },
		},
	},
}

Config.EggsById = {}
for index, egg in ipairs(Config.Eggs) do
	egg.Index = index
	Config.EggsById[egg.Id] = egg
end

-- Server-wide events (Grow a Garden style weather). LuckyHour boosts rare conveyor eggs,
-- GoldenRush boosts hatch mutations, CashFrenzy doubles income.
Config.Events = {
	LuckyHour = { Title = "LUCKY HOUR", Text = "Rare eggs spawn way more often!", Color = Color3.fromRGB(90, 255, 120) },
	GoldenRush = { Title = "GOLDEN RUSH", Text = "Mutations are 4x more likely!", Color = Color3.fromRGB(255, 205, 50) },
	CashFrenzy = { Title = "CASH FRENZY", Text = "All income is doubled!", Color = Color3.fromRGB(80, 200, 255) },
}

-- ROBUX: create these in Creator Hub (Monetization) and paste the IDs. 0 = disabled.
Config.GamePasses = {
	VIP = { Id = 0, Name = "VIP", Description = "1.5x income + VIP tag", Price = 199 },
	DoubleCash = { Id = 0, Name = "2x Cash", Description = "Double all income forever", Price = 399 },
	ExtraSlots = { Id = 0, Name = "+3 Egg Slots", Description = "Hold 3 more eggs/pets", Price = 249 },
	FastHatch = { Id = 0, Name = "Fast Hatch", Description = "Eggs hatch 2x faster", Price = 149 },
	AutoCollect = { Id = 0, Name = "Auto Collect", Description = "Cash goes straight to your wallet", Price = 99 },
}
Config.ExtraSlotsAmount = 3

Config.Products = {
	CashSmall = { Id = 0, Name = "Small Cash Pack", Kind = "Cash", Minutes = 10, Minimum = 2_500, Price = 25 },
	CashMedium = { Id = 0, Name = "Big Cash Pack", Kind = "Cash", Minutes = 60, Minimum = 50_000, Price = 99 },
	CashLarge = { Id = 0, Name = "Mega Cash Pack", Kind = "Cash", Minutes = 360, Minimum = 1_000_000, Price = 399 },
	ServerLuck = { Id = 0, Name = "Server Luck (10 min)", Kind = "ServerLuck", Duration = 600, Price = 149 },
	Shield = { Id = 0, Name = "Base Shield (10 min)", Kind = "Shield", Duration = 600, Price = 49 },
	InstantHatch = { Id = 0, Name = "Hatch All Eggs Now", Kind = "InstantHatch", Price = 39 },
}

return Config
