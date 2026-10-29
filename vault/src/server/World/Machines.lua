--[[
	Machines - the interactive equipment: deposit machines, elevator cabins, upgrade
	terminals and leaderboard boards. Each returns a record the services use (prompt,
	zone, display labels, moving parts the client animates).

	Prompts all use E / gamepad X / tap. The collect key is also E, so the client's
	collect input yields to a visible ProximityPrompt (InputController).
]]

local Props = require(script.Parent.Props)

local Machines = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local C = Props.Colors
local UP = CFrame.Angles(0, 0, math.pi / 2)

local function prompt(parent, action, object, distance)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	p.Parent = parent
	return p
end
Machines.prompt = prompt

--[[
	Deposit machine. cf: centre of the machine's footprint on the floor, LookVector = the
	front (where players stand). Returns { model, prompt, zone (CFrame, size), screen,
	amount, lights = { parts }, drum, chute (world position), id }.
]]
function Machines.deposit(b, cf, id, accent)
	local model = Instance.new("Model")
	model.Name = "DepositMachine_" .. id
	model.Parent = b.parent
	local mb = Props.builder(model)
	local front = -1 -- local -Z is the front
	mb.part({ Name = "Plinth", Size = Vector3.new(9, 0.6, 5.5), CFrame = cf * CFrame.new(0, 0.3, 0), Color = C.SteelDark, Material = M.DiamondPlate })
	mb.part({ Name = "Cabinet", Size = Vector3.new(7.6, 7, 3.4), CFrame = cf * CFrame.new(0, 4.1, 0.8), Color = C.Steel, Material = M.Metal })
	mb.deco({ Name = "CabinetTrim", Size = Vector3.new(7.8, 0.3, 3.6), CFrame = cf * CFrame.new(0, 7.65, 0.8), Color = accent, Material = M.Metal })
	mb.deco({ Name = "SidePanelL", Size = Vector3.new(0.2, 5.6, 2.6), CFrame = cf * CFrame.new(-3.9, 4, 0.8), Color = C.SteelLight, Material = M.DiamondPlate })
	mb.deco({ Name = "SidePanelR", Size = Vector3.new(0.2, 5.6, 2.6), CFrame = cf * CFrame.new(3.9, 4, 0.8), Color = C.SteelLight, Material = M.DiamondPlate })
	-- Input hopper: a slanted funnel feeding a dark slot.
	mb.part({ Name = "HopperBack", Size = Vector3.new(4.6, 0.3, 2.4), CFrame = cf * CFrame.new(0, 3.2, front * 1.4) * CFrame.Angles(math.rad(-35), 0, 0), Color = C.SteelLight, Material = M.Metal })
	for _, x in ipairs({ -2.3, 2.3 }) do
		mb.part({ Name = "HopperSide", Size = Vector3.new(0.3, 1.6, 2.4), CFrame = cf * CFrame.new(x, 3.4, front * 1.4), Color = C.SteelLight, Material = M.Metal })
	end
	local slot = mb.deco({ Name = "Chute", Size = Vector3.new(3.6, 0.9, 0.3), CFrame = cf * CFrame.new(0, 3.9, front * 0.92), Color = C.Black, Material = M.SmoothPlastic })
	-- Rollers inside the chute (spun by the client while depositing).
	local drum = mb.deco({ Name = "Drum", Size = Vector3.new(3.4, 0.7, 0.7), CFrame = cf * CFrame.new(0, 3.9, front * 0.5), Color = C.SteelLight, Material = M.Metal, Shape = Enum.PartType.Cylinder })
	-- Screen.
	local screen = mb.deco({ Name = "Screen", Size = Vector3.new(5.2, 2.2, 0.2), CFrame = cf * CFrame.new(0, 6.1, front * 0.95) * CFrame.Angles(math.rad(-12), 0, 0), Color = rgb(12, 24, 20), Material = M.SmoothPlastic })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = screen
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.4)
	title.Text = "DEPOSIT LOOT"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = rgb(120, 255, 170)
	title.Parent = gui
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Position = UDim2.fromScale(0, 0.42)
	amount.Size = UDim2.fromScale(1, 0.5)
	amount.Text = "READY"
	amount.TextScaled = true
	amount.Font = Enum.Font.GothamBold
	amount.TextColor3 = rgb(230, 255, 236)
	amount.Parent = gui
	-- Indicator lamps along the top and a status light.
	local lights = {}
	for i = 1, 5 do
		local lamp = mb.deco({ Name = "Lamp" .. i, Size = Vector3.new(0.5, 0.5, 0.3), CFrame = cf * CFrame.new((i - 3) * 1.2, 7.4, front * 0.95), Color = rgb(40, 90, 60), Material = M.Neon })
		table.insert(lights, lamp)
	end
	local status = mb.deco({ Name = "StatusLight", Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * CFrame.new(3.2, 2.4, front * 0.95), Color = C.Green, Material = M.Neon, Shape = Enum.PartType.Ball })
	local glow = Instance.new("PointLight")
	glow.Color = rgb(120, 255, 170)
	glow.Range = 12
	glow.Brightness = 0.8
	glow.Shadows = false
	glow.Parent = screen
	-- Counter dial + vents.
	mb.deco({ Name = "Dial", Size = Vector3.new(0.2, 1.1, 1.1), CFrame = cf * CFrame.new(-3.2, 2.4, front * 0.9) * CFrame.Angles(0, math.rad(90), 0), Color = C.White, Material = M.SmoothPlastic, Shape = Enum.PartType.Cylinder })
	for i = 0, 3 do
		mb.deco({ Name = "Vent", Size = Vector3.new(2.6, 0.12, 0.1), CFrame = cf * CFrame.new(0, 1.3 + i * 0.3, front * 0.92), Color = C.Black })
	end
	-- Hazard guards on both sides (protective barriers around the moving rollers).
	for _, x in ipairs({ -4.6, 4.6 }) do
		mb.part({ Name = "Guard", Size = Vector3.new(0.3, 3.2, 0.3), CFrame = cf * CFrame.new(x, 2.2, front * 2.6), Color = C.Hazard, Material = M.Metal })
		mb.deco({ Name = "GuardRail", Size = Vector3.new(0.25, 0.25, 2.2), CFrame = cf * CFrame.new(x, 3.6, front * 1.6), Color = C.Hazard, Material = M.Metal })
	end
	-- Auto-deposit zone painted on the floor in front.
	local zoneCF = cf * CFrame.new(0, 0, front * 6.2)
	local zoneSize = Vector3.new(8, 6, 6)
	Props.hazardStripes(mb, zoneCF * CFrame.new(0, 0, front * 3), 8, 0.4)
	Props.hazardStripes(mb, zoneCF * CFrame.new(0, 0, 3), 8, 0.4)
	Props.floorText(mb, zoneCF * CFrame.Angles(0, math.pi, 0), 7, 4.4, "DEPOSIT ZONE", rgb(236, 190, 40))
	local promptPart = mb.deco({ Name = "PromptPart", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 3.6, front * 1.8), Transparency = 1 })
	local p = prompt(promptPart, "Deposit", "Deposit Machine", 11)
	b.count += mb.count
	model:SetAttribute("MachineId", id)
	return {
		id = id,
		model = model,
		prompt = p,
		zone = { cframe = zoneCF * CFrame.new(0, 3, 0), size = zoneSize },
		screen = screen,
		title = title,
		amount = amount,
		lights = lights,
		status = status,
		drum = drum,
		chute = slot.CFrame.Position,
		cframe = cf,
	}
