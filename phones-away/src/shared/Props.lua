--[[
	Props - small part-built models: phones (per phone tier + skin) and desk decorations.
	All parts are anchored, non-colliding and non-queryable (purely visual).
]]

local Props = {}

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end
Props.rgb = rgb

-- Roblox forces Ball parts to a uniform size, so non-uniform "balls" (eyes, hair, cheeks)
-- use a Block with a built-in Sphere SpecialMesh instead (no imported assets).
local function shapeBall(p, size)
	if math.abs(size.X - size.Y) < 1e-3 and math.abs(size.Y - size.Z) < 1e-3 then
		p.Shape = Enum.PartType.Ball
		return
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function part(parent, name, size, cf, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in pairs(props or {}) do
		if k == "Shape" and v == Enum.PartType.Ball then
			shapeBall(p, (props and props.Size) or size)
		elseif k ~= "Size" or not (props and props.Shape == Enum.PartType.Ball) then
			p[k] = v
		end
	end
	if props and props.Size and props.Shape == Enum.PartType.Ball then
		p.Size = props.Size
	end
	p.Parent = parent
	return p
end
Props.part = part

local function material(name)
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

--[[
	Phone model. tier = UpgradeConfig tier table (Size, Color) or the ProPhone table.
	skin = CosmeticConfig skin item (Color / Material / Neon) or nil.
	The screen faces the model's -Z (LookVector). Returns model (PrimaryPart = Body).
]]
function Props.phone(tier, skin, cf)
	cf = cf or CFrame.new()
	local model = Instance.new("Model")
	model.Name = "Phone"
	local size = tier.Size or { 0.6, 1.2, 0.1 }
	local w, h, d = size[1], size[2], size[3]
	local bodyColor = if skin and skin.Color then rgb(skin.Color) else rgb(tier.Color or { 40, 40, 48 })
	local body = part(model, "Body", Vector3.new(w, h, d), cf, bodyColor, {
		Material = if skin and skin.Material then material(skin.Material) else Enum.Material.SmoothPlastic,
	})
	model.PrimaryPart = body
	local screen = part(model, "Screen", Vector3.new(w * 0.86, h * 0.84, 0.02), cf * CFrame.new(0, h * 0.02, -d / 2 - 0.011), Color3.fromRGB(150, 200, 255), {
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(170, 210, 255)
	light.Range = 7
	light.Brightness = 1.5
	light.Shadows = false
	light.Enabled = false
	light.Parent = screen
	part(model, "Camera", Vector3.new(0.12, 0.12, 0.03), cf * CFrame.new(w * 0.28, h * 0.38, d / 2 + 0.015), Color3.fromRGB(20, 20, 25))
	part(model, "Notch", Vector3.new(w * 0.3, 0.05, 0.025), cf * CFrame.new(0, h * 0.45, -d / 2 - 0.014), Color3.fromRGB(15, 15, 20))
	if skin and skin.Neon then
		part(model, "SkinStripe", Vector3.new(w * 0.9, 0.08, d + 0.02), cf * CFrame.new(0, -h * 0.3, 0), bodyColor:Lerp(Color3.new(1, 1, 1), 0.4), { Material = Enum.Material.Neon })
	end
	if tier.Name and string.find(tier.Name, "Flip", 1, true) then
		part(model, "Hinge", Vector3.new(w * 0.9, 0.06, d + 0.03), cf * CFrame.new(0, 0, 0), bodyColor:Lerp(Color3.new(0, 0, 0), 0.3))
	end
	if tier.Name and string.find(tier.Name, "Brick", 1, true) then
		part(model, "Antenna", Vector3.new(0.08, 0.35, 0.08), cf * CFrame.new(w * 0.3, h / 2 + 0.17, 0), Color3.fromRGB(30, 30, 30))
	end
	-- Selfie flash (enabled for a moment by PhoneService).
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Color = Color3.new(1, 1, 1)
	flash.Range = 18
	flash.Brightness = 6
	flash.Enabled = false
	flash.Parent = body
	return model
end

-- Applies how bright the screen glow is (phone case dims it).
function Props.setPhoneGlow(model, on, glowMultiplier)
	local screen = model:FindFirstChild("Screen")
	if not screen then
		return
	end
	local light = screen:FindFirstChild("Glow")
	if light then
		light.Enabled = on
		light.Brightness = 1.8 * (glowMultiplier or 1)
	end
	screen.Transparency = if on then 0 else 0.6
end

--[[
	Desk decoration by style. `cf` = point on the desk surface (top centre of the item base).
]]
function Props.decor(style, cf)
	local model = Instance.new("Model")
	model.Name = "Decor"
	if style == "Pencils" then
		part(model, "Cup", Vector3.new(0.5, 0.6, 0.5), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(80, 140, 230), { Shape = Enum.PartType.Cylinder, CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)) })
		local colors = { { 255, 205, 60 }, { 255, 90, 90 }, { 90, 200, 120 } }
		for i, c in ipairs(colors) do
			part(model, "Pencil", Vector3.new(0.08, 0.9, 0.08), cf * CFrame.new((i - 2) * 0.12, 0.65, (i % 2) * 0.08) * CFrame.Angles(0, 0, math.rad((i - 2) * 10)), rgb(c))
		end
	elseif style == "Plant" then
		part(model, "Pot", Vector3.new(0.55, 0.45, 0.55), cf * CFrame.new(0, 0.22, 0), Color3.fromRGB(200, 110, 70))
		part(model, "Cactus", Vector3.new(0.3, 0.7, 0.3), cf * CFrame.new(0, 0.75, 0), Color3.fromRGB(90, 170, 90), { Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4) })
		part(model, "Arm", Vector3.new(0.18, 0.35, 0.18), cf * CFrame.new(0.22, 0.85, 0), Color3.fromRGB(90, 170, 90))
		part(model, "Flower", Vector3.new(0.16, 0.16, 0.16), cf * CFrame.new(0, 1.0, 0), Color3.fromRGB(255, 120, 180), { Shape = Enum.PartType.Ball })
	elseif style == "Duck" then
		local yellow = Color3.fromRGB(255, 215, 60)
		part(model, "Body", Vector3.new(0.6, 0.45, 0.8), cf * CFrame.new(0, 0.23, 0), yellow, { Shape = Enum.PartType.Ball })
		part(model, "Head", Vector3.new(0.38, 0.38, 0.38), cf * CFrame.new(0, 0.55, -0.22), yellow, { Shape = Enum.PartType.Ball })
		part(model, "Beak", Vector3.new(0.2, 0.08, 0.16), cf * CFrame.new(0, 0.52, -0.44), Color3.fromRGB(255, 140, 40))
		part(model, "Eye", Vector3.new(0.06, 0.06, 0.06), cf * CFrame.new(0.12, 0.62, -0.36), Color3.new(0, 0, 0), { Shape = Enum.PartType.Ball })
	elseif style == "Apple" then
		part(model, "Apple", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(220, 40, 50), { Shape = Enum.PartType.Ball })
		part(model, "Stem", Vector3.new(0.05, 0.2, 0.05), cf * CFrame.new(0, 0.68, 0), Color3.fromRGB(90, 60, 30))
		part(model, "Leaf", Vector3.new(0.2, 0.04, 0.12), cf * CFrame.new(0.1, 0.72, 0), Color3.fromRGB(80, 180, 80))
	elseif style == "LavaLamp" then
		part(model, "Base", Vector3.new(0.45, 0.3, 0.45), cf * CFrame.new(0, 0.15, 0), Color3.fromRGB(180, 180, 190), { Material = Enum.Material.Metal })
		part(model, "Glass", Vector3.new(0.35, 0.8, 0.35), cf * CFrame.new(0, 0.7, 0), Color3.fromRGB(255, 120, 200), { Material = Enum.Material.Neon, Transparency = 0.3 })
		part(model, "Blob", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 0.8, 0), Color3.fromRGB(255, 220, 80), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon })
		part(model, "Cap", Vector3.new(0.3, 0.15, 0.3), cf * CFrame.new(0, 1.15, 0), Color3.fromRGB(180, 180, 190), { Material = Enum.Material.Metal })
	elseif style == "Trophy" then
		local gold = Color3.fromRGB(255, 200, 60)
		part(model, "Base", Vector3.new(0.5, 0.2, 0.5), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(60, 40, 30))
		part(model, "Stem", Vector3.new(0.12, 0.4, 0.12), cf * CFrame.new(0, 0.4, 0), gold, { Material = Enum.Material.Foil })
		part(model, "Cup", Vector3.new(0.5, 0.4, 0.5), cf * CFrame.new(0, 0.8, 0), gold, { Material = Enum.Material.Foil })
		for side = -1, 1, 2 do
			part(model, "Handle", Vector3.new(0.08, 0.25, 0.08), cf * CFrame.new(side * 0.3, 0.8, 0), gold, { Material = Enum.Material.Foil })
		end
	elseif style == "Globe" then
		part(model, "Stand", Vector3.new(0.5, 0.15, 0.5), cf * CFrame.new(0, 0.08, 0), Color3.fromRGB(90, 60, 40))
		part(model, "Axis", Vector3.new(0.06, 0.5, 0.06), cf * CFrame.new(0, 0.35, 0), Color3.fromRGB(200, 180, 120), { Material = Enum.Material.Metal })
		part(model, "Globe", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, 0.8, 0), Color3.fromRGB(60, 140, 230), { Shape = Enum.PartType.Ball })
		part(model, "Land", Vector3.new(0.3, 0.25, 0.1), cf * CFrame.new(0.1, 0.85, -0.26), Color3.fromRGB(90, 190, 90))
	elseif style == "Crown" then
		local gold = Color3.fromRGB(255, 205, 70)
		part(model, "Band", Vector3.new(0.7, 0.25, 0.7), cf * CFrame.new(0, 0.13, 0), gold, { Material = Enum.Material.Foil })
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			part(model, "Spike", Vector3.new(0.12, 0.3, 0.12), cf * CFrame.new(math.cos(a) * 0.3, 0.38, math.sin(a) * 0.3), gold, { Material = Enum.Material.Foil })
		end
		part(model, "Gem", Vector3.new(0.14, 0.14, 0.14), cf * CFrame.new(0, 0.16, -0.36), Color3.fromRGB(255, 60, 120), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon })
	end
	return model
