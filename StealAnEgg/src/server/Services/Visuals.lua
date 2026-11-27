-- Builds egg and pet models. Uses your models from ServerStorage.Models.Eggs/<EggId> and
-- ServerStorage.Models.Pets/<PetName> when present, otherwise builds a cute procedural one.
-- Every model is normalized: an anchored invisible "Root" PrimaryPart with everything welded to it.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Visuals = {}

local modelsFolder = ServerStorage:FindFirstChild("Models")

local function findMutation(name: string?)
	for _, mutation in Config.Mutations do
		if mutation.Name == name then
			return mutation
		end
	end
	return Config.Mutations[1]
end

local function stripScripts(model: Instance)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		end
	end
end

local function normalize(model: Model, targetSize: number): Model
	-- Scale so the largest dimension equals targetSize.
	local _, size = model:GetBoundingBox()
	local largest = math.max(size.X, size.Y, size.Z)
	if largest > 0 then
		model:ScaleTo(model:GetScale() * (targetSize / largest))
	end
	local cf, newSize = model:GetBoundingBox()

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new(cf.Position - Vector3.new(0, newSize.Y / 2, 0)) -- root sits at the model's base
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = true
	root.Parent = model

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.PrimaryPart = root
	model:SetAttribute("Height", newSize.Y)
	return model
end

local function ball(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

local function applyMutation(model: Model, mutationName: string?, recolor: boolean)
	local mutation = findMutation(mutationName)
	if mutation.Name == "Normal" then
		return
	end
	if recolor then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Root" and part.Name ~= "Eye" then
				if mutation.Name == "Golden" then
					part.Color = mutation.Color
					part.Material = Enum.Material.Foil
				elseif mutation.Name == "Diamond" then
					part.Color = mutation.Color
					part.Material = Enum.Material.Glass
					part.Transparency = 0.15
				elseif mutation.Name == "Galaxy" then
					part.Color = mutation.Color
					part.Material = Enum.Material.ForceField
				else
					part.Material = Enum.Material.Neon
				end
			end
		end
	end

	local anchor = model.PrimaryPart
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = mutation.Mult * 3
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.4, 0)
	emitter.LightEmission = 1
	if mutation.Name == "Rainbow" then
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 60)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 255)),
		})
	else
		emitter.Color = ColorSequence.new(mutation.Color)
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, (model:GetAttribute("Height") or 3) / 2, 0)
	attachment.Parent = anchor
	emitter.Parent = attachment

	local light = Instance.new("PointLight")
	light.Color = mutation.Color
	light.Range = 8 + mutation.Mult
	light.Brightness = 2
	light.Parent = attachment
end

local function rarityExtras(model: Model, rarityName: string)
	local rarity = Config.Rarities[rarityName]
	if not rarity or rarity.Order < 4 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, (model:GetAttribute("Height") or 3) / 2, 0)
	attachment.Parent = model.PrimaryPart
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = attachment
end

local function fromStorage(folderName: string, name: string): Model?
	local folder = modelsFolder and modelsFolder:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(name)
	if not template then
		return nil
	end
	local clone = template:Clone()
	if clone:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		clone.Parent = wrapper
		clone = wrapper
	end
	if not clone:IsA("Model") then
		return nil
	end
	stripScripts(clone)
	for _, d in clone:GetDescendants() do
		if d:IsA("Humanoid") then
			d:Destroy()
		end
	end
	return clone
end

function Visuals.MakeEgg(egg, mutationName: string?): Model
	local size = 3 + egg.Index * 0.25
	local model = fromStorage("Eggs", egg.Id)
	local custom = model ~= nil
	if not model then
		model = Instance.new("Model")
		local shell = ball(model, Vector3.new(size * 0.75, size, size * 0.75), egg.Color, CFrame.new(0, size / 2, 0))
		shell.Name = "Shell"
		if Config.Rarities[egg.Rarity].Order >= 5 then
			shell.Material = Enum.Material.Neon
		end
		-- Spots
		local rng = Random.new(egg.Index * 97)
		for _ = 1, 5 do
			local theta = rng:NextNumber(0, math.pi * 2)
			local y = rng:NextNumber(0.3, 0.75) * size
			local radius = size * 0.36
			local spot = ball(
				model,
				Vector3.new(size * 0.18, size * 0.18, size * 0.06),
				egg.Color:Lerp(Color3.new(1, 1, 1), 0.55),
				CFrame.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
					* CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(theta), 0, math.sin(theta))).Rotation
			)
			spot.Name = "Spot"
		end
	end
	model.Name = egg.Name
	normalize(model, size)
	rarityExtras(model, egg.Rarity)
	applyMutation(model, mutationName, not custom)
	return model
