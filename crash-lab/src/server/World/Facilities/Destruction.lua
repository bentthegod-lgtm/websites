--[[
	Destruction Testing Zone - a dusty demolition yard dense with destructibles: brick
	walls (each block its own prop), crate towers, a glass gallery, oil-drum stacks, a
	crane with a swinging wrecking ball (target), a rubble pit and a dumpster to land in.
	Shipping containers and catch nets line the yard; orange floodlights light it.

	Every destructible is a prebuilt part that is only hidden when broken (no geometry is
	created or destroyed per break); the few fragments that fly come from CourseService's
	capped, reused pool. Local coordinates (see CourseConfig.Courses.Destruction).
]]

local Kit = require(script.Parent.Parent.Kit)

local Destruction = {}

local rgb = Kit.rgb
local M = Kit.M
local C = Kit.C
local part, deco, key = Kit.part, Kit.deco, Kit.key

function Destruction.build(world, entry)
	local course = entry.course
	local O = entry.origin
	local A = course.Arena
	local length, half = A.Length, A.HalfWidth
	local root = entry.folder
	local arena = Kit.sub("Arena", root)
	local function at(x, y, z)
		return CFrame.new(O + Vector3.new(x, y, z))
	end

	-- Ground: packed dirt yard (slabs) + gravel behind the deck.
	for i = 0, 5 do
		local slab = (length + 40) / 6
		Kit.floor(part({ Name = "YardFloor", Size = Vector3.new(half * 2 + 4, 2, slab), CFrame = at(0, -1, 6 + slab * (i + 0.5)), Color = if i % 2 == 0 then rgb(150, 112, 80) else rgb(142, 106, 76), Material = M.Ground, Parent = arena }))
	end
	Kit.floor(part({ Name = "YardApron", Size = Vector3.new(half * 2 + 64, 2, 100), CFrame = at(0, -1, -44), Color = rgb(128, 112, 96), Material = M.Pebble, Parent = arena }))
	for _, x in ipairs({ -1, 1 }) do
		Kit.floor(part({ Name = "YardSide", Size = Vector3.new(30, 2, length + 40), CFrame = at(x * (half + 17), -1, length / 2 + 6), Color = rgb(124, 100, 80), Material = M.Ground, Parent = arena }))
	end
	-- Open scrubland around the yard (so nothing sits on the edge of the world).
	deco({ Name = "Scrubland", Size = Vector3.new(1400, 2, 1600), CFrame = at(0, -1.1, 300), Color = rgb(170, 128, 88), Material = M.Ground, Parent = arena })
	-- Tyre ruts and oil stains (thin decals made of parts, no images).
	for i = 1, 16 do
		local z = 30 + ((i * 83) % 460)
		local x = math.sin(i * 7.31) * 50
		deco({ Name = "Rut", Size = Vector3.new(1.2, 0.03, 10 + (i % 4) * 4), CFrame = at(x, 0.03, z) * CFrame.Angles(0, math.sin(i * 2.7) * 0.6, 0), Color = rgb(96, 72, 54), Transparency = 0.4, CastShadow = false, Parent = arena })
	end

	Kit.facilityDeck(world, entry, { accent = C.Orange, lampColor = rgb(255, 200, 140) })

	-- Shipping containers along both sides (outside the nets) and behind the deck.
	local containerColors = { rgb(176, 64, 44), rgb(46, 98, 150), rgb(210, 150, 40), rgb(70, 120, 80) }
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 15 do
			local z = 20 + i * 30
			local col = containerColors[(i + (if side > 0 then 1 else 0)) % #containerColors + 1]
			local box = part({ Name = "Container", Size = Vector3.new(8, 8.5, 26), CFrame = at(side * (half + 14), 4.25, z), Color = col, Material = M.CorrodedMetal, Parent = arena })
			key(box, "Container")
			if i % 3 == 1 then
				part({ Name = "Container", Size = Vector3.new(8, 8.5, 26), CFrame = at(side * (half + 14), 12.75, z), Color = containerColors[(i + 2) % #containerColors + 1], Material = M.CorrodedMetal, Parent = arena })
			end
		end
	end
	for i = -3, 3 do
		part({ Name = "Container", Size = Vector3.new(26, 8.5, 8), CFrame = at(i * 27, 4.25, -96), Color = containerColors[(i + 4) % #containerColors + 1], Material = M.CorrodedMetal, Parent = arena })
	end
	Kit.nets(O, arena, { half = half, length = length, height = 110, color = rgb(60, 50, 40), railColor = C.Orange })
	Kit.hazardStrip(at(0, 0.03, 20), 120, 1.6, 24, arena)

	-- Props --------------------------------------------------------------------------------
	local props = Kit.sub("Props", arena)
	local function prop(kindId, size, cf, group)
		return Kit.prop(world, kindId, size, cf, group, props, entry.id)
	end
	local brickShades = { rgb(170, 84, 62), rgb(156, 74, 56), rgb(182, 96, 70) }
	local function brickWall(z, cols, rows, group)
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				local x = (c - (cols - 1) / 2) * 8
				local brick = prop("Brick", Vector3.new(7.8, 3.9, 3), at(x, 2 + r * 4, z), group)
				brick.Color = brickShades[(r + c) % #brickShades + 1]
			end
		end
		-- Painted steel footing plate under the wall.
		deco({ Name = "WallFooting", Size = Vector3.new(cols * 8 + 4, 0.06, 4.4), CFrame = at(0, 0.03, z), Color = C.SteelDark, Material = M.Metal, CastShadow = false, Parent = arena })
	end
	brickWall(105, 5, 4, "DZ_Wall1")
	brickWall(250, 6, 3, "DZ_Wall2")
	-- Crate towers (2 x 2 x 3).
	local function crateTower(x0, z0)
		for layer = 0, 2 do
			for _, dx in ipairs({ -2.6, 2.6 }) do
				for _, dz in ipairs({ -2.6, 2.6 }) do
					prop("Crate", Vector3.new(5, 5, 5), at(x0 + dx, 2.5 + layer * 5, z0 + dz) * CFrame.Angles(0, math.rad((layer * 17 + dx * 3) % 12 - 6), 0), "DZ_Crates")
				end
			end
		end
	end
	for _, spot in ipairs({ { -40, 150 }, { 40, 150 }, { -22, 290 }, { 22, 290 }, { 58, 452 } }) do
		crateTower(spot[1], spot[2])
	end
	-- Glass gallery: seven panes between steel mullions on a concrete curb.
	part({ Name = "GalleryCurb", Size = Vector3.new(60, 1, 2), CFrame = at(0, 0.5, 175), Color = C.Concrete, Material = M.Concrete, Parent = arena })
	for i = -3, 3 do
		prop("Glass", Vector3.new(7.6, 10, 0.6), at(i * 8, 6, 175), "DZ_Glass")
	end
	for i = -3.5, 3.5 do
		key(part({ Name = "Mullion", Size = Vector3.new(0.6, 11.4, 1), CFrame = at(i * 8, 6.2, 175), Color = C.SteelDark, Material = M.Metal, Parent = arena }), "GlassFrame")
	end
	key(part({ Name = "GalleryBeam", Size = Vector3.new(60, 1, 1.2), CFrame = at(0, 11.6, 175), Color = C.SteelDark, Material = M.Metal, Parent = arena }), "GlassFrame")
	-- Oil drum pyramids (upright drums: a cylinder's axis is X, so stand it on end).
	local upright = CFrame.Angles(0, 0, math.rad(90))
	for _, spot in ipairs({ { -35, 360 }, { 35, 360 }, { 0, 395 } }) do
		for row, n in ipairs({ 3, 2, 1 }) do
			for j = 1, n do
				local x = spot[1] + (j - (n + 1) / 2) * 3.2
				local drum = prop("Barrel", Vector3.new(4, 3, 3), at(x, 2 + (row - 1) * 4, spot[2]) * upright, "DZ_Barrels")
				drum.Color = if (row + j) % 2 == 0 then rgb(210, 90, 40) else rgb(60, 110, 180)
			end
		end
	end

	-- Course pieces ----------------------------------------------------------------------
	for _, def in ipairs(course.Rings) do
		Kit.ring(world, def, O, arena)
	end
	for _, def in ipairs(course.Targets) do
		Kit.target(world, def, O, arena)
	end
	for _, def in ipairs(course.LandingZones) do
		Kit.zone(world, def, O, arena)
	end
	-- Rubble pit: low piles of broken concrete around the landing zone (soft-ish sand).
	local pit = course.LandingZones[1].Position
	local sand = part({ Name = "RubbleSand", Size = Vector3.new(30, 0.4, 30), CFrame = at(pit.X, 0.2, pit.Z), Color = rgb(196, 168, 120), Material = M.Sand, Parent = arena })
	Kit.floor(sand)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		key(part({ Class = "WedgePart", Name = "Rubble", Size = Vector3.new(7, 2.4, 5), CFrame = at(pit.X + math.cos(a) * 19, 1.2, pit.Z + math.sin(a) * 19) * CFrame.Angles(0, -a + math.pi / 2, 0), Color = rgb(150, 146, 140), Material = M.Slate, Parent = arena }), "Rubble")
	end
	-- Dumpster: open-top bin around the second landing zone.
	local bin = course.LandingZones[2].Position
	local binColor = rgb(40, 110, 70)
	for _, w in ipairs({ { 0, 7, 18, 0.8 }, { 0, -7, 18, 0.8 } }) do
		key(part({ Name = "DumpsterWall", Size = Vector3.new(w[3], 3, w[4]), CFrame = at(bin.X + w[1], 1.5, bin.Z + w[2]), Color = binColor, Material = M.Metal, Parent = arena }), "Dumpster")
	end
	for _, x in ipairs({ -9, 9 }) do
		key(part({ Name = "DumpsterWall", Size = Vector3.new(0.8, 3, 14.8), CFrame = at(bin.X + x, 1.5, bin.Z), Color = binColor, Material = M.Metal, Parent = arena }), "Dumpster")
	end

	Kit.markers(world, course, O, arena, { half = half })

	-- Floodlight towers: warm orange-white spots aimed into the yard.
	for _, spot in ipairs({ { -1, 60 }, { 1, 60 }, { -1, 300 }, { 1, 300 } }) do
		local x = spot[1] * (half + 26)
		part({ Name = "FloodTower", Size = Vector3.new(2.4, 64, 2.4), CFrame = at(x, 32, spot[2]), Color = C.SteelDark, Material = M.Metal, Parent = arena })
		local head = deco({ Name = "Floodlight", Size = Vector3.new(10, 4, 2), CFrame = at(x, 64, spot[2]) * CFrame.Angles(0, math.rad(spot[1] * -90), 0) * CFrame.Angles(math.rad(-28), 0, 0), Color = rgb(255, 214, 160), Material = M.Neon, Parent = arena })
		Kit.light("SpotLight", head, { Face = Enum.NormalId.Front, Angle = 75, Range = 140, Brightness = 2, Color = rgb(255, 186, 120), Shadows = false })
	end

	-- Excavator parked outside the yard (decoration).
	local ex = at(-(half + 34), 0, 220) * CFrame.Angles(0, math.rad(30), 0)
	part({ Name = "ExcavatorTracks", Size = Vector3.new(12, 3, 16), CFrame = ex * CFrame.new(0, 1.5, 0), Color = rgb(40, 40, 42), Material = M.Metal, Parent = arena })
	part({ Name = "ExcavatorBody", Size = Vector3.new(10, 6, 11), CFrame = ex * CFrame.new(0, 6, 1), Color = C.Yellow, Material = M.Metal, Parent = arena })
	part({ Name = "ExcavatorCab", Size = Vector3.new(5, 5, 5), CFrame = ex * CFrame.new(-2, 11, 3), Color = rgb(60, 90, 110), Material = M.Glass, Transparency = 0.25, Parent = arena })
	part({ Name = "ExcavatorBoom", Size = Vector3.new(2, 2, 18), CFrame = ex * CFrame.new(2, 12, -8) * CFrame.Angles(math.rad(25), 0, 0), Color = C.Yellow, Material = M.Metal, Parent = arena })
	part({ Name = "ExcavatorStick", Size = Vector3.new(1.6, 12, 1.6), CFrame = ex * CFrame.new(2, 10, -17), Color = C.Yellow, Material = M.Metal, Parent = arena })
	part({ Name = "ExcavatorBucket", Class = "WedgePart", Size = Vector3.new(5, 3, 4), CFrame = ex * CFrame.new(2, 3.5, -18), Color = rgb(70, 70, 72), Material = M.Metal, Parent = arena })
	-- Concrete rubble heaps and safety barriers outside the nets.
	for i = 1, 6 do
		local z = 40 + i * 70
		local x = (if i % 2 == 0 then 1 else -1) * (half + 32)
		part({ Class = "WedgePart", Name = "Heap", Size = Vector3.new(14, 6, 10), CFrame = at(x, 3, z) * CFrame.Angles(0, math.rad(i * 50), 0), Color = rgb(158, 150, 140), Material = M.Slate, Parent = arena })
	end

	Kit.ambient("DemolitionRumble", O + Vector3.new(-(half + 30), 6, 220), arena)
	Kit.ambient("Clank", O + Vector3.new(-44, 30, 330), arena)
	Kit.ambient("DemolitionRumble", O + Vector3.new(half + 20, 6, 420), arena)
end

return Destruction
