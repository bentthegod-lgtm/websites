--[[
	Models - small procedural models shared by the server, the client's viewport icons and
	the preview tools: every valuable (with a rarity-coloured glow ring), a preview dummy
	and the Captain's Outfit pieces (hat and coat built from parts on the player's avatar).
]]

local GameConfig = require(script.Parent.Config.GameConfig)
local Parts = require(script.Parent.Parts)

local Models = {}

local P = Parts.Palette
local M = Enum.Material
local rgb = Color3.fromRGB
local V3 = Vector3.new

local GOLD = rgb(240, 190, 60)
local SILVER = rgb(210, 214, 222)

-- Item shapes, relative to the model's base on the floor. { name, size, offset, color, material, shape }
local SHAPES = {
	Watch = {
		{ "Case", V3(0.3, 1.3, 1.3), CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0), GOLD, M.Metal, "Cylinder" },
		{ "Face", V3(0.32, 1, 1), CFrame.new(0, 0.8, -0.02) * CFrame.Angles(0, math.rad(90), 0), P.Cream, M.SmoothPlastic, "Cylinder" },
		{ "Chain", V3(0.12, 0.12, 1.4), CFrame.new(0, 1.5, 0.3) * CFrame.Angles(math.rad(50), 0, 0), GOLD, M.Metal },
	},
	Spoons = {
		{ "Spoon", V3(0.25, 0.12, 1.6), CFrame.new(-0.3, 0.3, 0) * CFrame.Angles(0, 0.2, 0), SILVER, M.Metal },
		{ "Spoon", V3(0.25, 0.12, 1.6), CFrame.new(0, 0.42, 0), SILVER, M.Metal },
		{ "Spoon", V3(0.25, 0.12, 1.6), CFrame.new(0.3, 0.54, 0) * CFrame.Angles(0, -0.2, 0), SILVER, M.Metal },
	},
	Wallet = {
		{ "Wallet", V3(1.3, 0.35, 0.9), CFrame.new(0, 0.4, 0), rgb(110, 66, 40), M.Leather },
		{ "Clasp", V3(0.3, 0.38, 0.92), CFrame.new(0.4, 0.4, 0), GOLD, M.Metal },
	},
	Spyglass = {
		{ "Tube", V3(2, 0.5, 0.5), CFrame.new(0, 0.5, 0), rgb(200, 150, 70), M.Metal, "Cylinder" },
		{ "Eyepiece", V3(0.6, 0.36, 0.36), CFrame.new(-1.2, 0.5, 0), P.BrassDark, M.Metal, "Cylinder" },
	},
	Necklace = {
		{ "Pearls", V3(0.2, 1.5, 1.5), CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(245, 240, 232), M.SmoothPlastic, "Cylinder" },
		{ "Pendant", V3(0.5, 0.5, 0.5), CFrame.new(0, 0.5, 0.8), rgb(250, 250, 255), M.Glass, "Ball" },
	},
	Compass = {
		{ "Body", V3(0.4, 1.4, 1.4), CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(200, 150, 70), M.Metal, "Cylinder" },
		{ "Face", V3(0.42, 1.1, 1.1), CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)), P.Cream, M.SmoothPlastic, "Cylinder" },
		{ "Needle", V3(0.12, 0.1, 0.9), CFrame.new(0, 0.66, 0) * CFrame.Angles(0, 0.6, 0), P.Red, M.Neon },
	},
	Decanter = {
		{ "Bowl", V3(1.1, 1.1, 1.1), CFrame.new(0, 0.7, 0), rgb(200, 230, 255), M.Glass, "Ball" },
		{ "Neck", V3(0.8, 0.35, 0.35), CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(200, 230, 255), M.Glass, "Cylinder" },
		{ "Stopper", V3(0.4, 0.4, 0.4), CFrame.new(0, 2, 0), rgb(170, 40, 60), M.Glass, "Ball" },
	},
	JewelBox = {
		{ "Box", V3(1.6, 0.8, 1.1), CFrame.new(0, 0.45, 0), rgb(110, 30, 60), M.Wood },
		{ "Lid", V3(1.6, 0.14, 1.1), CFrame.new(0, 1.05, -0.4) * CFrame.Angles(math.rad(-55), 0, 0), rgb(110, 30, 60), M.Wood },
		{ "Jewels", V3(1.3, 0.2, 0.8), CFrame.new(0, 0.86, 0), rgb(120, 255, 200), M.Neon },
	},
	GoldBar = {
		{ "Bar", V3(1.8, 0.6, 0.9), CFrame.new(0, 0.35, 0), GOLD, M.Metal },
		{ "Stamp", V3(0.8, 0.05, 0.4), CFrame.new(0, 0.66, 0), rgb(200, 150, 40), M.Metal },
	},
	Painting = {
		{ "Frame", V3(2.6, 2, 0.25), CFrame.new(0, 1.15, 0) * CFrame.Angles(math.rad(-12), 0, 0), GOLD, M.Wood },
		{ "Canvas", V3(2.2, 1.6, 0.28), CFrame.new(0, 1.15, 0.02) * CFrame.Angles(math.rad(-12), 0, 0), rgb(60, 110, 150), M.SmoothPlastic },
		{ "Sun", V3(0.6, 0.6, 0.3), CFrame.new(0.5, 1.4, 0.0) * CFrame.Angles(math.rad(-12), 0, 0), rgb(255, 180, 90), M.SmoothPlastic },
	},
	Tiara = {
		{ "Band", V3(0.25, 1.5, 1.5), CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, M.Metal, "Cylinder" },
		{ "Ruby", V3(0.55, 0.7, 0.4), CFrame.new(0, 0.9, -0.6), rgb(230, 30, 60), M.Neon },
		{ "Peak", V3(0.2, 0.6, 0.2), CFrame.new(0, 1.4, -0.6), GOLD, M.Metal },
	},
	Sextant = {
		{ "Arc", V3(0.2, 1.8, 1.8), CFrame.new(0, 1, 0), GOLD, M.Metal, "Cylinder" },
		{ "Arm", V3(0.2, 1.8, 0.2), CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(25), 0, 0), rgb(200, 150, 70), M.Metal },
		{ "Lens", V3(0.5, 0.3, 0.3), CFrame.new(0.2, 1.9, 0), rgb(160, 220, 255), M.Glass, "Cylinder" },
	},
	Sapphire = {
		{ "Gem", V3(1, 1, 1), CFrame.new(0, 1, 0), rgb(60, 110, 255), M.Neon, "Ball" },
		{ "Setting", V3(0.3, 1.2, 1.2), CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, M.Metal, "Cylinder" },
	},
}
Models.Shapes = SHAPES

