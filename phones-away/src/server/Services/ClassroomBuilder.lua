--[[
	ClassroomBuilder - builds the whole school from parts:

	  Classroom (Room 104): tiled floor, walls with windows and a door, whiteboard with
	  writing, wall clock with moving hands, posters, bookshelf, teacher's desk with a
	  "confiscated" basket, 12 student desks with chairs (2 gold VIP desks in the back row)
	  and the detention corner.
	  Hallway (lobby between classes): lockers, the School Store kiosk (opens the shop), the
	  global leaderboard, a "like the game" poster and the spawn.

	Returns a table the services use (desks, seats, phone spots, board, etc.).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)

local ClassroomBuilder = {}

local L = GameConfig.Classroom

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local COLORS = {
	Wall = rgb(246, 236, 214),
	WallTrim = rgb(110, 160, 200),
	FloorA = rgb(226, 222, 210),
	FloorB = rgb(196, 214, 222),
	DeskTop = rgb(214, 170, 112),
	Metal = rgb(120, 130, 145),
	Chair = rgb(70, 130, 200),
	Board = rgb(250, 252, 255),
	BoardFrame = rgb(170, 175, 185),
	Wood = rgb(160, 110, 70),
	LockerA = rgb(60, 110, 200),
	LockerB = rgb(220, 70, 70),
	Gold = rgb(255, 200, 70),
	HallFloorA = rgb(235, 235, 235),
	HallFloorB = rgb(60, 70, 90),
}

-- Roblox forces Ball parts to a uniform size, so non-uniform "balls" (eyes, hair, cheeks)
-- use a Block with a built-in Sphere SpecialMesh instead (no imported assets).
local function shapeBall(p, size)
	if math.abs(size.X - size.Y) < 1e-3 and math.abs(size.Y - size.Z) < 1e-3 then
		p.Shape = Enum.PartType.Ball
		return
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function part(parent, name, size, cf, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	for k, v in pairs(props or {}) do
		if k == "Shape" and v == Enum.PartType.Ball then
			shapeBall(p, (props and props.Size) or size)
		elseif k ~= "Size" or not (props and props.Shape == Enum.PartType.Ball) then
			p[k] = v
		end
	end
	if props and props.Size and props.Shape == Enum.PartType.Ball then
		p.Size = props.Size
	end
	p.Parent = parent
	return p
end

local function deco(parent, name, size, cf, color, props)
	local p = part(parent, name, size, cf, color, props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function surfaceText(p, face, text, props)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.4
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(40, 40, 60)
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = gui
	return label, gui
end

---------------------------------------------------------------------------------------------
-- Room shell
---------------------------------------------------------------------------------------------

local function buildShell(room)
	local W, D, H = L.Width, L.Depth, L.WallHeight
	local shell = folder("Shell", room)
	-- Tiled floor (checker of 5x5 tiles over a base)
	part(shell, "Floor", Vector3.new(W, 1, D), CFrame.new(0, -0.5, 0), COLORS.FloorA)
	local tiles = folder("Tiles", shell)
	for ix = 0, W / 5 - 1 do
		for iz = 0, D / 5 - 1 do
			if (ix + iz) % 2 == 0 then
				deco(tiles, "Tile", Vector3.new(5, 0.04, 5), CFrame.new(-W / 2 + 2.5 + ix * 5, 0.02, -D / 2 + 2.5 + iz * 5), COLORS.FloorB)
			end
		end
	end
	-- Front wall (whiteboard) and back wall
	part(shell, "FrontWall", Vector3.new(W, H, 1), CFrame.new(0, H / 2, -D / 2 - 0.5), COLORS.Wall)
	part(shell, "BackWall", Vector3.new(W, H, 1), CFrame.new(0, H / 2, D / 2 + 0.5), COLORS.Wall)
	-- Left wall with 4 windows
	local wx = -W / 2 - 0.5
	part(shell, "LeftWallLow", Vector3.new(1, 4, D), CFrame.new(wx, 2, 0), COLORS.Wall)
	part(shell, "LeftWallHigh", Vector3.new(1, 4, D), CFrame.new(wx, H - 2, 0), COLORS.Wall)
	local windows = folder("Windows", shell)
	local windowZ = { -17, -6, 5, 16 }
	local pillarEdges = { -D / 2 }
	for _, z in ipairs(windowZ) do
		table.insert(pillarEdges, z - 4)
		table.insert(pillarEdges, z + 4)
		deco(windows, "Glass", Vector3.new(0.2, 8, 8), CFrame.new(wx, 8, z), rgb(190, 225, 255), { Material = Enum.Material.Glass, Transparency = 0.55 })
		deco(windows, "FrameMid", Vector3.new(0.4, 8, 0.3), CFrame.new(wx + 0.1, 8, z), COLORS.WallTrim)
		deco(windows, "FrameBar", Vector3.new(0.4, 0.3, 8), CFrame.new(wx + 0.1, 8, z), COLORS.WallTrim)
		deco(windows, "Sill", Vector3.new(1.4, 0.3, 8.6), CFrame.new(wx + 0.5, 4.1, z), rgb(250, 250, 250))
	end
	table.insert(pillarEdges, D / 2)
	for i = 1, #pillarEdges, 2 do
		local a, b = pillarEdges[i], pillarEdges[i + 1]
		if b - a > 0.01 then
			part(shell, "LeftPillar", Vector3.new(1, 7, b - a), CFrame.new(wx, 7.5, (a + b) / 2), COLORS.Wall)
		end
	end
	-- Right wall with the door to the hallway
	local rx = W / 2 + 0.5
	local doorZ, doorW, doorH = L.DoorSpot[2], 6, 9.5
	local d0, d1 = doorZ - doorW / 2, doorZ + doorW / 2
	part(shell, "RightWallA", Vector3.new(1, H, d0 + D / 2), CFrame.new(rx, H / 2, (-D / 2 + d0) / 2), COLORS.Wall)
	part(shell, "RightWallB", Vector3.new(1, H, D / 2 - d1), CFrame.new(rx, H / 2, (d1 + D / 2) / 2), COLORS.Wall)
	part(shell, "RightWallTop", Vector3.new(1, H - doorH, doorW), CFrame.new(rx, doorH + (H - doorH) / 2, doorZ), COLORS.Wall)
	-- Trim stripe all round
	for _, spec in ipairs({
		{ Vector3.new(W, 0.6, 0.2), CFrame.new(0, 4.2, -D / 2 + 0.05) },
		{ Vector3.new(W, 0.6, 0.2), CFrame.new(0, 4.2, D / 2 - 0.05) },
		{ Vector3.new(0.2, 0.6, D), CFrame.new(W / 2 - 0.05, 4.2, 0) },
	}) do
		deco(shell, "Trim", spec[1], spec[2], COLORS.WallTrim)
	end
	for _, spec in ipairs({
		{ Vector3.new(W, 0.8, 0.3), CFrame.new(0, 0.4, -D / 2 + 0.1) },
		{ Vector3.new(W, 0.8, 0.3), CFrame.new(0, 0.4, D / 2 - 0.1) },
		{ Vector3.new(0.3, 0.8, D), CFrame.new(-W / 2 + 0.1, 0.4, 0) },
	}) do
		deco(shell, "Baseboard", spec[1], spec[2], rgb(120, 100, 90))
	end
	-- Ceiling with light panels
	part(shell, "Ceiling", Vector3.new(W + 2, 1, D + 2), CFrame.new(0, H + 0.5, 0), rgb(240, 240, 235))
	for ix = -1, 1 do
		for iz = -1, 1, 2 do
			local panel = deco(shell, "LightPanel", Vector3.new(8, 0.2, 3), CFrame.new(ix * 18, H - 0.1, iz * 10), rgb(255, 252, 235), { Material = Enum.Material.Neon })
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Range = 22
			light.Brightness = 1.1
			light.Angle = 120
			light.Color = rgb(255, 245, 225)
			light.Parent = panel
		end
	end
	-- Door (opens during the hallway break)
	local door = part(shell, "Door", Vector3.new(0.4, doorH, doorW), CFrame.new(rx, doorH / 2, doorZ), COLORS.Wood)
	deco(door, "Window", Vector3.new(0.5, 2.5, 1.6), CFrame.new(rx, 6.5, doorZ - 1.2), rgb(190, 225, 255), { Material = Enum.Material.Glass, Transparency = 0.4 })
	deco(door, "Handle", Vector3.new(0.7, 0.25, 0.7), CFrame.new(rx, 4.2, doorZ + 2.2), COLORS.Metal, { Material = Enum.Material.Metal })
	local doorClosed = door.CFrame
	-- Outside the windows: grass and a few trees, so the windows look onto a sunny day.
	local outside = folder("Outside", room)
	part(outside, "Grass", Vector3.new(60, 1, 90), CFrame.new(-W / 2 - 31, -0.6, 0), rgb(120, 200, 100), { Material = Enum.Material.Grass })
	for i, z in ipairs({ -30, -12, 6, 24, 40 }) do
		local x = -W / 2 - 12 - (i % 2) * 8
		deco(outside, "Trunk", Vector3.new(1.4, 7, 1.4), CFrame.new(x, 3.5, z), rgb(120, 85, 55))
		deco(outside, "Leaves", Vector3.new(9, 8, 9), CFrame.new(x, 9.5, z), rgb(90, 180, 90), { Shape = Enum.PartType.Ball, Material = Enum.Material.Grass })
	end
	return { door = door, doorClosed = doorClosed, doorOpen = doorClosed * CFrame.new(0, 0, -doorW / 2) * CFrame.Angles(0, math.rad(80), 0) * CFrame.new(0, 0, doorW / 2) }
end

---------------------------------------------------------------------------------------------
-- Front of the room
---------------------------------------------------------------------------------------------

local function buildFront(room)
	local front = folder("Front", room)
	local zWall = -L.Depth / 2
	-- Whiteboard
	local board = model("Whiteboard", room)
	deco(board, "Frame", Vector3.new(30, 9.4, 0.3), CFrame.new(0, 7.6, zWall + 0.15), COLORS.BoardFrame, { Material = Enum.Material.Metal })
	local surface = deco(board, "Surface", Vector3.new(29, 8.6, 0.12), CFrame.new(0, 7.6, zWall + 0.36), COLORS.Board)
	local text, textGui = surfaceText(surface, Enum.NormalId.Back, "", { TextScaled = false, TextSize = 64, TextColor3 = rgb(40, 70, 170), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.PatrickHand })
	textGui.PixelsPerStud = 30
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 40)
	pad.PaddingTop = UDim.new(0, 24)
	pad.Parent = text
	deco(board, "Tray", Vector3.new(28, 0.3, 0.8), CFrame.new(0, 3.2, zWall + 0.6), COLORS.BoardFrame, { Material = Enum.Material.Metal })
	for i, c in ipairs({ rgb(40, 90, 220), rgb(220, 50, 50), rgb(40, 160, 70), rgb(30, 30, 30) }) do
		deco(board, "Marker", Vector3.new(0.9, 0.2, 0.2), CFrame.new(-8 + i * 1.2, 3.45, zWall + 0.6), c)
	end
	deco(board, "Eraser", Vector3.new(1.2, 0.35, 0.5), CFrame.new(6, 3.5, zWall + 0.6), rgb(60, 60, 70))
	-- Wall clock (client animates the hands from the class time)
	local clock = model("WallClock", room)
	local center = CFrame.new(18, 12.8, zWall + 0.3)
	deco(clock, "Rim", Vector3.new(0.4, 3.4, 3.4), center * CFrame.Angles(0, math.rad(90), 0), rgb(40, 40, 50), { Shape = Enum.PartType.Cylinder })
	deco(clock, "Face", Vector3.new(0.42, 3.0, 3.0), center * CFrame.new(0, 0, 0.02) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 255, 250), { Shape = Enum.PartType.Cylinder })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		deco(clock, "Tick", Vector3.new(0.12, if i % 3 == 0 then 0.4 else 0.22, 0.05), center * CFrame.new(math.sin(a) * 1.25, math.cos(a) * 1.25, 0.25) * CFrame.Angles(0, 0, -a), rgb(40, 40, 50))
	end
	local hub = deco(clock, "Center", Vector3.new(0.2, 0.2, 0.2), center * CFrame.new(0, 0, 0.32), rgb(220, 60, 60), { Shape = Enum.PartType.Ball })
	deco(clock, "HourHand", Vector3.new(0.14, 0.8, 0.05), center * CFrame.new(0, 0.4, 0.28), rgb(30, 30, 40))
	deco(clock, "MinuteHand", Vector3.new(0.1, 1.15, 0.05), center * CFrame.new(0, 0.58, 0.3), rgb(30, 30, 40))
	clock.PrimaryPart = hub
	-- "Phones away" rule sign above the board
	local sign = deco(front, "RuleSign", Vector3.new(14, 1.8, 0.2), CFrame.new(-5, 13.4, zWall + 0.2), rgb(255, 230, 120))
	surfaceText(sign, Enum.NormalId.Back, "RULE #1: PHONES AWAY!", { TextColor3 = rgb(200, 40, 40) })
	-- Flag-free classroom posters
	local posters = {
		{ text = "PERIODIC\nTABLE", pos = CFrame.new(-24, 8, zWall + 0.1), size = Vector3.new(6, 4, 0.1), color = rgb(160, 220, 255) },
	}
	for _, p in ipairs(posters) do
		local poster = deco(front, "Poster", p.size, p.pos, p.color)
		surfaceText(poster, Enum.NormalId.Back, p.text)
	end
	-- Mini periodic-table grid on the poster
	for r = 0, 2 do
		for c = 0, 7 do
			if not (r == 0 and c > 0 and c < 7) then
				deco(front, "Element", Vector3.new(0.5, 0.4, 0.05), CFrame.new(-26.2 + c * 0.62, 6.9 - r * 0.48, zWall + 0.17), Color3.fromHSV(((r * 8 + c) % 9) / 9, 0.45, 1))
			end
		end
	end

	-- Teacher's desk (front left) with the basket of confiscated phones
	local desk = model("TeacherDesk", room)
	local dcf = CFrame.new(-17, 0, -19)
	part(desk, "Top", Vector3.new(8, 0.4, 4), dcf * CFrame.new(0, 3.2, 0), rgb(150, 100, 60), { Material = Enum.Material.Wood })
	part(desk, "Front", Vector3.new(8, 3, 0.3), dcf * CFrame.new(0, 1.5, 1.85), rgb(140, 92, 55), { Material = Enum.Material.Wood })
	for side = -1, 1, 2 do
		part(desk, "Side", Vector3.new(0.3, 3, 4), dcf * CFrame.new(side * 3.85, 1.5, 0), rgb(140, 92, 55), { Material = Enum.Material.Wood })
	end
	deco(desk, "Drawers", Vector3.new(2.5, 2.6, 3.4), dcf * CFrame.new(2.5, 1.6, -0.1), rgb(160, 110, 70), { Material = Enum.Material.Wood })
	for i = 0, 2 do
		deco(desk, "Knob", Vector3.new(0.3, 0.2, 0.2), dcf * CFrame.new(2.5, 0.8 + i * 0.85, -1.85), COLORS.Metal)
	end
	deco(desk, "Monitor", Vector3.new(2.4, 1.6, 0.2), dcf * CFrame.new(-2, 4.4, -0.8), rgb(30, 30, 35))
	deco(desk, "MonitorScreen", Vector3.new(2.2, 1.4, 0.05), dcf * CFrame.new(-2, 4.4, -0.68), rgb(90, 160, 255), { Material = Enum.Material.Neon, Transparency = 0.2 })
	deco(desk, "Stand", Vector3.new(0.3, 0.6, 0.3), dcf * CFrame.new(-2, 3.6, -0.8), rgb(30, 30, 35))
	deco(desk, "Mug", Vector3.new(0.5, 0.6, 0.5), dcf * CFrame.new(0.6, 3.7, 0.6), rgb(255, 120, 90), { Shape = Enum.PartType.Cylinder, CFrame = dcf * CFrame.new(0.6, 3.7, 0.6) * CFrame.Angles(0, 0, math.rad(90)) })
	deco(desk, "Apple", Vector3.new(0.6, 0.6, 0.6), dcf * CFrame.new(1.4, 3.7, 0.9), rgb(220, 40, 50), { Shape = Enum.PartType.Ball })
	for i = 0, 3 do
		deco(desk, "Paper", Vector3.new(1.4, 0.06, 1.8), dcf * CFrame.new(-0.4, 3.43 + i * 0.07, 0.3) * CFrame.Angles(0, math.rad(i * 7), 0), rgb(250, 250, 245))
	end
	local basket = deco(desk, "Basket", Vector3.new(2, 0.7, 1.4), dcf * CFrame.new(2.7, 3.75, 0.6), rgb(200, 160, 90), { Material = Enum.Material.Fabric })
	local basketSign = deco(desk, "BasketSign", Vector3.new(2, 0.5, 0.05), dcf * CFrame.new(2.7, 3.65, 1.33), rgb(255, 255, 255))
	surfaceText(basketSign, Enum.NormalId.Back, "CONFISCATED", { TextColor3 = rgb(200, 40, 40) })
	-- Teacher chair
	local chairCf = dcf * CFrame.new(-1, 0, -2.6)
	deco(desk, "ChairSeat", Vector3.new(2.2, 0.4, 2.2), chairCf * CFrame.new(0, 2, 0), rgb(40, 40, 50))
	deco(desk, "ChairBack", Vector3.new(2.2, 2.6, 0.3), chairCf * CFrame.new(0, 3.4, -1), rgb(40, 40, 50))
	deco(desk, "ChairPole", Vector3.new(0.3, 1.8, 0.3), chairCf * CFrame.new(0, 1, 0), COLORS.Metal)

	-- Bookshelf + globe (front right)
	local shelf = model("Bookshelf", room)
	local scf = CFrame.new(25, 0, -23)
	part(shelf, "Frame", Vector3.new(6, 8, 2), scf * CFrame.new(0, 4, 0), rgb(150, 100, 60), { Material = Enum.Material.Wood })
	for row = 0, 2 do
		for i = 0, 8 do
			local h = 1.3 + ((i * 7 + row * 3) % 4) * 0.15
			deco(shelf, "Book", Vector3.new(0.5, h, 1.4), scf * CFrame.new(-2.3 + i * 0.58, 1.1 + row * 2.6 + h / 2 - 0.3, -0.75), Color3.fromHSV(((i * 3 + row * 5) % 11) / 11, 0.6, 0.85))
		end
	end
	deco(shelf, "GlobeStand", Vector3.new(0.8, 0.2, 0.8), scf * CFrame.new(0, 8.1, 0), rgb(90, 60, 40))
	deco(shelf, "Globe", Vector3.new(1.6, 1.6, 1.6), scf * CFrame.new(0, 9, 0), rgb(60, 140, 230), { Shape = Enum.PartType.Ball })
	deco(shelf, "Continent", Vector3.new(0.8, 0.7, 0.2), scf * CFrame.new(0.2, 9.1, -0.72), rgb(90, 190, 90))

	return { boardText = text, clock = clock, basket = basket }
end

---------------------------------------------------------------------------------------------
-- Back of the room: posters, cubbies, detention corner
---------------------------------------------------------------------------------------------

local function buildBack(room)
	local back = folder("Back", room)
	local zWall = L.Depth / 2
	local posterSpecs = {
		{ "HANG IN THERE\n(class ends eventually)", 10, rgb(255, 200, 140) },
		{ "MATH IS\nEVERYWHERE\n2 + 2 = 4", -2, rgb(190, 240, 190) },
		{ "CLASS RULES\n1. Be kind\n2. No phones\n3. NO PHONES", 13.5, rgb(255, 230, 240) },
	}
	for _, spec in ipairs(posterSpecs) do
		local poster = deco(back, "Poster", Vector3.new(5, 6, 0.1), CFrame.new(spec[2], 9, zWall - 0.1), spec[3])
		surfaceText(poster, Enum.NormalId.Front, spec[1])
	end
	-- Cubbies with backpacks
	local cub = model("Cubbies", room)
	for i = 0, 5 do
		local x = -3 + i * 2.4
		part(cub, "Cubby", Vector3.new(2.3, 2.3, 1.6), CFrame.new(x, 1.2, zWall - 0.9), rgb(230, 200, 150), { Material = Enum.Material.Wood })
		deco(cub, "Backpack", Vector3.new(1.4, 1.4, 1), CFrame.new(x, 1.5, zWall - 1.6), Color3.fromHSV(i / 6, 0.6, 0.9), { Material = Enum.Material.Fabric })
	end
	-- Detention corner (back left): a tiny desk facing the wall, a stool and a sign.
	local det = model("DetentionCorner", room)
	local dx, dz = L.DetentionDesk[1], L.DetentionDesk[2]
	local dcf = CFrame.new(dx, 0, dz)
	deco(det, "Rug", Vector3.new(7, 0.05, 6), dcf * CFrame.new(0, 0.03, 0.5), rgb(200, 80, 80), { Material = Enum.Material.Fabric })
	part(det, "DeskTop", Vector3.new(3, 0.25, 2), dcf * CFrame.new(0, 2.4, 2.4), rgb(160, 160, 165))
	for sx = -1, 1, 2 do
		deco(det, "Leg", Vector3.new(0.2, 2.3, 0.2), dcf * CFrame.new(sx * 1.3, 1.15, 2.4), COLORS.Metal)
	end
	local seat = Instance.new("Seat")
	seat.Name = "DetentionSeat"
	seat.Size = Vector3.new(1.6, 0.3, 1.6)
	seat.CFrame = CFrame.lookAt(Vector3.new(dx, 1.3, dz), Vector3.new(dx, 1.3, dz + 5))
	seat.Color = rgb(90, 90, 100)
	seat.Material = Enum.Material.SmoothPlastic
	seat.Anchored = true
	seat.Parent = det
	deco(det, "StoolLeg", Vector3.new(0.3, 1.2, 0.3), dcf * CFrame.new(0, 0.6, 0), COLORS.Metal)
	local sign = deco(det, "Sign", Vector3.new(6, 2.4, 0.1), CFrame.new(dx, 8, zWall - 0.1), rgb(255, 90, 90))
	surfaceText(sign, Enum.NormalId.Front, "DETENTION\nthink about what you did", { TextColor3 = rgb(255, 255, 255) })
	local timer = deco(det, "Timer", Vector3.new(2, 1, 0.1), CFrame.new(dx, 5.6, zWall - 0.1), rgb(30, 30, 40))
	local timerLabel = surfaceText(timer, Enum.NormalId.Front, "", { TextColor3 = rgb(255, 80, 80), Font = Enum.Font.Code })
	-- A second seat for when two students are in detention at once.
	local seat2 = seat:Clone()
	seat2.Name = "DetentionSeat2"
	seat2.CFrame = seat.CFrame * CFrame.new(-3.2, 0, 0)
	seat2.Parent = det
	return { seats = { seat, seat2 }, timerLabel = timerLabel }
end

---------------------------------------------------------------------------------------------
-- Student desks
---------------------------------------------------------------------------------------------

local function buildDesks(room)
	local desksFolder = folder("Desks", room)
	local desks = {}
	local index = 0
	for row, z in ipairs(L.DeskRows) do
		for col, x in ipairs(L.DeskColumns) do
			index += 1
			local vip = row == #L.DeskRows and (col == 1 or col == #L.DeskColumns)
			local m = model("Desk" .. index, desksFolder)
			m:SetAttribute("DeskIndex", index)
			local topColor = if vip then rgb(120, 70, 40) else COLORS.DeskTop
			local top = part(m, "Top", Vector3.new(4, 0.25, 2.6), CFrame.new(x, 2.7, z), topColor, { Material = Enum.Material.Wood })
			deco(m, "Shelf", Vector3.new(3.6, 0.15, 2.2), CFrame.new(x, 2.05, z), COLORS.Metal)
			deco(m, "ShelfBack", Vector3.new(3.6, 0.65, 0.1), CFrame.new(x, 2.38, z - 1.05), COLORS.Metal)
			for sx = -1, 1, 2 do
				deco(m, "Leg", Vector3.new(0.18, 2.6, 0.18), CFrame.new(x + sx * 1.8, 1.3, z - 1.1), COLORS.Metal)
				deco(m, "Leg", Vector3.new(0.18, 2.6, 0.18), CFrame.new(x + sx * 1.8, 1.3, z + 1.1), COLORS.Metal)
			end
			-- Textbook + pencil on every desk
			deco(m, "Book", Vector3.new(1.3, 0.22, 1.7), CFrame.new(x + 1.1, 2.94, z - 0.2) * CFrame.Angles(0, math.rad(8), 0), Color3.fromHSV((index % 7) / 7, 0.55, 0.85))
			deco(m, "Pencil", Vector3.new(0.1, 0.1, 1), CFrame.new(x - 0.4, 2.88, z + 0.4) * CFrame.Angles(0, math.rad(70), 0), rgb(255, 205, 60))
			-- Chair (a Seat the student sits in)
			local chairZ = z + 2.3
			local seat = Instance.new("Seat")
			seat.Name = "Seat"
			seat.Size = Vector3.new(2.2, 0.3, 2)
			seat.CFrame = CFrame.new(x, 1.7, chairZ)
			seat.Color = if vip then COLORS.Gold else COLORS.Chair
			seat.Material = Enum.Material.SmoothPlastic
			seat.Anchored = true
			seat.Parent = m
			deco(m, "ChairBack", Vector3.new(2.2, 2, 0.25), CFrame.new(x, 3.2, chairZ + 1.0), if vip then COLORS.Gold else COLORS.Chair)
			for sx = -1, 1, 2 do
				deco(m, "ChairLeg", Vector3.new(0.15, 1.6, 0.15), CFrame.new(x + sx * 0.95, 0.8, chairZ - 0.85), COLORS.Metal)
				deco(m, "ChairLeg", Vector3.new(0.15, 1.6, 0.15), CFrame.new(x + sx * 0.95, 0.8, chairZ + 0.85), COLORS.Metal)
			end
			if vip then
				deco(m, "Cushion", Vector3.new(2, 0.3, 1.8), CFrame.new(x, 1.95, chairZ), rgb(200, 40, 120), { Material = Enum.Material.Fabric })
				deco(m, "GoldTrim", Vector3.new(4.1, 0.12, 2.7), CFrame.new(x, 2.62, z), COLORS.Gold, { Material = Enum.Material.Foil })
				local plate = deco(m, "VipPlate", Vector3.new(1.6, 0.4, 0.05), CFrame.new(x, 2.4, z - 1.32), COLORS.Gold, { Material = Enum.Material.Foil })
				surfaceText(plate, Enum.NormalId.Front, "VIP", { TextColor3 = rgb(80, 40, 10) })
			end
			-- Name card (set when someone sits here)
			local card = deco(m, "NameCard", Vector3.new(1.6, 0.5, 0.05), CFrame.new(x - 1.1, 3.05, z - 1.1) * CFrame.Angles(math.rad(-15), 0, 0), rgb(255, 255, 255))
			local cardLabel = surfaceText(card, Enum.NormalId.Back, "", { TextColor3 = rgb(40, 40, 80) })
			local studentPos = Vector3.new(x, 0, chairZ)
			table.insert(desks, {
				index = index,
				row = row,
				col = col,
				vip = vip,
				model = m,
				top = top,
				seat = seat,
				cardLabel = cardLabel,
				x = x,
				z = chairZ, -- where the student (and their phone) is, for detection
				position = studentPos,
				phoneUp = CFrame.lookAt(Vector3.new(x + 0.3, 3.55, chairZ - 1.05), Vector3.new(x + 0.3, 4.6, chairZ + 0.6)),
				phoneDown = CFrame.new(x - 0.6, 2.2, z + 0.2) * CFrame.Angles(math.rad(-90), 0, 0),
				decor = CFrame.new(x - 1.35, 2.83, z - 0.6),
				planeLand = CFrame.new(x + 0.6, 2.9, z + 0.3),
			})
		end
	end
	return desks
end

---------------------------------------------------------------------------------------------
-- Hallway (lobby)
---------------------------------------------------------------------------------------------

local function buildHallway(parent)
	local hall = folder("Hallway", parent)
	local x0, x1 = L.Width / 2 + 1, L.Width / 2 + 21
	local z0, z1 = -32, 42
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local H = 14
	part(hall, "Floor", Vector3.new(x1 - x0, 1, z1 - z0), CFrame.new(cx, -0.5, cz), COLORS.HallFloorA)
	for iz = 0, (z1 - z0) / 4 - 1 do
		for ix = 0, (x1 - x0) / 4 - 1 do
			if (ix + iz) % 2 == 0 then
				deco(hall, "Tile", Vector3.new(4, 0.04, 4), CFrame.new(x0 + 2 + ix * 4, 0.02, z0 + 2 + iz * 4), COLORS.HallFloorB)
			end
		end
	end
	part(hall, "Ceiling", Vector3.new(x1 - x0 + 2, 1, z1 - z0 + 2), CFrame.new(cx, H + 0.5, cz), rgb(240, 240, 235))
	part(hall, "FarWall", Vector3.new(1, H, z1 - z0), CFrame.new(x1 + 0.5, H / 2, cz), rgb(230, 225, 210))
	part(hall, "EndWallA", Vector3.new(x1 - x0 + 2, H, 1), CFrame.new(cx, H / 2, z0 - 0.5), rgb(230, 225, 210))
	part(hall, "EndWallB", Vector3.new(x1 - x0 + 2, H, 1), CFrame.new(cx, H / 2, z1 + 0.5), rgb(230, 225, 210))
	-- Extend the classroom's right wall along the hallway
	part(hall, "NearWallA", Vector3.new(1, H, -L.Depth / 2 - z0), CFrame.new(L.Width / 2 + 0.5, H / 2, (z0 - L.Depth / 2) / 2), rgb(230, 225, 210))
	part(hall, "NearWallB", Vector3.new(1, H, z1 - L.Depth / 2), CFrame.new(L.Width / 2 + 0.5, H / 2, (z1 + L.Depth / 2) / 2), rgb(230, 225, 210))
	for i = 0, 3 do
		local panel = deco(hall, "LightPanel", Vector3.new(4, 0.2, 8), CFrame.new(cx, H - 0.1, z0 + 9 + i * 18), rgb(255, 252, 235), { Material = Enum.Material.Neon })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 20
		light.Brightness = 1.2
		light.Angle = 120
		light.Parent = panel
	end
	-- Lockers along the far wall
	local lockers = folder("Lockers", hall)
	local n = 0
	for z = z0 + 2, z1 - 2, 2.3 do
		if math.abs(z - 6) > 7 then -- leave room for the leaderboard
			n += 1
			local color = if n % 2 == 0 then COLORS.LockerA else COLORS.LockerB
			local lx = x1 - 0.9
			part(lockers, "Locker", Vector3.new(1.8, 8, 2.2), CFrame.new(lx, 4, z), color, { Material = Enum.Material.Metal })
			for v = 0, 2 do
				deco(lockers, "Vent", Vector3.new(0.05, 0.12, 1.2), CFrame.new(lx - 0.92, 7 - v * 0.3, z), color:Lerp(Color3.new(0, 0, 0), 0.35))
			end
			deco(lockers, "Handle", Vector3.new(0.12, 0.6, 0.12), CFrame.new(lx - 0.95, 4, z + 0.7), COLORS.Metal, { Material = Enum.Material.Metal })
		end
	end
	-- Leaderboard
	local boardPart = part(hall, "Leaderboard", Vector3.new(0.5, 9, 12), CFrame.new(x1 - 0.3, 6, 6), rgb(30, 34, 60))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = boardPart
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.Text = "MOST CLOUT EVER"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = rgb(255, 200, 70)
	title.Parent = gui
	local rows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.Position = UDim2.new(0.04, 0, 0.15 + (i - 1) * 0.078, 0)
		row.Size = UDim2.new(0.92, 0, 0.074, 0)
		row.Text = ""
		row.TextScaled = true
		row.Font = Enum.Font.GothamBold
		row.TextColor3 = Color3.new(1, 1, 1)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Parent = gui
		rows[i] = row
	end
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0, 0, 0.94, 0)
	status.Size = UDim2.new(1, 0, 0.05, 0)
	status.Text = ""
	status.TextScaled = true
	status.Font = Enum.Font.Gotham
	status.TextColor3 = rgb(180, 190, 220)
	status.Parent = gui
	local board = { rows = rows, part = boardPart }
	function board.setRows(list, message)
		for i, row in ipairs(rows) do
			local entry = list[i]
			if entry then
				row.Text = string.format("  #%d  %s  -  %s", entry.rank, entry.name, entry.text)
			else
				row.Text = ""
			end
		end
		status.Text = message or "updates every minute"
	end
	board.setRows({}, "loading...")

	-- School Store kiosk (opens the shop)
	local kiosk = model("SchoolStore", hall)
	local kcf = CFrame.new(cx + 3, 0, -20)
	part(kiosk, "Counter", Vector3.new(8, 3.5, 3), kcf * CFrame.new(0, 1.75, 0), rgb(255, 170, 60))
	deco(kiosk, "CounterTop", Vector3.new(8.4, 0.3, 3.4), kcf * CFrame.new(0, 3.6, 0), rgb(250, 250, 250))
	for i = -1, 1, 2 do
		deco(kiosk, "Post", Vector3.new(0.4, 6, 0.4), kcf * CFrame.new(i * 3.8, 6.6, 1.2), rgb(250, 250, 250))
	end
	for i = 0, 5 do
		deco(kiosk, "Awning", Vector3.new(1.4, 0.3, 4), kcf * CFrame.new(-3.5 + i * 1.4, 9.7, 0.5) * CFrame.Angles(math.rad(-12), 0, 0), if i % 2 == 0 then rgb(255, 80, 120) else rgb(255, 255, 255))
	end
	local storeSign = deco(kiosk, "Sign", Vector3.new(7, 1.5, 0.2), kcf * CFrame.new(0, 8.6, -1.4), rgb(40, 40, 70))
	surfaceText(storeSign, Enum.NormalId.Front, "SCHOOL STORE", { TextColor3 = rgb(255, 210, 70) })
	for i = 0, 3 do
		deco(kiosk, "Snack", Vector3.new(0.8, 1.1, 0.5), kcf * CFrame.new(-2.5 + i * 1.6, 4.3, 0.3), Color3.fromHSV(i / 4, 0.7, 1))
	end
	local promptPart = deco(kiosk, "PromptPart", Vector3.new(1, 1, 1), kcf * CFrame.new(0, 3, -2), rgb(255, 255, 255), { Transparency = 1 })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "School Store"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart

	-- Poster: like the game for a code
	local likePoster = deco(hall, "LikePoster", Vector3.new(0.1, 4, 6), CFrame.new(L.Width / 2 + 1.05, 7, 32), rgb(120, 220, 255))
	surfaceText(likePoster, Enum.NormalId.Right, "LIKE THE GAME!\ncode at 1K likes:\nLIKE1K", { TextColor3 = rgb(20, 40, 80) })
	-- Room sign above the classroom door
	local roomSign = deco(hall, "RoomSign", Vector3.new(0.2, 1.6, 7), CFrame.new(L.Width / 2 + 1.1, 11, L.DoorSpot[2]), rgb(40, 40, 70))
	surfaceText(roomSign, Enum.NormalId.Right, "ROOM 104", { TextColor3 = rgb(255, 255, 255) })
	local banner = deco(hall, "Banner", Vector3.new(0.2, 3, 16), CFrame.new(L.Width / 2 + 1.1, 9.5, -12), rgb(255, 90, 90))
	surfaceText(banner, Enum.NormalId.Right, "PHONES AWAY!", { TextColor3 = rgb(255, 255, 255) })

	-- Spawn (welcome mat)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HallwaySpawn"
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.new(cx, 0.1, 10)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = rgb(255, 205, 80)
	spawn.Material = Enum.Material.Fabric
	spawn.Parent = hall
	local decal = Instance.new("SurfaceGui")
	decal.Face = Enum.NormalId.Top
	decal.Parent = spawn
	local mat = Instance.new("TextLabel")
	mat.BackgroundTransparency = 1
	mat.Size = UDim2.fromScale(1, 1)
	mat.Text = "WELCOME"
	mat.TextScaled = true
	mat.Font = Enum.Font.FredokaOne
	mat.TextColor3 = rgb(140, 60, 20)
	mat.Parent = decal

	local spots = {}
	for i = 0, 11 do
		table.insert(spots, CFrame.new(cx - 4 + (i % 3) * 4, 3, -4 + math.floor(i / 3) * 5))
	end
	return { board = board, prompt = prompt, spawn = spawn, spots = spots, center = Vector3.new(cx, 0, cz) }
end

function ClassroomBuilder.build()
	local old = workspace:FindFirstChild("School")
	if old then
		old:Destroy()
	end
	local school = folder("School", workspace)
	local room = folder("Classroom", school)
	local shell = buildShell(room)
	local front = buildFront(room)
	local back = buildBack(room)
	local desks = buildDesks(room)
	local hall = buildHallway(school)
	local props = folder("Props", school) -- phones, decor, planes (runtime)
	local npcs = folder("NPCs", school)
	return {
		folder = school,
		room = room,
		props = props,
		npcs = npcs,
		desks = desks,
		door = shell.door,
		doorClosed = shell.doorClosed,
		doorOpen = shell.doorOpen,
		boardText = front.boardText,
		clock = front.clock,
		basket = front.basket,
		detentionSeats = back.seats,
		detentionTimer = back.timerLabel,
		board = hall.board,
		shopPrompt = hall.prompt,
		spawn = hall.spawn,
		hallSpots = hall.spots,
		hallCenter = hall.center,
		teacherSpawn = CFrame.new(L.BoardSpot[1], 0, L.BoardSpot[2]),
		principalSpot = { L.DoorSpot[1] - 3, L.DoorSpot[2] - 2 },
	}
end

return ClassroomBuilder
