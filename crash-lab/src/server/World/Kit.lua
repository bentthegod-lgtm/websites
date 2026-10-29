--[[
	Kit - shared building blocks for every facility builder: anchored parts with a running
	part count, decorations (no collision / query / touch), signs, hazard stripes, and the
	course pieces the server's checks rely on (launch pads, rings, targets, landing zones,
	destructible props, distance markers, the arrival area and its HUB TRANSIT kiosk).

	Course pieces take `O`, the facility's world origin (CourseConfig.Courses[*].Origin),
	and the LOCAL positions from CourseConfig, so world and server checks always agree.
	Tags (attributes) used by the crash simulation:
	  CL_Floor = true      ground contact (grouped impacts)
	  CL_Key   = "<id>"    an obstacle that counts as its own impact object
	  CL_Prop  = "<id>"    a destructible prop (world.props[id])
	  CL_Target = "<id>"   a target (world.targets[id])
	  CL_Soft  = true      crash pad (bouncy; plays the soft sound)
	  CL_Bounce = speed    bounce field (Gravity Lab): launches the dummy upward
	  CL_Flip  = true      ceiling flip panel (Gravity Lab): switches the flip column off
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)

local Kit = {}

local rgb = Color3.fromRGB
Kit.rgb = rgb
Kit.M = Enum.Material
Kit.CYL = Enum.PartType.Cylinder
Kit.BALL = Enum.PartType.Ball
local M = Kit.M
local CYL = Kit.CYL

