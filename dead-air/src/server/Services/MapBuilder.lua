--[[
	MapBuilder - turns a MazeGen layout into the physical facility.

	Everything is built from Parts at runtime (no external models needed), using a muted
	liminal palette: yellowed plaster, mustard carpet, dirty-white ceilings, grey service
	areas, faded green restrooms, buzzing fluorescent fixtures.

	Navigation rule: every cell keeps a clear cross-shaped lane through its centre, and all
	doorways sit on that lane. Props only occupy the four corner quadrants, so every run stays
	walkable for players and for the Listener's pathfinding.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MapConfig = require(Shared.Config.MapConfig)
local MazeGen = require(Shared.MazeGen)

local MapBuilder = {}

local Map = {}
Map.__index = Map

---------------------------------------------------------------------------------------------
-- Palette / materials
---------------------------------------------------------------------------------------------

local function material(name, fallback)
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	if ok and value then
		return value
	end
	return Enum.Material[fallback]
end

local MAT = {
	Carpet = material("Carpet", "Fabric"),
	Tile = material("CeramicTiles", "SmoothPlastic"),
	Concrete = Enum.Material.Concrete,
	Metal = Enum.Material.DiamondPlate,
	Plaster = material("Plaster", "SmoothPlastic"),
	Cardboard = material("Cardboard", "Wood"),
	Fabric = Enum.Material.Fabric,
	Smooth = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	MetalPlain = Enum.Material.Metal,
	Wood = Enum.Material.Wood,
	Glass = Enum.Material.Glass,
}

local rgb = Color3.fromRGB

local WALL_COLORS = {
	Office = rgb(201, 186, 129),
	Hallway = rgb(206, 192, 136),
	Start = rgb(196, 184, 140),
	Anomaly = rgb(206, 190, 128),
	BreakRoom = rgb(196, 182, 128),
	Storage = rgb(172, 166, 140),
	Maintenance = rgb(128, 130, 122),
	PowerRoom = rgb(118, 122, 116),
	Exit = rgb(112, 114, 110),
	Restroom = rgb(170, 186, 160),
	Security = rgb(156, 164, 148),
}

local FLOOR_COLORS = {
	Carpet = rgb(122, 108, 70),
	Tile = rgb(188, 184, 166),
	Concrete = rgb(118, 116, 110),
	Metal = rgb(96, 98, 96),
}

local CEILING_COLOR = rgb(212, 206, 184)
local LIGHT_EMERGENCY = rgb(255, 206, 140)
local LIGHT_POWER = rgb(255, 242, 214)
local TUBE_ON = rgb(255, 248, 226)
local TUBE_OFF = rgb(70, 68, 60)

local CS = MapConfig.CellSize
local WT = MapConfig.WallThickness

---------------------------------------------------------------------------------------------
-- Part helpers
---------------------------------------------------------------------------------------------

local function newPart(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = MAT.Smooth
	for key, value in pairs(props) do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function occluder(p, kind)
	p:SetAttribute("Occluder", kind)
	return p
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

---------------------------------------------------------------------------------------------
-- Map object
---------------------------------------------------------------------------------------------

function Map:cellCenter(index)
	local cell = self.layout.cells[index]
	return Vector3.new((cell.x + 0.5) * CS, 0, (cell.y + 0.5) * CS)
end

function Map:cellAt(position)
	local x = math.floor(position.X / CS)
	local y = math.floor(position.Z / CS)
	if x < 0 or y < 0 or x >= self.layout.width or y >= self.layout.height then
		return nil
	end
	return y * self.layout.width + x + 1
end

function Map:cellHeight(index)
	local cell = self.layout.cells[index]
	if cell.variant == "TallRoom" then
		return MapConfig.TallRoomHeight
	end
	return MapConfig.WallHeight
end

function Map:isLit(index)
	local light = self.lights[index]
	return light ~= nil and light.on
end

local function applyLight(entry, on, powered)
	entry.on = on
	entry.light.Enabled = on
	entry.tube.Color = if on then TUBE_ON else TUBE_OFF
	entry.tube.Material = if on then MAT.Neon else MAT.Smooth
	if on then
		entry.light.Color = if powered then LIGHT_POWER else LIGHT_EMERGENCY
		entry.light.Brightness = if powered then 1.3 else 0.9
		entry.light.Range = if powered then 28 else 23
	end
	entry.tube:SetAttribute("On", on)
	-- Clients flicker lights locally relative to this value.
	entry.tube:SetAttribute("BaseBrightness", entry.light.Brightness)
end

function Map:setPower(on)
	self.powered = on
	for index, entry in pairs(self.lights) do
		local cell = self.layout.cells[index]
		local shouldBeOn = on or cell.lit
		entry.baseOn = shouldBeOn
		if not entry.overridden then
			applyLight(entry, shouldBeOn, on)
		end
	end
	for _, screen in ipairs(self.screens) do
		screen.Enabled = on
	end
	self.folder:SetAttribute("Powered", on)
end

-- Temporarily forces lights in the given cells off (horror event), restoring afterwards.
function Map:blackout(cellIndices, duration)
	for _, index in ipairs(cellIndices) do
		local entry = self.lights[index]
		if entry then
			entry.overridden = true
			applyLight(entry, false, self.powered)
		end
	end
	task.delay(duration, function()
		if not self.folder.Parent then
			return
		end
		for _, index in ipairs(cellIndices) do
			local entry = self.lights[index]
			if entry then
				entry.overridden = false
				applyLight(entry, entry.baseOn, self.powered)
			end
		end
	end)
end

function Map:destroy()
	if self.folder then
		self.folder:Destroy()
	end
end

---------------------------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------------------------

-- Builds a wall on a plane. runAxis "Z": the wall lies at X = fixed, spanning Z from..to.
-- runAxis "X": the wall lies at Z = fixed, spanning X from..to.
local function buildWall(parent, runAxis, fixed, from, to, height, opening, color, mat)
	local function segment(a, b, y0, y1)
		local len = b - a
		local h = y1 - y0
		if len <= 0.05 or h <= 0.05 then
			return
		end
		local mid = (a + b) / 2
		local size, pos
		if runAxis == "Z" then
			size = Vector3.new(WT, h, len)
			pos = Vector3.new(fixed, y0 + h / 2, mid)
		else
			size = Vector3.new(len, h, WT)
			pos = Vector3.new(mid, y0 + h / 2, fixed)
		end
		occluder(newPart(parent, { Name = "Wall", Size = size, Position = pos, Color = color, Material = mat }), "Wall")
	end

	if not opening then
		segment(from, to, 0, height)
		return nil
	end
	local mid = (from + to) / 2
	local half = opening.width / 2
	segment(from, mid - half, 0, height)
	segment(mid + half, to, 0, height)
	segment(mid - half, mid + half, opening.height, height)
	if runAxis == "Z" then
		return Vector3.new(fixed, 0, mid)
	end
	return Vector3.new(mid, 0, fixed)
end

---------------------------------------------------------------------------------------------
-- Props (all fit inside a ~8x8 quadrant footprint)
---------------------------------------------------------------------------------------------

local Props = {}

---------------------------------------------------------------------------------------------
-- Searchable containers (two-door cabinets you open and close by hand)
---------------------------------------------------------------------------------------------

-- Set by MapBuilder.build while a cell is being furnished; nil = do not register containers.
local containerSink, containerCell
local containerCounter = 0

local function registerContainer(record)
	if not containerSink then
		return
	end
	containerCounter += 1
	record.id = "Container" .. containerCounter
	record.cell = containerCell
	record.position = record.promptPart.Position
	table.insert(containerSink, record)
end

-- Vintage painted furniture (distressed turquoise, like an old shop counter). Fronts face the
-- lane (local -Z). Items are placed inside by ItemService and are only visible / reachable
-- while the furniture is open.

local PAINT = rgb(58, 136, 146)
local PAINT_DARK = rgb(40, 102, 112)
local PAINT_WORN = rgb(118, 176, 172)
local BARE_WOOD = rgb(92, 74, 56)
local PULL = rgb(46, 74, 66)

local function weldTo(base, part)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
end

-- Chipped paint: a few flat patches of bare wood and lighter worn paint on a face.
local function weather(m, faceCF, width, height, rng, base)
	for _ = 1, 4 do
		local patch = newPart(m, {
			Name = "Wear",
			Size = Vector3.new(rng:range(0.08, 0.3) * width / 2, rng:range(0.04, 0.12) * height, 0.02),
			CFrame = faceCF * CFrame.new(rng:range(-0.4, 0.4) * width, rng:range(-0.35, 0.35) * height, -0.01),
			Color = if rng:chance(0.45) then BARE_WOOD else PAINT_WORN,
			Material = MAT.Wood,
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		if base then
			weldTo(base, patch)
		end
	end
end

local function pullHandle(m, cf, base)
	local bar = newPart(m, { Name = "Pull", Size = Vector3.new(0.6, 0.1, 0.1), CFrame = cf * CFrame.new(0, 0, -0.14), Color = PULL, Material = MAT.MetalPlain, CanCollide = false })
	for _, x in ipairs({ -0.26, 0.26 }) do
		local post = newPart(m, { Name = "PullPost", Size = Vector3.new(0.08, 0.08, 0.14), CFrame = cf * CFrame.new(x, 0, -0.07), Color = PULL, Material = MAT.MetalPlain, CanCollide = false })
		if base then
			weldTo(base, post)
		end
	end
	if base then
		weldTo(base, bar)
	end
end

-- Low vintage chest with four drawers (2 x 2). Opening slides all four out; the item rides
-- out in one of them.
function Props.storageCabinet(parent, cf, rng)
	local m = model(parent, "DrawerChest")
	local w, d = 5.2, 2.6
	local legH, bodyH = 0.5, 2.1
	local top = legH + bodyH
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			newPart(m, { Name = "Leg", Size = Vector3.new(0.45, legH + 0.1, 0.45), CFrame = cf * CFrame.new(x * (w / 2 - 0.25), legH / 2, z * (d / 2 - 0.25)), Color = PAINT_DARK, Material = MAT.Wood })
		end
	end
	occluder(newPart(m, { Name = "Carcass", Size = Vector3.new(w, bodyH, d - 0.25), CFrame = cf * CFrame.new(0, legH + bodyH / 2, 0.12), Color = PAINT, Material = MAT.Wood }), "Prop")
	-- Thick worn top with a slight overhang.
	newPart(m, { Name = "Top", Size = Vector3.new(w + 0.3, 0.22, d + 0.25), CFrame = cf * CFrame.new(0, top + 0.11, 0), Color = rgb(96, 120, 116), Material = MAT.Wood })
	-- Face frame: rails and the centre stile between the drawers.
	local faceZ = -d / 2 + 0.06
	newPart(m, { Name = "Stile", Size = Vector3.new(0.22, bodyH, 0.14), CFrame = cf * CFrame.new(0, legH + bodyH / 2, faceZ), Color = PAINT_DARK, Material = MAT.Wood })
	newPart(m, { Name = "Rail", Size = Vector3.new(w, 0.16, 0.14), CFrame = cf * CFrame.new(0, legH + bodyH / 2, faceZ), Color = PAINT_DARK, Material = MAT.Wood })
	newPart(m, { Name = "Apron", Size = Vector3.new(w, 0.22, 0.16), CFrame = cf * CFrame.new(0, legH + 0.11, faceZ), Color = PAINT_DARK, Material = MAT.Wood })
	weather(m, cf * CFrame.new(0, top - 0.3, faceZ - 0.08), w, 0.3, rng)

	local dw, dh, dd = w / 2 - 0.25, bodyH / 2 - 0.22, d - 0.5
	local slide = 1.5
	local parts = {}
	local drawers = {}
	for row = 0, 1 do
		for col = -1, 1, 2 do
			local y = legH + 0.25 + dh / 2 + row * (dh + 0.2)
			local frontCF = cf * CFrame.new(col * (w / 4), y, faceZ - 0.02)
			local front = newPart(m, { Name = "DrawerFront", Size = Vector3.new(dw, dh, 0.16), CFrame = frontCF, Color = PAINT, Material = MAT.Wood })
			occluder(front, "Door")
			-- Drawer box behind the front (moves with it).
			local boxCF = frontCF * CFrame.new(0, -dh / 2 + 0.08, dd / 2)
			local bottom = newPart(m, { Name = "DrawerBottom", Size = Vector3.new(dw - 0.15, 0.08, dd), CFrame = boxCF, Color = BARE_WOOD, Material = MAT.Wood, CanCollide = false })
			weldTo(front, bottom)
			for _, sx in ipairs({ -1, 1 }) do
				local side = newPart(m, { Name = "DrawerSide", Size = Vector3.new(0.08, dh - 0.15, dd), CFrame = frontCF * CFrame.new(sx * (dw / 2 - 0.12), -0.05, dd / 2), Color = BARE_WOOD, Material = MAT.Wood, CanCollide = false })
				weldTo(front, side)
			end
			pullHandle(m, frontCF * CFrame.new(0, 0.05, 0), front)
			weather(m, frontCF * CFrame.new(0, 0, -0.09), dw, dh, rng, front)
			table.insert(parts, { part = front, closedCFrame = frontCF, openCFrame = frontCF * CFrame.new(0, 0, -slide) })
			table.insert(drawers, boxCF)
		end
	end
	local promptPart = newPart(m, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, legH + bodyH / 2, -d / 2 - 0.5), Transparency = 1, CanCollide = false, CanQuery = false })
	local chosen = rng:pick(drawers)
	registerContainer({
		label = "Drawer Chest",
		openNoise = "DrawerOpen",
		closeNoise = "DrawerClose",
		actionOpen = "Open drawers",
		actionClose = "Close drawers",
		parts = parts,
		promptPart = promptPart,
		itemSpot = (chosen * CFrame.new(0, 0.05, 0)).Position,
		-- The item rides out with its drawer and lies flat to fit.
		itemShift = (cf * CFrame.new(0, 0, -slide)).Position - cf.Position,
		layFlat = true,
	})
	return (cf * CFrame.new(1.4, top + 0.22, 0)).Position
end

-- Tall vintage sideboard: a row of small (decorative) drawers over two doors you open by hand.
function Props.tallCabinet(parent, cf, rng)
	local m = model(parent, "Sideboard")
	local w, h, d = 4.6, 5.2, 2.2
	local legH = 0.45
	for _, x in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			newPart(m, { Name = "Leg", Size = Vector3.new(0.4, legH + 0.1, 0.4), CFrame = cf * CFrame.new(x * (w / 2 - 0.22), legH / 2, z * (d / 2 - 0.22)), Color = PAINT_DARK, Material = MAT.Wood })
		end
	end
	local bodyH = h - legH
	local function body(name, size, offset, color)
		return occluder(newPart(m, { Name = name, Size = size, CFrame = cf * offset, Color = color or PAINT, Material = MAT.Wood }), "Prop")
	end
	body("Back", Vector3.new(w, bodyH, 0.15), CFrame.new(0, legH + bodyH / 2, d / 2 - 0.08))
	for _, sx in ipairs({ -1, 1 }) do
		body("Side", Vector3.new(0.15, bodyH, d), CFrame.new(sx * (w / 2 - 0.08), legH + bodyH / 2, 0))
	end
	newPart(m, { Name = "Top", Size = Vector3.new(w + 0.25, 0.2, d + 0.2), CFrame = cf * CFrame.new(0, h + 0.1, 0), Color = rgb(96, 120, 116), Material = MAT.Wood })
	newPart(m, { Name = "Bottom", Size = Vector3.new(w, 0.15, d), CFrame = cf * CFrame.new(0, legH + 0.08, 0), Color = PAINT_DARK, Material = MAT.Wood })
	-- Dark interior so the shelf contents read when the doors open.
	newPart(m, { Name = "Interior", Size = Vector3.new(w - 0.32, bodyH - 1.3, 0.05), CFrame = cf * CFrame.new(0, legH + (bodyH - 1.1) / 2, d / 2 - 0.2), Color = rgb(52, 40, 30), Material = MAT.Wood, CanCollide = false })
	local shelfY = legH + 1.9
	newPart(m, { Name = "Shelf", Size = Vector3.new(w - 0.3, 0.1, d - 0.3), CFrame = cf * CFrame.new(0, shelfY, 0.1), Color = BARE_WOOD, Material = MAT.Wood })
	-- Top row of four small drawers (decorative).
	local faceZ = -d / 2 + 0.06
	local rowY = h - 0.55
	newPart(m, { Name = "DrawerRow", Size = Vector3.new(w, 1.1, 0.12), CFrame = cf * CFrame.new(0, rowY, faceZ), Color = PAINT_DARK, Material = MAT.Wood })
	for k = 0, 3 do
		local x = -w / 2 + w / 8 + k * (w / 4)
		local frontCF = cf * CFrame.new(x, rowY, faceZ - 0.08)
		newPart(m, { Name = "SmallDrawer", Size = Vector3.new(w / 4 - 0.15, 0.8, 0.1), CFrame = frontCF, Color = PAINT, Material = MAT.Wood })
		pullHandle(m, frontCF * CFrame.new(0, 0, 0.04))
	end
	weather(m, cf * CFrame.new(0, rowY, faceZ - 0.14), w, 0.8, rng)
	-- Two doors below.
	local doorH = bodyH - 1.35
	local doors = {}
	for _, sx in ipairs({ -1, 1 }) do
		local hinge = cf * CFrame.new(sx * (w / 2 - 0.05), legH + 0.15 + doorH / 2, -d / 2 + 0.05)
		-- Doors meet in the middle so nothing on the shelf shows through the seam.
		local door = newPart(m, {
			Name = "Door",
			Size = Vector3.new(w / 2 - 0.06, doorH + 0.15, 0.12),
			CFrame = hinge * CFrame.new(-sx * (w / 4 - 0.02), 0.07, 0),
			Color = PAINT,
			Material = MAT.Wood,
		})
		occluder(door, "Door")
		-- Raised panel and a vertical pull near the centre seam.
		local panel = newPart(m, { Name = "Panel", Size = Vector3.new(w / 2 - 0.6, doorH - 0.6, 0.06), CFrame = door.CFrame * CFrame.new(0, 0, -0.08), Color = PAINT_DARK, Material = MAT.Wood, CanCollide = false })
		weldTo(door, panel)
		local pull = newPart(m, { Name = "Pull", Size = Vector3.new(0.1, 0.55, 0.1), CFrame = hinge * CFrame.new(-sx * (w / 2 - 0.3), 0, -0.14), Color = PULL, Material = MAT.MetalPlain, CanCollide = false })
		weldTo(door, pull)
		weather(m, door.CFrame * CFrame.new(0, 0, -0.07), w / 2 - 0.1, doorH, rng, door)
		local offset = hinge:ToObjectSpace(door.CFrame)
		table.insert(doors, { part = door, closedCFrame = door.CFrame, openCFrame = hinge * CFrame.Angles(0, math.rad(sx * 105), 0) * offset })
	end
	local promptPart = newPart(m, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 2.6, -d / 2 - 0.4), Transparency = 1, CanCollide = false, CanQuery = false })
	registerContainer({
		label = "Sideboard",
		openNoise = "CabinetOpen",
		closeNoise = "CabinetClose",
		actionOpen = "Open",
		actionClose = "Close",
		parts = doors,
		promptPart = promptPart,
		itemSpot = (cf * CFrame.new(0, shelfY + 0.05, 0.05)).Position,
	})
	return (cf * CFrame.new(0.8, h + 0.2, 0)).Position
end

function Props.desk(parent, cf, rng)
	local m = model(parent, "Desk")
	local wood = rgb(140, 118, 84)
	newPart(m, { Name = "Top", Size = Vector3.new(5, 0.3, 2.6), CFrame = cf * CFrame.new(0, 3, 0), Color = wood, Material = MAT.Wood })
	newPart(m, { Name = "SideL", Size = Vector3.new(0.3, 2.85, 2.4), CFrame = cf * CFrame.new(-2.3, 1.43, 0), Color = wood, Material = MAT.Wood })
	newPart(m, { Name = "SideR", Size = Vector3.new(0.3, 2.85, 2.4), CFrame = cf * CFrame.new(2.3, 1.43, 0), Color = wood, Material = MAT.Wood })
	local chairCf = cf * CFrame.new(rng:range(-1, 1), 0, 2.4) * CFrame.Angles(0, math.rad(rng:range(-30, 30)), 0)
	Props.chair(m, chairCf)
	if rng:chance(0.5) then
		-- CRT monitor
		newPart(m, { Name = "Monitor", Size = Vector3.new(1.6, 1.4, 1.4), CFrame = cf * CFrame.new(-1.2, 3.85, -0.3), Color = rgb(190, 184, 160) })
	end
	return (cf * CFrame.new(1.2, 3.25, 0)).Position
end

function Props.chair(parent, cf, upsideDown)
	local m = model(parent, "Chair")
	local fabric = rgb(92, 98, 112)
	local base = if upsideDown then cf * CFrame.Angles(math.pi, 0, 0) else cf
	newPart(m, { Name = "Seat", Size = Vector3.new(1.8, 0.3, 1.8), CFrame = base * CFrame.new(0, 1.8, 0), Color = fabric, Material = MAT.Fabric, CanCollide = false })
	newPart(m, { Name = "Back", Size = Vector3.new(1.8, 2, 0.25), CFrame = base * CFrame.new(0, 2.9, 0.85), Color = fabric, Material = MAT.Fabric, CanCollide = false })
	newPart(m, { Name = "Post", Size = Vector3.new(0.3, 1.7, 0.3), CFrame = base * CFrame.new(0, 0.85, 0), Color = rgb(40, 40, 40), CanCollide = false })
	return m
end

function Props.partition(parent, cf)
	local p = newPart(parent, { Name = "Partition", Size = Vector3.new(7, 5, 0.3), CFrame = cf * CFrame.new(0, 2.5, 3.2), Color = rgb(150, 150, 140), Material = MAT.Fabric })
	occluder(p, "Prop")
end

function Props.cubicle(parent, cf, rng)
	Props.partition(parent, cf)
	return Props.desk(parent, cf * CFrame.new(0, 0, -1.4), rng)
end

function Props.shelf(parent, cf, rng)
	local m = model(parent, "Shelf")
	local metal = rgb(110, 112, 108)
	newPart(m, { Size = Vector3.new(0.3, 7, 2.4), CFrame = cf * CFrame.new(-3, 3.5, 0), Color = metal, Material = MAT.MetalPlain })
	newPart(m, { Size = Vector3.new(0.3, 7, 2.4), CFrame = cf * CFrame.new(3, 3.5, 0), Color = metal, Material = MAT.MetalPlain })
	for _, y in ipairs({ 0.4, 2.7, 5.0 }) do
		newPart(m, { Size = Vector3.new(6, 0.2, 2.4), CFrame = cf * CFrame.new(0, y, 0), Color = metal, Material = MAT.MetalPlain })
	end
	local back = newPart(m, { Name = "Back", Size = Vector3.new(6, 7, 0.1), CFrame = cf * CFrame.new(0, 3.5, 1.15), Color = metal, Material = MAT.MetalPlain })
	occluder(back, "Prop")
	for _ = 1, rng:integer(1, 4) do
		local y = rng:pick({ 0.5, 2.8, 5.1 })
		local size = Vector3.new(rng:range(1, 1.8), rng:range(0.8, 1.6), rng:range(1, 1.8))
		newPart(m, {
			Name = "Box",
			Size = size,
			CFrame = cf * CFrame.new(rng:range(-2, 2), y + size.Y / 2, 0) * CFrame.Angles(0, math.rad(rng:range(-15, 15)), 0),
			Color = rgb(160, 132, 92),
			Material = MAT.Cardboard,
			CanCollide = false,
		})
	end
	return (cf * CFrame.new(rng:range(-1.5, 1.5), 2.95, -0.3)).Position
end

function Props.crates(parent, cf, rng)
	local m = model(parent, "Crates")
	local color = rgb(96, 102, 94)
	local a = newPart(m, { Size = Vector3.new(3.2, 3.2, 3.2), CFrame = cf * CFrame.new(-1.2, 1.6, 0), Color = color, Material = MAT.MetalPlain })
	occluder(a, "Prop")
	if rng:chance(0.6) then
		newPart(m, { Size = Vector3.new(2.6, 2.6, 2.6), CFrame = cf * CFrame.new(-1.2, 4.5, 0) * CFrame.Angles(0, math.rad(rng:range(-20, 20)), 0), Color = color, Material = MAT.MetalPlain })
	end
	newPart(m, { Size = Vector3.new(2.4, 1.8, 2.4), CFrame = cf * CFrame.new(2, 0.9, 0.5), Color = rgb(150, 124, 86), Material = MAT.Cardboard })
	return (cf * CFrame.new(2, 1.85, 0.5)).Position
end

function Props.pipes(parent, cf, height)
	local m = model(parent, "Pipes")
	for i, x in ipairs({ -2.5, -1.2, 0.6 }) do
		newPart(m, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 0.6 + i * 0.15, 0.6 + i * 0.15),
			CFrame = cf * CFrame.new(x, height / 2, -3.2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(120, 104, 86),
			Material = MAT.MetalPlain,
			CanCollide = false,
		})
	end
	return m