end

--[[
	Elevator cabin. cf: the centre of the cabin floor, LookVector = out of the doors (toward
	the arrival hall). Returns { model, prompt, arrival (CFrame where riders appear),
	doors = { left, right } (Models, open), display (TextLabel above the door), panel }.
]]
function Machines.elevator(b, cf, depthCode, accent)
	local model = Instance.new("Model")
	model.Name = "Elevator_" .. depthCode
	model.Parent = b.parent
	local eb = Props.builder(model)
	local W, D, H = 14, 13, 11
	eb.part({ Name = "CabinFloor", Size = Vector3.new(W, 0.4, D), CFrame = cf * CFrame.new(0, -0.2, 0), Color = C.SteelDark, Material = M.DiamondPlate })
	eb.part({ Name = "CabinCeiling", Size = Vector3.new(W, 0.4, D), CFrame = cf * CFrame.new(0, H, 0), Color = C.Steel, Material = M.Metal })
	local lightPanel = eb.deco({ Name = "CabinLight", Size = Vector3.new(W - 4, 0.1, D - 4), CFrame = cf * CFrame.new(0, H - 0.25, 0), Color = rgb(255, 246, 228), Material = M.Neon })
	local cabinLight = Instance.new("SurfaceLight")
	cabinLight.Face = Enum.NormalId.Bottom
	cabinLight.Brightness = 1.6
	cabinLight.Range = 14
	cabinLight.Color = rgb(255, 240, 220)
	cabinLight.Parent = lightPanel
	for _, x in ipairs({ -W / 2, W / 2 }) do
		eb.part({ Name = "CabinWall", Size = Vector3.new(0.4, H, D), CFrame = cf * CFrame.new(x, H / 2, 0), Color = C.Steel, Material = M.Metal })
		eb.deco({ Name = "Handrail", Size = Vector3.new(0.25, 0.25, D - 2), CFrame = cf * CFrame.new(x - math.sign(x) * 0.5, 3.4, 0), Color = accent, Material = M.Metal })
		for _, z in ipairs({ -D / 2 + 1, D / 2 - 1 }) do
			eb.deco({ Name = "RailBracket", Size = Vector3.new(0.6, 0.2, 0.2), CFrame = cf * CFrame.new(x - math.sign(x) * 0.25, 3.4, z), Color = C.SteelLight, Material = M.Metal })
		end
	end
	-- Back wall: a reinforced window into the shaft (cables and rails run up and down).
	local back = D / 2
	eb.part({ Name = "BackWallLow", Size = Vector3.new(W, 3.5, 0.4), CFrame = cf * CFrame.new(0, 1.75, back), Color = C.Steel, Material = M.Metal })
	eb.part({ Name = "BackWallHigh", Size = Vector3.new(W, 1.5, 0.4), CFrame = cf * CFrame.new(0, H - 0.75, back), Color = C.Steel, Material = M.Metal })
	eb.part({ Name = "ShaftWindow", Size = Vector3.new(W - 2, H - 5, 0.2), CFrame = cf * CFrame.new(0, 3.5 + (H - 5) / 2, back), Color = C.Glass, Material = M.Glass, Transparency = 0.6, CastShadow = false })
	for _, x in ipairs({ -W / 2 + 0.6, 0, W / 2 - 0.6 }) do
		eb.deco({ Name = "WindowBar", Size = Vector3.new(0.3, H - 5, 0.35), CFrame = cf * CFrame.new(x, 3.5 + (H - 5) / 2, back - 0.1), Color = C.SteelDark, Material = M.Metal })
	end
	-- Floor-selection panel (right wall, inside).
	local panel = eb.deco({ Name = "FloorPanel", Size = Vector3.new(0.3, 3, 1.6), CFrame = cf * CFrame.new(W / 2 - 0.4, 4.6, -D / 2 + 2.5), Color = C.SteelDark, Material = M.Metal })
	for i = 1, 7 do
		eb.deco({ Name = "FloorButton" .. i, Size = Vector3.new(0.1, 0.28, 0.28), CFrame = cf * CFrame.new(W / 2 - 0.58, 3.4 + (i - 1) * 0.36, -D / 2 + 2.5), Color = rgb(255, 220, 120), Material = M.Neon })
	end
	Props.text(panel, Enum.NormalId.Left, "FLOORS", { PPS = 40, Color = rgb(255, 220, 120) })
	-- Doors: two leaves that slide apart (open as built; the riding client closes them).
	local function leaf(name, x)
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = model
		local lb = Props.builder(m)
		local main = lb.part({ Name = "Leaf", Size = Vector3.new(W / 2 - 1, H - 1, 0.4), CFrame = cf * CFrame.new(x, (H - 1) / 2, -D / 2 - 0.4), Color = C.SteelLight, Material = M.Metal, CanCollide = false })
		lb.deco({ Name = "LeafStripe", Size = Vector3.new(W / 2 - 1, 0.4, 0.45), CFrame = cf * CFrame.new(x, 3.4, -D / 2 - 0.4), Color = accent, Material = M.Metal })
		m.PrimaryPart = main
		eb.count += lb.count
		return m
	end
	local doorL = leaf("DoorL", -W / 2 - (W / 2 - 1) / 2 + 0.6)
	local doorR = leaf("DoorR", W / 2 + (W / 2 - 1) / 2 - 0.6)
	model:SetAttribute("DoorClosedOffset", W / 2 - 0.6) -- slide distance from open to closed
	-- Prompt at the panel.
	local promptPart = eb.deco({ Name = "PromptPart", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(W / 2 - 2, 4.6, -D / 2 + 2.5), Transparency = 1 })
	local p = prompt(promptPart, "Select Floor", "Elevator " .. depthCode, 9)
	b.count += eb.count
	return {
		model = model,
		prompt = p,
		arrival = cf * CFrame.new(0, 3, 1.5), -- facing out of the doors (the cabin faces the room)
		doors = { left = doorL, right = doorR },
		panel = panel,
		cframe = cf,
		size = Vector3.new(W, H, D),
	}
