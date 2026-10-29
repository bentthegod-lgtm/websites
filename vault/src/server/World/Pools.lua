--[[
	Pools - every depth is a DEEP POOL OF TREASURE.

	Layout of one depth (x right, z away from the elevator, y up from the rim y0):

	        z -72 .. -46   FRONT DECK (the rim): elevator, deposit machines, upgrade
	                       terminal, signage, leaderboards on B1
	  x +-52..70 at y0    SIDE RIMS with railings overlooking the pool
	        z  50 .. 60   BACK RIM: the depth's monument; on B2+ the arrival tunnel from
	                       the depth above comes in through the back wall at x -40
	  x -52..52, z -46..50 THE POOL: a basin 42 studs deep. Its "water" is a walkable sea of
	                       that depth's loot: grand steps down from the deck, then terraces
	                       and ramps (about 31 degrees) to the deep end at y0 - 42.
	  deep end, z 50       a massive round VAULT DOOR in the pool's back wall, locked until
	                       the next depth is unlocked (the client swings it open)
	  behind the door      TUNNEL A ramps down under the back rim (14 degrees) to a landing
	                       with a window into a preview of the next depth; TUNNEL C ramps
	                       down again (27 degrees) and comes out on the NEXT depth's back
	                       rim, 90 studs lower. B7's landing ends at the sealed Ancient Vault.

	The walkable treasure surface is simple collidable geometry (step boxes, flat terrace
	boxes and tilted ramp slabs, all walkable); the pile of money on it is non-colliding
	decoration (bundles, bars, coins, gems, relics) in clusters of a few parts.
	Loot spawn points are spread over the whole pool surface, denser and luckier deeper down
	(point.bonus scales Rare Loot Luck), and VaultBuilder keeps only reachable ones (Reach).
	ctx.safeZones lists the volumes a player may be in (PlayerService returns anyone outside
	them to the rim).
]]

local Props = require(script.Parent.Props)
local Machines = require(script.Parent.Machines)
local Themes = require(script.Parent.Themes)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)

local Pools = {}

local M = Enum.Material
local rgb = Color3.fromRGB
local C = Props.Colors
local Z = Vector3.zAxis
local UP = CFrame.Angles(0, 0, math.pi / 2)
local W2 = GameConfig.RoomWidth / 2 -- 70
local BACK = GameConfig.RoomBack -- 60

local H = Themes.helpers
local emitter, light, decoLoot = H.emitter, H.light, H.decoLoot

Pools.Pool = { x0 = -52, x1 = 52, z0 = -46, z1 = 50, depth = 42 }
local P = Pools.Pool
Pools.DeckEnd = -46

-- The walkable profile along z (heights relative to the rim). Steps rise 1.0 over 1.78;
-- ramps are about 31 degrees; the deep end is flat in front of the vault door.
Pools.Profile = {
	{ kind = "stairs", z0 = -46, z1 = -30, h0 = 0, h1 = -9, steps = 9 },
	{ kind = "flat", z0 = -30, z1 = -26, h0 = -9, h1 = -9 },
	{ kind = "ramp", z0 = -26, z1 = -8, h0 = -9, h1 = -20 },
	{ kind = "flat", z0 = -8, z1 = -4, h0 = -20, h1 = -20 },
	{ kind = "ramp", z0 = -4, z1 = 14, h0 = -20, h1 = -31 },
	{ kind = "flat", z0 = 14, z1 = 18, h0 = -31, h1 = -31 },
	{ kind = "ramp", z0 = 18, z1 = 36, h0 = -31, h1 = -42 },
	{ kind = "flat", z0 = 36, z1 = 50, h0 = -42, h1 = -42 },
}

-- Height of the treasure surface at z (relative to the rim) and its slope angle.
function Pools.surface(z)
	for _, seg in ipairs(Pools.Profile) do
		if z >= seg.z0 and z <= seg.z1 then
			if seg.kind == "stairs" then
				local run = (seg.z1 - seg.z0) / seg.steps
				local i = math.clamp(math.floor((z - seg.z0) / run) + 1, 1, seg.steps)
				return seg.h0 - i * (seg.h0 - seg.h1) / seg.steps, 0
			elseif seg.kind == "ramp" then
				local t = (z - seg.z0) / (seg.z1 - seg.z0)
				return seg.h0 + (seg.h1 - seg.h0) * t, math.atan2(seg.h0 - seg.h1, seg.z1 - seg.z0)
			end
			return seg.h0, 0
		end
	end
	return if z < P.z0 then 0 else -P.depth, 0
end

