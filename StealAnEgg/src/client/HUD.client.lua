-- Steal an Egg — client HUD: cash, notifications, events, shop, rebirth, free gift, prompts.
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function now()
	return workspace:GetServerTimeNow()
end

------------------------------------------------------------------ UI helpers
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = Color3.fromRGB(20, 20, 30)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function text(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, props): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.3
	b.AutoButtonColor = true
	for key, value in props do
		(b :: any)[key] = value
	end
	corner(b)
	stroke(b)
	b.Parent = parent
	return b
end

------------------------------------------------------------------ Cash display
local cashFrame = Instance.new("Frame")
cashFrame.AnchorPoint = Vector2.new(0.5, 0)
cashFrame.Position = UDim2.new(0.5, 0, 0, 8)
cashFrame.Size = UDim2.fromOffset(300, 74)
cashFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
cashFrame.BackgroundTransparency = 0.25
corner(cashFrame, 16)
stroke(cashFrame, 3)
cashFrame.Parent = gui
local cashLabel = text(cashFrame, { Size = UDim2.fromScale(1, 0.62), TextColor3 = Color3.fromRGB(120, 255, 120), Text = "$0" })
local incomeLabel = text(cashFrame, { Size = UDim2.fromScale(1, 0.34), Position = UDim2.fromScale(0, 0.64), Text = "+$0/s" })

local function refreshCash()
	cashLabel.Text = Util.FormatCash(player:GetAttribute("Cash") or 0)
	incomeLabel.Text = "+" .. Util.FormatCash(player:GetAttribute("IncomePerSecond") or 0) .. "/s"
end
player:GetAttributeChangedSignal("Cash"):Connect(function()
	refreshCash()
	local pop = TweenService:Create(cashLabel, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ Size = UDim2.fromScale(1.08, 0.66) })
	pop:Play()
end)
player:GetAttributeChangedSignal("IncomePerSecond"):Connect(refreshCash)
refreshCash()

------------------------------------------------------------------ Status (lock / carry / event)
local statusLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 86),
	Size = UDim2.fromOffset(420, 26),
	Text = "",
})
local eventLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 114),
	Size = UDim2.fromOffset(520, 30),
	Text = "",
})

------------------------------------------------------------------ Notifications
local toastHolder = Instance.new("Frame")
toastHolder.BackgroundTransparency = 1
toastHolder.AnchorPoint = Vector2.new(1, 0)
toastHolder.Position = UDim2.new(1, -12, 0, 12)
toastHolder.Size = UDim2.fromOffset(360, 400)
toastHolder.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = toastHolder
local toastCount = 0

