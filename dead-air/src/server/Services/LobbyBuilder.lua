--[[
	LobbyBuilder - the surface-level staff reception where players gather between runs.

	Layout (north = -Z):
	  north    service elevator "DESCENT" with a hazard-striped READY PAD in front of it and
	           a status board above the doors (ready count / countdown / run in progress)
	  west     SPECIMEN 01: a caged, motionless Listener so new players learn its silhouette
	  centre   footstep test floor: carpet / tile / metal strips - listen to the difference
	  east     briefing boards (sound, hiding, teamwork) and the server record board
	  south    staff lounge with couches, vending machine and the spawn point
	  corner   practice locker you can climb into

	Standing on the ready pad marks you ready (the READY button works too).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MapConfig = require(Shared.Config.MapConfig)

local MapBuilder = require(script.Parent.MapBuilder)
local MonsterModel = require(script.Parent.MonsterModel)

local LobbyBuilder = {}

local Lobby = {}
Lobby.__index = Lobby

local rgb = Color3.fromRGB
local P = MapBuilder.Palette
local MAT = P.Materials
local newPart = MapBuilder.newPart
local surfaceText = MapBuilder.surfaceText
local Props = MapBuilder.Props

local WIDTH, DEPTH, HEIGHT = 72, 56, 14

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A wall-mounted board with a title and body; returns the body label for updates.
local function board(parent, cf, size, title, body)
	local part = newPart(parent, { Name = "Board", Size = Vector3.new(size.X, size.Y, 0.3), CFrame = cf, Color = rgb(36, 40, 36) })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.2
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(26, 30, 26)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 10)
	padding.Parent = frame
	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.new(1, 0, 0, 34)
	heading.Font = Enum.Font.Code
	heading.TextScaled = true
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = rgb(232, 196, 96)
	heading.Text = title
	heading.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, 42)
	label.Size = UDim2.new(1, 0, 1, -52)
	label.Font = Enum.Font.Code
	label.TextSize = 20
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = rgb(230, 224, 200)
	label.Text = body
	label.Parent = frame
	return label
end

