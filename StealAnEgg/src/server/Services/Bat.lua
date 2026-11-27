-- Bonk Bat: everyone gets one. Hitting a thief makes them drop what they're carrying.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Bat = {}
local S
local template: Tool

local function buildTemplate(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bonk Bat"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -1.2, 0)
	tool.ToolTip = "Bonk thieves to get your stuff back!"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 4, 0.6)
	handle.Color = Color3.fromRGB(150, 100, 60)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	handle.Parent = tool
	local sound = Instance.new("Sound")
	sound.Name = "Bonk"
	sound.SoundId = "rbxasset://sounds/swordslash.wav"
	sound.Volume = 0.8
	sound.Parent = handle
	return tool
end

local function onActivated(tool: Tool, player: Player)
	local last = tool:GetAttribute("LastSwing") or 0
	if os.clock() - last < Config.BatCooldown then
		return
	end
	tool:SetAttribute("LastSwing", os.clock())

	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash" -- picked up by the default Animate script
	anim.Parent = tool
	game:GetService("Debris"):AddItem(anim, 0.5)
	local sound = tool.Handle:FindFirstChild("Bonk")
	if sound then
		sound:Play()
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			local otherRoot = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = other.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and humanoid and humanoid.Health > 0 then
				local offset = otherRoot.Position - root.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if offset.Magnitude <= Config.BatRange and flat.Magnitude > 0.01
					and root.CFrame.LookVector:Dot(flat.Unit) > 0.2 then
					local push = flat.Unit * Config.BatKnockback + Vector3.new(0, 35, 0)
					S.Remotes.Knockback:FireClient(other, push)
					if S.Steal.IsCarrying(other) then
						S.Steal.Drop(other, "bonked")
						S.Notify(player, "💥 BONK! You made " .. other.DisplayName .. " drop the loot!", Color3.fromRGB(120, 255, 120))
					end
				end
			end
		end
	end
end

function Bat.Init(services)
	S = services
	template = buildTemplate()
end

function Bat.Give(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild(template.Name) then
		return
	end
	local tool = template:Clone()
	tool.Activated:Connect(function()
		onActivated(tool, player)
	end)
	tool.Parent = backpack
end

return Bat