-- Tunnel geometry (relative to the depth's rim), shared with the harness and PlayerService.
Pools.Tunnel = {
	doorZ = 50,
	aStart = 52, aRampStart = 58, aEnd = 130, aDrop = 18, -- floor -42 -> -60
	landing = { x0 = -48, x1 = 8, z0 = 128, z1 = 146, y = -60 },
	cX = -40, cTop = 130, cBottom = 70, cY = -90, -- floor -60 -> -90, then flat to z 61
	arrivalX = -40, -- where the tunnel from the depth above enters this depth's back rim
}
local T = Pools.Tunnel

-- Per-depth style: walls, steps, the treasure, lights.
local STYLES = {
	{ H = 24, wall = rgb(214, 208, 196), wallM = M.Marble, band = rgb(196, 160, 80), bandM = M.Metal, step = rgb(226, 220, 206), stepM = M.Marble, nose = rgb(196, 160, 80), sea = rgb(70, 118, 62), seaM = M.Fabric, column = rgb(230, 226, 214), light = rgb(255, 236, 206), cluster = "cash" },
	{ H = 26, wall = rgb(74, 70, 62), wallM = M.DiamondPlate, band = rgb(236, 190, 40), bandM = M.Metal, step = rgb(60, 58, 54), stepM = M.DiamondPlate, nose = rgb(236, 190, 40), sea = rgb(214, 164, 48), seaM = M.Metal, column = rgb(46, 44, 40), light = rgb(255, 214, 160), cluster = "gold" },
	{ H = 24, wall = rgb(150, 162, 182), wallM = M.Marble, band = rgb(170, 220, 255), bandM = M.Neon, step = rgb(196, 214, 232), stepM = M.Marble, nose = rgb(170, 220, 255), sea = rgb(150, 180, 214), seaM = M.Glass, column = rgb(120, 132, 152), light = rgb(214, 236, 255), cluster = "diamond" },
	{ H = 24, wall = rgb(30, 36, 33), wallM = M.Slate, band = rgb(60, 255, 150), bandM = M.Neon, step = rgb(38, 44, 41), stepM = M.Slate, nose = rgb(60, 255, 150), sea = rgb(20, 120, 66), seaM = M.Glass, column = rgb(24, 28, 26), light = rgb(210, 255, 225), cluster = "emerald" },
	{ H = 26, wall = rgb(110, 118, 130), wallM = M.Metal, band = rgb(200, 225, 255), bandM = M.Neon, step = rgb(84, 90, 100), stepM = M.DiamondPlate, nose = rgb(236, 190, 40), sea = rgb(176, 184, 196), seaM = M.Metal, column = rgb(70, 76, 86), light = rgb(205, 225, 255), cluster = "platinum" },
	{ H = 24, wall = rgb(176, 150, 112), wallM = M.Sandstone, band = rgb(60, 170, 170), bandM = M.Metal, step = rgb(190, 164, 120), stepM = M.Sandstone, nose = rgb(60, 170, 170), sea = rgb(186, 136, 64), seaM = M.Metal, column = rgb(160, 134, 98), light = rgb(255, 222, 180), cluster = "relic" },
	{ H = 24, wall = rgb(34, 28, 38), wallM = M.Marble, band = rgb(236, 184, 58), bandM = M.Metal, step = rgb(150, 24, 36), stepM = M.Fabric, nose = rgb(236, 184, 58), sea = rgb(220, 170, 52), seaM = M.Metal, column = rgb(236, 184, 58), light = rgb(255, 226, 180), cluster = "legend" },
}
Pools.Styles = STYLES

function Pools.ceiling(depth)
	return (STYLES[depth] or STYLES[1]).H
end

local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

-- Walkable slab whose TOP runs from a to b (centre line), `width` wide across x.
local function slab(b, name, a, z, width, color, material, thick)
	thick = thick or 2
	local dir = (z - a)
	local len = dir.Magnitude
	local cf = CFrame.lookAt((a + z) / 2, z)
	return b.part({ Name = name, Size = Vector3.new(width, thick, len + 1), CFrame = cf * CFrame.new(0, -thick / 2, 0), Color = color, Material = material })
end

-- Box between two corners (min / max), relative to nothing (world coordinates).
local function box(b, name, lo, hi, color, material, deco)
	local props = { Name = name, Size = hi - lo, CFrame = CFrame.new((lo + hi) / 2), Color = color, Material = material }
	return if deco then b.deco(props) else b.part(props)
end

-- Pool basin, walls and the walkable treasure surface -----------------------------------------

local function basin(ctx, st)
	local b, y0 = ctx.b, ctx.y0
	local floorY = y0 - P.depth
	-- Bottom slab and the three pool walls (the front is the grand staircase).
	box(b, "PoolBottom", Vector3.new(P.x0 - 2, floorY - 2, P.z0 - 2), Vector3.new(P.x1 + 2, floorY, P.z1 + 2), st.step, st.stepM)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (P.x1 + 1)
		box(b, "PoolWall", Vector3.new(x - 1, floorY - 2, P.z0 - 2), Vector3.new(x + 1, y0, P.z1 + 2), st.wall, st.wallM)
	end
	-- Back wall with the door opening (x -7..7, 14 high at the bottom).
	local bz = P.z1 + 1
	box(b, "PoolBackWall", Vector3.new(P.x0 - 2, floorY - 2, bz - 1), Vector3.new(-7, y0, bz + 1), st.wall, st.wallM)
	box(b, "PoolBackWall", Vector3.new(7, floorY - 2, bz - 1), Vector3.new(P.x1 + 2, y0, bz + 1), st.wall, st.wallM)
	box(b, "PoolBackWall", Vector3.new(-7, floorY + 14, bz - 1), Vector3.new(7, y0, bz + 1), st.wall, st.wallM)
	-- Wall dressing: horizontal bands every 10 studs of depth and pilasters every 16.
	for k = 1, 3 do
		local y = y0 - k * 10.5
		for _, side in ipairs({ -1, 1 }) do
			b.deco({ Name = "WallBand", Size = Vector3.new(0.3, 0.6, P.z1 - P.z0), CFrame = CFrame.new(side * (P.x1 - 0.1), y, (P.z0 + P.z1) / 2), Color = st.band, Material = st.bandM, CastShadow = false })
		end
		b.deco({ Name = "WallBand", Size = Vector3.new(P.x1 - P.x0, 0.6, 0.3), CFrame = CFrame.new(0, y, P.z1 - 0.1), Color = st.band, Material = st.bandM, CastShadow = false })
	end
	for z = P.z0 + 10, P.z1 - 4, 16 do
		for _, side in ipairs({ -1, 1 }) do
			local top = y0
			local bottom = y0 + Pools.surface(z) - 1
			b.deco({ Name = "Pilaster", Size = Vector3.new(1.2, top - bottom, 2.2), CFrame = CFrame.new(side * (P.x1 - 0.6), (top + bottom) / 2, z), Color = st.column, Material = st.wallM })
		end
	end
	for x = -40, 40, 16 do
		b.deco({ Name = "Pilaster", Size = Vector3.new(2.2, P.depth, 1.2), CFrame = CFrame.new(x, y0 - P.depth / 2, P.z1 - 0.6), Color = st.column, Material = st.wallM })
	end
	-- The walkable treasure surface.
	local width = P.x1 - P.x0
	for _, seg in ipairs(Pools.Profile) do
		if seg.kind == "stairs" then
			local run = (seg.z1 - seg.z0) / seg.steps
			for i = 1, seg.steps do
				local top = y0 - i * (seg.h0 - seg.h1) / seg.steps
				local za, zb = seg.z0 + (i - 1) * run, seg.z0 + i * run
				box(b, "Step", Vector3.new(P.x0, floorY, za), Vector3.new(P.x1, top, zb), st.step, st.stepM)
				b.deco({ Name = "StepNosing", Size = Vector3.new(width, 0.12, 0.4), CFrame = CFrame.new(0, top + 0.04, za + 0.2), Color = st.nose, Material = if st.nose == st.band then st.bandM else M.Metal, CastShadow = false })
			end
		elseif seg.kind == "flat" then
			box(b, "Terrace", Vector3.new(P.x0, floorY, seg.z0), Vector3.new(P.x1, y0 + seg.h0, seg.z1), st.sea, st.seaM)
		else
			slab(b, "TreasureSlope", Vector3.new(0, y0 + seg.h0, seg.z0), Vector3.new(0, y0 + seg.h1, seg.z1), width, st.sea, st.seaM)
		end
	end
	-- Grand stair balustrades (the steps' style frames the descent).
	for _, x in ipairs({ -20, 20 }) do
		local a = Vector3.new(x, y0 + 1.6, P.z0)
		local z = Vector3.new(x, y0 - 9 + 1.6, -30)
		b.deco({ Name = "Balustrade", Size = Vector3.new(0.5, 0.5, (z - a).Magnitude), CFrame = CFrame.lookAt((a + z) / 2, z), Color = st.nose, Material = M.Metal })
		for i = 0, 4 do
			local p = a:Lerp(z, i / 4)
			b.deco({ Name = "BalustradePost", Size = Vector3.new(0.4, 1.6, 0.4), CFrame = CFrame.new(p - Vector3.new(0, 0.8, 0)), Color = st.nose, Material = M.Metal })
		end
	end
	-- Ladders (climbable trusses) up the deep end to the back rim.
	for _, x in ipairs({ -44, 44 }) do
		local truss = Instance.new("TrussPart")
		truss.Name = "RimLadder"
		truss.Anchored = true
		truss.Size = Vector3.new(2, P.depth, 2)
		truss.CFrame = CFrame.new(x, floorY + P.depth / 2, P.z1 - 1)
		truss.Color = st.column
		truss.Material = M.Metal
		truss.Parent = b.parent
		b.count += 1
	end
end

-- Decorative treasure: a few parts per cluster, never colliding.
local function decoPart(b, name, size, cf, color, material, shape)
	return b.part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic, Shape = shape, CanCollide = false, CastShadow = false })
