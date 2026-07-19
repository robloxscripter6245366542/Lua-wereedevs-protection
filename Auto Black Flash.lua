--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!

	Auto Black Flash
	- Auto-combat: locks the nearest valid enemy, walks to a spot behind them
	  (leading their movement), and black-flashes the instant it's behind and
	  in range.
	- Movement is driven by Humanoid:Move with the default controls disabled,
	  so it's smooth and doesn't depend on the Roblox window being focused.
	- AI combos (optional): asks Pollinations AI for a keyboard combo each tick
	  and plays it on top. Off by default (a web call is too slow for real-time).

	Game binds differ, so edit the CONFIG block below to match your game.
]]
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Executor HTTP request function (name varies between executors). Used only
-- by the optional AI combo layer; nil on unsupported executors.
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

	-- Key that walks forward (used by the AI WALK macro only).
	WALK_KEY = Enum.KeyCode.W,

	-- Press this to toggle the bot on/off in-game.
	TOGGLE_KEY = Enum.KeyCode.RightControl,

	-- Targeting.
	DETECT_RANGE = 60,        -- how far to look for an enemy (studs)
	ATTACK_RANGE = 14,        -- how close before we try to hit
	IGNORE_TEAMMATES = true,  -- don't target players on your own team
	IGNORE_FORCEFIELD = true, -- don't target spawn-protected players

	-- "Behind" cutoff: dot of the target's look vector and the direction to
	-- you. -1 = directly behind, 0 = at their side. Lower = stricter.
	BEHIND_DOT = -0.25,

	-- Movement.
	PREDICT_TIME = 0.12,      -- lead the target's velocity by this many seconds
	BEHIND_OFFSET = 7,        -- how far behind the enemy to stand (studs)

	-- Timing.
	BLACK_FLASH_GAP = 0.33,   -- gap between the first and second key press
	DASH_HOLD = 0.12,         -- how long the strafe key is held during a dash
	WALK_HOLD = 0.35,         -- how long the AI WALK macro holds forward
	PRESS_COOLDOWN = 0.25,    -- min time between black-flash attempts
	FLANK_DASH_COOLDOWN = 0.45, -- min time between chase dashes

	-- Master switch for the positional auto-combat loop.
	USE_AUTO_COMBAT = true,

	-- Pollinations AI combo layer. Optional high-level planner that runs in
	-- parallel; it can NEVER slow the fast local loop. Off by default.
	USE_AI_MOVEMENT = false,
	AI_MODEL = "gpt-5.6-sol", -- model name (see https://text.pollinations.ai/models)
	AI_ENDPOINT = "https://text.pollinations.ai/openai",
	AI_INTERVAL = 1.0,        -- seconds between AI decisions (>= ~0.8; it's a web call)
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
	("Loaded!\nToggle: button or [%s]\nDrag by title • X to close"):format(CONFIG.TOGGLE_KEY.Name),
	6
)

------------------------------------------------------------------------
-- Low-level input
------------------------------------------------------------------------
local lastPress = 0

local function pressKey(keyCode)
	-- Release inside pcall too, so a mid-press error can't leave a key stuck.
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
	end)
	task.wait()
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
end

local function holdKey(keyCode, duration)
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
	end)
	task.wait(duration)
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
end

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

local dashLeft = false
local function sideDash()
	dashLeft = not dashLeft
	local strafe = dashLeft and Enum.KeyCode.A or Enum.KeyCode.D
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, strafe, false, game)
	end)
	pressKey(CONFIG.DASH_KEY)
	task.wait(CONFIG.DASH_HOLD)
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, strafe, false, game)
	end)
end

------------------------------------------------------------------------
-- Default-controls management
------------------------------------------------------------------------
-- Humanoid:Move fights the default control script (which zeroes movement each
-- frame). Disabling the controls while the bot drives makes movement smooth;
-- we always hand control back when idle, disabled, or closed.
local controlsModule
local function getControls()
	if controlsModule then return controlsModule end
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		controlsModule = pm:GetControls()
	end)
	return controlsModule
end