local function fixture(parent, position, flicker)
	local tube = newPart(parent, {
		Name = "FluorescentTube",
		Size = Vector3.new(6, 0.25, 1.2),
		Position = position,
		Color = P.TubeOn,
		Material = MAT.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 28
	light.Brightness = 1.05
	light.Color = P.LightPower
	light.Shadows = true
	light.Parent = tube
	-- Same tags/attributes as facility lights, so clients flicker them the same way.
	tube:SetAttribute("On", true)
	tube:SetAttribute("BaseBrightness", light.Brightness)
	tube:SetAttribute("Flicker", flicker == true)
	CollectionService:AddTag(tube, "DA_Light")
	return tube
end

function LobbyBuilder.build()
	local existing = Workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	local self = setmetatable({}, Lobby)
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	self.folder = folder
	local p = MapConfig.LobbyPosition
	local o = Vector3.new(p[1], p[2], p[3])
	self.origin = o
	local function at(x, y, z)
		return o + Vector3.new(x, y, z)
	end
	-- Facing helper: CFrame at (x, y, z) whose front looks toward (tx, tz).
	local function facing(x, y, z, tx, tz)
		return CFrame.lookAt(at(x, y, z), at(tx, y, tz))
	end

	-- Shell ---------------------------------------------------------------------------------
	newPart(folder, { Name = "Floor", Size = Vector3.new(WIDTH, 1, DEPTH), Position = at(0, -0.5, 0), Color = P.FloorColors.Carpet, Material = MAT.Carpet }):SetAttribute("Surface", "Carpet")
	newPart(folder, { Name = "Ceiling", Size = Vector3.new(WIDTH, 1, DEPTH), Position = at(0, HEIGHT + 0.5, 0), Color = P.Ceiling, Material = MAT.Plaster })
	local wallColor = P.WallColors.Hallway
	for _, spec in ipairs({
		{ Vector3.new(WIDTH, HEIGHT, 1), at(0, HEIGHT / 2, -DEPTH / 2) },
		{ Vector3.new(WIDTH, HEIGHT, 1), at(0, HEIGHT / 2, DEPTH / 2) },
		{ Vector3.new(1, HEIGHT, DEPTH), at(-WIDTH / 2, HEIGHT / 2, 0) },
		{ Vector3.new(1, HEIGHT, DEPTH), at(WIDTH / 2, HEIGHT / 2, 0) },
	}) do
		newPart(folder, { Name = "Wall", Size = spec[1], Position = spec[2], Color = wallColor, Material = MAT.Plaster })
	end
	-- Faded green wainscot band around the room.
	for _, spec in ipairs({
		{ Vector3.new(WIDTH - 1, 3, 0.2), at(0, 1.5, -DEPTH / 2 + 0.6) },
		{ Vector3.new(WIDTH - 1, 3, 0.2), at(0, 1.5, DEPTH / 2 - 0.6) },
		{ Vector3.new(0.2, 3, DEPTH - 1), at(-WIDTH / 2 + 0.6, 1.5, 0) },
		{ Vector3.new(0.2, 3, DEPTH - 1), at(WIDTH / 2 - 0.6, 1.5, 0) },
	}) do
		newPart(folder, { Name = "Wainscot", Size = spec[1], Position = spec[2], Color = rgb(122, 140, 108), Material = MAT.Plaster, CanCollide = false })
	end
	local flickerIndex = 4
	local i = 0
	for _, x in ipairs({ -22, 0, 22 }) do
		for _, z in ipairs({ -14, 10 }) do
			i += 1
			fixture(folder, at(x, HEIGHT - 0.15, z), i == flickerIndex)
		end
	end

	-- North: elevator + ready pad + status board --------------------------------------------
	local northZ = -DEPTH / 2 + 0.5
	local elevator = model(folder, "DescentElevator")
	newPart(elevator, { Name = "Frame", Size = Vector3.new(14, 12, 0.6), Position = at(0, 6, northZ + 0.2), Color = rgb(80, 84, 84), Material = MAT.MetalPlain })
	for _, s in ipairs({ -1, 1 }) do
		newPart(elevator, {
			Name = "Door",
			Size = Vector3.new(5.4, 10.4, 0.4),
			Position = at(s * 2.75, 5.2, northZ + 0.7),
			Color = rgb(150, 154, 150),
			Material = MAT.MetalPlain,
		})
	end
	local beacon = newPart(elevator, { Name = "Beacon", Size = Vector3.new(1.2, 0.6, 0.6), Position = at(0, 12.6, northZ + 0.8), Color = rgb(255, 70, 40), Material = MAT.Neon, CanCollide = false })
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = rgb(255, 70, 40)
	beaconLight.Range = 16
	beaconLight.Brightness = 0.8
	beaconLight.Parent = beacon
	self.beacon = beacon

	-- Ready pad: hazard stripes on the floor in front of the doors.
	local padCenter = at(0, 0, northZ + 7)
	local pad = model(folder, "ReadyPad")
	newPart(pad, { Name = "Base", Size = Vector3.new(14, 0.1, 9), Position = padCenter + Vector3.new(0, 0.05, 0), Color = rgb(30, 30, 28), CanCollide = false })
	for k = -3, 3 do
		newPart(pad, {
			Name = "Stripe",
			Size = Vector3.new(1, 0.12, 9.6),
			CFrame = CFrame.new(padCenter + Vector3.new(k * 2, 0.06, 0)) * CFrame.Angles(0, math.rad(35), 0),
			Color = rgb(214, 172, 40),
			CanCollide = false,
			CanQuery = false,
		})
	end
	local padLabel = newPart(pad, { Name = "Label", Size = Vector3.new(12, 0.1, 2.2), Position = padCenter + Vector3.new(0, 0.13, 3.4), Color = rgb(30, 30, 28), CanCollide = false })
	surfaceText(padLabel, Enum.NormalId.Top, "STAND HERE TO READY UP", rgb(232, 196, 96), rgb(30, 30, 28))
	self.padZone = newPart(pad, {
		Name = "Zone",
		Size = Vector3.new(14, 8, 9),
		Position = padCenter + Vector3.new(0, 4, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	self.statusLabel = board(folder, facing(-14, 8.5, northZ + 0.7, -14, 0), Vector2.new(12, 5), "NEXT DESCENT", "Waiting for staff...")
	self.recordLabel = board(folder, facing(14, 8.5, northZ + 0.7, 14, 0), Vector2.new(12, 5), "SUB-LEVEL 3 RECORD", "No descents yet.")

	-- West: the specimen exhibit ------------------------------------------------------------
	local westX = -WIDTH / 2 + 8
	local cage = model(folder, "SpecimenExhibit")
	newPart(cage, { Name = "Plinth", Size = Vector3.new(12, 1, 12), Position = at(westX, 0.5, 0), Color = rgb(70, 72, 70), Material = MAT.Concrete })
	for _, spec in ipairs({
		{ Vector3.new(12, 12.5, 0.3), at(westX, 7.25, -6) },
		{ Vector3.new(12, 12.5, 0.3), at(westX, 7.25, 6) },
		{ Vector3.new(0.3, 12.5, 12), at(westX + 6, 7.25, 0) },
	}) do
		newPart(cage, { Name = "Glass", Size = spec[1], Position = spec[2], Color = rgb(180, 200, 196), Material = MAT.Glass, Transparency = 0.7 })
	end
	for _, z in ipairs({ -4, -2, 0, 2, 4 }) do
		newPart(cage, { Name = "Bar", Size = Vector3.new(0.2, 12.5, 0.2), Position = at(westX + 6.2, 7.25, z), Color = rgb(60, 62, 60), Material = MAT.MetalPlain })
	end
	local specimenLight = newPart(cage, { Name = "SpecimenLight", Size = Vector3.new(1, 0.2, 1), Position = at(westX, HEIGHT - 0.2, 0), Color = rgb(120, 20, 16), Material = MAT.Neon, CanCollide = false })
	local red = Instance.new("SpotLight")
	red.Face = Enum.NormalId.Bottom
	red.Color = rgb(255, 60, 40)
	red.Brightness = 2.4
	red.Range = 18
	red.Angle = 50
	red.Parent = specimenLight
	-- The real creature rig, frozen mid-listen with its fins half open.
	local specimen = MonsterModel.build(CFrame.lookAt(at(westX, 1, 0), at(westX + 10, 1, 0)), o.Y + 1)
	for _, d in ipairs(specimen:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("Humanoid") then
			d:Destroy()
		end
	end
	specimen.Name = "Specimen"
	specimen.Parent = cage
	local placard = newPart(cage, { Name = "Placard", Size = Vector3.new(4.5, 2.2, 0.2), CFrame = facing(westX + 7, 3.2, -4, westX + 20, -4) * CFrame.Angles(math.rad(-20), 0, 0), Color = rgb(40, 40, 36) })
	surfaceText(placard, Enum.NormalId.Front, "SPECIMEN 01\nTHE LISTENER\nno eyes - it hunts by sound", rgb(235, 225, 190), rgb(40, 40, 36))

	-- Centre: footstep test floor -----------------------------------------------------------
	local strips = {
		{ "Carpet", P.FloorColors.Carpet, MAT.Carpet, "CARPET - quiet" },
		{ "Tile", P.FloorColors.Tile, MAT.Tile, "TILE" },
		{ "Metal", P.FloorColors.Metal, MAT.Metal, "METAL - LOUD" },
	}
	for k, strip in ipairs(strips) do
		local x = (k - 2) * 6
		local floor = newPart(folder, {
			Name = "TestStrip" .. strip[1],
			Size = Vector3.new(5.6, 0.1, 18),
			Position = at(x, 0.05, -2),
			Color = strip[2],
			Material = strip[3],
		})
		floor:SetAttribute("Surface", strip[1])
		local sign = newPart(folder, { Name = "StripLabel", Size = Vector3.new(5.4, 0.1, 1.6), Position = at(x, 0.12, 8.2), Color = rgb(30, 30, 28), CanCollide = false })
		surfaceText(sign, Enum.NormalId.Top, strip[4], rgb(232, 196, 96), rgb(30, 30, 28))
	end
	board(folder, facing(0, 4, -11.5, 0, 0) * CFrame.Angles(math.rad(-10), 0, 0), Vector2.new(17, 3), "LISTEN TO YOUR FEET", "Walk, sprint and crouch across the strips. Down there, it hears what you hear.")
	newPart(folder, { Name = "SignPost", Size = Vector3.new(0.3, 3, 0.3), Position = at(0, 1.5, -11.8), Color = rgb(60, 60, 60) })

	-- East: briefing boards -----------------------------------------------------------------
	local eastX = WIDTH / 2 - 0.7
	board(folder, facing(eastX, 6.5, -12, 0, -12), Vector2.new(11, 6.5), "1. SOUND",
		"Crouch and creep: totally silent.\nCrouch + Shift: faster, but it hears you up close.\nSprinting and metal floors carry far. Thrown bottles lure it away.")
	board(folder, facing(eastX, 6.5, 0, 0, 0), Vector2.new(11, 6.5), "2. HIDING",
		"Lockers hide you, they do not save you.\nIf it saw you get in, it will check.\nCatch your breath first - it hears panting.")
	board(folder, facing(eastX, 6.5, 12, 0, 12), Vector2.new(11, 6.5), "3. TEAMWORK",
		"Downed teammates can be revived (hold E).\nThe elevator alarm draws it in.\nNobody escapes if nobody waits.")

	-- Practice locker (north-east corner) ---------------------------------------------------
	local lockerPos = at(WIDTH / 2 - 2.2, 0, -DEPTH / 2 + 6)
	local practice = MapBuilder.buildLocker(folder, CFrame.lookAt(lockerPos, lockerPos + Vector3.new(-1, 0, 0)))
	self.practiceLocker = practice
	local tag = newPart(folder, { Name = "PracticeSign", Size = Vector3.new(0.2, 1.2, 3), Position = lockerPos + Vector3.new(-1.4, 8.4, 0), Color = rgb(40, 40, 36) })
	surfaceText(tag, Enum.NormalId.Left, "PRACTICE LOCKER", rgb(232, 196, 96), rgb(40, 40, 36))

	-- South: staff lounge + spawn ------------------------------------------------------------
	local southZ = DEPTH / 2
	newPart(folder, { Name = "Rug", Size = Vector3.new(22, 0.05, 12), Position = at(0, 0.03, southZ - 9), Color = rgb(96, 52, 44), Material = MAT.Fabric, CanCollide = false })
	for _, x in ipairs({ -8, 8 }) do
		newPart(folder, { Name = "Couch", Size = Vector3.new(8, 2.2, 2.8), CFrame = facing(x, 1.1, southZ - 3.2, x, 0), Color = rgb(110, 70, 56), Material = MAT.Fabric })
		newPart(folder, { Name = "CouchBack", Size = Vector3.new(8, 2, 0.6), CFrame = facing(x, 2.6, southZ - 2, x, 0), Color = rgb(100, 62, 50), Material = MAT.Fabric })
	end
	Props.table(folder, facing(0, 0, southZ - 8, 0, 0), { range = function(_, a, b)
		return (a + b) / 2
	end })
	Props.vending(folder, facing(-WIDTH / 2 + 4, 0, southZ - 4, 0, southZ - 4))
	Props.cooler(folder, facing(WIDTH / 2 - 4, 0, southZ - 4, 0, southZ - 4))
	for _, x in ipairs({ -16, 16 }) do
		Props.plant(folder, CFrame.new(at(x, 0, southZ - 2.5)))
	end
	local title = newPart(folder, { Name = "TitleSign", Size = Vector3.new(26, 5, 0.3), CFrame = facing(0, 9.5, southZ - 0.7, 0, 0), Color = rgb(28, 30, 26) })
	surfaceText(title, Enum.NormalId.Front, "DEAD AIR", rgb(235, 225, 190), rgb(28, 30, 26))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 6)
	spawn.Position = at(0, 0.05, southZ - 14)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	self.spawnCFrame = CFrame.lookAt(at(0, 3.5, southZ - 14), at(0, 3.5, -DEPTH / 2))

	folder.Parent = Workspace
	return self
end

function Lobby:isOnPad(position)
	local localPos = self.padZone.CFrame:PointToObjectSpace(position)
	local half = self.padZone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

function Lobby:setStatus(text)
	if self.statusLabel.Text ~= text then
		self.statusLabel.Text = text
	end
end

function Lobby:setRecord(text)
	self.recordLabel.Text = text
end

-- Practice locker: climb in and out without any of the run's rules.
function Lobby:wirePracticeLocker(playerService)
	local locker = self.practiceLocker
	local occupant
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hide"
	prompt.ObjectText = "Practice Locker"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight = false
	prompt.Parent = locker.promptPart
	local function release()
		local character = occupant and occupant.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			character:PivotTo(locker.exitCFrame)
			root.Anchored = false
		end
		if occupant then
			occupant:SetAttribute("DA_Hidden", false)
		end
		occupant = nil
		prompt.ActionText = "Hide"
	end
	prompt.Triggered:Connect(function(player)
		local state = playerService.get(player)
		if not state or state.inRound then
			return
		end
		if occupant == player then
			release()
			return
		end
		if occupant and occupant.Parent then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - locker.promptPart.Position).Magnitude > 9 then
			return
		end
		occupant = player
		root.Anchored = true
		character:PivotTo(locker.insideCFrame)
		player:SetAttribute("DA_Hidden", true)
		prompt.ActionText = "Leave"
	end)
	self.releasePractice = function(player)
		if occupant == player then
			release()
		end
	end
end

return LobbyBuilder