end

local CLUSTERS = {}
function CLUSTERS.cash(b, cf, rng)
	for i = 1, rng:NextInteger(2, 4) do
		local o = cf * CFrame.new(rng:NextNumber(-1.6, 1.6), 0.45 + (i - 1) % 2 * 0.9, rng:NextNumber(-1.4, 1.4)) * CFrame.Angles(0, rng:NextNumber(0, 3.1), 0)
		decoPart(b, "CashBundle", Vector3.new(2.2, 0.9, 1.3), o, rgb(118, 164, 104), M.Fabric)
		if i == 1 then
			decoPart(b, "CashBand", Vector3.new(0.4, 0.94, 1.34), o, rgb(236, 236, 230))
		end
	end
end
function CLUSTERS.gold(b, cf, rng)
	for i = 1, rng:NextInteger(2, 4) do
		local o = cf * CFrame.new(rng:NextNumber(-1.6, 1.6), 0.3 + (i - 1) % 3 * 0.6, rng:NextNumber(-1.2, 1.2)) * CFrame.Angles(0, rng:NextNumber(0, 3.1), 0)
		decoPart(b, "GoldBar", Vector3.new(2, 0.6, 1), o, rgb(236, 184, 58), M.Metal)
	end
	decoPart(b, "CoinPile", Vector3.new(0.6, 2.6, 2.6), cf * CFrame.new(rng:NextNumber(-1, 1), 0.2, rng:NextNumber(-1, 1)) * UP, rgb(250, 200, 70), M.Metal, Enum.PartType.Cylinder)
end
local function gemCluster(b, cf, rng, color)
	for _ = 1, rng:NextInteger(2, 3) do
		local s = rng:NextNumber(0.9, 1.8)
		local o = cf * CFrame.new(rng:NextNumber(-1.8, 1.8), s * 0.5, rng:NextNumber(-1.6, 1.6)) * CFrame.Angles(math.rad(45), rng:NextNumber(0, 3), math.rad(35))
		b.part({ Name = "Gem", Size = Vector3.new(s, s, s), CFrame = o, Color = color, Material = M.Glass, Transparency = 0.2, Reflectance = 0.3, CanCollide = false, CastShadow = false })
	end
	decoPart(b, "GemGlow", Vector3.new(0.7, 0.7, 0.7), cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)), color, M.Neon)
end
function CLUSTERS.diamond(b, cf, rng)
	gemCluster(b, cf, rng, rgb(210, 236, 255))
end
function CLUSTERS.emerald(b, cf, rng)
	gemCluster(b, cf, rng, rgb(40, 210, 110))
end
function CLUSTERS.platinum(b, cf, rng)
	for i = 1, rng:NextInteger(2, 4) do
		local o = cf * CFrame.new(rng:NextNumber(-1.6, 1.6), 0.35 + (i - 1) % 2 * 0.7, rng:NextNumber(-1.3, 1.3)) * CFrame.Angles(0, rng:NextNumber(0, 3.1), 0)
		decoPart(b, "Ingot", Vector3.new(2.2, 0.7, 1.1), o, rgb(214, 220, 228), M.Metal)
	end
end
function CLUSTERS.relic(b, cf, rng)
	for _ = 1, 2 do
		decoPart(b, "CoinPile", Vector3.new(0.5, 2.4, 2.4), cf * CFrame.new(rng:NextNumber(-1.5, 1.5), 0.2, rng:NextNumber(-1.5, 1.5)) * UP, rgb(200, 150, 70), M.Metal, Enum.PartType.Cylinder)
	end
	if rng:NextNumber() < 0.6 then
		decoPart(b, "Urn", Vector3.new(1.4, 1.8, 1.4), cf * CFrame.new(rng:NextNumber(-1, 1), 0.9, rng:NextNumber(-1, 1)), rgb(150, 100, 60), M.Slate, Enum.PartType.Ball)
	else
		decoPart(b, "RelicBox", Vector3.new(1.6, 1, 1.2), cf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(120, 84, 50), M.WoodPlanks)
	end
