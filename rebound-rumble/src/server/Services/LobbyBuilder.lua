--[[
	LobbyBuilder - the floating sky lobby: spawn, status board, global wins leaderboard,
	crate pedestal, giant ball centrepiece, how-to-play and "like for a code" signs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local ArenaConfig = require(Shared.Config.ArenaConfig)
local Build = require(script.Parent.Build)

local LobbyBuilder = {}

local WHITE = Color3.fromRGB(240, 244, 255)
local PINK = Color3.fromRGB(255, 70, 190)
local CYAN = Color3.fromRGB(60, 220, 255)
local GOLD = Color3.fromRGB(255, 205, 70)

local function buildLeaderboard(folder, cframe)
	local model = Instance.new("Model")
	model.Name = "WinsLeaderboard"
	model.Parent = folder
	local panel = Build.part(model, { Name = "Panel", Size = Vector3.new(22, 16, 1), CFrame = cframe, Color = Color3.fromRGB(20, 22, 40), Material = Enum.Material.SmoothPlastic })
	Build.neon(model, { Name = "Frame", Size = Vector3.new(23, 16.8, 0.6), CFrame = cframe * CFrame.new(0, 0, 0.3), Color = GOLD })
	for _, x in ipairs({ -9, 9 }) do
		Build.part(model, { Name = "Post", Size = Vector3.new(1, 10, 1), CFrame = cframe * CFrame.new(x, -12, 0.5), Color = Color3.fromRGB(40, 44, 70), Material = Enum.Material.Metal })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = panel
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.15, 0)
	title.BackgroundTransparency = 1
	title.Text = "MOST WINS"
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = GOLD
	title.Parent = gui
	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.Size = UDim2.new(1, 0, 0.1, 0)
	message.Position = UDim2.new(0, 0, 0.45, 0)
	message.BackgroundTransparency = 1
	message.Text = "Loading..."
	message.Font = Enum.Font.GothamMedium
	message.TextScaled = true
	message.TextColor3 = WHITE
	message.Parent = gui
	local rows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.new(0.9, 0, 0.075, 0)
		row.Position = UDim2.new(0.05, 0, 0.16 + (i - 1) * 0.082, 0)
		row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = WHITE
		row.Text = ""
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1 then GOLD elseif i == 2 then Color3.fromRGB(220, 220, 235) elseif i == 3 then Color3.fromRGB(230, 150, 90) else WHITE
		row.Parent = gui
		rows[i] = row
	end
	return {
		model = model,
		setRows = function(list, text)
			message.Text = text or ""
			message.Visible = text ~= nil
			for i, row in ipairs(rows) do
				local entry = list[i]
				row.Text = if entry then string.format("  #%d  %s  -  %d", entry.rank, entry.name, entry.wins) else ""
			end
		end,
	}
end

local function buildCentrepiece(folder, base)
	local model = Instance.new("Model")
	model.Name = "BallMonument"
	model.Parent = folder
	Build.disc(model, base + Vector3.new(0, 1, 0), 14, 2, Color3.fromRGB(40, 44, 70), Enum.Material.Metal, "Plinth")
	Build.disc(model, base + Vector3.new(0, 2.2, 0), 11, 0.4, PINK, Enum.Material.Neon, "PlinthGlow")
	local ball = Build.neon(model, { Name = "GiantBall", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), CFrame = CFrame.new(base + Vector3.new(0, 9, 0)), Color = Color3.fromRGB(255, 120, 220), CanCollide = false })
	Build.light(ball, PINK, 30, 3)
	Build.sparkles(ball, PINK, 10)
	for i, tilt in ipairs({ 20, -35, 70 }) do
		Build.neon(model, {
			Name = "Orbit" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 14 + i * 1.5, 14 + i * 1.5),
			CFrame = CFrame.new(base + Vector3.new(0, 9, 0)) * CFrame.Angles(math.rad(tilt), math.rad(i * 50), math.rad(90)),
			Color = if i == 2 then CYAN else WHITE,
			Transparency = 0.55,
			CanCollide = false,
		})
	end
	return model
end

local function buildCratePedestal(folder, cframe)
	local model = Instance.new("Model")
	model.Name = "CratePedestal"
	model.Parent = folder
	Build.part(model, { Name = "Base", Size = Vector3.new(8, 2, 8), CFrame = cframe * CFrame.new(0, 1, 0), Color = Color3.fromRGB(40, 44, 70), Material = Enum.Material.Metal })
	local crate = Build.part(model, { Name = "Crate", Size = Vector3.new(5, 5, 5), CFrame = cframe * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, math.rad(25), 0), Color = Color3.fromRGB(120, 70, 220), Material = Enum.Material.SmoothPlastic })
	for _, axis in ipairs({ Vector3.new(5.2, 0.6, 0.6), Vector3.new(0.6, 5.2, 0.6), Vector3.new(0.6, 0.6, 5.2) }) do
		Build.neon(model, { Name = "Band", Size = axis, CFrame = crate.CFrame, Color = GOLD, CanCollide = false })
	end
	Build.light(crate, Color3.fromRGB(190, 120, 255), 18, 2)
	Build.sparkles(crate, GOLD, 5)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CratePrompt"
	prompt.ActionText = "Open Crates"
	prompt.ObjectText = "Cosmetic Crates"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate
	local sign = Build.part(model, { Name = "Sign", Size = Vector3.new(8, 2, 0.4), CFrame = cframe * CFrame.new(0, 9.5, 0), Color = Color3.fromRGB(20, 22, 40), CanCollide = false })
	Build.sign(sign, "CRATES", GOLD)
	return model, prompt
