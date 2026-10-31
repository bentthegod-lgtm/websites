--[[
	LobbyBuilder - the lobby north of downtown (built at once: it's small, so players can
	spawn immediately while the track builds over the next frames).

	  * a neon plaza with the spawn
	  * the RACE PORTAL: a big glowing arch with a pad - stand on it to queue up
	  * two leaderboard boards (Most Wins, Fastest Chaos City lap)
	  * the kart showroom: both Stage 1 karts on turntables (kart select is in the menu)
	  * kiosks with prompts: Garage (karts), Shop, Daily Reward, Codes
	Returns { folder, spawn, spawnCFrame, holdCFrame, portalPosition, portalRadius,
	  boardRows = { Wins = {labels}, BestLap = {labels} }, prompts, partCount }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Parts = require(Shared.Parts)
local GameConfig = require(Shared.Config.GameConfig)
local VehicleModels = require(Shared.VehicleModels)
local VehicleRegistry = require(Shared.Vehicles.Registry)

local LobbyBuilder = {}

local P = Parts.Palette
local M = Enum.Material
local rgb = Color3.fromRGB

local function neonFor(i)
	local list = { P.NeonPink, P.NeonCyan, P.NeonYellow, P.NeonGreen }
	return list[(i - 1) % #list + 1]
end

local function board(folder, cf, title, color)
	local b = Parts.new({ Name = "Board", Size = Vector3.new(30, 26, 1.4), CFrame = cf, Color = rgb(14, 16, 30), Parent = folder })
	Parts.new({ Name = "BoardFrame", Size = Vector3.new(31.5, 27.5, 1), CFrame = cf * CFrame.new(0, 0, 0.5), Color = color, Material = M.Neon, CanCollide = false, Parent = folder })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = b
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.16, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = color
	titleLabel.Parent = gui
	local rows = {}
	for i = 1, GameConfig.Leaderboard.Rows do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.new(0.92, 0, 0.078, 0)
		row.Position = UDim2.new(0.04, 0, 0.17 + (i - 1) * 0.082, 0)
		row.BackgroundTransparency = 1
		row.Text = string.format("%d. ---", i)
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Font = Enum.Font.GothamBold
		row.TextColor3 = Color3.new(1, 1, 1)
		row.Parent = gui
		rows[i] = row
	end
	return rows
end

local function prompt(part, action, object)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = part
	return p
end

local function kiosk(folder, cf, name, color, action)
	local base = Parts.new({ Name = name .. "Kiosk", Size = Vector3.new(8, 7, 5), CFrame = cf * CFrame.new(0, 3.5, 0), Color = rgb(30, 32, 50), Parent = folder })
	Parts.new({ Name = name .. "Roof", Size = Vector3.new(10, 1, 7), CFrame = cf * CFrame.new(0, 9.5, 0), Color = color, Material = M.Neon, CanCollide = false, Parent = folder })
	for _, s in ipairs({ -1, 1 }) do
		Parts.new({ Name = "KioskPole", Size = Vector3.new(0.6, 3, 0.6), CFrame = cf * CFrame.new(s * 4.5, 8.5, -3), Color = color, Material = M.Neon, CanCollide = false, Parent = folder })
	end
	local sign = Parts.new({ Name = name .. "Sign", Size = Vector3.new(9, 2.2, 0.4), CFrame = cf * CFrame.new(0, 7.8, -3.4), Color = P.Black, CanCollide = false, Parent = folder })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.upper(name)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = gui
	return prompt(base, action, name), 6
end

function LobbyBuilder.build(parent, data)
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = parent
	local centre = data.lobby.centre
	local portalPos = data.lobby.portal
	local origin = CFrame.new(centre)
	local count = 0
	local function part(spec)
		spec.Parent = spec.Parent or folder
		count += 1
		return Parts.new(spec)
	end
	-- the plaza
	part({ Name = "LobbyFloor", Size = Vector3.new(220, 2, 190), CFrame = origin * CFrame.new(0, -0.9, 20), Color = rgb(36, 34, 58), Material = M.Slate })
	for i = -4, 4 do
		part({ Name = "FloorNeon", Size = Vector3.new(0.6, 0.2, 190), CFrame = origin * CFrame.new(i * 24, 0.12, 20), Color = if i % 2 == 0 then P.NeonPink else P.NeonCyan, Material = M.Neon, CanCollide = false, CastShadow = false })
	end
	for _, s in ipairs({ -1, 1 }) do
		part({ Name = "LobbyWall", Size = Vector3.new(2, 10, 190), CFrame = origin * CFrame.new(s * 110, 5, 20), Color = rgb(24, 22, 40) })
		part({ Name = "LobbyWallNeon", Size = Vector3.new(2.4, 0.8, 190), CFrame = origin * CFrame.new(s * 110, 10, 20), Color = P.NeonPurple, Material = M.Neon, CanCollide = false })
	end
	part({ Name = "LobbyBackWall", Size = Vector3.new(220, 10, 2), CFrame = origin * CFrame.new(0, 5, -75), Color = rgb(24, 22, 40) })
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = origin * CFrame.new(0, 0.5, -45)
	spawn.Anchored = true
	spawn.Color = P.NeonCyan
	spawn.Material = M.Neon
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	count += 1
	-- the RACE PORTAL arch + pad (open side faces the city)
	local portalCF = CFrame.new(portalPos)
	part({ Name = "PortalPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, data.lobby.portalRadius * 2, data.lobby.portalRadius * 2), CFrame = portalCF * CFrame.new(0, 0.3, 0) * Parts.UP, Color = P.NeonCyan, Material = M.Neon, Transparency = 0.15 })
	part({ Name = "PortalPadRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, data.lobby.portalRadius * 2 + 3, data.lobby.portalRadius * 2 + 3), CFrame = portalCF * CFrame.new(0, 0.1, 0) * Parts.UP, Color = P.Black })
	local segs = 14
	for i = 0, segs do
		local a = i / segs * math.pi
		local r = 22
		local x, y = math.cos(a) * r, math.sin(a) * r * 1.2
		part({ Name = "PortalArch", Size = Vector3.new(3, 3, 5.4), CFrame = portalCF * CFrame.new(x, y + 2, 0) * CFrame.Angles(0, 0, a), Color = if i % 2 == 0 then P.NeonPink else P.NeonYellow, Material = M.Neon, CanCollide = false })
	end
	local sign = part({ Name = "PortalSign", Size = Vector3.new(34, 6, 1), CFrame = portalCF * CFrame.new(0, 33, 0), Color = P.Black, CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "RACE PORTAL - STAND HERE"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = P.NeonYellow
	label.Parent = gui
	local glow = part({ Name = "PortalGlow", Size = Vector3.new(1, 1, 1), CFrame = portalCF * CFrame.new(0, 12, 0), Transparency = 1, CanCollide = false })
	Parts.light(glow, P.NeonCyan, 40, 3)
	-- leaderboards
	local boardRows = {
		Wins = board(folder, origin * CFrame.new(-70, 16, -60) * CFrame.Angles(0, math.rad(200), 0), "MOST WINS", P.NeonYellow),
		BestLap = board(folder, origin * CFrame.new(70, 16, -60) * CFrame.Angles(0, math.rad(160), 0), "FASTEST LAP - CHAOS CITY", P.NeonCyan),
	}
	count += 4
	-- showroom turntables with the Stage 1 karts
	local showroom = Instance.new("Folder")
	showroom.Name = "Showroom"
	showroom.Parent = folder
	for i, def in ipairs(VehicleRegistry.all()) do
		local x = -60 + (i - 1) * 120 / math.max(1, #VehicleRegistry.ORDER - 1)
		local base = origin * CFrame.new(x * 0.5, 0, 10)
		part({ Name = "Turntable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 16, 16), CFrame = base * CFrame.new(0, 0.6, 0) * Parts.UP, Color = rgb(50, 50, 80), Material = M.Metal })
		part({ Name = "TurntableNeon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 16.6, 16.6), CFrame = base * CFrame.new(0, 0.4, 0) * Parts.UP, Color = neonFor(i), Material = M.Neon, CanCollide = false })
		local model = VehicleModels.build(def.Id, { cframe = base * CFrame.new(0, 1.2 + 1.4, 0) * CFrame.Angles(0, math.rad(35), 0), label = def.Name, name = "Showroom_" .. def.Id })
		model.Parent = showroom
		count += 30
	end
	-- kiosks
	local prompts = {}
	local kioskCount
	prompts.Garage, kioskCount = kiosk(folder, origin * CFrame.new(-48, 0, 50) * CFrame.Angles(0, math.pi, 0), "Garage", P.NeonGreen, "Choose kart")
	count += kioskCount
	prompts.Shop, kioskCount = kiosk(folder, origin * CFrame.new(-16, 0, 60) * CFrame.Angles(0, math.pi, 0), "Shop", P.NeonPink, "Open")
	count += kioskCount
	prompts.Daily, kioskCount = kiosk(folder, origin * CFrame.new(16, 0, 60) * CFrame.Angles(0, math.pi, 0), "Daily", P.NeonYellow, "Claim")
	count += kioskCount
	prompts.Codes, kioskCount = kiosk(folder, origin * CFrame.new(48, 0, 50) * CFrame.Angles(0, math.pi, 0), "Codes", P.NeonCyan, "Redeem")
	count += kioskCount
	return {
		folder = folder,
		spawn = spawn,
		spawnCFrame = spawn.CFrame,
		holdCFrame = CFrame.new(centre + Vector3.new(0, -80, 0)),
		portalPosition = portalPos,
		portalRadius = data.lobby.portalRadius,
		boardRows = boardRows,
		prompts = prompts,
		partCount = count,
	}
end

return LobbyBuilder
