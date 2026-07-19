--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!

	Game Scanner  (companion to Auto Black Flash)
	Discovers what the script needs to hook a game and saves it:
	  - every RemoteEvent / RemoteFunction (name + full path) = ability "hooks"
	  - keybinds you actually press, learned live as you play
	  - a static pass over scripts for Enum.KeyCode (only if the executor can
	    decompile)

	It SAVES the dump three ways:
	  1. a local JSON file (writefile), if the executor supports files
	  2. your clipboard (setclipboard)
	  3. optionally commits it to your GitHub repo — but ONLY if you have a
	     personal-access-token in a LOCAL file. No token is ever stored in this
	     script, so it is safe to share the loadstring publicly.

	Keybind detection is best-effort: games bind inputs in many different ways,
	so the live logger (press your abilities once each) is the reliable source.
]]

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
	-- Where the local dump is written (needs an executor with writefile).
	OUTPUT_FILE = "abf_game_scan.json",

	-- Optional GitHub commit. The token is read from TOKEN_FILE on YOUR disk;
	-- it is never embedded here. Leave COMMIT_TO_GITHUB false to only save
	-- locally + clipboard.
	COMMIT_TO_GITHUB = true,
	TOKEN_FILE = "abf_github_token.txt", -- a local file containing ONLY your PAT
	GITHUB_OWNER = "robloxscripter6245366542",
	GITHUB_REPO = "lua-wereedevs-protection",
	GITHUB_BRANCH = "main",
	GITHUB_PATH = "scans/game_scan.json", -- path in the repo to write to

	-- How long the live keybind logger runs (seconds). Press each ability once.
	LOG_SECONDS = 60,
}
------------------------------------------------------------------------

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- Feature-detect executor capabilities (all optional).
local httpRequest = (syn and syn.request)
	or (http and http.request)
	or (fluxus and fluxus.request)
	or http_request
	or request
local canWrite = type(writefile) == "function"
local canRead = type(readfile) == "function" and type(isfile) == "function"
local canClip = type(setclipboard) == "function"
local canDecompile = type(decompile) == "function"

local function notify(text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Game Scanner",
			Text = text,
			Duration = duration or 5,
		})
	end)
end