end

function LobbyBuilder.build(parent)
	local origin = Vector3.new(table.unpack(ArenaConfig.Lobby.Origin))
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = parent or workspace

	-- Platform with a rocky underside and a neon rim.
	Build.disc(folder, origin + Vector3.new(0, -2, 0), 130, 4, Color3.fromRGB(210, 220, 240), Enum.Material.SmoothPlastic, "Floor")
	Build.disc(folder, origin + Vector3.new(0, -0.05, 0), 60, 0.2, Color3.fromRGB(190, 200, 230), Enum.Material.Marble, "Inlay")
	Build.disc(folder, origin + Vector3.new(0, -2.2, 0), 133, 3.4, CYAN, Enum.Material.Neon, "Rim")
	for i = 1, 5 do
		Build.disc(folder, origin + Vector3.new(0, -4 - i * 4, 0), 126 - i * 22, 4.2, Color3.fromRGB(110 - i * 8, 100 - i * 8, 120 - i * 6), Enum.Material.Rock, "Underside" .. i)
	end
	Build.barrierRing(folder, origin, 63, 14, 32)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.5, 18))
	spawn.Color = Color3.fromRGB(60, 220, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder

	-- Neon pillars around the rim.
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local pos = origin + Vector3.new(math.cos(a) * 58, 5, math.sin(a) * 58)
		Build.part(folder, { Name = "Pillar", Size = Vector3.new(2.4, 10, 2.4), CFrame = CFrame.new(pos), Color = Color3.fromRGB(40, 44, 70), Material = Enum.Material.Metal })
		local cap = Build.neon(folder, { Name = "PillarCap", Size = Vector3.new(3, 1, 3), CFrame = CFrame.new(pos + Vector3.new(0, 5.5, 0)), Color = if i % 2 == 0 then PINK else CYAN })
		Build.light(cap, cap.Color, 14, 1.5)
	end

	buildCentrepiece(folder, origin + Vector3.new(0, 0, -22))

	local board = buildLeaderboard(folder, CFrame.lookAt(origin + Vector3.new(-44, 16, -10), origin + Vector3.new(0, 16, 0)))

	-- Status board (round countdown / alive count) above the monument.
	local statusPart = Build.part(folder, { Name = "StatusBoard", Size = Vector3.new(30, 6, 1), CFrame = CFrame.lookAt(origin + Vector3.new(0, 24, -40), origin + Vector3.new(0, 24, 0)), Color = Color3.fromRGB(20, 22, 40), CanCollide = false })
	local statusLabel = Build.sign(statusPart, "WAITING FOR PLAYERS", WHITE)

	local _, cratePrompt = buildCratePedestal(folder, CFrame.new(origin + Vector3.new(40, 0, -12)) * CFrame.Angles(0, math.rad(-60), 0))

	-- How to play + like-for-code signs.
	local howTo = Build.part(folder, { Name = "HowToSign", Size = Vector3.new(16, 9, 0.6), CFrame = CFrame.lookAt(origin + Vector3.new(36, 7, 30), origin + Vector3.new(0, 7, 0)), Color = Color3.fromRGB(20, 22, 40) })
	Build.sign(howTo, "HOW TO PLAY\nThe ball hunts one player (red glow).\nPress F / Click / PARRY when it's close to send it at whoever you're looking at.\nMiss = BOOM. Last one standing wins!", WHITE)
	local like = Build.part(folder, { Name = "LikeSign", Size = Vector3.new(14, 5, 0.6), CFrame = CFrame.lookAt(origin + Vector3.new(-36, 5, 30), origin + Vector3.new(0, 5, 0)), Color = Color3.fromRGB(20, 22, 40) })
	Build.sign(like, "LIKE the game & use code LIKETHEGAME for free coins!", GOLD)

	-- Floating mini-islands around the lobby for depth.
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + 0.3
		local pos = origin + Vector3.new(math.cos(a) * 110, -10 + (i % 3) * 8, math.sin(a) * 110)
		Build.disc(folder, pos, 18 + (i % 2) * 8, 3, Color3.fromRGB(110, 190, 90), Enum.Material.Grass, "Islet")
		Build.disc(folder, pos + Vector3.new(0, -3, 0), 12 + (i % 2) * 6, 4, Color3.fromRGB(110, 90, 80), Enum.Material.Rock, "IsletRock")
	end

	return {
		folder = folder,
		spawn = spawn,
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0),
		board = board,
		cratePrompt = cratePrompt,
		setStatus = function(text, color)
			statusLabel.Text = text
			statusLabel.TextColor3 = color or WHITE
		end,
	}
end

return LobbyBuilder
