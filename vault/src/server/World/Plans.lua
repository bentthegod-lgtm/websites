--[[
	Plans - the floor plans and architecture of depths B1-B5 (B6 / B7 use the classic
	columned chamber from VaultBuilder + Themes). Every depth shares the facility's arrival
	hall, elevator, base materials and signage language, but each chamber is its own place:

	  B1 Cash Vault       a long BANKING HALL: marble colonnades split a coffered nave (the
	                      counting floor) from two low-ceilinged side aisles of cash racks;
	                      safe-deposit walls with open drawers; caged cash pyramid at the end.
	  B2 Gold Reserve     a tall FORTIFIED BULLION YARD: riveted steel walls and buttresses,
	                      a mezzanine catwalk on three sides, a ring of heavy gold racks round
	                      a central bullion stack under a gantry crane. Exit far right.
	  B3 Diamond Chamber  a HEXAGONAL HALL: six glass display wings radiate from a faceted
	                      crystal; stepped ceiling rings and cool spot lighting.
	  B4 Emerald Reserve  a NARROW VAULTED GALLERY: arched ceiling ribs over a 44-stud nave,
	                      side alcoves of premium cases behind green-lit arches. Exit far left.
	  B5 Platinum Reserve an INDUSTRIAL HALL: tall warehouse racks on the left, a conveyor and
	                      press line on the right, overhead catwalks, cold strip lighting.

	Loot is STAGED: most spawn points sit on the furniture of each floor (rack shelves,
	counting tables, carts, open drawers, pallets, display pedestals, trays, the conveyor);
	the rest are loose floor points along the walking lanes. VaultBuilder then drops any
	point that Reach finds buried in a part or out of pickup range of a walkable spot.

	Each builder sets ctx.landmark / ctx.rarePoint, adds route keep-outs (lanes that must
	stay clear of loot), points, emitters and lights.
]]

local Props = require(script.Parent.Props)
local Themes = require(script.Parent.Themes)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)

local Plans = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local C = Props.Colors
local X, Z = Vector3.xAxis, Vector3.zAxis
local UP = CFrame.Angles(0, 0, math.pi / 2)
local W2 = GameConfig.RoomWidth / 2 -- 70
local BACK = GameConfig.RoomBack -- 60
local CH0 = -38 -- chamber starts here (end of the arrival hall)

local H = Themes.helpers
local point, reserve, emitter, light, decoLoot = H.point, H.reserve, H.emitter, H.light, H.decoLoot

-- Per-depth layout: ceiling height, exit door x, which side the deposit machine is on.
Plans.Layout = {
	[1] = { H = 30, exitX = 0, depositSide = -1 },
	[2] = { H = 36, exitX = 38, depositSide = 1 },
	[3] = { H = 32, exitX = 0, depositSide = -1 },
	[4] = { H = 26, exitX = -36, depositSide = 1 },
	[5] = { H = 38, exitX = 40, depositSide = -1 },
	[6] = { H = 30, exitX = 0, depositSide = -1 },
	[7] = { H = 30, exitX = 0, depositSide = -1 },
}

local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

-- A colliding wall between two floor points (x, z), `height` tall.
local function wall(ctx, name, x1, z1, x2, z2, height, thick, color, material, yBase)
	local a, b2 = Vector3.new(x1, 0, z1), Vector3.new(x2, 0, z2)
	local len = (b2 - a).Magnitude
	local mid = (a + b2) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, ctx.y0 + (yBase or 0) + height / 2, mid.Z), Vector3.new(b2.X, ctx.y0 + (yBase or 0) + height / 2, b2.Z))
	return ctx.b.part({ Name = name, Size = Vector3.new(thick or 2, height, len), CFrame = cf, Color = color, Material = material or ctx.style.WallMaterial })
end

-- Open rack; shelves below `maxShelf` become loot points (dx offsets along the rack).
local function stagedRack(ctx, cf, width, depth, shelves, height, color, heavy, dxs, sizes, label, boxColor)
	local tops = Props.rack(ctx.b, cf, width, depth, shelves, height, color, heavy)
	for i, top in ipairs(tops) do
		if sizes[i] then
			for _, dx in ipairs(dxs) do
				point(ctx, top * CFrame.new(dx, 0, 0), sizes[i], "Shelf")
			end
		elseif i == #tops then
			for _, dx in ipairs({ -width / 3, 0, width / 3 }) do
				local box = ctx.b.deco({ Name = "SealedBox", Size = Vector3.new(math.min(3, width / 3.4), 1.4, depth * 0.7), CFrame = top * CFrame.new(dx, 0.7, 0), Color = boxColor or rgb(96, 100, 108), Material = M.Metal })
				if dx == 0 and label then
					Props.text(box, Enum.NormalId.Front, label, { PPS = 30, Color = C.Hazard })
				end
			end
		end
	end
	return tops
end

local function cashPallet(ctx, x, z, accent)
	local b, y0 = ctx.b, ctx.y0
	local top = Props.pallet(b, CFrame.new(x, y0, z))
	b.part({ Name = "WrappedCash", Size = Vector3.new(3.2, 1.4, 2.8), CFrame = top * CFrame.new(0, 0.7, 0), Color = rgb(112, 158, 98), Material = M.Fabric })
	b.deco({ Name = "Wrap", Size = Vector3.new(3.3, 1.5, 2.9), CFrame = top * CFrame.new(0, 0.75, 0), Color = rgb(230, 240, 255), Material = M.Glass, Transparency = 0.7 })
	b.deco({ Name = "PalletStrap", Size = Vector3.new(0.3, 1.55, 2.95), CFrame = top * CFrame.new(0, 0.75, 0), Color = accent, Material = M.Fabric })
	point(ctx, top * CFrame.new(-0.7, 1.4, 0), "M", "Pallet")
	point(ctx, top * CFrame.new(0.8, 1.4, 0), "S", "Pallet")
end

-- B1 Cash Vault: banking hall -----------------------------------------------------------------