end
function CLUSTERS.legend(b, cf, rng)
	local r = rng:NextNumber()
	CLUSTERS.gold(b, cf, rng)
	if r < 0.3 then
		decoPart(b, "Crown", Vector3.new(0.8, 1.6, 1.6), cf * CFrame.new(0.8, 1.1, 0.4) * UP, rgb(250, 200, 70), M.Metal, Enum.PartType.Cylinder)
		decoPart(b, "CrownJewel", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0.8, 1.7, 0.4), rgb(220, 40, 70), M.Glass, Enum.PartType.Ball)
	elseif r < 0.55 then
		decoPart(b, "Chest", Vector3.new(2.2, 1.4, 1.5), cf * CFrame.new(-0.6, 0.7, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(130, 30, 50), M.Fabric)
	elseif r < 0.75 then
		decoPart(b, "Ruby", Vector3.new(1, 1, 1), cf * CFrame.new(0, 1, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)), rgb(220, 40, 70), M.Glass)
	end
end

-- Mounds and clusters over the whole surface (and heaped higher along the pool walls).
local function treasureSea(ctx, st)
	local b, y0 = ctx.b, ctx.y0
	local rng = Random.new(ctx.def.Depth * 7717)
	local cluster = CLUSTERS[st.cluster]
	for z = P.z0 + 18, P.z1 - 2, 8.5 do
		local h, slope = Pools.surface(z)
		for x = -36, 36, 10 do
			local jx, jz = x + rng:NextNumber(-2.5, 2.5), z + rng:NextNumber(-2, 2)
			if not (math.abs(jx) < 10 and jz > 32) then -- keep the door's swing clear
				local hh = Pools.surface(jz)
				cluster(b, CFrame.new(jx, y0 + hh, jz) * CFrame.Angles(slope, rng:NextNumber(-0.3, 0.3), 0), rng)
			end
		end
		-- Treasure banked high against both pool walls: a rounded bank (a buried cylinder)
		-- rising ~6 studs, so the pool reads full to the brim with a valley down the middle.
		for _, side in ipairs({ -1, 1 }) do
			local bank = decoPart(b, "Bank", Vector3.new(9.2, 24, 24), CFrame.new(side * P.x1, y0 + h - 6, z) * CFrame.Angles(slope, math.pi / 2, 0), st.sea, st.seaM, Enum.PartType.Cylinder)
			bank.CastShadow = true
			cluster(b, CFrame.new(side * (P.x1 - 6.5), y0 + h + 4, z) * CFrame.Angles(slope, 0, side * math.rad(20)), rng)
		end
	end
end

-- Rims: decks are built by VaultBuilder's shell; here the railings, columns and lights ---------

local function rimDressing(ctx, st)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	-- Railings along both side rims and the back rim, overlooking the pool.
	local function rail(a, z)
		local mid, len = (a + z) / 2, (z - a).Magnitude
		local cf = CFrame.lookAt(mid, z)
		b.part({ Name = "RimRail", Size = Vector3.new(0.35, 0.35, len), CFrame = cf * CFrame.new(0, 3.4, 0), Color = st.nose, Material = M.Metal })
		b.deco({ Name = "RimRailMid", Size = Vector3.new(0.2, 0.2, len), CFrame = cf * CFrame.new(0, 1.7, 0), Color = st.column, Material = M.Metal })
		for i = 0, math.floor(len / 8) do
			local t = i / math.floor(len / 8) - 0.5
			b.part({ Name = "RimRailPost", Size = Vector3.new(0.4, 3.4, 0.4), CFrame = cf * CFrame.new(0, 1.7, t * len), Color = st.column, Material = M.Metal })
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		rail(Vector3.new(side * (P.x1 + 0.6), y0, P.z0), Vector3.new(side * (P.x1 + 0.6), y0, P.z1 + 0.6))
	end
	rail(Vector3.new(P.x0 - 0.6, y0, P.z1 + 0.6), Vector3.new(P.x1 + 0.6, y0, P.z1 + 0.6))
	-- Columns on the outer edge of the side rims.
	for z = P.z0 + 12, P.z1 + 6, 16 do
		for _, side in ipairs({ -1, 1 }) do
			Props.pillar(b, CFrame.new(side * (W2 - 2), y0, z), ht, 2.4, st.column, st.wallM)
		end
	end
	-- Lights: a grid under the ceiling, floodlights on the pool walls, a glow at the bottom.
	ctx.lights = {}
	for _, x in ipairs({ -32, 0, 32 }) do
		for _, z in ipairs({ -26, 6, 38 }) do
			local _, l = Props.lightFixture(b, CFrame.new(x, y0 + ht - 1.8, z), st.light, 2.2, 60, 8)
			l.Shadows = x == 0 and z == 6
			table.insert(ctx.lights, l)
		end
	end
	for _, z in ipairs({ -20, 12, 40 }) do
		for _, side in ipairs({ -1, 1 }) do
			local lamp = b.deco({ Name = "Floodlight", Size = Vector3.new(0.8, 1.2, 2.4), CFrame = CFrame.new(side * (P.x1 - 0.5), y0 - 6, z), Color = st.light, Material = M.Neon })
			local l = Instance.new("SpotLight")
			l.Face = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left
			l.Angle = 100
			l.Range = 56
			l.Brightness = 1.8
			l.Color = st.light
			l.Shadows = false
			l.Parent = lamp
			table.insert(ctx.lights, l)
		end
	end
	local glow = b.deco({ Name = "DeepGlow", Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(0, y0 - P.depth + 14.5, 44), Color = st.light, Material = M.Neon, Transparency = 1 })
	table.insert(ctx.lights, light(glow, "PointLight", st.light, 1.4, 40, false))
	-- Cameras on the rim watching the pool.
	Props.camera(b, facing(Vector3.new(-W2 + 1, y0 + ht - 6, P.z1 + 6), Vector3.new(1, -0.6, -1).Unit))
	Props.camera(b, facing(Vector3.new(W2 - 1, y0 + ht - 6, P.z0 + 2), Vector3.new(-1, -0.6, 1).Unit))
	emitter(ctx, Vector3.new(-40, y0 + 10, 0), "Ventilation")
	emitter(ctx, Vector3.new(40, y0 - 20, 30), if ctx.def.Depth == 2 or ctx.def.Depth == 5 then "Machinery" else "ElectricalHum")
end