------------------------------------------------------------------------
-- Pure-Lua base64 (for the GitHub contents API; no executor crypto needed)
------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64Encode(data)
	return ((data:gsub(".", function(x)
		local r, b = "", x:byte()
		for i = 8, 1, -1 do
			r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
		end
		return r
	end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
		if #x < 6 then return "" end
		local c = 0
		for i = 1, 6 do
			c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
		end
		return B64:sub(c + 1, c + 1)
	end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

------------------------------------------------------------------------
-- Scans
------------------------------------------------------------------------
-- Every RemoteEvent / RemoteFunction: the candidate "hooks" for game actions.
local function scanRemotes()
	local remotes = {}
	local ok = pcall(function()
		for _, obj in ipairs(game:GetDescendants()) do
			if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
				remotes[#remotes + 1] = {
					name = obj.Name,
					class = obj.ClassName,
					path = obj:GetFullName(),
				}
			end
		end
	end)
	return remotes, ok
end

-- Static keycode references found by decompiling LocalScripts/ModuleScripts.
-- Only runs if the executor exposes decompile(); otherwise returns empty.
local function scanKeycodesStatic()
	local found = {}
	if not canDecompile then return found end
	local seenKey = {}
	pcall(function()
		local containers = { player:FindFirstChild("PlayerScripts"), game:GetService("ReplicatedStorage") }
		for _, container in ipairs(containers) do
			if container then
				for _, obj in ipairs(container:GetDescendants()) do
					if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
						local ok, src = pcall(decompile, obj)
						if ok and type(src) == "string" then
							for key in src:gmatch("Enum%.KeyCode%.(%w+)") do
								local tag = obj:GetFullName() .. " -> " .. key
								if not seenKey[tag] then
									seenKey[tag] = true
									found[#found + 1] = { script = obj:GetFullName(), key = key }
								end
							end
						end
					end
				end
			end
		end
	end)
	return found
end

-- Live keybind logger: records the keys you actually press while playing, and
-- whether the game consumed the input (gameProcessed = a real bind fired).
local function logKeybindsLive(seconds, onDone)
	local presses = {}
	local order = {}
	local conn
	conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.Unknown then return end
		local name = input.KeyCode.Name
		if not presses[name] then
			presses[name] = { key = name, count = 0, gameUsed = false }
			order[#order + 1] = presses[name]
		end
		presses[name].count = presses[name].count + 1
		if gameProcessed then
			presses[name].gameUsed = true
		end
	end)

	task.delay(seconds, function()
		if conn then conn:Disconnect() end
		onDone(order)
	end)
end

------------------------------------------------------------------------
-- GitHub commit (optional; token read from a LOCAL file, never embedded)
------------------------------------------------------------------------
local function readToken()
	if not (canRead and CONFIG.TOKEN_FILE) then return nil end
	local token
	pcall(function()
		if isfile(CONFIG.TOKEN_FILE) then
			token = readfile(CONFIG.TOKEN_FILE)
		end
	end)
	if token then
		token = token:gsub("%s+", "") -- strip trailing newline/spaces
		if token == "" then token = nil end
	end
	return token
end

local function githubHeaders(token)
	return {
		["Authorization"] = "token " .. token,
		["Accept"] = "application/vnd.github+json",
		["User-Agent"] = "ABF-Game-Scanner",
		["Content-Type"] = "application/json",
	}
end

local function commitToGithub(jsonText)
	if not CONFIG.COMMIT_TO_GITHUB then return false, "commit disabled" end
	if not httpRequest then return false, "no HTTP support" end
	local token = readToken()
	if not token then
		return false, "no token file (" .. tostring(CONFIG.TOKEN_FILE) .. ")"
	end

	local api = ("https://api.github.com/repos/%s/%s/contents/%s"):format(
		CONFIG.GITHUB_OWNER, CONFIG.GITHUB_REPO, CONFIG.GITHUB_PATH
	)

	-- Get the existing file's sha (required to update an existing file).
	local sha
	pcall(function()
		local res = httpRequest({
			Url = api .. "?ref=" .. CONFIG.GITHUB_BRANCH,
			Method = "GET",
			Headers = githubHeaders(token),
		})
		if res and res.Body then
			local decoded
			pcall(function() decoded = HttpService:JSONDecode(res.Body) end)
			if decoded and decoded.sha then sha = decoded.sha end
		end
	end)

	local payload = {
		message = "Game scan dump from Auto Black Flash scanner",
		content = base64Encode(jsonText),
		branch = CONFIG.GITHUB_BRANCH,
	}
	if sha then payload.sha = sha end

	local ok, res = pcall(function()
		return httpRequest({
			Url = api,
			Method = "PUT",
			Headers = githubHeaders(token),
			Body = HttpService:JSONEncode(payload),
		})
	end)
	if not ok or type(res) ~= "table" then return false, "request failed" end
	local code = res.StatusCode or res.Status or 0
	if code == 200 or code == 201 then
		return true, "committed"
	end
	return false, "github status " .. tostring(code)
end

------------------------------------------------------------------------
-- Run
------------------------------------------------------------------------
local function saveAndReport(scan)
	local jsonText = HttpService:JSONEncode(scan)

	if canWrite then
		pcall(function() writefile(CONFIG.OUTPUT_FILE, jsonText) end)
	end
	if canClip then
		pcall(function() setclipboard(jsonText) end)
	end

	local ok, msg = commitToGithub(jsonText)
	local summary = ("%d remotes • %d keys logged • %d static keys\nLocal:%s Clip:%s GitHub:%s"):format(
		#scan.remotes,
		#scan.keybindsLive,
		#scan.keycodesStatic,
		canWrite and "yes" or "no",
		canClip and "yes" or "no",
		ok and "yes" or ("no(" .. tostring(msg) .. ")")
	)
	notify(summary, 10)
	print("[Game Scanner] " .. summary)
	print("[Game Scanner] dump:\n" .. jsonText)
end

notify(("Scanning… press each ability once in the next %ds."):format(CONFIG.LOG_SECONDS), CONFIG.LOG_SECONDS)

local scan = {
	game = { placeId = game.PlaceId, name = nil },
	remotes = select(1, scanRemotes()),
	keycodesStatic = scanKeycodesStatic(),
	keybindsLive = {},
	capabilities = {
		http = httpRequest ~= nil,
		writefile = canWrite,
		clipboard = canClip,
		decompile = canDecompile,
	},
}
pcall(function() scan.game.name = game.Name end)

-- Log keybinds live, then save everything.
logKeybindsLive(CONFIG.LOG_SECONDS, function(order)
	scan.keybindsLive = order
	saveAndReport(scan)
end)
