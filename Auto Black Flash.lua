--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!

	Auto Black Flash
	Bug-fixed version. See PR description for the list of issues addressed.
]]
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local enabled = true

local function notify(title, text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = duration,
		})
	end)
end

notify(
	"Auto Black Flash",
	"Loaded!\nClick button to toggle\nDrag by title • X to close (disables BF)",
	6
)

local AnimationTriggers = {
	["rbxassetid://100962226150441"] = 0.18,
	["rbxassetid://95852624447551"] = 0.18,
	["rbxassetid://74145636023952"] = 0.18,
	["rbxassetid://72475960800126"] = 0.20,
}

local function pressKey(keyCode)
	-- Guarantee the key is released even if SendKeyEvent throws mid-press,
	-- otherwise the key can get "stuck" down.
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
	end)
	task.wait()
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
end

-- Cooldown so overlapping / rapidly repeated trigger animations don't queue
-- up multiple key presses at once.
local lastPress = 0
local PRESS_COOLDOWN = 0.25

-- Track the current character's connection so respawning doesn't leak an
-- ever-growing pile of AnimationPlayed listeners.
local animationConnection

local function setupCharacter(character)
	if not character then return end

	if animationConnection then
		animationConnection:Disconnect()
		animationConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	local animator = humanoid:WaitForChild("Animator", 5)
	if not animator then return end

	animationConnection = animator.AnimationPlayed:Connect(function(track)
		if not enabled then return end
		local animation = track and track.Animation
		if not animation then return end

		local delayTime = AnimationTriggers[animation.AnimationId]
		if not delayTime then return end

		task.delay(delayTime, function()
			if not enabled then return end
			if humanoid.Health <= 0 then return end
			if os.clock() - lastPress < PRESS_COOLDOWN then return end
			lastPress = os.clock()
			pressKey(Enum.KeyCode.Three)
		end)
	end)
end

-- Run the initial setup off the main thread so its WaitForChild calls don't
-- delay the rest of the script (notably GUI creation) by up to 10 seconds.
if player.Character then
	task.spawn(setupCharacter, player.Character)
end
player.CharacterAdded:Connect(function(char)
	task.wait(0.3)
	setupCharacter(char)
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBlackFlash"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 100)
frame.Position = UDim2.new(1, -260, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 60)
stroke.Thickness = 1.5
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -35, 0, 35)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "AUTO BLACK FLASH"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = frame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.88, 0, 0, 42)
toggleButton.Position = UDim2.new(0.06, 0, 0, 48)
toggleButton.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
toggleButton.Text = "ENABLED"
toggleButton.TextColor3 = Color3.fromRGB(0, 0, 0)
toggleButton.TextScaled = true
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Parent = frame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 10)
btnCorner.Parent = toggleButton

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 28, 0, 28)
closeButton.Position = UDim2.new(1, -33, 0, 6)
closeButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = frame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

local function updateButton()
	if enabled then
		toggleButton.Text = "ENABLED ✅"
		toggleButton.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
	else
		toggleButton.Text = "DISABLED ❌"
		toggleButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	end
end

toggleButton.MouseButton1Click:Connect(function()
	enabled = not enabled
	updateButton()
	notify("Auto Black Flash", enabled and "ENABLED ✅" or "DISABLED ❌", 2.5)
end)

updateButton()

-- Dragging (supports both mouse and touch). Keep references to the global
-- UserInputService connections so they can be cleaned up on close instead of
-- firing forever against a destroyed frame.
local dragging = false
local dragStart
local startPos
local inputChangedConn
local inputEndedConn

local function isDragInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMoveInput(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

title.InputBegan:Connect(function(input)
	if isDragInput(input) then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)

inputChangedConn = UserInputService.InputChanged:Connect(function(input)
	if dragging and isMoveInput(input) and dragStart then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

inputEndedConn = UserInputService.InputEnded:Connect(function(input)
	if isDragInput(input) then
		dragging = false
	end
end)

closeButton.MouseButton1Click:Connect(function()
	enabled = false
	if animationConnection then
		animationConnection:Disconnect()
		animationConnection = nil
	end
	if inputChangedConn then
		inputChangedConn:Disconnect()
		inputChangedConn = nil
	end
	if inputEndedConn then
		inputEndedConn:Disconnect()
		inputEndedConn = nil
	end
	screenGui:Destroy()
end)
--son im crine who even struggle to blackflash