function Models.rarityColor(rarity)
	local r = GameConfig.Rarities[rarity]
	return if r then Parts.rgb(r.Color) else P.Cream
end

-- A valuable on the floor at `cf` (its base). Anchored, non-colliding; returns the model.
function Models.loot(key, cf, parent)
	local def = GameConfig.Loot[key]
	local model = Instance.new("Model")
	model.Name = "Loot_" .. key
	local color = Models.rarityColor(def.Rarity)
	local ring = Parts.new({ Name = "Glow", Shape = Enum.PartType.Cylinder, Size = V3(0.12, 2.6, 2.6), CFrame = cf * CFrame.new(0, 0.07, 0) * Parts.UP, Color = color, Material = M.Neon, CanCollide = false, CastShadow = false, Transparency = 0.25, Parent = model })
	for _, shape in ipairs(SHAPES[def.Model] or SHAPES.Wallet) do
		Parts.new({ Name = shape[1], Size = shape[2], CFrame = cf * shape[3], Color = shape[4], Material = shape[5], Shape = if shape[6] then Enum.PartType[shape[6]] else nil, CanCollide = false, Transparency = if shape[5] == M.Glass then 0.25 else 0, Parent = model })
	end
	Parts.light(ring, color, if def.Rarity == "Legendary" then 14 else 9, if def.Rarity == "Common" then 0.8 else 1.4, false)
	if def.Rarity == "Epic" or def.Rarity == "Legendary" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Color = ColorSequence.new(color)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.6, 1.2)
		sparkle.Rate = if def.Rarity == "Legendary" then 10 else 4
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(40, 40)
		sparkle.EmissionDirection = Enum.NormalId.Right
		sparkle.Parent = ring
	end
	model.PrimaryPart = ring
	model:SetAttribute("Item", key)
	model.Parent = parent
	return model
