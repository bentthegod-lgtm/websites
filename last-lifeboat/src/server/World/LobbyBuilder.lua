--[[
	LobbyBuilder - the harbour dock at dusk, built once at startup (about 700 parts, a few
	milliseconds): plank deck on pilings, lanterns, crates and barrels, bollards and rope,
	the ticket booth (the shop kiosk), the global leaderboard board, the daily reward chest,
	the codes post box, three ship vote pads, a warehouse, a crane and the town quay behind,
	a breakwater lighthouse out at sea. The ship is moored broadside to the dock (see
	GameConfig.World) and built per round by ShipBuilder; the sea is Terrain (OceanBuilder).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Parts = require(Shared.Parts)
local Rng = require(Shared.Rng)

local LobbyBuilder = {}

local P = Parts.Palette
local M = Enum.Material
local rgb = Color3.fromRGB
local V3 = Vector3.new
local W = GameConfig.World

local function sign(part, text, color, bg, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 120)
	gui.LightInfluence = 0.3
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or P.Navy
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color or P.Brass
	label.Font = Enum.Font.Antique
	label.Parent = gui
	return label
end
LobbyBuilder.sign = sign

function LobbyBuilder.build(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Harbour"
	folder.Parent = parent
	local b = Parts.builder(CFrame.new(), folder)
	local rng = Rng.new(2024)
	local top = W.DockTop
	local x0, x1 = W.DockX[1], W.DockX[2]
	local z0, z1 = W.DockZ[1], W.DockZ[2]
	local world = { folder = folder, votePads = {}, lanterns = {} }

	-- Dock deck: plank strips with slightly varied colours, edge beams, pilings.
	local strip = 5
	for z = z0, z1 - strip, strip do
		local shade = rng:NextNumber(-12, 12)
		b:part({ Name = "Planks", Size = V3(x1 - x0, 1, strip - 0.15), CFrame = CFrame.new((x0 + x1) / 2, top - 0.5, z + strip / 2), Color = rgb(128 + shade, 92 + shade, 62 + shade * 0.6), Material = M.WoodPlanks })
	end
	b:part({ Name = "DockUnder", Size = V3(x1 - x0, 1.2, z1 - z0), CFrame = CFrame.new((x0 + x1) / 2, top - 1.6, (z0 + z1) / 2), Color = rgb(70, 52, 38), Material = M.Wood })
	for _, z in ipairs({ z0, z1 }) do
		b:part({ Name = "EdgeBeam", Size = V3(x1 - x0, 1.4, 1), CFrame = CFrame.new((x0 + x1) / 2, top - 0.3, z), Color = rgb(84, 60, 42), Material = M.Wood })
	end
	b:part({ Name = "EdgeBeam", Size = V3(1, 1.4, z1 - z0), CFrame = CFrame.new(x1, top - 0.3, (z0 + z1) / 2), Color = rgb(84, 60, 42), Material = M.Wood })
	for z = z0, z1, 10 do
		for _, x in ipairs({ x1 - 0.5, x0 + 40, x0 + 10 }) do
			b:part({ Name = "Piling", Shape = Enum.PartType.Cylinder, Size = V3(top + 26, 1.8, 1.8), CFrame = CFrame.new(x, (top + 2 - 24) / 2, z) * Parts.UP, Color = rgb(70, 54, 40), Material = M.Wood })
		end
	end
	for x = x0 + 10, x1, 12 do
		for _, z in ipairs({ z0 - 0.5, z1 + 0.5 }) do
			b:part({ Name = "Piling", Shape = Enum.PartType.Cylinder, Size = V3(top + 26, 1.8, 1.8), CFrame = CFrame.new(x, (top + 2 - 24) / 2, z) * Parts.UP, Color = rgb(70, 54, 40), Material = M.Wood })
		end
	end
	-- bollards with rope along the pier edge (where the ship is moored)
	for z = z0 + 8, z1 - 8, 18 do
		b:part({ Name = "Bollard", Shape = Enum.PartType.Cylinder, Size = V3(1.8, 1.6, 1.6), CFrame = CFrame.new(x1 - 2, top + 0.9, z) * Parts.UP, Color = P.Black, Material = M.Metal })
		b:part({ Name = "BollardCap", Shape = Enum.PartType.Cylinder, Size = V3(0.4, 2.2, 2.2), CFrame = CFrame.new(x1 - 2, top + 1.9, z) * Parts.UP, Color = P.Black, Material = M.Metal })
		b:part({ Name = "RopeCoil", Shape = Enum.PartType.Cylinder, Size = V3(0.6, 2.6, 2.6), CFrame = CFrame.new(x1 - 2, top + 0.3, z + 2.4) * Parts.UP, Color = P.Rope, Material = M.Fabric })
	end
	-- ladders back up from the water
	for _, z in ipairs({ -30, 30 }) do
		local ladder = b:part({ Name = "DockLadder", Class = "TrussPart", Size = V3(2, 10, 2), CFrame = CFrame.new(x1 + 1, top - 5, z), Color = P.Steel, Material = M.Metal })
		ladder:SetAttribute("Ladder", true)
	end

	-- Lanterns along both long edges.
	for z = z0 + 6, z1 - 6, 16 do
		for _, x in ipairs({ x1 - 5, x0 + 4 }) do
			b:part({ Name = "LanternPost", Size = V3(0.6, 9, 0.6), CFrame = CFrame.new(x, top + 4.5, z), Color = P.Black, Material = M.Metal })
			b:part({ Name = "LanternArm", Size = V3(0.3, 0.3, 2), CFrame = CFrame.new(x, top + 8.8, z + 0.8), Color = P.Black, Material = M.Metal })
			local glow = b:part({ Name = "Lantern", Size = V3(1, 1.4, 1), CFrame = CFrame.new(x, top + 8, z + 1.6), Color = rgb(255, 196, 110), Material = M.Neon, CastShadow = false, CanCollide = false })
			b:part({ Name = "LanternCap", Size = V3(1.4, 0.3, 1.4), CFrame = CFrame.new(x, top + 8.85, z + 1.6), Color = P.Black, Material = M.Metal, CanCollide = false })
			Parts.light(glow, rgb(255, 190, 110), 24, 1.6, false)
			table.insert(world.lanterns, glow)
		end
	end

	-- Crates, barrels and nets scattered in clusters.
	local clusters = { { -58, -56 }, { -60, 50 }, { 8, -62 }, { 10, 62 }, { -24, 58 } }
	for _, c in ipairs(clusters) do
		for i = 1, 4 do
			local s = rng:NextNumber(2.4, 4)
			local stack = if i == 4 then s + rng:NextNumber(2.4, 3) else s / 2
			b:part({ Name = "Crate", Size = V3(s, s, s), CFrame = CFrame.new(c[1] + rng:NextNumber(-5, 5), top + stack, c[2] + rng:NextNumber(-4, 4)) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0), Color = if i % 2 == 0 then P.Crate else P.WoodLight, Material = M.WoodPlanks })
		end
		for _ = 1, 2 do
			b:part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = V3(3, 2.2, 2.2), CFrame = CFrame.new(c[1] + rng:NextNumber(-6, 6), top + 1.5, c[2] + rng:NextNumber(-6, 6)) * Parts.UP, Color = rgb(110, 70, 44), Material = M.Wood })
		end
	end

	-- Spawn.
	local spawnCF = CFrame.new(W.Spawn[1], top + 3, W.Spawn[2])
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DockSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 0.4, 12)
	spawn.CFrame = CFrame.new(W.Spawn[1], top + 0.2, W.Spawn[2])
	spawn.Color = rgb(150, 112, 74)
	spawn.Material = M.WoodPlanks
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	b.count += 1
	b:part({ Name = "CompassRose", Shape = Enum.PartType.Cylinder, Size = V3(0.1, 9, 9), CFrame = CFrame.new(W.Spawn[1], top + 0.42, W.Spawn[2]) * Parts.UP, Color = P.Brass, Material = M.Metal, CanCollide = false })
	b:part({ Name = "CompassStar", Size = V3(1, 0.12, 8), CFrame = CFrame.new(W.Spawn[1], top + 0.45, W.Spawn[2]), Color = P.Navy, CanCollide = false })
	b:part({ Name = "CompassStar", Size = V3(8, 0.12, 1), CFrame = CFrame.new(W.Spawn[1], top + 0.45, W.Spawn[2]), Color = P.Navy, CanCollide = false })
	world.spawn = spawn
	world.spawnCFrame = spawnCF

	-- The harbour arch over the spawn, the raised gangway, bunting along the pier.
	local ax = W.Spawn[1] + 10
	for _, z in ipairs({ -9, 9 }) do
		b:part({ Name = "ArchPost", Size = V3(1.2, 13, 1.2), CFrame = CFrame.new(ax, top + 6.5, z), Color = P.Navy, Material = M.Metal })
		b:part({ Name = "ArchLamp", Shape = Enum.PartType.Ball, Size = V3(1.1, 1.1, 1.1), CFrame = CFrame.new(ax, top + 13.6, z), Color = P.Window, Material = M.Neon, CastShadow = false, CanCollide = false })
	end
	local arch = b:part({ Name = "ArchSign", Size = V3(0.8, 3.2, 20), CFrame = CFrame.new(ax, top + 11.6, 0), Color = P.Navy, Material = M.SmoothPlastic })
	sign(arch, "DEPARTURES", P.Brass, P.Navy, Enum.NormalId.Right)
	sign(arch, "DEPARTURES", P.Brass, P.Navy, Enum.NormalId.Left)
	b:part({ Name = "ArchTrim", Size = V3(1, 0.4, 20.4), CFrame = CFrame.new(ax, top + 13.4, 0), Color = P.Brass, Material = M.Metal })
	local gz = 34
	b:part({ Name = "Gangway", Size = V3(14, 0.6, 4), CFrame = CFrame.new(x1 + 4, top + 3.2, gz) * CFrame.Angles(0, 0, math.rad(24)), Color = P.Teak, Material = M.WoodPlanks })
	for _, dz in ipairs({ -2, 2 }) do
		b:part({ Name = "GangwayRail", Size = V3(14, 0.25, 0.25), CFrame = CFrame.new(x1 + 4, top + 5.4, gz + dz) * CFrame.Angles(0, 0, math.rad(24)), Color = P.White, Material = M.Metal, CanCollide = false })
	end
	b:part({ Name = "GangwayFoot", Size = V3(3, 1.4, 5), CFrame = CFrame.new(x1 - 2, top + 0.7, gz), Color = P.SteelDark, Material = M.Metal })
	local flags = { P.Red, P.Cream, P.Navy, P.Hazard, P.Green, P.Orange }
	for z = z0 + 6, z1 - 22, 32 do
		local a, c = V3(x1 - 5, top + 8.6, z + 1.6), V3(x1 - 5, top + 8.6, z + 33.6)
		local cf, len = Parts.beamCFrame(a, c)
		b:part({ Name = "BuntingLine", Size = V3(0.08, 0.08, len), CFrame = cf * CFrame.new(0, -0.6, 0), Color = P.Rope, CanCollide = false, CastShadow = false })
		for i = 1, 7 do
			local fz = a.Z + i * len / 8
			b:part({ Name = "Flag", Class = "WedgePart", Size = V3(0.1, 1.1, 1.2), CFrame = CFrame.new(x1 - 5, top + 7.4 - math.sin(i / 8 * math.pi) * 1.2, fz) * CFrame.Angles(math.rad(180), 0, 0), Color = flags[(i + math.floor(z)) % #flags + 1], CanCollide = false, CastShadow = false })
		end
	end

	-- Vote pads: one per ship, along the pier edge, each with a sign.
	for i, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		local pos = V3(4, top, -26 + (i - 1) * 26)
		local col = Parts.rgb(def.Color)
		local pad = b:part({ Name = "VotePad_" .. key, Shape = Enum.PartType.Cylinder, Size = V3(0.5, 12, 12), CFrame = CFrame.new(pos + V3(0, 0.25, 0)) * Parts.UP, Color = P.Navy, Material = M.SmoothPlastic })
		local rim = b:part({ Name = "VoteRim", Shape = Enum.PartType.Cylinder, Size = V3(0.4, 13, 13), CFrame = CFrame.new(pos + V3(0, 0.15, 0)) * Parts.UP, Color = col, Material = M.Neon, CastShadow = false })
		b:part({ Name = "VoteSignPost", Size = V3(0.5, 7, 0.5), CFrame = CFrame.new(pos + V3(-7.5, 3.5, 0)), Color = P.Black, Material = M.Metal })
		local board = b:part({ Name = "VoteSign", Size = V3(0.4, 4, 9), CFrame = CFrame.new(pos + V3(-7.5, 7.5, 0)), Color = P.Navy, Material = M.SmoothPlastic })
		local label = sign(board, string.format("%s\n%s", string.upper(def.Name), if def.UnlockEscapes > 0 then string.format("Unlocks at %d escapes", def.UnlockEscapes) else "Always open"), P.Cream, P.Navy, Enum.NormalId.Right)
		local count = sign(board, "0 votes", col, P.Navy, Enum.NormalId.Left)
		world.votePads[key] = { position = pos, pad = pad, rim = rim, label = label, count = count }
	end

	-- Ticket booth = the shop kiosk.
	local kx, kz = -50, -24
	b:part({ Name = "BoothBase", Size = V3(10, 8, 8), CFrame = CFrame.new(kx, top + 4, kz), Color = P.Navy, Material = M.WoodPlanks })
	b:part({ Name = "BoothRoof", Size = V3(12, 0.8, 10), CFrame = CFrame.new(kx, top + 8.6, kz), Color = P.Red, Material = M.SmoothPlastic })
	b:part({ Name = "BoothRoofTrim", Size = V3(12.2, 0.4, 10.2), CFrame = CFrame.new(kx, top + 8.1, kz), Color = P.Cream, Material = M.SmoothPlastic })
	b:part({ Name = "BoothWindow", Size = V3(0.3, 3, 6), CFrame = CFrame.new(kx + 5.05, top + 5, kz), Color = rgb(255, 214, 150), Material = M.Neon, CastShadow = false })
	local counter = b:part({ Name = "BoothCounter", Size = V3(2, 0.5, 7), CFrame = CFrame.new(kx + 6, top + 3.3, kz), Color = P.Teak, Material = M.Wood })
	local boothSign = b:part({ Name = "BoothSign", Size = V3(0.4, 2.2, 9), CFrame = CFrame.new(kx + 5.4, top + 10, kz), Color = P.Navy, Material = M.SmoothPlastic })
	sign(boothSign, "TICKETS & SUPPLIES", P.Brass, P.Navy, Enum.NormalId.Right)
	local lamp = b:part({ Name = "BoothLamp", Shape = Enum.PartType.Ball, Size = V3(1, 1, 1), CFrame = CFrame.new(kx + 5.6, top + 7.4, kz), Color = P.Window, Material = M.Neon, CastShadow = false, CanCollide = false })
	Parts.light(lamp, P.Window, 18, 1.4, false)
	world.kiosk = counter

	-- Leaderboard board: two columns (Total Escapes, Loot Banked).
	local bx, bz = -50, 22
	for _, dz in ipairs({ -7, 7 }) do
		b:part({ Name = "BoardPost", Size = V3(0.8, 14, 0.8), CFrame = CFrame.new(bx, top + 7, bz + dz), Color = P.Teak, Material = M.Wood })
	end
	local board = b:part({ Name = "Leaderboard", Size = V3(0.6, 10, 15), CFrame = CFrame.new(bx, top + 9, bz), Color = P.Navy, Material = M.SmoothPlastic })
	b:part({ Name = "BoardFrame", Size = V3(0.5, 10.6, 15.6), CFrame = CFrame.new(bx - 0.1, top + 9, bz), Color = P.Brass, Material = M.Metal })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Right
	gui.CanvasSize = Vector2.new(600, 400)
	gui.LightInfluence = 0.2
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	title.Text = "HALL OF SURVIVORS"
	title.TextColor3 = P.Brass
	title.Font = Enum.Font.Antique
	title.TextScaled = true
	title.Parent = gui
	world.boardRows = {}
	for col, key in ipairs({ "Escapes", "Banked" }) do
		local head = Instance.new("TextLabel")
		head.Size = UDim2.new(0.5, -10, 0, 30)
		head.Position = UDim2.new((col - 1) * 0.5, 5, 0, 52)
		head.BackgroundTransparency = 1
		head.Text = if key == "Escapes" then "TOTAL ESCAPES" else "LOOT BANKED"
		head.TextColor3 = P.Cream
		head.Font = Enum.Font.GothamBold
		head.TextScaled = true
		head.Parent = gui
		world.boardRows[key] = {}
		for i = 1, GameConfig.Leaderboard.Rows do
			local row = Instance.new("TextLabel")
			row.Name = key .. i
			row.Size = UDim2.new(0.5, -10, 0, 30)
			row.Position = UDim2.new((col - 1) * 0.5, 5, 0, 84 + (i - 1) * 31)
			row.BackgroundTransparency = 1
			row.Text = i .. ". ---"
			row.TextColor3 = if i == 1 then P.Brass else P.Cream
			row.Font = Enum.Font.Gotham
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Parent = gui
			world.boardRows[key][i] = row
		end
	end

	-- Daily reward sea chest and the codes post box.
	local cx, cz = -22, -50
	local chest = b:part({ Name = "DailyChest", Size = V3(5, 3, 3.4), CFrame = CFrame.new(cx, top + 1.5, cz), Color = P.Wood, Material = M.Wood })
	b:part({ Name = "ChestLid", Size = V3(5.2, 1.2, 3.6), CFrame = CFrame.new(cx, top + 3.6, cz), Color = rgb(120, 76, 44), Material = M.Wood })
	b:part({ Name = "ChestBand", Size = V3(5.3, 4.4, 0.4), CFrame = CFrame.new(cx, top + 2.2, cz), Color = P.Brass, Material = M.Metal })
	local cglow = b:part({ Name = "ChestGlow", Size = V3(4.6, 0.3, 3), CFrame = CFrame.new(cx, top + 3.05, cz), Color = rgb(255, 210, 90), Material = M.Neon, CanCollide = false, CastShadow = false })
	Parts.light(cglow, rgb(255, 200, 90), 12, 1.2, false)
	local chestSign = b:part({ Name = "ChestSign", Size = V3(5, 1.4, 0.3), CFrame = CFrame.new(cx, top + 6, cz), Color = P.Navy, CanCollide = false })
	sign(chestSign, "DAILY REWARD", P.Brass, P.Navy, Enum.NormalId.Back)
	world.dailyChest = chest
	local px, pz = -22, 50
	local postbox = b:part({ Name = "CodesBox", Shape = Enum.PartType.Cylinder, Size = V3(5, 3, 3), CFrame = CFrame.new(px, top + 2.5, pz) * Parts.UP, Color = P.Red, Material = M.SmoothPlastic })
	b:part({ Name = "CodesBoxTop", Shape = Enum.PartType.Ball, Size = V3(3.1, 3.1, 3.1), CFrame = CFrame.new(px, top + 5, pz), Color = P.Red, Material = M.SmoothPlastic })
	local slot = b:part({ Name = "CodesSlot", Size = V3(1.6, 0.4, 0.3), CFrame = CFrame.new(px, top + 4, pz - 1.45), Color = P.Black, CanCollide = false })
	local codeSign = b:part({ Name = "CodesSign", Size = V3(4, 1.2, 0.3), CFrame = CFrame.new(px, top + 7.4, pz), Color = P.Navy, CanCollide = false })
	sign(codeSign, "CODES", P.Brass, P.Navy, Enum.NormalId.Front)
	local _ = slot
	world.codesBox = postbox

	-- Warehouse and crane behind, the town quay with lit windows.
	b:part({ Name = "Quay", Size = V3(120, 8, 300), CFrame = CFrame.new(x0 - 60, top - 4, 0), Color = rgb(96, 94, 92), Material = M.Cobblestone })
	b:part({ Name = "Warehouse", Size = V3(34, 22, 60), CFrame = CFrame.new(x0 - 26, top + 11, 0), Color = rgb(150, 70, 52), Material = M.Brick })
	b:part({ Name = "WarehouseRoof", Class = "WedgePart", Size = V3(60, 8, 18), CFrame = CFrame.new(x0 - 26 + 9, top + 26, 0) * CFrame.Angles(0, math.rad(-90), 0), Color = rgb(60, 64, 72), Material = M.Slate })
	b:part({ Name = "WarehouseRoof", Class = "WedgePart", Size = V3(60, 8, 18), CFrame = CFrame.new(x0 - 26 - 9, top + 26, 0) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(60, 64, 72), Material = M.Slate })
	b:part({ Name = "WarehouseDoor", Size = V3(0.4, 14, 16), CFrame = CFrame.new(x0 - 8.8, top + 7, 0), Color = rgb(70, 50, 36), Material = M.Wood })
	local ws = b:part({ Name = "WarehouseSign", Size = V3(0.4, 3, 26), CFrame = CFrame.new(x0 - 8.7, top + 17, 0), Color = P.Cream, Material = M.SmoothPlastic })
	sign(ws, "HARBOUR MASTER", P.Navy, P.Cream, Enum.NormalId.Right)
	for i = -2, 2 do
		local win = b:part({ Name = "WarehouseWindow", Size = V3(0.3, 2.4, 3.2), CFrame = CFrame.new(x0 - 8.8, top + 17, i * 11 + (if i == 0 then 30 else 0)), Color = P.Window, Material = M.Neon, CastShadow = false })
		local _ = win
	end
	local townRng = Rng.new(77)
	for i = 1, 14 do
		local h = townRng:NextNumber(14, 34)
		local z = -140 + i * 19
		local x = x0 - 70 - townRng:NextNumber(0, 30)
		local col = ({ rgb(196, 170, 140), rgb(170, 120, 96), rgb(220, 210, 190), rgb(140, 150, 160) })[townRng:NextInteger(1, 4)]
		b:part({ Name = "TownHouse", Size = V3(16, h, 16), CFrame = CFrame.new(x, top + h / 2, z), Color = col, Material = M.SmoothPlastic })
		b:part({ Name = "TownRoof", Class = "WedgePart", Size = V3(16, 6, 8.5), CFrame = CFrame.new(x + 4, top + h + 3, z) * CFrame.Angles(0, math.rad(-90), 0), Color = rgb(90, 50, 44), Material = M.Slate })
		b:part({ Name = "TownRoof", Class = "WedgePart", Size = V3(16, 6, 8.5), CFrame = CFrame.new(x - 4, top + h + 3, z) * CFrame.Angles(0, math.rad(90), 0), Color = rgb(90, 50, 44), Material = M.Slate })
		for j = 1, 2 do
			b:part({ Name = "TownWindow", Size = V3(0.3, 2.4, 2.4), CFrame = CFrame.new(x + 8.05, top + h * (j / 3), z + (j * 2 - 3) * 3.5), Color = P.Window, Material = M.Neon, CastShadow = false })
		end
	end
	-- crane at the far end of the dock
	local crx, crz = -6, -66
	for _, dx in ipairs({ -3, 3 }) do
		for _, dz in ipairs({ -3, 3 }) do
			b:part({ Name = "CraneLeg", Size = V3(0.8, 26, 0.8), CFrame = CFrame.new(crx + dx, top + 13, crz + dz), Color = P.Hazard, Material = M.Metal })
		end
	end
	b:part({ Name = "CraneCab", Size = V3(8, 5, 8), CFrame = CFrame.new(crx, top + 28, crz), Color = P.Hazard, Material = M.Metal })
	b:part({ Name = "CraneJib", Size = V3(40, 1.4, 1.4), CFrame = CFrame.new(crx + 18, top + 31, crz) * CFrame.Angles(0, 0, math.rad(8)), Color = P.Hazard, Material = M.Metal })
	b:part({ Name = "CraneHook", Size = V3(0.2, 14, 0.2), CFrame = CFrame.new(crx + 34, top + 26, crz), Color = P.Black, CanCollide = false })
	-- breakwater and lighthouse out at sea, buoys
	b:part({ Name = "Breakwater", Size = V3(14, 6, 160), CFrame = CFrame.new(220, 1, -160) * CFrame.Angles(0, math.rad(30), 0), Color = rgb(90, 92, 96), Material = M.Rock })
	b:part({ Name = "Lighthouse", Shape = Enum.PartType.Cylinder, Size = V3(34, 9, 9), CFrame = CFrame.new(260, 21, -228) * Parts.UP, Color = P.White, Material = M.SmoothPlastic })
	b:part({ Name = "LighthouseBand", Shape = Enum.PartType.Cylinder, Size = V3(6, 9.4, 9.4), CFrame = CFrame.new(260, 18, -228) * Parts.UP, Color = P.Red, Material = M.SmoothPlastic })
	local beam = b:part({ Name = "LighthouseLamp", Shape = Enum.PartType.Ball, Size = V3(5, 5, 5), CFrame = CFrame.new(260, 40, -228), Color = rgb(255, 240, 200), Material = M.Neon, CastShadow = false })
	Parts.light(beam, rgb(255, 236, 190), 60, 2, false)
	for i = 1, 6 do
		local bz = -150 + i * 50
		b:part({ Name = "Buoy", Shape = Enum.PartType.Ball, Size = V3(2.4, 2.4, 2.4), CFrame = CFrame.new(150 + (i % 2) * 30, 0.6, bz), Color = if i % 2 == 0 then P.Red else P.Green, Material = M.SmoothPlastic })
	end

	world.partCount = b.count
	return world
end

-- The ship's starting pivot for a ship key: stern on the centreline at the waterline,
-- broadside to the dock, centred on Z = 0.
function LobbyBuilder.shipBase(shipKey)
	local def = GameConfig.Ships[shipKey]
	return CFrame.new(W.ShipX, W.SeaLevel, -def.Length / 2)
end

return LobbyBuilder
