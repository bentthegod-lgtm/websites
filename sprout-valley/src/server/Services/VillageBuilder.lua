--[[
	VillageBuilder - builds the whole village from parts: grass, cobbled street and plaza,
	six fenced garden plots with soil tiles, the three NPC stalls (Seed Shop, Gear Shop,
	Sell Stand), the leaderboard board, fountain, lamps, trees, flowers, windmill and clouds.

	Layout (top view, +X east):
	    plaza (x ~ -88)            street            plots: 3 north (z > 22), 3 south (z < -22)
	  [Seed Shop]  fountain  [Sell Stand] ... [P1][P2][P3] / [P4][P5][P6] ... windmill

	Returns { folder, plots = {...}, stalls = { SeedShop, GearShop, SellStand }, board, spawn }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local Rng = require(Shared.Rng)

local VillageBuilder = {}

local PLOT = GameConfig.Plot
local L = CFrame.new
local A = CFrame.Angles
local rad = math.rad

local PLOT_WIDTH = PLOT.Cols * PLOT.TileSize + 6
local PLOT_DEPTH = PLOT.Rows * PLOT.TileSize + 6
local PLAZA = Vector3.new(-88, 0, 0)

VillageBuilder.SoilColor = Color3.fromRGB(122, 84, 54)
VillageBuilder.LockedColor = Color3.fromRGB(96, 158, 72)
VillageBuilder.PlotAccents = {
	Color3.fromRGB(255, 170, 190),
	Color3.fromRGB(255, 210, 120),
	Color3.fromRGB(150, 210, 255),
	Color3.fromRGB(190, 160, 255),
	Color3.fromRGB(150, 230, 170),
	Color3.fromRGB(255, 180, 130),
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "ClassName" and k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Text on one face of a part.
function VillageBuilder.surfaceText(target, face, text, color, ppStud)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppStud or 40
	gui.LightInfluence = 0.2
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or rgb(255, 255, 255)
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	return label, gui
end

---------------------------------------------------------------------------------------------
-- Plots
---------------------------------------------------------------------------------------------

-- Local position (relative to the plot's front-centre CFrame) of a tile's top centre.
function VillageBuilder.tileLocal(index)
	local col = ((index - 1) % PLOT.Cols) + 1
	local row = ((index - 1) // PLOT.Cols) + 1
	return Vector3.new((col - (PLOT.Cols + 1) / 2) * PLOT.TileSize, 0.5, 3 + (row - 0.5) * PLOT.TileSize)
end

function VillageBuilder.setTileLocked(tile, locked)
	tile:SetAttribute("Locked", locked)
	if locked then
		tile.Color = VillageBuilder.LockedColor
		tile.Material = Enum.Material.Grass
		tile.Transparency = 0.35
	else
		tile.Color = VillageBuilder.SoilColor
		tile.Material = Enum.Material.Ground
		tile.Transparency = 0
	end
end

local function fenceLine(parent, cf, from, to, color)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2
	local look = CFrame.lookAt(mid, mid + delta)
	for _, y in ipairs({ 1.0, 2.1 }) do
		part(parent, { Name = "Rail", Size = Vector3.new(0.25, 0.35, length), CFrame = cf * (look + Vector3.new(0, y, 0)), Color = color, Material = Enum.Material.WoodPlanks })
	end
	local posts = math.max(1, math.floor(length / 5))
	for i = 0, posts do
		local p = from + delta * (i / posts)
		part(parent, { Name = "Post", Size = Vector3.new(0.6, 3, 0.6), CFrame = cf * L(p.X, 1.5, p.Z), Color = color, Material = Enum.Material.WoodPlanks })
		part(parent, { Name = "Cap", Size = Vector3.new(0.75, 0.3, 0.75), CFrame = cf * L(p.X, 3.1, p.Z), Color = color:Lerp(rgb(255, 255, 255), 0.4) })
	end
end

local function buildPlot(parent, id, cf)
	local f = folder("Plot" .. id, parent)
	local accent = VillageBuilder.PlotAccents[id]
	local fence = rgb(245, 236, 220)
	part(f, { Name = "Lawn", Size = Vector3.new(PLOT_WIDTH, 0.2, PLOT_DEPTH), CFrame = cf * L(0, 0.06, PLOT_DEPTH / 2), Color = rgb(104, 170, 76), Material = Enum.Material.Grass, CanCollide = false })
	-- Path from the gate to the first row.
	part(f, { Name = "Path", Size = Vector3.new(6, 0.22, 3), CFrame = cf * L(0, 0.08, 1.4), Color = rgb(214, 196, 160), Material = Enum.Material.Pebble, CanCollide = false })

	local tiles = {}
	local tileFolder = folder("Tiles", f)
	for index = 1, PLOT.Cols * PLOT.Rows do
		local pos = VillageBuilder.tileLocal(index)
		local tile = part(tileFolder, {
			Name = "Tile",
			Size = Vector3.new(PLOT.TileSize - 0.3, 0.5, PLOT.TileSize - 0.3),
			CFrame = cf * L(pos.X, 0.25, pos.Z),
			CanCollide = false,
		})
		tile:SetAttribute("PlotId", id)
		tile:SetAttribute("TileIndex", index)
		VillageBuilder.setTileLocked(tile, true)
		tiles[index] = tile
	end

	local hw, d = PLOT_WIDTH / 2, PLOT_DEPTH
	local fenceFolder = folder("Fence", f)
	fenceLine(fenceFolder, cf, Vector3.new(-hw, 0, 0), Vector3.new(-4, 0, 0), fence)
	fenceLine(fenceFolder, cf, Vector3.new(4, 0, 0), Vector3.new(hw, 0, 0), fence)
	fenceLine(fenceFolder, cf, Vector3.new(-hw, 0, 0), Vector3.new(-hw, 0, d), fence)
	fenceLine(fenceFolder, cf, Vector3.new(hw, 0, 0), Vector3.new(hw, 0, d), fence)
	fenceLine(fenceFolder, cf, Vector3.new(-hw, 0, d), Vector3.new(hw, 0, d), fence)

	-- Gate arch with the owner's name.
	for _, x in ipairs({ -4.2, 4.2 }) do
		part(f, { Name = "ArchPost", Size = Vector3.new(0.9, 7.5, 0.9), CFrame = cf * L(x, 3.75, 0), Color = accent, Material = Enum.Material.WoodPlanks })
		part(f, { Name = "ArchCap", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = cf * L(x, 7.8, 0), Color = accent:Lerp(rgb(255, 255, 255), 0.4) })
	end
	local beam = part(f, { Name = "ArchSign", Size = Vector3.new(9.8, 1.8, 0.5), CFrame = cf * L(0, 6.6, 0), Color = rgb(250, 240, 220), Material = Enum.Material.WoodPlanks })
	-- Label both faces: Front faces the street, Back faces into the garden.
	local signLabel = VillageBuilder.surfaceText(beam, Enum.NormalId.Back, "Empty Plot", rgb(110, 70, 40))
	signLabel.TextStrokeTransparency = 1
	local signInner = VillageBuilder.surfaceText(beam, Enum.NormalId.Front, "Empty Plot", rgb(110, 70, 40))
	signInner.TextStrokeTransparency = 1
	-- Flower boxes either side of the gate.
	for _, x in ipairs({ -7.5, 7.5 }) do
		part(f, { Name = "FlowerBox", Size = Vector3.new(5, 0.9, 1.2), CFrame = cf * L(x, 0.45, -1), Color = rgb(150, 100, 60), Material = Enum.Material.WoodPlanks })
		for k = -2, 2 do
			local c = Color3.fromHSV(((id * 0.17) + k * 0.08) % 1, 0.45, 1)
			part(f, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = cf * L(x + k * 0.9, 1.15, -1), Color = c, CanCollide = false })
		end
	end
	local crops = folder("Crops", f)
	local extras = folder("Gear", f)

	return {
		id = id,
		cf = cf,
		folder = f,
		tiles = tiles,
		crops = crops,
		extras = extras,
		signLabels = { signLabel, signInner },
		accent = accent,
		spawnCFrame = cf * L(0, 3.5, 2.5) * A(0, math.pi, 0),
		center = (cf * L(0, 0, PLOT_DEPTH / 2)).Position,
		models = {},
		sprinklerModels = {},
	}
end

---------------------------------------------------------------------------------------------
-- NPC stalls
---------------------------------------------------------------------------------------------

local function buildNpc(parent, cf, shirt, hatColor, hatStyle)
	local skin = rgb(255, 214, 170)
	local m = Instance.new("Model")
	m.Name = "Npc"
	m.Parent = parent
	local pants = rgb(90, 80, 120)
	part(m, { Name = "LegL", Size = Vector3.new(0.95, 2, 0.95), CFrame = cf * L(-0.5, 1, 0), Color = pants })
	part(m, { Name = "LegR", Size = Vector3.new(0.95, 2, 0.95), CFrame = cf * L(0.5, 1, 0), Color = pants })
	local torso = part(m, { Name = "Torso", Size = Vector3.new(2, 2, 1), CFrame = cf * L(0, 3, 0), Color = shirt })
	part(m, { Name = "Apron", Size = Vector3.new(1.6, 1.6, 0.1), CFrame = cf * L(0, 2.8, -0.55), Color = rgb(250, 245, 230) })
	part(m, { Name = "ArmL", Size = Vector3.new(0.9, 2, 0.9), CFrame = cf * L(-1.45, 3, -0.2) * A(rad(-20), 0, rad(-8)), Color = shirt })
	part(m, { Name = "ArmR", Size = Vector3.new(0.9, 2, 0.9), CFrame = cf * L(1.45, 3, -0.2) * A(rad(-20), 0, rad(8)), Color = shirt })
	part(m, { Name = "HandL", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = cf * L(-1.5, 2, -0.55), Color = skin })
	part(m, { Name = "HandR", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = cf * L(1.5, 2, -0.55), Color = skin })
	local head = part(m, { Name = "Head", Size = Vector3.new(2, 1, 1), CFrame = cf * L(0, 4.75, 0), Color = skin })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.35, 1.25)
	mesh.Parent = head
	for _, x in ipairs({ -0.35, 0.35 }) do
		part(m, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.24, 0.3, 0.24), CFrame = cf * L(x, 4.95, -0.6), Color = rgb(40, 30, 30), CanCollide = false })
		part(m, { Name = "Cheek", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = cf * L(x * 1.6, 4.6, -0.5), Color = rgb(255, 150, 150), CanCollide = false })
	end
	part(m, { Name = "Smile", Size = Vector3.new(0.5, 0.08, 0.08), CFrame = cf * L(0, 4.45, -0.62), Color = rgb(120, 50, 50), CanCollide = false })
	if hatStyle == "Straw" then
		part(m, { Name = "Brim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 3, 3), CFrame = cf * L(0, 5.55, 0) * A(0, 0, math.pi / 2), Color = hatColor, Material = Enum.Material.Fabric })
		part(m, { Name = "Crown", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.6, 1.6), CFrame = cf * L(0, 5.95, 0) * A(0, 0, math.pi / 2), Color = hatColor, Material = Enum.Material.Fabric })
		part(m, { Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.65, 1.65), CFrame = cf * L(0, 5.7, 0) * A(0, 0, math.pi / 2), Color = rgb(230, 80, 80) })
	elseif hatStyle == "Cap" then
		part(m, { Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.7, 1.7), CFrame = cf * L(0, 5.4, 0), Color = hatColor })
		part(m, { Name = "Visor", Size = Vector3.new(1.4, 0.12, 0.9), CFrame = cf * L(0, 5.35, -0.9), Color = hatColor })
	else
		part(m, { Name = "Beanie", Shape = Enum.PartType.Ball, Size = Vector3.new(1.75, 1.75, 1.75), CFrame = cf * L(0, 5.45, 0), Color = hatColor, Material = Enum.Material.Fabric })
		part(m, { Name = "Pom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * L(0, 6.35, 0), Color = rgb(255, 255, 255), Material = Enum.Material.Fabric })
	end
	m.PrimaryPart = torso
	return m, head
end

local function billboard(adornee, title, subtitle, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Adornee = adornee
	gui.Parent = adornee
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0.6, 0)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = title
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Parent = gui
	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromScale(0, 0.6)
	s.Size = UDim2.new(1, 0, 0.4, 0)
	s.Font = Enum.Font.GothamMedium
	s.TextScaled = true
	s.Text = subtitle
	s.TextColor3 = rgb(255, 255, 255)
	s.TextStrokeTransparency = 0.4
	s.Parent = gui
	return gui
end

local STALLS = {
	SeedShop = {
		Title = "SEED SHOP",
		Npc = "Pip",
		Role = "Seed Keeper",
		Stripes = { rgb(120, 200, 100), rgb(255, 250, 235) },
		Wood = rgb(196, 140, 90),
		Shirt = rgb(110, 180, 90),
		Hat = rgb(235, 205, 130),
		HatStyle = "Straw",
		Prompt = "Browse seeds",
		Position = PLAZA + Vector3.new(0, 0, 24),
	},
	GearShop = {
		Title = "GEAR SHOP",
		Npc = "Bolt",
		Role = "Tinkerer",
		Stripes = { rgb(100, 160, 240), rgb(255, 250, 235) },
		Wood = rgb(170, 120, 85),
		Shirt = rgb(90, 140, 220),
		Hat = rgb(250, 190, 60),
		HatStyle = "Cap",
		Prompt = "Browse gear",
		Position = PLAZA + Vector3.new(0, 0, -24),
	},
	SellStand = {
		Title = "SELL STAND",
		Npc = "Marlow",
		Role = "Produce Buyer",
		Stripes = { rgb(250, 190, 60), rgb(255, 250, 235) },
		Wood = rgb(185, 130, 80),
		Shirt = rgb(230, 120, 80),
		Hat = rgb(200, 90, 120),
		HatStyle = "Beanie",
		Prompt = "Sell produce",
		Position = PLAZA + Vector3.new(-30, 0, 0),
	},
}

local function stallDisplay(f, cf, name)
	if name == "SeedShop" then
		for i = -2, 2 do
			local c = Color3.fromHSV((i + 2) * 0.17, 0.5, 1)
			part(f, { Name = "Packet", Size = Vector3.new(0.9, 1.2, 0.12), CFrame = cf * L(i * 1.4, 3.85, -3.1) * A(rad(-15), 0, 0), Color = c, CanCollide = false })
		end
		for _, x in ipairs({ -4.6, 4.6 }) do
			part(f, { Name = "Crate", Size = Vector3.new(1.8, 1, 1.4), CFrame = cf * L(x, 3.75, -3), Color = rgb(170, 120, 70), Material = Enum.Material.WoodPlanks, CanCollide = false })
			for k = -1, 1 do
				part(f, { Name = "Produce", Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), CFrame = cf * L(x + k * 0.5, 4.35, -3), Color = if x < 0 then rgb(255, 130, 30) else rgb(230, 40, 60), CanCollide = false })
			end
		end
	elseif name == "GearShop" then
		part(f, { Name = "Can", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 1, 1), CFrame = cf * L(-3, 4.1, -3) * A(0, 0, math.pi / 2), Color = rgb(90, 170, 255), Material = Enum.Material.Metal, CanCollide = false })
		part(f, { Name = "Spout", Size = Vector3.new(1.2, 0.2, 0.2), CFrame = cf * L(-2.1, 4.3, -3) * A(0, 0, rad(30)), Color = rgb(90, 170, 255), Material = Enum.Material.Metal, CanCollide = false })
		part(f, { Name = "SprinklerBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.2, 1.2), CFrame = cf * L(1, 3.4, -3) * A(0, 0, math.pi / 2), Color = rgb(200, 200, 210), Material = Enum.Material.Metal, CanCollide = false })
		part(f, { Name = "SprinklerHead", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * L(1, 4, -3), Color = rgb(255, 200, 80), CanCollide = false })
		part(f, { Name = "Trowel", Size = Vector3.new(0.3, 0.12, 1.6), CFrame = cf * L(3.6, 3.35, -3) * A(0, rad(30), 0), Color = rgb(200, 200, 210), Material = Enum.Material.Metal, CanCollide = false })
	else
		part(f, { Name = "ScaleBase", Size = Vector3.new(1.2, 0.8, 1.2), CFrame = cf * L(-3, 3.65, -3), Color = rgb(210, 70, 70), CanCollide = false })
		part(f, { Name = "ScalePlate", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1.8, 1.8), CFrame = cf * L(-3, 4.15, -3) * A(0, 0, math.pi / 2), Color = rgb(220, 220, 230), Material = Enum.Material.Metal, CanCollide = false })
		for i = 1, 6 do
			part(f, { Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.7, 0.7), CFrame = cf * L(2.5 + (i % 3) * 0.5, 3.3 + (i // 3) * 0.13, -3 + (i % 2) * 0.3) * A(0, 0, math.pi / 2), Color = rgb(255, 205, 60), Material = Enum.Material.Foil, CanCollide = false })
		end
	end
end

local function buildStall(parent, key)
	local def = STALLS[key]
	local f = folder(key, parent)
	local cf = CFrame.lookAt(def.Position, Vector3.new(PLAZA.X, def.Position.Y, PLAZA.Z))
	part(f, { Name = "Floor", Size = Vector3.new(15, 0.4, 10), CFrame = cf * L(0, 0.2, 0.5), Color = def.Wood:Lerp(rgb(0, 0, 0), 0.15), Material = Enum.Material.WoodPlanks })
	part(f, { Name = "Counter", Size = Vector3.new(12, 3, 1.6), CFrame = cf * L(0, 1.9, -3), Color = def.Wood, Material = Enum.Material.WoodPlanks })
	part(f, { Name = "CounterTop", Size = Vector3.new(12.6, 0.3, 2.1), CFrame = cf * L(0, 3.5, -3), Color = def.Wood:Lerp(rgb(255, 255, 255), 0.25), Material = Enum.Material.Wood })
	part(f, { Name = "Front", Size = Vector3.new(11.6, 1.6, 0.1), CFrame = cf * L(0, 2, -3.85), Color = def.Stripes[1] })
	for _, x in ipairs({ -6.8, 6.8 }) do
		for _, z in ipairs({ -3.9, 4.6 }) do
			part(f, { Name = "Post", Size = Vector3.new(0.6, 9.4, 0.6), CFrame = cf * L(x, 4.9, z), Color = def.Wood, Material = Enum.Material.Wood })
		end
	end
	part(f, { Name = "BackWall", Size = Vector3.new(13.6, 7, 0.4), CFrame = cf * L(0, 3.9, 4.6), Color = def.Wood:Lerp(rgb(255, 240, 220), 0.3), Material = Enum.Material.WoodPlanks })
	-- Striped awning, tilted down towards the customers.
	local stripes = 7
	for i = 1, stripes do
		local x = (i - (stripes + 1) / 2) * 2
		part(f, { Name = "Awning", Size = Vector3.new(2, 0.25, 10.4), CFrame = cf * L(x, 9.7, 0.2) * A(rad(-10), 0, 0), Color = def.Stripes[(i % 2) + 1], Material = Enum.Material.Fabric, CanCollide = false })
		part(f, { Name = "Scallop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 1.9, 1.9), CFrame = cf * L(x, 8.75, -5) * A(0, math.pi / 2, 0) * A(0, 0, 0), Color = def.Stripes[(i % 2) + 1], Material = Enum.Material.Fabric, CanCollide = false })
	end
	local sign = part(f, { Name = "Sign", Size = Vector3.new(11, 2.4, 0.4), CFrame = cf * L(0, 11.6, -4), Color = rgb(255, 248, 230), Material = Enum.Material.WoodPlanks })
	local signText = VillageBuilder.surfaceText(sign, Enum.NormalId.Front, def.Title, def.Stripes[1]:Lerp(rgb(0, 0, 0), 0.25))
	signText.TextStrokeTransparency = 1
	stallDisplay(f, cf, key)
	local npc, head = buildNpc(f, cf * L(0, 0.4, 0.9), def.Shirt, def.Hat, def.HatStyle)
	billboard(head, def.Npc, def.Role, def.Stripes[1]:Lerp(rgb(255, 255, 255), 0.2))

	local anchor = part(f, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = cf * L(0, 3, -4.5), Transparency = 1, CanCollide = false, CanQuery = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = def.Prompt
	prompt.ObjectText = def.Npc .. " - " .. def.Title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = anchor

	return {
		key = key,
		folder = f,
		cf = cf,
		npc = npc,
		position = (cf * L(0, 0, -6)).Position,
		standCFrame = cf * L(0, 3.5, -9) * A(0, math.pi, 0),
		prompt = prompt,
	}
end

---------------------------------------------------------------------------------------------
-- Decorations
---------------------------------------------------------------------------------------------

local function tree(parent, pos, rng)
	local h = 7 + rng:NextNumber() * 5
	local trunk = rgb(120, 82, 52)
	part(parent, { Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 1.4, 1.4), CFrame = L(pos.X, h / 2, pos.Z) * A(0, 0, math.pi / 2), Color = trunk, Material = Enum.Material.Wood })
	local green = Color3.fromHSV(0.25 + rng:NextNumber() * 0.08, 0.55, 0.65 + rng:NextNumber() * 0.15)
	local blossom = rng:NextNumber() < 0.25
	if blossom then
		green = rgb(255, 190, 215)
	end
	part(parent, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), CFrame = L(pos.X, h + 1.5, pos.Z), Color = green, Material = Enum.Material.Grass, CanCollide = false })
	part(parent, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), CFrame = L(pos.X + 2.4, h, pos.Z + 0.8), Color = green:Lerp(rgb(0, 0, 0), 0.08), Material = Enum.Material.Grass, CanCollide = false })
	part(parent, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), CFrame = L(pos.X - 2.2, h + 0.4, pos.Z - 1), Color = green:Lerp(rgb(255, 255, 255), 0.06), Material = Enum.Material.Grass, CanCollide = false })