end

-- The test paper lying on a desk: a sheet with question lines, a name line, a big version
-- letter and a pencil. `cf` = centre of the paper on the desk surface.
function Props.testPaper(cf, letter)
	local model = Instance.new("Model")
	model.Name = "TestPaper"
	local sheet = part(model, "Sheet", Vector3.new(1.7, 0.03, 2.2), cf * CFrame.Angles(0, math.rad(-6), 0), Color3.fromRGB(252, 252, 246))
	model.PrimaryPart = sheet
	local ink = Color3.fromRGB(70, 90, 160)
	part(model, "Title", Vector3.new(1.1, 0.01, 0.12), sheet.CFrame * CFrame.new(-0.1, 0.02, -0.9), Color3.fromRGB(40, 40, 60))
	for i = 1, 8 do
		part(model, "Line", Vector3.new(1.3, 0.01, 0.04), sheet.CFrame * CFrame.new(0, 0.02, -0.6 + i * 0.17), ink)
		part(model, "Bubble", Vector3.new(0.06, 0.01, 0.06), sheet.CFrame * CFrame.new(-0.72, 0.02, -0.6 + i * 0.17), ink)
	end
	local badge = part(model, "Version", Vector3.new(0.34, 0.012, 0.34), sheet.CFrame * CFrame.new(0.6, 0.02, -0.88), if letter == "B" then Color3.fromRGB(255, 120, 160) else Color3.fromRGB(90, 170, 255))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.Parent = badge
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = letter or "A"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	part(model, "Pencil", Vector3.new(0.08, 0.08, 1.3), sheet.CFrame * CFrame.new(0.95, 0.05, 0.1) * CFrame.Angles(0, math.rad(10), 0), Color3.fromRGB(255, 205, 60))
	return model
end

-- A torn-up test (after a catch): scattered scraps.
function Props.rippedPaper(cf)
	local model = Instance.new("Model")
	model.Name = "RippedTest"
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		part(model, "Scrap", Vector3.new(0.5, 0.02, 0.4), cf * CFrame.new(math.cos(a) * 0.5, 0.02 + i * 0.005, math.sin(a) * 0.5) * CFrame.Angles(0, a * 1.7, 0), Color3.fromRGB(245, 245, 235))
	end
	return model
end

-- A folded paper airplane (for throws).
function Props.plane(cf)
	local model = Instance.new("Model")
	model.Name = "PaperPlane"
	local white = Color3.fromRGB(250, 250, 245)
	local body = part(model, "Body", Vector3.new(0.1, 0.12, 1.1), cf, white)
	model.PrimaryPart = body
	for side = -1, 1, 2 do
		part(model, "Wing", Vector3.new(0.45, 0.03, 1.0), cf * CFrame.new(side * 0.22, 0.05, 0.05) * CFrame.Angles(0, 0, math.rad(side * -12)), white)
	end
	return model
end

return Props
