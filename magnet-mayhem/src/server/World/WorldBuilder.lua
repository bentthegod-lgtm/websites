--[[
	WorldBuilder - builds the whole map from code: Rustyard (start zone) and Metro Wreck.

	Layout (top view, -Z is north):
	                 North yard / cranes / pipes
	   Warehouse  [ containers ]   SHREDDER   [ containers ]
	   West yard      STATION    spawn  boards    East yard  ===GATE===>  METRO WRECK
	                 Crane corner / rusty cars

	Returns a `world` table the services use:
	  folder, scrapFolder, spawn, sellPad, shredder (machine parts by name), station,
	  gate { barrier, prompt, zoneId }, boards { value, rare }, targets { Shredder, Station,
	  Yard, Gate }, regions { [zoneId] = { {cx, cz, w, h, weight, maxRank, rareBoost} } },
	  heightAt(x, z) -> ground height for spawning.

	Everything decorative is anchored. Collidable: ground, buildings, containers, fences,
	machines. Scrap and effects never collide.
]]

local WorldBuilder = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local at = CFrame.new
local ang = CFrame.Angles

local partCount = 0
local blockers = {} -- { x, z, r }: scrap never spawns inside these
local function block(x, z, r)
	table.insert(blockers, { x = x, z = z, r = r })
end

local function part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.Concrete
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	partCount += 1
	return p
end