end

local function lamp(parent, pos)
	part(parent, { Name = "LampPost", Size = Vector3.new(0.5, 9, 0.5), CFrame = L(pos.X, 4.5, pos.Z), Color = rgb(60, 90, 70), Material = Enum.Material.Metal })
	part(parent, { Name = "LampArm", Size = Vector3.new(0.3, 0.3, 1.6), CFrame = L(pos.X, 8.8, pos.Z - math.sign(pos.Z) * 0.7), Color = rgb(60, 90, 70), Material = Enum.Material.Metal })
	local bulb = part(parent, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = L(pos.X, 8.3, pos.Z - math.sign(pos.Z) * 1.4), Color = rgb(255, 225, 160), Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 0.9
	light.Color = rgb(255, 210, 150)
	light.Shadows = false
	light.Parent = bulb
end

local function flowerPatch(parent, center, rng)
	for _ = 1, 5 do
		local p = center + Vector3.new(rng:NextNumber(-1.6, 1.6), 0, rng:NextNumber(-0.8, 0.8))
		part(parent, { Name = "Stem", Size = Vector3.new(0.15, 1, 0.15), CFrame = L(p.X, 0.5, p.Z), Color = rgb(80, 150, 60), CanCollide = false })
		part(parent, { Name = "Bloom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = L(p.X, 1.05, p.Z), Color = Color3.fromHSV(rng:NextNumber(), 0.5, 1), CanCollide = false })
	end
end

local function fountain(parent, pos)
	local stone = rgb(214, 208, 196)
	part(parent, { Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 15, 15), CFrame = L(pos.X, 0.8, pos.Z) * A(0, 0, math.pi / 2), Color = stone, Material = Enum.Material.Limestone })
	local water = part(parent, { Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 13.4, 13.4), CFrame = L(pos.X, 1.55, pos.Z) * A(0, 0, math.pi / 2), Color = rgb(110, 190, 240), Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
	water.Reflectance = 0.2
	part(parent, { Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 1.6, 1.6), CFrame = L(pos.X, 3, pos.Z) * A(0, 0, math.pi / 2), Color = stone, Material = Enum.Material.Limestone })
	part(parent, { Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 5, 5), CFrame = L(pos.X, 5.2, pos.Z) * A(0, 0, math.pi / 2), Color = stone, Material = Enum.Material.Limestone })
	local top = part(parent, { Name = "Spout", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = L(pos.X, 6, pos.Z), Color = rgb(150, 210, 250), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(rgb(200, 235, 255))
	spray.Rate = 30
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Speed = NumberRange.new(6, 9)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -22, 0)
	spray.Size = NumberSequence.new(0.35)
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = top
end

local function windmill(parent, pos)
	local m = Instance.new("Model")
	m.Name = "Windmill"
	m.Parent = parent
	part(m, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(12, 9, 9), CFrame = L(pos.X, 6, pos.Z) * A(0, 0, math.pi / 2), Color = rgb(245, 236, 220), Material = Enum.Material.Plaster })
	part(m, { Name = "Upper", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 7, 7), CFrame = L(pos.X, 15, pos.Z) * A(0, 0, math.pi / 2), Color = rgb(245, 236, 220), Material = Enum.Material.Plaster })
	part(m, { Name = "Roof", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), CFrame = L(pos.X, 18.5, pos.Z), Color = rgb(200, 90, 80), Material = Enum.Material.ClayRoofTiles })
	part(m, { Name = "Door", Size = Vector3.new(0.4, 4, 2.6), CFrame = L(pos.X - 4.5, 2, pos.Z), Color = rgb(140, 90, 60), Material = Enum.Material.WoodPlanks })
	local blades = Instance.new("Model")
	blades.Name = "Blades"
	blades.Parent = m
	local hubCf = L(pos.X - 4.4, 15.5, pos.Z) * A(0, math.pi / 2, 0)
	local hub = part(blades, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.6, 1.6), CFrame = hubCf * A(0, math.pi / 2, 0), Color = rgb(120, 80, 50), Material = Enum.Material.Wood, CanCollide = false })
	for i = 0, 3 do
		local a = i * math.pi / 2
		part(blades, { Name = "Blade", Size = Vector3.new(1.6, 10, 0.2), CFrame = hubCf * A(0, 0, a) * L(0, 5.6, 0.3), Color = rgb(250, 245, 235), Material = Enum.Material.Fabric, CanCollide = false })
	end
	blades.PrimaryPart = hub
	return blades
