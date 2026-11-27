-- Server-wide events (Lucky Hour / Golden Rush / Cash Frenzy). Also triggered by the Server Luck product.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Events = {}
local S

local function now()
	return workspace:GetServerTimeNow()
end

function Events.Init(services)
	S = services
	ReplicatedStorage:SetAttribute("EventName", "")
	ReplicatedStorage:SetAttribute("EventEnds", 0)
	ReplicatedStorage:SetAttribute("EventBy", "")
end

function Events.IsActive(name: string): boolean
	return ReplicatedStorage:GetAttribute("EventName") == name and (ReplicatedStorage:GetAttribute("EventEnds") or 0) > now()
end

function Events.AnyActive(): boolean
	return (ReplicatedStorage:GetAttribute("EventEnds") or 0) > now()
end

function Events.Begin(name: string, duration: number, by: string?)
	local info = Config.Events[name]
	if not info then
		return
	end
	local ends = now() + duration
	if Events.IsActive(name) then
		ends = ReplicatedStorage:GetAttribute("EventEnds") + duration -- stack purchases
	end
	ReplicatedStorage:SetAttribute("EventName", name)
	ReplicatedStorage:SetAttribute("EventEnds", ends)
	ReplicatedStorage:SetAttribute("EventBy", by or "")
	local suffix = if by then " (thanks " .. by .. "!)" else ""
	S.Announce("⚡ " .. info.Title .. "! " .. info.Text .. suffix, info.Color)
end

function Events.Start()
	task.spawn(function()
		local names = {}
		for name in Config.Events do
			table.insert(names, name)
		end
		table.sort(names)
		while true do
			task.wait(Config.EventInterval)
			if not Events.AnyActive() then
				Events.Begin(names[math.random(#names)], Config.EventDuration)
			end
		end
	end)
end

return Events