end

function Props.workbench(parent, cf, rng)
	local m = model(parent, "Workbench")
	newPart(m, { Size = Vector3.new(6, 0.4, 2.6), CFrame = cf * CFrame.new(0, 3, -1.5), Color = rgb(88, 90, 86), Material = MAT.MetalPlain })
	newPart(m, { Size = Vector3.new(5.6, 2.8, 2.2), CFrame = cf * CFrame.new(0, 1.4, -1.5), Color = rgb(70, 72, 70), Material = MAT.MetalPlain })
	if rng:chance(0.5) then
		newPart(m, { Name = "Toolbox", Size = Vector3.new(1.8, 0.9, 0.9), CFrame = cf * CFrame.new(-1.6, 3.65, -1.5), Color = rgb(160, 40, 36), Material = MAT.MetalPlain })
	end
	return (cf * CFrame.new(1.2, 3.45, -1.5)).Position
end

function Props.cooler(parent, cf)
	local m = model(parent, "WaterCooler")
	newPart(m, { Size = Vector3.new(1.4, 3.4, 1.4), CFrame = cf * CFrame.new(0, 1.7, -2), Color = rgb(210, 208, 200) })
	newPart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.2, 1.2), CFrame = cf * CFrame.new(0, 4.2, -2) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(150, 190, 210), Material = MAT.Glass, Transparency = 0.4, CanCollide = false })
	return (cf * CFrame.new(0, 0.2, 0)).Position