-- Monuments on the back rim, above the vault door ----------------------------------------------

local MONUMENTS = {}
local function monumentBase(ctx)
	return CFrame.new(0, ctx.y0, (P.z1 + BACK) / 2 + 1)
end
function MONUMENTS.cash(ctx, st)
	local b, base = ctx.b, monumentBase(ctx)
	b.cyl({ Name = "Dais", Size = Vector3.new(1, 9, 9), CFrame = base * CFrame.new(0, 0.5, 0) * UP, Color = rgb(60, 62, 68), Material = M.Marble })
	local layer = 0
	for n = 3, 1, -1 do
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				b.deco({ Name = "CashBrick", Size = Vector3.new(2, 0.9, 1.4), CFrame = base * CFrame.new((i - (n - 1) / 2) * 2.1, 1.45 + layer * 0.92, (j - (n - 1) / 2) * 1.5), Color = rgb(112, 158, 98), Material = M.Fabric })
			end
		end
		layer += 1
	end
	for _, p in ipairs({ { -3.6, -3.6 }, { 3.6, -3.6 }, { -3.6, 3.6 }, { 3.6, 3.6 } }) do
		b.part({ Name = "CagePost", Size = Vector3.new(0.5, 6.4, 0.5), CFrame = base * CFrame.new(p[1], 4.2, p[2]), Color = st.band, Material = M.Metal })
	end
	b.deco({ Name = "CageRoof", Size = Vector3.new(7.6, 0.4, 7.6), CFrame = base * CFrame.new(0, 7.5, 0), Color = st.band, Material = M.Metal })
	b.part({ Name = "CageGlass", Size = Vector3.new(7.2, 6, 7.2), CFrame = base * CFrame.new(0, 4.2, 0), Color = C.Glass, Material = M.Glass, Transparency = 0.8, CastShadow = false })
end
function MONUMENTS.gold(ctx, st)
	local b, y0, ht = ctx.b, ctx.y0, ctx.H
	-- A gantry crane across the pool lowering a pallet of gold into it.
	for _, x in ipairs({ -(W2 - 3), W2 - 3 }) do
		b.deco({ Name = "CraneRail", Size = Vector3.new(1.4, 1.4, P.z1 - P.z0), CFrame = CFrame.new(x, y0 + ht - 5, (P.z0 + P.z1) / 2), Color = st.band, Material = M.Metal })
	end
	b.deco({ Name = "CraneBridge", Size = Vector3.new(W2 * 2 - 6, 2.6, 2.6), CFrame = CFrame.new(0, y0 + ht - 3.6, 10), Color = rgb(236, 180, 40), Material = M.Metal })
	for i = -7, 7 do
		b.deco({ Name = "BridgeStripe", Size = Vector3.new(2, 2.62, 0.05), CFrame = CFrame.new(i * 4, y0 + ht - 3.6, 8.67), Color = if i % 2 == 0 then C.Hazard else C.Black, CastShadow = false })
	end
	b.deco({ Name = "HoistCable", Size = Vector3.new(0.18, 24, 0.18), CFrame = CFrame.new(0, y0 + ht - 16, 10), Color = C.Black, CastShadow = false })
	decoLoot(ctx, "GoldCrate", Props.pallet(b, CFrame.new(0, y0 + ht - 30, 10)))
	-- And a bullion stack on the back rim.
	local base = monumentBase(ctx)
	for layer = 0, 4 do
		local n = 4 - math.floor(layer / 2)
		for i = 0, n - 1 do
			b.deco({ Name = "StackBar", Size = Vector3.new(2.6, 0.6, 1.2), CFrame = base * CFrame.new((i - (n - 1) / 2) * 2.7, 0.3 + layer * 0.62, 0) * CFrame.Angles(0, if layer % 2 == 0 then 0 else 0.15, 0), Color = rgb(236, 184, 58), Material = M.Metal, Reflectance = 0.2 })
		end
	end
end
function MONUMENTS.diamond(ctx, st)
	local b, base = ctx.b, monumentBase(ctx)
	b.cyl({ Name = "Pedestal", Size = Vector3.new(2, 8, 8), CFrame = base * CFrame.new(0, 1, 0) * UP, Color = rgb(40, 46, 58), Material = M.Marble })
	for i = 1, 2 do
		b.cyl({ Name = "Ring" .. i, Size = Vector3.new(0.25, 6 + i * 2.4, 6 + i * 2.4), CFrame = base * CFrame.new(0, 4 + i * 2, 0) * UP * CFrame.Angles(math.rad(i * 20), 0, 0), Color = st.band, Material = M.Neon, CanCollide = false })
	end
	b.deco({ Name = "GiantCrystal", Size = Vector3.new(4.6, 4.6, 4.6), CFrame = base * CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(210, 236, 255), Material = M.Glass, Transparency = 0.12, Reflectance = 0.4 })
	local core = b.deco({ Name = "CrystalCore", Size = Vector3.new(2, 2, 2), CFrame = base * CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = st.band, Material = M.Neon, Transparency = 0.3 })
	light(core, "PointLight", st.band, 1.6, 26, false)
end
function MONUMENTS.emerald(ctx, st)
	local b, base = ctx.b, monumentBase(ctx)
	b.part({ Name = "ObeliskBase", Size = Vector3.new(7, 2, 7), CFrame = base * CFrame.new(0, 1, 0), Color = rgb(20, 22, 22), Material = M.Slate })
	b.part({ Name = "Obelisk", Size = Vector3.new(3, 16, 3), CFrame = base * CFrame.new(0, 10, 0), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.15 })
	local core = b.deco({ Name = "ObeliskCore", Size = Vector3.new(1.2, 14, 1.2), CFrame = base * CFrame.new(0, 10, 0), Color = st.band, Material = M.Neon, Transparency = 0.35 })
	light(core, "PointLight", st.band, 1.6, 26, false)
	b.part({ Name = "ObeliskTip", Size = Vector3.new(2, 2, 2), CFrame = base * CFrame.new(0, 18.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)), Color = rgb(30, 200, 110), Material = M.Glass, Transparency = 0.1 })