end

-- Upgrade terminal kiosk. cf on the floor, LookVector = front. Returns { model, prompt }.
function Machines.terminal(b, cf, accent, big)
	local model = Instance.new("Model")
	model.Name = "UpgradeTerminal"
	model.Parent = b.parent
	local tb = Props.builder(model)
	tb.part({ Name = "Base", Size = Vector3.new(4, 0.5, 3), CFrame = cf * CFrame.new(0, 0.25, 0), Color = C.SteelDark, Material = M.DiamondPlate })
	tb.part({ Name = "Pedestal", Size = Vector3.new(2.4, 3.6, 1.6), CFrame = cf * CFrame.new(0, 2.3, 0.3), Color = C.Steel, Material = M.Metal })
	local screen = tb.deco({ Name = "Screen", Size = Vector3.new(3.4, 2.2, 0.2), CFrame = cf * CFrame.new(0, 4.8, 0) * CFrame.Angles(math.rad(-20), 0, 0), Color = rgb(14, 18, 30), Material = M.SmoothPlastic })
	Props.text(screen, Enum.NormalId.Front, "UPGRADES", { PPS = 60, Color = accent, Brightness = 2 })
	tb.deco({ Name = "Keyboard", Size = Vector3.new(2.2, 0.15, 0.8), CFrame = cf * CFrame.new(0, 4.15, -0.7) * CFrame.Angles(math.rad(-15), 0, 0), Color = C.Black })
	tb.deco({ Name = "Trim", Size = Vector3.new(2.5, 0.2, 1.7), CFrame = cf * CFrame.new(0, 4.1, 0.3), Color = accent, Material = M.Metal })
	local glow = Instance.new("PointLight")
	glow.Color = accent
	glow.Range = 10
	glow.Brightness = 0.8
	glow.Shadows = false
	glow.Parent = screen
	if big then
		-- The starting area's station: an arch with a sign so it reads from across the hall.
		for _, x in ipairs({ -3.6, 3.6 }) do
			tb.part({ Name = "ArchPost", Size = Vector3.new(0.8, 9, 0.8), CFrame = cf * CFrame.new(x, 4.5, 0.8), Color = C.SteelDark, Material = M.Metal })
		end
		local top = tb.deco({ Name = "ArchSign", Size = Vector3.new(8.4, 1.6, 0.6), CFrame = cf * CFrame.new(0, 9.4, 0.8), Color = C.SteelDark, Material = M.Metal })
		Props.text(top, Enum.NormalId.Front, "UPGRADE STATION", { PPS = 40, Color = accent })
		tb.deco({ Name = "ArchTrim", Size = Vector3.new(8.6, 0.25, 0.7), CFrame = cf * CFrame.new(0, 8.5, 0.8), Color = accent, Material = M.Neon })
	end
	local promptPart = tb.deco({ Name = "PromptPart", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 3.6, -1.2), Transparency = 1 })
	local p = prompt(promptPart, "Upgrades", "Upgrade Terminal", 10)
	b.count += tb.count
	return { model = model, prompt = p, cframe = cf }
