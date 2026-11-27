-- Builds the whole map (ground, conveyor road, 8 bases) and assigns bases to players.
-- Plot local space: origin = plot centre on the ground, +Z points at the conveyor (entrance side).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Plots = {}
local S
local plots = {}
local byPlayer: { [Player]: any } = {}

local W, D = Config.Plot.Width, Config.Plot.Depth
local WALL_H = 12
local SLOT_X = { -25, -15, -5, 5, 15, 25 }
local SLOT_Z = { -16, 0 }

local function now()
	return workspace:GetServerTimeNow()
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function label(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.Size = UDim2.fromScale(1, 0.25)
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function buildWorld(mapFolder: Folder)
	part({
		Name = "Ground",
		Size = Vector3.new(460, 2, 260),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(110, 200, 90),
		Material = Enum.Material.Grass,
		Parent = mapFolder,
	})
	part({
		Name = "Road",
		Size = Vector3.new(420, 0.4, 20),
		Position = Vector3.new(0, 0.2, 0),
		Color = Color3.fromRGB(60, 60, 70),
		Parent = mapFolder,
	})
	local belt = part({
		Name = "ConveyorBelt",
		Size = Vector3.new(400, 1, 8),
		Position = Vector3.new(0, 0.9, 0),
		Color = Color3.fromRGB(35, 35, 40),
		Material = Enum.Material.DiamondPlate,
		Parent = mapFolder,
	})
	for x = -195, 195, 10 do
		part({
			Name = "Stripe",
			Size = Vector3.new(1, 0.1, 8),
			Position = Vector3.new(x, 1.45, 0),
			Color = Color3.fromRGB(255, 210, 40),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = belt,
		})
	end
	-- Shop arch at the start of the belt
	for _, z in { -6, 6 } do
		part({
			Size = Vector3.new(2, 14, 2),
			Position = Vector3.new(Config.Conveyor.StartX, 7, z),
			Color = Color3.fromRGB(255, 120, 40),
			Parent = mapFolder,
		})
	end
	local arch = part({
		Name = "EggShopSign",
		Size = Vector3.new(2, 4, 14),
		Position = Vector3.new(Config.Conveyor.StartX, 15, 0),
		Color = Color3.fromRGB(255, 120, 40),
		Parent = mapFolder,
	})
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 40
		gui.Parent = arch
		label(gui, { Text = "🥚 EGG CONVEYOR 🥚", Size = UDim2.fromScale(1, 1) })
	end

	local lighting = game:GetService("Lighting")
	lighting.ClockTime = 14
	lighting.Brightness = 2.5
	lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
end

local function buildPlot(index: number, mapFolder: Folder)
	local side = if index <= Config.Plot.Count / 2 then -1 else 1
	local column = (index - 1) % (Config.Plot.Count / 2)
	local x = -135 + column * 90
	local z = side * 52
	local cf = CFrame.new(x, 0, z) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local function at(lx, ly, lz)
		return cf * CFrame.new(lx, ly, lz)
	end

	part({
		Name = "Floor",
		Size = Vector3.new(W, 1, D),
		CFrame = at(0, 0.5, 0),
		Color = Color3.fromRGB(235, 225, 205),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	local wallColor = Color3.fromHSV((index * 0.13) % 1, 0.45, 0.95)
	part({ Name = "WallBack", Size = Vector3.new(W, WALL_H, 1), CFrame = at(0, WALL_H / 2 + 1, -D / 2), Color = wallColor, Parent = model })
	part({ Name = "WallL", Size = Vector3.new(1, WALL_H, D), CFrame = at(-W / 2, WALL_H / 2 + 1, 0), Color = wallColor, Parent = model })
	part({ Name = "WallR", Size = Vector3.new(1, WALL_H, D), CFrame = at(W / 2, WALL_H / 2 + 1, 0), Color = wallColor, Parent = model })
	local gap = 16
	local segment = (W - gap) / 2
	for _, s in { -1, 1 } do
		part({
			Name = "WallFront",
			Size = Vector3.new(segment, WALL_H, 1),
			CFrame = at(s * (gap / 2 + segment / 2), WALL_H / 2 + 1, D / 2),
			Color = wallColor,
			Parent = model,
		})
	end

	local laser = part({
		Name = "Laser",
		Size = Vector3.new(gap, WALL_H, 0.6),
		CFrame = at(0, WALL_H / 2 + 1, D / 2),
		Color = Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})

	local signPart = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		CFrame = at(0, WALL_H + 5, D / 2),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.fromOffset(320, 110)
	signGui.MaxDistance = 250
	signGui.Parent = signPart
	local ownerLabel = label(signGui, { Text = "Empty Base", Size = UDim2.fromScale(1, 0.6) })
	local lockLabel = label(signGui, { Text = "", Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6) })

	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(7, 0.6, 7),
		CFrame = at(-W / 2 + 6, 1.3, D / 2 - 7),
		Color = Color3.fromRGB(60, 220, 90),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local lockGui = Instance.new("BillboardGui")
	lockGui.Size = UDim2.fromOffset(160, 50)
	lockGui.StudsOffset = Vector3.new(0, 3, 0)
	lockGui.MaxDistance = 60
	lockGui.Parent = lockPad
	label(lockGui, { Text = "🔒 LOCK BASE", Size = UDim2.fromScale(1, 1) })

	local spawnCFrame = at(0, 4, 14) * CFrame.Angles(0, math.pi, 0)

	local plot = {
		Index = index,
		CFrame = cf,
		Model = model,
		Laser = laser,
		LockPad = lockPad,
		OwnerLabel = ownerLabel,
		LockLabel = lockLabel,
		SpawnCFrame = spawnCFrame,
		Owner = nil :: Player?,
		LockedUntil = 0,
		Slots = {},
	}

	local slotIndex = 0
	for _, lz in SLOT_Z do
		for _, lx in SLOT_X do
			slotIndex += 1
			local pedestal = part({
				Name = "Pedestal" .. slotIndex,
				Size = Vector3.new(7, 1.5, 7),
				CFrame = at(lx, 1.75, lz),
				Color = Color3.fromRGB(90, 90, 105),
				Material = Enum.Material.Slate,
				Parent = model,
			})
			local pad = part({
				Name = "CollectPad" .. slotIndex,
				Size = Vector3.new(6, 0.4, 3),
				CFrame = at(lx, 1.2, lz + 5.5),
				Color = Color3.fromRGB(60, 200, 80),
				Material = Enum.Material.Neon,
				Parent = model,
			})
			local padGui = Instance.new("BillboardGui")
			padGui.Size = UDim2.fromOffset(120, 30)
			padGui.StudsOffset = Vector3.new(0, 1.5, 0)
			padGui.MaxDistance = 45
			padGui.Parent = pad
			local padLabel = label(padGui, { Text = "", Size = UDim2.fromScale(1, 1), TextColor3 = Color3.fromRGB(120, 255, 120) })

			local info = Instance.new("BillboardGui")
			info.Size = UDim2.fromOffset(200, 110)
			info.StudsOffset = Vector3.new(0, 9, 0)
			info.MaxDistance = 70
			info.Parent = pedestal
			local nameLabel = label(info, { Text = "", Position = UDim2.fromScale(0, 0) })
			local rarityLabel = label(info, { Text = "", Position = UDim2.fromScale(0, 0.25) })
			local incomeLabel = label(info, { Text = "", Position = UDim2.fromScale(0, 0.5), TextColor3 = Color3.fromRGB(120, 255, 120) })
			local timerLabel = label(info, { Text = "", Position = UDim2.fromScale(0, 0.75), TextColor3 = Color3.fromRGB(255, 230, 120) })

			local promptAttachment = Instance.new("Attachment")
			promptAttachment.Position = Vector3.new(0, 3, 0)
			promptAttachment.Parent = pedestal

			local stealPrompt = Instance.new("ProximityPrompt")
			stealPrompt.Name = "StealPrompt"
			stealPrompt.ActionText = "Steal"
			stealPrompt.ObjectText = ""
			stealPrompt.HoldDuration = Config.StealHoldDuration
			stealPrompt.MaxActivationDistance = 9
			stealPrompt.RequiresLineOfSight = false
			stealPrompt.KeyboardKeyCode = Enum.KeyCode.E
			stealPrompt:SetAttribute("Role", "Steal")
			stealPrompt:SetAttribute("OwnerId", 0)
			stealPrompt:SetAttribute("Occupied", false)
			stealPrompt.Parent = promptAttachment
			CollectionService:AddTag(stealPrompt, "SlotPrompt")

			local sellPrompt = Instance.new("ProximityPrompt")
			sellPrompt.Name = "SellPrompt"
			sellPrompt.ActionText = "Sell"
			sellPrompt.HoldDuration = 1
			sellPrompt.MaxActivationDistance = 9
			sellPrompt.RequiresLineOfSight = false
			sellPrompt.KeyboardKeyCode = Enum.KeyCode.F
			sellPrompt.UIOffset = Vector2.new(0, 60)
			sellPrompt:SetAttribute("Role", "Sell")
			sellPrompt:SetAttribute("OwnerId", 0)
			sellPrompt:SetAttribute("Occupied", false)
			sellPrompt.Parent = promptAttachment
			CollectionService:AddTag(sellPrompt, "SlotPrompt")

			plot.Slots[slotIndex] = {
				Index = slotIndex,
				Pedestal = pedestal,
				Pad = pad,
				PadLabel = padLabel,
				TopCFrame = at(lx, 2.5, lz) * CFrame.Angles(0, math.pi, 0), -- models face the entrance
				NameLabel = nameLabel,
				RarityLabel = rarityLabel,
				IncomeLabel = incomeLabel,
				TimerLabel = timerLabel,
				StealPrompt = stealPrompt,
				SellPrompt = sellPrompt,
				ItemModel = nil :: Model?,
			}
		end
	end

	model.Parent = mapFolder
	return plot
end

function Plots.Init(services)
	S = services
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace
	buildWorld(mapFolder)
	for index = 1, Config.Plot.Count do
		plots[index] = buildPlot(index, mapFolder)
	end
end

function Plots.All()
	return plots
end

function Plots.Get(player: Player)
	return byPlayer[player]
end

function Plots.Assign(player: Player)
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			plot.LockedUntil = 0
			byPlayer[player] = plot
			plot.OwnerLabel.Text = player.DisplayName .. "'s Base"
			for _, slot in plot.Slots do
				slot.StealPrompt:SetAttribute("OwnerId", player.UserId)
				slot.SellPrompt:SetAttribute("OwnerId", player.UserId)
			end
			return plot
		end
	end
	return nil
end

function Plots.Release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	plot.Owner = nil
	plot.LockedUntil = 0
	plot.OwnerLabel.Text = "Empty Base"
	plot.LockLabel.Text = ""
	plot.Laser.Transparency = 1
	for _, slot in plot.Slots do
		slot.StealPrompt:SetAttribute("OwnerId", 0)
		slot.SellPrompt:SetAttribute("OwnerId", 0)
	end
end

function Plots.IsInside(plot, position: Vector3): boolean
	local localPos = plot.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) < W / 2 and math.abs(localPos.Z) < D / 2 and localPos.Y < 40
end

function Plots.LockRemaining(plot): number
	local owner = plot.Owner
	local shield = 0
	if owner then
		local data = S.Data.Get(owner)
		shield = data and data.ShieldUntil or 0
	end
	return math.max(plot.LockedUntil, shield) - now()
end

function Plots.IsLocked(plot): boolean
	return Plots.LockRemaining(plot) > 0
end

local function characterOf(hit: BasePart): (Player?, BasePart?)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return player, root :: BasePart?
end

function Plots.Start()
	for _, plot in plots do
		plot.LockPad.Touched:Connect(function(hit)
			local player = characterOf(hit)
			if player and player == plot.Owner and plot.LockedUntil < now() then
				plot.LockedUntil = now() + Config.LockDuration
				S.Notify(player, "🔒 Base locked for " .. Config.LockDuration .. "s!", Color3.fromRGB(120, 255, 120))
			end
		end)
		plot.Laser.Touched:Connect(function(hit)
			local player, root = characterOf(hit)
			if player and root and player ~= plot.Owner and Plots.IsLocked(plot) then
				-- Bounce intruders back out onto the road side.
				root.CFrame = plot.CFrame * CFrame.new(0, 4, D / 2 + 6)
			end
		end)
	end

	task.spawn(function()
		while true do
			for _, plot in plots do
				if plot.Owner then
					local remaining = Plots.LockRemaining(plot)
					if remaining > 0 then
						plot.Laser.Transparency = 0.35
						plot.LockLabel.Text = "🔒 LOCKED " .. Util.FormatTime(remaining)
						plot.LockLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
					else
						plot.Laser.Transparency = 1
						plot.LockLabel.Text = "🔓 UNLOCKED"
						plot.LockLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
					end
					plot.Owner:SetAttribute("LockedUntil", now() + math.max(remaining, 0))
				end
			end
			task.wait(0.5)
		end
	end)
end

return Plots
