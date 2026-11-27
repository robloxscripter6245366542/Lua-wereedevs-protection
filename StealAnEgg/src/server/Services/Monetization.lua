-- Game passes + developer products (ProcessReceipt with duplicate protection).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Monetization = {}
local S
local owned: { [Player]: { [string]: boolean } } = {}

local function now()
	return workspace:GetServerTimeNow()
end

function Monetization.HasPass(player: Player, key: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[key] == true
end

local function grantPass(player: Player, key: string)
	owned[player] = owned[player] or {}
	owned[player][key] = true
	player:SetAttribute("Pass_" .. key, true)
	if key == "ExtraSlots" then
		S.Pedestals.RefreshPlot(player)
	end
end

function Monetization.LoadPasses(player: Player)
	owned[player] = {}
	for key, pass in Config.GamePasses do
		if pass.Id ~= 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and has then
				grantPass(player, key)
			end
		end
	end
end

function Monetization.Release(player: Player)
	owned[player] = nil
end

local function grantProduct(player: Player, product): boolean
	local data = S.Data.Get(player)
	if not data then
		return false
	end
	if product.Kind == "Cash" then
		local income = player:GetAttribute("IncomePerSecond") or 0
		local amount = math.floor(math.max(product.Minimum, income * product.Minutes * 60))
		S.Data.AddCash(player, amount)
		S.Notify(player, "💸 +" .. Util.FormatCash(amount) .. "! Thanks for the support!", Color3.fromRGB(120, 255, 120))
	elseif product.Kind == "ServerLuck" then
		S.Events.Begin("LuckyHour", product.Duration, player.DisplayName)
	elseif product.Kind == "Shield" then
		data.ShieldUntil = math.max(data.ShieldUntil or 0, now()) + product.Duration
		S.Data.Sync(player)
		S.Notify(player, "🛡️ Base shielded for " .. Util.FormatTime(product.Duration) .. "!", Color3.fromRGB(120, 200, 255))
	elseif product.Kind == "InstantHatch" then
		for _, item in data.Slots do
			if not item.Pet then
				item.HatchAt = 0
			end
		end
		S.Notify(player, "🐣 Hatching all your eggs NOW!", Color3.fromRGB(255, 220, 90))
	else
		return false
	end
	return true
end

function Monetization.Init(services)
	S = services
	local productsById = {}
	for _, product in Config.Products do
		if product.Id ~= 0 then
			productsById[product.Id] = product
		end
	end

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local product = productsById[receipt.ProductId]
		local data = player and S.Data.Get(player)
		if not player or not product or not data then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		data.Receipts = data.Receipts or {}
		if table.find(data.Receipts, receipt.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local ok, granted = pcall(grantProduct, player, product)
		if not ok or not granted then
			warn("[Monetization] grant failed:", granted)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(data.Receipts, receipt.PurchaseId)
		while #data.Receipts > 50 do
			table.remove(data.Receipts, 1)
		end
		task.spawn(S.Data.Save, player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in Config.GamePasses do
			if pass.Id == passId then
				grantPass(player, key)
				S.Notify(player, "🎉 You got " .. pass.Name .. "!", Color3.fromRGB(255, 220, 90))
			end
		end
	end)
end

return Monetization
