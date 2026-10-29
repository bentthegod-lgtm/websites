--[[
	High-Altitude Launch Facility - a launch deck on a cliff-top mesa over a deep canyon.
	Dummies fly off the cliff into the canyon: three rope bridges cross it at different
	depths, landing ledges sit on rock pillars at three depths, rings hang from cables, a
	target juts from the canyon wall and another swings under a cable. Wind gusts and the
	Free-Fall Bonus are server-side (CrashService / Scoring).

	Players can't walk off the mesa: invisible walls in the CL_PlayerWall collision group
	stop characters but not dummies (and anyone who still falls is put back on the deck).
	Local coordinates: deck top Y = 1, canyon floor Y = -200 (CourseConfig.Courses.HighAltitude).
]]

local Kit = require(script.Parent.Parent.Kit)

local HighAltitude = {}

local rgb = Kit.rgb
local M = Kit.M
local C = Kit.C
local CYL = Kit.CYL
local part, deco, key = Kit.part, Kit.deco, Kit.key

local ROCK = rgb(128, 116, 104)
local ROCK_DARK = rgb(104, 94, 86)
local ROCK_LIGHT = rgb(150, 138, 122)

function HighAltitude.build(world, entry)
	local course = entry.course
	local O = entry.origin
	local A = course.Arena
	local length, half = A.Length, A.HalfWidth
	local bottom = A.CanyonFloorY
	local root = entry.folder
	local arena = Kit.sub("Arena", root)
	local function at(x, y, z)
		return CFrame.new(O + Vector3.new(x, y, z))
	end

	-- The mesa the deck stands on (top at local Y 0, edge at Z = 10).
	Kit.floor(part({ Name = "Mesa", Size = Vector3.new(230, 200, 112), CFrame = at(0, -100, -46), Color = ROCK, Material = M.Rock, Parent = arena }))
	for i, spot in ipairs({ { -70, -60 }, { 72, -70 }, { -86, -20 }, { 80, -30 } }) do
		deco({ Name = "Grass", Size = Vector3.new(30 + i * 4, 0.2, 26), CFrame = at(spot[1], 0.1, spot[2]), Color = rgb(96, 140, 70), Material = M.Grass, CastShadow = false, Parent = arena })
	end
	-- Strata bands on the mesa's cliff face.
	for k, y in ipairs({ -30, -75, -120, -165 }) do
		deco({ Name = "Strata", Size = Vector3.new(230, 5, 0.6), CFrame = at(0, y, 10.2), Color = if k % 2 == 0 then ROCK_DARK else ROCK_LIGHT, Material = M.Rock, Parent = arena })
	end

	Kit.facilityDeck(world, entry, { accent = rgb(110, 190, 255) })

	-- Keep players on the mesa (dummies pass straight through these).
	Kit.playerWall({ Name = "EdgeWall", Size = Vector3.new(230, 14, 1), CFrame = at(0, 7, 10.5), Parent = arena })
	Kit.playerWall({ Name = "BackWall", Size = Vector3.new(230, 14, 1), CFrame = at(0, 7, -101.5), Parent = arena })
	for _, x in ipairs({ -1, 1 }) do
		Kit.playerWall({ Name = "SideWall", Size = Vector3.new(1, 14, 112), CFrame = at(x * 115.5, 7, -46), Parent = arena })
	end
	-- Visible safety rail along the cliff edge (decoration only; it doesn't snag dummies).
	for x = -105, 105, 15 do
		deco({ Name = "RailPost", Size = Vector3.new(0.5, 3.4, 0.5), CFrame = at(x, 1.7, 9.6), Color = C.Steel, Material = M.Metal, Parent = arena })
	end
	deco({ Name = "Rail", Size = Vector3.new(212, 0.4, 0.4), CFrame = at(0, 3.3, 9.6), Color = C.Yellow, Material = M.Metal, Parent = arena })
	-- Windsock on the deck: the wind is real here.
	part({ Name = "WindsockPole", Size = Vector3.new(0.6, 14, 0.6), CFrame = at(56, 7, -14), Color = C.Steel, Material = M.Metal, Parent = arena })
	for k = 0, 3 do
		deco({ Name = "Windsock", Size = Vector3.new(2.4 - k * 0.4, 2.4 - k * 0.4, 2), CFrame = at(57.6 + k * 2, 13, -14), Color = if k % 2 == 0 then C.Orange else C.White, Parent = arena })
	end

	-- Canyon: floor with a river, rock walls with strata, and mist far below the deck.
	Kit.floor(part({ Name = "CanyonFloor", Size = Vector3.new(half * 2 + 40, 4, length + 30), CFrame = at(0, bottom - 2, length / 2 + 15), Color = rgb(150, 128, 98), Material = M.Ground, Parent = arena }))
	deco({ Name = "River", Size = Vector3.new(14, 0.12, length + 20), CFrame = at(-6, bottom + 0.06, length / 2 + 15), Color = rgb(70, 130, 170), Material = M.Glass, Transparency = 0.25, CastShadow = false, Parent = arena })
	local wallTop = 60
	local wallH = wallTop - bottom
	for _, side in ipairs({ -1, 1 }) do
		local wall = part({ Name = "CanyonWall", Size = Vector3.new(24, wallH, length + 20), CFrame = at(side * (half + 12), bottom + wallH / 2, length / 2 + 20), Color = ROCK, Material = M.Rock, Parent = arena })
		key(wall, "CanyonWall")
		for k, y in ipairs({ -25, -70, -115, -160 }) do
			deco({ Name = "Strata", Size = Vector3.new(0.6, 4 + k, length + 20), CFrame = at(side * (half + 0.2), y, length / 2 + 20), Color = if k % 2 == 0 then ROCK_DARK else ROCK_LIGHT, Material = M.Rock, Parent = arena })
		end
	end
	for k, z in ipairs({ 140, 330, 520 }) do
		deco({ Name = "Mist", Size = Vector3.new(half * 2, 3, 120), CFrame = at(0, -150 + k * 12, z), Color = rgb(235, 242, 250), Material = M.SmoothPlastic, Transparency = 0.85, CastShadow = false, Parent = arena })
	end
	-- Catch net at the far end of the canyon, from the floor to the rim.
	key(part({ Name = "CatchNet", Size = Vector3.new(half * 2 + 8, wallH, 6), CFrame = at(0, bottom + wallH / 2, length + 2.5), Color = rgb(40, 44, 50), Material = M.Fabric, Transparency = 0.7, Parent = arena }), "CatchNet")
	part({ Name = "CatchFrameTop", Size = Vector3.new(half * 2 + 4, 2, 2), CFrame = at(0, wallTop + 1, length), Color = C.Yellow, Material = M.Metal, Parent = arena })

	-- Landing ledges on rock pillars.
	for _, def in ipairs(course.LandingZones) do
		local p = def.Position
		Kit.floor(part({ Name = "Ledge", Size = Vector3.new(40, 6, 36), CFrame = at(p.X, p.Y - 3, p.Z), Color = ROCK_LIGHT, Material = M.Slate, Parent = arena }))
		local pillarH = p.Y - 6 - bottom
		key(part({ Name = "Pillar", Size = Vector3.new(18, pillarH, 18), CFrame = at(p.X, bottom + pillarH / 2, p.Z), Color = ROCK_DARK, Material = M.Rock, Parent = arena }), "Pillar")
		Kit.hazardStrip(at(p.X, p.Y + 0.06, p.Z - 17.4), 40, 1, 10, arena)
		Kit.zone(world, def, O, arena)
	end

	-- Rope bridges: three sagging plank segments wall to wall, rope rails above.
	local span = half * 2
	for _, b in ipairs(course.Bridges) do
		local segs = { { x = -span / 3, tilt = -2.2, dy = -1 }, { x = 0, tilt = 0, dy = -2.2 }, { x = span / 3, tilt = 2.2, dy = -1 } }
		for _, sg in ipairs(segs) do
			local plank = part({ Name = b.Id, Size = Vector3.new(span / 3 + 0.6, 1, 8), CFrame = at(sg.x, b.Y + sg.dy, b.Z) * CFrame.Angles(0, 0, math.rad(sg.tilt)), Color = rgb(150, 108, 66), Material = M.WoodPlanks, Parent = arena })
			key(plank, b.Id)
		end
		for _, dz in ipairs({ -4.2, 4.2 }) do
			deco({ Name = "Rope", Size = Vector3.new(span, 0.35, 0.35), CFrame = at(0, b.Y + 2.4, b.Z + dz), Color = rgb(186, 160, 110), Material = M.Fabric, Parent = arena })
		end
		for x = -span / 2 + 15, span / 2 - 15, 30 do
			deco({ Name = "Hanger", Size = Vector3.new(0.25, 3.4, 0.25), CFrame = at(x, b.Y + 0.6, b.Z - 4.2), Color = rgb(186, 160, 110), Parent = arena })
		end
	end

	-- Rings hang from cables strung between the canyon walls.
	for _, def in ipairs(course.Rings) do
		Kit.ring(world, def, O, arena)
		local p = def.Position
		local cableY = p.Y + def.Radius + 14
		deco({ Name = "RingCable", Size = Vector3.new(span + 8, 0.5, 0.5), CFrame = at(0, cableY, p.Z), Color = C.SteelDark, Material = M.Metal, Parent = arena })
		deco({ Name = "RingHanger", Size = Vector3.new(0.3, 14, 0.3), CFrame = at(p.X, p.Y + def.Radius + 7, p.Z), Color = C.Steel, Material = M.Metal, Parent = arena })
	end
	for _, def in ipairs(course.Targets) do
		Kit.target(world, def, O, arena, { floorY = bottom, span = span + 8, wallX = half })
	end

	-- Distance: lines on the canyon floor, big boards on both canyon walls near the rim.
	Kit.markers(world, course, O, arena, { floorY = bottom + 0.1, half = half, signX = half - 0.6, signY = -14 })

	-- Highlands around the canyon at the mesa's height (the canyon is cut into them), so
	-- nothing floats in the sky.
	for _, side in ipairs({ -1, 1 }) do
		deco({ Name = "Highland", Size = Vector3.new(560, 40, 1500), CFrame = at(side * (114 + 280), -20, 400), Color = rgb(122, 128, 96), Material = M.Grass, Parent = arena })
	end
	deco({ Name = "Highland", Size = Vector3.new(230, 40, 600), CFrame = at(0, -20, -402), Color = rgb(122, 128, 96), Material = M.Grass, Parent = arena })
	deco({ Name = "Highland", Size = Vector3.new(230, 40, 300), CFrame = at(0, -20, length + 160), Color = rgb(122, 128, 96), Material = M.Grass, Parent = arena })
	-- Mountains on the highlands and pines on the mesa (decoration).
	for i, m in ipairs({ { -300, 160, 240 }, { 310, 120, 300 }, { -340, 520, 340 }, { 360, 560, 260 }, { 0, 940, 380 }, { -230, 860, 300 } }) do
		local h = m[3]
		local cf = at(m[1], h / 2, m[2]) * CFrame.Angles(0, math.rad(i * 37), 0)
		deco({ Class = "WedgePart", Name = "Peak", Size = Vector3.new(160, h, 90), CFrame = cf, Color = if i % 2 == 0 then ROCK_DARK else rgb(116, 108, 112), Material = M.Rock, Parent = arena })
		-- A WedgePart rises toward its +Z: two back to back make a ridge along X.
		deco({ Class = "WedgePart", Name = "PeakBack", Size = Vector3.new(160, h, 90), CFrame = cf * CFrame.new(0, 0, 90) * CFrame.Angles(0, math.pi, 0), Color = if i % 2 == 0 then ROCK_DARK else rgb(116, 108, 112), Material = M.Rock, Parent = arena })
		for _, sideZ in ipairs({ -1, 1 }) do
			local snowCF = cf * CFrame.new(0, h * 0.39, 45 + sideZ * 10) * (if sideZ > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
			deco({ Class = "WedgePart", Name = "Snow", Size = Vector3.new(70, h * 0.22, 20), CFrame = snowCF, Color = rgb(245, 248, 252), Material = M.Snow, Parent = arena })
		end
	end
	for _, t in ipairs({ { -96, -84 }, { -78, -92 }, { 92, -86 }, { 100, -60 }, { -100, -40 }, { 96, -24 } }) do
		part({ Name = "PineTrunk", Size = Vector3.new(1.4, 6, 1.4), CFrame = at(t[1], 3, t[2]), Color = rgb(96, 70, 48), Material = M.Wood, Parent = arena })
		for k = 0, 2 do
			deco({ Name = "PineCrown", Size = Vector3.new(8 - k * 2.4, 3.2, 8 - k * 2.4), CFrame = at(t[1], 6.5 + k * 3, t[2]) * CFrame.Angles(0, math.rad(k * 30), 0), Color = rgb(50, 104, 66), Material = M.Grass, Parent = arena })
		end
	end
	-- Observation platform with a telescope on the mesa corner.
	part({ Name = "LookoutDeck", Size = Vector3.new(16, 1, 12), CFrame = at(-92, 0.5, 0), Color = C.SteelDark, Material = M.DiamondPlate, Parent = arena })
	deco({ Name = "Telescope", Size = Vector3.new(4, 1.2, 1.2), CFrame = at(-92, 4, 2) * CFrame.Angles(0, math.rad(80), math.rad(20)), Shape = CYL, Color = C.White, Material = M.Metal, Parent = arena })
	deco({ Name = "TelescopeLeg", Size = Vector3.new(0.4, 3.4, 0.4), CFrame = at(-92, 2.7, 2), Color = C.Steel, Parent = arena })

	Kit.ambient("CanyonWind", O + Vector3.new(0, 4, 8), arena)
	Kit.ambient("CanyonWind", O + Vector3.new(0, -100, 300), arena)
end

return HighAltitude
