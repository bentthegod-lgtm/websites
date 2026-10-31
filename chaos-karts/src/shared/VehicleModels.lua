--[[
	VehicleModels - builds a kart Model from a vehicle definition (Vehicles/*).

	Every kart is the same rig:
	  Chassis   the invisible physics box (KartStats.Hitbox), Anchored, CanCollide /
	            CanQuery / CanTouch off. The kart controller moves ONLY this part
	            (kinematic CFrame movement); everything else is welded to it.
	  Body      an invisible, massless hub Weld-ed to the chassis; its C0 carries the
	            visual lean, drift angle and landing squash. All cosmetic parts are welded
	            to it (massless, CanCollide off).
	  Wheels    each on its own Weld to the chassis (C0 = spin + front-wheel steer).
	  Attachments for drift sparks (rear wheels) and boost flames (exhaust).

	The builder `b` passed to a vehicle's Build(b): b:box / b:wedge / b:ball / b:cylinder
	(name, size, localCFrame, color, material), b:wheels(spec), b:driver(localCFrame).
	Local space: y = 0 is the chassis centre, the ground is at y = -RideHeight, -Z is the
	nose.
]]

local KartStats = require(script.Parent.Config.KartStats)
local VehicleRegistry = require(script.Parent.Vehicles.Registry)
local Parts = require(script.Parent.Parts)

local VehicleModels = {}

local rgb = Color3.fromRGB

local function color(c)
	if typeof(c) == "Color3" then
		return c
	end
	return rgb(c[1], c[2], c[3])
end

local Builder = {}
Builder.__index = Builder

function Builder:_part(name, shapeClass, size, cf, col, material, shape)
	local part = Parts.new({
		Class = shapeClass,
		Name = name,
		Size = size,
		CFrame = self.origin * cf,
		Color = color(col),
		Material = if material then Parts.material(material) else Enum.Material.SmoothPlastic,
		Shape = shape,
		CanCollide = false,
		Anchored = false,
		Parent = self.model,
	})
	Parts.weldCosmetic(part, self.body)
	self.count += 1
	return part
end

function Builder:box(name, size, cf, col, material)
	return self:_part(name, "Part", size, cf, col, material)
end

function Builder:wedge(name, size, cf, col, material)
	return self:_part(name, "WedgePart", size, cf, col, material)
end

function Builder:ball(name, size, cf, col, material)
	return self:_part(name, "Part", size, cf, col, material, Enum.PartType.Ball)
end

function Builder:cylinder(name, length, diameter, cf, col, material)
	return self:_part(name, "Part", Vector3.new(length, diameter, diameter), cf, col, material, Enum.PartType.Cylinder)
end

function Builder:wheels(spec)
	local y = -KartStats.RideHeight + spec.radius
	for _, w in ipairs({
		{ x = -spec.track, z = spec.front, front = true, width = spec.width },
		{ x = spec.track, z = spec.front, front = true, width = spec.width },
		{ x = -spec.track, z = spec.rear, front = false, width = spec.rearWidth or spec.width },
		{ x = spec.track, z = spec.rear, front = false, width = spec.rearWidth or spec.width },
	}) do
		local hub = Parts.new({ Name = "WheelHub", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = self.origin * CFrame.new(w.x, y, w.z), Transparency = 1, CanCollide = false, Anchored = false, Parent = self.model })
		hub.Massless = true
		hub.CanQuery = false
		hub.CanTouch = false
		local weld = Instance.new("Weld")
		weld.Part0 = self.chassis
		weld.Part1 = hub
		weld.C0 = CFrame.new(w.x, y, w.z)
		weld.Parent = hub
		local function add(name, size, cf, col, material)
			local part = Parts.new({ Name = name, Shape = Enum.PartType.Cylinder, Size = size, CFrame = hub.CFrame * cf, Color = col, Material = material or Enum.Material.SmoothPlastic, CanCollide = false, Anchored = false, Parent = self.model })
			Parts.weldCosmetic(part, hub)
			self.count += 1
		end
		add("Tire", Vector3.new(w.width, spec.radius * 2, spec.radius * 2), CFrame.new(), rgb(28, 28, 32))
		add("Rim", Vector3.new(w.width + 0.06, spec.radius * 1.15, spec.radius * 1.15), CFrame.new(), color(self.colors.Metal), Enum.Material.Metal)
		table.insert(self.rig.wheels, { weld = weld, base = weld.C0, front = w.front, radius = spec.radius, spin = 0 })
		if not w.front then
			local a = Instance.new("Attachment")
			a.Name = "SparkPoint"
			a.Position = Vector3.new(w.x, -KartStats.RideHeight + 0.2, w.z + spec.radius * 0.6)
			a.Parent = self.chassis
			table.insert(self.rig.sparks, a)
		end
	end
	local exhaust = Instance.new("Attachment")
	exhaust.Name = "Exhaust"
	exhaust.Position = Vector3.new(0, 0.5, KartStats.Hitbox.Z / 2 + 0.6)
	exhaust.Parent = self.chassis
	self.rig.exhaust = exhaust
end

function Builder:driver(cf)
	local suit = self.driverColor
	self:box("DriverBody", Vector3.new(1.9, 1.9, 1.2), cf * CFrame.new(0, 0.9, 0.2), suit)
	for _, side in ipairs({ -1, 1 }) do
		self:box("DriverArm", Vector3.new(0.55, 0.55, 1.8), cf * CFrame.new(side * 1.05, 1.2, -0.7) * CFrame.Angles(math.rad(20), 0, 0), suit)
	end
	self:ball("Helmet", Vector3.new(1.9, 1.9, 1.9), cf * CFrame.new(0, 2.65, 0.1), rgb(250, 250, 250))
	self:box("Visor", Vector3.new(1.5, 0.6, 0.3), cf * CFrame.new(0, 2.7, -0.75), rgb(30, 34, 46), "Glass")
	self:box("HelmetStripe", Vector3.new(0.4, 0.2, 1.95), cf * CFrame.new(0, 3.55, 0.1), suit)
end

--[[
	VehicleModels.build(vehicleId, opts) -> model, rig
	opts: cframe, parent, name, driverColor (Color3 or {r,g,b}), label (name tag text),
	labelColor.
]]
function VehicleModels.build(vehicleId, opts)
	opts = opts or {}
	local def = VehicleRegistry.get(vehicleId)
	local origin = opts.cframe or CFrame.new()
	local model = Instance.new("Model")
	model.Name = opts.name or ("Kart_" .. def.Id)
	model:SetAttribute("Vehicle", def.Id)
	local hb = KartStats.Hitbox
	local chassis = Parts.new({ Name = "Chassis", Size = Vector3.new(hb.X, hb.Y, hb.Z), CFrame = origin, Transparency = 1, CanCollide = false, Anchored = true, Parent = model })
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.CastShadow = false
	model.PrimaryPart = chassis
	local body = Parts.new({ Name = "Body", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = origin, Transparency = 1, CanCollide = false, Anchored = false, Parent = model })
	body.Massless = true
	body.CanQuery = false
	body.CanTouch = false
	local bodyWeld = Instance.new("Weld")
	bodyWeld.Part0 = chassis
	bodyWeld.Part1 = body
	bodyWeld.C0 = CFrame.new()
	bodyWeld.Parent = body
	local colors = table.clone(def.Colors)
	local rig = { model = model, chassis = chassis, bodyWeld = bodyWeld, wheels = {}, sparks = {}, exhaust = nil, vehicle = def.Id }
	local b = setmetatable({
		model = model,
		chassis = chassis,
		body = body,
		origin = origin,
		colors = colors,
		driverColor = color(opts.driverColor or def.Colors.Body),
		rig = rig,
		count = 0,
	}, Builder)
	def.Build(b)
	rig.partCount = b.count + 2
	if opts.label then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameTag"
		gui.Size = UDim2.fromOffset(200, 34)
		gui.StudsOffset = Vector3.new(0, 6.5, 0)
		gui.MaxDistance = 220
		gui.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = opts.label
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = if opts.labelColor then color(opts.labelColor) else Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = chassis
		rig.label = label
	end
	if opts.parent then
		model.Parent = opts.parent
	end
	return model, rig
end

--[[
	Visual animation (no physics): wheel spin and steer, body lean into turns, drift angle,
	landing squash. look = { speed, steer (-1..1), drift (-1/0/1), squash, air, dt }.
]]
function VehicleModels.animate(rig, look)
	local dt = look.dt or 1 / 60
	for _, w in ipairs(rig.wheels) do
		w.spin = (w.spin + (look.speed or 0) * dt / w.radius) % (math.pi * 2)
		local steerAngle = if w.front then -(look.steer or 0) * math.rad(24) else 0
		w.weld.C0 = w.base * CFrame.Angles(0, steerAngle, 0) * CFrame.Angles(-w.spin, 0, 0)
	end
	rig.lean = rig.lean or 0
	rig.slip = rig.slip or 0
	local wantLean = -(look.steer or 0) * math.rad(7) * math.clamp((look.speed or 0) / KartStats.TopSpeed, 0, 1)
	local wantSlip = (look.drift or 0) * math.rad(-22)
	local k = math.min(1, dt * 10)
	rig.lean += (wantLean - rig.lean) * k
	rig.slip += (wantSlip - rig.slip) * k
	local squash = look.squash or 0
	rig.bodyWeld.C0 = CFrame.new(0, -squash * 1.4, 0) * CFrame.Angles(0, rig.slip, rig.lean) * CFrame.Angles(squash * 0.15, 0, 0)
end

return VehicleModels
