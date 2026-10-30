--[[
	Parts - small helpers for building models from parts (shared by the server builders, the
	client's viewport icons and the preview tools).

	Parts.new(opts): opts = Size, CFrame, Color, Material, Transparency, Shape, Name,
	CanCollide (default true), Anchored (default true), CastShadow, Reflectance, Class, Parent.
	Cylinders in Roblox run along their local X axis: use Parts.UP / Parts.ALONG_Z to turn them.
]]

local Parts = {}

local rgb = Color3.fromRGB
local M = Enum.Material

Parts.UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinder standing up
Parts.ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder lying along Z

Parts.Palette = {
	Navy = rgb(24, 38, 66),
	Brass = rgb(206, 160, 70),
	BrassDark = rgb(150, 108, 44),
	Cream = rgb(240, 230, 204),
	Red = rgb(190, 50, 46),
	AntiFoul = rgb(150, 44, 40),
	White = rgb(242, 240, 232),
	Teak = rgb(168, 116, 70),
	TeakDark = rgb(120, 80, 48),
	Steel = rgb(120, 126, 136),
	SteelDark = rgb(64, 68, 76),
	Rope = rgb(198, 170, 120),
	Orange = rgb(240, 120, 40),
	Window = rgb(255, 214, 140),
	WindowCool = rgb(190, 220, 255),
	Black = rgb(22, 22, 26),
	Wood = rgb(140, 92, 54),
	WoodLight = rgb(186, 140, 92),
	Crate = rgb(160, 120, 74),
	Tarp = rgb(150, 140, 104),
	Green = rgb(70, 200, 120),
	Hazard = rgb(250, 200, 40),
}

function Parts.rgb(t)
	return rgb(t[1], t[2], t[3])
end

function Parts.material(name)
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	return if ok and value then value else M.SmoothPlastic
end

function Parts.new(opts)
	local p = Instance.new(opts.Class or "Part")
	p.Name = opts.Name or "Part"
	p.Anchored = opts.Anchored ~= false
	p.Size = opts.Size
	p.CFrame = opts.CFrame
	p.Color = opts.Color or Parts.Palette.White
	p.Material = opts.Material or M.SmoothPlastic
	p.Transparency = opts.Transparency or 0
	p.Reflectance = opts.Reflectance or 0
	p.CanCollide = opts.CanCollide ~= false
	p.CanQuery = opts.CanQuery ~= false and p.CanCollide
	p.CanTouch = false
	p.CastShadow = opts.CastShadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.Shape then
		p.Shape = opts.Shape
	end
	p.Parent = opts.Parent
	return p
end

function Parts.light(parent, color, range, brightness, shadows)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = shadows == true
	l.Parent = parent
	return l
end

-- A box from point a to point b (thickness t x t), e.g. rails, beams, ropes.
function Parts.beamCFrame(a, b)
	local mid = (a + b) / 2
	return CFrame.lookAt(mid, b), (b - a).Magnitude
end

--[[
	A flat right triangle (a WedgePart turned on its side): the right angle at `corner`, one
	leg along unit `dirA` (length a), the other along unit `dirB` (length b), `thick` thick
	(perpendicular to both legs). Fills the gaps between a deck and a tapering hull.
]]
function Parts.triangleCFrame(corner, dirA, a, dirB, b)
	local y = dirA
	local z = -dirB
	local x = y:Cross(z)
	local centre = corner + dirA * (a / 2) + dirB * (b / 2)
	return CFrame.fromMatrix(centre, x, y, z)
end

-- A builder that places parts relative to an origin CFrame and counts them.
local Builder = {}
Builder.__index = Builder

function Parts.builder(origin, parent)
	return setmetatable({ origin = origin, parent = parent, count = 0 }, Builder)
end

function Builder:part(opts)
	opts.CFrame = self.origin * opts.CFrame
	opts.Parent = opts.Parent or self.parent
	self.count += 1
	return Parts.new(opts)
end

-- Box between two LOCAL points.
function Builder:beam(a, b, thick, opts)
	local cf, len = Parts.beamCFrame(a, b)
	opts.CFrame = cf
	opts.Size = Vector3.new(thick, opts.Height or thick, len)
	return self:part(opts)
end

function Builder:folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or self.parent
	return f
end

return Parts