local function cashVault(ctx)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	local accent, trim = Props.rgb(ctx.palette.Accent), Props.rgb(ctx.palette.Trim)
	local marble, brass = rgb(214, 208, 196), rgb(196, 160, 80)
	local COL_X = 20
	local zs = { -30, -16, -2, 12, 26, 40, 54 }
	-- Hall portal: two big columns and an arch sign over the nave.
	for _, x in ipairs({ -COL_X, COL_X }) do
		for _, z in ipairs(zs) do
			b.cyl({ Name = "Column", Size = Vector3.new(ht - 4, 3, 3), CFrame = CFrame.new(x, y0 + (ht - 4) / 2, z) * UP, Color = marble, Material = M.Marble })
			b.deco({ Name = "ColumnBase", Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(x, y0 + 0.5, z), Color = trim, Material = M.Marble })
			b.deco({ Name = "Capital", Size = Vector3.new(4, 1.2, 4), CFrame = CFrame.new(x, y0 + ht - 4.6, z), Color = brass, Material = M.Metal })
		end
		-- Architrave over each colonnade.
		b.deco({ Name = "Architrave", Size = Vector3.new(3, 4, BACK - CH0), CFrame = CFrame.new(x, y0 + ht - 2, (CH0 + BACK) / 2), Color = marble, Material = M.Marble })
		b.deco({ Name = "ArchitraveTrim", Size = Vector3.new(3.2, 0.4, BACK - CH0), CFrame = CFrame.new(x, y0 + ht - 4.1, (CH0 + BACK) / 2), Color = brass, Material = M.Metal })
		reserve(ctx, x - 2.5, x + 2.5, CH0, BACK)
	end
	Props.sign(b, facing(Vector3.new(0, y0 + ht - 6, CH0 + 0.5), -Z), 30, 2.6, "MAIN BANKING HALL  -  B1", { Color = brass, PPS = 30 })
	-- Coffered nave ceiling.
	for z = CH0 + 4, BACK - 2, 8 do
		b.deco({ Name = "Coffer", Size = Vector3.new(COL_X * 2, 1.2, 0.8), CFrame = CFrame.new(0, y0 + ht - 0.6, z), Color = trim, Material = M.Marble })
	end
	for _, x in ipairs({ -12, -4, 4, 12 }) do
		b.deco({ Name = "Coffer", Size = Vector3.new(0.8, 1.2, BACK - CH0), CFrame = CFrame.new(x, y0 + ht - 0.6, (CH0 + BACK) / 2), Color = trim, Material = M.Marble })
	end
	-- Low soffit ceilings over the side aisles with recessed light strips.
	ctx.lights = {}
	for _, side in ipairs({ -1, 1 }) do
		local cx = side * (COL_X + W2) / 2
		b.deco({ Name = "Soffit", Size = Vector3.new(W2 - COL_X - 1.5, 1, BACK - CH0), CFrame = CFrame.new(cx, y0 + 16.5, (CH0 + BACK) / 2), Color = trim, Material = M.Concrete })
		for z = CH0 + 8, BACK - 4, 18 do
			local tube, l = Props.lightFixture(b, CFrame.new(cx, y0 + 15.8, z), Props.rgb(ctx.palette.Light), 1.8, 26, 14)
			tube.Name = "SoffitLight"
			l.Shadows = false
			table.insert(ctx.lights, l)
		end
	end
	for _, z in ipairs({ -14, 14, 40 }) do
		local _, l = Props.lightFixture(b, CFrame.new(0, y0 + ht - 1.6, z), Props.rgb(ctx.palette.Light), 2.4, 40, 10)
		l.Shadows = z == 14
		table.insert(ctx.lights, l)
	end
	-- Counting floor: an inlaid marble field down the nave with six counting tables.
	b.deco({ Name = "CountingFloor", Size = Vector3.new(30, 0.06, BACK - CH0 - 8), CFrame = CFrame.new(0, y0 + 0.03, (CH0 + BACK) / 2), Color = rgb(70, 64, 56), Material = M.Marble, CastShadow = false })
	for _, x in ipairs({ -15, 15 }) do
		b.deco({ Name = "FloorBorder", Size = Vector3.new(0.5, 0.07, BACK - CH0 - 8), CFrame = CFrame.new(x, y0 + 0.035, (CH0 + BACK) / 2), Color = brass, Material = M.Metal, CastShadow = false })
	end
	for _, x in ipairs({ -10, 10 }) do
		for _, z in ipairs({ -24, -6, 12 }) do
			local top = Props.table(b, facing(Vector3.new(x, y0, z), X), 9, 3.6, 3.2, C.SteelLight)
			b.deco({ Name = "Counter", Size = Vector3.new(1.4, 1.2, 1.8), CFrame = top * CFrame.new(3.6, 0.6, 0), Color = rgb(40, 44, 50), Material = M.Metal })
			b.deco({ Name = "CounterDisplay", Size = Vector3.new(0.05, 0.4, 1.2), CFrame = top * CFrame.new(2.85, 0.9, 0), Color = rgb(80, 255, 140), Material = M.Neon })
			for _, dx in ipairs({ -3, -0.6, 1.8 }) do
				point(ctx, top * CFrame.new(dx, 0, 0), "M", "Table")
			end
			reserve(ctx, x - 2.4, x + 2.4, z - 5, z + 5)
		end
	end
	-- Side aisles: rows of open cash racks running out from the colonnade to the wall.
	local rows = { -28, -10, 8, 26, 44 }
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs(rows) do
			stagedRack(ctx, facing(Vector3.new(side * 44, y0, z), Z), 16, 3.2, 3, 7.6, C.Steel, false, { -5.2, 0, 5.2 }, { "M", "S" }, "CURRENCY")
			reserve(ctx, side * 44 - 8.5, side * 44 + 8.5, z - 2.2, z + 2.2)
		end
		-- Cash carts parked in the aisles between the rows.
		for _, z in ipairs({ -19, 17, 35 }) do
			local cf = facing(Vector3.new(side * 28, y0, z), X)
			local top = Props.table(b, cf, 3.6, 2.2, 2.6, rgb(70, 74, 82))
			for _, rx in ipairs({ -1.8, 1.8 }) do
				b.deco({ Name = "CartRail", Size = Vector3.new(0.12, 0.8, 2.2), CFrame = top * CFrame.new(rx, 0.4, 0), Color = C.SteelLight, Material = M.Metal })
			end
			b.deco({ Name = "CartHandle", Size = Vector3.new(0.15, 1.2, 2), CFrame = top * CFrame.new(-2.1, 0.6, 0), Color = C.SteelDark, Material = M.Metal })
			point(ctx, top * CFrame.new(-0.8, 0, 0), "S", "Cart")
			point(ctx, top * CFrame.new(0.9, 0, 0), "M", "Cart")
			reserve(ctx, side * 28 - 2, side * 28 + 2, z - 2.6, z + 2.6)
		end
		-- Safe-deposit wall along the outer wall, with open drawers holding cash.
		for col = 0, 18 do
			local z = CH0 + 3 + col * 5
			for row = 0, 2 do
				b.deco({ Name = "DepositBox", Size = Vector3.new(0.5, 2.3, 4.6), CFrame = CFrame.new(side * (W2 - 0.3), y0 + 5.2 + row * 2.5, z), Color = if (col + row) % 2 == 0 then rgb(176, 168, 150) else rgb(156, 150, 134), Material = M.Metal })
			end
		end
		b.deco({ Name = "DepositWallTrim", Size = Vector3.new(0.7, 0.5, BACK - CH0), CFrame = CFrame.new(side * (W2 - 0.4), y0 + 12.8, (CH0 + BACK) / 2), Color = brass, Material = M.Metal })
		for _, z in ipairs({ -19, -1, 17, 35 }) do
			local drawer = b.part({ Name = "OpenDrawer", Size = Vector3.new(1.8, 0.5, 2.6), CFrame = CFrame.new(side * (W2 - 0.9), y0 + 3, z), Color = brass, Material = M.Metal })
			b.deco({ Name = "DrawerFront", Size = Vector3.new(0.15, 0.9, 2.6), CFrame = drawer.CFrame * CFrame.new(-side * 0.95, 0.2, 0), Color = rgb(156, 150, 134), Material = M.Metal })
			point(ctx, CFrame.new(side * (W2 - 1.1), y0 + 3.25, z), "S", "Drawer")
		end
		-- Wrapped cash pallets by the deposit wall.
		for _, z in ipairs({ -19, 17 }) do
			cashPallet(ctx, side * 62, z + 9, accent)
			reserve(ctx, side * 62 - 2.4, side * 62 + 2.4, z + 6.6, z + 11.4)
		end
	end
	-- Loose bills along the lanes: beside the counting tables and between the rack rows.
	for _, x in ipairs({ -16.2, 16.2 }) do
		for z = -32, 32, 8 do
			point(ctx, CFrame.new(x, y0, z), "L", "Floor")
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -19, -1, 17, 35, 52 }) do
			for _, x in ipairs({ 40, 50 }) do
				point(ctx, CFrame.new(side * x, y0, z), "L", "Floor")
			end
		end
	end
	-- Landmark: a caged pyramid of banded cash on a gold-trimmed dais at the end of the nave.
	local base = CFrame.new(0, y0, 44)
	b.cyl({ Name = "Dais", Size = Vector3.new(1, 15, 15), CFrame = base * CFrame.new(0, 0.5, 0) * UP, Color = rgb(60, 62, 68), Material = M.Marble })
	b.cyl({ Name = "DaisTrim", Size = Vector3.new(0.3, 15.4, 15.4), CFrame = base * CFrame.new(0, 1.05, 0) * UP, Color = accent, Material = M.Metal, CanCollide = false })
	local layer = 0
	for n = 4, 1, -1 do
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local x, z = (i - (n - 1) / 2) * 2.3, (j - (n - 1) / 2) * 1.5
				b.deco({ Name = "CashBrick", Size = Vector3.new(2.2, 0.9, 1.4), CFrame = base * CFrame.new(x, 1.65 + layer * 0.92, z), Color = rgb(112, 158, 98), Material = M.Fabric })
				if (i + j + layer) % 2 == 0 then
					b.deco({ Name = "CashBand", Size = Vector3.new(0.4, 0.94, 1.44), CFrame = base * CFrame.new(x, 1.65 + layer * 0.92, z), Color = C.White })
				end
			end
		end
		layer += 1
	end
	for _, p in ipairs({ { -5.5, -5.5 }, { 5.5, -5.5 }, { -5.5, 5.5 }, { 5.5, 5.5 } }) do
		b.part({ Name = "CagePost", Size = Vector3.new(0.6, 8, 0.6), CFrame = base * CFrame.new(p[1], 5, p[2]), Color = accent, Material = M.Metal })
	end
	for _, s in ipairs({ { 0, -5.5, 11, 0.3 }, { 0, 5.5, 11, 0.3 }, { -5.5, 0, 0.3, 11 }, { 5.5, 0, 0.3, 11 } }) do
		b.part({ Name = "CageGlass", Size = Vector3.new(s[3], 7.4, s[4]), CFrame = base * CFrame.new(s[1], 4.8, s[2]), Color = C.Glass, Material = M.Glass, Transparency = 0.75, CastShadow = false })
	end
	b.deco({ Name = "CageRoof", Size = Vector3.new(11.6, 0.4, 11.6), CFrame = base * CFrame.new(0, 9, 0), Color = accent, Material = M.Metal })
	local plaque = Props.sign(b, base * CFrame.new(0, 2.2, -8) * CFrame.Angles(0, math.pi, 0), 6, 1, "RESERVE 01  -  $50,000,000", { PPS = 40, Color = accent })
	plaque.CanCollide = false
	local spot = b.deco({ Name = "LandmarkSpot", Size = Vector3.new(2, 0.2, 2), CFrame = base * CFrame.new(0, 14, 0), Color = rgb(255, 240, 210), Material = M.Neon })
	light(spot, "SpotLight", rgb(255, 236, 200), 2.2, 22, false)
	reserve(ctx, -8.5, 8.5, 35.5, 52.5)
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(-12, 0, -6)
	-- Routes kept clear of loot: the nave's centre lane and the lanes round the dais.
	reserve(ctx, -4.5, 4.5, CH0, 34)
	reserve(ctx, -15, 15, 33, 35.5)
	reserve(ctx, -14, -9, 34, BACK)
	reserve(ctx, 9, 14, 34, BACK)
	Props.camera(b, facing(Vector3.new(-COL_X + 1.6, y0 + 12, CH0 + 2), Vector3.new(1, -0.2, 1).Unit))
	Props.camera(b, facing(Vector3.new(COL_X - 1.6, y0 + 12, BACK - 2), Vector3.new(-1, -0.2, -1).Unit))
	emitter(ctx, Vector3.new(-45, y0 + 14, 10), "Ventilation")
	emitter(ctx, Vector3.new(45, y0 + 14, 30), "Ventilation")
	emitter(ctx, Vector3.new(0, y0 + 24, 20), "LightBuzz")