local controlsDisabled = false
local function setControls(disable)
	local controls = getControls()
	if not controls then return end
	if disable and not controlsDisabled then
		controlsDisabled = true
		pcall(function() controls:Disable() end)
	elseif not disable and controlsDisabled then
		controlsDisabled = false
		pcall(function() controls:Enable() end)
	end
end

-- A fresh character spawns with controls enabled again; forget our stale flag
-- so the next drive re-disables them.
player.CharacterAdded:Connect(function()
	controlsDisabled = false
end)

------------------------------------------------------------------------
-- Targeting / geometry
------------------------------------------------------------------------
local function getMyRoot()
	local char = player.Character
	if not char then return nil, nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil, nil end
	return hrp, hum
end

local function isValidEnemy(other)
	if other == player then return false end
	if CONFIG.IGNORE_TEAMMATES and player.Team and other.Team == player.Team then
		return false
	end
	local char = other.Character
	if not char then return nil end
	if CONFIG.IGNORE_FORCEFIELD and char:FindFirstChildOfClass("ForceField") then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return false end
	return true, hrp, hum
end

-- Returns nearest enemy's root part, distance, humanoid, and player.
local function getNearestTarget(myRoot)
	local bestRoot, bestDist, bestHum, bestPlayer
	for _, other in ipairs(Players:GetPlayers()) do
		local ok, hrp, hum = isValidEnemy(other)
		if ok then
			local dist = (hrp.Position - myRoot.Position).Magnitude
			if dist <= CONFIG.DETECT_RANGE and (not bestDist or dist < bestDist) then
				bestRoot, bestDist, bestHum, bestPlayer = hrp, dist, hum, other
			end
		end
	end
	return bestRoot, bestDist, bestHum, bestPlayer
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

local function getVelocity(part)
	local ok, vel = pcall(function()
		return part.AssemblyLinearVelocity
	end)
	if ok and vel then return vel end
	return part.Velocity
end

local function stopMovingHumanoid(hum)
	pcall(function()
		hum:Move(Vector3.new(0, 0, 0), false)
	end)
end

------------------------------------------------------------------------
-- Fast local combat/movement loop (Heartbeat: every frame, network-free)
------------------------------------------------------------------------
local lastFlankDash = 0
local combatConnection
combatConnection = RunService.Heartbeat:Connect(function()
	if destroyed then return end

	if not (enabled and CONFIG.USE_AUTO_COMBAT) then
		setControls(false) -- give control back to the player
		return
	end

	local myRoot, myHum = getMyRoot()
	local targetRoot, dist
	if myRoot then
		targetRoot, dist = getNearestTarget(myRoot)
	end

	if not (myRoot and myHum and targetRoot) then
		setControls(false) -- no target: let the player move freely
		return
	end

	-- We have a target: take over movement.
	setControls(true)

	-- Lead the enemy's motion, then aim for a point behind their facing.
	local predicted = targetRoot.Position + getVelocity(targetRoot) * CONFIG.PREDICT_TIME
	local behindOffset = targetRoot.CFrame.LookVector * CONFIG.BEHIND_OFFSET
	local goalPos = predicted - behindOffset
	local toGoal = goalPos - myRoot.Position
	toGoal = Vector3.new(toGoal.X, 0, toGoal.Z)

	if toGoal.Magnitude > 2 then
		pcall(function()
			myHum:Move(toGoal.Unit, false)
		end)
	else
		stopMovingHumanoid(myHum)
	end

	-- Attack when behind and close. Guard on the cooldown BEFORE spawning so we
	-- don't spawn a throwaway thread every frame.
	if isBehind(myRoot, targetRoot) and dist <= CONFIG.ATTACK_RANGE then
		if os.clock() - lastPress >= CONFIG.PRESS_COOLDOWN then
			task.spawn(tryBlackFlash)
		end
	elseif dist > CONFIG.ATTACK_RANGE and os.clock() - lastFlankDash >= CONFIG.FLANK_DASH_COOLDOWN then
		-- Dash to close the gap faster while chasing.
		lastFlankDash = os.clock()
		task.spawn(function()
			pressKey(CONFIG.DASH_KEY)
		end)
	end
end)

