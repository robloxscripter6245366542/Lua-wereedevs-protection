--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!

	Auto Black Flash
	- Auto-combat: finds the nearest player, gets behind them, presses the
	  black-flash key, then side-dashes and repeats.
	- AI movement (optional): asks Pollinations AI (Claude model) what to do
	  each tick and walks/strafes/dashes/attacks based on the reply. Falls
	  back to the rule-based auto-combat if the executor can't make HTTP
	  requests or the AI call fails.

	Game binds differ, so edit the CONFIG block below to match your game.
]]
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- Executor HTTP request function (name varies between executors). Used only
-- by the optional AI movement controller; nil on unsupported executors.
local httpRequest = (syn and syn.request)
	or (http and http.request)
	or (fluxus and fluxus.request)
	or http_request
	or request

------------------------------------------------------------------------
-- CONFIG  (edit these to match your game)
------------------------------------------------------------------------
local CONFIG = {
	-- Key that performs the black flash / attack.
	BLACK_FLASH_KEY = Enum.KeyCode.Three,

	-- Key that performs a dash/dodge in your game (Q is a common default).
	DASH_KEY = Enum.KeyCode.Q,

	-- Key that walks forward.
	WALK_KEY = Enum.KeyCode.W,

	-- How close (in studs) a player must be before auto-combat engages.
	DETECT_RANGE = 40,

	-- How close you must be to actually land the hit.
	ATTACK_RANGE = 14,

	-- "Behind" cutoff: dot of the target's look vector and the direction to
	-- you. -1 = directly behind, 0 = at their side. Lower = stricter.
	BEHIND_DOT = -0.25,

	-- Timing.
	BLACK_FLASH_GAP = 0.33,   -- gap between the first and second key press
	HIT_TO_DASH_DELAY = 0.15, -- wait after the black flash before dashing
	DASH_HOLD = 0.12,         -- how long the strafe key is held during a dash
	WALK_HOLD = 0.35,         -- how long a walk/strafe step is held
	LOOP_INTERVAL = 0.1,      -- delay between combat-loop iterations
	PRESS_COOLDOWN = 0.25,    -- min time between black-flash attempts

	-- Master switch for the positional auto-combat loop.
	USE_AUTO_COMBAT = true,

	-- Pollinations AI movement controller.
	USE_AI_MOVEMENT = true,   -- let the AI decide inputs each tick
	AI_MODEL = "gpt-5.6-sol",  -- model name (see https://text.pollinations.ai/models)
	AI_ENDPOINT = "https://text.pollinations.ai/openai",
	AI_INTERVAL = 1.0,        -- seconds between AI decisions (keep >= ~0.8; it's a web call)
	COMBO_STEP = 0.08,        -- delay between inputs within an AI combo
	MAX_COMBO_INPUTS = 12,    -- safety cap on how many inputs one combo can fire
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

-- Black flash: press the key, then press it again BLACK_FLASH_GAP seconds later.
local function tryBlackFlash()
	if os.clock() - lastPress < CONFIG.PRESS_COOLDOWN then return false end
	lastPress = os.clock()
	pressKey(CONFIG.BLACK_FLASH_KEY)
	task.wait(CONFIG.BLACK_FLASH_GAP)
	pressKey(CONFIG.BLACK_FLASH_KEY)
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

-- Hold a key down for a fixed duration (used for walk/strafe steps).
local function holdKey(keyCode, duration)
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
	end)
	task.wait(duration)
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
end

-- Fire a single mouse-button click at the current cursor position.
-- button: 0 = left (M1), 1 = right (M2).
local function clickMouse(button)
	local pos = UserInputService:GetMouseLocation()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, button, true, game, 0)
	end)
	task.wait()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, button, false, game, 0)
	end)
end

------------------------------------------------------------------------
-- AI combo controller (Pollinations AI, Claude model)
------------------------------------------------------------------------
-- The AI drives raw inputs through VirtualInputManager. Each tick it returns
-- a short sequence of input tokens (a combo) which we execute in order.

