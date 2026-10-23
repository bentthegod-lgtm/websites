--[[
	FlashlightModel - a chunky old maintenance flashlight built from Parts.

	Used twice: the server mounts one on every character (what other players see) and each
	client holds one in front of its camera as a first-person viewmodel. The lens part's
	Front face points along the beam; lights are parented to it.
]]

local FlashlightModel = {}

local BODY = Color3.fromRGB(58, 60, 56)
local GRIP = Color3.fromRGB(32, 32, 30)
local TRIM = Color3.fromRGB(170, 150, 90)
local LENS_OFF = Color3.fromRGB(70, 68, 60)

-- Returns model, lens. The model's pivot is the grip centre, LookVector = beam direction.
function FlashlightModel.build(name)
	local model = Instance.new("Model")
	model.Name = name or "Flashlight"

	local function part(partName, shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = partName
		p.Shape = shape
		p.Size = size
		-- Cylinders run along X in Roblox; turn them so they run along the beam (-Z).
		p.CFrame = offset * (if shape == Enum.PartType.Cylinder then CFrame.Angles(0, math.rad(90), 0) else CFrame.new())
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local cyl = Enum.PartType.Cylinder
	local grip = part("Grip", cyl, Vector3.new(1.1, 0.34, 0.34), CFrame.new(0, 0, 0.1), BODY)
	for i = -1, 1 do
		part("Rib", cyl, Vector3.new(0.06, 0.36, 0.36), CFrame.new(0, 0, 0.1 + i * 0.28), GRIP, Enum.Material.Rubber)
	end
	part("Tail", cyl, Vector3.new(0.12, 0.3, 0.3), CFrame.new(0, 0, 0.7), GRIP, Enum.Material.Rubber)
	part("Neck", cyl, Vector3.new(0.22, 0.42, 0.42), CFrame.new(0, 0, -0.55), BODY)
	part("Head", cyl, Vector3.new(0.34, 0.56, 0.56), CFrame.new(0, 0, -0.8), BODY)
	part("Bezel", cyl, Vector3.new(0.05, 0.6, 0.6), CFrame.new(0, 0, -0.98), TRIM)
	part("Switch", Enum.PartType.Block, Vector3.new(0.12, 0.08, 0.2), CFrame.new(0, 0.19, -0.15), Color3.fromRGB(150, 36, 30), Enum.Material.SmoothPlastic)

	-- The lens is a thin Block so its Front face (-Z) can carry the SpotLight.
	local lens = part("Lens", Enum.PartType.Block, Vector3.new(0.42, 0.42, 0.04), CFrame.new(0, 0, -1.01), LENS_OFF, Enum.Material.Glass)
	lens.Transparency = 0.1

	-- Weld everything to the grip so the model moves as one piece.
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= grip then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = grip
			weld.Part1 = p
			weld.Parent = p
		end
	end
	model.PrimaryPart = grip
	-- Pivot at the grip centre, facing down the beam (the grip itself is rotated).
	grip.PivotOffset = grip.CFrame:Inverse()
	return model, lens
end

-- Visual on/off state of the lens.
function FlashlightModel.setLens(lens, on, color)
	lens.Color = if on then (color or Color3.fromRGB(255, 244, 214)) else LENS_OFF
	lens.Material = if on then Enum.Material.Neon else Enum.Material.Glass
end

return FlashlightModel