end

-- Captain's Outfit pieces, welded to the avatar by PlayerService. { name, anchor, size, offset, color, material, shape }
Models.CaptainOutfit = {
	{ "CapCrown", "Head", V3(0.55, 1.35, 1.35), CFrame.new(0, 0.62, 0) * Parts.UP, P.White, M.SmoothPlastic, "Cylinder" },
	{ "CapBand", "Head", V3(0.25, 1.38, 1.38), CFrame.new(0, 0.42, 0) * Parts.UP, P.Black, M.SmoothPlastic, "Cylinder" },
	{ "CapPeak", "Head", V3(1.1, 0.12, 0.6), CFrame.new(0, 0.32, -0.75), P.Black, M.SmoothPlastic },
	{ "CapBadge", "Head", V3(0.35, 0.3, 0.1), CFrame.new(0, 0.5, -0.7), P.Brass, M.Metal },
	{ "Coat", "Torso", V3(2.15, 2.1, 1.15), CFrame.new(0, -0.05, 0), P.Navy, M.Fabric },
	{ "Lapel", "Torso", V3(0.8, 1.2, 0.1), CFrame.new(0, 0.35, -0.6), P.White, M.Fabric },
	{ "Buttons", "Torso", V3(0.25, 1.4, 0.1), CFrame.new(0, -0.3, -0.62), P.Brass, M.Metal },
	{ "Epaulette", "Torso", V3(0.6, 0.15, 0.9), CFrame.new(-1.05, 1.02, 0), P.Brass, M.Metal },
	{ "Epaulette", "Torso", V3(0.6, 0.15, 0.9), CFrame.new(1.05, 1.02, 0), P.Brass, M.Metal },
}

-- A blocky stand-in character for previews (feet at cf).
function Models.dummy(cf, parent, captain)
	local model = Instance.new("Model")
	model.Name = "Dummy"
	local skin = rgb(234, 190, 150)
	local shirt = if captain then P.Navy else rgb(70, 120, 170)
	local function piece(name, size, offset, color, shape)
		return Parts.new({ Name = name, Size = size, CFrame = cf * offset, Color = color, Material = M.SmoothPlastic, Shape = shape, CanCollide = false, Parent = model })
	end
	piece("LeftLeg", V3(1, 2, 1), CFrame.new(-0.5, 1, 0), rgb(50, 54, 70))
	piece("RightLeg", V3(1, 2, 1), CFrame.new(0.5, 1, 0), rgb(50, 54, 70))
	local torso = piece("Torso", V3(2, 2, 1), CFrame.new(0, 3, 0), shirt)
	piece("LeftArm", V3(1, 2, 1), CFrame.new(-1.5, 3, 0), shirt)
	piece("RightArm", V3(1, 2, 1), CFrame.new(1.5, 3, 0), shirt)
	local head = piece("Head", V3(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), skin, Enum.PartType.Ball)
	if captain then
		for _, item in ipairs(Models.CaptainOutfit) do
			local anchor = if item[2] == "Head" then head else torso
			Parts.new({ Name = item[1], Size = item[3], CFrame = anchor.CFrame * item[4], Color = item[5], Material = item[6], Shape = if item[7] then Enum.PartType[item[7]] else nil, CanCollide = false, Parent = model })
		end
	else
		piece("LifeVest", V3(2.1, 1.5, 1.1), CFrame.new(0, 3.2, 0), P.Orange)
	end
	model.Parent = parent
	return model
end

return Models