end

-- B2 Gold Reserve: fortified bullion yard -----------------------------------------------------

local function goldReserve(ctx)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	local accent = Props.rgb(ctx.palette.Accent)
	local steel, steelDark, gold = rgb(70, 66, 60), rgb(44, 42, 38), rgb(236, 180, 40)
	-- Riveted steel wall plating and buttresses.
	for _, side in ipairs({ -1, 1 }) do
		for z = CH0 + 7, BACK - 4, 14 do
			b.part({ Name = "Buttress", Size = Vector3.new(2.4, ht, 2.4), CFrame = CFrame.new(side * (W2 - 1.2), y0 + ht / 2, z), Color = steelDark, Material = M.Metal })
			b.deco({ Name = "WallPlate", Size = Vector3.new(0.4, 10, 11), CFrame = CFrame.new(side * (W2 - 0.2), y0 + 6, z + 7), Color = steel, Material = M.DiamondPlate })
			for _, dy in ipairs({ 1.4, 10.6 }) do
				b.deco({ Name = "RivetRow", Size = Vector3.new(0.5, 0.3, 10.6), CFrame = CFrame.new(side * (W2 - 0.45), y0 + dy, z + 7), Color = rgb(120, 112, 100), Material = M.Metal })
			end
		end
	end
	for x = -W2 + 8, W2 - 8, 14 do
		b.deco({ Name = "WallPlate", Size = Vector3.new(11, 10, 0.4), CFrame = CFrame.new(x, y0 + 6, BACK - 0.2), Color = steel, Material = M.DiamondPlate })
	end
	-- Blast-door frame at the yard entrance (the leaves are parked open in the wall).
	for _, x in ipairs({ -15, 15 }) do
		b.part({ Name = "BlastFrame", Size = Vector3.new(3, 16, 3), CFrame = CFrame.new(x, y0 + 8, CH0 + 1), Color = steelDark, Material = M.Metal })
		b.part({ Name = "BlastLeaf", Size = Vector3.new(10, 14, 1.4), CFrame = CFrame.new(x + (if x < 0 then -6.5 else 6.5), y0 + 7, CH0 + 1.5), Color = steel, Material = M.DiamondPlate })
	end
	b.deco({ Name = "BlastLintel", Size = Vector3.new(33, 3, 3), CFrame = CFrame.new(0, y0 + 17.5, CH0 + 1), Color = steelDark, Material = M.Metal })
	Props.hazardStripes(b, CFrame.new(0, y0, CH0 + 1), 27, 1.4)
	Props.sign(b, facing(Vector3.new(0, y0 + 17.5, CH0 - 0.6), -Z), 20, 1.8, "BULLION YARD  -  B2", { Color = gold, PPS = 30 })
	reserve(ctx, -26, -13, CH0, CH0 + 3)
	reserve(ctx, 13, 26, CH0, CH0 + 3)
	-- Mezzanine catwalk round three sides (the yard's upper level), on posts.
	local mz = 12
	for _, side in ipairs({ -1, 1 }) do
		b.deco({ Name = "Mezzanine", Size = Vector3.new(6, 0.5, BACK - CH0 - 4), CFrame = CFrame.new(side * (W2 - 5.4), y0 + mz, (CH0 + BACK) / 2 + 2), Color = steelDark, Material = M.DiamondPlate })
		b.deco({ Name = "MezzRail", Size = Vector3.new(0.25, 0.25, BACK - CH0 - 4), CFrame = CFrame.new(side * (W2 - 8.5), y0 + mz + 3.2, (CH0 + BACK) / 2 + 2), Color = C.Hazard, Material = M.Metal })
		b.deco({ Name = "MezzKick", Size = Vector3.new(0.2, 0.8, BACK - CH0 - 4), CFrame = CFrame.new(side * (W2 - 8.5), y0 + mz + 0.6, (CH0 + BACK) / 2 + 2), Color = C.Hazard, Material = M.Metal })
		for z = CH0 + 8, BACK - 6, 14 do
			b.part({ Name = "MezzPost", Size = Vector3.new(0.6, mz, 0.6), CFrame = CFrame.new(side * (W2 - 8.5), y0 + mz / 2, z), Color = steelDark, Material = M.Metal })
			b.deco({ Name = "MezzRailPost", Size = Vector3.new(0.25, 3.2, 0.25), CFrame = CFrame.new(side * (W2 - 8.5), y0 + mz + 1.6, z), Color = C.Hazard, Material = M.Metal })
		end
	end
	b.deco({ Name = "Mezzanine", Size = Vector3.new(W2 * 2 - 4, 0.5, 6), CFrame = CFrame.new(0, y0 + mz, BACK - 3), Color = steelDark, Material = M.DiamondPlate })
	b.deco({ Name = "MezzRail", Size = Vector3.new(W2 * 2 - 18, 0.25, 0.25), CFrame = CFrame.new(0, y0 + mz + 3.2, BACK - 6.1), Color = C.Hazard, Material = M.Metal })
	for i = 0, 9 do
		b.deco({ Name = "MezzStair", Size = Vector3.new(3, 0.4, 1.4), CFrame = CFrame.new(-W2 + 4, y0 + 1.2 * (i + 1), CH0 + 22 - i * 1.4), Color = steelDark, Material = M.DiamondPlate })
	end
	-- Ring of heavy gold racks round the central bullion stack.
	local centre = Vector3.new(0, y0, 12)
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local pos = centre + Vector3.new(math.sin(a) * 17, 0, math.cos(a) * 17)
		local cf = CFrame.lookAt(pos, Vector3.new(centre.X, y0, centre.Z))
		local tops = stagedRack(ctx, cf, 8.6, 2.6, 3, 6.6, steel, true, { -2.8, 0, 2.8 }, { "M", "S" }, "BULLION", rgb(70, 66, 60))
		b.deco({ Name = "RackPlate", Size = Vector3.new(8.6, 0.5, 0.2), CFrame = cf * CFrame.new(0, 6.9, -1.4), Color = gold, Material = M.Metal })
		decoLoot(ctx, "GoldBrick", tops[3] * CFrame.new(0, 1.4, 0))
	end
	-- Central bullion stack on a steel plinth.
	local base = CFrame.new(centre)
	b.part({ Name = "StackPlinth", Size = Vector3.new(7, 1, 7), CFrame = base * CFrame.new(0, 0.5, 0), Color = steelDark, Material = M.DiamondPlate })
	b.deco({ Name = "StackKerb", Size = Vector3.new(7.6, 0.25, 7.6), CFrame = base * CFrame.new(0, 1.05, 0), Color = C.Hazard, Material = M.Metal })
	for layer = 0, 4 do
		local n = 4 - math.floor(layer / 2)
		for i = 0, n - 1 do
			local along = (i - (n - 1) / 2) * 1.4
			local cf = base * CFrame.new(0, 1.3 + layer * 0.62, 0) * CFrame.Angles(0, if layer % 2 == 0 then 0 else math.pi / 2, 0)
			for j = -1, 1 do
				b.deco({ Name = "StackBar", Size = Vector3.new(2.6, 0.6, 1.2), CFrame = cf * CFrame.new(j * 0.2, 0, along), Color = rgb(236, 184, 58), Material = M.Metal, Reflectance = 0.2 })
			end
		end
	end
	Props.hazardStripes(b, base * CFrame.new(0, 0, -7), 12, 0.8)
	-- Gantry crane over the stack: rails on the buttresses, bridge, trolley, a lifted load.
	for _, x in ipairs({ -(W2 - 3), W2 - 3 }) do
		b.deco({ Name = "CraneRail", Size = Vector3.new(1.4, 1.4, BACK - CH0 - 6), CFrame = CFrame.new(x, y0 + 26, (CH0 + BACK) / 2), Color = accent, Material = M.Metal })
	end
	for _, dz in ipairs({ -2, 2 }) do
		b.deco({ Name = "CraneBridge", Size = Vector3.new(W2 * 2 - 6, 2.6, 2.4), CFrame = CFrame.new(0, y0 + 27.4, centre.Z + dz), Color = gold, Material = M.Metal })
	end
	for i = -7, 7 do
		b.deco({ Name = "BridgeStripe", Size = Vector3.new(2, 2.62, 0.05), CFrame = CFrame.new(i * 4, y0 + 27.4, centre.Z - 3.22), Color = if i % 2 == 0 then C.Hazard else C.Black, CastShadow = false })
	end
	b.deco({ Name = "Trolley", Size = Vector3.new(5, 2.2, 6.4), CFrame = CFrame.new(0, y0 + 25.6, centre.Z), Color = steelDark, Material = M.Metal })
	b.deco({ Name = "HoistCable", Size = Vector3.new(0.18, 9, 0.18), CFrame = CFrame.new(0, y0 + 20, centre.Z), Color = C.Black, CastShadow = false })
	b.deco({ Name = "HookBlock", Size = Vector3.new(3.4, 1.4, 1.6), CFrame = CFrame.new(0, y0 + 15, centre.Z), Color = accent, Material = M.Metal })
	local load = Props.pallet(b, CFrame.new(0, y0 + 11.6, centre.Z))
	decoLoot(ctx, "GoldCrate", load)
	local warm = b.deco({ Name = "GoldGlow", Size = Vector3.new(2, 0.2, 2), CFrame = CFrame.new(0, y0 + 24.2, centre.Z + 4), Color = rgb(255, 200, 120), Material = M.Neon })
	light(warm, "SpotLight", rgb(255, 196, 110), 2.6, 30, false)
	-- Loose gold inside the ring, round the stack (reached through the gaps).
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		point(ctx, CFrame.new(centre + Vector3.new(math.sin(a) * 8.5, 0, math.cos(a) * 8.5)), "L", "Floor")
	end
	-- Heavy wall shelving for bars on the left wall, under the mezzanine.
	for _, z in ipairs({ -22, -2, 18, 38 }) do
		stagedRack(ctx, facing(Vector3.new(-W2 + 4.6, y0, z), X), 10, 2.8, 3, 7, steel, true, { -3.2, 0, 3.2 }, { "M", "S" }, "AU-999", rgb(70, 66, 60))
		reserve(ctx, -W2, -W2 + 7, z - 6, z + 6)
	end
	-- Stacked gold pallets in the outer yard.
	for _, p in ipairs({ { -44, -28 }, { -56, 48 }, { 56, -26 }, { 56, 48 }, { -32, 40 } }) do
		local top = Props.pallet(b, CFrame.new(p[1], y0, p[2]))
		b.part({ Name = "BarBlock", Size = Vector3.new(3.2, 1.2, 2.8), CFrame = top * CFrame.new(0, 0.6, 0), Color = rgb(236, 184, 58), Material = M.Metal, Reflectance = 0.2 })
		b.deco({ Name = "BarStrap", Size = Vector3.new(0.25, 1.25, 2.85), CFrame = top * CFrame.new(0, 0.62, 0), Color = C.Black, Material = M.Fabric })
		point(ctx, top * CFrame.new(-0.7, 1.2, 0), "M", "Pallet")
		point(ctx, top * CFrame.new(0.8, 1.2, 0), "S", "Pallet")
		reserve(ctx, p[1] - 2.4, p[1] + 2.4, p[2] - 2.2, p[2] + 2.2)
	end
	-- Bullion cages along the back wall (sealed: decor gold inside).
	for _, x in ipairs({ -40, -24, -8 }) do
		local cbase = CFrame.new(x, y0, BACK - 6)
		decoLoot(ctx, "GoldCrate", Props.pallet(b, cbase))
		for _, s in ipairs({ { 0, -3, 6.4, 0.2 }, { -3.1, 0, 0.2, 6 }, { 3.1, 0, 0.2, 6 } }) do
			b.part({ Name = "CageMesh", Size = Vector3.new(s[3], 5.6, s[4]), CFrame = cbase * CFrame.new(s[1], 2.8, s[2]), Color = rgb(90, 86, 80), Material = M.ForceField, Transparency = 0.55, CastShadow = false })
		end
		b.deco({ Name = "CageTop", Size = Vector3.new(6.4, 0.3, 6.4), CFrame = cbase * CFrame.new(0, 5.7, 0), Color = steelDark, Material = M.DiamondPlate })
		reserve(ctx, x - 4, x + 4, BACK - 10, BACK)
	end
	-- Forklift parked by the entrance.
	local fl = facing(Vector3.new(-34, y0, -26), Z)
	b.part({ Name = "ForkliftBody", Size = Vector3.new(3.6, 2.6, 5), CFrame = fl * CFrame.new(0, 1.9, 0), Color = gold, Material = M.Metal })
	b.part({ Name = "ForkliftMast", Size = Vector3.new(3.2, 7, 0.5), CFrame = fl * CFrame.new(0, 3.6, -2.7), Color = rgb(40, 40, 44), Material = M.Metal })
	reserve(ctx, -38, -30, -32, -20)
	-- Loose bars along the outer lanes.
	for _, p in ipairs({ { -30, -6 }, { -30, 12 }, { -30, 28 }, { -50, 4 }, { -50, 24 }, { -14, 44 }, { 4, 44 }, { 26, 40 }, { 50, 0 }, { 50, 20 }, { 26, -2 }, { 26, 22 }, { -14, -20 }, { 50, 34 } }) do
		point(ctx, CFrame.new(p[1], y0, p[2]), "L", "Floor")
	end
	-- High-bay lamps.
	ctx.lights = {}
	for _, x in ipairs({ -44, 0, 44 }) do
		for _, z in ipairs({ -14, 36 }) do
			local _, l = Props.lightFixture(b, CFrame.new(x, y0 + ht - 2, z), Props.rgb(ctx.palette.Light), 2.4, 48, 6)
			l.Shadows = x == 0
			table.insert(ctx.lights, l)
		end
	end
	-- Route: hall -> along the front of the ring -> up the right side to the exit (x 38).
	reserve(ctx, -4, 42, CH0, -24)
	reserve(ctx, 33, 43, -30, BACK)
	ctx.landmark = base
	ctx.rarePoint = CFrame.new(centre + Vector3.new(0, 0, -6))
	Props.camera(b, facing(Vector3.new(-W2 + 3, y0 + mz + 6, CH0 + 4), Vector3.new(1, -0.3, 1).Unit))
	Props.camera(b, facing(Vector3.new(W2 - 3, y0 + mz + 6, BACK - 8), Vector3.new(-1, -0.3, -1).Unit))
	emitter(ctx, Vector3.new(0, y0 + 26, centre.Z), "Machinery")
	emitter(ctx, Vector3.new(-50, y0 + 20, -10), "Ventilation")
	emitter(ctx, Vector3.new(50, y0 + 20, 30), "Ventilation")
end

-- B3 Diamond Chamber: hexagonal hall ---------------------------------------------------------

local function diamondChamber(ctx)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	local accent = Props.rgb(ctx.palette.Accent)
	local plinth, marble, cool = rgb(40, 46, 58), rgb(150, 162, 182), rgb(170, 220, 255)
	local cx, cz = 0, 10
	local A = 44 -- apothem (centre to the middle of a wall)
	local R = A / math.cos(math.rad(30))
	local verts = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		verts[i + 1] = Vector3.new(cx + math.cos(a) * R, 0, cz + math.sin(a) * R)
	end
	local north = cz + A
	-- The six walls; the south and north walls have a 20-stud opening (in from the hall,
	-- out to the exit vestibule).
	for i = 1, 6 do
		local p, q = verts[i], verts[i % 6 + 1]
		local midZ = (p.Z + q.Z) / 2
		local flat = math.abs(p.Z - q.Z) < 0.01
		if flat then
			-- Split round the opening.
			local x0, x1 = math.min(p.X, q.X), math.max(p.X, q.X)
			wall(ctx, "HexWall", x0, midZ, -10, midZ, ht, 2, marble)
			wall(ctx, "HexWall", 10, midZ, x1, midZ, ht, 2, marble)
			b.part({ Name = "HexLintel", Size = Vector3.new(20, ht - 18, 2), CFrame = CFrame.new(0, y0 + 18 + (ht - 18) / 2, midZ), Color = marble, Material = M.Marble })
			b.deco({ Name = "PortalTrim", Size = Vector3.new(21, 0.6, 2.4), CFrame = CFrame.new(0, y0 + 18, midZ), Color = accent, Material = M.Neon })
		else
			wall(ctx, "HexWall", p.X, p.Z, q.X, q.Z, ht, 2, marble)
		end
		-- Cool light pilasters at each corner and wall middle.
		b.deco({ Name = "LightPilaster", Size = Vector3.new(0.8, ht - 6, 0.8), CFrame = CFrame.new(p.X * 0.97, y0 + (ht - 6) / 2 + 1, cz + (p.Z - cz) * 0.97), Color = cool, Material = M.Neon, CastShadow = false })
		b.deco({ Name = "Wainscot", Size = Vector3.new(2.3, 3, (q - p).Magnitude), CFrame = CFrame.lookAt(Vector3.new((p.X + q.X) / 2, y0 + 1.5, midZ), Vector3.new(q.X, y0 + 1.5, q.Z)), Color = rgb(30, 40, 70), Material = M.Marble })
	end
	for _, x in ipairs({ -11, 11 }) do
		wall(ctx, "VestibuleWall", x, north, x, BACK, 20, 2, marble)
	end
	-- Close the dead corners outside the hexagon (they read as solid stone).
	for _, side in ipairs({ -1, 1 }) do
		wall(ctx, "HexClosure", side * R / 2, cz - A, side * W2, cz - A, ht, 2, marble)
		wall(ctx, "HexClosure", side * R / 2, north, side * W2, north, ht, 2, marble)
	end
	for _, p in ipairs({ { -60, -30 }, { 60, -30 }, { -60, 50 }, { 60, 50 } }) do
		b.deco({ Name = "CornerFill", Size = Vector3.new(18, ht, 16), CFrame = CFrame.new(p[1], y0 + ht / 2, p[2]), Color = rgb(30, 34, 44), Material = M.Slate })
	end
	-- Stepped hexagonal ceiling rings and a glowing oculus.
	for k, ring in ipairs({ { 40, ht - 7 }, { 28, ht - 4.5 }, { 16, ht - 2.4 } }) do
		local rr = ring[1] / math.cos(math.rad(30))
		for i = 0, 5 do
			local a1, a2 = math.rad(i * 60), math.rad((i + 1) * 60)
			local p = Vector3.new(cx + math.cos(a1) * rr, y0 + ring[2], cz + math.sin(a1) * rr)
			local q = Vector3.new(cx + math.cos(a2) * rr, y0 + ring[2], cz + math.sin(a2) * rr)
			b.deco({ Name = "CeilingRing" .. k, Size = Vector3.new(2.4 - k * 0.4, 1.4, (q - p).Magnitude + 1), CFrame = CFrame.lookAt((p + q) / 2, q), Color = if k == 3 then accent else rgb(60, 70, 90), Material = if k == 3 then M.Neon else M.Marble })
		end
	end
	b.cyl({ Name = "Oculus", Size = Vector3.new(0.3, 8, 8), CFrame = CFrame.new(cx, y0 + ht - 0.3, cz) * UP, Color = cool, Material = M.Neon, CanCollide = false })
	-- Radial floor inlays.
	for i = 0, 5 do
		local a = math.rad(i * 60 + 30)
		b.deco({ Name = "RadialInlay", Size = Vector3.new(0.5, 0.06, 30), CFrame = CFrame.lookAt(Vector3.new(cx + math.cos(a) * 26, y0 + 0.03, cz + math.sin(a) * 26), Vector3.new(cx + math.cos(a) * 40, y0 + 0.03, cz + math.sin(a) * 40)), Color = accent, Material = M.Neon, CastShadow = false })
	end
	-- Six glass display wings: a low glass partition with open pedestals on both sides.
	ctx.lights = {}
	for _, deg in ipairs({ 0, 45, 135, 180, 225, 315 }) do
		local a = math.rad(deg)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local from, to = Vector3.new(cx, 0, cz) + dir * 15, Vector3.new(cx, 0, cz) + dir * 37
		local p = wall(ctx, "WingGlass", from.X, from.Z, to.X, to.Z, 3.2, 0.6, C.Glass, M.Glass)
		p.Transparency = 0.55
		p.CastShadow = false
		b.deco({ Name = "WingCap", Size = Vector3.new(0.8, 0.25, 22), CFrame = p.CFrame * CFrame.new(0, 1.7, 0), Color = rgb(60, 70, 90), Material = M.Metal })
		for _, r in ipairs({ 18, 24, 30, 36 }) do
			for _, s in ipairs({ -1, 1 }) do
				local pos = Vector3.new(cx, y0, cz) + dir * r + perp * (s * 2.8)
				local cf = CFrame.new(pos)
				b.cyl({ Name = "Pedestal", Size = Vector3.new(2.6, 2.4, 2.4), CFrame = cf * CFrame.new(0, 1.3, 0) * UP, Color = plinth, Material = M.Marble })
				b.cyl({ Name = "PedestalVelvet", Size = Vector3.new(0.12, 2.2, 2.2), CFrame = cf * CFrame.new(0, 2.66, 0) * UP, Color = rgb(30, 40, 90), Material = M.Fabric, CanCollide = false })
				b.cyl({ Name = "PedestalRing", Size = Vector3.new(0.1, 2.6, 2.6), CFrame = cf * CFrame.new(0, 0.1, 0) * UP, Color = accent, Material = M.Neon, CanCollide = false })
				point(ctx, cf * CFrame.new(0, 2.72, 0), if r >= 30 then "M" else "S", "Pedestal")
			end
		end
		local spot = b.deco({ Name = "WingSpot", Size = Vector3.new(1.4, 0.3, 1.4), CFrame = CFrame.new(Vector3.new(cx, y0 + ht - 8, cz) + dir * 26), Color = cool, Material = M.Neon })
		table.insert(ctx.lights, light(spot, "SpotLight", cool, 2.4, 30, false))
	end
	-- Open velvet trays on stands along the four slanted walls.
	for i = 1, 6 do
		local p, q = verts[i], verts[i % 6 + 1]
		if math.abs(p.Z - q.Z) > 0.01 then
			local inward = (Vector3.new(cx, 0, cz) - (p + q) / 2).Unit
			for _, t in ipairs({ 0.28, 0.5, 0.72 }) do
				local pos = p:Lerp(q, t) + inward * 3.4
				local cf = CFrame.lookAt(Vector3.new(pos.X, y0, pos.Z), Vector3.new(pos.X, y0, pos.Z) + inward)
				b.part({ Name = "TrayStand", Size = Vector3.new(3.2, 3, 2), CFrame = cf * CFrame.new(0, 1.5, 0), Color = plinth, Material = M.Metal })
				b.deco({ Name = "Tray", Size = Vector3.new(3, 0.15, 1.8), CFrame = cf * CFrame.new(0, 3.07, 0), Color = rgb(30, 40, 90), Material = M.Fabric })
				for _, tx in ipairs({ -1, 0, 1 }) do
					point(ctx, cf * CFrame.new(tx, 3.15, 0), "S", "Tray")
				end
			end
		end
	end
	-- Centre: the giant crystal inside a laser ring.
	local base = CFrame.new(cx, y0, cz)
	b.cyl({ Name = "Pedestal", Size = Vector3.new(2, 10, 10), CFrame = base * CFrame.new(0, 1, 0) * UP, Color = plinth, Material = M.Marble, Reflectance = 0.1 })
	b.cyl({ Name = "PedestalTier", Size = Vector3.new(1.4, 7, 7), CFrame = base * CFrame.new(0, 2.7, 0) * UP, Color = rgb(60, 70, 90), Material = M.Marble })
	for i = 1, 3 do
		b.cyl({ Name = "Ring" .. i, Size = Vector3.new(0.25, 7 + i * 2.4, 7 + i * 2.4), CFrame = base * CFrame.new(0, 4 + i * 2.2, 0) * UP * CFrame.Angles(math.rad(i * 18), 0, 0), Color = accent, Material = M.Neon, CanCollide = false, Transparency = 0.25 })
	end
	b.deco({ Name = "GiantCrystal", Size = Vector3.new(5.2, 5.2, 5.2), CFrame = base * CFrame.new(0, 8.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(210, 236, 255), Material = M.Glass, Transparency = 0.12, Reflectance = 0.4 })
	b.deco({ Name = "CrystalCore", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = base * CFrame.new(0, 8.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = cool, Material = M.Neon, Transparency = 0.3 })
	for i = 0, 7 do
		local a, a2 = i / 8 * math.pi * 2, (i + 1) / 8 * math.pi * 2
		b.part({ Name = "LaserPost", Size = Vector3.new(0.4, 2.6, 0.4), CFrame = base * CFrame.new(math.cos(a) * 8.5, 1.3, math.sin(a) * 8.5), Color = C.SteelDark, Material = M.Metal })
		local p1 = Vector3.new(math.cos(a) * 8.5, 1.8, math.sin(a) * 8.5)
		local p2 = Vector3.new(math.cos(a2) * 8.5, 1.8, math.sin(a2) * 8.5)
		b.deco({ Name = "LaserBeam", Size = Vector3.new(0.06, 0.06, (p2 - p1).Magnitude), CFrame = base * CFrame.lookAt((p1 + p2) / 2, p2), Color = rgb(255, 50, 60), Material = M.Neon, CastShadow = false })
	end
	local top = b.deco({ Name = "CrystalSpot", Size = Vector3.new(2, 0.3, 2), CFrame = base * CFrame.new(0, ht - 3, 0), Color = cool, Material = M.Neon })
	table.insert(ctx.lights, light(top, "SpotLight", cool, 3, 34, true))
	reserve(ctx, cx - 9.5, cx + 9.5, cz - 9.5, cz + 9.5)
	-- Loose gems round the laser ring and in the lanes between the wings.
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + 0.3
		point(ctx, CFrame.new(cx + math.cos(a) * 11.5, y0, cz + math.sin(a) * 11.5), "L", "Floor")
	end
	for _, deg in ipairs({ 22.5, 157.5, 202.5, 337.5, 67, 113, 247, 293 }) do
		local a = math.rad(deg)
		point(ctx, CFrame.new(cx + math.cos(a) * 30, y0, cz + math.sin(a) * 30), "L", "Floor")
		point(ctx, CFrame.new(cx + math.cos(a) * 39, y0, cz + math.sin(a) * 39), "L", "Floor")
	end
	-- Routes: south opening -> centre ring -> north opening.
	reserve(ctx, -4.5, 4.5, CH0, cz - 9)
	reserve(ctx, -4.5, 4.5, cz + 9, BACK)
	ctx.landmark = base
	ctx.rarePoint = base * CFrame.new(0, 0, -12.5)
	Props.camera(b, facing(Vector3.new(verts[5].X * 0.95, y0 + 14, verts[5].Z + 1), Vector3.new(1, -0.3, 1).Unit))
	Props.camera(b, facing(Vector3.new(verts[2].X * 0.95, y0 + 14, verts[2].Z - 1), Vector3.new(-1, -0.3, -1).Unit))
	emitter(ctx, Vector3.new(cx, y0 + 20, cz), "ElectricalHum")
	emitter(ctx, Vector3.new(30, y0 + 22, -10), "Ventilation")
end

-- B4 Emerald Reserve: vaulted gallery --------------------------------------------------------

local function emeraldReserve(ctx)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	local accent = Props.rgb(ctx.palette.Accent)
	local dark, darkMetal, goldInlay = rgb(26, 30, 28), rgb(40, 46, 44), rgb(200, 160, 60)
	local GW = 22 -- gallery half-width (wall centre)
	local AB = 36 -- alcove back wall
	local LEFT_END = 42 -- the left gallery wall stops here: beyond it, the passage to the exit
	-- Front closure with the gallery portal (x -10..10).
	wall(ctx, "GalleryFront", -W2, CH0 + 1, -10, CH0 + 1, ht, 2, darkMetal)
	wall(ctx, "GalleryFront", 10, CH0 + 1, W2, CH0 + 1, ht, 2, darkMetal)
	b.part({ Name = "PortalLintel", Size = Vector3.new(20, ht - 14, 2), CFrame = CFrame.new(0, y0 + 14 + (ht - 14) / 2, CH0 + 1), Color = darkMetal, Material = M.Metal })
	b.deco({ Name = "PortalArch", Size = Vector3.new(21, 0.8, 2.6), CFrame = CFrame.new(0, y0 + 14, CH0 + 1), Color = accent, Material = M.Neon })
	Props.sign(b, facing(Vector3.new(0, y0 + 16.5, CH0 - 0.1), -Z), 18, 1.6, "EMERALD GALLERY  -  B4", { Color = accent, PPS = 30 })
	-- Alcove bays: gallery wall segments between alcove mouths, bay walls, back walls.
	local bays = {
		[-1] = { { CH0 + 2, -18 }, { -18, 0 }, { 0, 18 }, { 18, LEFT_END } },
		[1] = { { CH0 + 2, -18 }, { -18, 0 }, { 0, 18 }, { 18, 36 }, { 36, BACK } },
	}
	local items = { "Emerald", "EmeraldCluster", "PremiumEmerald", "GrandEmerald" }
	local n = 0
	for side, list in pairs(bays) do
		local lastEnd = CH0 + 2
		for _, bay in ipairs(list) do
			local z0, z1 = bay[1], bay[2]
			local zc = (z0 + z1) / 2
			-- Gallery wall up to this bay's mouth, then a lintel over the mouth.
			wall(ctx, "GalleryWall", side * GW, lastEnd, side * GW, zc - 4, ht, 2, darkMetal, M.Metal)
			b.part({ Name = "MouthLintel", Size = Vector3.new(2, ht - 10, 8), CFrame = CFrame.new(side * GW, y0 + 10 + (ht - 10) / 2, zc), Color = darkMetal, Material = M.Metal })
			b.deco({ Name = "MouthArch", Size = Vector3.new(2.4, 0.6, 8.4), CFrame = CFrame.new(side * GW, y0 + 10, zc), Color = accent, Material = M.Neon })
			for _, dz in ipairs({ -4.2, 4.2 }) do
				b.deco({ Name = "MouthJamb", Size = Vector3.new(2.4, 10, 0.4), CFrame = CFrame.new(side * GW, y0 + 5, zc + dz), Color = goldInlay, Material = M.Metal })
			end
			lastEnd = zc + 4
			-- Bay walls and the back wall.
			wall(ctx, "BayWall", side * GW, z1, side * AB, z1, ht, 1.6, dark, M.Slate)
			if z0 == CH0 + 2 then
				wall(ctx, "BayWall", side * GW, z0, side * AB, z0, ht, 1.6, dark, M.Slate)
			end
			wall(ctx, "AlcoveBack", side * AB, z0, side * AB, z1, ht, 2, dark, M.Slate)
			-- Premium cases: a glass emerald tower against the back wall, open trays in front.
			n += 1
			local tower = CFrame.new(side * (AB - 2.6), y0, zc)
			b.cyl({ Name = "TowerBase", Size = Vector3.new(1.2, 3.6, 3.6), CFrame = tower * CFrame.new(0, 0.6, 0) * UP, Color = dark, Material = M.Metal })
			b.cyl({ Name = "TowerGlass", Size = Vector3.new(9, 3, 3), CFrame = tower * CFrame.new(0, 5.7, 0) * UP, Color = rgb(190, 255, 220), Material = M.Glass, Transparency = 0.7, CastShadow = false })
			b.cyl({ Name = "TowerRing", Size = Vector3.new(0.15, 3.2, 3.2), CFrame = tower * CFrame.new(0, 3, 0) * UP, Color = accent, Material = M.Neon, CanCollide = false })
			decoLoot(ctx, items[(n - 1) % #items + 1], tower * CFrame.new(0, 5, 0))
			for _, dz in ipairs({ -5, 0, 5 }) do
				if math.abs(dz) < (z1 - z0) / 2 - 2 then
					local cf = facing(Vector3.new(side * (GW + 6.6), y0, zc + dz), -side * X)
					b.part({ Name = "CaseStand", Size = Vector3.new(2.6, 3, 2.2), CFrame = cf * CFrame.new(0, 1.5, 0), Color = dark, Material = M.Slate })
					b.deco({ Name = "CaseInlay", Size = Vector3.new(2.7, 0.15, 2.3), CFrame = cf * CFrame.new(0, 3.05, 0), Color = goldInlay, Material = M.Metal })
					b.deco({ Name = "CaseRim", Size = Vector3.new(2.7, 0.5, 0.12), CFrame = cf * CFrame.new(0, 3.3, 1.1), Color = rgb(190, 255, 220), Material = M.Glass, Transparency = 0.5 })
					point(ctx, cf * CFrame.new(-0.6, 3.12, 0), "S", "Case")
					point(ctx, cf * CFrame.new(0.6, 3.12, 0), if dz == 0 then "M" else "S", "Case")
				end
			end
			local spot = b.deco({ Name = "AlcoveSpot", Size = Vector3.new(1.2, 0.3, 1.2), CFrame = CFrame.new(side * (GW + 7), y0 + 12, zc), Color = accent, Material = M.Neon })
			if n % 2 == 1 then
				light(spot, "SpotLight", rgb(150, 255, 190), 2, 18, false)
			end
		end
		if side == 1 then
			wall(ctx, "GalleryWall", GW, lastEnd, GW, BACK, ht, 2, darkMetal, M.Metal)
		else
			wall(ctx, "GalleryWall", -GW, lastEnd, -GW, LEFT_END, ht, 2, darkMetal, M.Metal)
		end
	end
	-- Beyond the alcoves the rock is solid (sealed).
	for _, side in ipairs({ -1, 1 }) do
		local zEnd = if side < 0 then LEFT_END else BACK
		b.deco({ Name = "Bedrock", Size = Vector3.new(W2 - AB - 1, ht, zEnd - CH0), CFrame = CFrame.new(side * (W2 + AB + 1) / 2, y0 + ht / 2, (CH0 + zEnd) / 2), Color = rgb(22, 24, 22), Material = M.Slate })
	end
	-- Exit passage at the north-west: closed off from the sealed rock by a wall.
	wall(ctx, "PassageWall", -W2, LEFT_END, -AB, LEFT_END, ht, 2, dark, M.Slate)
	-- The vault: flattened arch ribs every 12 studs and the vault surface between them.
	local segs = 6
	local function archPoint(t)
		local a = math.pi * t
		return Vector3.new(-math.cos(a) * GW, 12 + math.sin(a) * (ht - 13.5), 0)
	end
	for i = 0, segs - 1 do
		local p, q = archPoint(i / segs), archPoint((i + 1) / segs)
		local mid = (p + q) / 2
		local cfa = CFrame.lookAt(Vector3.new(0, y0, 0) + mid, Vector3.new(0, y0, 0) + q)
		b.deco({ Name = "VaultSurface", Size = Vector3.new(0.6, (q - p).Magnitude + 0.4, BACK - CH0), CFrame = CFrame.new(mid.X, y0 + mid.Y + 0.6, (CH0 + BACK) / 2) * CFrame.Angles(0, 0, math.atan2(q.Y - p.Y, q.X - p.X) - math.pi / 2), Color = rgb(34, 40, 38), Material = M.Slate })
		for z = CH0 + 6, BACK - 2, 12 do
			b.deco({ Name = "ArchRib", Size = Vector3.new(1.2, 1.2, (q - p).Magnitude + 0.6), CFrame = CFrame.new(0, 0, z) * cfa, Color = if i % 2 == 0 then darkMetal else goldInlay, Material = M.Metal })
		end
	end
	-- Gallery centre: black stands with premium trays either side of the walkway.
	for _, x in ipairs({ -10, 10 }) do
		for _, z in ipairs({ -26, -12, 2, 16, 30 }) do
			local cf = CFrame.new(x, y0, z)
			b.part({ Name = "Stand", Size = Vector3.new(3.2, 3, 2.4), CFrame = cf * CFrame.new(0, 1.5, 0), Color = dark, Material = M.Slate })
			b.deco({ Name = "StandInlay", Size = Vector3.new(3.3, 0.15, 2.5), CFrame = cf * CFrame.new(0, 3.05, 0), Color = goldInlay, Material = M.Metal })
			b.deco({ Name = "StandGlow", Size = Vector3.new(3.3, 0.1, 2.5), CFrame = cf * CFrame.new(0, 0.05, 0), Color = accent, Material = M.Neon })
			point(ctx, cf * CFrame.new(-1, 3.12, 0), "S", "Stand")
			point(ctx, cf * CFrame.new(0, 3.12, 0), "M", "Stand")
			point(ctx, cf * CFrame.new(1, 3.12, 0), "S", "Stand")
			reserve(ctx, x - 2.2, x + 2.2, z - 1.8, z + 1.8)
		end
	end
	-- Loose emeralds along the gallery lanes.
	for _, x in ipairs({ -16, 16 }) do
		for z = -30, 34, 8 do
			point(ctx, CFrame.new(x, y0, z), "L", "Floor")
		end
	end
	-- Landmark: an emerald obelisk at the north end of the gallery.
	local base = CFrame.new(8, y0, 50)
	b.part({ Name = "ObeliskBase", Size = Vector3.new(9, 2, 9), CFrame = base * CFrame.new(0, 1, 0), Color = rgb(20, 22, 22), Material = M.Slate })
	b.part({ Name = "Obelisk", Size = Vector3.new(3.4, 15, 3.4), CFrame = base * CFrame.new(0, 9.5, 0), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.15, Reflectance = 0.25 })
	local core = b.deco({ Name = "ObeliskCore", Size = Vector3.new(1.4, 13, 1.4), CFrame = base * CFrame.new(0, 9.5, 0), Color = rgb(60, 255, 150), Material = M.Neon, Transparency = 0.35 })
	light(core, "PointLight", rgb(80, 255, 150), 1.6, 24, false)
	b.part({ Name = "ObeliskTip", Size = Vector3.new(2.2, 2.2, 2.2), CFrame = base * CFrame.new(0, 17.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.1 })
	for s = 0, 3 do
		local a = s / 4 * math.pi * 2 + math.pi / 4
		b.deco({ Name = "GoldInlay", Size = Vector3.new(0.3, 0.4, 9.2), CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(4.55, 1.6, 0), Color = goldInlay, Material = M.Metal })
	end
	reserve(ctx, 2, 14, 44, 56)
	-- Lights: a row down the vault crown, green-tinted.
	ctx.lights = {}
	for _, z in ipairs({ -20, 10, 40 }) do
		local _, l = Props.lightFixture(b, CFrame.new(0, y0 + ht - 2.4, z), rgb(210, 255, 225), 2, 34, 8)
		l.Shadows = z == 10
		table.insert(ctx.lights, l)
	end
	-- Route: up the gallery, then west to the exit at x -36.
	reserve(ctx, -4.5, 4.5, CH0, 46)
	reserve(ctx, -42, 4.5, 42, BACK)
	ctx.landmark = base
	ctx.rarePoint = CFrame.new(-6, y0, 36)
	Props.camera(b, facing(Vector3.new(-GW + 1.4, y0 + 9, CH0 + 4), Vector3.new(1, -0.3, 1).Unit))
	Props.camera(b, facing(Vector3.new(GW - 1.4, y0 + 9, BACK - 4), Vector3.new(-1, -0.3, -1).Unit))
	emitter(ctx, Vector3.new(0, y0 + 18, 18), "ElectricalHum")
	emitter(ctx, Vector3.new(0, y0 + 16, -20), "Ventilation")
end

-- B5 Platinum Reserve: industrial hall -------------------------------------------------------

local function platinumReserve(ctx)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	local accent = Props.rgb(ctx.palette.Accent)
	local frame, alloy, coldLight = rgb(90, 100, 116), rgb(200, 206, 216), rgb(200, 225, 255)
	-- Corrugated wall ribs.
	for _, side in ipairs({ -1, 1 }) do
		for z = CH0 + 2, BACK - 2, 5 do
			b.deco({ Name = "WallRib", Size = Vector3.new(0.5, ht - 2, 1), CFrame = CFrame.new(side * (W2 - 0.25), y0 + ht / 2, z), Color = rgb(110, 118, 130), Material = M.Metal, CastShadow = false })
		end
	end
	for x = -W2 + 3, W2 - 3, 5 do
		b.deco({ Name = "WallRib", Size = Vector3.new(1, ht - 2, 0.5), CFrame = CFrame.new(x, y0 + ht / 2, BACK - 0.25), Color = rgb(110, 118, 130), Material = M.Metal, CastShadow = false })
	end
	-- Yellow steel portal frame at the hall entrance.
	for _, x in ipairs({ -16, 16 }) do
		b.part({ Name = "PortalColumn", Size = Vector3.new(1.6, 18, 1.6), CFrame = CFrame.new(x, y0 + 9, CH0 + 1), Color = C.Hazard, Material = M.Metal })
	end
	b.deco({ Name = "PortalBeam", Size = Vector3.new(34, 2, 1.6), CFrame = CFrame.new(0, y0 + 18.6, CH0 + 1), Color = C.Hazard, Material = M.Metal })
	Props.sign(b, facing(Vector3.new(0, y0 + 21, CH0 + 0.5), -Z), 22, 1.8, "PLATINUM PROCESSING  -  B5", { Color = coldLight, PPS = 30 })
	-- Warehouse: three rows of tall racks on the left, cross-aisles between segments.
	local rowXs = { -63, -45, -27 }
	local segZs = { -26, -8, 10, 28, 46 }
	for ri, x in ipairs(rowXs) do
		for _, z in ipairs(segZs) do
			local dir = if ri == 1 then X else (if ri == 3 then -X else X)
			stagedRack(ctx, facing(Vector3.new(x, y0, z), dir), 14, 3.4, 5, 14, frame, true, { -4.2, 0, 4.2 }, { "M", "S" }, "PT-ALLOY", rgb(120, 130, 146))
			reserve(ctx, x - 2.4, x + 2.4, z - 7.5, z + 7.5)
		end
		b.deco({ Name = "RowSign", Size = Vector3.new(0.3, 1.4, 6), CFrame = CFrame.new(x, y0 + 16, CH0 + 6), Color = accent, Material = M.Neon })
	end
	-- Floor lane markings for the warehouse aisles.
	for _, x in ipairs({ -54, -36 }) do
		b.deco({ Name = "LaneLine", Size = Vector3.new(0.4, 0.05, BACK - CH0 - 10), CFrame = CFrame.new(x, y0 + 0.03, (CH0 + BACK) / 2), Color = C.Hazard, CastShadow = false })
	end
	-- Press line on the right: a conveyor with three presses and output tables.
	local lineX = 16
	b.part({ Name = "ConveyorFrame", Size = Vector3.new(3.6, 2.6, 72), CFrame = CFrame.new(lineX, y0 + 1.3, 10), Color = rgb(60, 64, 72), Material = M.Metal })
	b.deco({ Name = "ConveyorBelt", Size = Vector3.new(3.2, 0.12, 72), CFrame = CFrame.new(lineX, y0 + 2.66, 10), Color = rgb(30, 30, 34), Material = M.Rubber })
	for z = -24, 44, 4 do
		b.deco({ Name = "BeltCleat", Size = Vector3.new(3.2, 0.14, 0.3), CFrame = CFrame.new(lineX, y0 + 2.7, z), Color = rgb(90, 96, 106), Material = M.Metal })
	end
	for _, pz in ipairs({ -12, 10, 32 }) do
		for _, dx in ipairs({ -3, 3 }) do
			b.part({ Name = "PressColumn", Size = Vector3.new(0.9, 12, 0.9), CFrame = CFrame.new(lineX + dx, y0 + 6, pz), Color = frame, Material = M.Metal })
		end
		b.part({ Name = "PressHead", Size = Vector3.new(7.4, 2.4, 4), CFrame = CFrame.new(lineX, y0 + 12.4, pz), Color = rgb(60, 64, 72), Material = M.Metal })
		b.deco({ Name = "PressPiston", Size = Vector3.new(4, 1.2, 1.2), CFrame = CFrame.new(lineX, y0 + 9.4, pz) * UP, Color = alloy, Material = M.Metal, Shape = Enum.PartType.Cylinder })
		b.deco({ Name = "PressPlate", Size = Vector3.new(3.4, 0.5, 3), CFrame = CFrame.new(lineX, y0 + 7.2, pz), Color = rgb(150, 156, 166), Material = M.DiamondPlate })
		Props.warningLight(b, CFrame.new(lineX + 3.7, y0 + 13.6, pz), C.Amber)
		Props.hazardStripes(b, CFrame.new(lineX, y0, pz - 2.6) * CFrame.Angles(0, math.pi / 2, 0), 3, 9)
		-- Output table beside each press.
		local top = Props.table(b, facing(Vector3.new(lineX + 6.4, y0, pz + 5), X), 4.4, 2.6, 3, rgb(150, 156, 166))
		point(ctx, top * CFrame.new(-1, 0, 0), "M", "Table")
		point(ctx, top * CFrame.new(1, 0, 0), "S", "Table")
		reserve(ctx, lineX + 4.6, lineX + 8.2, pz + 2.4, pz + 7.6)
	end
	-- Finished pieces riding the belt between the presses.
	for _, z in ipairs({ -22, -18, -4, 0, 18, 22, 40, 44 }) do
		point(ctx, CFrame.new(lineX, y0 + 2.72, z), "M", "Conveyor")
	end
	reserve(ctx, lineX - 4, lineX + 4, -27, 47)
	-- Robotic arm at the end of the line.
	local arm = CFrame.new(lineX - 6, y0, 50)
	b.cyl({ Name = "ArmBase", Size = Vector3.new(1.4, 4, 4), CFrame = arm * CFrame.new(0, 0.7, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal })
	b.part({ Name = "ArmLower", Size = Vector3.new(1.2, 7, 1.2), CFrame = arm * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.rad(-20)), Color = rgb(236, 180, 40), Material = M.Metal })
	b.deco({ Name = "ArmUpper", Size = Vector3.new(1, 6, 1), CFrame = arm * CFrame.new(2.6, 9.4, 0) * CFrame.Angles(0, 0, math.rad(60)), Color = rgb(236, 180, 40), Material = M.Metal })
	reserve(ctx, lineX - 9, lineX - 3, 47, 53)
	-- Alloy canister shelving along the right wall.
	for _, z in ipairs({ -24, -6, 30, 46 }) do
		stagedRack(ctx, facing(Vector3.new(W2 - 3.6, y0, z), -X), 10, 3, 4, 10, frame, true, { -2.6, 2.6 }, { "M", "S" }, "PT", rgb(120, 130, 146))
		reserve(ctx, W2 - 6, W2, z - 5.5, z + 5.5)
	end
	-- Catwalks overhead across the hall, on columns clear of the lanes.
	for _, cz in ipairs({ 0, 36 }) do
		b.deco({ Name = "Catwalk", Size = Vector3.new(W2 * 2 - 4, 0.4, 4), CFrame = CFrame.new(0, y0 + 16, cz), Color = rgb(60, 64, 72), Material = M.DiamondPlate })
		for _, dz in ipairs({ -2, 2 }) do
			b.deco({ Name = "CatwalkRail", Size = Vector3.new(W2 * 2 - 4, 0.2, 0.2), CFrame = CFrame.new(0, y0 + 19.2, cz + dz), Color = C.Hazard, Material = M.Metal })
		end
		for _, x in ipairs({ -36, -18, 4, 28, 56 }) do
			b.part({ Name = "CatwalkColumn", Size = Vector3.new(0.8, 16, 0.8), CFrame = CFrame.new(x, y0 + 8, cz + 2.4), Color = frame, Material = M.Metal })
		end
	end
	-- Landmark: the platinum refinery vessel by the right wall.
	local base = CFrame.new(56, y0, 14)
	b.cyl({ Name = "VesselFoot", Size = Vector3.new(1.6, 11, 11), CFrame = base * CFrame.new(0, 0.8, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal })
	b.cyl({ Name = "Vessel", Size = Vector3.new(16, 8.4, 8.4), CFrame = base * CFrame.new(0, 9.6, 0) * UP, Color = alloy, Material = M.Metal, Reflectance = 0.15 })
	b.part({ Name = "VesselDome", Size = Vector3.new(8.4, 8.4, 8.4), CFrame = base * CFrame.new(0, 17.6, 0), Color = alloy, Material = M.Metal, Shape = Enum.PartType.Ball })
	for i = 0, 2 do
		b.cyl({ Name = "VesselBand", Size = Vector3.new(0.6, 8.7, 8.7), CFrame = base * CFrame.new(0, 4 + i * 5, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal, CanCollide = false })
	end
	local window = b.deco({ Name = "VesselWindow", Size = Vector3.new(0.4, 3.4, 2.4), CFrame = base * CFrame.new(-4.2, 9, 0), Color = rgb(150, 210, 255), Material = M.Neon })
	light(window, "PointLight", rgb(150, 210, 255), 1.4, 18, false)
	Props.pipe(b, Vector3.new(51.6, y0 + 15, 14), Vector3.new(lineX + 4, y0 + 15, 14), 1.2, rgb(170, 176, 186))
	reserve(ctx, 49, W2, 6, 22)
	-- Loose platinum along the warehouse aisles and the press-line lanes.
	for _, x in ipairs({ -54, -36 }) do
		for z = -32, 52, 12 do
			point(ctx, CFrame.new(x, y0, z), "L", "Floor")
		end
	end
	for _, z in ipairs({ -20, 4, 24, 44 }) do
		point(ctx, CFrame.new(lineX - 6.5, y0, z), "L", "Floor")
	end
	-- Cold strip lighting in long rows.
	ctx.lights = {}
	for _, x in ipairs({ -45, -10, 30 }) do
		for _, z in ipairs({ -16, 18, 48 }) do
			local _, l = Props.lightFixture(b, CFrame.new(x, y0 + ht - 3, z), coldLight, 1.8, 44, 12)
			l.Shadows = x == -10 and z == 18
			table.insert(ctx.lights, l)
		end
	end
	-- Route: hall -> right lane -> exit at x 40.
	reserve(ctx, -4.5, 44, CH0, -30)
	reserve(ctx, 35, 45, -32, BACK)
	ctx.landmark = base
	ctx.rarePoint = CFrame.new(47.5, y0, 26)
	Props.camera(b, facing(Vector3.new(-W2 + 2, y0 + 20, CH0 + 4), Vector3.new(1, -0.3, 1).Unit))
	Props.camera(b, facing(Vector3.new(W2 - 2, y0 + 20, BACK - 4), Vector3.new(-1, -0.3, -1).Unit))
	emitter(ctx, Vector3.new(lineX, y0 + 8, 10), "Machinery")
	emitter(ctx, Vector3.new(-45, y0 + 20, 10), "Ventilation")
	emitter(ctx, Vector3.new(56, y0 + 12, 14), "ElectricalHum")
end

local BUILDERS = { cashVault, goldReserve, diamondChamber, emeraldReserve, platinumReserve }

function Plans.has(depth)
	return BUILDERS[depth] ~= nil
end

function Plans.build(ctx)
	local fn = BUILDERS[ctx.def.Depth]
	if fn then
		fn(ctx)
	end
end

return Plans
