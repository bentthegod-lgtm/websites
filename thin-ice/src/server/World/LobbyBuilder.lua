--[[
	LobbyBuilder - the shore camp and everything around the lake that never changes:
	snowy plaza, boardwalk with lamp posts, campfire ring, the beacon, the rescue sled, the
	warming hut, the escapes board, snow cliffs on three sides of the lake, the lakebed and
	water under the ice, pines, distant mountains and the aurora.

	Built once at startup (a few hundred parts, well under a frame's worth of work). The
	ice itself is generated per round by LakeBuilder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local Models = require(Shared.Models)
local Rng = require(Shared.Rng)

local LobbyBuilder = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local P = Models.Palette
local part = Models.part
local L = GameConfig.Lake
local G = GameConfig.Lobby

local LAKE_W = L.Columns * L.TileSize
local LAKE_L = L.RowsPerZone * #GameConfig.Zones * L.TileSize
local LAKE_MIN_X, LAKE_MAX_X = -LAKE_W / 2, LAKE_W / 2
local LAKE_FAR_Z = L.ShoreZ + LAKE_L

local function at(xz, y)
	return Vector3.new(xz[1], y or G.GroundTop, xz[2])
end
LobbyBuilder.at = at

local function board(parent, pivot, title, rows)
	local back = part({ Name = "Board", Size = Vector3.new(14, 11, 0.6), CFrame = pivot * CFrame.new(0, 7.5, 0), Color = P.WoodDark, Material = M.Wood, Parent = parent, CanCollide = true })
	for _, x in ipairs({ -6, 6 }) do
		part({ Name = "Leg", Size = Vector3.new(0.8, 4, 0.8), CFrame = pivot * CFrame.new(x, 1.6, 0), Color = P.WoodDark, Material = M.Wood, Parent = parent })
	end
	part({ Name = "BoardSnow", Size = Vector3.new(14.4, 0.5, 1), CFrame = pivot * CFrame.new(0, 13.2, 0), Color = P.Snow, Material = M.Snow, Parent = parent })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(560, 440)
	gui.LightInfluence = 0
	gui.Parent = back
	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 60)
	header.Font = Enum.Font.GothamBlack
	header.TextScaled = true
	header.Text = title
	header.TextColor3 = rgb(200, 236, 255)
	header.Parent = gui
	local labels = {}
	for i = 1, rows do
		local label = Instance.new("TextLabel")
		label.Name = "Row" .. i
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 24, 0, 60 + (i - 1) * 37)
		label.Size = UDim2.new(1, -48, 0, 34)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = rgb(240, 244, 250)
		label.Text = string.format("%d. ---", i)
		label.Parent = gui
		labels[i] = label
	end
	return labels
end

local function sign(parent, pivot, text, color)
	local plank = part({ Name = "Sign", Size = Vector3.new(9, 3, 0.5), CFrame = pivot * CFrame.new(0, 5, 0), Color = P.Wood, Material = M.Wood, Parent = parent })
	part({ Name = "SignPost", Size = Vector3.new(0.6, 4, 0.6), CFrame = pivot * CFrame.new(0, 2, 0), Color = P.WoodDark, Material = M.Wood, Parent = parent })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(300, 100)
	gui.LightInfluence = 0
	gui.Parent = plank
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or rgb(60, 40, 30)
	label.Parent = gui
	return plank
end

function LobbyBuilder.build(parent)
	local rng = Rng.new(7331)
	local folder = Instance.new("Folder")
	folder.Name = "ThinIceWorld"
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = folder
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder
	local lakeFolder = Instance.new("Folder")
	lakeFolder.Name = "Lake"
	lakeFolder.Parent = folder

	local top = G.GroundTop
	local world = { folder = folder, lakeFolder = lakeFolder }

	-- Ground: the shore plaza (everything with Z < ShoreZ) and the snow cliffs around the lake.
	local plaza = part({ Name = "Shore", Size = Vector3.new(220, 4, 130), CFrame = CFrame.new(0, top - 2, L.ShoreZ - 65), Color = P.Snow, Material = M.Snow, Parent = lobby, CanCollide = true })
	plaza:SetAttribute("TI_Shore", true)
	local bankH = G.BankHeight
	local sideW = 60
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (LAKE_W / 2 + sideW / 2)
		part({ Name = "Bank", Size = Vector3.new(sideW, bankH + 4, LAKE_L + 60), CFrame = CFrame.new(x, top + bankH / 2 - 2, L.ShoreZ + LAKE_L / 2 + 30), Color = P.Snow, Material = M.Snow, Parent = scenery, CanCollide = true })
		-- a lip of ice where the bank meets the lake
		part({ Name = "BankIce", Size = Vector3.new(2, bankH * 0.6, LAKE_L), CFrame = CFrame.new(side * (LAKE_W / 2 + 1), top + bankH * 0.3 - 1, L.ShoreZ + LAKE_L / 2), Color = P.IceLight, Material = M.Ice, Parent = scenery, CanCollide = true })
	end
	part({ Name = "FarBank", Size = Vector3.new(LAKE_W + sideW * 2, bankH + 4, 60), CFrame = CFrame.new(0, top + bankH / 2 - 2, LAKE_FAR_Z + 30), Color = P.Snow, Material = M.Snow, Parent = scenery, CanCollide = true })
	-- Invisible guard rails where the lobby plaza meets the cliffs (no climbing round the lake).
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Guard", Size = Vector3.new(2, 30, 140), CFrame = CFrame.new(side * 109, top + 15, L.ShoreZ - 65), Transparency = 1, Parent = scenery, CanCollide = true, CastShadow = false })
	end
	part({ Name = "Guard", Size = Vector3.new(220, 30, 2), CFrame = CFrame.new(0, top + 15, L.ShoreZ - 129), Transparency = 1, Parent = scenery, CanCollide = true, CastShadow = false })

	-- Under the ice: dark water you can wade in (and climb out of) and a lakebed to stand on.
	local water = part({ Name = "Water", Size = Vector3.new(LAKE_W, 0.4, LAKE_L), CFrame = CFrame.new(0, top - 1.6, L.ShoreZ + LAKE_L / 2), Color = P.Water, Material = M.Glass, Transparency = 0.15, Reflectance = 0.15, Parent = scenery, CastShadow = false })
	water:SetAttribute("TI_Water", true)
	-- The Deep Hollow's water is black.
	local deepLen = L.RowsPerZone * L.TileSize
	part({ Name = "DeepWater", Size = Vector3.new(LAKE_W, 0.4, deepLen), CFrame = CFrame.new(0, top - 1.55, LAKE_FAR_Z - deepLen / 2), Color = rgb(6, 12, 26), Material = M.Glass, Transparency = 0.05, Reflectance = 0.2, Parent = scenery, CastShadow = false })
	part({ Name = "Lakebed", Size = Vector3.new(LAKE_W, 2, LAKE_L), CFrame = CFrame.new(0, top - 5, L.ShoreZ + LAKE_L / 2), Color = rgb(30, 40, 52), Material = M.Slate, Parent = scenery, CanCollide = true })
	-- The shore edge: a low frosted ledge you step down from onto row 0.
	part({ Name = "ShoreEdge", Size = Vector3.new(LAKE_W + 4, 1, 1.4), CFrame = CFrame.new(0, top - 0.3, L.ShoreZ - 0.7), Color = P.IceLight, Material = M.Ice, Parent = lobby })

	-- Boardwalk from the hut down to the ice, with lamp posts.
	local walkStart, walkEnd = G.Hut[2] + 6, L.ShoreZ - 1
	local walkLen = walkEnd - walkStart
	part({ Name = "Boardwalk", Size = Vector3.new(9, 0.6, walkLen), CFrame = CFrame.new(0, top + 0.3, walkStart + walkLen / 2), Color = rgb(226, 200, 160), Material = M.WoodPlanks, Parent = lobby, CanCollide = true })
	for z = walkStart + 3, walkEnd - 2, 6 do
		part({ Name = "Plank", Size = Vector3.new(9.4, 0.25, 0.6), CFrame = CFrame.new(0, top + 0.7, z), Color = rgb(196, 160, 116), Material = M.Wood, Parent = lobby })
	end
	for z = walkStart + 4, walkEnd - 4, 18 do
		for _, x in ipairs({ -6, 6 }) do
			Models.lampPost(CFrame.new(x, top, z), lobby)
		end
	end
	-- The dock: a wider deck right at the shore.
	part({ Name = "Dock", Size = Vector3.new(26, 0.6, 10), CFrame = CFrame.new(0, top + 0.3, L.ShoreZ - 6), Color = rgb(214, 186, 144), Material = M.WoodPlanks, Parent = lobby, CanCollide = true })
	for _, x in ipairs({ -12.5, 12.5 }) do
		part({ Name = "DockPost", Size = Vector3.new(0.9, 3, 0.9), CFrame = CFrame.new(x, top + 1.5, L.ShoreZ - 1.5), Color = P.WoodDark, Material = M.Wood, Parent = lobby })
	end

	-- Spawn in front of the hut.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(at(G.Spawn, top + 0.2))
	spawn.Color = rgb(226, 200, 160)
	spawn.Material = M.WoodPlanks
	spawn.Transparency = 0
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	world.spawn = spawn
	world.spawnCFrame = CFrame.new(at(G.Spawn, top + 3.5)) * CFrame.Angles(0, math.pi, 0)

	world.hut = Models.hut(CFrame.new(at(G.Hut)) * CFrame.Angles(0, math.pi, 0), lobby)
	sign(world.hut, CFrame.new(at(G.Hut, top)) * CFrame.new(0, 3.8, 5.6) * CFrame.Angles(0, math.pi, 0), "WARMING HUT")

	-- Campfire ring with log benches: the warmest place in the world.
	world.campfire = Models.campfire(CFrame.new(at(G.Campfire)), lobby)
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3 + 0.4
		part({ Name = "Bench", Size = Vector3.new(5, 1, 1.4), CFrame = CFrame.new(at(G.Campfire, top + 0.5)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 5.4), Color = P.Wood, Material = M.Wood, Parent = lobby, CanCollide = true })
	end
	world.fires = { at(G.Campfire) }

	-- The beacon (delivered cores light it) and the rescue sled.
	local beacon, flame = Models.beacon(CFrame.new(at(G.Beacon)), lobby)
	world.beacon = { model = beacon, flame = flame, light = flame:FindFirstChild("BeaconLight"), position = at(G.Beacon) }
	sign(lobby, CFrame.new(at(G.Beacon)) * CFrame.new(-6, 0, -5) * CFrame.Angles(0, math.pi, 0), "BRING CORES HERE", rgb(30, 70, 110))
	local sled = Models.sled(CFrame.new(at(G.Sled)) * CFrame.Angles(0, math.rad(15), 0), lobby)
	world.sled = { model = sled, position = at(G.Sled) }
	sign(lobby, CFrame.new(at(G.Sled)) * CFrame.new(7, 0, -6) * CFrame.Angles(0, math.pi, 0), "RESCUE SLED")

	-- Escapes board + title sign.
	world.boardRows = board(lobby, CFrame.new(at(G.Board)) * CFrame.Angles(0, math.rad(70), 0), "MOST ESCAPES", 10)
	sign(lobby, CFrame.new(0, top, L.ShoreZ - 13) * CFrame.new(9, 0, 0) * CFrame.Angles(0, math.pi, 0), "THIN ICE", rgb(40, 80, 130))

	-- Snow mounds and supply crates for a lived-in camp.
	for _ = 1, 14 do
		local x = rng:NextNumber(-95, 95)
		local z = rng:NextNumber(-120, L.ShoreZ - 8)
		if math.abs(x) > 10 then
			Models.drift(CFrame.new(x, top - 0.6, z), scenery)
		end
	end
	for i = 1, 3 do
		part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(-26 + i * 3.2, top + 1.5, -32) * CFrame.Angles(0, i * 0.3, 0), Color = P.Wood, Material = M.WoodPlanks, Parent = lobby, CanCollide = true })
	end

	-- Pines: round the plaza and along the cliff tops.
	local pines = 0
	local function pine(x, y, z, scale)
		Models.pine(CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber() * 6, 0), scenery, scale)
		pines += 1
	end
	for _ = 1, 26 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		pine(side * rng:NextNumber(40, 100), top, rng:NextNumber(-120, L.ShoreZ - 10), rng:NextNumber(0.9, 1.5))
	end
	for z = L.ShoreZ + 6, LAKE_FAR_Z + 40, 22 do
		for _, side in ipairs({ -1, 1 }) do
			pine(side * rng:NextNumber(LAKE_W / 2 + 8, LAKE_W / 2 + 50), top + bankH, z + rng:NextNumber(-6, 6), rng:NextNumber(1, 1.7))
		end
	end
	for x = LAKE_MIN_X - 30, LAKE_MAX_X + 30, 20 do
		pine(x + rng:NextNumber(-5, 5), top + bankH, LAKE_FAR_Z + rng:NextNumber(10, 50), rng:NextNumber(1.1, 1.8))
	end
	world.pines = pines

	-- Distant blocky mountains.
	local mountainColor = rgb(70, 92, 140)
	for i = 0, 16 do
		local x = -320 + i * 40 + rng:NextNumber(-10, 10)
		local h = rng:NextNumber(60, 130)
		local z = LAKE_FAR_Z + rng:NextNumber(110, 180)
		part({ Name = "Mountain", Size = Vector3.new(rng:NextNumber(50, 80), h, 50), CFrame = CFrame.new(x, h / 2 - 4, z) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Color = mountainColor:Lerp(rgb(30, 40, 70), rng:NextNumber() * 0.5), Material = M.Slate, Parent = scenery, CastShadow = false })
		part({ Name = "MountainSnow", Size = Vector3.new(22, h * 0.18, 22), CFrame = CFrame.new(x, h - 2, z), Color = rgb(200, 214, 236), Material = M.Snow, Parent = scenery, CastShadow = false })
	end
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 10 do
			local h = rng:NextNumber(50, 110)
			local z = -80 + i * 55
			part({ Name = "Mountain", Size = Vector3.new(50, h, rng:NextNumber(50, 70)), CFrame = CFrame.new(side * rng:NextNumber(200, 240), h / 2 - 4, z), Color = mountainColor:Lerp(rgb(30, 40, 70), rng:NextNumber() * 0.5), Material = M.Slate, Parent = scenery, CastShadow = false })
		end
	end

	-- The aurora: long translucent ribbons high over the far shore.
	local auroraColors = { rgb(90, 255, 170), rgb(80, 220, 210), rgb(150, 120, 255) }
	for i = 0, 13 do
		local x = -280 + i * 42
		part({ Name = "Aurora", Size = Vector3.new(44, rng:NextNumber(60, 110), 1), CFrame = CFrame.new(x, 190 + math.sin(i * 0.8) * 22, LAKE_FAR_Z + 260) * CFrame.Angles(math.rad(-25), math.rad(math.sin(i) * 18), math.rad(math.cos(i * 0.7) * 10)), Color = auroraColors[(i % 3) + 1], Material = M.Neon, Transparency = 0.72, Parent = scenery, CastShadow = false })
	end

	folder.Parent = parent or workspace
	local count = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	world.partCount = count
	world.lakeBounds = { minX = LAKE_MIN_X, maxX = LAKE_MAX_X, minZ = L.ShoreZ, maxZ = LAKE_FAR_Z }
	return world
end

return LobbyBuilder
