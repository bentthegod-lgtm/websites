--[[
	WorldBuilder - builds the whole map from parts: grass field, the red carpet with its
	portal and exit, 8 bases (walls, laser door, lock button, 20 pedestals with collect
	pads, owner sign), the global leaderboard and the events board.

	Returns a `world` table with references the services need (no game logic here).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Layout)

local WorldBuilder = {}

local P = GameConfig.Plot
local C = GameConfig.Carpet

local PLOT_COLORS = {
	Color3.fromRGB(255, 140, 160),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(150, 230, 120),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(190, 140, 255),
	Color3.fromRGB(255, 160, 90),
	Color3.fromRGB(100, 230, 210),
	Color3.fromRGB(250, 120, 220),
}
WorldBuilder.PlotColors = PLOT_COLORS

local function part(props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "ClassName" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end
WorldBuilder.part = part

local function vcyl(props, height, diameter)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = props.CFrame * CFrame.Angles(0, 0, math.pi / 2)
	return part(props)
end

local function textLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end
WorldBuilder.textLabel = textLabel

local function billboard(parent, size, offset, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 120
	gui.Parent = parent
	return gui
end
WorldBuilder.billboard = billboard

local function surface(parent, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = parent
	return gui
end

---------------------------------------------------------------------------------------------
-- Global scenery
---------------------------------------------------------------------------------------------

local function buildTree(folder, position, scale)
	local trunkH = 7 * scale
	vcyl({ Name = "Trunk", CFrame = CFrame.new(position + Vector3.new(0, trunkH / 2, 0)), Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood, Parent = folder }, trunkH, 1.6 * scale)
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1) * 8 * scale, CFrame = CFrame.new(position + Vector3.new(0, trunkH + 2 * scale, 0)), Color = Color3.fromRGB(70, 170, 80), Material = Enum.Material.Grass, Parent = folder })
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1) * 5.5 * scale, CFrame = CFrame.new(position + Vector3.new(1.8 * scale, trunkH + 4.5 * scale, 0.8 * scale)), Color = Color3.fromRGB(90, 190, 90), Material = Enum.Material.Grass, Parent = folder })
end

local function buildCarpet(folder)
	local length = C.EndZ - C.StartZ
	local midZ = (C.StartZ + C.EndZ) / 2
	part({ Name = "Carpet", Size = Vector3.new(C.Width, 0.3, length), CFrame = CFrame.new(0, 0.15, midZ), Color = Color3.fromRGB(206, 32, 48), Material = Enum.Material.Fabric, Parent = folder })
	for _, x in ipairs({ -1, 1 }) do
		part({ Name = "CarpetEdge", Size = Vector3.new(0.7, 0.4, length), CFrame = CFrame.new(x * (C.Width / 2 + 0.35), 0.2, midZ), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Metal, Parent = folder })
		-- walkway between the carpet and the bases
		part({ Name = "Walkway", Size = Vector3.new(8, 0.1, length + 30), CFrame = CFrame.new(x * (C.Width / 2 + 4.7), 0.05, midZ), Color = Color3.fromRGB(236, 222, 196), Parent = folder })
	end
	-- chevrons pointing the way the Blobbies walk
	for z = C.StartZ + 10, C.EndZ - 10, 20 do
		for _, x in ipairs({ -1, 1 }) do
			part({ Name = "Chevron", Size = Vector3.new(4.2, 0.32, 0.8), CFrame = CFrame.new(x * 1.6, 0.17, z) * CFrame.Angles(0, x * math.rad(35), 0), Color = Color3.fromRGB(255, 90, 100), Material = Enum.Material.Fabric, Parent = folder })
		end
	end
	-- lamp posts
	for z = C.StartZ + 20, C.EndZ - 20, 44 do
		for _, x in ipairs({ -1, 1 }) do
			local base = Vector3.new(x * (C.Width / 2 + 2), 0, z)
			vcyl({ Name = "LampPost", CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0)), Color = Color3.fromRGB(50, 50, 60), Material = Enum.Material.Metal, Parent = folder }, 9, 0.5)
			local bulb = part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1) * 1.5, CFrame = CFrame.new(base + Vector3.new(0, 9.4, 0)), Color = Color3.fromRGB(255, 236, 170), Material = Enum.Material.Neon, CanCollide = false, Parent = folder })
			local light = Instance.new("PointLight")
			light.Range = 16
			light.Brightness = 0.8
			light.Color = Color3.fromRGB(255, 226, 170)
			light.Parent = bulb
		end
	end