end

-- Leaderboard board on a wall. cf: board centre, LookVector = out of the wall.
function Machines.leaderboard(b, cf, title)
	local back = b.deco({ Name = "Leaderboard", Size = Vector3.new(9, 11, 0.4), CFrame = cf, Color = rgb(20, 22, 26), Material = M.Metal })
	b.deco({ Name = "BoardTrim", Size = Vector3.new(9.4, 0.3, 0.5), CFrame = cf * CFrame.new(0, 5.6, 0), Color = C.Gold, Material = M.Metal })
	b.deco({ Name = "BoardTrim", Size = Vector3.new(9.4, 0.3, 0.5), CFrame = cf * CFrame.new(0, -5.6, 0), Color = C.Gold, Material = M.Metal })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = back
	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 0.13)
	head.Text = title
	head.TextScaled = true
	head.Font = Enum.Font.GothamBlack
	head.TextColor3 = rgb(255, 204, 80)
	head.Parent = gui
	local rows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0.05, 0, 0.15 + (i - 1) * 0.083, 0)
		row.Size = UDim2.new(0.9, 0, 0.075, 0)
		row.Text = string.format("%d.  ---", i)
		row.TextScaled = true
		row.Font = Enum.Font.GothamMedium
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i <= 3 then rgb(255, 232, 170) else rgb(225, 225, 225)
		row.Parent = gui
		rows[i] = row
	end
	return { part = back, rows = rows }