local function wedge(parent, name, size, cf, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.Concrete
	p.Anchored = true
	p.Parent = parent
	partCount += 1
	return p
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function surfaceText(target, face, text, color, background, size)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.2
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background or rgb(30, 30, 34)
	label.BackgroundTransparency = if background then 0 else 1
	label.Text = text
	label.TextColor3 = color or rgb(255, 255, 255)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextSize = size or 40
	label.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size or 120
	limit.Parent = label
	return label
end

local function light(parent, kind, props)
	local l = Instance.new(kind)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function ambient(parent, name, position, soundName)
	local p = part(parent, name, Vector3.new(1, 1, 1), at(position), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	p:SetAttribute("Ambient", soundName)
	return p
end

-- Shared prop builders ----------------------------------------------------------------

local CONTAINER_COLORS = { rgb(178, 74, 52), rgb(52, 96, 140), rgb(196, 146, 52), rgb(70, 122, 84), rgb(130, 132, 138) }

local function container(parent, cf, color)
	local m = model(parent, "Container")
	block(cf.Position.X, cf.Position.Z, 11)
	part(m, "Box", Vector3.new(20, 8.5, 8.5), cf, color, M.CorrodedMetal)
	for i = -4, 4 do
		part(m, "Rib", Vector3.new(0.3, 8.6, 8.7), cf * at(i * 2.2, 0, 0), color:Lerp(rgb(0, 0, 0), 0.25), M.Metal, { CanCollide = false })
	end
	part(m, "DoorL", Vector3.new(0.2, 8, 4), cf * at(10.05, 0, 2.1), color:Lerp(rgb(0, 0, 0), 0.15), M.Metal)
	part(m, "DoorR", Vector3.new(0.2, 8, 4), cf * at(10.05, 0, -2.1), color:Lerp(rgb(0, 0, 0), 0.15), M.Metal)
	return m
end

local function scrapHeap(parent, center, radius, height, seed)
	local rng = Random.new(seed)
	local m = model(parent, "ScrapHeap")
	block(center.X, center.Z, radius + 2)
	local palette = { rgb(120, 70, 44), rgb(96, 92, 88), rgb(140, 100, 70), rgb(74, 70, 66), rgb(160, 120, 80) }
	part(m, "Mound", Vector3.new(radius * 2, height * 0.6, radius * 2), at(center + Vector3.new(0, height * 0.3 - 0.5, 0)) * ang(0, rng:NextNumber(0, 6), 0), rgb(92, 78, 64), M.Ground)
	for i = 1, 9 do
		local r = rng:NextNumber(0, radius * 0.8)
		local a = rng:NextNumber(0, math.pi * 2)
		local size = Vector3.new(rng:NextNumber(1.5, 5), rng:NextNumber(0.5, 2.5), rng:NextNumber(1.5, 5))
		local y = height * 0.6 * (1 - r / radius) + size.Y * 0.3
		part(m, "Junk" .. i, size, at(center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)) * ang(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6), rng:NextNumber(-0.6, 0.6)), palette[rng:NextInteger(1, #palette)], if i % 3 == 0 then M.CorrodedMetal else M.Metal, { CanCollide = false })
	end
	return m
end

local function rustyCar(parent, cf, color)
	local m = model(parent, "RustyCar")
	block(cf.Position.X, cf.Position.Z, 6)
	part(m, "Body", Vector3.new(9, 2.4, 4.4), cf * at(0, 1.8, 0), color, M.CorrodedMetal)
	part(m, "Cabin", Vector3.new(4.6, 1.8, 4), cf * at(-0.6, 3.9, 0), color:Lerp(rgb(60, 40, 30), 0.3), M.CorrodedMetal)
	part(m, "Glass", Vector3.new(4.7, 1.3, 4.1), cf * at(-0.6, 4.0, 0), rgb(60, 70, 70), M.Glass, { Transparency = 0.4, CanCollide = false })
	for _, p in ipairs({ { 3, 2.2 }, { 3, -2.2 }, { -3, 2.2 }, { -3, -2.2 } }) do
		part(m, "Wheel", Vector3.new(0.9, 2.2, 2.2), cf * at(p[1], 1.1, p[2]) * ang(0, math.rad(90), 0), rgb(30, 30, 30), M.Rubber, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	return m
end

local function crane(parent, base, yaw)
	local m = model(parent, "Crane")
	block(base.X, base.Z, 8)
	local cf = at(base) * ang(0, yaw, 0)
	local yellow = rgb(222, 170, 44)
	part(m, "Foot", Vector3.new(10, 2, 10), cf * at(0, 1, 0), rgb(80, 80, 84), M.Concrete)
	for _, c in ipairs({ { -1.8, -1.8 }, { 1.8, -1.8 }, { -1.8, 1.8 }, { 1.8, 1.8 } }) do
		part(m, "Leg", Vector3.new(0.6, 58, 0.6), cf * at(c[1], 31, c[2]), yellow, M.Metal)
	end
	for y = 6, 56, 6 do
		part(m, "Brace", Vector3.new(4.2, 0.4, 0.4), cf * at(0, y, -1.8), yellow, M.Metal, { CanCollide = false })
		part(m, "Brace", Vector3.new(4.2, 0.4, 0.4), cf * at(0, y, 1.8), yellow, M.Metal, { CanCollide = false })
	end
	part(m, "Cab", Vector3.new(5, 4, 5), cf * at(0, 60, 0), yellow, M.Metal)
	part(m, "Jib", Vector3.new(46, 1.6, 2.4), cf * at(18, 62.5, 0), yellow, M.Metal)
	part(m, "Counter", Vector3.new(10, 1.6, 2.4), cf * at(-9, 62.5, 0), yellow, M.Metal)
	part(m, "Weight", Vector3.new(4, 4, 3), cf * at(-12, 60, 0), rgb(90, 90, 94), M.Concrete)
	part(m, "Cable", Vector3.new(0.15, 26, 0.15), cf * at(34, 49, 0), rgb(30, 30, 30), M.Metal, { CanCollide = false })
	local hook = part(m, "Magnet", Vector3.new(1.2, 4.8, 4.8), cf * at(34, 35, 0) * ang(0, 0, math.rad(90)), rgb(60, 60, 66), M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	local beacon = part(m, "Beacon", Vector3.new(0.8, 0.8, 0.8), cf * at(40.5, 64, 0), rgb(255, 60, 40), M.Neon, { CanCollide = false })
	light(beacon, "PointLight", { Color = rgb(255, 60, 40), Range = 10, Brightness = 1, Shadows = false })
	return m, hook
end

local function warehouse(parent, cf, w, d, h, color)
	local m = model(parent, "Warehouse")
	block(cf.Position.X, cf.Position.Z, math.max(w, d) / 2 + 3)
	part(m, "Walls", Vector3.new(w, h, d), cf * at(0, h / 2, 0), color, M.CorrodedMetal)
	wedge(m, "RoofA", Vector3.new(w, 5, d / 2), cf * at(0, h + 2.5, d / 4) * ang(0, math.rad(180), 0), color:Lerp(rgb(40, 40, 40), 0.35), M.Metal)
	wedge(m, "RoofB", Vector3.new(w, 5, d / 2), cf * at(0, h + 2.5, -d / 4), color:Lerp(rgb(40, 40, 40), 0.35), M.Metal)
	part(m, "Door", Vector3.new(w * 0.35, h * 0.7, 0.4), cf * at(0, h * 0.35, d / 2 + 0.1), rgb(70, 70, 74), M.Metal)
	for i = -2, 2 do
		part(m, "Window", Vector3.new(w * 0.12, 2.4, 0.3), cf * at(i * w * 0.18, h * 0.82, d / 2 + 0.05), rgb(255, 214, 150), M.Neon, { Transparency = 0.25, CanCollide = false })
	end
	return m
end

local function fenceLine(parent, from, to, height, gapCenter, gapWidth)
	local dir = to - from
	local length = dir.Magnitude
	local unit = dir.Unit
	local spacing = 12
	local n = math.floor(length / spacing)
	for i = 0, n do
		local pos = from + unit * (i * spacing)
		local skip = gapCenter and (pos - gapCenter).Magnitude < gapWidth / 2
		if not skip then
			part(parent, "Post", Vector3.new(0.5, height, 0.5), at(pos + Vector3.new(0, height / 2, 0)), rgb(90, 88, 84), M.Metal)
			if i < n then
				local mid = pos + unit * (spacing / 2)
				if not (gapCenter and (mid - gapCenter).Magnitude < gapWidth / 2 + spacing / 2) then
					part(parent, "Mesh", Vector3.new(spacing, height - 0.5, 0.15), CFrame.lookAt(mid + Vector3.new(0, height / 2, 0), mid + Vector3.new(0, height / 2, 0) + unit) * ang(0, math.rad(90), 0), rgb(150, 150, 146), M.DiamondPlate, { Transparency = 0.55 })
					part(parent, "Rail", Vector3.new(spacing, 0.25, 0.25), CFrame.lookAt(mid + Vector3.new(0, height, 0), mid + Vector3.new(0, height, 0) + unit) * ang(0, math.rad(90), 0), rgb(90, 88, 84), M.Metal, { CanCollide = false })
				end
			end
		end
	end
end

local function lampPost(parent, position, color, range, flicker)
	local m = model(parent, "WorkLight")
	part(m, "Pole", Vector3.new(0.6, 16, 0.6), at(position + Vector3.new(0, 8, 0)), rgb(70, 70, 74), M.Metal)
	part(m, "Arm", Vector3.new(0.4, 0.4, 3), at(position + Vector3.new(0, 15.8, -1.4)), rgb(70, 70, 74), M.Metal)
	local lamp = part(m, "Lamp", Vector3.new(1.6, 0.5, 1.2), at(position + Vector3.new(0, 15.6, -2.8)), color, M.Neon, { CanCollide = false })
	light(lamp, "SpotLight", { Color = color, Range = range or 40, Brightness = 2.2, Angle = 75, Face = Enum.NormalId.Bottom, Shadows = false })
	if flicker then
		lamp:SetAttribute("Flicker", true)
	end
	return m
end

-- Rustyard ----------------------------------------------------------------------------

local function buildRustyard(root, world)
	local z = folder(root, "Rustyard")
	local sand = rgb(176, 150, 116)
	part(z, "Ground", Vector3.new(320, 4, 320), at(0, -2, 0), sand, M.Ground)
	-- Gravel route: spawn -> shredder, spawn -> station, spawn -> gate.
	part(z, "PathNorth", Vector3.new(14, 0.2, 60), at(0, 0.1, -8), rgb(132, 122, 108), M.Slate, { CanCollide = false })
	part(z, "PathEast", Vector3.new(120, 0.2, 12), at(90, 0.1, 30), rgb(132, 122, 108), M.Slate, { CanCollide = false })
	part(z, "PathWest", Vector3.new(30, 0.2, 10), at(-18, 0.1, 22), rgb(132, 122, 108), M.Slate, { CanCollide = false })
	-- Oil stains and dirt patches for variety.
	local rng = Random.new(42)
	for i = 1, 26 do
		local x, zz = rng:NextNumber(-140, 140), rng:NextNumber(-140, 140)
		if math.abs(x) > 18 or math.abs(zz) > 70 then
			part(z, "Patch" .. i, Vector3.new(rng:NextNumber(10, 26), 0.1, rng:NextNumber(8, 22)), at(x, 0.05, zz) * ang(0, rng:NextNumber(0, 3), 0), if i % 3 == 0 then rgb(70, 62, 54) else rgb(150, 126, 96), if i % 3 == 0 then M.Asphalt else M.Mud, { CanCollide = false })
		end
	end
	-- Raised edges: berms around the yard so it isn't a flat plate.
	for _, b in ipairs({ { -150, 0, 6, 320 }, { 0, -150, 320, 6 }, { 0, 150, 320, 6 } }) do
		wedge(z, "Berm", Vector3.new(b[3], 6, b[4]), at(b[1], 3, b[2]), rgb(150, 126, 96), M.Ground)
	end

	-- Spawn pad.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = at(0, 0.5, 40)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = rgb(236, 186, 46)
	spawn.Material = M.DiamondPlate
	spawn.Parent = z
	partCount += 1
	world.spawn = spawn

	-- SHREDDER FACILITY (north of spawn) ------------------------------------------------
	local shred = model(z, "Shredder")
	block(0, -48, 22)
	block(0, -26, 10)
	block(0, 40, 9)
	local base = at(0, 0, -48)
	local yellow, dark = rgb(236, 186, 46), rgb(46, 46, 50)
	part(shred, "Platform", Vector3.new(34, 1.2, 24), base * at(0, 0.6, 0), rgb(110, 110, 112), M.Concrete)
	part(shred, "Body", Vector3.new(20, 13, 14), base * at(0, 7.7, -2), yellow, M.Metal)
	part(shred, "Stripe", Vector3.new(20.2, 1.6, 14.2), base * at(0, 2.4, -2), dark, M.Metal)
	part(shred, "Top", Vector3.new(21, 1.2, 15), base * at(0, 14.8, -2), dark, M.Metal)
	-- Hopper (funnel opening toward the spawn side, +Z).
	wedge(shred, "HopperFront", Vector3.new(18, 6, 5), base * at(0, 18.4, 7.4) * ang(0, math.rad(180), 0), rgb(200, 160, 40), M.Metal)
	wedge(shred, "HopperBack", Vector3.new(18, 6, 5), base * at(0, 18.4, -9.6), rgb(200, 160, 40), M.Metal)
	part(shred, "HopperL", Vector3.new(1, 6, 22), base * at(-9.5, 18.4, -1.1), rgb(200, 160, 40), M.Metal)
	part(shred, "HopperR", Vector3.new(1, 6, 22), base * at(9.5, 18.4, -1.1), rgb(200, 160, 40), M.Metal)
	local mouth = part(shred, "Mouth", Vector3.new(16, 0.4, 10), base * at(0, 15.6, -1), rgb(20, 20, 22), M.Metal, { CanCollide = false })
	world.hopper = mouth
	for i, x in ipairs({ -3.6, 3.6 }) do
		local roller = part(shred, "Roller" .. i, Vector3.new(15, 2.6, 2.6), base * at(0, 16, -1 + x * 0.5), rgb(80, 80, 86), M.DiamondPlate, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		roller:SetAttribute("Roller", if i == 1 then 1 else -1)
	end
	-- Pistons that pump while processing (client animates them).
	for i, x in ipairs({ -12, 12 }) do
		part(shred, "PistonHousing" .. i, Vector3.new(3, 10, 3), base * at(x, 6.2, -2), dark, M.Metal)
		local rod = part(shred, "Piston" .. i, Vector3.new(1.4, 6, 1.4), base * at(x, 12.5, -2), rgb(210, 214, 220), M.Metal, { CanCollide = false })
		rod:SetAttribute("Piston", true)
	end
	-- Smokestack.
	part(shred, "Stack", Vector3.new(3.4, 16, 3.4), base * at(7, 23, -7), rgb(90, 86, 82), M.Metal, { Shape = Enum.PartType.Cylinder, CFrame = base * at(7, 23, -7) * ang(0, 0, math.rad(90)) })
	local stackTop = part(shred, "StackTop", Vector3.new(1, 1, 1), base * at(7, 31.5, -7), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Rate = 3
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 8) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(rgb(150, 140, 130))
	smoke.Parent = stackTop
	-- Warning lights (flash during processing).
	for i, x in ipairs({ -10.4, 10.4 }) do
		local beacon = part(shred, "Warning" .. i, Vector3.new(1.4, 1.4, 1.4), base * at(x, 15.8, 5.2), rgb(255, 120, 30), M.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		beacon:SetAttribute("WarningLight", true)
		light(beacon, "PointLight", { Color = rgb(255, 120, 30), Range = 14, Brightness = 0.6, Shadows = false })
	end
	-- Indicator panel.
	for i = 0, 4 do
		local ind = part(shred, "Indicator" .. i, Vector3.new(0.8, 0.8, 0.2), base * at(-4 + i * 2, 10, 5.05), rgb(60, 200, 90), M.Neon, { CanCollide = false })
		ind:SetAttribute("Indicator", i)
	end
	local sign = part(shred, "Sign", Vector3.new(16, 3.2, 0.4), base * at(0, 11.5, 5.1), dark, M.Metal, { CanCollide = false })
	surfaceText(sign, Enum.NormalId.Front, "SCRAP SHREDDER", yellow)
	-- Output conveyor to the east with moving slats (client scrolls them).
	local belt = part(shred, "Belt", Vector3.new(18, 0.6, 4), base * at(19, 3, -2), rgb(40, 40, 42), M.Rubber)
	for i = 0, 8 do
		local slat = part(shred, "Slat" .. i, Vector3.new(0.4, 0.15, 3.8), belt.CFrame * at(-8 + i * 2, 0.35, 0), rgb(120, 120, 124), M.Metal, { CanCollide = false })
		slat:SetAttribute("Slat", i)
	end
	part(shred, "BeltFrame", Vector3.new(18, 1, 0.4), base * at(19, 2.4, 0.2), yellow, M.Metal)
	part(shred, "BeltFrame2", Vector3.new(18, 1, 0.4), base * at(19, 2.4, -4.2), yellow, M.Metal)
	part(shred, "Bin", Vector3.new(7, 4, 7), base * at(31, 2, -2), rgb(70, 110, 80), M.CorrodedMetal)
	-- Sell pad in front.
	local pad = part(z, "SellPad", Vector3.new(18, 0.4, 12), at(0, 0.2, -26), yellow, M.DiamondPlate, { CanCollide = false })
	for i = -4, 4 do
		part(pad, "Hazard" .. i, Vector3.new(1.2, 0.05, 12.2), at(i * 2, 0.42, -26) * ang(0, 0.6, 0), dark, M.SmoothPlastic, { CanCollide = false, CanQuery = false })
	end
	local padSign = part(z, "PadSign", Vector3.new(10, 2.4, 0.3), at(0, 5.5, -32.6), dark, M.Metal, { CanCollide = false })
	surfaceText(padSign, Enum.NormalId.Back, "STAND HERE TO SELL", yellow)
	local console = part(z, "SellConsole", Vector3.new(2, 3.5, 1.4), at(10.5, 1.75, -26), dark, M.Metal)
	part(console, "Screen", Vector3.new(1.6, 1.2, 0.1), at(10.5, 3.0, -25.25), rgb(255, 200, 60), M.Neon, { CanCollide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Sell Scrap"
	prompt.ObjectText = "Shredder"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	world.sellPad, world.sellPrompt, world.shredder = pad, prompt, shred
	lampPost(z, Vector3.new(-16, 0, -22), rgb(255, 214, 150), 46)
	lampPost(z, Vector3.new(16, 0, -22), rgb(255, 214, 150), 46)
	ambient(z, "ShredderHum", Vector3.new(0, 6, -48), "Machinery")

	-- UPGRADE STATION (west of spawn) -------------------------------------------------
	local station = model(z, "UpgradeStation")
	block(-34, 20, 10)
	block(33, 26, 12)
	local sBase = at(-34, 0, 20) * ang(0, math.rad(-90), 0) -- screen faces east, toward the spawn
	part(station, "Base", Vector3.new(14, 1, 10), sBase * at(0, 0.5, 0), rgb(70, 72, 78), M.DiamondPlate)
	part(station, "Kiosk", Vector3.new(7, 8, 3), sBase * at(0, 5, -2.5), rgb(46, 46, 50), M.Metal)
	local screen = part(station, "Screen", Vector3.new(6, 3.6, 0.2), sBase * at(0, 6.2, -0.95), rgb(20, 24, 30), M.SmoothPlastic, { CanCollide = false })
	surfaceText(screen, Enum.NormalId.Front, "MAGNET UPGRADES", rgb(255, 200, 60), rgb(20, 24, 30))
	for i, x in ipairs({ -3.8, 3.8 }) do
		local trim = part(station, "Trim" .. i, Vector3.new(0.4, 8, 0.4), sBase * at(x, 5, -1), rgb(255, 170, 40), M.Neon, { CanCollide = false })
		trim:SetAttribute("StationTrim", true)
	end
	part(station, "Canopy", Vector3.new(12, 0.6, 8), sBase * at(0, 10.5, -0.5), rgb(236, 186, 46), M.Metal)
	-- A demo magnet coil on the bench.
	part(station, "Bench", Vector3.new(4, 2.4, 2), sBase * at(4.8, 1.2, 1.5), rgb(110, 84, 60), M.Wood)
	part(station, "CoilDemo", Vector3.new(1.6, 1.6, 1.6), sBase * at(4.8, 3.2, 1.5) * ang(0, 0, math.rad(90)), rgb(196, 112, 60), M.Metal, { Shape = Enum.PartType.Cylinder })
	local sPrompt = Instance.new("ProximityPrompt")
	sPrompt.Name = "UpgradePrompt"
	sPrompt.ActionText = "Upgrades"
	sPrompt.ObjectText = "Magnet Station"
	sPrompt.KeyboardKeyCode = Enum.KeyCode.E
	sPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	sPrompt.MaxActivationDistance = 12
	sPrompt.RequiresLineOfSight = false
	sPrompt.Parent = screen
	world.station, world.stationPrompt = station, sPrompt
	lampPost(z, Vector3.new(-26, 0, 10), rgb(255, 230, 190), 36)

	-- Leaderboard boards (east of spawn).
	world.boards = {}
	for i, info in ipairs({ { key = "value", title = "TOP SCRAP VALUE", x = 26 }, { key = "rare", title = "RARE DISCOVERIES", x = 40 } }) do
		local boardPos = Vector3.new(info.x, 8, 26)
		local board = part(z, "Board" .. i, Vector3.new(12, 14, 0.6), CFrame.lookAt(boardPos, Vector3.new(0, 8, 46)), rgb(36, 36, 40), M.Metal) -- faces the spawn
		part(z, "BoardLeg" .. i, Vector3.new(0.6, 8, 0.6), at(info.x, 1, 26.3), rgb(70, 70, 74), M.Metal)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0.15
		gui.Parent = board
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0.14, 0)
		title.BackgroundTransparency = 1
		title.Text = info.title
		title.TextColor3 = rgb(255, 200, 60)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.Parent = gui
		local rows = {}
		for r = 1, 10 do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(0.92, 0, 0.078, 0)
			row.Position = UDim2.new(0.04, 0, 0.15 + (r - 1) * 0.084, 0)
			row.BackgroundTransparency = 1
			row.Text = string.format("%d. ---", r)
			row.TextColor3 = rgb(235, 235, 235)
			row.Font = Enum.Font.GothamMedium
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Parent = gui
			rows[r] = row
		end
		world.boards[info.key] = { part = board, rows = rows }
	end

	-- Containers, warehouses, cranes, heaps, cars --------------------------------------
	local containers = folder(z, "Containers")
	local cIndex = 0
	local function stack(x, zz, yaw, levels)
		for l = 0, levels - 1 do
			cIndex += 1
			container(containers, at(x, 4.25 + l * 8.5, zz) * ang(0, yaw, 0), CONTAINER_COLORS[(cIndex % #CONTAINER_COLORS) + 1])
		end
	end
	stack(-40, -48, 0, 2)
	stack(40, -50, 0, 1)
	stack(-60, -66, math.rad(90), 1)
	stack(62, -72, math.rad(90), 2)
	stack(-118, 0, math.rad(90), 2)
	stack(-118, 24, math.rad(90), 1)
	stack(120, -40, math.rad(90), 2)
	stack(118, 74, 0, 1)
	-- The container maze (a secret stash with better odds sits inside).
	stack(-82, -30, 0, 1)
	stack(-82, -52, 0, 1)
	stack(-104, -41, math.rad(90), 1)
	stack(-66, -24, math.rad(90), 1)
	local stashSign = part(z, "StashSign", Vector3.new(3, 1.2, 0.2), at(-72, 2, -31) * ang(0, math.rad(-90), 0), rgb(40, 40, 44), M.Metal, { CanCollide = false })
	surfaceText(stashSign, Enum.NormalId.Front, "KEEP OUT", rgb(220, 60, 50))

	warehouse(z, at(-118, 0, 82) * ang(0, math.rad(90), 0), 40, 26, 16, rgb(118, 96, 80))
	warehouse(z, at(70, 0, -124), 50, 24, 18, rgb(98, 104, 112))
	local _, hookA = crane(z, Vector3.new(-116, 0, -118), math.rad(30))
	local _, hookB = crane(z, Vector3.new(118, 0, 118), math.rad(200))
	world.craneMagnets = { hookA, hookB }

	local heaps = folder(z, "Heaps")
	local heapSpots = { { -70, 60, 10, 6 }, { 70, -10, 9, 5 }, { -30, -100, 14, 8 }, { 40, -96, 10, 6 }, { 96, 30, 8, 5 }, { -100, -90, 12, 7 }, { 20, 110, 11, 6 }, { -60, 120, 9, 5 }, { 130, -110, 12, 7 } }
	for i, h in ipairs(heapSpots) do
		scrapHeap(heaps, Vector3.new(h[1], 0, h[2]), h[3], h[4], i * 17)
	end
	local cars = folder(z, "Cars")
	for i, c in ipairs({ { 92, 100, 0.4 }, { 104, 96, 2.2 }, { -46, 108, 1.2 }, { 60, 64, 2.9 }, { -128, -64, 0.2 }, { 136, 10, 1.6 } }) do
		rustyCar(cars, at(c[1], 0, c[2]) * ang(0, c[3], 0), CONTAINER_COLORS[(i % #CONTAINER_COLORS) + 1]:Lerp(rgb(120, 70, 40), 0.45))
	end
	-- Big pipes along the north edge with cable runs.
	for i = 0, 3 do
		part(z, "Pipe" .. i, Vector3.new(70, 3.2, 3.2), at(-105 + i * 70, 6, -142) * ang(0, 0, 0), rgb(120, 88, 64), M.CorrodedMetal, { Shape = Enum.PartType.Cylinder })
		part(z, "PipeStand" .. i, Vector3.new(2, 6, 2), at(-105 + i * 70, 3, -142), rgb(80, 80, 84), M.Metal)
	end
	for i = 0, 5 do
		part(z, "CablePole" .. i, Vector3.new(0.8, 18, 0.8), at(-140 + i * 56, 9, 140), rgb(96, 76, 56), M.Wood)
	end
	for i = 0, 4 do
		part(z, "Cable" .. i, Vector3.new(56, 0.15, 0.15), at(-112 + i * 56, 16.5, 140), rgb(30, 30, 30), M.Metal, { CanCollide = false })
	end

	-- Perimeter fence (gap for the gate on the east side).
	local fence = folder(z, "Fence")
	fenceLine(fence, Vector3.new(-150, 0, -150), Vector3.new(150, 0, -150), 9)
	fenceLine(fence, Vector3.new(-150, 0, 150), Vector3.new(150, 0, 150), 9)
	fenceLine(fence, Vector3.new(-150, 0, -150), Vector3.new(-150, 0, 150), 9)
	fenceLine(fence, Vector3.new(150, 0, -150), Vector3.new(150, 0, 150), 9, Vector3.new(150, 0, 0), 26)
	-- Invisible walls so nobody climbs out over the fence.
	for _, w in ipairs({ { 0, -151, 304, 2 }, { 0, 151, 304, 2 }, { -151, 0, 2, 304 } }) do
		part(fence, "Wall", Vector3.new(w[3], 40, w[4]), at(w[1], 20, w[2]), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	end
	for _, zz in ipairs({ -76, 76 }) do
		part(fence, "WallE", Vector3.new(2, 40, 140), at(151, 20, zz + (if zz < 0 then -6 else 6)), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	end

	-- Distant industrial silhouettes.
	local far = folder(z, "Skyline")
	local frng = Random.new(7)
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2 + 0.2
		local d = frng:NextNumber(330, 420)
		local h = frng:NextNumber(30, 90)
		local x, zz = math.cos(a) * d, math.sin(a) * d
		if x < 150 then -- keep the Metro side clear
			part(far, "Factory" .. i, Vector3.new(frng:NextNumber(30, 60), h, frng:NextNumber(20, 40)), at(x, h / 2 - 4, zz) * ang(0, a, 0), rgb(84, 76, 72), M.Concrete, { CanCollide = false, CastShadow = false })
			if i % 3 == 0 then
				part(far, "Chimney" .. i, Vector3.new(5, h + 40, 5), at(x + 8, (h + 40) / 2 - 4, zz), rgb(96, 84, 78), M.Concrete, { CanCollide = false, CastShadow = false })
			end
		end
	end

	-- Work lights around the yard.
	for _, p in ipairs({ { -70, 30 }, { 70, 10 }, { -20, -80 }, { 90, -90 }, { -100, 110 } }) do
		lampPost(z, Vector3.new(p[1], 0, p[2]), rgb(255, 205, 140), 44)
	end
	-- Ambient emitters.
	ambient(z, "WindA", Vector3.new(-100, 10, -60), "Wind")
	ambient(z, "WindB", Vector3.new(100, 10, 80), "Wind")
	ambient(z, "CreakA", Vector3.new(-80, 6, -40), "Creak")
	ambient(z, "CreakB", Vector3.new(118, 6, 74), "Creak")
	ambient(z, "Clang", Vector3.new(70, 10, -124), "DistantClang")
	ambient(z, "BirdsA", Vector3.new(0, 20, 120), "Birds")

	world.targets.Shredder = Vector3.new(0, 0, -26)
	world.targets.Station = Vector3.new(-31, 0, 20)
	world.targets.Yard = Vector3.new(-60, 0, -70)
	world.targets.Gate = Vector3.new(146, 0, 0)

	world.regions.Rustyard = {
		{ cx = 0, cz = 66, w = 70, h = 34, weight = 2.5, maxRank = 1 }, -- right next to spawn
		{ cx = -24, cz = 40, w = 24, h = 26, weight = 0.8, maxRank = 1 },
		{ cx = -78, cz = 30, w = 70, h = 120, weight = 3 },
		{ cx = 72, cz = 40, w = 90, h = 70, weight = 3 },
		{ cx = -20, cz = -104, w = 160, h = 60, weight = 3, rareBoost = 1.4 },
		{ cx = 96, cz = 108, w = 70, h = 50, weight = 1.5, rareBoost = 1.6 },
		{ cx = 92, cz = -96, w = 60, h = 70, weight = 1.5, rareBoost = 1.3 },
		{ cx = -85, cz = -41, w = 18, h = 16, weight = 0.4, rareBoost = 5 }, -- container-maze stash
	}
end

-- Gate ---------------------------------------------------------------------------------

local function buildGate(root, world)
	local g = model(root, "MetroGate")
	local x = 157
	local steel = rgb(70, 72, 78)
	part(g, "Road", Vector3.new(20, 0.3, 26), at(x, 0.15, 0), rgb(58, 58, 62), M.Asphalt)
	part(g, "PillarN", Vector3.new(4, 24, 4), at(x, 12, -14), steel, M.Metal)
	part(g, "PillarS", Vector3.new(4, 24, 4), at(x, 12, 14), steel, M.Metal)
	part(g, "Arch", Vector3.new(5, 4, 34), at(x, 26, 0), rgb(236, 186, 46), M.Metal)
	local sign = part(g, "Sign", Vector3.new(0.4, 3.4, 22), at(x - 2.7, 26, 0), rgb(30, 30, 34), M.Metal)
	surfaceText(sign, Enum.NormalId.Left, "METRO WRECK", rgb(150, 190, 255))
	local barrier = part(g, "Barrier", Vector3.new(1, 22, 24), at(x, 11, 0), rgb(110, 160, 255), M.ForceField, { Transparency = 0.35 })
	barrier:SetAttribute("Zone", "MetroWreck")
	-- Side walls between the gate and the Metro buildings.
	part(g, "WallN", Vector3.new(16, 40, 136), at(x, 20, -82), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	part(g, "WallS", Vector3.new(16, 40, 136), at(x, 20, 82), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	local console = part(g, "Console", Vector3.new(2.4, 4, 2), at(x - 8, 2, -9), rgb(46, 46, 50), M.Metal)
	local screen = part(g, "Screen", Vector3.new(0.1, 1.6, 1.8), at(x - 9.25, 3.2, -9), rgb(110, 160, 255), M.Neon, { CanCollide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatePrompt"
	prompt.ActionText = "Unlock"
	prompt.ObjectText = "Metro Wreck"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen
	local preview = part(g, "Preview", Vector3.new(0.3, 7, 10), at(x - 9, 9, 18), rgb(20, 24, 30), M.SmoothPlastic, { CanCollide = false })
	surfaceText(preview, Enum.NormalId.Left, "NEXT ZONE\nMETRO WRECK\nCar doors, traffic lights, ATMs", rgb(200, 220, 255), rgb(20, 24, 30))
	world.gate = { barrier = barrier, prompt = prompt, zoneId = "MetroWreck", console = console }
	-- Teleport target just inside each side of the gate.
	world.gate.inside = Vector3.new(x + 16, 3, 0)
	world.gate.outside = Vector3.new(x - 16, 3, 0)
end

-- Metro Wreck --------------------------------------------------------------------------

local function facade(parent, cf, w, h, color, seed)
	local m = model(parent, "Building")
	block(cf.Position.X, cf.Position.Z, math.max(w, 16) / 2 + 2)
	part(m, "Block", Vector3.new(w, h, 16), cf * at(0, h / 2, 0), color, M.Concrete)
	local rng = Random.new(seed)
	for row = 1, math.floor(h / 7) - 1 do
		for col = 0, math.floor(w / 6) - 1 do
			local lit = rng:NextNumber() < 0.28
			part(m, "Window", Vector3.new(3, 3.4, 0.3), cf * at(-w / 2 + 3.5 + col * 6, row * 7, -8.1), if lit then rgb(255, 210, 140) else rgb(40, 46, 60), if lit then M.Neon else M.Glass, { CanCollide = false, Transparency = if lit then 0.2 else 0.1 })
		end
	end
	part(m, "Roof", Vector3.new(w + 1, 1, 17), cf * at(0, h + 0.5, 0), color:Lerp(rgb(20, 20, 20), 0.4), M.Concrete)
	return m
end

local function buildMetro(root, world)
	local z = folder(root, "MetroWreck")
	local cx = 305
	part(z, "Ground", Vector3.new(290, 4, 270), at(cx, -2, 0), rgb(84, 84, 88), M.Asphalt)
	part(z, "Avenue", Vector3.new(280, 0.2, 34), at(cx, 0.1, 0), rgb(52, 52, 56), M.Asphalt, { CanCollide = false })
	part(z, "CrossStreet", Vector3.new(30, 0.2, 260), at(cx + 20, 0.1, 0), rgb(52, 52, 56), M.Asphalt, { CanCollide = false })
	for i = 0, 12 do
		part(z, "Lane" .. i, Vector3.new(6, 0.05, 0.6), at(170 + i * 22, 0.22, 0), rgb(236, 200, 60), M.SmoothPlastic, { CanCollide = false })
	end
	for _, zz in ipairs({ -21, 21 }) do
		part(z, "Sidewalk", Vector3.new(280, 0.6, 8), at(cx, 0.3, zz), rgb(150, 148, 142), M.Concrete)
	end
	-- Buildings around the edge (they are the zone's walls).
	local colors = { rgb(120, 92, 80), rgb(90, 96, 110), rgb(140, 120, 96), rgb(70, 74, 86), rgb(110, 80, 70) }
	local b = 0
	for x = 185, 430, 34 do
		b += 1
		-- Facades are built with their windows on local -Z; turn each row to face the streets.
		facade(z, at(x, 0, -126) * ang(0, math.rad(180), 0), 30, 30 + (b % 3) * 12, colors[(b % #colors) + 1], b)
		facade(z, at(x, 0, 126), 30, 26 + (b % 4) * 10, colors[((b + 2) % #colors) + 1], b + 50)
	end
	for zz = -100, 100, 40 do
		b += 1
		if math.abs(zz) > 30 then
			facade(z, at(446, 0, zz) * ang(0, math.rad(90), 0), 36, 34 + (b % 3) * 10, colors[(b % #colors) + 1], b + 100)
			facade(z, at(168, 0, zz) * ang(0, math.rad(-90), 0), 36, 22, colors[((b + 1) % #colors) + 1], b + 150)
		end
	end
	part(z, "EastWall", Vector3.new(2, 60, 270), at(452, 30, 0), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	part(z, "NorthWall", Vector3.new(290, 60, 2), at(cx, 30, -136), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	part(z, "SouthWall", Vector3.new(290, 60, 2), at(cx, 30, 136), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	-- Wrecked cars, barriers, bus stop, hydrants.
	local wrecks = folder(z, "Wrecks")
	for i, c in ipairs({ { 200, -8, 0.3 }, { 236, 9, 2.8 }, { 270, -4, 1.4 }, { 340, 10, 0.1 }, { 380, -10, 2.2 }, { 410, 6, 1.0 }, { 318, -60, 1.6 }, { 330, 70, 0.6 } }) do
		rustyCar(wrecks, at(c[1], 0, c[2]) * ang(0.05 * (i % 3), c[3], 0), colors[(i % #colors) + 1]:Lerp(rgb(150, 40, 40), 0.25))
	end
	for i, p in ipairs({ { 250, -30 }, { 290, 30 }, { 360, -30 }, { 400, 30 } }) do
		part(wrecks, "Barrier" .. i, Vector3.new(8, 1.6, 1), at(p[1], 0.8, p[2]) * ang(0, i * 0.4, 0.1), rgb(236, 120, 40), M.SmoothPlastic)
		part(wrecks, "Hydrant" .. i, Vector3.new(1, 2, 1), at(p[1] + 6, 1, p[2] + (if p[2] < 0 then 3 else -3)), rgb(196, 44, 40), M.Metal, { Shape = Enum.PartType.Cylinder, CFrame = at(p[1] + 6, 1.2, p[2] + (if p[2] < 0 then 3 else -3)) * ang(0, 0, math.rad(90)) })
	end
	local stop = model(z, "BusStop")
	part(stop, "Roof", Vector3.new(12, 0.4, 5), at(300, 8, -28), rgb(60, 64, 70), M.Metal)
	part(stop, "Glass", Vector3.new(12, 6, 0.2), at(300, 4, -30.4), rgb(160, 190, 210), M.Glass, { Transparency = 0.6 })
	-- Streetlights: some work, some flicker, some are dead.
	for i, x in ipairs({ 190, 230, 270, 310, 350, 390, 430 }) do
		local side = if i % 2 == 0 then -26 else 26
		local m = lampPost(z, Vector3.new(x, 0, side), rgb(255, 220, 170), 46, i % 3 == 1)
		if i % 4 == 0 then
			local lamp = m:FindFirstChild("Lamp")
			lamp.Color = rgb(40, 40, 40)
			lamp.Material = M.Glass
			lamp:FindFirstChildOfClass("SpotLight"):Destroy()
		end
	end
	ambient(z, "UrbanWindA", Vector3.new(250, 12, 0), "UrbanWind")
	ambient(z, "UrbanWindB", Vector3.new(390, 12, -40), "UrbanWind")
	ambient(z, "HumA", Vector3.new(330, 6, 60), "Hum")
	world.regions.MetroWreck = {
		{ cx = 300, cz = 0, w = 250, h = 30, weight = 3 },
		{ cx = 325, cz = -70, w = 26, h = 100, weight = 1.5 },
		{ cx = 325, cz = 70, w = 26, h = 100, weight = 1.5 },
		{ cx = 240, cz = -70, w = 90, h = 70, weight = 1.2, rareBoost = 1.3 },
		{ cx = 395, cz = 70, w = 80, h = 70, weight = 1.2, rareBoost = 1.5 },
	}
end

function WorldBuilder.build()
	partCount = 0
	blockers = {}
	local existing = workspace:FindFirstChild("MagnetMayhemWorld")
	if existing then
		existing:Destroy()
	end
	local root = folder(workspace, "MagnetMayhemWorld")
	local world = { folder = root, targets = {}, regions = {} }
	part(root, "Outskirts", Vector3.new(2000, 2, 2000), at(150, -1.4, 0), rgb(150, 128, 100), M.Ground, { CanCollide = false })
	buildRustyard(root, world)
	buildGate(root, world)
	buildMetro(root, world)
	world.scrapFolder = folder(root, "Scrap")
	world.partCount = partCount
	world.blockers = blockers
	function world.heightAt(_x, _z)
		return 0
	end
	return world
end

return WorldBuilder