end

function Props.bench(parent, cf)
	newPart(parent, { Name = "Bench", Size = Vector3.new(6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 0.8, -2), Color = rgb(110, 92, 70), Material = MAT.Wood })
	return (cf * CFrame.new(1.5, 1.75, -2)).Position
end

function Props.plant(parent, cf)
	local m = model(parent, "DeadPlant")
	newPart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(120, 80, 60) })
	newPart(m, { Size = Vector3.new(0.2, 3, 0.2), CFrame = cf * CFrame.new(0, 3, 0) * CFrame.Angles(0.2, 0, 0.15), Color = rgb(96, 88, 60), CanCollide = false })
	return nil
end

function Props.stall(parent, cf)
	local m = model(parent, "Stall")
	local color = rgb(150, 168, 150)
	newPart(m, { Size = Vector3.new(0.25, 6, 4), CFrame = cf * CFrame.new(-2, 3.2, -1), Color = color })
	newPart(m, { Size = Vector3.new(0.25, 6, 4), CFrame = cf * CFrame.new(2, 3.2, -1), Color = color })
	local door = newPart(m, { Size = Vector3.new(3.75, 6, 0.2), CFrame = cf * CFrame.new(0, 3.2, 1) * CFrame.Angles(0, math.rad(25), 0), Color = color })
	occluder(door, "Prop")
	return (cf * CFrame.new(0, 0.2, -1)).Position