end
function MONUMENTS.platinum(ctx, st)
	local b, y0, base = ctx.b, ctx.y0, monumentBase(ctx)
	b.cyl({ Name = "VesselFoot", Size = Vector3.new(1.4, 8, 8), CFrame = base * CFrame.new(0, 0.7, 0) * UP, Color = rgb(60, 64, 72), Material = M.Metal })
	b.cyl({ Name = "Vessel", Size = Vector3.new(12, 7, 7), CFrame = base * CFrame.new(0, 7.4, 0) * UP, Color = rgb(200, 206, 216), Material = M.Metal, Reflectance = 0.15 })
	b.part({ Name = "VesselDome", Size = Vector3.new(7, 7, 7), CFrame = base * CFrame.new(0, 13.4, 0), Color = rgb(200, 206, 216), Material = M.Metal, Shape = Enum.PartType.Ball })
	-- A chute pouring ingots into the pool.
	local a, z = Vector3.new(6, y0 + 9, P.z1 + 3), Vector3.new(18, y0 - 6, P.z1 - 12)
	b.deco({ Name = "Chute", Size = Vector3.new(3, 0.4, (z - a).Magnitude), CFrame = CFrame.lookAt((a + z) / 2, z), Color = rgb(90, 96, 106), Material = M.DiamondPlate })
	local window = b.deco({ Name = "VesselWindow", Size = Vector3.new(2.4, 3, 0.3), CFrame = base * CFrame.new(0, 7.4, -3.6), Color = st.band, Material = M.Neon })
	light(window, "PointLight", st.band, 1.4, 20, false)
end
function MONUMENTS.relic(ctx, st)
	local b, base = ctx.b, monumentBase(ctx)
	local stone = rgb(176, 150, 112)
	for _, x in ipairs({ -6, 6 }) do
		b.part({ Name = "ArchColumn", Size = Vector3.new(2, 12, 2), CFrame = base * CFrame.new(x, 6, 0), Color = stone, Material = M.Sandstone })
	end
	b.part({ Name = "ArchLintel", Size = Vector3.new(15, 2, 2.6), CFrame = base * CFrame.new(0, 13, 0), Color = stone, Material = M.Sandstone })
	b.part({ Name = "Sarcophagus", Size = Vector3.new(3, 2.4, 7), CFrame = base * CFrame.new(0, 1.2, 0), Color = rgb(200, 160, 70), Material = M.Metal })
	b.deco({ Name = "SarcophagusLid", Size = Vector3.new(3.2, 0.5, 7.2), CFrame = base * CFrame.new(0, 2.6, 0), Color = st.band, Material = M.Metal })
	b.part({ Name = "Field", Size = Vector3.new(5, 6, 9), CFrame = base * CFrame.new(0, 3, 0), Color = rgb(120, 230, 255), Material = M.ForceField, Transparency = 0.5, CanCollide = false })
end
function MONUMENTS.legend(ctx, st)
	local b, base = ctx.b, monumentBase(ctx)
	for i, d in ipairs({ 9, 7, 5 }) do
		b.cyl({ Name = "DaisTier" .. i, Size = Vector3.new(1, d, d), CFrame = base * CFrame.new(0, 0.5 + (i - 1), 0) * UP, Color = if i % 2 == 1 then rgb(20, 18, 24) else rgb(40, 34, 46), Material = M.Marble })
	end
	decoLoot(ctx, "TreasureHoard", base * CFrame.new(0, 3, 0), 1.6)
	for _, x in ipairs({ -3, 3 }) do
		b.part({ Name = "LightShaft", Size = Vector3.new(1.4, ctx.H - 4, 1.4), CFrame = base * CFrame.new(x, (ctx.H - 4) / 2 + 3, 0), Color = rgb(255, 230, 170), Material = M.Neon, Transparency = 0.8, CanCollide = false, CastShadow = false })
	end
	b.deco({ Name = "DaisTrim", Size = Vector3.new(9.4, 0.3, 9.4), CFrame = base * CFrame.new(0, 1.05, 0), Color = st.band, Material = M.Metal })
end

-- Exit: vault door at the deep end, tunnel down to the next depth's rim ---------------------------

