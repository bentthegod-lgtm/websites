--[[
	CityBuilder - Chaos City around the track (all Deco: karts never touch it; the track
	walls keep them on the road). Landmarks:
	  * Downtown: neon-lit skyscrapers both sides of the start straight, a skyline ring
	  * NEON PLAZA beside the straight with BIG TOASTY, a giant original brainrot statue
	    (a golden slice of toast with sunglasses, flexing on a pedestal), a fountain, palms
	  * a giant QUACKARONI billboard (the parade event's star) facing the banked bowl
	  * the spiral PARKING GARAGE in the bowl's infield (its roof is the Rooftop Leap)
	  * the STADIUM by the stadium bulge, CHAOS PARK by the north leg, the river bridge
	    arches, street lamps, billboards, tyre stacks and cones
	Buildings are only placed where they clear every road (MapData projection).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Parts = require(Shared.Parts)
local Rng = require(Shared.Rng)

local CityBuilder = {}

local P = Parts.Palette
local M = Enum.Material
local rgb = Color3.fromRGB
local NEONS = { P.NeonPink, P.NeonCyan, P.NeonYellow, P.NeonPurple, P.NeonGreen, P.NeonOrange }

-- Distance from (x, z) to the nearest road edge (negative = on a road).
local function clearance(data, x, z)
	local best = math.huge
	local probe = Vector3.new(x, 0, z)
	local hit = data.main:project(probe, nil, 600)
	if hit then
		best = math.abs(hit.lateral) - (hit.w / 2 + hit.sh + 2)
		local _, _, planar2 = data.main:locate(hit.index, x, z)
		best = math.min(best, math.sqrt(planar2) - (hit.w / 2 + hit.sh + 2))
	end
	for _, sc in ipairs(data.shortcuts) do
		local h = sc.track:project(probe, nil, 600)
		if h then
			best = math.min(best, math.abs(h.lateral) - (h.w / 2 + h.sh + 3))
		end
	end
	return best
end
CityBuilder.clearance = clearance

local function blocked(data, x, z, radius)
	local river = data.def.River
	if river and z + radius > river.z0 - 6 and z - radius < river.z1 + 6 then
		return true
	end
	local lobby = data.lobby.centre
	if math.abs(x - lobby.X) < 150 + radius and math.abs(z - lobby.Z) < 130 + radius then
		return true
	end
	return clearance(data, x, z) < radius
end
CityBuilder.blocked = blocked

local function tower(job, x, z, w, d, h, neon, rng, opts)
	opts = opts or {}
	local glass = rng:NextNumber() < 0.55
	local body = if glass then rgb(22 + rng:NextInteger(0, 20), 26 + rng:NextInteger(0, 24), 58 + rng:NextInteger(0, 40)) else rgb(46 + rng:NextInteger(0, 30), 36 + rng:NextInteger(0, 24), 70 + rng:NextInteger(0, 40))
	local yaw = opts.yaw or 0
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	job:add("City/Downtown", { Name = "Tower", Size = Vector3.new(w, h, d), CFrame = base * CFrame.new(0, h / 2, 0), Color = body, Material = if glass then M.Glass else M.Concrete, Reflectance = if glass then 0.15 else 0, CanCollide = false })
	-- window bands that glow at dusk
	local bands = math.clamp(math.floor(h / 26), 1, 4)
	for i = 1, bands do
		local y = h * i / (bands + 1)
		job:add("City/Downtown", { Name = "WindowBand", Size = Vector3.new(w + 0.4, 2.6, d + 0.4), CFrame = base * CFrame.new(0, y, 0), Color = if i % 2 == 0 then neon else rgb(255, 214, 140), Material = M.Neon, CanCollide = false, CastShadow = false })
	end
	-- neon edge trims and a rooftop sign / antenna
	for _, sx in ipairs({ -1, 1 }) do
		job:add("City/Downtown", { Name = "NeonTrim", Size = Vector3.new(1.2, h, 1.2), CFrame = base * CFrame.new(sx * w / 2, h / 2, -d / 2), Color = neon, Material = M.Neon, CanCollide = false, CastShadow = false })
	end
	job:add("City/Downtown", { Name = "RoofTrim", Size = Vector3.new(w + 1, 1.2, d + 1), CFrame = base * CFrame.new(0, h, 0), Color = neon, Material = M.Neon, CanCollide = false, CastShadow = false })
	if rng:NextNumber() < 0.55 then
		job:add("City/Downtown", { Name = "RoofSign", Size = Vector3.new(w * 0.8, 6, 1), CFrame = base * CFrame.new(0, h + 4, -d / 2 + 2), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = opts.sign or "CHAOS", Color = neon }, Light = { Color = neon, Range = 30, Brightness = 1.5 } })
	else
		job:add("City/Downtown", { Name = "Antenna", Size = Vector3.new(1, 18, 1), CFrame = base * CFrame.new(0, h + 9, 0), Color = P.SteelDark, CanCollide = false })
		job:add("City/Downtown", { Name = "AntennaTip", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = base * CFrame.new(0, h + 18, 0), Color = P.Red, Material = M.Neon, CanCollide = false })
	end
	return 5 + bands
end

local SIGNS = { "TURBO TACOS", "BONK BANK", "NOODLE CORP", "ZOOM INSURANCE", "SKID MARK CAFE", "MEGA MALL", "DRIFT KING", "GIGA PIZZA", "HONK HOTEL", "NITRO NEWS", "BOOST BURGERS", "QUACK TOWER" }

local function downtown(job, data, rng)
	local n = 0
	-- north of the start straight: three rows, tallest at the back
	for row, z in ipairs({ -78, -150, -232, -330 }) do
		local x = -840
		while x < 640 do
			local w = rng:NextInteger(34, 52)
			local d = rng:NextInteger(34, 50)
			local h = 40 + row * 28 + rng:NextInteger(0, 60)
			if not blocked(data, x, z, math.max(w, d) / 2 + 4) then
				n += tower(job, x, z, w, d, h, NEONS[rng:NextInteger(1, #NEONS)], rng, { sign = SIGNS[rng:NextInteger(1, #SIGNS)] })
			end
			x += w + rng:NextInteger(14, 26)
		end
	end
	-- the strip between the straight and the west leg, and east of the north leg
	for _, spot in ipairs({ { -560, 72 }, { -460, 70 }, { -360, 74 }, { -250, 78 }, { -150, 90 }, { 560, 160 }, { 520, 260 }, { -830, 260 }, { -860, 120 }, { -900, -30 } }) do
		local w = rng:NextInteger(28, 40)
		if not blocked(data, spot[1], spot[2], w / 2 + 4) then
			n += tower(job, spot[1], spot[2], w, w, rng:NextInteger(40, 90), NEONS[rng:NextInteger(1, #NEONS)], rng, { sign = SIGNS[rng:NextInteger(1, #SIGNS)] })
		end
	end
	return n
end

-- Mid-rise districts around the course: random lots that clear every road and each other.
local placed = {}
local function overlapsPlaced(x, z, r)
	for _, p in ipairs(placed) do
		if (p.x - x) ^ 2 + (p.z - z) ^ 2 < (p.r + r + 8) ^ 2 then
			return true
		end
	end
	return false
end

local function district(job, data, rng, x0, z0, x1, z1, count, minH, maxH)
	local n, made = 0, 0
	for _ = 1, count * 12 do
		if made >= count then
			break
		end
		local w = rng:NextInteger(30, 50)
		local x, z = rng:NextNumber(x0, x1), rng:NextNumber(z0, z1)
		if not overlapsPlaced(x, z, w * 0.75) and not blocked(data, x, z, w * 0.75 + 4) then
			table.insert(placed, { x = x, z = z, r = w * 0.75 })
			n += tower(job, x, z, w, rng:NextInteger(30, 50), rng:NextInteger(minH, maxH), NEONS[rng:NextInteger(1, #NEONS)], rng, { sign = SIGNS[rng:NextInteger(1, #SIGNS)], yaw = rng:NextNumber(-0.2, 0.2) })
			made += 1
		end
	end
	return n
end

-- The downtown ground: city blocks (dark asphalt) instead of grass north of the straight.
local function cityGround(job)
	job:add("City/Downtown", { Name = "CityBlock", Size = Vector3.new(1700, 0.2, 380), CFrame = CFrame.new(-90, -0.1, -245), Color = rgb(52, 50, 66), Material = M.Asphalt, CanCollide = false })
	for i = 0, 3 do
		job:add("City/Downtown", { Name = "AvenueNeon", Size = Vector3.new(1700, 0.25, 1), CFrame = CFrame.new(-90, -0.05, -110 - i * 88), Color = NEONS[i + 1], Material = M.Neon, CanCollide = false, CastShadow = false })
	end
	return 5
end

-- A ring of far skyline towers (cheap: one box + one glow band each).
local function skyline(job, rng)
	local n = 0
	for i = 1, 56 do
		local a = i / 56 * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local r = rng:NextNumber(2050, 2400)
		local x, z = math.cos(a) * r, 400 + math.sin(a) * r
		local w = rng:NextInteger(60, 120)
		local h = rng:NextInteger(90, 320)
		job:add("City/Skyline", { Name = "Skyline", Size = Vector3.new(w, h, w), CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(0, a, 0), Color = rgb(40 + rng:NextInteger(0, 30), 46 + rng:NextInteger(0, 30), 80 + rng:NextInteger(0, 50)), Material = M.SmoothPlastic, CanCollide = false })
		job:add("City/Skyline", { Name = "SkylineGlow", Size = Vector3.new(w + 1, 3, w + 1), CFrame = CFrame.new(x, h * 0.7, z) * CFrame.Angles(0, a, 0), Color = NEONS[i % #NEONS + 1], Material = M.Neon, CanCollide = false, CastShadow = false })
		n += 2
	end
	return n
end

--[[
	BIG TOASTY - the landmark statue: an original brainrot character, a giant golden slice
	of toast with sunglasses and a grin, flexing both arms on a neon pedestal.
]]
function CityBuilder.statue(job, base)
	local folder = "City/Statue"
	local gold = rgb(240, 186, 60)
	local crust = rgb(176, 112, 40)
	local function part(spec)
		spec.CanCollide = false
		job:add(folder, spec)
	end
	part({ Name = "Pedestal", Size = Vector3.new(30, 8, 30), CFrame = base * CFrame.new(0, 4, 0), Color = P.ConcreteDark, Material = M.Marble })
	part({ Name = "PedestalTop", Size = Vector3.new(26, 2, 26), CFrame = base * CFrame.new(0, 9, 0), Color = P.Black, Material = M.Marble })
	part({ Name = "PedestalNeon", Size = Vector3.new(31, 0.8, 31), CFrame = base * CFrame.new(0, 7.6, 0), Color = P.NeonPink, Material = M.Neon })
	part({ Name = "Plaque", Size = Vector3.new(18, 4, 0.6), CFrame = base * CFrame.new(0, 4, -15.2), Color = rgb(40, 30, 20), Text = { Face = Enum.NormalId.Front, Text = "BIG TOASTY - HERO OF CHAOS CITY", Color = gold } })
	-- legs and sneakers
	for _, s in ipairs({ -1, 1 }) do
		part({ Name = "Leg", Size = Vector3.new(2.6, 9, 2.6), CFrame = base * CFrame.new(s * 4, 14.5, 0), Color = gold, Material = M.Metal })
		part({ Name = "Shoe", Size = Vector3.new(4.4, 3, 7), CFrame = base * CFrame.new(s * 4, 11.5, -1.2), Color = P.Red, Material = M.Metal })
	end
	-- the toast slice: a tall body with a rounded top (crust frame + soft middle)
	part({ Name = "Crust", Size = Vector3.new(22, 26, 5), CFrame = base * CFrame.new(0, 32, 0), Color = crust, Material = M.Metal })
	part({ Name = "Bread", Size = Vector3.new(19, 23, 5.4), CFrame = base * CFrame.new(0, 32, 0), Color = gold, Material = M.Metal, Reflectance = 0.15 })
	for _, s in ipairs({ -1, 1 }) do
		part({ Name = "CrustTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 13, 13), CFrame = base * CFrame.new(s * 5.2, 45, 0) * Parts.ALONG_Z, Color = crust, Material = M.Metal })
		part({ Name = "BreadTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5.4, 11, 11), CFrame = base * CFrame.new(s * 5.2, 45, 0) * Parts.ALONG_Z, Color = gold, Material = M.Metal })
	end
	-- face: shades, grin, cheeks
	part({ Name = "Shades", Size = Vector3.new(15, 3.4, 1), CFrame = base * CFrame.new(0, 39, -3), Color = P.Black, Material = M.Glass, Reflectance = 0.4 })
	part({ Name = "ShadesGlow", Size = Vector3.new(15.4, 0.6, 1.1), CFrame = base * CFrame.new(0, 40.9, -3), Color = P.NeonCyan, Material = M.Neon })
	part({ Name = "Grin", Size = Vector3.new(9, 1.6, 0.8), CFrame = base * CFrame.new(0, 32, -3), Color = rgb(120, 40, 30) })
	part({ Name = "Teeth", Size = Vector3.new(7, 0.8, 0.9), CFrame = base * CFrame.new(0, 32.6, -3.05), Color = P.White })
	for _, s in ipairs({ -1, 1 }) do
		part({ Name = "Cheek", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 1.4), CFrame = base * CFrame.new(s * 6.5, 34, -2.8), Color = rgb(255, 140, 120) })
		-- flexing arms: upper arm out, forearm up, fist
		part({ Name = "UpperArm", Size = Vector3.new(9, 3, 3), CFrame = base * CFrame.new(s * 15, 33, 0) * CFrame.Angles(0, 0, math.rad(s * 10)), Color = gold, Material = M.Metal })
		part({ Name = "Bicep", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), CFrame = base * CFrame.new(s * 15, 35, 0), Color = gold, Material = M.Metal })
		part({ Name = "Forearm", Size = Vector3.new(3, 9, 3), CFrame = base * CFrame.new(s * 19.5, 38, 0), Color = gold, Material = M.Metal })
		part({ Name = "Fist", Shape = Enum.PartType.Ball, Size = Vector3.new(4.4, 4.4, 4.4), CFrame = base * CFrame.new(s * 19.5, 43.5, 0), Color = gold, Material = M.Metal })
	end
	-- a crown of neon butter
	part({ Name = "Butter", Size = Vector3.new(8, 2.4, 6), CFrame = base * CFrame.new(0, 52, 0) * CFrame.Angles(0, math.rad(20), math.rad(6)), Color = rgb(255, 240, 140), Material = M.Neon })
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		part({ Name = "Spotlight", Size = Vector3.new(2, 2, 2), CFrame = base * CFrame.new(math.cos(a) * 17, 1, math.sin(a) * 17), Color = P.White, Material = M.Neon, Light = { Color = rgb(255, 220, 150), Range = 40, Brightness = 2, Spot = true, Face = Enum.NormalId.Top, Angle = 50 } })
	end
	return 35
end

local function palm(job, folder, x, z, rng)
	local h = rng:NextInteger(16, 24)
	job:add(folder, { Name = "PalmTrunk", Size = Vector3.new(1.6, h, 1.6), CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6))), Color = rgb(140, 100, 60), Material = M.Wood, CanCollide = false })
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		job:add(folder, { Name = "PalmLeaf", Size = Vector3.new(1, 0.4, 9), CFrame = CFrame.new(x, h, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -4) * CFrame.Angles(math.rad(-18), 0, 0), Color = rgb(60, 170, 80), Material = M.Grass, CanCollide = false })
	end
	return 6
end

local function tree(job, folder, x, z, rng)
	local h = rng:NextInteger(7, 11)
	job:add(folder, { Name = "Trunk", Size = Vector3.new(1.8, h, 1.8), CFrame = CFrame.new(x, h / 2, z), Color = rgb(110, 76, 46), Material = M.Wood, CanCollide = false })
	local c = rng:NextInteger(0, 2)
	local leaf = if c == 0 then rgb(70, 170, 80) elseif c == 1 then rgb(100, 190, 70) else rgb(230, 120, 170)
	job:add(folder, { Name = "Canopy", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 10, 11), CFrame = CFrame.new(x, h + 3, z), Color = leaf, Material = M.Grass, CanCollide = false })
	job:add(folder, { Name = "Canopy", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), CFrame = CFrame.new(x + 2, h + 7, z - 1), Color = leaf, Material = M.Grass, CanCollide = false })
	return 3
end

-- Neighbourhoods: low shops / houses and tree clumps scattered over the open ground between
-- the landmarks, so no stretch of the lap looks empty. Everything clears every road.
local SHOP_COLORS = { rgb(240, 170, 120), rgb(150, 200, 240), rgb(240, 220, 140), rgb(200, 160, 230), rgb(160, 220, 170), rgb(245, 245, 235) }
local ROOF_COLORS = { rgb(190, 70, 60), rgb(70, 90, 140), rgb(90, 70, 60), rgb(60, 120, 90) }
local function neighbourhoods(job, data, rng)
	local n = 0
	local shops, trees = 0, 0
	for _ = 1, 900 do
		if shops >= 120 and trees >= 110 then
			break
		end
		local x, z = rng:NextNumber(-1450, 1500), rng:NextNumber(-60, 1850)
		if rng:NextNumber() < 0.5 and shops < 120 then
			local w, d = rng:NextInteger(16, 26), rng:NextInteger(14, 22)
			local h = rng:NextInteger(9, 18)
			local r = math.max(w, d) * 0.6
			if not overlapsPlaced(x, z, r) and not blocked(data, x, z, r + 6) then
				table.insert(placed, { x = x, z = z, r = r })
				local yaw = rng:NextInteger(0, 3) * math.pi / 2
				local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
				job:add("City/Neighbourhood", { Name = "Shop", Size = Vector3.new(w, h, d), CFrame = base * CFrame.new(0, h / 2, 0), Color = SHOP_COLORS[rng:NextInteger(1, #SHOP_COLORS)], Material = M.SmoothPlastic, CanCollide = false })
				job:add("City/Neighbourhood", { Name = "Roof", Size = Vector3.new(w + 1.5, 1.4, d + 1.5), CFrame = base * CFrame.new(0, h + 0.7, 0), Color = ROOF_COLORS[rng:NextInteger(1, #ROOF_COLORS)], Material = M.SmoothPlastic, CanCollide = false })
				job:add("City/Neighbourhood", { Name = "Windows", Size = Vector3.new(w + 0.3, 2.4, d + 0.3), CFrame = base * CFrame.new(0, h * 0.55, 0), Color = if rng:NextNumber() < 0.4 then NEONS[rng:NextInteger(1, #NEONS)] else rgb(255, 222, 160), Material = M.Neon, CanCollide = false, CastShadow = false })
				n += 3
				shops += 1
			end
		elseif trees < 110 then
			if not overlapsPlaced(x, z, 8) and not blocked(data, x, z, 10) then
				table.insert(placed, { x = x, z = z, r = 8 })
				n += tree(job, "City/Neighbourhood", x, z, rng)
				trees += 1
			end
		end
	end
	return n
end

local function plaza(job, data, rng)
	local n = 0
	-- NEON PLAZA: south of the straight around the Neon Plaza zone
	local zone = data.zoneById.NeonPlaza
	local mid = data.main:at(zone.from + zone.span / 2)
	local centre = mid.pos + mid.right * 120
	job:add("City/Plaza", { Name = "PlazaTiles", Size = Vector3.new(240, 0.2, 150), CFrame = CFrame.new(centre.X, -0.1, centre.Z), Color = rgb(196, 190, 210), Material = M.Slate, CanCollide = false })
	job:add("City/Plaza", { Name = "PlazaNeonRing", Size = Vector3.new(244, 0.3, 2), CFrame = CFrame.new(centre.X, 0.05, centre.Z - 76), Color = P.NeonPink, Material = M.Neon, CanCollide = false })
	n += 2
	n += CityBuilder.statue(job, CFrame.lookAt(Vector3.new(centre.X, 0, centre.Z), Vector3.new(mid.pos.X, 0, mid.pos.Z)))
	-- fountain
	local f = centre + Vector3.new(-80, 0, 0)
	job:add("City/Plaza", { Name = "FountainBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 26, 26), CFrame = CFrame.new(f.X, 1.5, f.Z) * Parts.UP, Color = P.Concrete, Material = M.Marble, CanCollide = false })
	job:add("City/Plaza", { Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 23, 23), CFrame = CFrame.new(f.X, 3, f.Z) * Parts.UP, Color = P.Water, Material = M.Glass, Transparency = 0.2, CanCollide = false })
	job:add("City/Plaza", { Name = "FountainJet", Shape = Enum.PartType.Cylinder, Size = Vector3.new(12, 2, 2), CFrame = CFrame.new(f.X, 9, f.Z) * Parts.UP, Color = P.NeonCyan, Material = M.Neon, Transparency = 0.3, CanCollide = false })
	n += 3
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local x, z = centre.X + math.cos(a) * 100, centre.Z + math.sin(a) * 60
		if not blocked(data, x, z, 4) then
			n += palm(job, "City/Plaza", x, z, rng)
		end
	end
	-- neon arches over the plaza walk
	for i = 0, 2 do
		local x = centre.X + 70 + i * 16
		for _, s in ipairs({ -1, 1 }) do
			job:add("City/Plaza", { Name = "ArchPost", Size = Vector3.new(1.2, 16, 1.2), CFrame = CFrame.new(x, 8, centre.Z + s * 14), Color = NEONS[i + 1], Material = M.Neon, CanCollide = false })
		end
		job:add("City/Plaza", { Name = "ArchTop", Size = Vector3.new(1.2, 1.2, 29), CFrame = CFrame.new(x, 16, centre.Z), Color = NEONS[i + 1], Material = M.Neon, CanCollide = false })
		n += 3
	end
	return n, centre
end

local function billboard(job, cf, text, color, sub)
	job:add("City/Billboards", { Name = "BillboardPost", Size = Vector3.new(2, 24, 2), CFrame = cf * CFrame.new(0, 12, 0), Color = P.SteelDark, Material = M.Metal, CanCollide = false })
	job:add("City/Billboards", { Name = "Billboard", Size = Vector3.new(44, 18, 1.4), CFrame = cf * CFrame.new(0, 31, 0), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = text, Color = color } })
	job:add("City/Billboards", { Name = "BillboardFrame", Size = Vector3.new(46, 19.5, 1), CFrame = cf * CFrame.new(0, 31, 0.5), Color = color, Material = M.Neon, CanCollide = false, Light = { Color = color, Range = 26, Brightness = 1 } })
	if sub then
		job:add("City/Billboards", { Name = "BillboardSub", Size = Vector3.new(40, 4, 1.5), CFrame = cf * CFrame.new(0, 24.5, -0.2), Color = color, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = sub, Color = P.Black } })
		return 4
	end
	return 3
end

-- Faces a CFrame at `pos` toward the nearest point of the main road.
local function facingRoad(data, pos)
	local hit = data.main:project(pos, nil, 900)
	local target = if hit then hit.centre else Vector3.new(0, 0, 0)
	return CFrame.lookAt(Vector3.new(pos.X, 0, pos.Z), Vector3.new(target.X, 0, target.Z))
end

local function billboards(job, data)
	local n = 0
	local list = {
		{ 1010, 330, "QUACKARONI'S SNEAKER PARADE", P.NeonYellow, "LIVE ON THE TRACK - WATCH YOUR LANE!" },
		{ 330, -54, "DRIFT FOR BOOST", P.NeonCyan, "HOLD DRIFT - BLUE, ORANGE, PURPLE" },
		{ -560, 1080, "RIVER TUNNEL", P.NeonCyan, nil },
		{ 300, 1460, "STADIUM OF CHAOS", P.NeonPink, "FINAL LAP = MORE CHAOS" },
		{ 260, 900, "BIG JUMP AHEAD", P.NeonPink, nil },
		{ -720, 300, "HAIRPIN HAVOC", P.NeonOrange, "BRAKE? NEVER." },
		{ 640, -54, "ROOFTOP LEAP?", P.NeonGreen, "BOOST OR BUST" },
		{ -300, 480, "CHAOS PARK", P.NeonGreen, nil },
	}
	for _, b in ipairs(list) do
		local pos = Vector3.new(b[1], 0, b[2])
		if not blocked(data, pos.X, pos.Z, 6) then
			n += billboard(job, facingRoad(data, pos), b[3], b[4], b[5])
		end
	end
	return n
end

-- The parking garage in the bowl's infield (the Rooftop Leap runs over its roof) and the
-- spiral ramp tower beside it.
local function garage(job, data)
	local sc = data.byId.RooftopLeap
	if not sc then
		return 0
	end
	local n = 0
	local a = sc.track:frame(sc.pointDist[4], 0, 0)
	local b = sc.track:frame(sc.pointDist[6], 0, 0)
	local mid = (a.Position + b.Position) / 2
	local look = (b.Position - a.Position)
	local len = Vector3.new(look.X, 0, look.Z).Magnitude
	local frame = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.Position.X, 0, b.Position.Z))
	local width = sc.def.w + sc.def.sh * 2 + 3
	for floor = 0, 3 do
		local y = 1 + floor * 6
		job:add("City/Garage", { Name = "GarageDeck", Size = Vector3.new(width, 1, len + 20), CFrame = frame * CFrame.new(0, y, 0), Color = P.Concrete, Material = M.Concrete, CanCollide = false })
		n += 1
		for _, s2 in ipairs({ -1, 1 }) do
			job:add("City/Garage", { Name = "GarageStripe", Size = Vector3.new(0.6, 0.9, len + 20), CFrame = frame * CFrame.new(s2 * (width / 2 + 0.5), y + 2.6, 0), Color = if floor % 2 == 0 then P.NeonYellow else P.NeonCyan, Material = M.Neon, CanCollide = false })
			n += 1
		end
	end
	for _, s2 in ipairs({ -1, 1 }) do
		for i = -2, 2 do
			job:add("City/Garage", { Name = "GarageColumn", Size = Vector3.new(2.4, 23, 2.4), CFrame = frame * CFrame.new(s2 * (width / 2 - 1.5), 11.5, i * (len + 16) / 4), Color = P.ConcreteDark, Material = M.Concrete, CanCollide = false })
			n += 1
		end
	end
	job:add("City/Garage", { Name = "GarageSign", Size = Vector3.new(22, 14, 1), CFrame = frame * CFrame.new(width / 2 + 6, 34, 0) * CFrame.Angles(0, math.rad(90), 0), Color = P.Blue, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = "P", Color = P.White }, Light = { Color = P.Blue, Range = 30, Brightness = 1.2 } })
	n += 1
	-- spiral ramp tower
	local tower = frame * CFrame.new(-width / 2 - 26, 0, -len / 4)
	job:add("City/Garage", { Name = "SpiralCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(34, 10, 10), CFrame = tower * CFrame.new(0, 17, 0) * Parts.UP, Color = P.ConcreteDark, Material = M.Concrete, CanCollide = false })
	for i = 0, 9 do
		local ang = i * math.rad(40)
		job:add("City/Garage", { Name = "SpiralRamp", Size = Vector3.new(14, 1, 9), CFrame = tower * CFrame.Angles(0, ang, 0) * CFrame.new(10, 2 + i * 3.2, 0) * CFrame.Angles(0, 0, math.rad(8)), Color = if i % 2 == 0 then P.Concrete else P.Sidewalk, Material = M.Concrete, CanCollide = false })
	end
	n += 11
	return n
end

local function stadium(job, data, rng)
	local zone = data.zoneById.Stadium
	if not zone then
		return 0
	end
	local mid = data.main:at(zone.from + zone.span / 2)
	local centre = mid.pos + mid.right * -1 * 0 + Vector3.new(0, 0, 185)
	local n = 0
	local rx, rz = 180, 105
	job:add("City/Stadium", { Name = "Pitch", Size = Vector3.new(rx * 1.4, 0.4, rz * 1.3), CFrame = CFrame.new(centre.X, 0.1, centre.Z), Color = rgb(70, 170, 80), Material = M.Grass, CanCollide = false })
	n += 1
	local segs = 18
	for i = 0, segs - 1 do
		local a = i / segs * math.pi * 2
		local x, z = centre.X + math.cos(a) * rx, centre.Z + math.sin(a) * rz
		if not blocked(data, x, z, 10) then
			local cf = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(centre.X, 0, centre.Z))
			job:add("City/Stadium", { Name = "Stand", Size = Vector3.new(66, 16, 22), CFrame = cf * CFrame.new(0, 8, 6) * CFrame.Angles(math.rad(-18), 0, 0), Color = if i % 2 == 0 then rgb(60, 60, 130) else rgb(90, 60, 140), Material = M.Concrete, CanCollide = false })
			job:add("City/Stadium", { Name = "StandRail", Size = Vector3.new(66, 1.2, 1.2), CFrame = cf * CFrame.new(0, 17, 12), Color = NEONS[i % #NEONS + 1], Material = M.Neon, CanCollide = false })
			n += 2
		end
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local x, z = centre.X + math.cos(a) * (rx + 22), centre.Z + math.sin(a) * (rz + 22)
		if not blocked(data, x, z, 4) then
			job:add("City/Stadium", { Name = "FloodTower", Size = Vector3.new(3, 46, 3), CFrame = CFrame.new(x, 23, z), Color = P.SteelDark, Material = M.Metal, CanCollide = false })
			job:add("City/Stadium", { Name = "FloodLights", Size = Vector3.new(12, 6, 2), CFrame = CFrame.lookAt(Vector3.new(x, 48, z), Vector3.new(centre.X, 0, centre.Z)), Color = P.White, Material = M.Neon, CanCollide = false, Light = { Color = rgb(255, 245, 220), Range = 60, Brightness = 2, Spot = true, Face = Enum.NormalId.Front, Angle = 70 } })
			n += 2
		end
	end
	job:add("City/Stadium", { Name = "Scoreboard", Size = Vector3.new(50, 20, 2), CFrame = CFrame.lookAt(centre + Vector3.new(0, 40, rz + 30), centre + Vector3.new(0, 40, -100)), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = "CHAOS STADIUM", Color = P.NeonYellow }, Light = { Color = P.NeonYellow, Range = 40, Brightness = 1 } })
	n += 1
	local _ = rng
	return n
end

local function park(job, data, rng)
	local n = 0
	local count = 0
	for _ = 1, 160 do
		if count >= 34 then
			break
		end
		local x = rng:NextNumber(-520, 40)
		local z = rng:NextNumber(460, 760)
		if not blocked(data, x, z, 8) then
			n += tree(job, "City/Park", x, z, rng)
			count += 1
		end
	end
	job:add("City/Park", { Name = "Pond", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 90, 90), CFrame = CFrame.new(-250, 0.05, 600) * Parts.UP, Color = P.Water, Material = M.Glass, Transparency = 0.15, CanCollide = false })
	job:add("City/Park", { Name = "PondEdge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 94, 94), CFrame = CFrame.new(-250, 0, 600) * Parts.UP, Color = P.Sidewalk, Material = M.Concrete, CanCollide = false })
	n += 2
	return n
end

-- Arches over the river bridge (north leg): a red steel arch each side, with hangers.
local function bridgeArches(job, data)
	local n = 0
	local river = data.def.River
	if not river then
		return 0
	end
	local main = data.main
	-- the bridge: the main-track stretch over the river (north leg, tagged bridge)
	local d0, d1 = nil, nil
	for _, s in ipairs(main.samples) do
		if s.tags.bridge and s.pos.Z > river.z0 - 40 and s.pos.Z < river.z1 + 40 then
			d0 = if d0 then math.min(d0, s.dist) else s.dist
			d1 = if d1 then math.max(d1, s.dist) else s.dist
		end
	end
	if not d0 then
		return 0
	end
	local SEG = 10
	for _, side in ipairs({ -1, 1 }) do
		local prev = nil
		for i = 0, SEG do
			local u = i / SEG
			local s = main:at(d0 + (d1 - d0) * u)
			local rise = 30 * math.sin(u * math.pi)
			local p = s.pos + s.right * side * (s.w / 2 + s.sh + 2.5) + Vector3.new(0, 4 + rise, 0)
			if prev then
				local cf, len = Parts.beamCFrame(prev, p)
				job:add("City/Bridge", { Name = "Arch", Size = Vector3.new(2.6, 2.6, len + 1), CFrame = cf, Color = P.Red, Material = M.Metal, CanCollide = false })
				n += 1
			end
			if i > 0 and i < SEG then
				local deck = s.pos + s.right * side * (s.w / 2 + s.sh + 2.5)
				local h = p.Y - deck.Y
				job:add("City/Bridge", { Name = "Hanger", Size = Vector3.new(0.5, h, 0.5), CFrame = CFrame.new(deck + Vector3.new(0, h / 2, 0)), Color = P.White, CanCollide = false })
				n += 1
			end
			prev = p
		end
	end
	-- a neon crown along the top of both arches
	local top = main:at((d0 + d1) / 2)
	job:add("City/Bridge", { Name = "BridgeSign", Size = Vector3.new(top.w + 10, 4, 0.8), CFrame = CFrame.lookAt(top.pos + Vector3.new(0, 30, 0), top.pos + Vector3.new(0, 30, 0) - top.flat), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = "CHAOS RIVER BRIDGE", Color = P.NeonCyan } })
	return n + 1
end

-- Street lamps along the downtown straight, tyre stacks at the hairpin, cones.
local function props(job, data, rng)
	local n = 0
	local main = data.main
	local d = 0
	while d < main.length do
		local s = main:at(d)
		if s.tags.downtown or s.tags.park or s.tags.highway then
			for _, side in ipairs({ -1, 1 }) do
				local p = s.pos + s.right * side * (s.w / 2 + s.sh + 4.5)
				if clearance(data, p.X, p.Z) > -3 then
					job:add("City/Lamps", { Name = "LampPost", Size = Vector3.new(0.8, 16, 0.8), CFrame = CFrame.new(p + Vector3.new(0, 8, 0)), Color = P.SteelDark, Material = M.Metal, CanCollide = false })
					job:add("City/Lamps", { Name = "Lamp", Size = Vector3.new(4, 0.8, 1.6), CFrame = CFrame.lookAt(p + Vector3.new(0, 16, 0), p + Vector3.new(0, 16, 0) - s.right * side) * CFrame.new(0, 0, -1.5), Color = if s.tags.downtown then P.NeonPink else rgb(255, 230, 170), Material = M.Neon, CanCollide = false, Light = if (d // 72) % 2 == 0 then { Color = rgb(255, 214, 160), Range = 28, Brightness = 1.4 } else nil })
					n += 2
				end
			end
		end
		d += 72
	end
	local hairpin = data.zoneById.Hairpin
	if hairpin then
		for i = 0, 10 do
			local s = main:at(hairpin.from + hairpin.span * i / 10)
			local p = s.pos + s.right * -(s.w / 2 + s.sh + 6)
			if clearance(data, p.X, p.Z) > 1 then
				for k = 0, 1 do
					job:add("City/Props", { Name = "TyreStack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 4, 4), CFrame = CFrame.new(p + Vector3.new(0, 1.1 + k * 2.2, 0)) * Parts.UP, Color = if k == 0 then P.Black else P.CurbRed, CanCollide = false })
					n += 1
				end
			end
		end
	end
	for _ = 1, 24 do
		local s = main:at(rng:NextNumber(0, main.length))
		local p = s.pos + s.right * (if rng:NextNumber() < 0.5 then -1 else 1) * (s.w / 2 + s.sh + 3)
		if clearance(data, p.X, p.Z) > -2 and p.Y < 1 then
			job:add("City/Props", { Name = "Cone", Size = Vector3.new(1.4, 2.4, 1.4), CFrame = CFrame.new(p + Vector3.new(0, 1.2, 0)), Color = P.Orange, CanCollide = false })
			n += 1
		end
	end
	return n
end

function CityBuilder.plan(data, job, seed)
	local rng = Rng.new(seed or 2024)
	local n = 0
	placed = {}
	n += cityGround(job)
	n += downtown(job, data, rng)
	n += district(job, data, rng, 1080, -300, 1550, 900, 12, 40, 110) -- east of the bowl
	n += district(job, data, rng, -1500, -350, -900, 900, 12, 40, 100) -- west
	n += district(job, data, rng, 350, 1350, 1100, 1900, 8, 30, 80) -- south-east
	n += district(job, data, rng, -1300, 1300, -500, 1900, 7, 30, 80) -- south-west
	local plazaCount, plazaCentre = plaza(job, data, rng)
	n += plazaCount
	n += skyline(job, rng)
	n += billboards(job, data)
	n += garage(job, data)
	n += stadium(job, data, rng)
	n += park(job, data, rng)
	n += bridgeArches(job, data)
	n += props(job, data, rng)
	n += neighbourhoods(job, data, rng)
	return { parts = n, plaza = plazaCentre }
end

return CityBuilder