Kit.C = {
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
local C = Kit.C

-- Collision group for walls that stop players but not dummies or debris (see CrashService).
Kit.PlayerWallGroup = "CL_PlayerWall"

local partCount = 0
local root
local propCounter = 0

function Kit.reset(folder)
	partCount = 0
	propCounter = 0
	root = folder
end

function Kit.count()
	return partCount
end

function Kit.add(n)
	partCount += n
end

function Kit.part(props)
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
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	p.Name = props.Name or "Part"
	p.Parent = props.Parent or root
	partCount += 1
	return p
end

function Kit.deco(props)
	props.CanCollide = false
	props.CanQuery = false
	local p = Kit.part(props)
	p.CanTouch = false
	return p
end

-- A wall only players bump into (dummies and debris fly straight through it).
function Kit.playerWall(props)
	props.Transparency = props.Transparency or 1
	props.CanQuery = false
	props.CastShadow = false
	local p = Kit.part(props)
	p.CanTouch = false
	p.CollisionGroup = Kit.PlayerWallGroup
	return p
end

function Kit.sub(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or root
	return f
end

function Kit.key(p, id)
	p:SetAttribute("CL_Key", id)
	return p
end

function Kit.floor(p)
	p:SetAttribute("CL_Floor", true)
	return p
end

function Kit.surfaceText(target, face, text, props)
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

-- Yellow / black hazard stripes along the CFrame's X axis.
function Kit.hazardStrip(cf, length, width, count, parent, colors)
	local seg = length / count
	local a, b = (colors and colors[1]) or C.Yellow, (colors and colors[2]) or C.Black
	for i = 0, count - 1 do
		Kit.deco({ Size = Vector3.new(seg, 0.12, width), CFrame = cf * CFrame.new(-length / 2 + seg * (i + 0.5), 0, 0), Color = if i % 2 == 0 then a else b, Parent = parent })
	end
end

function Kit.light(className, parent, props)
	local l = Instance.new(className)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Kit.prompt(parent, action, object, distance)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

---------------------------------------------------------------------------------------------
-- Launch pads
---------------------------------------------------------------------------------------------

-- One launch pad at `cf` (its top centre, facing +Z down the course). Pads are numbered
-- across every facility (world.pads is one list), and each knows its facility.
function Kit.pad(world, parent, cf, yaw, facilityId)
	local i = #world.pads + 1
	local pad = Kit.part({ Name = "Pad" .. i, Size = Vector3.new(13, 0.3, 13), CFrame = cf * CFrame.new(0, 0.15, 0), Color = rgb(40, 44, 52), Material = M.Metal, Parent = parent })
	local glow = Kit.deco({ Name = "PadGlow", Size = Vector3.new(13.4, 0.15, 13.4), CFrame = cf * CFrame.new(0, 0.05, 0), Color = C.Green, Material = M.Neon, Parent = parent })
	local numberPost = Kit.deco({ Size = Vector3.new(3, 3, 0.4), CFrame = cf * CFrame.new(5, 4, -6.4), Color = C.Black, Parent = parent })
	local label = Kit.surfaceText(numberPost, Enum.NormalId.Front, tostring(i), { Color = C.Yellow, PPS = 30 })
	Kit.deco({ Size = Vector3.new(0.4, 2.5, 0.4), CFrame = cf * CFrame.new(5, 1.25, -6.4), Color = C.Steel, Parent = parent })
	local ownerBoard = Kit.deco({ Size = Vector3.new(8, 1.6, 0.3), CFrame = cf * CFrame.new(0, 9.5, -6.6), Color = C.Black, Parent = parent })
	local ownerLabel = Kit.surfaceText(ownerBoard, Enum.NormalId.Front, "FREE  -  PRESS E", { Color = C.Green, PPS = 30, LightInfluence = 0 })
	Kit.deco({ Size = Vector3.new(0.4, 8, 0.4), CFrame = cf * CFrame.new(-3.6, 5.6, -6.6), Color = C.Steel, Parent = parent })
	Kit.deco({ Size = Vector3.new(0.4, 8, 0.4), CFrame = cf * CFrame.new(3.6, 5.6, -6.6), Color = C.Steel, Parent = parent })
	local prompt = Kit.prompt(pad, "Use Launcher", "Launch Pad " .. i, 11)
	local slot = Kit.sub("PadMachine" .. i, parent)
	-- Where the owner stands while launching: behind the machine, FACING down the course
	-- (a character faces its LookVector, -Z, so turn half way round).
	local stand = cf * CFrame.new(0, 3, -10) * CFrame.Angles(0, math.pi, 0)
	local record = {
		index = i,
		facility = facilityId,
		cframe = cf,
		yaw = yaw,
		part = pad,
		glow = glow,
		prompt = prompt,
		slot = slot,
		label = label,
		ownerLabel = ownerLabel,
		stand = stand,
	}
	table.insert(world.pads, record)
	return record
end

-- A row of `count` pads centred on X = 0 of the facility, aiming slightly toward the
-- centre line (they converge ~280 studs out). `top` is the deck's top surface (local Y).
function Kit.padRow(world, parent, O, count, spacing, top, facilityId)
	local list = {}
	for i = 1, count do
		local x = (i - (count + 1) / 2) * spacing
		local yaw = math.atan2(-x, 280)
		local cf = CFrame.new(O + Vector3.new(x, top, 0)) * CFrame.Angles(0, yaw, 0)
		table.insert(list, Kit.pad(world, parent, cf, yaw, facilityId))
	end
	return list
end

---------------------------------------------------------------------------------------------
-- Rings, targets, landing zones, props
---------------------------------------------------------------------------------------------

-- Fly-through ring: the ring itself doesn't collide; its posts do (floating rings have none).
-- opts.postFloor: local Y the posts stand on (default 0).
function Kit.ring(world, def, O, parent, opts)
	opts = opts or {}
	local ringFolder = Kit.sub(def.Id, parent)
	local col = rgb(def.Color[1], def.Color[2], def.Color[3])
	local centre = O + def.Position
	local segments = 20
	for s = 0, segments - 1 do
		local a = s / segments * math.pi * 2
		local p = centre + Vector3.new(math.cos(a) * def.Radius, math.sin(a) * def.Radius, 0)
		Kit.deco({ Size = Vector3.new(1.2, def.Radius * 2 * math.pi / segments + 0.5, 1.2), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, a), Color = col, Material = M.Neon, Parent = ringFolder })
	end
	if not def.Floating then
		local floorY = opts.postFloor or 0
		local h = def.Position.Y - floorY
		for _, side in ipairs({ -1, 1 }) do
			local postX = centre.X + side * (def.Radius + 1.5)
			local post = Kit.part({ Name = "RingPost", Size = Vector3.new(1.2, h, 1.2), CFrame = CFrame.new(postX, O.Y + floorY + h / 2, centre.Z), Color = C.Steel, Material = M.Metal, Parent = ringFolder })
			Kit.key(post, def.Id .. "Post")
		end
	end
	Kit.light("PointLight", ringFolder:FindFirstChildWhichIsA("BasePart"), { Color = col, Range = 18, Brightness = 0.8 })
	world.rings[def.Id] = { def = def, folder = ringFolder }
	return ringFolder
end

-- Targets. Moving ones are moved by CourseService (Motion + the facility origin).
-- def.Mount picks the frame: nil (overhead track + posts / floor carriage / gong frame),
-- "Cable" (canyon cable, no posts), "Wall" (arm from the canyon wall), "Crane" (a crane
-- jib with a wrecking ball), "Float" (a glowing core with no frame at all).
-- opts: { floorY = local floor, span = cable length, wallX = local X of the wall }
function Kit.target(world, def, O, parent, opts)
	opts = opts or {}
	local floorY = opts.floorY or 0
	local tFolder = Kit.sub(def.Id, parent)
	local centre = O + def.Position
	local face = CFrame.new(centre) * CFrame.Angles(0, math.rad(90), 0)
	local hit
	local rings = {}
	if def.Mount == "Crane" or def.Mount == "Float" then
		local core = def.Mount == "Float"
		hit = Kit.part({ Name = def.Id, Size = Vector3.new(def.Radius * 2, def.Radius * 2, def.Radius * 2), CFrame = CFrame.new(centre), Shape = Kit.BALL, Color = if core then rgb(120, 240, 255) else rgb(46, 46, 50), Material = if core then M.Neon else M.Metal, Parent = tFolder })
		if core then
			for k = 1, 2 do
				table.insert(rings, Kit.deco({ Size = Vector3.new(0.6, def.Radius * 2 + 4 + k * 3, def.Radius * 2 + 4 + k * 3), CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(k * 60)), Shape = CYL, Color = rgb(190, 110, 255), Material = M.Neon, Transparency = 0.2, Parent = tFolder }))
			end
		else
			table.insert(rings, Kit.deco({ Size = Vector3.new(def.Radius * 2 + 0.4, 1.4, 1.4), CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = C.Yellow, Material = M.Metal, Parent = tFolder }))
		end
	else
		hit = Kit.part({ Name = def.Id, Size = Vector3.new(1.4, def.Radius * 2, def.Radius * 2), CFrame = face, Shape = CYL, Color = C.White, Material = M.SmoothPlastic, Parent = tFolder })
		for k, rr in ipairs({ 0.75, 0.5, 0.25 }) do
			table.insert(rings, Kit.deco({ Size = Vector3.new(1.5 + k * 0.05, def.Radius * 2 * rr, def.Radius * 2 * rr), CFrame = face, Shape = CYL, Color = if k % 2 == 1 then C.Red else C.White, Parent = tFolder }))
		end
	end
	hit:SetAttribute("CL_Target", def.Id)
	local movers = { hit }
	for _, r in ipairs(rings) do
		table.insert(movers, r)
	end
	local motion = def.Motion
	if motion and motion.Kind == "Swing" then
		local trackY = centre.Y + def.Radius + 10
		if def.Mount == "Cable" then
			-- A steel cable across the canyon, anchored in both walls.
			Kit.part({ Name = "Cable", Size = Vector3.new(opts.span or (motion.Amplitude * 2 + 20), 0.8, 0.8), CFrame = CFrame.new(centre.X, trackY, centre.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
		elseif def.Mount == "Crane" then
			-- Crane jib over the yard on a lattice tower.
			local towerX = centre.X - motion.Amplitude - 16
			local towerH = trackY + 4 - (O.Y + floorY)
			Kit.part({ Name = "CraneTower", Size = Vector3.new(4, towerH, 4), CFrame = CFrame.new(towerX, O.Y + floorY + towerH / 2, centre.Z), Color = C.Yellow, Material = M.Metal, Parent = tFolder })
			for y = 6, towerH - 4, 8 do
				Kit.deco({ Size = Vector3.new(4.4, 0.5, 4.4), CFrame = CFrame.new(towerX, O.Y + floorY + y, centre.Z), Color = C.Black, Material = M.Metal, Parent = tFolder })
			end
			Kit.part({ Name = "CraneJib", Size = Vector3.new(motion.Amplitude * 2 + 30, 2.4, 3), CFrame = CFrame.new(centre.X - 1, trackY + 1, centre.Z), Color = C.Yellow, Material = M.Metal, Parent = tFolder })
			Kit.part({ Name = "CraneCab", Size = Vector3.new(6, 5, 6), CFrame = CFrame.new(towerX, trackY + 1, centre.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
		else
			Kit.part({ Name = "Track", Size = Vector3.new(motion.Amplitude * 2 + 20, 1, 1.6), CFrame = CFrame.new(centre.X, trackY, centre.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
			local postH = trackY - (O.Y + floorY)
			for _, side in ipairs({ -1, 1 }) do
				Kit.part({ Name = "TrackPost", Size = Vector3.new(1.4, postH, 1.4), CFrame = CFrame.new(centre.X + side * (motion.Amplitude + 10), O.Y + floorY + postH / 2, centre.Z), Color = C.Steel, Material = M.Metal, Parent = tFolder })
			end
		end
		table.insert(movers, Kit.deco({ Size = Vector3.new(0.4, 10, 0.4), CFrame = CFrame.new(centre + Vector3.new(0, def.Radius + 5, 0)), Color = C.Steel, Parent = tFolder }))
	elseif motion then
		Kit.part({ Name = "Track", Size = Vector3.new(motion.Amplitude * 2 + 20, 1, 1.6), CFrame = CFrame.new(centre.X, O.Y + floorY + 0.6, centre.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
		local mastH = def.Position.Y - floorY - def.Radius - 1
		table.insert(movers, Kit.deco({ Size = Vector3.new(4, 2, 3), CFrame = CFrame.new(centre.X, O.Y + floorY + 1.6, centre.Z), Color = C.Yellow, Parent = tFolder }))
		table.insert(movers, Kit.deco({ Size = Vector3.new(0.6, mastH, 0.6), CFrame = CFrame.new(centre.X, O.Y + floorY + (def.Position.Y - floorY - def.Radius) / 2 + 1, centre.Z), Color = C.Steel, Parent = tFolder }))
	elseif def.Mount == "Wall" then
		-- Steel arm from the canyon wall out to the target.
		local wallX = O.X + (opts.wallX or (def.Position.X + 30))
		local len = math.abs(wallX - centre.X)
		Kit.part({ Name = "TargetArm", Size = Vector3.new(len, 1.6, 1.6), CFrame = CFrame.new((wallX + centre.X) / 2, centre.Y, centre.Z + 1.5), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
		Kit.part({ Name = "TargetBrace", Size = Vector3.new(len * 0.7, 1, 1), CFrame = CFrame.new((wallX + centre.X) / 2 + len * 0.12, centre.Y - 5, centre.Z + 1.5) * CFrame.Angles(0, 0, math.rad(-22)), Color = C.Steel, Material = M.Metal, Parent = tFolder })
	elseif def.Mount ~= "Float" then
		-- The gong frame.
		local h = def.Position.Y - floorY + def.Radius + 4
		for _, side in ipairs({ -1, 1 }) do
			Kit.part({ Name = "GongPost", Size = Vector3.new(2, h, 2), CFrame = CFrame.new(centre.X + side * (def.Radius + 3), O.Y + floorY + h / 2, centre.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
		end
		Kit.part({ Name = "GongBeam", Size = Vector3.new(def.Radius * 2 + 10, 2, 2), CFrame = CFrame.new(centre.X, centre.Y + def.Radius + 4, centre.Z), Color = C.SteelDark, Material = M.Metal, Parent = tFolder })
		hit.Color = rgb(214, 170, 60)
		hit.Material = M.Metal
		for _, r in ipairs(rings) do
			r.Color = rgb(190, 140, 40)
			r.Material = M.Metal
		end
	end
	local base = {}
	for _, m in ipairs(movers) do
		base[m] = CFrame.new(centre):ToObjectSpace(m.CFrame)
	end
	-- `offset` is the facility origin: CourseService moves targets to offset + Motion.position.
	world.targets[def.Id] = { def = def, part = hit, movers = movers, base = base, origin = centre, offset = O }
	return tFolder
end

function Kit.zone(world, def, O, parent)
	local col = rgb(def.Color[1], def.Color[2], def.Color[3])
	local disc = Kit.deco({ Size = Vector3.new(0.12, def.Radius * 2, def.Radius * 2), CFrame = CFrame.new(O + def.Position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = col, Material = M.Neon, Transparency = 0.25, Parent = parent })
	Kit.deco({ Size = Vector3.new(0.14, def.Radius * 1.2, def.Radius * 1.2), CFrame = disc.CFrame, Shape = CYL, Color = C.White, Material = M.SmoothPlastic, Parent = parent })
	Kit.deco({ Size = Vector3.new(0.16, def.Radius * 0.5, def.Radius * 0.5), CFrame = disc.CFrame, Shape = CYL, Color = col, Material = M.Neon, Parent = parent })
	world.zones[def.Id] = { def = def, part = disc }
	return disc
end

-- A destructible prop (world CFrame). Breaking only hides it (a prebuilt break state:
-- no geometry is created or destroyed), CourseService adds a few pooled fragments.
function Kit.prop(world, kindId, size, cf, groupName, parent, facilityId)
	propCounter += 1
	local kind = CourseConfig.DestructibleKinds[kindId]
	local id = kindId .. propCounter
	local p = Kit.part({ Name = id, Size = size, CFrame = cf, Color = rgb(kind.Color[1], kind.Color[2], kind.Color[3]), Material = M[kind.Material] or M.SmoothPlastic, Shape = if kind.Shape then Enum.PartType[kind.Shape] else nil, Transparency = kind.Transparency, Parent = parent })
	p:SetAttribute("CL_Prop", id)
	world.props[id] = { id = id, kind = kindId, group = groupName, part = p, cframe = cf, size = size, broken = false, transparency = kind.Transparency or 0, facility = facilityId }
	return p
end

---------------------------------------------------------------------------------------------
-- Distance markers, nets, arrival
---------------------------------------------------------------------------------------------

-- Floor lines + numbers + side signs every MarkerEvery studs. opts: { floorY, half, length,
-- signX (local X of the side signs), signY (local base height), floorColor }
function Kit.markers(world, course, O, parent, opts)
	local floorY = opts.floorY or 0
	local half = opts.half or course.Arena.HalfWidth
	for d = course.MarkerEvery, (opts.length or course.Arena.Length) - 40, course.MarkerEvery do
		local isGoal = table.find(course.DistanceGoals, d) ~= nil
		local col = if isGoal then C.Yellow else (opts.lineColor or C.White)
		if not opts.noFloor then
			Kit.deco({ Name = "MarkerLine", Size = Vector3.new(half * 2 - 6, 0.06, 0.8), CFrame = CFrame.new(O + Vector3.new(0, floorY + 0.045, d)), Color = col, Material = if isGoal then M.Neon else M.SmoothPlastic, CastShadow = false, Parent = parent })
			for _, x in ipairs({ -22, 22 }) do
				local paint = Kit.deco({ Name = "FloorNumber", Size = Vector3.new(12, 0.02, 7), CFrame = CFrame.new(O + Vector3.new(x, floorY + 0.03, d + 5)) * CFrame.Angles(0, math.rad(180), 0), Color = col, Transparency = 1, CastShadow = false, Parent = parent })
				Kit.surfaceText(paint, Enum.NormalId.Top, tostring(d), { Color = col, PPS = 12, LightInfluence = 1 })
			end
		end
		local signX = opts.signX or (half - 3)
		local signY = opts.signY or floorY
		for _, x in ipairs({ -1, 1 }) do
			local post = Kit.deco({ Size = Vector3.new(0.6, 8, 0.6), CFrame = CFrame.new(O + Vector3.new(x * signX, signY + 4, d)), Color = C.Steel, Parent = parent })
			local signPart = Kit.deco({ Size = Vector3.new(6, 3.4, 0.4), CFrame = post.CFrame * CFrame.new(0, 5, 0), Color = if isGoal then C.Yellow else C.Black, Parent = parent })
			Kit.surfaceText(signPart, Enum.NormalId.Back, tostring(d), { Color = if isGoal then C.Black else C.White, PPS = 24 })
			Kit.surfaceText(signPart, Enum.NormalId.Front, tostring(d), { Color = if isGoal then C.Black else C.White, PPS = 24 })
		end
		table.insert(world.markers, d)
	end
end

-- Thick side nets and a far catch net (fast dummies can tunnel through thin parts).
-- opts: { floorY, half, length, height, color }
function Kit.nets(O, parent, opts)
	local floorY = opts.floorY or 0
	local half, length, height = opts.half, opts.length, opts.height or 130
	local netColor = opts.color or rgb(40, 44, 50)
	for _, x in ipairs({ -1, 1 }) do
		local net = Kit.part({ Name = "SideNet", Size = Vector3.new(4, height, length + 20), CFrame = CFrame.new(O + Vector3.new(x * (half + 2), floorY + height / 2, length / 2 + 4)), Color = netColor, Material = M.Fabric, Transparency = 0.82, Parent = parent })
		Kit.key(net, "SideNet")
		Kit.deco({ Size = Vector3.new(1.2, 1.2, length + 20), CFrame = CFrame.new(O + Vector3.new(x * (half + 2), floorY + height + 0.6, length / 2 + 4)), Color = opts.railColor or C.Yellow, Material = M.Metal, Parent = parent })
		for z = 10, length, 60 do
			Kit.part({ Name = "NetPost", Size = Vector3.new(1.4, height, 1.4), CFrame = CFrame.new(O + Vector3.new(x * (half + 4.6), floorY + height / 2, z)), Color = C.Steel, Material = M.Metal, Parent = parent })
		end
	end
	local catch = Kit.part({ Name = "CatchNet", Size = Vector3.new(half * 2 + 8, height, 6), CFrame = CFrame.new(O + Vector3.new(0, floorY + height / 2, length + 2.5)), Color = netColor, Material = M.Fabric, Transparency = 0.7, Parent = parent })
	Kit.key(catch, "CatchNet")
	Kit.part({ Name = "CatchFrameTop", Size = Vector3.new(half * 2 + 4, 2, 2), CFrame = CFrame.new(O + Vector3.new(0, floorY + height + 1, length)), Color = opts.railColor or C.Yellow, Material = M.Metal, Parent = parent })
end

-- Arrival area behind a facility's deck: where travellers appear, plus the HUB TRANSIT
-- kiosk (its prompt takes the player back to the hub). Returns the spawn CFrame.
function Kit.arrival(facilityId, O, parent, opts)
	opts = opts or {}
	local top = opts.top or 0
	local accent = opts.accent or C.Yellow
	local z = opts.z or -46
	local padPart = Kit.part({ Name = "ArrivalPad", Size = Vector3.new(14, 0.4, 14), CFrame = CFrame.new(O + Vector3.new(0, top + 0.2, z)), Color = C.SteelDark, Material = M.DiamondPlate, Parent = parent })
	Kit.floor(padPart)
	Kit.deco({ Name = "ArrivalRing", Size = Vector3.new(0.2, 15, 15), CFrame = CFrame.new(O + Vector3.new(0, top + 0.32, z)) * CFrame.Angles(0, 0, math.rad(90)), Shape = CYL, Color = accent, Material = M.Neon, Transparency = 0.3, Parent = parent })
	local kioskCF = CFrame.new(O + Vector3.new(22, top, z)) * CFrame.Angles(0, math.rad(-90), 0)
	local kiosk = Kit.part({ Name = "HubTransit", Size = Vector3.new(8, 8, 3), CFrame = kioskCF * CFrame.new(0, 4, 0), Color = C.SteelDark, Material = M.Metal, Parent = parent })
	local screen = Kit.deco({ Size = Vector3.new(6.6, 3, 0.3), CFrame = kioskCF * CFrame.new(0, 5.4, -1.6), Color = rgb(20, 30, 40), Parent = parent })
	Kit.surfaceText(screen, Enum.NormalId.Front, "HUB TRANSIT", { Color = accent, PPS = 30, LightInfluence = 0 })
	Kit.deco({ Size = Vector3.new(8.4, 0.5, 3.4), CFrame = kioskCF * CFrame.new(0, 8.2, 0), Color = accent, Material = M.Neon, Parent = parent })
	local prompt = Kit.prompt(kiosk, "Return to Hub", "Hub Transit", 12)
	local sign = Kit.deco({ Name = "FacilitySign", Size = Vector3.new(34, 5, 0.6), CFrame = CFrame.new(O + Vector3.new(0, top + 16, z - 12)) * CFrame.Angles(0, math.pi, 0), Color = C.Black, Material = M.Metal, Parent = parent })
	Kit.surfaceText(sign, Enum.NormalId.Front, string.upper(CourseConfig.FacilityById[facilityId].Name), { Color = accent, PPS = 16, LightInfluence = 0 })
	Kit.surfaceText(sign, Enum.NormalId.Back, string.upper(CourseConfig.FacilityById[facilityId].Name), { Color = accent, PPS = 16, LightInfluence = 0 })
	for _, x in ipairs({ -16.5, 16.5 }) do
		Kit.part({ Name = "SignPost", Size = Vector3.new(0.8, 16, 0.8), CFrame = CFrame.new(O + Vector3.new(x, top + 8, z - 12)), Color = C.Steel, Material = M.Metal, Parent = parent })
	end
	return CFrame.new(O + Vector3.new(0, top + 4, z)) * CFrame.Angles(0, math.pi, 0), prompt
end

-- The launch deck of a new facility (local Z -23..7, top at local Y 1, standing on
-- ground at local Y 0) with its pads, a ramp down to the arrival area, the arrival pad
-- and the HUB TRANSIT kiosk. Fills entry.pads / entry.spawn / entry.returnPrompt.
function Kit.facilityDeck(world, entry, opts)
	opts = opts or {}
	local O = entry.origin
	local deck = Kit.sub("LaunchDeck", entry.folder)
	local count = entry.course.PadCount
	local width = count * 18 + 22
	local floor = Kit.part({ Name = "Deck", Size = Vector3.new(width, 1, 30), CFrame = CFrame.new(O + Vector3.new(0, 0.5, -8)), Color = opts.deckColor or C.SteelDark, Material = M.DiamondPlate, Parent = deck })
	Kit.floor(floor)
	local stripes = math.floor(width / 5)
	Kit.hazardStrip(CFrame.new(O + Vector3.new(0, 1.06, 6.4)), width, 1.2, stripes, deck, opts.stripes)
	Kit.hazardStrip(CFrame.new(O + Vector3.new(0, 1.06, -22.4)), width, 1.2, stripes, deck, opts.stripes)
	local ramp = Kit.part({ Class = "WedgePart", Name = "DeckRamp", Size = Vector3.new(40, 1, 6), CFrame = CFrame.new(O + Vector3.new(0, 0.5, -26)), Color = opts.deckColor or C.SteelDark, Material = M.DiamondPlate, Parent = deck })
	Kit.floor(ramp)
	-- A light bar over the pads, in the facility's accent colour.
	Kit.deco({ Name = "LightBar", Size = Vector3.new(width - 10, 1, 1.6), CFrame = CFrame.new(O + Vector3.new(0, 24, -4)), Color = C.SteelDark, Material = M.Metal, Parent = deck })
	for _, x in ipairs({ -1, 1 }) do
		Kit.part({ Name = "LightBarPost", Size = Vector3.new(1.4, 23, 1.4), CFrame = CFrame.new(O + Vector3.new(x * (width / 2 - 5), 12.5, -4)), Color = C.Steel, Material = M.Metal, Parent = deck })
	end
	local lamp = Kit.deco({ Name = "WorkLight", Size = Vector3.new(width - 20, 0.5, 1.2), CFrame = CFrame.new(O + Vector3.new(0, 23.3, -4)), Color = opts.lampColor or rgb(255, 226, 170), Material = M.Neon, Parent = deck })
	Kit.light("SurfaceLight", lamp, { Face = Enum.NormalId.Bottom, Angle = 100, Range = 32, Brightness = 1.1, Color = opts.lampColor or rgb(255, 214, 160), Shadows = false })
	entry.pads = Kit.padRow(world, deck, O, count, 18, 1, entry.id)
	entry.spawn, entry.returnPrompt = Kit.arrival(entry.id, O, entry.folder, { top = 0, accent = opts.accent })
	return deck
end

-- An ambient sound emitter (AudioController plays AudioAssets[name] from it).
function Kit.ambient(name, position, parent)
	local e = Kit.deco({ Name = "Ambient", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(position), Transparency = 1, Color = C.Steel, Parent = parent })
	e:SetAttribute("Ambient", name)
	return e
end

return Kit