end

local function buildPortal(folder)
	local center = Vector3.new(0, 9, C.StartZ - 2)
	local segments = 18
	local radius = 9
	for i = 0, segments - 1 do
		local a = i * 2 * math.pi / segments
		local pos = center + Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)
		part({
			Name = "PortalRing",
			Size = Vector3.new(3.4, 1.4, 1.4),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, a + math.pi / 2),
			Color = if i % 2 == 0 then Color3.fromRGB(190, 90, 255) else Color3.fromRGB(80, 220, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})
	end
	local swirl = part({ Name = "PortalSwirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 17, 17), CFrame = CFrame.new(center) * CFrame.Angles(0, math.pi / 2, 0), Color = Color3.fromRGB(140, 60, 220), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = folder })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 140, 255), Color3.fromRGB(100, 230, 255))
	emitter.LightEmission = 1
	emitter.Rate = 25
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = swirl
	part({ Name = "PortalBase", Size = Vector3.new(26, 1, 8), CFrame = CFrame.new(0, 0.5, C.StartZ - 2), Color = Color3.fromRGB(60, 50, 90), Material = Enum.Material.Slate, Parent = folder })
	local sign = part({ Name = "PortalSign", Size = Vector3.new(20, 3.4, 0.6), CFrame = CFrame.lookAt(Vector3.new(0, 21, C.StartZ - 2), Vector3.new(0, 21, 0)), Color = Color3.fromRGB(40, 30, 70), Parent = folder })
	textLabel(surface(sign), { Size = UDim2.fromScale(1, 1), Text = "BLOBBY PORTAL", TextColor3 = Color3.fromRGB(255, 230, 120) })

	-- exit hole at the far end
	vcyl({ Name = "ExitHole", CFrame = CFrame.new(0, 0.2, C.EndZ + 4), Color = Color3.fromRGB(20, 16, 28), CanCollide = false, Parent = folder }, 0.42, 16)
	local arch = part({ Name = "ExitSign", Size = Vector3.new(18, 3, 0.6), CFrame = CFrame.lookAt(Vector3.new(0, 12, C.EndZ + 6), Vector3.new(0, 12, 0)), Color = Color3.fromRGB(40, 30, 70), Parent = folder })
	textLabel(surface(arch), { Size = UDim2.fromScale(1, 1), Text = "BYE BYE BLOBBIES", TextColor3 = Color3.fromRGB(255, 160, 200) })
	for _, x in ipairs({ -9, 9 }) do
		part({ Name = "ExitPillar", Size = Vector3.new(1.4, 13.5, 1.4), CFrame = CFrame.new(x, 6.75, C.EndZ + 6), Color = Color3.fromRGB(60, 50, 90), Parent = folder })
	end
	return center
end

-- A board with a title and a vertical list of rows. Returns { part, title, rows = {TextLabel} }
local function buildBoard(folder, name, position, title, rows, accent)
	local board = part({ Name = name, Size = Vector3.new(18, 22, 1), CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0)), Color = Color3.fromRGB(34, 28, 56), Parent = folder })
	part({ Name = name .. "Trim", Size = Vector3.new(19, 23, 0.6), CFrame = board.CFrame * CFrame.new(0, 0, 0.5), Color = accent, Material = Enum.Material.Neon, Parent = folder })
	for _, x in ipairs({ -7, 7 }) do
		part({ Name = name .. "Leg", Size = Vector3.new(1, position.Y - 11, 1), CFrame = CFrame.new(board.CFrame * Vector3.new(x, 0, 0.8) * Vector3.new(1, 0, 1) + Vector3.new(0, (position.Y - 11) / 2, 0)), Color = Color3.fromRGB(50, 44, 70), Parent = folder })
	end
	local gui = surface(board)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local titleLabel = textLabel(frame, { Size = UDim2.fromScale(1, 0.12), Text = title, TextColor3 = accent })
	local out = { part = board, title = titleLabel, rows = {} }
	for i = 1, rows do
		out.rows[i] = textLabel(frame, {
			Name = "Row" .. i,
			Position = UDim2.fromScale(0.04, 0.13 + (i - 1) * (0.85 / rows)),
			Size = UDim2.fromScale(0.92, 0.85 / rows * 0.9),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if i <= 3 then Color3.fromRGB(255, 226, 120) else Color3.new(1, 1, 1),
		})
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Plots
---------------------------------------------------------------------------------------------