end

function Props.sink(parent, cf)
	newPart(parent, { Name = "Sink", Size = Vector3.new(3, 3, 2), CFrame = cf * CFrame.new(0, 1.5, -2.5), Color = rgb(220, 220, 212) })
	return (cf * CFrame.new(0, 3.15, -2.5)).Position
end

function Props.table(parent, cf, rng)
	local m = model(parent, "Table")
	newPart(m, { Size = Vector3.new(4.5, 0.3, 3), CFrame = cf * CFrame.new(0, 3, 0), Color = rgb(196, 196, 188) })
	newPart(m, { Size = Vector3.new(0.5, 2.85, 0.5), CFrame = cf * CFrame.new(0, 1.43, 0), Color = rgb(60, 60, 60) })
	Props.chair(m, cf * CFrame.new(-1.2, 0, 2.2) * CFrame.Angles(0, math.rad(rng:range(-40, 40)), 0))
	Props.chair(m, cf * CFrame.new(1.2, 0, -2.2) * CFrame.Angles(0, math.rad(180 + rng:range(-40, 40)), 0))
	return (cf * CFrame.new(0.8, 3.25, 0)).Position
end

function Props.vending(parent, cf)
	local m = model(parent, "Vending")
	local body = newPart(m, { Size = Vector3.new(3.6, 7, 2.6), CFrame = cf * CFrame.new(0, 3.5, -2), Color = rgb(120, 40, 36) })
	occluder(body, "Prop")
	newPart(m, { Size = Vector3.new(2.6, 4, 0.1), CFrame = cf * CFrame.new(-0.3, 4.2, -0.68), Color = rgb(180, 200, 190), Material = MAT.Neon, Transparency = 0.55, CanCollide = false })
	return nil
end

local PROPS_BY_KIND = {
	Office = { { "cubicle", 4 }, { "desk", 2 }, { "tallCabinet", 3 }, { "storageCabinet", 3 }, { "plant", 1 } },
	Hallway = { { "cooler", 1 }, { "bench", 2 }, { "plant", 1 }, { "desk", 1 }, { "storageCabinet", 2 }, { "tallCabinet", 1 } },
	Storage = { { "shelf", 3 }, { "crates", 2 }, { "storageCabinet", 3 } },
	Maintenance = { { "workbench", 2 }, { "crates", 2 }, { "shelf", 1 }, { "storageCabinet", 2 }, { "tallCabinet", 1 } },
	Restroom = { { "stall", 3 }, { "sink", 2 }, { "storageCabinet", 1 } },
	BreakRoom = { { "table", 3 }, { "vending", 1 }, { "cooler", 1 }, { "storageCabinet", 2 } },
	Anomaly = { { "desk", 1 } },
}

local function pickProp(rng, kind)
	local list = PROPS_BY_KIND[kind] or PROPS_BY_KIND.Office
	local weights = {}
	for _, entry in ipairs(list) do
		weights[entry[1]] = entry[2]
	end
	return rng:weighted(weights)
end

---------------------------------------------------------------------------------------------
-- Lockers
---------------------------------------------------------------------------------------------

local lockerCounter = 0