local function toast(message: string, color: Color3)
	toastCount += 1
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 46)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	frame.BackgroundTransparency = 0.15
	frame.LayoutOrder = -toastCount
	corner(frame, 10)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 2
	s.Parent = frame
	text(frame, {
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = message,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	frame.Parent = toastHolder
	local children = toastHolder:GetChildren()
	if #children > 8 then
		for _, child in children do
			if child:IsA("Frame") and child.LayoutOrder > -toastCount + 6 then
				child:Destroy()
			end
		end
	end
	task.delay(5, function()
		frame:Destroy()
	end)
end

local announceLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.28),
	Size = UDim2.fromScale(0.7, 0.07),
	Text = "",
	TextTransparency = 1,
	TextStrokeTransparency = 1,
})
local announceToken = 0
local function announce(message: string, color: Color3)
	announceToken += 1
	local token = announceToken
	announceLabel.Text = message
	announceLabel.TextColor3 = color
	announceLabel.TextTransparency = 0
	announceLabel.TextStrokeTransparency = 0
	announceLabel.Size = UDim2.fromScale(0.5, 0.05)
	TweenService:Create(announceLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.7, 0.07) }):Play()
	task.delay(4, function()
		if token == announceToken then
			TweenService:Create(announceLabel, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

Remotes.Notify.OnClientEvent:Connect(function(message: string, color: Color3, isAnnouncement: boolean)
	if isAnnouncement then
		announce(message, color)
	end
	toast(message, color)
end)

------------------------------------------------------------------ Effects
local collectSound = Instance.new("Sound")
collectSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
collectSound.Volume = 0.5
collectSound.Parent = gui

Remotes.Effect.OnClientEvent:Connect(function(kind: string, amount: number)
	if kind == "Collect" then
		collectSound:Play()
		local float = text(gui, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromOffset(260, 50),
			Text = "+" .. Util.FormatCash(amount),
			TextColor3 = Color3.fromRGB(120, 255, 120),
		})
		TweenService:Create(float, TweenInfo.new(1), { Position = UDim2.fromScale(0.5, 0.4), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(1, function()
			float:Destroy()
		end)
	elseif kind == "Steal" then
		announce("😈 STOLEN!", Color3.fromRGB(255, 220, 90))
	end
end)

Remotes.Knockback.OnClientEvent:Connect(function(push: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		root.AssemblyLinearVelocity = push
	end
end)

------------------------------------------------------------------ Left buttons
local sideBar = Instance.new("Frame")
sideBar.BackgroundTransparency = 1
sideBar.AnchorPoint = Vector2.new(0, 0.5)
sideBar.Position = UDim2.new(0, 12, 0.5, 0)
sideBar.Size = UDim2.fromOffset(140, 240)
sideBar.Parent = gui
local sideList = Instance.new("UIListLayout")
sideList.Padding = UDim.new(0, 10)
sideList.Parent = sideBar

local shopButton = button(sideBar, { Size = UDim2.fromOffset(140, 60), Text = "🛒 Shop", BackgroundColor3 = Color3.fromRGB(255, 170, 40) })
local rebirthButton = button(sideBar, { Size = UDim2.fromOffset(140, 60), Text = "🔁 Rebirth", BackgroundColor3 = Color3.fromRGB(170, 90, 255) })
local giftButton = button(sideBar, { Size = UDim2.fromOffset(140, 60), Text = "🎁 Gift", BackgroundColor3 = Color3.fromRGB(60, 200, 110) })

------------------------------------------------------------------ Panels
local function panel(title: string): (Frame, Frame)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(460, 420)
	frame.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
	frame.Visible = false
	corner(frame, 18)
	stroke(frame, 4)
	frame.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(460, 420)
	constraint.Parent = frame
	text(frame, { Size = UDim2.new(1, -60, 0, 44), Position = UDim2.fromOffset(16, 8), Text = title, TextXAlignment = Enum.TextXAlignment.Left })
	local close = button(frame, { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -50, 0, 10), Text = "X", BackgroundColor3 = Color3.fromRGB(230, 60, 60) })
	close.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)
	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 60)
	body.Size = UDim2.new(1, -24, 1, -72)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 6
	body.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body
	return frame, body
end

-- Shop
local shopFrame, shopBody = panel("🛒 Shop")
local function shopRow(order: number, name: string, description: string, price: number, onBuy: (() -> ())?)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 64)
	row.BackgroundColor3 = Color3.fromRGB(50, 50, 75)
	row.LayoutOrder = order
	corner(row, 10)
	row.Parent = shopBody
	text(row, { Size = UDim2.new(0.65, 0, 0.55, 0), Position = UDim2.fromOffset(10, 2), Text = name, TextXAlignment = Enum.TextXAlignment.Left })
	text(row, {
		Size = UDim2.new(0.65, 0, 0.38, 0),
		Position = UDim2.new(0, 10, 0.58, 0),
		Text = description,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local buy = button(row, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.3, 0, 0.75, 0),
		Text = if onBuy then "R$ " .. price else "Soon",
		BackgroundColor3 = if onBuy then Color3.fromRGB(60, 200, 110) else Color3.fromRGB(110, 110, 120),
	})
	if onBuy then
		buy.MouseButton1Click:Connect(onBuy)
	end
	return buy
end

local order = 0
for key, pass in Config.GamePasses do
	order += 1
	local buy = shopRow(order, "⭐ " .. pass.Name, pass.Description, pass.Price, if pass.Id ~= 0 then function()
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end else nil)
	local function markOwned()
		if player:GetAttribute("Pass_" .. key) then
			buy.Text = "Owned"
			buy.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
			buy.Active = false
		end
	end
	player:GetAttributeChangedSignal("Pass_" .. key):Connect(markOwned)
	markOwned()
end
for _, product in Config.Products do
	order += 1
	local description = if product.Kind == "Cash" then ("%d min of income (min %s)"):format(product.Minutes, Util.FormatCash(product.Minimum))
		elseif product.Kind == "ServerLuck" then "Lucky Hour for EVERYONE in the server"
		elseif product.Kind == "Shield" then "Nobody can steal from you"
		else "Instantly hatch every egg in your base"
	shopRow(100 + order, product.Name, description, product.Price, if product.Id ~= 0 then function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end else nil)