end

function Visuals.MakePet(egg, petName: string, mutationName: string?): Model
	local pet
	for _, candidate in egg.Pets do
		if candidate.Name == petName then
			pet = candidate
		end
	end
	local mult = pet and pet.Mult or 3
	local size = 3.5 + egg.Index * 0.3 + math.log(mult, 2) * 0.4
	local model = fromStorage("Pets", petName)
	local custom = model ~= nil
	if not model then
		model = Instance.new("Model")
		local h, s, v = egg.Color:ToHSV()
		local petIndex = 1
		for i, candidate in egg.Pets do
			if candidate.Name == petName then
				petIndex = i
			end
		end
		local color = Color3.fromHSV((h + petIndex * 0.08) % 1, math.clamp(s + 0.1, 0, 1), math.clamp(v, 0.35, 1))
		local unit = size / 4
		local body = ball(model, Vector3.new(2.6, 2.3, 2.8) * unit, color, CFrame.new(0, 1.3 * unit, 0))
		body.Name = "Body"
		local head = ball(model, Vector3.new(2, 2, 2) * unit, color, CFrame.new(0, 2.6 * unit, -1.1 * unit))
		head.Name = "Head"
		for _, side in { -1, 1 } do
			local eye = ball(model, Vector3.new(0.35, 0.5, 0.2) * unit, Color3.new(0.05, 0.05, 0.05),
				CFrame.new(side * 0.42 * unit, 2.75 * unit, -2.02 * unit))
			eye.Name = "Eye"
			local ear = Instance.new("WedgePart")
			ear.Size = Vector3.new(0.25, 0.9, 0.6) * unit
			ear.Color = color:Lerp(Color3.new(0, 0, 0), 0.15)
			ear.CFrame = CFrame.new(side * 0.6 * unit, 3.7 * unit, -1.0 * unit)
			ear.Parent = model
			local foot = ball(model, Vector3.new(0.8, 0.5, 0.9) * unit, color:Lerp(Color3.new(1, 1, 1), 0.3),
				CFrame.new(side * 0.8 * unit, 0.25 * unit, -0.6 * unit))
			foot.Name = "Foot"
		end
		if mult >= 10 then
			-- Fancy pets get wings
			for _, side in { -1, 1 } do
				local wing = ball(model, Vector3.new(0.3, 1.6, 2.4) * unit, color:Lerp(Color3.new(1, 1, 1), 0.5),
					CFrame.new(side * 1.5 * unit, 2 * unit, 0.4 * unit) * CFrame.Angles(0, 0, side * math.rad(35)), Enum.Material.Neon)
				wing.Name = "Wing"
			end
		end
	end
	model.Name = petName
	normalize(model, size)
	rarityExtras(model, egg.Rarity)
	applyMutation(model, mutationName, not custom)
	return model
end

function Visuals.MakeItem(item): Model?
	local egg = Config.EggsById[item.EggId]
	if not egg then
		return nil
	end
	if item.Pet then
		return Visuals.MakePet(egg, item.Pet, item.Mutation)
	end
	return Visuals.MakeEgg(egg, item.Mutation)
end

function Visuals.Burst(position: Vector3, color: Color3, amount: number?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(1.2, 0)
	emitter.Speed = NumberRange.new(10, 25)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 0
	emitter.Parent = part
	part.Parent = workspace
	emitter:Emit(amount or 50)
	game:GetService("Debris"):AddItem(part, 2)
end

Visuals.FindMutation = findMutation

return Visuals