local function exitRoute(ctx, st)
	local def, y0 = ctx.def, ctx.y0
	local model = Instance.new("Model")
	model.Name = "ExitRoute"
	model.Parent = ctx.folder
	local b = Props.builder(model)
	local accent = Props.rgb(ctx.palette.Accent)
	local nextDef = DepthConfig.get(def.Depth + 1)
	local floorY = y0 - P.depth
	local tw = rgb(92, 88, 82) -- tunnels are bare rock-cut concrete on every depth
	local tm = M.Concrete
	-- The door, in the pool's back wall, facing the pool.
	ctx.exitDoor = Props.vaultDoor(b, facing(Vector3.new(0, floorY + 8.5, T.doorZ), -Z), 15, accent, model)
	ctx.exitDoor.next = def.Depth + 1
	ctx.exitDoor.model:SetAttribute("ExitDoor", true)
	ctx.exitDoor.model:SetAttribute("NextDepth", def.Depth + 1)
	local restricted = if nextDef then string.format("%s %s  -  CLEARANCE REQUIRED", nextDef.Code, string.upper(nextDef.Name)) else "ANCIENT VAULT COMPLEX  -  SEALED"
	Props.sign(b, facing(Vector3.new(0, floorY + 19, T.doorZ - 0.2), -Z), 20, 1.8, restricted, { Color = rgb(255, 90, 80), PPS = 30 })
	for _, x in ipairs({ -11, 11 }) do
		Props.warningLight(b, CFrame.new(x, floorY + 16, T.doorZ - 1.4), rgb(255, 150, 40))
	end
	Props.hazardStripes(b, CFrame.new(0, floorY, T.doorZ - 3), 20, 1.4)
	ctx.exitDoorPosition = Vector3.new(0, floorY, T.doorZ - 5)
	-- Tunnel A: threshold, then a ramp down under the back rim.
	local aTop = floorY + 18 -- flat ceiling
	box(b, "TunnelFloor", Vector3.new(-6, floorY - 2, T.aStart - 1), Vector3.new(6, floorY, T.aRampStart), C.SteelDark, M.DiamondPlate)
	slab(b, "TunnelRamp", Vector3.new(0, floorY, T.aRampStart), Vector3.new(0, floorY - T.aDrop, T.aEnd), 12, C.SteelDark, M.DiamondPlate)
	for _, x in ipairs({ -7, 7 }) do
		box(b, "TunnelWall", Vector3.new(x - 1, floorY - T.aDrop - 2, T.aStart - 1), Vector3.new(x + 1, aTop, T.aEnd - 1), tw, tm)
	end
	box(b, "TunnelCeiling", Vector3.new(-8, aTop, T.aStart - 1), Vector3.new(8, aTop + 2, T.aEnd - 1), C.SteelDark, M.Concrete)
	for _, z in ipairs({ 66, 94, 120 }) do
		local _, l = Props.lightFixture(b, CFrame.new(0, aTop - 0.4, z), st.light, 1.6, 30, 6)
		l.Shadows = false
	end
	-- Landing with a window into the preview room.
	local L = T.landing
	local ly = y0 + L.y
	box(b, "LandingFloor", Vector3.new(L.x0, ly - 2, L.z0), Vector3.new(L.x1, ly, L.z1), C.SteelDark, M.DiamondPlate)
	box(b, "LandingCeiling", Vector3.new(L.x0 - 1, aTop, L.z0 - 1), Vector3.new(L.x1 + 1, aTop + 2, L.z1 + 1), C.SteelDark, M.Concrete)
	box(b, "LandingWall", Vector3.new(L.x1, ly - 2, L.z0 - 1), Vector3.new(L.x1 + 2, aTop, L.z1 + 1), tw, tm) -- east
	box(b, "LandingWall", Vector3.new(L.x0 - 2, ly - 2, L.z0 - 1), Vector3.new(L.x0, aTop, L.z1 + 1), tw, tm) -- west
	-- South wall: openings for tunnel A (x -6..6) and tunnel C (x -46..-34, up to ly + 16).
	box(b, "LandingWall", Vector3.new(-34, ly - 2, L.z0 - 1), Vector3.new(-6, aTop, L.z0 + 1), tw, tm)
	box(b, "LandingWall", Vector3.new(-46, ly + 16, L.z0 - 1), Vector3.new(-34, aTop, L.z0 + 1), tw, tm)
	-- North wall with the preview window (x -30..-12, y +3..+12).
	local pz = L.z1
	box(b, "LandingWall", Vector3.new(L.x0, ly - 2, pz - 1), Vector3.new(-30, aTop, pz + 1), tw, tm)
	box(b, "LandingWall", Vector3.new(-12, ly - 2, pz - 1), Vector3.new(L.x1, aTop, pz + 1), tw, tm)
	box(b, "LandingWall", Vector3.new(-30, ly - 2, pz - 1), Vector3.new(-12, ly + 3, pz + 1), tw, tm)
	box(b, "LandingWall", Vector3.new(-30, ly + 12, pz - 1), Vector3.new(-12, aTop, pz + 1), tw, tm)
	local glass = b.part({ Name = "PreviewGlass", Size = Vector3.new(18, 9, 0.6), CFrame = CFrame.new(-21, ly + 7.5, pz), Color = C.Glass, Material = M.Glass, Transparency = 0.55, CastShadow = false })
	glass.Name = "PreviewGlass"
	local _, ll = Props.lightFixture(b, CFrame.new(-20, aTop - 0.4, (L.z0 + L.z1) / 2), st.light, 1.8, 34, 8)
	ll.Shadows = false
	-- Preview room behind the glass: the next depth's loot on display cases.
	local nextPal = if nextDef then nextDef.Palette else { Wall = { 90, 84, 70 }, Floor = { 60, 54, 44 }, Accent = { 190, 160, 110 }, Light = { 255, 220, 170 } }
	local pv = { x0 = -32, x1 = -10, z0 = pz + 1, z1 = pz + 15 }
	box(b, "PreviewFloor", Vector3.new(pv.x0, ly - 1, pv.z0), Vector3.new(pv.x1, ly, pv.z1), Props.rgb(nextPal.Floor), M.Marble)
	box(b, "PreviewCeiling", Vector3.new(pv.x0, ly + 14, pv.z0), Vector3.new(pv.x1, ly + 15, pv.z1), Props.rgb(nextPal.Wall), M.Concrete)
	box(b, "PreviewBack", Vector3.new(pv.x0, ly - 1, pv.z1), Vector3.new(pv.x1, ly + 15, pv.z1 + 1), Props.rgb(nextPal.Wall), M.Concrete)
	for _, x in ipairs({ pv.x0 - 1, pv.x1 }) do
		box(b, "PreviewSide", Vector3.new(x, ly - 1, pv.z0), Vector3.new(x + 1, ly + 15, pv.z1 + 1), Props.rgb(nextPal.Wall), M.Concrete)
	end
	local spot = b.deco({ Name = "PreviewLight", Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(-21, ly + 13.9, pv.z0 + 7), Color = Props.rgb(nextPal.Light), Material = M.Neon })
	light(spot, "SpotLight", Props.rgb(nextPal.Light), 2.4, 22, false)
	local label = if nextDef then string.format("%s  %s", nextDef.Code, string.upper(nextDef.Name)) else "ANCIENT VAULT  -  COMING SOON"
	Props.sign(b, facing(Vector3.new(-21, ly + 13, pv.z1 - 0.1), -Z), 12, 1.4, label, { Color = Props.rgb(nextPal.Accent), PPS = 30 })
	ctx.preview = { cframes = {}, nextDepth = if nextDef then nextDef.Depth else nil }
	for i, x in ipairs({ -27, -21, -15 }) do
		table.insert(ctx.preview.cframes, Props.displayCase(b, CFrame.new(x, ly, pv.z0 + 7), 3.4, 3, 2.4 + (i % 2) * 0.6, Props.rgb(nextPal.Wall), 2.6))
	end
	-- Tunnel C down to the next depth's back rim (or the sealed Ancient Vault after B7).
	if nextDef then
		local cy0 = y0 + L.y
		local cy1 = y0 + T.cY
		slab(b, "TunnelRamp", Vector3.new(T.cX, cy0, T.cTop), Vector3.new(T.cX, cy1, T.cBottom), 12, C.SteelDark, M.DiamondPlate)
		box(b, "TunnelFloor", Vector3.new(T.cX - 6, cy1 - 2, BACK + 2), Vector3.new(T.cX + 6, cy1, T.cBottom + 0.5), C.SteelDark, M.DiamondPlate)
		for _, x in ipairs({ T.cX - 7, T.cX + 7 }) do
			box(b, "TunnelWall", Vector3.new(x - 1, cy1 - 2, BACK + 4), Vector3.new(x + 1, ly + 16, L.z0 + 1), tw, tm)
		end
		box(b, "TunnelCeiling", Vector3.new(T.cX - 8, ly + 16, BACK + 4), Vector3.new(T.cX + 8, ly + 18, L.z0 - 1), C.SteelDark, M.Concrete)
		-- Above the next depth's back wall the tunnel end is capped.
		box(b, "TunnelEndCap", Vector3.new(T.cX - 8, cy1 + 30, BACK + 3), Vector3.new(T.cX + 8, ly + 16, BACK + 4), tw, tm)
		for _, z in ipairs({ 80, 110 }) do
			local _, l = Props.lightFixture(b, CFrame.new(T.cX, ly + 15.6, z), st.light, 1.6, 40, 6)
			l.Shadows = false
		end
		Props.sign(b, facing(Vector3.new(T.cX, ly + 13, L.z0 + 1.2), -Z), 12, 1.4, string.format("DOWN TO %s  %s", nextDef.Code, string.upper(nextDef.Name)), { Color = Props.rgb(nextDef.Palette.Accent), PPS = 30 })
		ctx.tunnelEnd = Vector3.new(T.cX, cy1, BACK - 4)
	else
		box(b, "LandingWall", Vector3.new(-46, ly - 2, L.z0 - 1), Vector3.new(-34, ly + 16, L.z0 + 1), tw, tm)
		local grate = b.part({ Name = "SealedGrate", Size = Vector3.new(12, 16, 0.6), CFrame = CFrame.new(-40, ly + 8, L.z0 + 1.4), Color = C.SteelDark, Material = M.DiamondPlate })
		Props.text(grate, Enum.NormalId.Back, "ANCIENT VAULT - SEALED", { Color = C.Hazard, PPS = 20 })
	end
	ctx.b.count += b.count
	-- Where a player may legitimately be (PlayerService safety): this depth's tunnels.
	table.insert(ctx.safeZones, { Vector3.new(-8, floorY - T.aDrop - 2, T.doorZ - 2), Vector3.new(8, aTop, T.aEnd + 1) })
	table.insert(ctx.safeZones, { Vector3.new(L.x0 - 1, ly - 2, L.z0 - 2), Vector3.new(L.x1 + 1, aTop, L.z1 + 1) })
	table.insert(ctx.safeZones, { Vector3.new(pv.x0, ly - 1, pv.z0 - 1), Vector3.new(pv.x1, ly + 14, pv.z1) })
	if nextDef then
		table.insert(ctx.safeZones, { Vector3.new(T.cX - 7, y0 + T.cY - 2, BACK), Vector3.new(T.cX + 7, ly + 16, L.z0 + 1) })
	end