local function buildPedestal(folder, plotCf, slot, color)
	local lx, lz = Layout.pedestalLocal(slot, P)
	local floorY = 1
	local h = P.PedestalHeight
	local base = plotCf * CFrame.new(lx, floorY, lz)
	local model = Instance.new("Model")
	model.Name = "Pedestal" .. slot
	model.Parent = folder
	local column = vcyl({ Name = "Column", CFrame = base * CFrame.new(0, (h - 0.4) / 2, 0), Color = Color3.fromRGB(245, 242, 236), Material = Enum.Material.Marble, Parent = model }, h - 0.4, 4.6)
	local top = vcyl({ Name = "Top", CFrame = base * CFrame.new(0, h - 0.2, 0), Color = color, Parent = model }, 0.4, 5.4)
	local ring = vcyl({ Name = "Ring", CFrame = base * CFrame.new(0, h - 0.5, 0), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Neon, CanCollide = false, Parent = model }, 0.25, 5.7)
	local pad = part({ Name = "CollectPad", Size = Vector3.new(4.4, 0.3, 2.6), CFrame = base * CFrame.new(0, 0.15, -4), Color = Color3.fromRGB(70, 200, 90), Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
	local cashGui = billboard(pad, UDim2.new(5, 0, 1.4, 0), Vector3.new(0, 1.4, 0), 70)
	cashGui.Name = "CashGui"
	local cashLabel = textLabel(cashGui, { Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = Color3.fromRGB(120, 255, 120) })
	local lockedGui = billboard(column, UDim2.new(4, 0, 1, 0), Vector3.new(0, 1.6, 0), 60)
	lockedGui.Name = "LockedGui"
	textLabel(lockedGui, { Size = UDim2.fromScale(1, 1), Text = "LOCKED SLOT", TextColor3 = Color3.fromRGB(200, 200, 210) })
	lockedGui.Enabled = false
	return {
		slot = slot,
		model = model,
		column = column,
		top = top,
		ring = ring,
		pad = pad,
		cashLabel = cashLabel,
		lockedGui = lockedGui,
		-- where a Blobby's feet go, facing the entrance
		standCFrame = base * CFrame.new(0, h, 0),
		local_ = Vector3.new(lx, 0, lz),
	}
end

local function buildPlot(root, index)
	local x, z, yaw = Layout.plotPosition(index, P)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local color = PLOT_COLORS[index]
	local folder = Instance.new("Model")
	folder.Name = "Plot" .. index
	folder.Parent = root
	local W, D, H = P.Width, P.Depth, P.WallHeight
	local front = -D / 2
	local wallColor = Color3.fromRGB(252, 248, 240)

	part({ Name = "Floor", Size = Vector3.new(W, 1, D), CFrame = cf * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(236, 232, 226), Parent = folder })
	part({ Name = "FloorInlay", Size = Vector3.new(W - 6, 0.06, D - 6), CFrame = cf * CFrame.new(0, 1.03, 1), Color = color, Transparency = 0.45, Parent = folder })

	local function wall(name, size, offset)
		local w = part({ Name = name, Size = size, CFrame = cf * CFrame.new(offset), Color = wallColor, Parent = folder })
		part({ Name = name .. "Trim", Size = size + Vector3.new(0.4, 0, 0.4) * Vector3.new(1, 0, 1) + Vector3.new(0, 0.8 - size.Y, 0), CFrame = cf * CFrame.new(offset + Vector3.new(0, size.Y / 2 + 0.4, 0)), Color = color, Parent = folder })
		part({ Name = name .. "Stripe", Size = size + Vector3.new(0.12, 0, 0.12) * Vector3.new(1, 0, 1) + Vector3.new(0, 1.2 - size.Y, 0), CFrame = cf * CFrame.new(offset + Vector3.new(0, -size.Y / 2 + 3, 0)), Color = color, Parent = folder })
		return w
	end
	wall("BackWall", Vector3.new(W, H, 1.2), Vector3.new(0, 1 + H / 2, D / 2))
	wall("LeftWall", Vector3.new(1.2, H, D), Vector3.new(-W / 2, 1 + H / 2, 0))
	wall("RightWall", Vector3.new(1.2, H, D), Vector3.new(W / 2, 1 + H / 2, 0))
	local seg = (W - P.EntranceWidth) / 2
	for _, sx in ipairs({ -1, 1 }) do
		wall("FrontWall", Vector3.new(seg, H, 1.2), Vector3.new(sx * (P.EntranceWidth / 2 + seg / 2), 1 + H / 2, front))
	end

	-- Laser door
	local strips, bars = {}, {}
	for _, sx in ipairs({ -1, 1 }) do
		local px = sx * (P.EntranceWidth / 2 + 0.6)
		part({ Name = "DoorPost", Size = Vector3.new(1.6, H + 1.5, 1.8), CFrame = cf * CFrame.new(px, 1 + (H + 1.5) / 2, front), Color = Color3.fromRGB(44, 40, 60), Material = Enum.Material.Metal, Parent = folder })
		table.insert(strips, part({ Name = "DoorStrip", Size = Vector3.new(0.35, H - 1, 0.35), CFrame = cf * CFrame.new(px - sx * 0.85, 1 + H / 2, front), Color = Color3.fromRGB(80, 255, 120), Material = Enum.Material.Neon, CanCollide = false, Parent = folder }))
	end
	for i = 1, 6 do
		table.insert(bars, part({ Name = "LaserBar", Size = Vector3.new(P.EntranceWidth, 0.25, 0.25), CFrame = cf * CFrame.new(0, 1 + i * 2, front), Color = Color3.fromRGB(255, 40, 60), Material = Enum.Material.Neon, Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false, Parent = folder }))
	end
	local blocker = part({ Name = "LaserBlocker", Size = Vector3.new(P.EntranceWidth, H + 6, 0.8), CFrame = cf * CFrame.new(0, 1 + (H + 6) / 2, front), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false, Parent = folder })
	blocker:SetAttribute("PlotIndex", index)

	-- Owner sign above the entrance (faces the carpet)
	local sign = part({ Name = "Sign", Size = Vector3.new(P.EntranceWidth + 4, 3.4, 0.8), CFrame = cf * CFrame.new(0, H + 3.4, front - 0.1), Color = Color3.fromRGB(40, 32, 66), Parent = folder })
	part({ Name = "SignTrim", Size = Vector3.new(P.EntranceWidth + 4.6, 4, 0.5), CFrame = cf * CFrame.new(0, H + 3.4, front + 0.35), Color = color, Material = Enum.Material.Neon, Parent = folder })
	local signLabel = textLabel(surface(sign), { Size = UDim2.fromScale(1, 1), Text = "EMPTY PLOT", TextColor3 = Color3.fromRGB(255, 255, 255) })
	local statusGui = billboard(sign, UDim2.new(14, 0, 2.2, 0), Vector3.new(0, 3.2, 0), 160)
	statusGui.Name = "LockStatus"
	local statusLabel = textLabel(statusGui, { Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = Color3.fromRGB(120, 255, 140) })

	-- Lock button (inside, right of the entrance)
	local buttonBase = part({ Name = "LockConsole", Size = Vector3.new(2.4, 2.6, 2.4), CFrame = cf * CFrame.new(P.EntranceWidth / 2 + 5, 1 + 1.3, front + 5), Color = Color3.fromRGB(60, 56, 80), Material = Enum.Material.Metal, Parent = folder })
	local button = vcyl({ Name = "LockButton", CFrame = buttonBase.CFrame * CFrame.new(0, 1.55, 0), Color = Color3.fromRGB(255, 50, 60), Material = Enum.Material.Neon, Parent = folder }, 0.5, 1.8)
	local lockPrompt = Instance.new("ProximityPrompt")
	lockPrompt.Name = "LockPrompt"
	lockPrompt.ActionText = "Lock Base"
	lockPrompt.ObjectText = "Laser Door"
	lockPrompt.HoldDuration = 0.25
	lockPrompt.MaxActivationDistance = 9
	lockPrompt.RequiresLineOfSight = false
	lockPrompt.KeyboardKeyCode = Enum.KeyCode.E
	lockPrompt.Parent = button
	local consoleGui = billboard(buttonBase, UDim2.new(6, 0, 1.6, 0), Vector3.new(0, 3.4, 0), 50)
	local consoleLabel = textLabel(consoleGui, { Size = UDim2.fromScale(1, 1), Text = "LOCK", TextColor3 = Color3.fromRGB(255, 120, 120) })

	-- Pedestals
	local pedestals = {}
	for slot = 1, GameConfig.MaxPedestals do
		pedestals[slot] = buildPedestal(folder, cf, slot, color)
	end

	return {
		index = index,
		cframe = cf,
		color = color,
		model = folder,
		pedestals = pedestals,
		laser = { blocker = blocker, bars = bars, strips = strips },
		signLabel = signLabel,
		statusLabel = statusLabel,
		lockButton = button,
		lockPrompt = lockPrompt,
		consoleLabel = consoleLabel,
		spawnCFrame = cf * CFrame.new(0, 4, front + 9),
		-- just outside the laser door, on the walkway
		doorstep = cf * CFrame.new(0, 0, front - 4),
		entrance = cf * CFrame.new(0, 1, front + 3),
	}
end

function WorldBuilder.build()
	local existing = workspace:FindFirstChild("SnatchWorld")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "SnatchWorld"
	root.Parent = workspace

	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = root

	local groundSize = Vector3.new(220, 1, C.EndZ - C.StartZ + 120)
	part({ Name = "Ground", Size = groundSize, CFrame = CFrame.new(0, -0.5, 0), Color = Color3.fromRGB(112, 198, 92), Material = Enum.Material.Grass, Parent = scenery })
	-- invisible boundary walls
	for _, w in ipairs({
		{ Vector3.new(2, 60, groundSize.Z), Vector3.new(groundSize.X / 2, 30, 0) },
		{ Vector3.new(2, 60, groundSize.Z), Vector3.new(-groundSize.X / 2, 30, 0) },
		{ Vector3.new(groundSize.X, 60, 2), Vector3.new(0, 30, groundSize.Z / 2) },
		{ Vector3.new(groundSize.X, 60, 2), Vector3.new(0, 30, -groundSize.Z / 2) },
	}) do
		part({ Name = "Boundary", Size = w[1], CFrame = CFrame.new(w[2]), Transparency = 1, CastShadow = false, Parent = scenery })
	end
	buildCarpet(scenery)
	local portalCenter = buildPortal(scenery)

	-- trees around the edge
	local seed = 17
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for i = 0, 13 do
		local z = C.StartZ - 20 + i * ((C.EndZ - C.StartZ + 40) / 13)
		for _, x in ipairs({ -88, 88 }) do
			buildTree(scenery, Vector3.new(x + (rnd() - 0.5) * 12, 0, z + (rnd() - 0.5) * 8), 0.8 + rnd() * 0.6)
		end
	end
	for _, x in ipairs({ -60, -40, 40, 60 }) do
		buildTree(scenery, Vector3.new(x, 0, C.StartZ - 34 + rnd() * 6), 0.9 + rnd() * 0.4)
		buildTree(scenery, Vector3.new(x, 0, C.EndZ + 30 + rnd() * 6), 0.9 + rnd() * 0.4)
	end

	local leaderboard = buildBoard(scenery, "Leaderboard", Vector3.new(-30, 14, C.StartZ - 8), "TOP EARNERS ($/s)", 10, Color3.fromRGB(255, 200, 60))
	local eventBoard = buildBoard(scenery, "EventBoard", Vector3.new(30, 14, C.StartZ - 8), "SERVER EVENTS", 6, Color3.fromRGB(120, 220, 255))

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root
	local plots = {}
	for i = 1, GameConfig.MaxPlayers do
		plots[i] = buildPlot(plotsFolder, i)
	end

	local blobbies = Instance.new("Folder")
	blobbies.Name = "Blobbies"
	blobbies.Parent = root
	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = root

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "FallbackSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, C.StartZ - 18)
	spawn.Color = Color3.fromRGB(60, 50, 90)
	spawn.Material = Enum.Material.Slate
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = scenery

	return {
		folder = root,
		plots = plots,
		blobbies = blobbies,
		effects = effects,
		leaderboard = leaderboard,
		eventBoard = eventBoard,
		portalCenter = portalCenter,
		carpetStart = Vector3.new(0, 0.3, C.StartZ),
		carpetEnd = Vector3.new(0, 0.3, C.EndZ),
	}
end

return WorldBuilder