end

local function cloud(parent, pos, rng)
	local m = Instance.new("Model")
	m.Name = "Cloud"
	m.Parent = parent
	for i = 1, 4 do
		local d = 10 + rng:NextNumber() * 8
		part(m, { Name = "Puff", Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d), CFrame = L(pos.X + (i - 2.5) * 8, pos.Y + rng:NextNumber() * 3, pos.Z + rng:NextNumber(-3, 3)), Color = rgb(255, 255, 255), Material = Enum.Material.SmoothPlastic, Transparency = 0.08, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	return m
end

local function leaderboard(parent, pos)
	local f = folder("Leaderboard", parent)
	local cf = CFrame.lookAt(pos, Vector3.new(PLAZA.X, pos.Y, PLAZA.Z))
	for _, x in ipairs({ -6.5, 6.5 }) do
		part(f, { Name = "Post", Size = Vector3.new(0.8, 14, 0.8), CFrame = cf * L(x, 7, 0.4), Color = rgb(150, 100, 60), Material = Enum.Material.Wood })
	end
	local board = part(f, { Name = "Board", Size = Vector3.new(13, 11, 0.5), CFrame = cf * L(0, 8, 0), Color = rgb(70, 110, 70), Material = Enum.Material.WoodPlanks })
	part(f, { Name = "Roof", Size = Vector3.new(14.5, 0.5, 2.2), CFrame = cf * L(0, 13.9, 0), Color = rgb(200, 90, 80) })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.1
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "TOP GARDENERS - Total Coins Earned"
	title.TextColor3 = rgb(255, 230, 140)
	title.Parent = gui
	local rows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0.05, 0, 0.15 + (i - 1) * 0.083, 0)
		row.Size = UDim2.new(0.9, 0, 0.075, 0)
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1 then rgb(255, 215, 80) elseif i == 2 then rgb(220, 225, 235) elseif i == 3 then rgb(235, 165, 110) else rgb(240, 245, 235)
		row.Text = string.format("%d.  ---", i)
		row.Parent = gui
		rows[i] = row
	end
	return { board = board, rows = rows, title = title }
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

