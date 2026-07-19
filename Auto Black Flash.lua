--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!

	Auto Black Flash
	- Auto-combat: finds the nearest player, gets behind them, presses the
	  black-flash key, then side-dashes and repeats.

	Game binds differ, so edit the CONFIG block below to match your game.
]]
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- CONFIG  (edit these to match your game)
------------------------------------------------------------------------
local CONFIG = {
	-- Key that performs a dash/dodge in your game (Q is a common default).
	DASH_KEY = Enum.KeyCode.Q,

	-- How close (in studs) a player must be before auto-combat engages.
	DETECT_RANGE = 40,

	-- How close you must be to actually land the hit.
	ATTACK_RANGE = 14,

	-- "Behind" cutoff: dot of the target's look vector and the direction to
	-- you. -1 = directly behind, 0 = at their side. Lower = stricter.
	BEHIND_DOT = -0.25,

	-- Timing.
	BLACK_FLASH_GAP = 0.33,   -- gap between the first and second click
	HIT_TO_DASH_DELAY = 0.15, -- wait after the black flash before dashing
	DASH_HOLD = 0.12,         -- how long the strafe key is held during a dash
	LOOP_INTERVAL = 0.1,      -- delay between combat-loop iterations
	PRESS_COOLDOWN = 0.25,    -- min time between black-flash attempts

	-- Master switch for the positional auto-combat loop.
	USE_AUTO_COMBAT = true,
}
------------------------------------------------------------------------

local enabled = true
local destroyed = false

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

-- Cooldown so the combat loop can't stack presses on top of each other.
local lastPress = 0

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

-- Fire a single left-mouse click at the current cursor position.
local function clickMouse()
	local pos = UserInputService:GetMouseLocation()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
	end)
	task.wait()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
	end)
end

-- Black flash is a click, then another click BLACK_FLASH_GAP seconds later.
local function tryBlackFlash()
	if os.clock() - lastPress < CONFIG.PRESS_COOLDOWN then return false end
	lastPress = os.clock()
	clickMouse()
	task.wait(CONFIG.BLACK_FLASH_GAP)
	clickMouse()
	lastPress = os.clock()
	return true
end

------------------------------------------------------------------------
-- Auto-combat (positional): detect nearest player, get behind, hit, dash
------------------------------------------------------------------------
local function getMyRoot()
	local char = player.Character
	if not char then return nil, nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil, nil end
	return hrp, hum
end

-- Returns the nearest alive enemy's root part and the distance to it.
local function getNearestTarget(myRoot)
	local nearestRoot, nearestDist
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local char = other.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local dist = (hrp.Position - myRoot.Position).Magnitude
				if dist <= CONFIG.DETECT_RANGE and (not nearestDist or dist < nearestDist) then
					nearestRoot, nearestDist = hrp, dist
				end
			end
		end
	end
	return nearestRoot, nearestDist
end

-- Flatten to the XZ plane and return whether we are behind the target.
local function isBehind(myRoot, targetRoot)
	local toMe = myRoot.Position - targetRoot.Position
	toMe = Vector3.new(toMe.X, 0, toMe.Z)
	if toMe.Magnitude == 0 then return false end
	local look = targetRoot.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude == 0 then return false end
	return look.Unit:Dot(toMe.Unit) <= CONFIG.BEHIND_DOT
end

-- Alternate the strafe direction each dash so we weave side to side.
local dashLeft = false
local function sideDash()
	dashLeft = not dashLeft
	local strafe = dashLeft and Enum.KeyCode.A or Enum.KeyCode.D
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, strafe, false, game)
	end)
	pressKey(CONFIG.DASH_KEY) -- tap dash while holding the strafe direction
	task.wait(CONFIG.DASH_HOLD)
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, strafe, false, game)
	end)
end

task.spawn(function()
	while not destroyed do
		if enabled and CONFIG.USE_AUTO_COMBAT then
			local myRoot = getMyRoot()
			if myRoot then
				local targetRoot, dist = getNearestTarget(myRoot)
				if targetRoot and dist <= CONFIG.ATTACK_RANGE then
					if isBehind(myRoot, targetRoot) then
						-- Behind them: hit, then reposition and go again.
						if tryBlackFlash() then
							task.wait(CONFIG.HIT_TO_DASH_DELAY)
							sideDash()
						end
					else
						-- Not behind yet: side-dash to try to flank them.
						sideDash()
					end
				end
			end
		end
		task.wait(CONFIG.LOOP_INTERVAL)
	end
end)

------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------
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
	destroyed = true
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
