--[[
	FacilityBuilder - builds the Industrial Crash Lab from code: the lobby (CRASH LAB sign,
	dummy display, upgrade station, results board, leaderboards, tutorial signs, facility
	gate) and the test arena (launch deck with six pads, crash pads, ramps, barriers,
	destructible props, rings, moving targets, landing zones, distance markers, catch
	nets, spectator stands, observation booth, gantries, light towers, fans).

	The layout comes from CourseConfig so the server's objective checks and the world can
	never disagree. Tagging (attributes) used by the crash simulation:
	  CL_Floor = true         floor / ground contact (grouped impacts)
	  CL_Key   = "<id>"       an obstacle that counts as its own impact object
	  CL_Prop  = "<id>"       a destructible prop (see world.props[id])
	  CL_Target = "<id>"      a target (see world.targets[id])
	  CL_Soft  = true         crash pad (bouncy; impacts play the soft sound)
	Returns a `world` table (see the end of build()).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local GameConfig = require(Shared.Config.GameConfig)
local CourseConfig = require(Shared.Config.CourseConfig)
local DummyModel = require(Shared.DummyModel)

local FacilityBuilder = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CYL = Enum.PartType.Cylinder

local C = {
	Concrete = rgb(168, 166, 160),
	ConcreteDark = rgb(132, 130, 126),
	Floor = rgb(150, 152, 150),
	Steel = rgb(98, 104, 114),
	SteelDark = rgb(56, 60, 68),
	Yellow = rgb(255, 200, 40),
	Black = rgb(28, 28, 30),
	White = rgb(240, 240, 236),
	Blue = rgb(60, 130, 220),
	Red = rgb(225, 70, 55),
	Orange = rgb(255, 140, 40),
	Glass = rgb(170, 210, 230),
	Green = rgb(80, 210, 120),
}

local partCount = 0
local folder

local function part(props)
	local p = Instance.new(props.Class or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or M.SmoothPlastic
	p.Color = props.Color or C.Concrete
	p.Size = props.Size
	p.CFrame = props.CFrame
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	if props.CanQuery ~= nil then
		p.CanQuery = props.CanQuery
	end
	if props.CastShadow ~= nil then
		p.CastShadow = props.CastShadow
	end
	p.Name = props.Name or "Part"
	p.Parent = props.Parent or folder
	partCount += 1
	return p
end

local function deco(props)
	props.CanCollide = false
	props.CanQuery = false
	local p = part(props)
	p.CanTouch = false
	return p
end

local function sub(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or folder
	return f
end

local function surfaceText(target, face, text, props)
	props = props or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = props.PPS or 24
	gui.LightInfluence = props.LightInfluence or 0.2
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = props.Font or Enum.Font.GothamBlack
	label.TextColor3 = props.Color or C.White
	label.TextStrokeTransparency = props.Stroke or 1
	label.Parent = gui
	return label, gui
end

-- Yellow / black hazard stripes along X between two points at height y.
local function hazardStrip(cf, length, width, count, parent)
	local seg = length / count
	for i = 0, count - 1 do
		deco({ Size = Vector3.new(seg, 0.12, width), CFrame = cf * CFrame.new(-length / 2 + seg * (i + 0.5), 0, 0), Color = if i % 2 == 0 then C.Yellow else C.Black, Parent = parent })
	end
end

---------------------------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------------------------

local function buildLobby(world)
	local lobby = sub("Lobby")
	local z0 = GameConfig.Arena.LobbyZ
	-- Floor + walls.
	local floor = part({ Name = "LobbyFloor", Size = Vector3.new(200, 2, 140), CFrame = CFrame.new(0, -1, z0), Color = rgb(122, 124, 128), Material = M.Concrete, Parent = lobby })
	floor:SetAttribute("CL_Floor", true)
	for i = -4, 4 do
		deco({ Size = Vector3.new(0.3, 0.05, 140), CFrame = CFrame.new(i * 20, 0.02, z0), Color = rgb(108, 110, 114), Parent = lobby })
	end
	part({ Name = "BackWall", Size = Vector3.new(200, 40, 2), CFrame = CFrame.new(0, 20, z0 - 70), Color = C.ConcreteDark, Material = M.Concrete, Parent = lobby })
	for _, x in ipairs({ -100, 100 }) do
		part({ Name = "SideWall", Size = Vector3.new(2, 40, 140), CFrame = CFrame.new(x, 20, z0), Color = C.ConcreteDark, Material = M.Concrete, Parent = lobby })
		for zz = -60, 60, 20 do
			deco({ Size = Vector3.new(2.6, 40, 1.4), CFrame = CFrame.new(x, 20, z0 + zz), Color = C.Steel, Material = M.Metal, Parent = lobby })
		end
	end
	hazardStrip(CFrame.new(0, 0.06, z0 + 68), 200, 2, 40, lobby)

	-- Spawn.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 0.5, z0 - 30)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = M.DiamondPlate
	spawn.Color = C.SteelDark
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	partCount += 1
	world.spawn = spawn
	hazardStrip(CFrame.new(0, 1.02, z0 - 37), 14, 1, 7, lobby)

	-- CRASH LAB sign above the back wall.
	local sign = part({ Name = "CrashLabSign", Size = Vector3.new(80, 18, 2), CFrame = CFrame.new(0, 34, z0 - 68), Color = C.Black, Material = M.Metal, Parent = lobby })
	surfaceText(sign, Enum.NormalId.Back, "CRASH LAB", { Color = C.Yellow, PPS = 10, LightInfluence = 0 })
	deco({ Size = Vector3.new(82, 1, 2.4), CFrame = CFrame.new(0, 24.6, z0 - 68), Color = C.Yellow, Material = M.Neon, Parent = lobby })
	deco({ Size = Vector3.new(82, 1, 2.4), CFrame = CFrame.new(0, 43.4, z0 - 68), Color = C.Yellow, Material = M.Neon, Parent = lobby })
	local subtitle = deco({ Size = Vector3.new(60, 5, 1), CFrame = CFrame.new(0, 18.5, z0 - 68.5), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
	surfaceText(subtitle, Enum.NormalId.Back, "BUILD  -  LAUNCH  -  CRASH  -  REPEAT", { Color = C.White, PPS = 16 })

	-- Dummy display: three dummies in poses on pedestals.
	world.displayDummies = {}
	for i, x in ipairs({ -14, 0, 14 }) do
		part({ Name = "Pedestal", Size = Vector3.new(7, 3, 7), CFrame = CFrame.new(x, 1.5, z0 + 5), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
		hazardStrip(CFrame.new(x, 3.02, z0 + 1.6), 7, 0.6, 6, lobby)
		local skin = ({ "Default", "Safety", "Lab" })[i]
		local cf = CFrame.new(x, 3 + DummyModel.RootHeight, z0 + 5) * CFrame.Angles(0, math.rad(180 + (i - 2) * 20), 0)
		local dummy = DummyModel.build(skin, cf, { ragdoll = false })
		dummy.Name = "DisplayDummy"
		dummy.Parent = lobby
		partCount += #dummy:GetDescendants()
		table.insert(world.displayDummies, dummy)
	end
	local plaque = deco({ Size = Vector3.new(30, 3, 0.6), CFrame = CFrame.new(0, 1.6, z0 + 0.9), Color = C.Black, Parent = lobby })
	surfaceText(plaque, Enum.NormalId.Front, "MEET THE TEST TEAM: 100% DUMMY, 0% INJURIES", { Color = C.Yellow, PPS = 20 })

	-- Upgrade station (kiosk with a screen and prompt).
	local stationCF = CFrame.new(-48, 0, z0 + 20) * CFrame.Angles(0, math.rad(-45), 0)
	local kiosk = part({ Name = "UpgradeStation", Size = Vector3.new(10, 9, 4), CFrame = stationCF * CFrame.new(0, 4.5, 0), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
	local screen = deco({ Size = Vector3.new(8, 4.5, 0.3), CFrame = stationCF * CFrame.new(0, 6, -2.1), Color = rgb(20, 30, 40), Material = M.SmoothPlastic, Parent = lobby })
	surfaceText(screen, Enum.NormalId.Front, "UPGRADES", { Color = C.Yellow, PPS = 30, LightInfluence = 0 })
	deco({ Size = Vector3.new(10.4, 0.6, 4.4), CFrame = stationCF * CFrame.new(0, 9.2, 0), Color = C.Yellow, Material = M.Neon, Parent = lobby })
	local stationLight = Instance.new("PointLight")
	stationLight.Color = C.Yellow
	stationLight.Range = 16
	stationLight.Brightness = 1.2
	stationLight.Parent = screen
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Upgrades"
	prompt.ObjectText = "Machine Upgrade Station"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = kiosk
	world.stationPrompt = prompt
	world.stationScreen = screen

	-- Cosmetics locker (coins + optional Robux cosmetics).
	local lockerCF = CFrame.new(48, 0, z0 + 20) * CFrame.Angles(0, math.rad(45), 0)
	local locker = part({ Name = "DummyLocker", Size = Vector3.new(10, 9, 4), CFrame = lockerCF * CFrame.new(0, 4.5, 0), Color = rgb(70, 100, 150), Material = M.Metal, Parent = lobby })
	local lockerScreen = deco({ Size = Vector3.new(8, 4.5, 0.3), CFrame = lockerCF * CFrame.new(0, 6, -2.1), Color = rgb(20, 30, 40), Parent = lobby })
	surfaceText(lockerScreen, Enum.NormalId.Front, "DUMMY LOCKER", { Color = C.White, PPS = 30, LightInfluence = 0 })
	local lockerPrompt = Instance.new("ProximityPrompt")
	lockerPrompt.ActionText = "Customize"
	lockerPrompt.ObjectText = "Dummy Locker"
	lockerPrompt.KeyboardKeyCode = Enum.KeyCode.E
	lockerPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	lockerPrompt.MaxActivationDistance = 12
	lockerPrompt.RequiresLineOfSight = false
	lockerPrompt.Parent = locker
	world.lockerPrompt = lockerPrompt

	-- Results board (recent runs) + two leaderboards.
	local function board(name, cf, title, rowsCount)
		local b = part({ Name = name, Size = Vector3.new(22, 16, 1), CFrame = cf, Color = C.Black, Material = M.Metal, Parent = lobby })
		deco({ Size = Vector3.new(22.6, 0.6, 1.4), CFrame = cf * CFrame.new(0, 8.2, 0), Color = C.Yellow, Material = M.Neon, Parent = lobby })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Parent = b
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Size = UDim2.new(1, 0, 0.16, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = title
		titleLabel.TextScaled = true
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.TextColor3 = C.Yellow
		titleLabel.Parent = gui
		local rows = {}
		for i = 1, rowsCount do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(0.92, 0, 0.8 / rowsCount, 0)
			row.Position = UDim2.new(0.04, 0, 0.18 + (i - 1) * 0.8 / rowsCount, 0)
			row.BackgroundTransparency = 1
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Font = Enum.Font.GothamMedium
			row.TextColor3 = C.White
			row.Text = string.format("%d. ---", i)
			row.Parent = gui
			rows[i] = row
		end
		return { part = b, rows = rows, title = titleLabel }
	end
	world.boards = {
		score = board("BestScoreBoard", CFrame.new(-72, 12, z0 - 30) * CFrame.Angles(0, math.rad(-90), 0), "TOP SCORES", 10),
		distance = board("DistanceBoard", CFrame.new(72, 12, z0 - 30) * CFrame.Angles(0, math.rad(90), 0), "FARTHEST FLIGHTS", 10),
	}
	world.resultsBoard = board("ResultsBoard", CFrame.new(-62, 12, z0 - 67) * CFrame.Angles(0, math.rad(180), 0), "LATEST TESTS", 6)

	-- Tutorial area: three numbered signs on the route from spawn to the launch deck.
	local steps = { "1  WALK TO A LAUNCH PAD", "2  PRESS LAUNCH", "3  EARN COINS  -  UPGRADE" }
	for i, text in ipairs(steps) do
		local s = deco({ Size = Vector3.new(16, 4, 0.5), CFrame = CFrame.new(-30 + (i - 1) * 30, 5, z0 + 45), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
		surfaceText(s, Enum.NormalId.Front, text, { Color = C.Yellow, PPS = 20 })
		deco({ Size = Vector3.new(0.5, 3, 0.5), CFrame = CFrame.new(-30 + (i - 1) * 30, 1.5, z0 + 45), Color = C.Steel, Parent = lobby })
	end
	-- Floor arrows toward the deck.
	for i = 0, 4 do
		deco({ Class = "WedgePart", Size = Vector3.new(4, 0.1, 3), CFrame = CFrame.new(0, 0.06, z0 + 22 + i * 9), Color = C.Yellow, Material = M.Neon, Parent = lobby })
	end

	-- Facility gate (future facilities, unlocked by real progression).
	local gateCF = CFrame.new(99, 0, z0 + 20)
	part({ Name = "GateFrame", Size = Vector3.new(4, 26, 40), CFrame = gateCF * CFrame.new(0, 13, 0), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
	local door = part({ Name = "GateDoor", Size = Vector3.new(1, 20, 30), CFrame = gateCF * CFrame.new(-2.6, 10, 0), Color = C.Yellow, Material = M.DiamondPlate, Parent = lobby })
	hazardStrip(CFrame.new(96.5, 20.6, z0 + 20) * CFrame.Angles(0, math.rad(90), 0), 30, 0.8, 10, lobby)
	local gateSign = deco({ Size = Vector3.new(0.5, 4, 26), CFrame = gateCF * CFrame.new(-3.4, 23, 0), Color = C.Black, Parent = lobby })
	local gateLabel = surfaceText(gateSign, Enum.NormalId.Left, "FUTURE FACILITIES", { Color = C.Yellow, PPS = 16 })
	local gatePrompt = Instance.new("ProximityPrompt")
	gatePrompt.ActionText = "View"
	gatePrompt.ObjectText = "Facility Access"
	gatePrompt.KeyboardKeyCode = Enum.KeyCode.E
	gatePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	gatePrompt.MaxActivationDistance = 14
	gatePrompt.RequiresLineOfSight = false
	gatePrompt.Parent = door
	world.gate = { door = door, prompt = gatePrompt, label = gateLabel }

	-- Exhibit: a test car crumpled against a barrier (the lab's "greatest hit").
	local carCF = CFrame.new(34, 0, z0 - 6) * CFrame.Angles(0, math.rad(-25), 0)
	part({ Name = "ExhibitPlinth", Size = Vector3.new(22, 1, 14), CFrame = carCF * CFrame.new(0, 0.5, 0), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
	hazardStrip(carCF * CFrame.new(0, 1.05, 6.6), 22, 0.8, 10, lobby)
	part({ Name = "CarBody", Size = Vector3.new(6.5, 2.4, 10), CFrame = carCF * CFrame.new(0, 2.8, 1), Color = C.Red, Material = M.Metal, Parent = lobby })
	part({ Name = "CarCrumple", Class = "WedgePart", Size = Vector3.new(6.5, 2.4, 3), CFrame = carCF * CFrame.new(0, 2.8, -5.4) * CFrame.Angles(math.rad(15), 0, 0), Color = rgb(190, 60, 50), Material = M.Metal, Parent = lobby })
	part({ Name = "CarCabin", Size = Vector3.new(5.6, 2, 5), CFrame = carCF * CFrame.new(0, 5, 2.4), Color = rgb(200, 220, 235), Material = M.Glass, Transparency = 0.3, Parent = lobby })
	for _, w in ipairs({ { -3.3, -2.8 }, { 3.3, -2.8 }, { -3.3, 4.2 }, { 3.3, 4.2 } }) do
		deco({ Size = Vector3.new(0.8, 2.6, 2.6), CFrame = carCF * CFrame.new(w[1], 2.3, w[2]), Shape = CYL, Color = C.Black, Material = M.SmoothPlastic, Parent = lobby })
	end
	part({ Name = "ExhibitBarrier", Size = Vector3.new(9, 4, 2), CFrame = carCF * CFrame.new(0, 3, -7.8), Color = C.White, Material = M.Concrete, Parent = lobby })
	hazardStrip(carCF * CFrame.new(0, 5.06, -7.8), 9, 2, 6, lobby)
	local passenger = DummyModel.build("Default", carCF * CFrame.new(0, 5.2, 1.6) * CFrame.Angles(math.rad(-25), 0, 0), { ragdoll = false })
	passenger.Parent = lobby
	partCount += #passenger:GetDescendants()
	-- Safety pillars, tyre stacks and barrels around the hall.
	for _, spot in ipairs({ { -96, z0 - 66 }, { 96, z0 - 66 }, { -96, z0 + 66 }, { 96, z0 + 66 } }) do
		for k = 0, 5 do
			deco({ Size = Vector3.new(3, 4, 3), CFrame = CFrame.new(spot[1], 2 + k * 4, spot[2]), Color = if k % 2 == 0 then C.Yellow else C.Black, Parent = lobby })
		end
	end
	for _, spot in ipairs({ { -80, z0 - 50 }, { -84, z0 - 44 }, { 80, z0 + 40 } }) do
		for k = 0, 2 do
			deco({ Size = Vector3.new(1.4, 4, 4), CFrame = CFrame.new(spot[1], 0.7 + k * 1.4, spot[2]) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = rgb(36, 36, 38), Parent = lobby })
		end
	end
	for i, spot in ipairs({ { 84, z0 - 52 }, { 88, z0 - 48 }, { 84, z0 - 46 }, { -84, z0 + 44 } }) do
		local barrel = part({ Name = "Barrel", Size = Vector3.new(4.5, 3, 3), CFrame = CFrame.new(spot[1], 2.25, spot[2]) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = if i % 2 == 0 then C.Blue else C.Orange, Material = M.Metal, Parent = lobby })
		deco({ Size = Vector3.new(0.3, 3.1, 3.1), CFrame = barrel.CFrame, Shape = CYL, Color = C.White, Parent = lobby })
	end
	-- Floor logo stripe down the centre aisle.
	deco({ Size = Vector3.new(10, 0.05, 50), CFrame = CFrame.new(0, 0.03, z0 + 40), Color = rgb(56, 58, 64), Parent = lobby })

	-- Ceiling lights over the lobby.
	for _, x in ipairs({ -50, 0, 50 }) do
		local lamp = deco({ Size = Vector3.new(10, 0.6, 3), CFrame = CFrame.new(x, 30, z0 - 10), Color = rgb(255, 244, 220), Material = M.Neon, Parent = lobby })
		local l = Instance.new("SurfaceLight")
		l.Face = Enum.NormalId.Bottom
		l.Range = 40
		l.Angle = 110
		l.Brightness = 1.4
		l.Color = rgb(255, 238, 210)
		l.Parent = lamp
	end
	local vent = deco({ Size = Vector3.new(6, 6, 1), CFrame = CFrame.new(-90, 30, z0 - 69), Color = C.Steel, Material = M.Metal, Parent = lobby })
	vent:SetAttribute("Ambient", "Ventilation")
	local hum = deco({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(-48, 8, z0 + 20), Color = C.Steel, Transparency = 1, Parent = lobby })
	hum:SetAttribute("Ambient", "ElectricHum")
end

---------------------------------------------------------------------------------------------
-- Launch deck
---------------------------------------------------------------------------------------------

local function buildDeck(world)
	local deck = sub("LaunchDeck")
	local deckTop = 1
	local floor = part({ Name = "Deck", Size = Vector3.new(150, deckTop, 30), CFrame = CFrame.new(0, deckTop / 2, -8), Color = C.SteelDark, Material = M.DiamondPlate, Parent = deck })
	floor:SetAttribute("CL_Floor", true)
	hazardStrip(CFrame.new(0, deckTop + 0.06, 6.4), 150, 1.2, 30, deck)
	hazardStrip(CFrame.new(0, deckTop + 0.06, -22.4), 150, 1.2, 30, deck)
	-- Ramp from the lobby floor up onto the deck.
	part({ Class = "WedgePart", Name = "DeckRamp", Size = Vector3.new(60, deckTop, 6), CFrame = CFrame.new(0, deckTop / 2, -26), Color = C.SteelDark, Material = M.DiamondPlate, Parent = deck })
	world.pads = {}
	local count = GameConfig.PadCount
	for i = 1, count do
		local x = (i - (count + 1) / 2) * GameConfig.PadSpacing
		-- Pads aim slightly toward the centre line (they converge ~280 studs out).
		local yaw = math.atan2(-x, 280)
		local cf = CFrame.new(x, deckTop, 0) * CFrame.Angles(0, yaw, 0)
		local pad = part({ Name = "Pad" .. i, Size = Vector3.new(13, 0.3, 13), CFrame = cf * CFrame.new(0, 0.15, 0), Color = rgb(40, 44, 52), Material = M.Metal, Parent = deck })
		local glow = deco({ Name = "PadGlow", Size = Vector3.new(13.4, 0.15, 13.4), CFrame = cf * CFrame.new(0, 0.05, 0), Color = C.Green, Material = M.Neon, Parent = deck })
		local numberPost = deco({ Size = Vector3.new(3, 3, 0.4), CFrame = cf * CFrame.new(5, 4, -6.4), Color = C.Black, Parent = deck })
		local label = surfaceText(numberPost, Enum.NormalId.Front, tostring(i), { Color = C.Yellow, PPS = 30 })
		deco({ Size = Vector3.new(0.4, 2.5, 0.4), CFrame = cf * CFrame.new(5, 1.25, -6.4), Color = C.Steel, Parent = deck })
		local ownerBoard = deco({ Size = Vector3.new(8, 1.6, 0.3), CFrame = cf * CFrame.new(0, 9.5, -6.6), Color = C.Black, Parent = deck })
		local ownerLabel = surfaceText(ownerBoard, Enum.NormalId.Front, "FREE  -  PRESS E", { Color = C.Green, PPS = 30, LightInfluence = 0 })
		deco({ Size = Vector3.new(0.4, 8, 0.4), CFrame = cf * CFrame.new(-3.6, 5.6, -6.6), Color = C.Steel, Parent = deck })
		deco({ Size = Vector3.new(0.4, 8, 0.4), CFrame = cf * CFrame.new(3.6, 5.6, -6.6), Color = C.Steel, Parent = deck })
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use Launcher"
		prompt.ObjectText = "Launch Pad " .. i
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad
		local slot = sub("Machine", deck)
		slot.Name = "PadMachine" .. i
		-- Where the owner stands while launching: behind the machine, FACING down the course
		-- (a character faces its LookVector, -Z, so turn half way round).
		local stand = cf * CFrame.new(0, 3, -10) * CFrame.Angles(0, math.pi, 0)
		table.insert(world.pads, {
			index = i,
			cframe = cf,
			yaw = yaw,
			part = pad,
			glow = glow,
			prompt = prompt,
			slot = slot,
			label = label,
			ownerLabel = ownerLabel,
			stand = stand,
		})
	end
	-- Control booth at the end of the deck (off the players' camera line).
	local boothX = -64
	part({ Name = "ControlBooth", Size = Vector3.new(22, 10, 12), CFrame = CFrame.new(boothX, 14, -12), Color = C.Steel, Material = M.Metal, Parent = deck })
	deco({ Size = Vector3.new(20, 5, 0.4), CFrame = CFrame.new(boothX, 15, -5.8), Color = C.Glass, Material = M.Glass, Transparency = 0.45, Parent = deck })
	for _, x in ipairs({ -10, 10 }) do
		part({ Name = "BoothLeg", Size = Vector3.new(1.4, 9, 1.4), CFrame = CFrame.new(boothX + x, 4.5, -12), Color = C.SteelDark, Material = M.Metal, Parent = deck })
	end
	local lights = deco({ Name = "DeckLights", Size = Vector3.new(20, 0.6, 0.6), CFrame = CFrame.new(boothX, 19.4, -5.9), Color = C.Red, Material = M.Neon, Parent = deck })
	world.deckLights = lights
	local machinery = deco({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(boothX, 10, -12), Transparency = 1, Color = C.Steel, Parent = deck })
	machinery:SetAttribute("Ambient", "Machinery")
end

---------------------------------------------------------------------------------------------
-- Arena
---------------------------------------------------------------------------------------------

local function key(p, id)
	p:SetAttribute("CL_Key", id)
	return p
end

local function buildArena(world)
	local arena = sub("Arena")
	local A = GameConfig.Arena
	local length, half = A.Length, A.HalfWidth
	-- Floor: concrete slabs with lane lines.
	for i = 0, 5 do
		local slabLength = (length + 40) / 6
		local f = part({ Name = "ArenaFloor", Size = Vector3.new(half * 2 + 4, 2, slabLength), CFrame = CFrame.new(0, -1, 6 + slabLength * (i + 0.5)), Color = if i % 2 == 0 then C.Floor else rgb(144, 146, 144), Material = M.Concrete, Parent = arena })
		f:SetAttribute("CL_Floor", true)
	end
	-- Outer apron (spectator area ground).
	for _, x in ipairs({ -1, 1 }) do
		local apron = part({ Name = "Apron", Size = Vector3.new(60, 2, length + 60), CFrame = CFrame.new(x * (half + 32), -1, length / 2), Color = rgb(116, 118, 118), Material = M.Concrete, Parent = arena })
		apron:SetAttribute("CL_Floor", true)
	end
	for _, x in ipairs({ -40, 0, 40 }) do
		deco({ Size = Vector3.new(0.4, 0.04, length), CFrame = CFrame.new(x, 0.02, length / 2 + 6), Color = rgb(230, 230, 224), Parent = arena })
	end

	-- Distance markers every 50 studs: floor line + sign on both sides.
	world.markers = {}
	for d = CourseConfig.MarkerEvery, length - 40, CourseConfig.MarkerEvery do
		local isGoal = table.find(CourseConfig.DistanceGoals, d) ~= nil
		local col = if isGoal then C.Yellow else C.White
		deco({ Size = Vector3.new(half * 2, 0.06, 0.8), CFrame = CFrame.new(0, 0.04, d), Color = col, Material = if isGoal then M.Neon else M.SmoothPlastic, Parent = arena })
		for _, x in ipairs({ -1, 1 }) do
			local post = deco({ Size = Vector3.new(0.6, 8, 0.6), CFrame = CFrame.new(x * (half - 3), 4, d), Color = C.Steel, Parent = arena })
			local signPart = deco({ Size = Vector3.new(6, 3.4, 0.4), CFrame = post.CFrame * CFrame.new(0, 5, 0), Color = if isGoal then C.Yellow else C.Black, Parent = arena })
			surfaceText(signPart, Enum.NormalId.Back, tostring(d), { Color = if isGoal then C.Black else C.White, PPS = 24 })
			surfaceText(signPart, Enum.NormalId.Front, tostring(d), { Color = if isGoal then C.Black else C.White, PPS = 24 })
		end
		table.insert(world.markers, d)
	end

	-- Side nets (glass lower wall + net frame) and the far catch net.
	for _, x in ipairs({ -1, 1 }) do
		local wall = part({ Name = "SideGlass", Size = Vector3.new(1, 14, length + 20), CFrame = CFrame.new(x * half, 7, length / 2 + 4), Color = C.Glass, Material = M.Glass, Transparency = 0.55, Parent = arena })
		key(wall, "SideWall")
		for z = 10, length, 40 do
			part({ Name = "NetPost", Size = Vector3.new(1.4, 70, 1.4), CFrame = CFrame.new(x * (half + 0.6), 35, z), Color = C.Steel, Material = M.Metal, Parent = arena })
		end
		local net = part({ Name = "SideNet", Size = Vector3.new(0.4, 56, length + 20), CFrame = CFrame.new(x * half, 42, length / 2 + 4), Color = rgb(40, 44, 50), Material = M.Fabric, Transparency = 0.82, Parent = arena })
		key(net, "SideNet")
		deco({ Size = Vector3.new(1.2, 1.2, length + 20), CFrame = CFrame.new(x * (half + 0.6), 70, length / 2 + 4), Color = C.Yellow, Material = M.Metal, Parent = arena })
	end
	local catch = part({ Name = "CatchNet", Size = Vector3.new(half * 2, 130, 1), CFrame = CFrame.new(0, 65, length), Color = rgb(40, 44, 50), Material = M.Fabric, Transparency = 0.7, Parent = arena })
	key(catch, "CatchNet")
	part({ Name = "CatchFrameTop", Size = Vector3.new(half * 2 + 4, 2, 2), CFrame = CFrame.new(0, 131, length), Color = C.Yellow, Material = M.Metal, Parent = arena })
	for _, x in ipairs({ -1, 0, 1 }) do
		part({ Name = "CatchPost", Size = Vector3.new(2, 132, 2), CFrame = CFrame.new(x * half, 66, length + 1.5), Color = C.Steel, Material = M.Metal, Parent = arena })
	end

	-- Crash pads (soft and bouncy).
	local function crashPad(name, size, cf, col)
		local p = part({ Name = name, Size = size, CFrame = cf, Color = col, Material = M.Fabric, Parent = arena })
		p.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.35, 0.92, 1, 100)
		p:SetAttribute("CL_Soft", true)
		key(p, name)
		deco({ Size = Vector3.new(size.X + 0.2, 0.5, size.Z + 0.2), CFrame = cf * CFrame.new(0, size.Y / 2 - 0.2, 0), Color = C.Yellow, Material = M.Fabric, Parent = arena })
		return p
	end
	for i, x in ipairs({ -40, -14, 14, 40 }) do
		crashPad("BouncePad" .. i, Vector3.new(22, 3, 18), CFrame.new(x, 1.5, 62), if i % 2 == 0 then C.Blue else rgb(80, 160, 230))
	end
	for i, x in ipairs({ -45, -15, 15, 45 }) do
		crashPad("LandingCushion" .. i, Vector3.new(28, 4, 26), CFrame.new(x, 2, 462), if i % 2 == 0 then C.Orange else rgb(255, 170, 70))
	end

	-- Kicker ramps. (A WedgePart rises toward its back, +Z: low edge faces the launchers.)
	for i, x in ipairs({ -32, 32 }) do
		local ramp = part({ Class = "WedgePart", Name = "Ramp" .. i, Size = Vector3.new(26, 9, 26), CFrame = CFrame.new(x, 4.5, 125), Color = C.Yellow, Material = M.DiamondPlate, Parent = arena })
		key(ramp, "Ramp" .. i)
		part({ Name = "RampBack", Size = Vector3.new(26, 9, 2), CFrame = CFrame.new(x, 4.5, 139), Color = C.SteelDark, Material = M.Metal, Parent = arena })
	end
	local skid = part({ Class = "WedgePart", Name = "SkidRamp", Size = Vector3.new(30, 5, 30), CFrame = CFrame.new(0, 2.5, 345), Color = C.Yellow, Material = M.DiamondPlate, Parent = arena })
	key(skid, "SkidRamp")

	-- Indestructible steel barriers (jersey barriers + bumpers).
	for i, x in ipairs({ -50, 50 }) do
		local b = part({ Name = "JerseyBarrier" .. i, Size = Vector3.new(24, 4, 3), CFrame = CFrame.new(x, 2, 388), Color = C.White, Material = M.Concrete, Parent = arena })
		key(b, "Jersey" .. i)
		hazardStrip(CFrame.new(x, 4.06, 388), 24, 3, 6, arena)
	end
	for i, x in ipairs({ -60, 60 }) do
		local bumper = part({ Name = "Bumper" .. i, Size = Vector3.new(4, 6, 40), CFrame = CFrame.new(x, 3, 250), Color = C.Red, Material = M.Metal, Parent = arena })
		key(bumper, "Bumper" .. i)
	end

	-- Destructible props.
	world.props = {}
	local propsFolder = sub("Props", arena)
	local propCounter = 0
	local function prop(kindId, size, cf, groupName)
		propCounter += 1
		local kind = CourseConfig.DestructibleKinds[kindId]
		local id = kindId .. propCounter
		local p = part({ Name = id, Size = size, CFrame = cf, Color = Color3.fromRGB(kind.Color[1], kind.Color[2], kind.Color[3]), Material = M[kind.Material] or M.SmoothPlastic, Parent = propsFolder })
		if kindId == "Panel" then
			p.Transparency = 0.35
		end
		p:SetAttribute("CL_Prop", id)
		world.props[id] = { id = id, kind = kindId, group = groupName, part = p, cframe = cf, size = size, broken = false }
		return p
	end
	-- Cardboard box stacks.
	for _, spot in ipairs({ { -22, 95 }, { 22, 95 }, { -10, 142 }, { 10, 142 }, { -42, 228 }, { 42, 228 } }) do
		for layer = 0, 2 do
			for j = 0, 2 - layer do
				local x = spot[1] + (j - (2 - layer) / 2) * 4.2
				prop("Cardboard", Vector3.new(4, 4, 4), CFrame.new(x, 2 + layer * 4, spot[2]) * CFrame.Angles(0, math.rad((j * 13 + layer * 7) % 20 - 10), 0), "Boxes")
			end
		end
	end
	-- Plastic test targets (tall pins with red rings).
	for _, x in ipairs({ -30, -15, 15, 30 }) do
		local pin = prop("Plastic", Vector3.new(2.6, 7, 2.6), CFrame.new(x, 3.5, 186), "Pins")
		for k = 0, 1 do
			deco({ Size = Vector3.new(2.7, 0.5, 2.7), CFrame = pin.CFrame * CFrame.new(0, 1 + k * 1.4, 0), Color = C.Red, Parent = pin })
		end
	end
	-- Wooden barriers (the "Fence" group).
	for i, x in ipairs({ -48, -24, 0, 24, 48 }) do
		local fence = prop("Wood", Vector3.new(20, 6, 1.2), CFrame.new(x, 3, 170), "Fence")
		fence.Name = "Fence" .. i
		deco({ Size = Vector3.new(20.2, 0.6, 1.3), CFrame = fence.CFrame * CFrame.new(0, 1.6, 0), Color = C.Yellow, Parent = fence })
	end
	-- Breakaway panel wall (needs the Reinforced dummy or heavier).
	for i = -4, 4 do
		prop("Panel", Vector3.new(12, 14, 1), CFrame.new(i * 12, 7, 285), "PanelWall")
	end
	part({ Name = "PanelWallBeam", Size = Vector3.new(112, 1.4, 1.6), CFrame = CFrame.new(0, 14.7, 285), Color = C.SteelDark, Material = M.Metal, Parent = arena })
	-- Lightweight test structures (stacked blocks).
	for _, x in ipairs({ -28, 28 }) do
		for layer = 0, 3 do
			for j = -1, 1 do
				prop("Tower", Vector3.new(3, 3, 3), CFrame.new(x + j * 3.1, 1.5 + layer * 3.05, 352), "Tower")
			end
		end
	end

	-- Rings (fly-through: the ring itself doesn't collide; its posts do).
	world.rings = {}
	for _, def in ipairs(CourseConfig.Rings) do
		local ringFolder = sub(def.Id, arena)
		local col = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
		local segments = 20
		for s = 0, segments - 1 do
			local a = s / segments * math.pi * 2
			local p = def.Position + Vector3.new(math.cos(a) * def.Radius, math.sin(a) * def.Radius, 0)
			deco({ Size = Vector3.new(1.2, def.Radius * 2 * math.pi / segments + 0.5, 1.2), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, a), Color = col, Material = M.Neon, Parent = ringFolder })
		end
		for _, side in ipairs({ -1, 1 }) do
			local postX = def.Position.X + side * (def.Radius + 1.5)
			local post = part({ Name = "RingPost", Size = Vector3.new(1.2, def.Position.Y, 1.2), CFrame = CFrame.new(postX, def.Position.Y / 2, def.Position.Z), Color = C.Steel, Material = M.Metal, Parent = ringFolder })
			key(post, def.Id .. "Post")
		end
		local glow = Instance.new("PointLight")
		glow.Color = col
		glow.Range = 18
		glow.Brightness = 0.8
		glow.Parent = ringFolder:FindFirstChildWhichIsA("BasePart")
		world.rings[def.Id] = { def = def, folder = ringFolder }
	end

	-- Targets (moving ones are moved by CourseService).
	world.targets = {}
	for _, def in ipairs(CourseConfig.Targets) do
		local tFolder = sub(def.Id, arena)
		local face = CFrame.new(def.Position) * CFrame.Angles(0, math.rad(90), 0)
		local hit = part({ Name = def.Id, Size = Vector3.new(1.4, def.Radius * 2, def.Radius * 2), CFrame = face, Shape = CYL, Color = C.White, Material = M.SmoothPlastic, Parent = tFolder })
		hit:SetAttribute("CL_Target", def.Id)
		local rings = {}
		for k, rr in ipairs({ 0.75, 0.5, 0.25 }) do
			local ringPart = deco({ Size = Vector3.new(1.5 + k * 0.05, def.Radius * 2 * rr, def.Radius * 2 * rr), CFrame = face, Shape = CYL, Color = if k % 2 == 1 then C.Red else C.White, Parent = tFolder })
			table.insert(rings, ringPart)
		end
		local movers = { hit }
		for _, r in ipairs(rings) do
			table.insert(movers, r)
		end
		if def.Motion then
			-- Overhead track / rail.
			local trackY = if def.Motion.Kind == "Swing" then def.Position.Y + def.Radius + 10 else 0.6
			part({ Name = "Track", Size = Vector3.new(def.Motion.Amplitude * 2 + 20, 1, 1.6), CFrame = CFrame.new(def.Position.X, trackY, def.Position.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
			if def.Motion.Kind == "Swing" then
				for _, side in ipairs({ -1, 1 }) do
					part({ Name = "TrackPost", Size = Vector3.new(1.4, trackY, 1.4), CFrame = CFrame.new(def.Position.X + side * (def.Motion.Amplitude + 10), trackY / 2, def.Position.Z), Color = C.Steel, Material = M.Metal, Parent = tFolder })
				end
				local rod = deco({ Size = Vector3.new(0.4, 10, 0.4), CFrame = CFrame.new(def.Position + Vector3.new(0, def.Radius + 5, 0)), Color = C.Steel, Parent = tFolder })
				table.insert(movers, rod)
			else
				local carriage = deco({ Size = Vector3.new(4, 2, 3), CFrame = CFrame.new(def.Position.X, 1.6, def.Position.Z), Color = C.Yellow, Parent = tFolder })
				local mast = deco({ Size = Vector3.new(0.6, def.Position.Y - def.Radius - 1, 0.6), CFrame = CFrame.new(def.Position.X, (def.Position.Y - def.Radius) / 2 + 1, def.Position.Z), Color = C.Steel, Parent = tFolder })
				table.insert(movers, carriage)
				table.insert(movers, mast)
			end
		else
			-- The gong's frame.
			for _, side in ipairs({ -1, 1 }) do
				part({ Name = "GongPost", Size = Vector3.new(2, def.Position.Y + def.Radius + 4, 2), CFrame = CFrame.new(def.Position.X + side * (def.Radius + 3), (def.Position.Y + def.Radius + 4) / 2, def.Position.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
			end
			part({ Name = "GongBeam", Size = Vector3.new(def.Radius * 2 + 10, 2, 2), CFrame = CFrame.new(def.Position.X, def.Position.Y + def.Radius + 4, def.Position.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
			hit.Color = rgb(214, 170, 60)
			hit.Material = M.Metal
			for _, r in ipairs(rings) do
				r.Color = rgb(190, 140, 40)
				r.Material = M.Metal
			end
		end
		local base = {}
		for _, m in ipairs(movers) do
			base[m] = CFrame.new(def.Position):ToObjectSpace(m.CFrame)
		end
		world.targets[def.Id] = { def = def, part = hit, movers = movers, base = base, origin = def.Position }
	end

	-- Landing zones.
	world.zones = {}
	for _, def in ipairs(CourseConfig.LandingZones) do
		local col = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
		local disc = deco({ Size = Vector3.new(0.12, def.Radius * 2, def.Radius * 2), CFrame = CFrame.new(def.Position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = col, Material = M.Neon, Transparency = 0.25, Parent = arena })
		deco({ Size = Vector3.new(0.14, def.Radius * 1.2, def.Radius * 1.2), CFrame = disc.CFrame, Shape = CYL, Color = C.White, Material = M.SmoothPlastic, Parent = arena })
		deco({ Size = Vector3.new(0.16, def.Radius * 0.5, def.Radius * 0.5), CFrame = disc.CFrame, Shape = CYL, Color = col, Material = M.Neon, Parent = arena })
		world.zones[def.Id] = { def = def, part = disc }
	end

	-- Gantries overhead (well above most arcs) + industrial light towers.
	for _, z in ipairs({ 80, 300 }) do
		part({ Name = "Gantry", Size = Vector3.new(half * 2 + 30, 4, 4), CFrame = CFrame.new(0, 190, z), Color = C.Yellow, Material = M.Metal, Parent = arena })
		for _, x in ipairs({ -1, 1 }) do
			part({ Name = "GantryLeg", Size = Vector3.new(4, 190, 4), CFrame = CFrame.new(x * (half + 14), 95, z), Color = C.Steel, Material = M.Metal, Parent = arena })
		end
	end
	world.lightTowers = {}
	for _, spot in ipairs({ { -1, 40 }, { 1, 40 }, { -1, 230 }, { 1, 230 }, { -1, 420 }, { 1, 420 } }) do
		local x = spot[1] * (half + 24)
		part({ Name = "LightTower", Size = Vector3.new(2, 60, 2), CFrame = CFrame.new(x, 30, spot[2]), Color = C.Steel, Material = M.Metal, Parent = arena })
		local head = deco({ Size = Vector3.new(8, 3, 3), CFrame = CFrame.new(x, 61, spot[2]) * CFrame.Angles(math.rad(-25), math.rad(spot[1] * -90), 0), Color = rgb(255, 246, 225), Material = M.Neon, Parent = arena })
		local s = Instance.new("SpotLight")
		s.Face = Enum.NormalId.Front
		s.Angle = 70
		s.Range = 120
		s.Brightness = 1.6
		s.Color = rgb(255, 240, 214)
		s.Shadows = false
		s.Parent = head
		table.insert(world.lightTowers, head)
	end

	-- Big test fans along the side (spun by the client).
	world.fans = {}
	for _, z in ipairs({ 160, 400 }) do
		for _, side in ipairs({ -1, 1 }) do
			local x = side * (half + 10)
			part({ Name = "FanHousing", Size = Vector3.new(4, 18, 18), CFrame = CFrame.new(x, 11, z), Color = C.SteelDark, Material = M.Metal, Parent = arena })
			local fanId = #world.fans + 1
			local hub = deco({ Name = "FanHub", Size = Vector3.new(1, 3, 3), CFrame = CFrame.new(x - side * 2.6, 11, z), Shape = CYL, Color = C.Yellow, Material = M.Metal, Parent = arena })
			hub:SetAttribute("Fan", fanId)
			local blades = {}
			for b = 0, 3 do
				local blade = deco({ Name = "FanBlade", Size = Vector3.new(0.4, 7, 2), CFrame = hub.CFrame * CFrame.Angles(b * math.pi / 2, 0, 0) * CFrame.new(0, 3.8, 0), Color = rgb(200, 205, 210), Material = M.Metal, Parent = arena })
				blade:SetAttribute("Fan", fanId)
				table.insert(blades, blade)
			end
			table.insert(world.fans, { hub = hub, blades = blades, side = side })
		end
	end

	-- Spectator stands (outside the side nets) and an elevated observation booth.
	for _, side in ipairs({ -1, 1 }) do
		for row = 0, 3 do
			part({ Name = "Bleacher", Size = Vector3.new(4, 1 + row * 2, 120), CFrame = CFrame.new(side * (half + 32 + row * 4), (1 + row * 2) / 2, 180), Color = if row % 2 == 0 then C.Blue else rgb(70, 140, 230), Material = M.SmoothPlastic, Parent = arena })
		end
	end
	local boothCF = CFrame.new(-(half + 30), 0, 320)
	part({ Name = "ObservationDeck", Size = Vector3.new(24, 1, 30), CFrame = boothCF * CFrame.new(0, 16, 0), Color = C.SteelDark, Material = M.DiamondPlate, Parent = arena })
	deco({ Size = Vector3.new(0.6, 8, 30), CFrame = boothCF * CFrame.new(12, 20.5, 0), Color = C.Glass, Material = M.Glass, Transparency = 0.6, Parent = arena })
	part({ Name = "ObservationRoof", Size = Vector3.new(24, 1, 30), CFrame = boothCF * CFrame.new(0, 25, 0), Color = C.Steel, Material = M.Metal, Parent = arena })
	for _, zz in ipairs({ -14, 14 }) do
		part({ Name = "ObsLeg", Size = Vector3.new(1.5, 16, 1.5), CFrame = boothCF * CFrame.new(-11, 8, zz), Color = C.Steel, Material = M.Metal, Parent = arena })
	end
	-- Stairs up to the booth.
	for s = 0, 15 do
		part({ Name = "Stair", Size = Vector3.new(6, 1, 2), CFrame = boothCF * CFrame.new(-8, 0.5 + s, -26 + s * 2) * CFrame.new(0, 0, 0), Color = C.SteelDark, Material = M.DiamondPlate, Parent = arena })
	end

	-- Ambient emitters in the arena.
	local clank = deco({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(half + 12, 10, 200), Transparency = 1, Color = C.Steel, Parent = arena })
	clank:SetAttribute("Ambient", "Clank")
	local fanHum = deco({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(-(half + 10), 11, 160), Transparency = 1, Color = C.Steel, Parent = arena })
	fanHum:SetAttribute("Ambient", "Machinery")
end

function FacilityBuilder.build()
	partCount = 0
	local existing = Workspace:FindFirstChild("CrashLabFacility")
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "CrashLabFacility"
	local world = {}
	buildLobby(world)
	buildDeck(world)
	buildArena(world)
	local dummies = Instance.new("Folder")
	dummies.Name = "Dummies"
	dummies.Parent = folder
	local debris = Instance.new("Folder")
	debris.Name = "Debris"
	debris.Parent = folder
	folder.Parent = Workspace
	world.folder = folder
	world.dummyFolder = dummies
	world.debrisFolder = debris
	world.partCount = partCount
	world.arena = GameConfig.Arena
	return world
end

return FacilityBuilder