end

-- Loot spawn points over the treasure surface: denser and luckier deeper down.
local function spawnPoints(ctx)
	local rng = Random.new(ctx.def.Depth * 3137)
	local y0 = ctx.y0
	local z = P.z0 + 1.2
	while z < P.z1 - 1 do
		local h, slope = Pools.surface(z)
		local deep = -h / P.depth -- 0 at the rim .. 1 at the bottom
		local spacing = 16 - 8 * deep
		local x = -38 + rng:NextNumber(0, spacing * 0.6)
		while x < 38 do
			local px = x + rng:NextNumber(-1.2, 1.2)
			local doorLane = math.abs(px - 2) < 12 and z > 28
			local chute = ctx.def.Depth >= 2 and px > -38 and px < -22 and z > 34
			if not doorLane and not chute then
				local ph = Pools.surface(z)
				table.insert(ctx.extraPoints, {
					cframe = CFrame.new(px, y0 + ph, z) * CFrame.Angles(slope, rng:NextNumber(0, math.pi * 2), 0),
					size = "L",
					kind = "Pool",
					bonus = 1 + 0.8 * deep,
				})
			end
			x += spacing
		end
		z += 5.2 - 1.8 * deep
	end
end

function Pools.build(ctx)
	local st = STYLES[ctx.def.Depth] or STYLES[1]
	ctx.safeZones = ctx.safeZones or {}
	basin(ctx, st)
	treasureSea(ctx, st)
	rimDressing(ctx, st)
	MONUMENTS[st.cluster](ctx, st)
	ctx.landmark = monumentBase(ctx)
	ctx.rarePoint = CFrame.new(-12, ctx.y0 - P.depth, 41)
	-- A secondary "pneumatic chute" deposit at the deep end (B2+): 85% payout, so it
	-- shortens the trip without making the walk up pointless.
	if ctx.def.Depth >= 2 then
		local chute = Machines.deposit(ctx.b, facing(Vector3.new(-30, ctx.y0 - P.depth, P.z1 - 2.6), -Z), string.format("D%d_B", ctx.def.Depth), Props.rgb(ctx.palette.Accent))
		chute.payoutFactor = Pools.ChutePayout
		chute.bottom = true
		Props.sign(ctx.b, facing(Vector3.new(-30, ctx.y0 - P.depth + 10.4, P.z1 - 0.2), -Z), 11, 1.3, string.format("CHUTE  -  %d%% PAYOUT", math.floor(Pools.ChutePayout * 100 + 0.5)), { Color = rgb(255, 210, 120), PPS = 30 })
		table.insert(ctx.deposits, chute)
	end
	exitRoute(ctx, st)
	spawnPoints(ctx)
	-- Safe volumes: rims (incl. the elevator cabin), the pool, and (for B2+) the arrival
	-- end of the tunnel from the depth above.
	local y0, ht = ctx.y0, ctx.H
	table.insert(ctx.safeZones, { Vector3.new(-W2 - 1, y0 - 1, GameConfig.RoomFront - 16), Vector3.new(W2 + 1, y0 + ht, BACK + 4) })
	table.insert(ctx.safeZones, { Vector3.new(P.x0 - 1, y0 - P.depth - 1, P.z0 - 1), Vector3.new(P.x1 + 1, y0 + 1, P.z1 + 1) })
end

Pools.ChutePayout = 0.85

return Pools
