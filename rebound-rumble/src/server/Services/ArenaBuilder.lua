--[[
	ArenaBuilder - procedural arenas, one per theme, rebuilt each round.

	Every arena is a circular play area of ArenaConfig.Radius around the arena origin with
	the floor top at origin.Y, an invisible barrier ring, spawn points on an inner ring and
	themed decoration around (not inside) the play area so nothing blocks the ball.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local ArenaConfig = require(Shared.Config.ArenaConfig)
local Rng = require(Shared.Rng)
local Build = require(script.Parent.Build)

local ArenaBuilder = {}

local themes = {}

local function ring(n, radius, fn)
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		fn(i, a, math.cos(a) * radius, math.sin(a) * radius)
	end
end

function themes.FloatingIsland(folder, o, r, theme, rng)
	Build.disc(folder, o + Vector3.new(0, -2, 0), r * 2 + 6, 4, Build.rgb(theme.Floor), Enum.Material.Grass, "Floor")
	Build.disc(folder, o + Vector3.new(0, -0.02, 0), 24, 0.1, Color3.fromRGB(235, 225, 190), Enum.Material.Sand, "CenterSand")
	for i = 1, 6 do
		Build.disc(folder, o + Vector3.new(0, -4 - i * 5, 0), r * 2 + 4 - i * 22, 5.2, Build.rgb(theme.Edge):Lerp(Color3.new(0, 0, 0), i * 0.06), Enum.Material.Rock, "Rock" .. i)
	end
	-- Trees on the outer edge.
	ring(9, r - 3, function(i, _, x, z)
		local base = o + Vector3.new(x, 0, z)
		local h = rng:range(7, 11)
		Build.part(folder, { Name = "Trunk", Size = Vector3.new(1.6, h, 1.6), CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)), Color = Color3.fromRGB(110, 75, 50), Material = Enum.Material.Wood })
		for j = 1, 3 do
			Build.part(folder, {
				Name = "Leaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1, 1, 1) * (7 - j),
				CFrame = CFrame.new(base + Vector3.new(rng:range(-1, 1), h + j * 1.6, rng:range(-1, 1))),
				Color = Color3.fromRGB(70 + j * 12, 160 + j * 10, 70),
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
		end
		if i % 3 == 0 then
			Build.part(folder, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(base + Vector3.new(3, 0.6, 0)), Color = Color3.fromRGB(255, 120, 180), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
	end)
	-- Clouds and satellite islets.
	for i = 1, 10 do
		local a = rng:range(0, math.pi * 2)
		local d = rng:range(r + 30, r + 120)
		local cloud = o + Vector3.new(math.cos(a) * d, rng:range(-30, 40), math.sin(a) * d)
		for j = 1, 3 do
			Build.part(folder, { Name = "Cloud", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1) * rng:range(10, 18), CFrame = CFrame.new(cloud + Vector3.new(j * 7, rng:range(-2, 2), 0)), Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic, Transparency = 0.15, CanCollide = false, CastShadow = false })
		end
		if i % 2 == 0 then
			Build.disc(folder, cloud + Vector3.new(0, -12, 0), rng:range(10, 18), 3, Build.rgb(theme.Floor), Enum.Material.Grass, "Islet")
		end
	end
	-- Golden ring markers on the floor.
	Build.disc(folder, o + Vector3.new(0, 0.02, 0), r * 1.2, 0.05, Build.rgb(theme.Accent), Enum.Material.Neon, "RingMark").Transparency = 0.6
end

function themes.NeonGrid(folder, o, r, theme, rng)
	local floorColor = Build.rgb(theme.Floor)
	Build.part(folder, { Name = "Floor", Size = Vector3.new(r * 2 + 8, 4, r * 2 + 8), CFrame = CFrame.new(o + Vector3.new(0, -2, 0)), Color = floorColor, Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 })
	local a1, a2 = Build.rgb(theme.Accent), Build.rgb(theme.Accent2)
	local step = 12
	for i = -math.floor(r / step), math.floor(r / step) do
		local color = if i % 2 == 0 then a1 else a2
		Build.neon(folder, { Name = "GridX", Size = Vector3.new(r * 2 + 8, 0.12, 0.35), CFrame = CFrame.new(o + Vector3.new(0, 0.02, i * step)), Color = color, CanCollide = false, CanQuery = false })
		Build.neon(folder, { Name = "GridZ", Size = Vector3.new(0.35, 0.12, r * 2 + 8), CFrame = CFrame.new(o + Vector3.new(i * step, 0.02, 0)), Color = color, CanCollide = false, CanQuery = false })
	end
	-- Pillars and floating cubes outside the play area.
	ring(16, r + 6, function(i, _, x, z)
		local h = 14 + (i % 4) * 6
		local pillar = Build.part(folder, { Name = "Pylon", Size = Vector3.new(3, h, 3), CFrame = CFrame.new(o + Vector3.new(x, h / 2, z)), Color = Build.rgb(theme.Edge), Material = Enum.Material.Metal })
		local cap = Build.neon(folder, { Name = "PylonGlow", Size = Vector3.new(3.4, 1, 3.4), CFrame = pillar.CFrame * CFrame.new(0, h / 2, 0), Color = if i % 2 == 0 then a1 else a2 })
		Build.light(cap, cap.Color, 20, 2)
	end)
	for i = 1, 14 do
		local a = rng:range(0, math.pi * 2)
		local d = rng:range(r + 20, r + 90)
		Build.neon(folder, {
			Name = "DataCube",
			Size = Vector3.new(1, 1, 1) * rng:range(3, 8),
			CFrame = CFrame.new(o + Vector3.new(math.cos(a) * d, rng:range(10, 50), math.sin(a) * d)) * CFrame.Angles(rng:range(0, 3), rng:range(0, 3), 0),
			Color = if i % 2 == 0 then a1 else a2,
			Transparency = 0.35,
			CanCollide = false,
		})
	end
	-- Sun disc on the horizon (synthwave).
	Build.neon(folder, { Name = "Sun", Shape = Enum.PartType.Ball, Size = Vector3.new(80, 80, 80), CFrame = CFrame.new(o + Vector3.new(0, 30, -r - 260)), Color = Color3.fromRGB(255, 90, 150), CanCollide = false, CastShadow = false })
end

function themes.Volcano(folder, o, r, theme, rng)
	Build.disc(folder, o + Vector3.new(0, -2, 0), r * 2 + 6, 4, Build.rgb(theme.Floor), Enum.Material.Basalt, "Floor")
	-- Glowing cracks across the floor.
	for _ = 1, 14 do
		local a = rng:range(0, math.pi * 2)
		local len = rng:range(10, 30)
		local d = rng:range(8, r - 15)
		Build.neon(folder, { Name = "Crack", Size = Vector3.new(len, 0.1, rng:range(0.4, 1)), CFrame = CFrame.new(o + Vector3.new(math.cos(a) * d, 0.03, math.sin(a) * d)) * CFrame.Angles(0, rng:range(0, math.pi), 0), Color = Build.rgb(theme.Accent), CanCollide = false, CanQuery = false })
	end
	-- Lava sea below and crater walls around.
	local lava = Build.neon(folder, { Name = "Lava", Size = Vector3.new(r * 6, 2, r * 6), CFrame = CFrame.new(o + Vector3.new(0, -26, 0)), Color = Color3.fromRGB(255, 80, 10), CanCollide = false })
	Build.light(lava, Color3.fromRGB(255, 100, 30), 60, 3)
	for i = 1, 4 do
		Build.disc(folder, o + Vector3.new(0, -4 - i * 5, 0), r * 2 + 2 - i * 18, 5.2, Build.rgb(theme.Edge), Enum.Material.Basalt, "Pillar" .. i)
	end
	ring(20, r + 18, function(i, a, x, z)
		local h = rng:range(24, 60)
		Build.part(folder, {
			Name = "CraterWall",
			ClassName = "WedgePart",
			Size = Vector3.new(26, h, 22),
			CFrame = CFrame.lookAt(o + Vector3.new(x, h / 2 - 20, z), o + Vector3.new(0, h / 2 - 20, 0)),
			Color = Build.rgb(theme.Edge):Lerp(Color3.fromRGB(80, 40, 30), (i % 3) / 3),
			Material = Enum.Material.Basalt,
		})
		if i % 4 == 0 then
			-- Lava fall down the crater wall.
			Build.neon(folder, { Name = "LavaFall", Size = Vector3.new(3, h, 1), CFrame = CFrame.lookAt(o + Vector3.new(math.cos(a) * (r + 8), h / 2 - 20, math.sin(a) * (r + 8)), o + Vector3.new(0, h / 2 - 20, 0)), Color = Build.rgb(theme.Accent), CanCollide = false })
		end
	end)
	-- Embers rising.
	local emberSource = Build.part(folder, { Name = "Embers", Size = Vector3.new(r * 2, 1, r * 2), CFrame = CFrame.new(o + Vector3.new(0, -5, 0)), Transparency = 1, CanCollide = false, CanQuery = false })
	local emitter = Build.sparkles(emberSource, Color3.fromRGB(255, 140, 40), 30)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
end

function themes.FrostRing(folder, o, r, theme, rng)
	Build.disc(folder, o + Vector3.new(0, -2, 0), r * 2 + 6, 4, Build.rgb(theme.Floor), Enum.Material.Ice, "Floor")
	Build.disc(folder, o + Vector3.new(0, -0.02, 0), r * 1.4, 0.05, Color3.fromRGB(255, 255, 255), Enum.Material.Snow, "SnowRing")
	for i = 1, 4 do
		Build.disc(folder, o + Vector3.new(0, -4 - i * 5, 0), r * 2 + 2 - i * 20, 5.2, Build.rgb(theme.Edge), Enum.Material.Glacier, "Glacier" .. i)
	end
	-- Ice crystals around the edge.
	ring(18, r + 5, function(i, _, x, z)
		local h = rng:range(8, 22)
		local crystal = Build.part(folder, {
			Name = "Crystal",
			Size = Vector3.new(3, h, 3),
			CFrame = CFrame.new(o + Vector3.new(x, h / 2 - 1, z)) * CFrame.Angles(rng:range(-0.25, 0.25), rng:range(0, 3), rng:range(-0.25, 0.25)),
			Color = Build.rgb(theme.Accent):Lerp(Color3.new(1, 1, 1), (i % 3) * 0.25),
			Material = Enum.Material.Glass,
			Transparency = 0.25,
			Reflectance = 0.2,
		})
		if i % 3 == 0 then
			Build.light(crystal, Build.rgb(theme.Accent), 18, 1.5)
		end
	end)
	-- Snowfall.
	local snow = Build.part(folder, { Name = "Snowfall", Size = Vector3.new(r * 2.5, 1, r * 2.5), CFrame = CFrame.new(o + Vector3.new(0, 60, 0)), Transparency = 1, CanCollide = false, CanQuery = false })
	local emitter = Build.sparkles(snow, Color3.new(1, 1, 1), 40)
	emitter.LightEmission = 0.3
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Lifetime = NumberRange.new(5, 7)
end

function ArenaBuilder.themes()
	return ArenaConfig.Order
end

function ArenaBuilder.build(themeKey, seed, parent)
	local theme = ArenaConfig.Themes[themeKey]
	assert(theme and themes[themeKey], "unknown arena theme " .. tostring(themeKey))
	local origin = Vector3.new(table.unpack(ArenaConfig.Origin))
	local radius = ArenaConfig.Radius
	local rng = Rng.new(seed or 1)
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder:SetAttribute("Theme", themeKey)
	folder.Parent = parent or workspace

	themes[themeKey](folder, origin, radius, theme, rng)
	Build.barrierRing(folder, origin, radius, 40, 32)
	-- Center pad where the ball spawns.
	local pad = Build.disc(folder, origin + Vector3.new(0, 0.05, 0), 10, 0.2, Build.rgb(theme.Accent), Enum.Material.Neon, "BallPad")
	pad.CanCollide = false
	Build.light(pad, pad.Color, 20, 2)

	local spawns = {}
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		local ringRadius = if i % 2 == 0 then radius * 0.62 else radius * 0.45
		local pos = origin + Vector3.new(math.cos(a) * ringRadius, 3, math.sin(a) * ringRadius)
		table.insert(spawns, CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z)))
	end

	local bots = Instance.new("Folder")
	bots.Name = "Bots"
	bots.Parent = folder

	return {
		folder = folder,
		bots = bots,
		theme = themeKey,
		name = theme.Name,
		center = origin,
		radius = radius,
		spawns = spawns,
		killY = origin.Y - 40,
		destroy = function()
			folder:Destroy()
		end,
	}
end

return ArenaBuilder