-- Token -> KeyCode. Digits need naming because Enum.KeyCode["1"] doesn't exist.
local KEY_MAP = {
	W = Enum.KeyCode.W, A = Enum.KeyCode.A, S = Enum.KeyCode.S, D = Enum.KeyCode.D,
	Q = Enum.KeyCode.Q, E = Enum.KeyCode.E, R = Enum.KeyCode.R, F = Enum.KeyCode.F,
	T = Enum.KeyCode.T, G = Enum.KeyCode.G, C = Enum.KeyCode.C, V = Enum.KeyCode.V,
	Z = Enum.KeyCode.Z, X = Enum.KeyCode.X, B = Enum.KeyCode.B, Y = Enum.KeyCode.Y,
	SPACE = Enum.KeyCode.Space, SHIFT = Enum.KeyCode.LeftShift, CTRL = Enum.KeyCode.LeftControl,
	["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
	["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
	["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine,
	["0"] = Enum.KeyCode.Zero,
}

-- Every token the AI is allowed to use (keys above plus a few macros).
local VALID_TOKENS = { M1 = true, M2 = true, DASH = true, BF = true, WALK = true, WAIT = true }
for token in pairs(KEY_MAP) do
	VALID_TOKENS[token] = true
end

-- Perform a single token through VirtualInputManager.
local function pressToken(token)
	if token == "M1" then
		clickMouse(0)
	elseif token == "M2" then
		clickMouse(1)
	elseif token == "DASH" then
		sideDash()
	elseif token == "BF" then
		tryBlackFlash()
	elseif token == "WALK" then
		holdKey(CONFIG.WALK_KEY, CONFIG.WALK_HOLD)
	elseif token == "WAIT" then
		task.wait(CONFIG.COMBO_STEP)
	elseif KEY_MAP[token] then
		pressKey(KEY_MAP[token])
	end
end

-- Build a compact snapshot of the situation for the prompt.
local function buildState()
	local myRoot = getMyRoot()
	if not myRoot then return nil end
	local targetRoot, dist = getNearestTarget(myRoot)
	if not targetRoot then
		return { hasTarget = false }
	end
	return {
		hasTarget = true,
		distance = math.floor(dist),
		behind = isBehind(myRoot, targetRoot),
	}
end

-- Ask Pollinations for a combo. Returns an ordered list of valid tokens.
local function askAI(state)
	if not httpRequest then return nil end

	local prompt = string.format(
		"You control a Roblox anime fighting-game character through VirtualInputManager. "
			.. "Output a combo as a space-separated sequence of input tokens to run in order, "
			.. "and NOTHING else. Valid tokens: W A S D (move), SPACE (jump), SHIFT (run), "
			.. "Q E R F T G C V Z X B Y (skills/moves), 1 2 3 4 5 6 7 8 9 0 (skill slots), "
			.. "M1 (light attack click), M2 (heavy/aim click), DASH (dodge), BF (black flash), "
			.. "WAIT (small pause). Keep it under %d tokens. Chain moves into a real combo. "
			.. "Situation: hasTarget=%s, distanceStuds=%s, behindEnemy=%s. "
			.. "Goal: close in, get behind the enemy, then combo into BF.",
		CONFIG.MAX_COMBO_INPUTS,
		tostring(state.hasTarget),
		tostring(state.distance),
		tostring(state.behind)
	)

	local ok, body = pcall(function()
		return HttpService:JSONEncode({
			model = CONFIG.AI_MODEL,
			messages = { { role = "user", content = prompt } },
			seed = math.random(1, 1000000),
		})
	end)
	if not ok then return nil end

	local reqOk, res = pcall(function()
		return httpRequest({
			Url = CONFIG.AI_ENDPOINT,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
	if not reqOk or type(res) ~= "table" or not res.Body then return nil end

	-- Response may be OpenAI-style JSON or plain text; handle both.
	local content
	local decoded
	pcall(function() decoded = HttpService:JSONDecode(res.Body) end)
	if decoded and decoded.choices and decoded.choices[1] and decoded.choices[1].message then
		content = decoded.choices[1].message.content
	end
	content = string.upper(content or res.Body or "")

	-- Pull out valid tokens in order, ignoring any extra prose the model adds.
	local combo = {}
	for word in string.gmatch(content, "[%w]+") do
		if VALID_TOKENS[word] then
			combo[#combo + 1] = word
			if #combo >= CONFIG.MAX_COMBO_INPUTS then break end
		end
	end
	if #combo == 0 then return nil end
	return combo
end

-- Execute a combo token by token, bailing out if we get disabled mid-combo.
local function executeCombo(combo)
	for _, token in ipairs(combo) do
		if destroyed or not enabled then break end
		pressToken(token)
		task.wait(CONFIG.COMBO_STEP)
	end
end

-- Whether the AI controller is actually driving (needs HTTP support).
local function aiActive()
	return CONFIG.USE_AI_MOVEMENT and httpRequest ~= nil
end

if CONFIG.USE_AI_MOVEMENT and not httpRequest then
	notify(
		"Auto Black Flash",
		"AI movement needs an executor with HTTP support.\nUsing rule-based combat instead.",
		5
	)
end

task.spawn(function()
	while not destroyed do
		if enabled and aiActive() then
			local state = buildState()
			if state then
				local combo = askAI(state)
				if combo then
					executeCombo(combo)
				end
			end
		end
		task.wait(CONFIG.AI_INTERVAL)
	end
end)

task.spawn(function()
	while not destroyed do
		-- Rule-based combat runs when the AI controller isn't driving (either
		-- disabled or unsupported on this executor).
		if enabled and CONFIG.USE_AUTO_COMBAT and not aiActive() then
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
