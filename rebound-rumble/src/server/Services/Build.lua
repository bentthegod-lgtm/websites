--[[
	Small part-construction helpers shared by the lobby and arena builders.
]]

local Build = {}

function Build.rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Build.material(name)
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

-- props: Size, CFrame, Color, Material, Shape, Transparency, CanCollide, Name, Reflectance
function Build.part(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = props.Name or "Part"
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.Color = props.Color or Color3.fromRGB(200, 200, 200)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	if props.Shape and p:IsA("Part") then
		p.Shape = props.Shape
	end
	p.Transparency = props.Transparency or 0
	p.CanCollide = props.CanCollide ~= false
	p.CastShadow = props.CastShadow ~= false
	if props.CanQuery == false then
		p.CanQuery = false
	end
	if props.CanTouch == false then
		p.CanTouch = false
	end
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	p.Parent = parent
	return p
end

-- A flat disc (cylinder lying on its side so its axis is vertical).
function Build.disc(parent, center, diameter, height, color, material, name)
	return Build.part(parent, {
		Name = name or "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	})
end

function Build.neon(parent, props)
	props.Material = Enum.Material.Neon
	props.CastShadow = false
	return Build.part(parent, props)
end

-- Invisible collision ring that keeps players inside a circular area.
function Build.barrierRing(parent, center, radius, height, segments)
	local folder = Instance.new("Folder")
	folder.Name = "Barrier"
	folder.Parent = parent
	segments = segments or 28
	local width = 2 * math.pi * radius / segments + 1
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * radius, height / 2, math.sin(a) * radius)
		Build.part(folder, {
			Name = "Wall",
			Size = Vector3.new(width, height, 2),
			CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)),
			Transparency = 1,
			CastShadow = false,
			CanQuery = false,
		})
	end
	return folder
end

function Build.light(part, color, range, brightness)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 16
	light.Brightness = brightness or 2
	light.Shadows = false
	light.Parent = part
	return light
end

function Build.sparkles(part, color, rate)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1.5, 3)
	emitter.Rate = rate or 6
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part
	return emitter
end

-- SurfaceGui with a single big TextLabel; returns the label.
function Build.sign(part, text, textColor, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.Parent = gui
	return label, gui
end

return Build