function VillageBuilder.plotCFrame(id)
	local xs = { -36, 0, 36 }
	local column = ((id - 1) % 3) + 1
	if id <= 3 then
		return L(xs[column], 0, 22)
	end
	return L(xs[column], 0, -22) * A(0, math.pi, 0)
end

function VillageBuilder.build()
	local root = workspace:FindFirstChild("Village")
	if root then
		root:Destroy()
	end
	root = folder("Village", workspace)
	local rng = Rng.new(2024)

	part(root, { Name = "Ground", Size = Vector3.new(420, 2, 320), CFrame = L(-20, -1, 0), Color = rgb(112, 184, 82), Material = Enum.Material.Grass })
	part(root, { Name = "Street", Size = Vector3.new(170, 0.3, 34), CFrame = L(-5, -0.08, 0), Color = rgb(214, 196, 162), Material = Enum.Material.Cobblestone })
	part(root, { Name = "Plaza", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 74, 74), CFrame = L(PLAZA.X, -0.07, PLAZA.Z) * A(0, 0, math.pi / 2), Color = rgb(222, 206, 174), Material = Enum.Material.Cobblestone })
	-- Invisible walls at the edge of the world.
	for _, w in ipairs({ { L(-20, 20, 160), Vector3.new(420, 40, 2) }, { L(-20, 20, -160), Vector3.new(420, 40, 2) }, { L(190, 20, 0), Vector3.new(2, 40, 320) }, { L(-230, 20, 0), Vector3.new(2, 40, 320) } }) do
		part(root, { Name = "Boundary", Size = w[2], CFrame = w[1], Transparency = 1, CanQuery = false })
	end

	local plotsFolder = folder("Plots", root)
	local plots = {}
	for id = 1, PLOT.Count do
		plots[id] = buildPlot(plotsFolder, id, VillageBuilder.plotCFrame(id))
	end

	local stallFolder = folder("Stalls", root)
	local stalls = {}
	for _, key in ipairs({ "SeedShop", "GearShop", "SellStand" }) do
		stalls[key] = buildStall(stallFolder, key)
	end

	local decor = folder("Decor", root)
	fountain(decor, PLAZA)
	-- Lamps and flowers line the street between the garden gates (gates at x = -36, 0, 36).
	for _, x in ipairs({ -54, -18, 18, 54 }) do
		lamp(decor, Vector3.new(x, 0, 18.5))
		lamp(decor, Vector3.new(x, 0, -18.5))
	end
	for _, x in ipairs({ -64, -48, -26, -10, 10, 26, 48, 64 }) do
		flowerPatch(decor, Vector3.new(x, 0, 16.5), rng)
		flowerPatch(decor, Vector3.new(x, 0, -16.5), rng)
	end
	for _ = 1, 26 do
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		tree(decor, Vector3.new(rng:NextNumber(-200, 160), 0, side * rng:NextNumber(84, 140)), rng)
	end
	for _ = 1, 8 do
		tree(decor, Vector3.new(rng:NextNumber(-205, -140), 0, rng:NextNumber(-70, 70)), rng)
	end
	local blades = windmill(decor, Vector3.new(84, 0, 0))
	local clouds = {}
	local cloudFolder = folder("Clouds", root)
	for i = 1, 8 do
		clouds[i] = cloud(cloudFolder, Vector3.new(rng:NextNumber(-220, 180), 110 + rng:NextNumber() * 30, rng:NextNumber(-150, 150)), rng)
	end
	local board = leaderboard(root, PLAZA + Vector3.new(-22, 0, -24))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "VillageSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = L(PLAZA.X + 22, 0.2, PLAZA.Z)
	spawn.Color = rgb(255, 230, 170)
	spawn.Material = Enum.Material.Pebble
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root

	return {
		folder = root,
		plots = plots,
		stalls = stalls,
		board = board,
		spawn = spawn,
		blades = blades,
		clouds = clouds,
		plaza = PLAZA,
	}
end

return VillageBuilder