end

-- Rebirth
local rebirthFrame, rebirthBody = panel("🔁 Rebirth")
local rebirthInfo = text(rebirthBody, { Size = UDim2.new(1, -8, 0, 150), TextWrapped = true, LayoutOrder = 1, Text = "" })
local doRebirth = button(rebirthBody, {
	Size = UDim2.new(1, -8, 0, 64),
	LayoutOrder = 2,
	Text = "REBIRTH",
	BackgroundColor3 = Color3.fromRGB(170, 90, 255),
})
local function refreshRebirth()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local cost = player:GetAttribute("RebirthCost") or Config.RebirthBaseCost
	rebirthInfo.Text = ("Cost: %s\nIncome: x%.1f → x%.1f\n+%d egg slot\n⚠ Resets your cash and base!"):format(
		Util.FormatCash(cost),
		1 + rebirths * Config.RebirthIncomeBonus,
		1 + (rebirths + 1) * Config.RebirthIncomeBonus,
		Config.Plot.SlotsPerRebirth
	)
	local affordable = (player:GetAttribute("Cash") or 0) >= cost
	doRebirth.BackgroundColor3 = if affordable then Color3.fromRGB(170, 90, 255) else Color3.fromRGB(110, 110, 120)
end
doRebirth.MouseButton1Click:Connect(function()
	Remotes.Rebirth:FireServer()
	rebirthFrame.Visible = false
end)

shopButton.MouseButton1Click:Connect(function()
	rebirthFrame.Visible = false
	shopFrame.Visible = not shopFrame.Visible
end)
rebirthButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
	refreshRebirth()
	rebirthFrame.Visible = not rebirthFrame.Visible
end)
giftButton.MouseButton1Click:Connect(function()
	if (player:GetAttribute("NextGiftAt") or math.huge) <= now() then
		Remotes.ClaimGift:FireServer()
	end
end)

------------------------------------------------------------------ Prompt visibility
-- Owners see "Sell" on their own pedestals, everyone else sees "Steal".
local function refreshPrompt(prompt: ProximityPrompt)
	local occupied = prompt:GetAttribute("Occupied") == true
	local ownerId = prompt:GetAttribute("OwnerId") or 0
	local isMine = ownerId == player.UserId
	if prompt:GetAttribute("Role") == "Steal" then
		prompt.Enabled = occupied and ownerId ~= 0 and not isMine
	else
		prompt.Enabled = occupied and isMine
	end
end
local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	refreshPrompt(prompt)
	prompt:GetAttributeChangedSignal("Occupied"):Connect(function()
		refreshPrompt(prompt)
	end)
	prompt:GetAttributeChangedSignal("OwnerId"):Connect(function()
		refreshPrompt(prompt)
	end)
end
CollectionService:GetInstanceAddedSignal("SlotPrompt"):Connect(watchPrompt)
for _, prompt in CollectionService:GetTagged("SlotPrompt") do
	watchPrompt(prompt)
end

------------------------------------------------------------------ Per-frame text updates
local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.25 then
		return
	end
	accumulator = 0

	local giftAt = player:GetAttribute("NextGiftAt") or math.huge
	if giftAt <= now() then
		giftButton.Text = "🎁 CLAIM!"
	else
		giftButton.Text = "🎁 " .. (if giftAt == math.huge then "..." else Util.FormatTime(giftAt - now()))
	end

	local carrying = player:GetAttribute("Carrying")
	local lockedUntil = player:GetAttribute("LockedUntil") or 0
	if carrying then
		statusLabel.Text = "🏃 Carrying " .. carrying .. " — RUN HOME!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	elseif lockedUntil > now() then
		statusLabel.Text = "🔒 Your base is locked: " .. Util.FormatTime(lockedUntil - now())
		statusLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	else
		statusLabel.Text = "🔓 Base unlocked — step on the green LOCK pad!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	end

	local eventName = ReplicatedStorage:GetAttribute("EventName") or ""
	local eventEnds = ReplicatedStorage:GetAttribute("EventEnds") or 0
	local info = Config.Events[eventName]
	if info and eventEnds > now() then
		eventLabel.Text = "⚡ " .. info.Title .. " — " .. info.Text .. " " .. Util.FormatTime(eventEnds - now())
		eventLabel.TextColor3 = info.Color
	else
		eventLabel.Text = ""
	end

	if rebirthFrame.Visible then
		refreshRebirth()
	end
end)
