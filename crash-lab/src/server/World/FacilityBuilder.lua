--[[
	FacilityBuilder - builds every facility from code at server start. The hub: the lobby
	(CRASH LAB sign, dummy display, upgrade station, results board, leaderboards, tutorial
	signs, facility transit gate) and the Industrial Crash Lab arena (launch deck with six
	pads, crash pads, ramps, barriers, destructible props, rings, moving targets, landing
	zones, distance markers, catch nets, stands, booth, gantries, light towers, fans).
	The three other facilities are built by World/Facilities/* 4,000 studs away, each in
	its own folder (CrashLabFacility.Facilities.<Id>) with its own deck and arena.

	The layout comes from CourseConfig so the server's objective checks and the world can
	never disagree. Tags used by the crash simulation are listed in World/Kit.
	Returns a `world` table (see the end of build()).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local GameConfig = require(Shared.Config.GameConfig)
local CourseConfig = require(Shared.Config.CourseConfig)
local DummyModel = require(Shared.DummyModel)

local Kit = require(script.Parent.Kit)
local Facilities = script.Parent:WaitForChild("Facilities")

local FacilityBuilder = {}

local rgb = Kit.rgb
local M = Kit.M
local CYL = Kit.CYL
local C = Kit.C
local part, deco, sub, surfaceText, hazardStrip, key = Kit.part, Kit.deco, Kit.sub, Kit.surfaceText, Kit.hazardStrip, Kit.key
local ORIGIN = Vector3.new(0, 0, 0) -- the hub course sits at the world origin

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
	Kit.add(1)
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
		Kit.add(#dummy:GetDescendants())
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
	-- Walkway from the spawn to the deck ramp: yellow edge lines + glowing chevrons that
	-- point at the deck, and an overhead sign at the exit.
	local walkStart, walkEnd = z0 - 22, z0 + 63
	for _, x in ipairs({ -6, 6 }) do
		deco({ Name = "WalkwayEdge", Size = Vector3.new(0.6, 0.04, walkEnd - walkStart), CFrame = CFrame.new(x, 0.035, (walkStart + walkEnd) / 2), Color = C.Yellow, Parent = lobby })
	end
	for i = 0, 8 do
		local cz = walkStart + 6 + i * 9
		for _, side in ipairs({ -1, 1 }) do
			-- Two angled bars make a ">" pointing toward +Z (the deck).
			deco({ Name = "Chevron", Size = Vector3.new(0.7, 0.06, 3.4), CFrame = CFrame.new(side * 1.15, 0.05, cz) * CFrame.Angles(0, math.rad(-side * 35), 0), Color = C.Yellow, Material = M.Neon, Parent = lobby })
		end
	end
	local exitSign = deco({ Name = "DeckSign", Size = Vector3.new(26, 5, 0.6), CFrame = CFrame.new(0, 17, z0 + 64), Color = C.Black, Material = M.Metal, Parent = lobby })
	surfaceText(exitSign, Enum.NormalId.Front, "LAUNCH DECK  >>>", { Color = C.Yellow, PPS = 20, LightInfluence = 0 })
	deco({ Size = Vector3.new(26.4, 0.5, 0.8), CFrame = CFrame.new(0, 14.4, z0 + 64), Color = C.Yellow, Material = M.Neon, Parent = lobby })
	for _, x in ipairs({ -13.5, 13.5 }) do
		deco({ Size = Vector3.new(0.5, 3, 0.5), CFrame = CFrame.new(x, 20.5, z0 + 64), Color = C.Steel, Parent = lobby })
	end

	-- Facility transit gate: opens the Facilities menu (unlock + travel). The Space Launch
	-- Facility's door next to it is boarded up: the only one still under construction.
	local gateCF = CFrame.new(99, 0, z0 + 20)
	part({ Name = "GateFrame", Size = Vector3.new(4, 26, 40), CFrame = gateCF * CFrame.new(0, 13, 0), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
	local door = part({ Name = "GateDoor", Size = Vector3.new(1, 20, 30), CFrame = gateCF * CFrame.new(-2.6, 10, 0), Color = C.Yellow, Material = M.DiamondPlate, Parent = lobby })
	hazardStrip(CFrame.new(96.5, 20.6, z0 + 20) * CFrame.Angles(0, math.rad(90), 0), 30, 0.8, 10, lobby)
	local gateSign = deco({ Size = Vector3.new(0.5, 4, 26), CFrame = gateCF * CFrame.new(-3.4, 23, 0), Color = C.Black, Parent = lobby })
	local gateLabel = surfaceText(gateSign, Enum.NormalId.Left, "FACILITY TRANSIT", { Color = C.Yellow, PPS = 16 })
	local gatePrompt = Kit.prompt(door, "Travel", "Facility Transit", 14)
	world.gate = { door = door, prompt = gatePrompt, label = gateLabel }
	local spaceCF = CFrame.new(99, 0, z0 - 26)
	part({ Name = "SpaceGateFrame", Size = Vector3.new(4, 20, 24), CFrame = spaceCF * CFrame.new(0, 10, 0), Color = C.SteelDark, Material = M.Metal, Parent = lobby })
	part({ Name = "SpaceGateDoor", Size = Vector3.new(1, 16, 18), CFrame = spaceCF * CFrame.new(-2.6, 8, 0), Color = rgb(70, 74, 84), Material = M.DiamondPlate, Parent = lobby })
	for k, y in ipairs({ 5, 11 }) do
		deco({ Size = Vector3.new(0.4, 1.2, 21), CFrame = spaceCF * CFrame.new(-3.3, y, 0) * CFrame.Angles(math.rad(if k == 1 then 14 else -14), 0, 0), Color = rgb(150, 110, 70), Material = M.WoodPlanks, Parent = lobby })
	end
	hazardStrip(CFrame.new(96.4, 17.2, z0 - 26) * CFrame.Angles(0, math.rad(90), 0), 18, 0.8, 8, lobby)
	local spaceSign = deco({ Size = Vector3.new(0.5, 3.4, 20), CFrame = spaceCF * CFrame.new(-3.4, 19, 0), Color = C.Black, Parent = lobby })
	world.spaceGateLabel = surfaceText(spaceSign, Enum.NormalId.Left, "SPACE LAUNCH - UNDER CONSTRUCTION", { Color = C.Orange, PPS = 16 })

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
	Kit.add(#passenger:GetDescendants())
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
	-- Walkway paint between the edge lines.
	deco({ Size = Vector3.new(11.4, 0.03, walkEnd - walkStart), CFrame = CFrame.new(0, 0.02, (walkStart + walkEnd) / 2), Color = rgb(70, 72, 80), Parent = lobby })

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
	-- Hazard stripes on the deck's side ends and a warm work-light bar over the pads.
	hazardStrip(CFrame.new(-74.4, deckTop + 0.06, -8) * CFrame.Angles(0, math.rad(90), 0), 30, 1.2, 8, deck)
	hazardStrip(CFrame.new(74.4, deckTop + 0.06, -8) * CFrame.Angles(0, math.rad(90), 0), 30, 1.2, 8, deck)
	deco({ Name = "LightBar", Size = Vector3.new(124, 1, 1.6), CFrame = CFrame.new(0, 26, -4), Color = C.SteelDark, Material = M.Metal, Parent = deck })
	for _, x in ipairs({ -66, 66 }) do
		part({ Name = "LightBarPost", Size = Vector3.new(1.4, 25, 1.4), CFrame = CFrame.new(x, 13.5, -4), Color = C.Steel, Material = M.Metal, Parent = deck })
	end
	for _, x in ipairs({ -40, 0, 40 }) do
		local lamp = deco({ Name = "WorkLight", Size = Vector3.new(8, 0.5, 2), CFrame = CFrame.new(x, 25.3, -4), Color = rgb(255, 226, 170), Material = M.Neon, Parent = deck })
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 95
		light.Range = 40
		light.Brightness = 1.3
		light.Color = rgb(255, 214, 160) -- warm work light
		light.Shadows = false
		light.Parent = lamp
	end
	-- Ramp from the lobby floor up onto the deck.
	part({ Class = "WedgePart", Name = "DeckRamp", Size = Vector3.new(60, deckTop, 6), CFrame = CFrame.new(0, deckTop / 2, -26), Color = C.SteelDark, Material = M.DiamondPlate, Parent = deck })
	world.facilities.IndustrialLab.pads = Kit.padRow(world, deck, ORIGIN, GameConfig.PadCount, GameConfig.PadSpacing, deckTop, "IndustrialLab")
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
	-- Painted floor: lane lines, a dashed yellow centre line, red keep-out edges, a
	-- start box in front of the deck, and scuff / tyre marks (thin dark parts - no images).
	-- Heights are staggered (0.02 / 0.03 / 0.045) so overlapping paint never z-fights.
	for _, x in ipairs({ -40, 40 }) do
		deco({ Name = "LaneLine", Size = Vector3.new(0.5, 0.04, length), CFrame = CFrame.new(x, 0.02, length / 2 + 6), Color = rgb(236, 236, 228), CastShadow = false, Parent = arena })
	end
	for z = 14, length - 20, 12 do
		deco({ Name = "CentreDash", Size = Vector3.new(0.7, 0.05, 6), CFrame = CFrame.new(0, 0.025, z), Color = C.Yellow, CastShadow = false, Parent = arena })
	end
	for _, side in ipairs({ -1, 1 }) do
		deco({ Name = "KeepOut", Size = Vector3.new(2, 0.04, length), CFrame = CFrame.new(side * (half - 2.5), 0.02, length / 2 + 6), Color = C.Red, CastShadow = false, Parent = arena })
	end
	hazardStrip(CFrame.new(0, 0.03, 20), 120, 1.6, 24, arena)
	local function scuff(x, z, len, yaw, width)
		deco({ Name = "Scuff", Size = Vector3.new(width or 0.9, 0.03, len), CFrame = CFrame.new(x, 0.03, z) * CFrame.Angles(0, yaw, 0), Color = rgb(70, 70, 72), Transparency = 0.55, CastShadow = false, Parent = arena })
	end
	for i = 1, 22 do
		-- Deterministic scatter (same every build).
		local z = 40 + ((i * 97) % 470)
		local x = math.sin(i * 12.9898) * 52
		local yaw = math.sin(i * 4.1) * 0.9
		scuff(x, z, 6 + (i % 5) * 3, yaw)
		if i % 3 == 0 then
			-- Tyre marks: a pair of parallel curving skids.
			for k = 0, 2 do
				for _, off in ipairs({ -1.4, 1.4 }) do
					scuff(x + 8 + off + k * 1.6, z + 6 + k * 5, 5.4, 0.35 * k, 0.6)
				end
			end
		end
	end

	-- Distance markers every 50 studs: floor line + sign on both sides.
	for d = CourseConfig.MarkerEvery, length - 40, CourseConfig.MarkerEvery do
		local isGoal = table.find(CourseConfig.DistanceGoals, d) ~= nil
		local col = if isGoal then C.Yellow else C.White
		deco({ Name = "MarkerLine", Size = Vector3.new(half * 2 - 6, 0.06, 0.8), CFrame = CFrame.new(0, 0.045, d), Color = col, Material = if isGoal then M.Neon else M.SmoothPlastic, CastShadow = false, Parent = arena })
		-- Painted distance numbers on the floor (SurfaceGui text, readable from the deck).
		for _, x in ipairs({ -22, 22 }) do
			local paint = deco({ Name = "FloorNumber", Size = Vector3.new(12, 0.02, 7), CFrame = CFrame.new(x, 0.03, d + 5) * CFrame.Angles(0, math.rad(180), 0), Color = col, Transparency = 1, CastShadow = false, Parent = arena })
			surfaceText(paint, Enum.NormalId.Top, tostring(d), { Color = if isGoal then C.Yellow else Color3.fromRGB(236, 236, 228), PPS = 12, LightInfluence = 1 })
		end
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
			part({ Name = "NetPost", Size = Vector3.new(1.4, 130, 1.4), CFrame = CFrame.new(x * (half + 2.6), 65, z), Color = C.Steel, Material = M.Metal, Parent = arena })
		end
		-- Thick nets: fast dummies can tunnel through thin parts between physics steps.
		local net = part({ Name = "SideNet", Size = Vector3.new(4, 116, length + 20), CFrame = CFrame.new(x * (half + 2), 72, length / 2 + 4), Color = rgb(40, 44, 50), Material = M.Fabric, Transparency = 0.82, Parent = arena })
		key(net, "SideNet")
		deco({ Size = Vector3.new(1.2, 1.2, length + 20), CFrame = CFrame.new(x * (half + 2), 130.6, length / 2 + 4), Color = C.Yellow, Material = M.Metal, Parent = arena })
	end
	local catch = part({ Name = "CatchNet", Size = Vector3.new(half * 2 + 8, 130, 6), CFrame = CFrame.new(0, 65, length + 2.5), Color = rgb(40, 44, 50), Material = M.Fabric, Transparency = 0.7, Parent = arena })
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
	local propsFolder = sub("Props", arena)
	local function prop(kindId, size, cf, groupName)
		return Kit.prop(world, kindId, size, cf, groupName, propsFolder, "IndustrialLab")
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

	-- Rings (fly-through: the ring itself doesn't collide; its posts do), targets (moving
	-- ones are moved by CourseService) and landing zones.
	for _, def in ipairs(CourseConfig.Rings) do
		Kit.ring(world, def, ORIGIN, arena)
	end
	for _, def in ipairs(CourseConfig.Targets) do
		Kit.target(world, def, ORIGIN, arena)
	end
	for _, def in ipairs(CourseConfig.LandingZones) do
		Kit.zone(world, def, ORIGIN, arena)
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

local NEW_FACILITIES = { "Destruction", "HighAltitude", "GravityLab" }

function FacilityBuilder.build()
	local existing = Workspace:FindFirstChild("CrashLabFacility")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "CrashLabFacility"
	Kit.reset(folder)
	local world = { pads = {}, rings = {}, targets = {}, zones = {}, props = {}, markers = {}, facilities = {} }
	local hub = CourseConfig.Courses.IndustrialLab
	world.facilities.IndustrialLab = { id = "IndustrialLab", course = hub, origin = hub.Origin, folder = folder }
	buildLobby(world)
	buildDeck(world)
	buildArena(world)
	world.facilities.IndustrialLab.spawn = world.spawn.CFrame * CFrame.new(0, 4, 0)
	world.facilities.IndustrialLab.parts = Kit.count()
	-- The other facilities, each in its own folder far from the hub.
	local others = Kit.sub("Facilities", folder)
	for _, id in ipairs(NEW_FACILITIES) do
		local before = Kit.count()
		local course = CourseConfig.Courses[id]
		local fFolder = Kit.sub(id, others)
		local entry = { id = id, course = course, origin = course.Origin, folder = fFolder }
		world.facilities[id] = entry
		require(Facilities[id]).build(world, entry)
		entry.parts = Kit.count() - before
	end
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
	world.partCount = Kit.count()
	world.arena = GameConfig.Arena
	return world
end

return FacilityBuilder