------------------------------------------------------------------------
-- Optional AI combo layer (Pollinations)
------------------------------------------------------------------------
-- Token -> KeyCode covering the WHOLE keyboard, built from every Enum.KeyCode
-- (addressed by its name uppercased), plus friendly aliases.
local KEY_MAP = {}
for _, kc in ipairs(Enum.KeyCode:GetEnumItems()) do
	KEY_MAP[string.upper(kc.Name)] = kc
end
local KEY_ALIASES = {
	["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
	["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
	["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine,
	["0"] = Enum.KeyCode.Zero,
	SHIFT = Enum.KeyCode.LeftShift, CTRL = Enum.KeyCode.LeftControl,
	ALT = Enum.KeyCode.LeftAlt, ENTER = Enum.KeyCode.Return, ESC = Enum.KeyCode.Escape,
}
for token, kc in pairs(KEY_ALIASES) do
	KEY_MAP[token] = kc
end

local VALID_TOKENS = { M1 = true, M2 = true, DASH = true, BF = true, WALK = true, WAIT = true }
for token in pairs(KEY_MAP) do
	VALID_TOKENS[token] = true
end

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

local function r1(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function buildState()
	local myRoot, myHum = getMyRoot()
	if not myRoot then return nil end
	local targetRoot, dist, targetHum = getNearestTarget(myRoot)
	if not targetRoot then
		return { hasTarget = false }
	end

	local toTarget = targetRoot.Position - myRoot.Position
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local dir = toTarget.Magnitude > 0 and toTarget.Unit or Vector3.new(0, 0, 1)

	local myLook = myRoot.CFrame.LookVector
	myLook = Vector3.new(myLook.X, 0, myLook.Z)
	myLook = myLook.Magnitude > 0 and myLook.Unit or Vector3.new(0, 0, 1)
	local facingDot = myLook:Dot(dir)
	local sideDot = myLook:Cross(dir).Y
	local bearing
	if facingDot > 0.5 then
		bearing = "front"
	elseif facingDot < -0.5 then
		bearing = "behind_me"
	else
		bearing = sideDot >= 0 and "right" or "left"
	end

	local enemyVel = getVelocity(targetRoot)
	local enemyVelFlat = Vector3.new(enemyVel.X, 0, enemyVel.Z)
	local enemySpeed = enemyVelFlat.Magnitude
	local approach = -enemyVelFlat:Dot(dir)
	local enemyMotion
	if enemySpeed < 2 then
		enemyMotion = "still"
	elseif approach > 1 then
		enemyMotion = "closing"
	elseif approach < -1 then
		enemyMotion = "retreating"
	else
		enemyMotion = "strafing"
	end

	return {
		hasTarget = true,
		distance = math.floor(dist),
		behind = isBehind(myRoot, targetRoot),
		bearing = bearing,
		enemyMotion = enemyMotion,
		enemySpeed = r1(enemySpeed),
		mySpeed = r1(getVelocity(myRoot).Magnitude),
		myHealth = myHum and math.floor(myHum.Health) or 0,
		enemyHealth = targetHum and math.floor(targetHum.Health) or 0,
	}
end

local function askAI(state)
	if not httpRequest then return nil end

	local prompt = string.format(
		"You control a Roblox anime fighting-game character through VirtualInputManager. "
			.. "Output a combo as a space-separated sequence of input tokens to run in order, "
			.. "and NOTHING else. You have the WHOLE keyboard: any letter A-Z, any number "
			.. "0-9, F1-F12, SPACE, SHIFT, CTRL, ALT, ENTER, ESC, TAB, and the arrow keys "
			.. "(UP DOWN LEFT RIGHT) all press that key. Plus macros: M1 (light attack click), "
			.. "M2 (heavy/aim click), DASH (dodge), BF (black flash), WALK (step forward), "
			.. "WAIT (small pause). Typical binds: W A S D move, SPACE jump, skills on the "
			.. "number row and letters like Q E R F. Keep it under %d tokens. "
			.. "Situation: distanceStuds=%s, behindEnemy=%s, enemyBearing=%s, enemyMotion=%s, "
			.. "enemySpeed=%s, mySpeed=%s, myHealth=%s, enemyHealth=%s. "
			.. "Chase when they retreat, DASH when they close fast, get behind them, combo into BF.",
		CONFIG.MAX_COMBO_INPUTS,
		tostring(state.distance),
		tostring(state.behind),
		tostring(state.bearing),
		tostring(state.enemyMotion),
		tostring(state.enemySpeed),
		tostring(state.mySpeed),
		tostring(state.myHealth),
		tostring(state.enemyHealth)
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

	local content
	local decoded
	pcall(function() decoded = HttpService:JSONDecode(res.Body) end)
	if decoded and decoded.choices and decoded.choices[1] and decoded.choices[1].message then
		content = decoded.choices[1].message.content
	end
	content = string.upper(content or res.Body or "")

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

local function executeCombo(combo)
	for _, token in ipairs(combo) do
		if destroyed or not enabled then break end
		pressToken(token)
		task.wait(CONFIG.COMBO_STEP)
	end
end

local function aiActive()
	return CONFIG.USE_AI_MOVEMENT and httpRequest ~= nil
end

if CONFIG.USE_AI_MOVEMENT and not httpRequest then
	notify(
		"Auto Black Flash",
		"AI combos need an executor with HTTP support.\nFast local combat still runs.",
		5
	)
end

task.spawn(function()
	while not destroyed do
		if enabled and aiActive() then
			local state = buildState()
			if state and state.hasTarget then
				local combo = askAI(state)
				if combo then
					executeCombo(combo)
				end
			end
		end
		task.wait(CONFIG.AI_INTERVAL)
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
frame.Size = UDim2.new(0, 240, 0, 126)
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
title.Size = UDim2.new(1, -35, 0, 32)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "AUTO BLACK FLASH"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = frame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0.88, 0, 0, 40)
toggleButton.Position = UDim2.new(0.06, 0, 0, 44)
toggleButton.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
toggleButton.Text = "ENABLED"
toggleButton.TextColor3 = Color3.fromRGB(0, 0, 0)
toggleButton.TextScaled = true
toggleButton.Font = Enum.Font.GothamBold
toggleButton.Parent = frame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 10)
btnCorner.Parent = toggleButton

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0.88, 0, 0, 26)
status.Position = UDim2.new(0.06, 0, 0, 90)
status.BackgroundTransparency = 1
status.Text = "idle"
status.TextColor3 = Color3.fromRGB(180, 180, 180)
status.TextScaled = true
status.Font = Enum.Font.Gotham
status.TextXAlignment = Enum.TextXAlignment.Center
status.Parent = frame

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

local function setEnabled(value)
	enabled = value
	updateButton()
	notify("Auto Black Flash", enabled and "ENABLED ✅" or "DISABLED ❌", 2)
end

toggleButton.MouseButton1Click:Connect(function()
	setEnabled(not enabled)
end)

updateButton()

-- Live status readout (throttled; the Heartbeat loop stays lean).
task.spawn(function()
	while not destroyed do
		if not enabled then
			status.Text = "disabled"
		else
			local myRoot = getMyRoot()
			local _, dist, _, targetPlayer = myRoot and getNearestTarget(myRoot)
			if targetPlayer then
				status.Text = ("%s • %dst%s"):format(
					targetPlayer.Name,
					math.floor(dist),
					aiActive() and " • AI" or ""
				)
			else
				status.Text = "searching…"
			end
		end
		task.wait(0.2)
	end
end)

------------------------------------------------------------------------
-- Toggle keybind + dragging
------------------------------------------------------------------------
local keybindConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == CONFIG.TOGGLE_KEY then
		setEnabled(not enabled)
	end
end)

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
	if combatConnection then
		combatConnection:Disconnect()
		combatConnection = nil
	end
	setControls(false) -- IMPORTANT: give the player their controls back
	if keybindConn then keybindConn:Disconnect() end
	if inputChangedConn then inputChangedConn:Disconnect() end
	if inputEndedConn then inputEndedConn:Disconnect() end
	screenGui:Destroy()
end)
--son im crine who even struggle to blackflash
