-- Stealing (Steal a Brainrot style): grab an egg/pet from another base, carry it home.
-- Getting bonked or dying while carrying sends it back to the owner.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Steal = {}
local S
local carrying: { [Player]: { Item: any, Victim: Player, Model: Model?, Died: RBXScriptConnection? } } = {}

local RED = Color3.fromRGB(255, 80, 80)

local function setSpeed(player: Player, speed: number)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

local function clearCarry(thief: Player)
	local entry = carrying[thief]
	if not entry then
		return nil
	end
	carrying[thief] = nil
	if entry.Model then
		entry.Model:Destroy()
	end
	if entry.Died then
		entry.Died:Disconnect()
	end
	thief:SetAttribute("Carrying", nil)
	setSpeed(thief, Config.NormalWalkSpeed)
	return entry
end

local function giveBack(victim: Player, item)
	if not S.Data.Get(victim) then
		return
	end
	if not S.Pedestals.PlaceItem(victim, item) then
		-- No room: refund its value so nothing is ever lost.
		S.Data.AddCash(victim, S.Pedestals.ItemValue(item))
	end
end

function Steal.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function Steal.TrySteal(thief: Player, victim: Player, index: number)
	if carrying[thief] then
		S.Notify(thief, "You're already carrying something!", RED)
		return
	end
	local thiefPlot = S.Plots.Get(thief)
	local victimPlot = S.Plots.Get(victim)
	if not thiefPlot or not victimPlot then
		return
	end
	if S.Plots.IsLocked(victimPlot) then
		S.Notify(thief, "🔒 That base is locked!", RED)
		return
	end
	if not S.Pedestals.FreeSlot(thief) then
		S.Notify(thief, "❌ Your base is full — no room for stolen loot!", RED)
		return
	end
	local character = thief.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	local item = S.Pedestals.TakeItem(victim, index)
	if not item then
		return
	end

	local model = S.Visuals.MakeItem(item)
	if model then
		local modelRoot = model.PrimaryPart :: BasePart
		modelRoot.Anchored = false
		modelRoot.Massless = true
		model:PivotTo(root.CFrame * CFrame.new(0, 3, 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = modelRoot
		weld.Parent = modelRoot
		model.Parent = character
	end

	local entry = { Item = item, Victim = victim, Model = model, Died = nil :: RBXScriptConnection? }
	entry.Died = humanoid.Died:Connect(function()
		Steal.Drop(thief, "died")
	end)
	carrying[thief] = entry
	thief:SetAttribute("Carrying", S.Pedestals.ItemName(item))
	setSpeed(thief, Config.CarryWalkSpeed)

	local name = S.Pedestals.ItemName(item)
	S.Notify(thief, "🏃 You grabbed " .. name .. "! Run back to your base!", Color3.fromRGB(255, 220, 90))
	S.Notify(victim, "🚨 " .. thief.DisplayName .. " is stealing your " .. name .. "! Bonk them!", RED)
end

-- Item goes back to its owner.
function Steal.Drop(thief: Player, reason: string)
	local entry = clearCarry(thief)
	if not entry then
		return
	end
	local name = S.Pedestals.ItemName(entry.Item)
	giveBack(entry.Victim, entry.Item)
	if reason == "bonked" then
		S.Notify(thief, "💥 You got bonked and dropped " .. name .. "!", RED)
		S.Notify(entry.Victim, "🛡️ " .. name .. " was recovered!", Color3.fromRGB(120, 255, 120))
	elseif reason == "died" then
		S.Notify(entry.Victim, "🛡️ " .. name .. " was recovered!", Color3.fromRGB(120, 255, 120))
	end
end

local function deliver(thief: Player)
	local entry = clearCarry(thief)
	if not entry then
		return
	end
	local name = S.Pedestals.ItemName(entry.Item)
	if S.Pedestals.PlaceItem(thief, entry.Item) then
		local data = S.Data.Get(thief)
		if data then
			data.TotalSteals = (data.TotalSteals or 0) + 1
		end
		S.Notify(thief, "😈 Stolen! " .. name .. " is yours now!", Color3.fromRGB(120, 255, 120))
		S.Notify(entry.Victim, "😭 " .. thief.DisplayName .. " stole your " .. name .. "! Steal it back!", RED)
		S.Effect(thief, "Steal", 0)
	else
		giveBack(entry.Victim, entry.Item)
	end
end

function Steal.OnPlayerRemoving(player: Player)
	if carrying[player] then
		Steal.Drop(player, "left")
	end
	for thief, entry in carrying do
		if entry.Victim == player then
			clearCarry(thief)
			giveBack(player, entry.Item)
			S.Notify(thief, "The owner left — the loot went back to them.", RED)
		end
	end
end

function Steal.Start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0
		for thief in carrying do
			local plot = S.Plots.Get(thief)
			local root = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
			if plot and root and S.Plots.IsInside(plot, root.Position) then
				deliver(thief)
			end
		end
	end)
end

function Steal.Init(services)
	S = services
end

return Steal