-- cf: floor-level CFrame whose LookVector is the locker's front.
-- style "Cabinet" builds a wooden office supply cabinet that works the same way.
local function buildLocker(parent, cf, style)
	lockerCounter += 1
	local cabinet = style == "Cabinet"
	local id = (if cabinet then "Cabinet" else "Locker") .. lockerCounter
	local m = model(parent, id)
	local color = if cabinet then rgb(122, 92, 62) else rgb(104, 116, 108)
	local shellMaterial = if cabinet then MAT.Wood else MAT.MetalPlain
	local w, d, h = 3, 2.4, 7.6
	local function lp(name, size, offset)
		return occluder(newPart(m, { Name = name, Size = size, CFrame = cf * offset, Color = color, Material = shellMaterial }), "Prop")
	end
	lp("Back", Vector3.new(w, h, 0.2), CFrame.new(0, h / 2, d / 2 - 0.1))
	lp("Left", Vector3.new(0.2, h, d), CFrame.new(-w / 2 + 0.1, h / 2, 0))
	lp("Right", Vector3.new(0.2, h, d), CFrame.new(w / 2 - 0.1, h / 2, 0))
	lp("Top", Vector3.new(w, 0.2, d), CFrame.new(0, h - 0.1, 0))
	lp("Bottom", Vector3.new(w, 0.2, d), CFrame.new(0, 0.1, 0))

	-- Door: built as a hinged assembly with eye-level slits to peek through.
	local hinge = cf * CFrame.new(-w / 2, 0, -d / 2)
	local door = model(m, "Door")
	local doorColor = if cabinet then rgb(138, 104, 70) else rgb(96, 108, 100)
	local pieces = {
		{ y0 = 0.2, y1 = 4.55 },
		{ y0 = 4.8, y1 = 5.0 },
		{ y0 = 5.25, y1 = 5.45 },
		{ y0 = 5.7, y1 = h - 0.2 },
	}
	local parts = {}
	for i, piece in ipairs(pieces) do
		local ph = piece.y1 - piece.y0
		local p = newPart(door, {
			Name = "Panel" .. i,
			Size = Vector3.new(w - 0.1, ph, 0.15),
			CFrame = hinge * CFrame.new(w / 2, piece.y0 + ph / 2, -0.05),
			Color = doorColor,
			Material = shellMaterial,
		})
		occluder(p, "Door")
		table.insert(parts, p)
	end
	door.PrimaryPart = parts[1]

	local promptPart = newPart(m, {
		Name = "PromptAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = cf * CFrame.new(0, 3.6, -d / 2 - 0.3),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})

	CollectionService:AddTag(m, "DA_HidingSpot")
	return {
		id = id,
		label = if cabinet then "Supply Cabinet" else "Locker",
		model = m,
		door = door,
		doorParts = parts,
		hinge = hinge,
		promptPart = promptPart,
		-- Character pivot when hidden: standing inside, facing out through the slits.
		insideCFrame = cf * CFrame.new(0, 3.05, 0.1),
		exitCFrame = cf * CFrame.new(0, 3.05, -d / 2 - 2.2),
		frontPosition = (cf * CFrame.new(0, 0, -d / 2 - 3)).Position,
	}
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function quadrantSign(q)
	local sx = if q == "NE" or q == "SE" then 1 else -1
	local sz = if q == "NE" or q == "NW" then -1 else 1
	return sx, sz
end

local DIRECTION_VECTORS = {
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
	S = Vector3.new(0, 0, 1),
	N = Vector3.new(0, 0, -1),
}

local function neighborDirection(layout, fromIndex, toIndex)
	local a, b = layout.cells[fromIndex], layout.cells[toIndex]
	if b.x > a.x then
		return "E"
	elseif b.x < a.x then
		return "W"
	elseif b.y > a.y then
		return "S"
	end
	return "N"
end

local function surfaceText(parent, face, text, textColor, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	label.BackgroundTransparency = if bg then 0 else 1
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = Enum.Font.Code
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return gui, label
end

function MapBuilder.build(layout, chainDef, rng, options)
	options = options or {}
	local self = setmetatable({}, Map)
	self.layout = layout
	self.powered = false
	self.lights = {}
	self.screens = {}
	self.doors = {}
	self.lockers = {}
	self.falseDoors = {}
	self.stations = {}
	self.itemSpots = {}
	self.containers = {}
	self.containersByCell = {}
	self.patrolPoints = {}
	self.startSpawns = {}
	self.cellLabels = {}

	local folder = Instance.new("Folder")
	folder.Name = "Facility"
	self.folder = folder
	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = folder
	local propsFolder = Instance.new("Folder")
	propsFolder.Name = "Props"
	propsFolder.Parent = folder
	local doorsFolder = Instance.new("Folder")
	doorsFolder.Name = "Doors"
	doorsFolder.Parent = folder
	local lockersFolder = Instance.new("Folder")
	lockersFolder.Name = "Lockers"
	lockersFolder.Parent = folder
	local stationsFolder = Instance.new("Folder")
	stationsFolder.Name = "Stations"
	stationsFolder.Parent = folder
	self.itemsFolder = Instance.new("Folder")
	self.itemsFolder.Name = "Items"
	self.itemsFolder.Parent = folder

	local width, height = layout.width, layout.height

	-- Floors, ceilings, lights --------------------------------------------------------------
	for index, cell in ipairs(layout.cells) do
		local center = self:cellCenter(index)
		local h = self:cellHeight(index)
		newPart(geometry, {
			Name = "Floor",
			Size = Vector3.new(CS, 1, CS),
			Position = center - Vector3.new(0, 0.5, 0),
			Color = FLOOR_COLORS[cell.floor] or FLOOR_COLORS.Concrete,
			Material = MAT[cell.floor] or MAT.Concrete,
		}):SetAttribute("Surface", cell.floor)
		newPart(geometry, {
			Name = "Ceiling",
			Size = Vector3.new(CS, 1, CS),
			Position = center + Vector3.new(0, h + 0.5, 0),
			Color = CEILING_COLOR,
			Material = MAT.Plaster,
		})

		local inverted = cell.variant == "InvertedRoom"
		local tubeY = if inverted then 0.15 else h - 0.15
		local tube = newPart(geometry, {
			Name = "FluorescentTube",
			Size = Vector3.new(6, 0.25, 1.2),
			Position = center + Vector3.new(0, tubeY, 0),
			Color = TUBE_ON,
			Material = MAT.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		local light = Instance.new("PointLight")
		-- Shadow-casting on every other fixture keeps the look while saving mobile GPUs.
		light.Shadows = index % 2 == 0
		light.Parent = tube
		tube:SetAttribute("Cell", index)
		tube:SetAttribute("Flicker", cell.flicker == true)
		CollectionService:AddTag(tube, "DA_Light")
		local entry = { tube = tube, light = light, on = false, baseOn = cell.lit, overridden = false }
		self.lights[index] = entry
		applyLight(entry, cell.lit, false)

		-- Rooms whose ceiling light is dead still get a dim amber emergency lamp high on the
		-- north wall, so nowhere is pitch black (it stays on after the power returns).
		if not cell.lit and cell.kind ~= "Start" then
			local lampPos = center + Vector3.new(-9, h - 3, -CS / 2 + WT / 2 + 0.35)
			local lamp = newPart(geometry, {
				Name = "EmergencyLamp",
				Size = Vector3.new(1.6, 0.6, 0.5),
				Position = lampPos,
				Color = rgb(255, 170, 70),
				Material = MAT.Neon,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			})
			local glow = Instance.new("PointLight")
			glow.Color = rgb(255, 170, 90)
			glow.Range = 16
			glow.Brightness = 0.45
			glow.Shadows = false
			glow.Parent = lamp
		end

		if not cell.special and cell.kind ~= "Start" then
			table.insert(self.patrolPoints, center + Vector3.new(0, 3, 0))
		end
	end

	-- Walls -------------------------------------------------------------------------------------
	local function wallStyle(a, b)
		local ca = layout.cells[a]
		local cb = b and layout.cells[b]
		local kind = ca.kind
		if cb and (cb.special or cb.kind == "Maintenance") then
			kind = cb.kind
		end
		return WALL_COLORS[kind] or WALL_COLORS.Office, if kind == "Maintenance" or (cb and cb.special) or ca.special then MAT.Concrete else MAT.Plaster
	end

	local function buildEdge(a, b, runAxis, fixed, from, to)
		local h = math.max(self:cellHeight(a), b and self:cellHeight(b) or 0)
		local color, mat = wallStyle(a, b)
		local edge = b and layout.edges[MazeGen.edgeKey(a, b)]
		if not edge then
			buildWall(geometry, runAxis, fixed, from, to, h, nil, color, mat)
			return
		end
		if edge.kind == "Open" then
			buildWall(geometry, runAxis, fixed, from, to, h, { width = MapConfig.OpenWidth, height = MapConfig.DoorHeight + 0.5 }, color, mat)
			return
		end
		local center = buildWall(geometry, runAxis, fixed, from, to, h, { width = MapConfig.DoorWidth, height = MapConfig.DoorHeight }, color, mat)
		self.doors[#self.doors + 1] = {
			edgeKey = edge.key,
			center = center,
			runAxis = runAxis,
			heavy = edge.heavy == true,
			special = edge.special,
			metal = edge.heavy or layout.cells[a].kind == "Maintenance" or layout.cells[b].kind == "Maintenance",
			cellA = a,
			cellB = b,
			parent = doorsFolder,
		}
	end

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local index = y * width + x + 1
			local minX, minZ = x * CS, y * CS
			-- West / north outer boundary
			if x == 0 then
				buildEdge(index, nil, "Z", minX, minZ, minZ + CS)
			end
			if y == 0 then
				buildEdge(index, nil, "X", minZ, minX, minX + CS)
			end
			-- East
			if x < width - 1 then
				buildEdge(index, index + 1, "Z", minX + CS, minZ, minZ + CS)
			else
				buildEdge(index, nil, "Z", minX + CS, minZ, minZ + CS)
			end
			-- South
			if y < height - 1 then
				buildEdge(index, index + width, "X", minZ + CS, minX, minX + CS)
			else
				buildEdge(index, nil, "X", minZ + CS, minX, minX + CS)
			end
		end
	end

	-- Door models -----------------------------------------------------------------------------
	for _, door in ipairs(self.doors) do
		local w = MapConfig.DoorWidth - 0.3
		local h = MapConfig.DoorHeight - 0.15
		local rot = if door.runAxis == "Z" then CFrame.Angles(0, math.rad(90), 0) else CFrame.new()
		local base = CFrame.new(door.center) * rot -- local X runs along the wall
		local m = model(door.parent, "Door_" .. door.edgeKey)
		local color = if door.heavy then rgb(88, 94, 92) elseif door.metal then rgb(120, 124, 118) else rgb(150, 128, 92)
		local panel = newPart(m, {
			Name = "Panel",
			Size = Vector3.new(w, h, if door.heavy then 0.6 else 0.35),
			CFrame = base * CFrame.new(0, h / 2, 0),
			Color = color,
			Material = if door.heavy or door.metal then MAT.MetalPlain else MAT.Wood,
		})
		occluder(panel, "Door")
		local modifier = Instance.new("PathfindingModifier")
		modifier.Label = "Door"
		modifier.PassThrough = true
		modifier.Parent = panel
		if door.heavy then
			-- Hazard stripe and status light on heavy security doors.
			local stripe = newPart(m, {
				Name = "Stripe",
				Size = Vector3.new(w, 0.6, 0.65),
				CFrame = base * CFrame.new(0, 1.2, 0),
				Color = rgb(200, 160, 40),
				CanCollide = false,
			})
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = panel
			weld.Part1 = stripe
			weld.Parent = stripe
			stripe.Anchored = false
			stripe.Massless = true
			local status = newPart(m, {
				Name = "Status",
				Size = Vector3.new(0.6, 0.6, 1.2),
				CFrame = base * CFrame.new(w / 2 + 0.9, MapConfig.DoorHeight - 1.5, 0),
				Color = rgb(255, 60, 50),
				Material = MAT.Neon,
				CanCollide = false,
			})
			door.statusLight = status
		else
			local knob = newPart(m, {
				Name = "Knob",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.4, 0.4, 0.4),
				CFrame = base * CFrame.new(w / 2 - 0.7, 4.2, 0),
				Color = rgb(170, 160, 120),
				Material = MAT.MetalPlain,
				CanCollide = false,
				Anchored = false,
				Massless = true,
			})
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = panel
			weld.Part1 = knob
			weld.Parent = knob
		end
		m.PrimaryPart = panel
		door.model = m
		door.panel = panel
		door.closedCFrame = panel.CFrame
		if door.heavy then
			door.openCFrame = panel.CFrame + Vector3.new(0, h - 0.6, 0)
		else
			local hingeCf = base * CFrame.new(-w / 2, h / 2, 0)
			local offset = hingeCf:ToObjectSpace(panel.CFrame)
			door.openCFrame = hingeCf * CFrame.Angles(0, math.rad(95), 0) * offset
		end
		-- Prompt anchors on both sides of the door.
		local anchor = newPart(m, {
			Name = "PromptAnchor",
			Size = Vector3.new(1, 1, 1),
			CFrame = base * CFrame.new(0, 4, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		door.promptPart = anchor
	end

	-- Quadrant contents ------------------------------------------------------------------------
	local Q = MapConfig.QuadrantOffset
	for index, cell in ipairs(layout.cells) do
		local center = self:cellCenter(index)
		local spots = {}
		self.itemSpots[index] = spots
		if not cell.special and cell.kind ~= "Start" then
			containerSink = self.containers
			containerCell = index
			for _, q in ipairs(MazeGen.Quadrants) do
				local sx, sz = quadrantSign(q)
				local qCenter = center + Vector3.new(sx * Q, 0, sz * Q)
				local content = cell.quadrants[q]
				-- Face the prop toward the cross lane so its "front" is reachable.
				local cf = CFrame.lookAt(qCenter, qCenter + Vector3.new(0, 0, -sz))
				if content == "Locker" then
					-- Against the east/west wall. Doorways and arches span at most +-6 studs
					-- around the wall centre, and the locker sits at +-8.5, so it never blocks one.
					local pos = Vector3.new(center.X + sx * (CS / 2 - WT / 2 - 1.3), 0, qCenter.Z)
					local lockerCf = CFrame.lookAt(pos, pos + Vector3.new(-sx, 0, 0))
					local locker = buildLocker(lockersFolder, lockerCf, if MapConfig.CabinetKinds[cell.kind] then "Cabinet" else "Locker")
					locker.cell = index
					table.insert(self.lockers, locker)
				elseif content == "Prop" then
					local kind = cell.kind
					if cell.variant == "ChairRoom" then
						for row = -1, 1 do
							for col = -1, 1 do
								Props.chair(propsFolder, CFrame.lookAt(qCenter + Vector3.new(col * 2.6, 0, row * 2.6), qCenter + Vector3.new(col * 2.6, 0, row * 2.6 - 10)))
							end
						end
						table.insert(spots, qCenter + Vector3.new(0, 0.3, 0))
					elseif cell.variant == "InvertedRoom" then
						local hTop = self:cellHeight(index)
						local flipped = CFrame.new(qCenter + Vector3.new(0, hTop, 0)) * CFrame.Angles(0, 0, math.pi)
						-- The upside-down desk's drawer is on the ceiling: not searchable.
						containerSink = nil
						Props.desk(propsFolder, flipped, rng)
						containerSink = self.containers
						table.insert(spots, qCenter + Vector3.new(0, 0.3, 0))
					else
						local propName = pickProp(rng, kind)
						local spot = Props[propName](propsFolder, cf, rng)
						if spot then
							table.insert(spots, spot)
						end
					end
				elseif content == "Empty" then
					-- Most open corners get a cabinet to search; the rest stay bare floor.
					if cell.variant ~= "InvertedRoom" and rng:chance(MapConfig.EmptyCornerCabinetChance) then
						local name = if rng:chance(0.5) then "storageCabinet" else "tallCabinet"
						Props[name](propsFolder, cf, rng)
					else
						table.insert(spots, qCenter + Vector3.new(rng:range(-2, 2), 0.3, rng:range(-2, 2)))
					end
				end
			end
			containerSink = nil
			if cell.kind == "Maintenance" then
				Props.pipes(propsFolder, CFrame.lookAt(center + Vector3.new(-CS / 2 + 4, 0, -CS / 2 + 4.5), center + Vector3.new(-CS / 2 + 4, 0, 0)), self:cellHeight(index))
			end
			if #spots == 0 then
				table.insert(spots, center + Vector3.new(Q, 0.3, Q))
			end
			if cell.struggle then
				MapBuilder.dressStruggle(self, propsFolder, index, rng)
			end
			if cell.variant == "FalseDoor" then
				MapBuilder.buildFalseDoor(self, propsFolder, index)
			end
		end
	end

	for _, container in ipairs(self.containers) do
		self.containersByCell[container.cell] = self.containersByCell[container.cell] or {}
		table.insert(self.containersByCell[container.cell], container)
	end

	-- Special rooms ---------------------------------------------------------------------------
	for roomName, index in pairs(layout.specials) do
		local cell = layout.cells[index]
		local inward = DIRECTION_VECTORS[neighborDirection(layout, index, cell.entrance)]
		local center = self:cellCenter(index)
		local back = center - inward * (CS / 2 - WT / 2 - 0.4)
		local side = Vector3.new(inward.Z, 0, -inward.X) -- perpendicular along the back wall
		local facing = CFrame.lookAt(back, back + inward) -- LookVector points into the room
		if roomName == "PowerRoom" then
			if chainDef.PowerRoomVariant == "Generator" then
				MapBuilder.buildGeneratorRoom(self, stationsFolder, facing, side)
			else
				MapBuilder.buildElectricalRoom(self, stationsFolder, facing, side, options.fuseCount or 3)
			end
		elseif roomName == "Security" then
			MapBuilder.buildSecurityRoom(self, stationsFolder, facing)
		elseif roomName == "Exit" then
			MapBuilder.buildExitRoom(self, stationsFolder, facing, center)
		end
	end

	MapBuilder.buildStartRoom(self, propsFolder, chainDef, options.runLabel or "")

	-- Monster spawn ---------------------------------------------------------------------------
	self.monsterSpawn = CFrame.new(self:cellCenter(layout.monsterSpawn) + Vector3.new(0, 6, 0))

	folder.Parent = Workspace
	self:setPower(false)
	return self
end

---------------------------------------------------------------------------------------------
-- Room dressings
---------------------------------------------------------------------------------------------

function MapBuilder.dressStruggle(self, parent, index, rng)
	local center = self:cellCenter(index)
	-- Overturned chair in the lane, scattered papers, a dark stain, scratches on the wall.
	local chair = Props.chair(parent, CFrame.new(center + Vector3.new(rng:range(-2, 2), 0.6, rng:range(-2, 2))) * CFrame.Angles(math.rad(90), math.rad(rng:range(0, 360)), 0))
	chair.Name = "OverturnedChair"
	for _ = 1, 7 do
		newPart(parent, {
			Name = "Paper",
			Size = Vector3.new(0.9, 0.02, 1.2),
			CFrame = CFrame.new(center + Vector3.new(rng:range(-5, 5), 0.02, rng:range(-5, 5))) * CFrame.Angles(0, math.rad(rng:range(0, 360)), 0),
			Color = rgb(230, 226, 210),
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
	end
	newPart(parent, {
		Name = "Stain",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.04, 5.5, 5.5),
		CFrame = CFrame.new(center + Vector3.new(rng:range(-3, 3), 0.03, rng:range(-3, 3))) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(60, 30, 24),
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	-- Long scratch marks high on the north wall: something tall did this.
	local wallZ = center.Z - CS / 2 + WT / 2 + 0.06
	for i = 1, 4 do
		newPart(parent, {
			Name = "Scratch",
			Size = Vector3.new(0.12, 4.5, 0.05),
			CFrame = CFrame.new(center.X - 8 + i * 0.7, 8, wallZ) * CFrame.Angles(0, 0, math.rad(12)),
			Color = rgb(70, 60, 44),
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
	end
end

function MapBuilder.buildFalseDoor(self, parent, index)
	-- A door on a solid wall. It opens onto bare concrete.
	local layout = self.layout
	local cell = layout.cells[index]
	local center = self:cellCenter(index)
	local candidates = { "N", "S", "E", "W" }
	for other in pairs(cell.links) do
		local dir = neighborDirection(layout, index, other)
		local i = table.find(candidates, dir)
		if i then
			table.remove(candidates, i)
		end
	end
	local dir = candidates[1]
	if not dir then
		return
	end
	local outward = DIRECTION_VECTORS[dir]
	local pos = center + outward * (CS / 2 - WT / 2 - 0.25)
	local base = CFrame.lookAt(pos, pos - outward)
	local m = model(parent, "FalseDoor")
	newPart(m, { Name = "Concrete", Size = Vector3.new(7.6, 11.6, 0.2), CFrame = base * CFrame.new(0, 5.8, 0.15), Color = rgb(90, 88, 84), Material = MAT.Concrete })
	newPart(m, { Name = "FrameL", Size = Vector3.new(0.4, 12, 0.5), CFrame = base * CFrame.new(-4, 6, 0), Color = rgb(120, 100, 76) })
	newPart(m, { Name = "FrameR", Size = Vector3.new(0.4, 12, 0.5), CFrame = base * CFrame.new(4, 6, 0), Color = rgb(120, 100, 76) })
	local panel = newPart(m, { Name = "Panel", Size = Vector3.new(7.6, 11.6, 0.3), CFrame = base * CFrame.new(0, 5.8, -0.2), Color = rgb(150, 128, 92), Material = MAT.Wood })
	local hinge = base * CFrame.new(-3.8, 5.8, -0.2)
	table.insert(self.falseDoors, {
		panel = panel,
		closedCFrame = panel.CFrame,
		openCFrame = hinge * CFrame.Angles(0, math.rad(-100), 0) * hinge:ToObjectSpace(panel.CFrame),
		position = panel.Position,
	})
end

local function station(self, name, part, extra)
	local record = extra or {}
	record.name = name
	record.part = part
	record.position = part.Position
	self.stations[name] = record
	part:SetAttribute("Station", name)
	return record
end

function MapBuilder.buildElectricalRoom(self, parent, facing, side, fuseCount)
	local m = model(parent, "ElectricalRoom")
	local metal = rgb(92, 98, 96)
	local box = newPart(m, { Name = "FuseBox", Size = Vector3.new(4.5, 5, 0.8), CFrame = facing * CFrame.new(-4, 5, -0.4), Color = metal, Material = MAT.MetalPlain })
	local slots = {}
	for i = 1, fuseCount do
		local offset = (i - (fuseCount + 1) / 2) * 1.0
		local slot = newPart(m, {
			Name = "Slot" .. i,
			Size = Vector3.new(0.5, 1.4, 0.3),
			CFrame = facing * CFrame.new(-4 + offset, 5, -0.9),
			Color = rgb(30, 30, 30),
			CanCollide = false,
		})
		table.insert(slots, slot)
	end
	surfaceText(box, Enum.NormalId.Front, "FUSES", rgb(255, 200, 60))
	station(self, "FuseBox", box, { slots = slots })

	local breakerBox = newPart(m, { Name = "Breaker", Size = Vector3.new(3, 5, 1.2), CFrame = facing * CFrame.new(4, 4.5, -0.6), Color = rgb(70, 74, 70), Material = MAT.MetalPlain })
	local lever = newPart(m, {
		Name = "Lever",
		Size = Vector3.new(0.4, 2.4, 0.4),
		CFrame = facing * CFrame.new(4, 4.5, -1.5) * CFrame.Angles(math.rad(35), 0, 0),
		Color = rgb(200, 40, 30),
		CanCollide = false,
	})
	surfaceText(breakerBox, Enum.NormalId.Front, "MAIN", rgb(255, 90, 60))
	station(self, "Breaker", breakerBox, { lever = lever, leverDown = facing * CFrame.new(4, 3.6, -1.5) * CFrame.Angles(math.rad(-35), 0, 0) })

	-- Electrical cabinets along the side walls (outside the lane).
	for _, s in ipairs({ -1, 1 }) do
		local cabinet = newPart(m, {
			Name = "Cabinet",
			Size = Vector3.new(2.2, 7, 5),
			CFrame = facing * CFrame.new(s * 10.5, 3.5, -7),
			Color = rgb(110, 116, 110),
			Material = MAT.MetalPlain,
		})
		occluder(cabinet, "Prop")
	end
	return side
end

function MapBuilder.buildGeneratorRoom(self, parent, facing, _side)
	local m = model(parent, "GeneratorRoom")
	local body = newPart(m, { Name = "Generator", Size = Vector3.new(7, 4.5, 4), CFrame = facing * CFrame.new(0, 2.25, -2.4), Color = rgb(170, 140, 40), Material = MAT.MetalPlain })
	occluder(body, "Prop")
	for _, x in ipairs({ -2.2, 2.2 }) do
		newPart(m, {
			Name = "Exhaust",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(8, 0.9, 0.9),
			CFrame = facing * CFrame.new(x, 8.5, -1) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(80, 74, 66),
			Material = MAT.MetalPlain,
			CanCollide = false,
		})
	end
	local gauge = newPart(m, { Name = "Gauge", Size = Vector3.new(2, 1.2, 0.2), CFrame = facing * CFrame.new(0, 3.6, -4.45), Color = rgb(20, 20, 20), CanCollide = false })
	local _, label = surfaceText(gauge, Enum.NormalId.Front, "FUEL 0%", rgb(255, 180, 60))
	station(self, "Generator", body, { gaugeLabel = label })
end

function MapBuilder.buildSecurityRoom(self, parent, facing)
	local m = model(parent, "SecurityRoom")
	local desk = newPart(m, { Name = "Terminal", Size = Vector3.new(9, 3, 3), CFrame = facing * CFrame.new(0, 1.5, -2.5), Color = rgb(90, 92, 90), Material = MAT.MetalPlain })
	local labels = {}
	for i, x in ipairs({ -3, 0, 3 }) do
		local monitor = newPart(m, {
			Name = "Monitor" .. i,
			Size = Vector3.new(2.6, 2, 1.4),
			CFrame = facing * CFrame.new(x, 4.1, -1.8) * CFrame.Angles(math.rad(-8), 0, 0),
			Color = rgb(40, 40, 42),
		})
		local gui, label = surfaceText(monitor, Enum.NormalId.Front, if i == 2 then "OVERRIDE\nLOCKED" else "CAM " .. i, rgb(140, 255, 160), rgb(4, 14, 6))
		gui.Enabled = false
		table.insert(self.screens, gui)
		table.insert(labels, label)
	end
	station(self, "Terminal", desk, { labels = labels })
	Props.chair(m, facing * CFrame.new(0, 0, -5.5) * CFrame.Angles(0, math.rad(180), 0))
end

function MapBuilder.buildExitRoom(self, parent, facing, _center)
	local m = model(parent, "ServiceElevator")
	local metal = rgb(80, 84, 84)
	local depth, widthCar, heightCar = 8, 10, 11
	-- Car walls (sides + ceiling); the room's back wall is the car's back.
	for _, s in ipairs({ -1, 1 }) do
		newPart(m, { Name = "CarSide", Size = Vector3.new(0.5, heightCar, depth), CFrame = facing * CFrame.new(s * widthCar / 2, heightCar / 2, -depth / 2), Color = metal, Material = MAT.MetalPlain })
	end
	newPart(m, { Name = "CarTop", Size = Vector3.new(widthCar, 0.5, depth), CFrame = facing * CFrame.new(0, heightCar, -depth / 2), Color = metal, Material = MAT.MetalPlain })
	newPart(m, { Name = "CarFloor", Size = Vector3.new(widthCar, 0.2, depth), CFrame = facing * CFrame.new(0, 0.1, -depth / 2), Color = rgb(60, 62, 62), Material = MAT.Metal })
	local carLight = newPart(m, { Name = "CarLight", Size = Vector3.new(4, 0.2, 1), CFrame = facing * CFrame.new(0, heightCar - 0.4, -depth / 2), Color = TUBE_OFF, Material = MAT.Smooth, CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Range = 12
	pl.Brightness = 1.2
	pl.Color = rgb(255, 230, 200)
	pl.Enabled = false
	pl.Parent = carLight
	-- Header above the doors.
	newPart(m, { Name = "Header", Size = Vector3.new(widthCar, 3, 0.6), CFrame = facing * CFrame.new(0, heightCar - 1.5, -depth - 0.3), Color = metal, Material = MAT.MetalPlain })

	-- Sliding doors.
	local doorH = heightCar - 3
	local leftClosed = facing * CFrame.new(-widthCar / 4, doorH / 2, -depth - 0.2)
	local rightClosed = facing * CFrame.new(widthCar / 4, doorH / 2, -depth - 0.2)
	local left = newPart(m, { Name = "DoorL", Size = Vector3.new(widthCar / 2, doorH, 0.3), CFrame = leftClosed, Color = rgb(150, 154, 150), Material = MAT.MetalPlain })
	local right = newPart(m, { Name = "DoorR", Size = Vector3.new(widthCar / 2, doorH, 0.3), CFrame = rightClosed, Color = rgb(150, 154, 150), Material = MAT.MetalPlain })
	occluder(left, "Door")
	occluder(right, "Door")

	local zone = newPart(m, {
		Name = "BoardingZone",
		Size = Vector3.new(widthCar - 1, 8, depth - 1),
		CFrame = facing * CFrame.new(0, 4, -depth / 2),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	local panel = newPart(m, { Name = "ExitPanel", Size = Vector3.new(1.2, 2, 0.4), CFrame = facing * CFrame.new(widthCar / 2 + 1.6, 4.5, -depth - 0.3), Color = rgb(60, 60, 60) })
	local button = newPart(m, { Name = "Button", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), CFrame = facing * CFrame.new(widthCar / 2 + 1.6, 4.6, -depth - 0.55), Color = rgb(120, 30, 30), Material = MAT.Neon, CanCollide = false })
	local beacon = newPart(m, { Name = "Beacon", Size = Vector3.new(1, 0.6, 1), CFrame = facing * CFrame.new(0, heightCar + 0.5, -depth - 0.8), Color = rgb(80, 20, 16), Material = MAT.Smooth, CanCollide = false })
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = rgb(255, 50, 30)
	beaconLight.Range = 30
	beaconLight.Brightness = 2
	beaconLight.Enabled = false
	beaconLight.Parent = beacon

	self.elevator = {
		zone = zone,
		left = left,
		right = right,
		leftClosed = leftClosed,
		rightClosed = rightClosed,
		leftOpen = leftClosed * CFrame.new(-widthCar / 2 + 0.6, 0, 0),
		rightOpen = rightClosed * CFrame.new(widthCar / 2 - 0.6, 0, 0),
		carLight = carLight,
		beacon = beacon,
		beaconLight = beaconLight,
		button = button,
	}
	station(self, "ExitPanel", panel)
end

function MapBuilder.buildStartRoom(self, parent, chainDef, runLabel)
	local index = self.layout.start
	local center = self:cellCenter(index)
	local m = model(parent, "SafeRoom")
	local board = newPart(m, {
		Name = "Briefing",
		Size = Vector3.new(8, 4.5, 0.3),
		CFrame = CFrame.lookAt(center + Vector3.new(9, 5, -9), center + Vector3.new(0, 5, 0)),
		Color = rgb(40, 44, 40),
	})
	surfaceText(board, Enum.NormalId.Front, "SUB-LEVEL 3\n" .. chainDef.Title .. "\n" .. runLabel .. "\nKEEP QUIET", rgb(235, 225, 190), rgb(28, 32, 28))
	newPart(m, { Name = "Couch", Size = Vector3.new(7, 2.2, 2.6), CFrame = CFrame.lookAt(center + Vector3.new(-9, 1.1, 9), center + Vector3.new(-9, 1.1, 0)), Color = rgb(110, 70, 56), Material = MAT.Fabric })
	newPart(m, { Name = "Rug", Size = Vector3.new(9, 0.05, 9), Position = center + Vector3.new(0, 0.03, 0), Color = rgb(96, 52, 44), Material = MAT.Fabric, CanCollide = false })
	for i = 0, 5 do
		local angle = (i / 6) * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * 3.5, 3.2, math.sin(angle) * 3.5)
		table.insert(self.startSpawns, CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z + 20)))
	end
end

---------------------------------------------------------------------------------------------
-- Lobby (built once, away from the facility)
---------------------------------------------------------------------------------------------

-- Shared building blocks for LobbyBuilder.
MapBuilder.Props = Props
MapBuilder.newPart = newPart
MapBuilder.surfaceText = surfaceText
MapBuilder.buildLocker = buildLocker
MapBuilder.Palette = {
	Materials = MAT,
	WallColors = WALL_COLORS,
	FloorColors = FLOOR_COLORS,
	Ceiling = CEILING_COLOR,
	LightPower = LIGHT_POWER,
	TubeOn = TUBE_ON,
}

return MapBuilder