end

-- The shared elevator shaft column behind the cabins: guide rails, hoist cables, a
-- counterweight and shaft lights, running the whole height of the vault.
function Machines.shaft(b, top, bottom, z, depths)
	local height = top - bottom
	local mid = (top + bottom) / 2
	for _, x in ipairs({ -10, 10 }) do
		b.part({ Name = "ShaftWall", Size = Vector3.new(1, height, 12), CFrame = CFrame.new(x, mid, z - 2), Color = rgb(70, 70, 70), Material = M.Concrete })
	end
	b.part({ Name = "ShaftBack", Size = Vector3.new(21, height, 1), CFrame = CFrame.new(0, mid, z - 8.5), Color = rgb(64, 64, 64), Material = M.Concrete })
	for _, x in ipairs({ -6.5, 6.5 }) do
		b.deco({ Name = "GuideRail", Size = Vector3.new(0.5, height, 0.8), CFrame = CFrame.new(x, mid, z - 3), Color = C.SteelLight, Material = M.Metal })
	end
	for _, x in ipairs({ -1.2, -0.4, 0.4, 1.2 }) do
		b.deco({ Name = "HoistCable", Size = Vector3.new(height, 0.16, 0.16), CFrame = CFrame.new(x, mid, z - 4.5) * UP, Color = C.Black, Material = M.Metal, Shape = Enum.PartType.Cylinder, CastShadow = false })
	end
	for _, d in ipairs(depths) do
		-- A counterweight parked between floors and a strip light at every landing.
		b.deco({ Name = "Counterweight", Size = Vector3.new(3, 6, 1.2), CFrame = CFrame.new(4, d.y + 60, z - 7), Color = C.SteelDark, Material = M.DiamondPlate })
		local strip = b.deco({ Name = "ShaftLight", Size = Vector3.new(16, 0.3, 0.3), CFrame = CFrame.new(0, d.y + 12.5, z - 7.8), Color = rgb(255, 230, 190), Material = M.Neon })
		local l = Instance.new("PointLight")
		l.Range = 14
		l.Brightness = 0.8
		l.Shadows = false
		l.Color = rgb(255, 230, 190)
		l.Parent = strip
		local plate = b.deco({ Name = "LandingNumber", Size = Vector3.new(4, 2, 0.3), CFrame = CFrame.new(-5, d.y + 8, z - 7.9) * CFrame.Angles(0, math.pi, 0), Color = rgb(30, 30, 30), Material = M.Metal })
		Props.text(plate, Enum.NormalId.Front, d.code, { PPS = 30, Color = rgb(255, 220, 120) })
	end
end

return Machines
