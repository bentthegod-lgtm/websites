--[[
	ShipBuilder - turns a ShipGen plan into parts, a few hundred parts per server frame.

	ShipBuilder.new(plan, parent, base) returns a job; RoundService calls
	job:step(GameConfig.Ship.PartsPerStep) once per Heartbeat until it returns true, so the
	server never stalls (Roblox kills a script that runs ~10 s without yielding). Tests and
	the preview tool use ShipBuilder.buildAll.

	Everything is built in ship-local coordinates (see ShipGen) through a builder whose
	origin is `base`, the ship's starting pivot: the stern, on the centreline, at the
	waterline. The model's PrimaryPart ("Pivot") sits exactly there, so one PivotTo sinks
	and tilts the whole ship (a lurch).

	The job's `record` is what the services use: the model, deck heights, bulkheads (door +
	levers), valves, hazards, the lifeboat (+ its seat zone), loose props and where loot goes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local ShipGen = require(Shared.ShipGen)
local Parts = require(Shared.Parts)
local Rng = require(Shared.Rng)

local ShipBuilder = {}
ShipBuilder.__index = ShipBuilder

local S = GameConfig.Ship
local P = Parts.Palette
local M = Enum.Material
local rgb = Color3.fromRGB
local V3 = Vector3.new

local T = 1.2 -- hull plate thickness
local BULWARK = 3.5

---------------------------------------------------------------------------------------------
-- Context helpers
---------------------------------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

function Ctx:part(opts)
	opts.CFrame = self.base * opts.CFrame
	opts.Parent = opts.Parent or self.current
	self.count += 1
	return Parts.new(opts)
end

-- A box between two local points.
function Ctx:beam(a, b, w, h, opts)
	local cf, len = Parts.beamCFrame(a, b)
	opts.CFrame = cf
	opts.Size = V3(w, h, len)
	return self:part(opts)
end

-- Reserves a rect on a deck cell for a prop; false if something is already there.
function Ctx:claim(deck, cell, x, z, hx, hz)
	local r = ShipGen.rect(x, z, hx, hz)
	local c = self.plan.cells[cell]
	if math.abs(x) + hx > c.width / 2 - 0.3 then
		return false
	end
	if not ShipGen.isFree(self.plan, deck, cell, r) then
		return false
	end
	local key = ShipGen.node(deck, cell)
	self.plan.reserved[key] = self.plan.reserved[key] or {}
	r.tag = "prop"
	table.insert(self.plan.reserved[key], r)
	return true
end

function Ctx:loose(opts)
	if #self.record.loose >= S.MaxLooseProps then
		opts.Anchored = true
		return self:part(opts)
	end
	opts.Anchored = false
	opts.Parent = self.record.looseFolder
	local localCF = opts.CFrame
	local p = self:part(opts)
	pcall(function()
		p.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.12, 0.2, 1, 1)
	end)
	p:SetAttribute("LooseProp", true)
	table.insert(self.record.loose, { part = p, localCF = localCF })
	return p
end

local function hullX(plan, z)
	return ShipGen.widthAt(plan.def, z) / 2
end

---------------------------------------------------------------------------------------------
-- Hull
---------------------------------------------------------------------------------------------

local function bands(plan)
	local n = #plan.decks
	local topY = plan.decks[n].y
	local whiteFrom = if n >= 5 then plan.decks[n - 2].y + 1 else topY - 5
	return {
		{ S.Keel, 0.4, P.AntiFoul, M.SmoothPlastic },
		{ 0.4, 1.1, P.White, M.SmoothPlastic },
		{ 1.1, whiteFrom - 0.8, Parts.rgb(plan.def.Hull), M.Metal },
		{ whiteFrom - 0.8, whiteFrom, Parts.rgb(plan.def.FunnelBand), M.SmoothPlastic },
		{ whiteFrom, topY + BULWARK, P.White, M.SmoothPlastic },
	}, topY
end

local function hullCell(ctx, c)
	local plan = ctx.plan
	local cell = plan.cells[c]
	local list, topY = bands(plan)
	for _, side in ipairs({ -1, 1 }) do
		local a = V3(side * cell.wBack / 2, 0, cell.z0)
		local b = V3(side * cell.wFront / 2, 0, cell.z1)
		local dir = (b - a).Unit
		local len = (b - a).Magnitude + 0.7
		local outward = V3(dir.Z, 0, -dir.X) * side
		local mid = (a + b) / 2 + outward * (T / 2)
		for _, band in ipairs(list) do
			local y0, y1 = band[1], band[2]
			local centre = mid + V3(0, (y0 + y1) / 2, 0)
			ctx:part({ Name = "Hull", Size = V3(T, y1 - y0, len), CFrame = CFrame.lookAt(centre, centre + dir), Color = band[3], Material = band[4] })
		end
		local rail = mid + V3(0, topY + BULWARK + 0.25, 0)
		ctx:part({ Name = "CapRail", Size = V3(T + 0.6, 0.5, len), CFrame = CFrame.lookAt(rail, rail + dir), Color = P.Teak, Material = M.Wood })
	end
	ctx:part({ Name = "Bottom", Size = V3(math.min(cell.wBack, cell.wFront), 1, S.CellLength + 0.4), CFrame = CFrame.new(0, S.Keel + 0.5, (cell.z0 + cell.z1) / 2), Color = P.AntiFoul })
end

local function hullEnds(ctx)
	local plan = ctx.plan
	local list, topY = bands(plan)
	local ws = ShipGen.widthAt(plan.def, 0) + 2 * T
	for _, band in ipairs(list) do
		ctx:part({ Name = "Transom", Size = V3(ws, band[2] - band[1], T), CFrame = CFrame.new(0, (band[1] + band[2]) / 2, -T / 2), Color = band[3], Material = band[4] })
	end
	ctx:part({ Name = "CapRail", Size = V3(ws, 0.5, T + 0.6), CFrame = CFrame.new(0, topY + BULWARK + 0.25, -T / 2), Color = P.Teak, Material = M.Wood })
	ctx:part({ Name = "Rudder", Size = V3(1, 7, 6), CFrame = CFrame.new(0, S.Keel + 1.5, -4), Color = P.AntiFoul })
	for _, x in ipairs({ -5, 5 }) do
		ctx:part({ Name = "Propeller", Shape = Enum.PartType.Cylinder, Size = V3(1, 5, 5), CFrame = CFrame.new(x, S.Keel + 2.5, -2) * Parts.ALONG_Z, Color = P.Brass, Material = M.Metal })
	end
	-- the ship's name across the stern
	local name = ctx:part({ Name = "SternName", Size = V3(ws * 0.7, 3, 0.2), CFrame = CFrame.new(0, topY - 1.5, -T - 0.15), Transparency = 1, CanCollide = false })
	ShipBuilder.nameplate(name, plan.def.Name, P.Brass)
	-- bow: stem post and a tip plate
	local L = plan.length
	local tipW = ShipGen.widthAt(plan.def, L)
	for _, band in ipairs(list) do
		ctx:part({ Name = "BowTip", Size = V3(tipW + 2 * T, band[2] - band[1], T), CFrame = CFrame.new(0, (band[1] + band[2]) / 2, L + T / 2), Color = band[3], Material = band[4] })
	end
	ctx:part({ Name = "Stem", Size = V3(1.6, topY + BULWARK + 2 - S.Keel, 1.6), CFrame = CFrame.new(0, (topY + BULWARK + 2 + S.Keel) / 2, L + T + 0.4), Color = Parts.rgb(plan.def.Hull), Material = M.Metal })
	-- belt lines along the parallel mid-body at every deck (they break up the slab sides)
	local midZ0, midZ1 = S.CellLength, L - S.BowCells * S.CellLength
	local beltLen = midZ1 - midZ0
	local whiteFrom = list[#list][1]
	for _, deck in ipairs(plan.decks) do
		local y = deck.y - 1.3
		for _, side in ipairs({ -1, 1 }) do
			ctx:part({ Name = "BeltLine", Size = V3(0.5, 0.45, beltLen), CFrame = CFrame.new(side * (plan.beam / 2 + T + 0.15), y, (midZ0 + midZ1) / 2), Color = if y > whiteFrom then P.Cream else Parts.rgb(plan.def.Hull):Lerp(P.White, 0.25), Material = M.SmoothPlastic, CanCollide = false })
		end
	end
	-- names on both bows and anchors
	local zN = L - S.BowCells * S.CellLength + 6
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (hullX(plan, zN) + T + 0.15)
		local p = ctx:part({ Name = "BowName", Size = V3(22, 3, 0.2), CFrame = CFrame.new(x, topY - 2, zN) * CFrame.Angles(0, if side > 0 then math.rad(-90) else math.rad(90), 0), Transparency = 1, CanCollide = false })
		ShipBuilder.nameplate(p, plan.def.Name, P.White)
		local za = L - S.CellLength * 1.2
		ctx:part({ Name = "Anchor", Size = V3(0.8, 3.2, 2.4), CFrame = CFrame.new(side * (hullX(plan, za) + T + 0.3), topY - 7, za), Color = P.Black, Material = M.Metal })
	end
end

function ShipBuilder.nameplate(part, text, color)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Name"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 80)
	gui.LightInfluence = 0.4
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.upper(text)
	label.TextScaled = true
	label.TextColor3 = color
	label.Font = Enum.Font.Antique
	label.Parent = gui
	return gui
end

---------------------------------------------------------------------------------------------
-- Decks: floor (holes for stairs / ladders arriving from below), wedge fills at the
-- tapered ends, wall lining, portholes / windows, ceiling lamps.
---------------------------------------------------------------------------------------------

local function holeFor(plan, deck, cell)
	for _, conn in ipairs(plan.connectors) do
		if conn.to == deck and conn.cell == cell and not conn.blocked then
			local hx, hz = ShipGen.connectorFootprint(conn.kind)
			return ShipGen.rect(conn.x, conn.z, hx, hz), conn
		end
	end
	return nil
end

local function floorPieces(x0, x1, z0, z1, hole)
	if not hole then
		return { { x0, x1, z0, z1 } }
	end
	local hx0, hx1 = math.max(x0, hole[1]), math.min(x1, hole[2])
	local hz0, hz1 = math.max(z0, hole[3]), math.min(z1, hole[4])
	local out = {}
	if hx0 > x0 + 0.05 then
		table.insert(out, { x0, hx0, z0, z1 })
	end
	if hx1 < x1 - 0.05 then
		table.insert(out, { hx1, x1, z0, z1 })
	end
	if hz0 > z0 + 0.05 then
		table.insert(out, { hx0, hx1, z0, hz0 })
	end
	if hz1 < z1 - 0.05 then
		table.insert(out, { hx0, hx1, hz1, z1 })
	end
	return out
end

local LINED = { CrewQuarters = true, Cabins = true, DiningHall = true, Promenade = true, EngineRoom = true, CargoHold = true }
local FRAME = { EngineRoom = rgb(70, 74, 84), CargoHold = rgb(92, 84, 70), CrewQuarters = rgb(110, 118, 126), Cabins = rgb(120, 82, 50), DiningHall = rgb(104, 64, 36), Promenade = rgb(236, 232, 220) }
local FRAME_WOOD = { Cabins = true, DiningHall = true }
local WAINSCOT = { Cabins = rgb(96, 62, 38), DiningHall = rgb(84, 50, 30), CrewQuarters = rgb(70, 90, 84) }
local RUNNER = { Cabins = rgb(40, 64, 120), DiningHall = rgb(150, 30, 40), Promenade = nil }

local function deckCell(ctx, d, c)
	local plan = ctx.plan
	local deck = plan.decks[d]
	local theme = GameConfig.Themes[deck.theme]
	local cell = plan.cells[c]
	local y = deck.y
	local floorColor, floorMat = Parts.rgb(theme.Floor), Parts.material(theme.FloorMat)
	local w = math.min(cell.wBack, cell.wFront)
	local hole = holeFor(plan, d, c)
	for _, r in ipairs(floorPieces(-w / 2, w / 2, cell.z0, cell.z1, hole)) do
		ctx:part({ Name = "Floor", Size = V3(r[2] - r[1], 1, r[4] - r[3]), CFrame = CFrame.new((r[1] + r[2]) / 2, y - 0.5, (r[3] + r[4]) / 2), Color = floorColor, Material = floorMat })
	end
	-- wedge fills where the hull tapers
	local wide = math.max(cell.wBack, cell.wFront)
	local a = (wide - w) / 2
	if a > 0.3 then
		local narrowAtFront = cell.wFront < cell.wBack
		for _, side in ipairs({ -1, 1 }) do
			local corner = V3(side * w / 2, y - 0.5, if narrowAtFront then cell.z0 else cell.z1)
			local dirB = if narrowAtFront then V3(0, 0, 1) else V3(0, 0, -1)
			ctx:part({ Name = "FloorFill", Class = "WedgePart", Size = V3(1, a, S.CellLength), CFrame = Parts.triangleCFrame(corner, V3(side, 0, 0), a, dirB, S.CellLength), Color = floorColor, Material = floorMat })
		end
	end
	if deck.top then
		return
	end
	local h = S.DeckHeight - 1
	for _, side in ipairs({ -1, 1 }) do
		local p0 = V3(side * cell.wBack / 2, 0, cell.z0)
		local p1 = V3(side * cell.wFront / 2, 0, cell.z1)
		local dir = (p1 - p0).Unit
		local inward = -V3(dir.Z, 0, -dir.X) * side
		local outward = -inward
		if LINED[deck.theme] then
			local mid = (p0 + p1) / 2 + inward * 0.2 + V3(0, y + h / 2, 0)
			ctx:part({ Name = "Lining", Size = V3(0.4, h, (p1 - p0).Magnitude + 0.4), CFrame = CFrame.lookAt(mid, mid + dir), Color = Parts.rgb(theme.Wall), Material = Parts.material(theme.WallMat) })
		end
		if deck.theme == "Promenade" then
			local mid = (p0 + p1) / 2 + outward * (T / 2) + V3(0, y + 6.5, 0)
			ctx:part({ Name = "Window", Size = V3(T + 1, 5, (p1 - p0).Magnitude * 0.72), CFrame = CFrame.lookAt(mid, mid + dir), Color = P.Window, Material = M.Neon, CastShadow = false })
		else
			for _, f in ipairs({ 0.3, 0.7 }) do
				local z = cell.z0 + S.CellLength * f
				local pos = V3(side * (hullX(plan, z) + T / 2), y + 7, z)
				ctx:part({ Name = "Porthole", Shape = Enum.PartType.Cylinder, Size = V3(T + 1.1, 1.7, 1.7), CFrame = CFrame.lookAt(pos, pos + outward) * CFrame.Angles(0, math.rad(90), 0), Color = P.Window, Material = M.Neon, CastShadow = false, CanCollide = false })
			end
		end
	end
	-- structural frame at the stern end of every cell: a ceiling beam plus a rib up each hull side
	do
		local fc = FRAME[deck.theme] or P.SteelDark
		local fm = if FRAME_WOOD[deck.theme] then M.Wood else M.Metal
		local fz = cell.z0 + 0.6
		local fw = 2 * hullX(plan, fz) - 1.2
		ctx:part({ Name = "CeilingBeam", Size = V3(fw, 1, 1.2), CFrame = CFrame.new(0, y + h - 0.5, fz), Color = fc, Material = fm, CanCollide = false })
		for _, side in ipairs({ -1, 1 }) do
			ctx:part({ Name = "Rib", Size = V3(0.9, h - 1, 1.2), CFrame = CFrame.new(side * (fw / 2 - 0.45), y + (h - 1) / 2, fz), Color = fc, Material = fm, CanCollide = false })
		end
		if WAINSCOT[deck.theme] then
			for _, side in ipairs({ -1, 1 }) do
				local z0c, z1c = cell.z0 + 1.2, cell.z1
				local mz = (z0c + z1c) / 2
				local wx = side * (math.min(hullX(plan, z0c), hullX(plan, z1c)) - 0.75)
				ctx:part({ Name = "Wainscot", Size = V3(0.3, 3.2, z1c - z0c), CFrame = CFrame.new(wx, y + 1.6, mz), Color = WAINSCOT[deck.theme], Material = M.Wood, CanCollide = false })
				ctx:part({ Name = "DadoRail", Size = V3(0.45, 0.35, z1c - z0c), CFrame = CFrame.new(wx, y + 3.3, mz), Color = P.Brass, Material = M.Metal, CanCollide = false })
			end
		end
		if deck.theme == "EngineRoom" or deck.theme == "CargoHold" then
			for _, side in ipairs({ -1, 1 }) do
				ctx:part({ Name = "HazardStripe", Size = V3(0.5, 0.06, S.CellLength - 1.4), CFrame = CFrame.new(side * (S.WalkwayHalf + 0.4), y + 0.03, (cell.z0 + cell.z1) / 2 + 0.6), Color = P.Hazard, Material = M.SmoothPlastic, CanCollide = false, CastShadow = false })
			end
		end
	end
	if RUNNER[deck.theme] then
		ctx:part({ Name = "Runner", Size = V3(6, 0.1, S.CellLength), CFrame = CFrame.new(0, y + 0.05, (cell.z0 + cell.z1) / 2), Color = RUNNER[deck.theme], Material = M.Fabric, CanCollide = false })
	end
	if c % 2 == 0 then
		local lampY = y + h - 0.4
		local cz = (cell.z0 + cell.z1) / 2
		local chandelierHere = false
		for _, hz in ipairs(plan.hazards) do
			chandelierHere = chandelierHere or (hz.kind == "Chandelier" and hz.deck == d and hz.cell == c)
		end
		if not chandelierHere then
			ctx:part({ Name = "LampBase", Shape = Enum.PartType.Cylinder, Size = V3(0.4, 2.2, 2.2), CFrame = CFrame.new(0, lampY + 0.2, cz) * Parts.UP, Color = P.Brass, Material = M.Metal, CanCollide = false })
			local bulb = ctx:part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = V3(1.2, 1.2, 1.2), CFrame = CFrame.new(0, lampY - 0.4, cz), Color = Parts.rgb(theme.Light), Material = M.Neon, CanCollide = false, CastShadow = false })
			Parts.light(bulb, Parts.rgb(theme.Light), 26, 1.3, false)
			ctx.record.lamps[#ctx.record.lamps + 1] = bulb
		end
	end
end

---------------------------------------------------------------------------------------------
-- Theme decoration (side bands only; the walkway |x| < WalkwayHalf stays clear)
---------------------------------------------------------------------------------------------

local DECOR = {}

local function sideX(cell, side, inset)
	return side * (cell.width / 2 - inset)
end

function DECOR.EngineRoom(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	local side = if c % 2 == 0 then 1 else -1
	local bx = sideX(cell, side, 5)
	if ctx:claim(d, c, bx, cz, 4, 6) then
		ctx:part({ Name = "Boiler", Shape = Enum.PartType.Cylinder, Size = V3(11, 7, 7), CFrame = CFrame.new(bx, y + 4, cz) * Parts.ALONG_Z, Color = rgb(96, 70, 56), Material = M.Metal })
		for _, dz in ipairs({ -3.5, 3.5 }) do
			ctx:part({ Name = "BoilerBand", Shape = Enum.PartType.Cylinder, Size = V3(0.6, 7.4, 7.4), CFrame = CFrame.new(bx, y + 4, cz + dz) * Parts.ALONG_Z, Color = P.SteelDark, Material = M.Metal, CanCollide = false })
		end
		ctx:part({ Name = "Firebox", Size = V3(3, 3, 0.6), CFrame = CFrame.new(bx, y + 2, cz - 5.8), Color = rgb(255, 120, 40), Material = M.Neon, CanCollide = false })
		ctx:part({ Name = "Gauge", Shape = Enum.PartType.Cylinder, Size = V3(0.3, 1.2, 1.2), CFrame = CFrame.new(bx - side * 3.6, y + 6, cz) * CFrame.Angles(0, 0, 0), Color = P.Cream, Material = M.Neon, CanCollide = false })
	end
	-- pipes along the ceiling on both sides
	for _, s in ipairs({ -1, 1 }) do
		ctx:part({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = V3(S.CellLength, 1.2, 1.2), CFrame = CFrame.new(sideX(cell, s, 1.5), y + 11.4, cz) * Parts.ALONG_Z, Color = rgb(150, 90, 60), Material = M.Metal, CanCollide = false })
	end
	-- catwalk on the other side
	local ox = sideX(cell, -side, 3.2)
	if c % 2 == 1 and ctx:claim(d, c, ox, cz, 2.2, 6) then
		ctx:part({ Name = "Catwalk", Size = V3(4, 0.4, 12), CFrame = CFrame.new(ox, y + 5, cz), Color = P.Steel, Material = M.DiamondPlate })
		ctx:part({ Name = "CatwalkRail", Size = V3(0.3, 0.3, 12), CFrame = CFrame.new(ox + side * 2, y + 8, cz), Color = P.Hazard, Material = M.Metal, CanCollide = false })
		ctx:part({ Name = "CatwalkLeg", Size = V3(0.5, 5, 0.5), CFrame = CFrame.new(ox, y + 2.5, cz), Color = P.SteelDark, Material = M.Metal })
	elseif rng:NextNumber() < 0.5 and ctx:claim(d, c, ox, cz, 1.2, 1.2) then
		ctx:loose({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = V3(2.6, 2, 2), CFrame = CFrame.new(ox, y + 1.3, cz) * Parts.UP, Color = rgb(70, 90, 110), Material = M.Metal })
	end
end

local function crate(ctx, opts, loose)
	opts.Name = "Crate"
	opts.Color = opts.Color or P.Crate
	opts.Material = M.WoodPlanks
	if loose then
		return ctx:loose(opts)
	end
	return ctx:part(opts)
end

function DECOR.CargoHold(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	for _, side in ipairs({ -1, 1 }) do
		local kind = (c + (if side > 0 then 1 else 0)) % 3
		local x = sideX(cell, side, 6)
		if kind == 0 and ctx:claim(d, c, x, cz, 3.8, 6.5) then
			-- a car under a tarp
			ctx:part({ Name = "CarBody", Size = V3(6, 2.4, 11), CFrame = CFrame.new(x, y + 1.9, cz), Color = rgb(120, 40, 40), Material = M.SmoothPlastic })
			ctx:part({ Name = "Tarp", Size = V3(6.6, 2.2, 8), CFrame = CFrame.new(x, y + 3.6, cz - 0.6), Color = P.Tarp, Material = M.Fabric })
			for _, dz in ipairs({ -3.6, 3.6 }) do
				ctx:part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = V3(6.4, 2, 2), CFrame = CFrame.new(x, y + 1, cz + dz), Color = P.Black, Material = M.SmoothPlastic })
			end
		elseif kind == 1 and ctx:claim(d, c, x, cz, 3.5, 4) then
			-- a crate stack (the top one slides)
			crate(ctx, { Size = V3(5, 4, 5), CFrame = CFrame.new(x, y + 2, cz - 1.5) })
			crate(ctx, { Size = V3(4, 3.4, 4), CFrame = CFrame.new(x - side * 0.4, y + 5.7, cz - 1.2) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Color = P.WoodLight })
			crate(ctx, { Size = V3(3, 3, 3), CFrame = CFrame.new(x, y + 1.5, cz + 2.4) }, true)
		elseif kind == 2 and ctx:claim(d, c, x, cz, 3.2, 3.2) then
			-- a wire cage
			for _, dx in ipairs({ -3, 3 }) do
				for _, dz in ipairs({ -3, 3 }) do
					ctx:part({ Name = "CagePost", Size = V3(0.4, 7, 0.4), CFrame = CFrame.new(x + dx, y + 3.5, cz + dz), Color = P.SteelDark, Material = M.Metal })
				end
			end
			ctx:part({ Name = "CageTop", Size = V3(6.4, 0.3, 6.4), CFrame = CFrame.new(x, y + 7, cz), Color = P.Steel, Material = M.DiamondPlate, Transparency = 0.4 })
			ctx:part({ Name = "CageMesh", Size = V3(6.2, 6.6, 0.2), CFrame = CFrame.new(x, y + 3.5, cz - 3), Color = P.Steel, Material = M.DiamondPlate, Transparency = 0.55 })
			crate(ctx, { Size = V3(2.6, 2.6, 2.6), CFrame = CFrame.new(x, y + 1.3, cz + 0.5) * CFrame.Angles(0, 0.4, 0), Color = rgb(90, 110, 80) })
		end
	end
end

function DECOR.CrewQuarters(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	local side = if c % 2 == 0 then 1 else -1
	local x = sideX(cell, side, 3)
	if ctx:claim(d, c, x, cz, 2, 4) then
		-- a two-tier bunk
		for _, h in ipairs({ 1.4, 5 }) do
			ctx:part({ Name = "Bunk", Size = V3(3.4, 0.6, 7), CFrame = CFrame.new(x, y + h, cz), Color = P.SteelDark, Material = M.Metal })
			ctx:part({ Name = "Mattress", Size = V3(3, 0.6, 6.4), CFrame = CFrame.new(x, y + h + 0.6, cz), Color = rgb(200, 206, 214), Material = M.Fabric, CanCollide = false })
			ctx:part({ Name = "Blanket", Size = V3(3.1, 0.3, 3.8), CFrame = CFrame.new(x, y + h + 0.95, cz + 1.2), Color = if (c + math.floor(h)) % 2 == 0 then rgb(60, 80, 120) else rgb(120, 50, 50), Material = M.Fabric, CanCollide = false })
		end
		ctx:part({ Name = "BunkPost", Size = V3(0.4, 7, 7.2), CFrame = CFrame.new(x - side * 1.6, y + 3.5, cz), Color = P.SteelDark, Material = M.Metal, Transparency = 0.2 })
	end
	local ox = sideX(cell, -side, 1.4)
	if ctx:claim(d, c, ox, cz - 3, 1.2, 4.5) then
		ctx:part({ Name = "Lockers", Size = V3(2, 7, 9), CFrame = CFrame.new(ox, y + 3.5, cz - 3), Color = rgb(90, 120, 110), Material = M.Metal })
		ctx:part({ Name = "LockerVents", Size = V3(2.1, 0.4, 8.6), CFrame = CFrame.new(ox, y + 6, cz - 3), Color = P.SteelDark, Material = M.Metal, CanCollide = false })
	end
	if rng:NextNumber() < 0.5 then
		local tx = sideX(cell, -side, 7)
		if ctx:claim(d, c, tx, cz + 4, 2, 2) then
			ctx:part({ Name = "MessTable", Size = V3(3.6, 0.4, 3.6), CFrame = CFrame.new(tx, y + 2.6, cz + 4), Color = P.WoodLight, Material = M.Wood })
			ctx:part({ Name = "TableLeg", Size = V3(0.5, 2.4, 0.5), CFrame = CFrame.new(tx, y + 1.2, cz + 4), Color = P.SteelDark })
		end
	end
end

function DECOR.Cabins(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	local wallX = S.WalkwayHalf + 0.4
	local wall = Parts.rgb(GameConfig.Themes.Cabins.Wall)
	local h = S.DeckHeight - 1
	if cell.width / 2 > wallX + 4 then
		for _, side in ipairs({ -1, 1 }) do
			-- corridor wall with a door opening at the stern end of the cell
			local doorZ0, doorZ1 = cell.z0 + 1.5, cell.z0 + 5.5
			ctx:part({ Name = "CabinWall", Size = V3(0.4, h, cell.z1 - doorZ1), CFrame = CFrame.new(side * wallX, y + h / 2, (doorZ1 + cell.z1) / 2), Color = wall, Material = M.SmoothPlastic })
			ctx:part({ Name = "CabinWall", Size = V3(0.4, h, doorZ0 - cell.z0), CFrame = CFrame.new(side * wallX, y + h / 2, (cell.z0 + doorZ0) / 2), Color = wall, Material = M.SmoothPlastic })
			ctx:part({ Name = "Lintel", Size = V3(0.5, h - 7.5, 4), CFrame = CFrame.new(side * wallX, y + 7.5 + (h - 7.5) / 2, (doorZ0 + doorZ1) / 2), Color = P.Wood, Material = M.Wood })
			-- the cabin door, swung open into the cabin
			ctx:part({ Name = "CabinDoor", Size = V3(3.8, 7.3, 0.3), CFrame = CFrame.new(side * (wallX + 1.9), y + 3.7, doorZ0 + 0.2), Color = P.Wood, Material = M.Wood, CanCollide = false })
			-- a bed against the hull, a suitcase on the floor
			local bx = sideX(cell, side, 3.2)
			if ctx:claim(d, c, bx, cz + 2.5, 2.4, 4) then
				ctx:part({ Name = "Bed", Size = V3(4.4, 1.6, 7.4), CFrame = CFrame.new(bx, y + 0.8, cz + 2.5), Color = P.Wood, Material = M.Wood })
				ctx:part({ Name = "Sheets", Size = V3(4.2, 0.6, 5.4), CFrame = CFrame.new(bx, y + 1.9, cz + 3.4), Color = P.Cream, Material = M.Fabric, CanCollide = false })
				ctx:part({ Name = "Pillow", Size = V3(3, 0.6, 1.4), CFrame = CFrame.new(bx, y + 2, cz - 0.4), Color = rgb(250, 250, 250), Material = M.Fabric, CanCollide = false })
			end
			local sx = side * (wallX + 2.4)
			if rng:NextNumber() < 0.6 and ctx:claim(d, c, sx, cz + 5.5, 1.2, 1.4) then
				ctx:loose({ Name = "Suitcase", Size = V3(2.2, 1.6, 2.8), CFrame = CFrame.new(sx, y + 0.9, cz + 5.5) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0), Color = if rng:NextNumber() < 0.5 then rgb(120, 70, 40) else rgb(60, 70, 110), Material = M.Leather })
			end
		end
	end
end

function DECOR.DiningHall(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	for _, side in ipairs({ -1, 1 }) do
		local tx = side * math.min(cell.width / 2 - 5, S.WalkwayHalf + 6)
		if ctx:claim(d, c, tx, cz, 3.6, 3.6) then
			ctx:part({ Name = "TableTop", Shape = Enum.PartType.Cylinder, Size = V3(0.3, 5.4, 5.4), CFrame = CFrame.new(tx, y + 2.9, cz) * Parts.UP, Color = P.White, Material = M.Fabric })
			ctx:part({ Name = "TableStem", Size = V3(0.6, 2.8, 0.6), CFrame = CFrame.new(tx, y + 1.4, cz), Color = P.BrassDark, Material = M.Metal })
			ctx:part({ Name = "Candle", Size = V3(0.3, 0.9, 0.3), CFrame = CFrame.new(tx, y + 3.5, cz), Color = rgb(255, 210, 120), Material = M.Neon, CanCollide = false, CastShadow = false })
			for _, dz in ipairs({ -3.3, 3.3 }) do
				local facing = CFrame.new(tx, y, cz + dz) * CFrame.Angles(0, if dz > 0 then math.rad(180) else 0, 0)
				if rng:NextNumber() < 0.35 then
					ctx:loose({ Name = "Chair", Size = V3(1.8, 2.6, 1.8), CFrame = facing * CFrame.new(0, 1.3, 0), Color = rgb(120, 40, 46), Material = M.Fabric })
				else
					ctx:part({ Name = "ChairSeat", Size = V3(1.8, 1.5, 1.8), CFrame = facing * CFrame.new(0, 0.75, 0), Color = rgb(120, 40, 46), Material = M.Fabric })
					ctx:part({ Name = "ChairBack", Size = V3(1.8, 2.2, 0.35), CFrame = facing * CFrame.new(0, 2.6, -0.75), Color = P.Wood, Material = M.Wood, CanCollide = false })
				end
			end
		end
		-- wood columns with brass caps along the walls
		if c % 2 == 1 then
			local px = sideX(cell, side, 1.2)
			if ctx:claim(d, c, px, cell.z0 + 1, 1, 1) then
				ctx:part({ Name = "Column", Size = V3(1.4, S.DeckHeight - 1, 1.4), CFrame = CFrame.new(px, y + (S.DeckHeight - 1) / 2, cell.z0 + 1), Color = rgb(110, 70, 40), Material = M.Wood })
			end
		end
	end
	if c == math.floor(plan.cellCount * 0.5) then
		-- the grand piano
		local px = sideX(cell, -1, 6)
		if ctx:claim(d, c, px, cz + 3, 3.5, 3) then
			ctx:part({ Name = "Piano", Size = V3(5, 1.6, 6), CFrame = CFrame.new(px, y + 3, cz + 3), Color = P.Black, Material = M.SmoothPlastic, Reflectance = 0.15 })
			ctx:part({ Name = "PianoLid", Size = V3(4.8, 0.2, 5.6), CFrame = CFrame.new(px + 0.6, y + 4.8, cz + 3) * CFrame.Angles(0, 0, math.rad(-30)), Color = P.Black, Material = M.SmoothPlastic, CanCollide = false })
			ctx:part({ Name = "Keys", Size = V3(5, 0.25, 1), CFrame = CFrame.new(px, y + 3.4, cz - 0.4), Color = P.White, Material = M.SmoothPlastic, CanCollide = false })
			for _, dx in ipairs({ -2, 2 }) do
				ctx:part({ Name = "PianoLeg", Size = V3(0.5, 2.2, 0.5), CFrame = CFrame.new(px + dx, y + 1.1, cz + 3), Color = P.Black })
			end
			ctx:part({ Name = "PianoBench", Size = V3(3, 1.6, 1.3), CFrame = CFrame.new(px, y + 0.8, cz - 1.6), Color = P.Black })
		end
	end
end

function DECOR.Promenade(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	for _, side in ipairs({ -1, 1 }) do
		local rx = sideX(cell, side, 1.6)
		ctx:part({ Name = "Railing", Size = V3(0.3, 0.3, S.CellLength), CFrame = CFrame.new(rx, y + 3.4, cz), Color = P.Brass, Material = M.Metal, CanCollide = false })
		ctx:part({ Name = "RailPost", Size = V3(0.3, 3.4, 0.3), CFrame = CFrame.new(rx, y + 1.7, cell.z0 + 1), Color = P.Brass, Material = M.Metal })
		local x = sideX(cell, side, 5)
		if ctx:claim(d, c, x, cz - 2, 1.6, 2.6) then
			local chair = { Name = "DeckChair", Class = "WedgePart", Size = V3(2.4, 1.8, 4.6), CFrame = CFrame.new(x, y + 0.9, cz - 2) * CFrame.Angles(0, if side > 0 then math.rad(90) else math.rad(-90), 0), Color = P.Cream, Material = M.Fabric }
			if rng:NextNumber() < 0.5 then
				ctx:loose(chair)
			else
				ctx:part(chair)
			end
		end
		local bx = sideX(cell, side, 6.5)
		if c % 2 == 0 and ctx:claim(d, c, bx, cz + 4.5, 1.5, 3) then
			ctx:part({ Name = "Bench", Size = V3(2, 0.5, 5.4), CFrame = CFrame.new(bx, y + 1.8, cz + 4.5), Color = P.Teak, Material = M.WoodPlanks })
			ctx:part({ Name = "BenchFrame", Size = V3(1.6, 1.6, 0.4), CFrame = CFrame.new(bx, y + 0.8, cz + 4.5), Color = P.Black, Material = M.Metal })
		elseif ctx:claim(d, c, bx, cz + 4.5, 1.2, 1.2) then
			ctx:part({ Name = "Planter", Size = V3(2, 1.6, 2), CFrame = CFrame.new(bx, y + 0.8, cz + 4.5), Color = P.WoodLight, Material = M.Wood })
			ctx:part({ Name = "Palm", Shape = Enum.PartType.Ball, Size = V3(2.8, 2.8, 2.8), CFrame = CFrame.new(bx, y + 2.8, cz + 4.5), Color = rgb(60, 130, 70), Material = M.Grass, CanCollide = false })
		end
	end
end

function DECOR.TopDeck(ctx, d, c, rng)
	local plan, y = ctx.plan, ctx.plan.decks[d].y
	local cell = plan.cells[c]
	local cz = (cell.z0 + cell.z1) / 2
	local dh = ctx.plan.deckhouse
	local inHouse = dh and cz > dh.z0 and cz < dh.z1
	if c % 2 == 1 and c > 2 then
		for _, side in ipairs({ -1, 1 }) do
			local x = sideX(cell, side, 1.8)
			if ctx:claim(d, c, x, cz, 0.8, 0.8) then
				ctx:part({ Name = "LampPost", Size = V3(0.5, 7, 0.5), CFrame = CFrame.new(x, y + 3.5, cz), Color = P.Black, Material = M.Metal })
				local lamp = ctx:part({ Name = "DeckLamp", Shape = Enum.PartType.Ball, Size = V3(1.3, 1.3, 1.3), CFrame = CFrame.new(x, y + 7.4, cz), Color = P.Window, Material = M.Neon, CanCollide = false, CastShadow = false })
				Parts.light(lamp, P.Window, 22, 1.2, false)
			end
		end
	end
	if not inHouse and c > 2 and c < plan.cellCount - 1 and rng:NextNumber() < 0.5 then
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = sideX(cell, side, 5)
		if ctx:claim(d, c, x, cz + 3, 1.4, 3) then
			ctx:part({ Name = "Bench", Size = V3(2, 0.5, 5.4), CFrame = CFrame.new(x, y + 1.8, cz + 3), Color = P.Teak, Material = M.WoodPlanks })
			ctx:part({ Name = "BenchBack", Size = V3(0.4, 1.6, 5.4), CFrame = CFrame.new(x + side * 0.9, y + 2.8, cz + 3), Color = P.Teak, Material = M.WoodPlanks })
		end
	end
	if c % 3 == 0 then
		local side = if c % 2 == 0 then 1 else -1
		local z = cz
		ctx:part({ Name = "LifeRing", Shape = Enum.PartType.Cylinder, Size = V3(0.6, 2.4, 2.4), CFrame = CFrame.new(side * (hullX(plan, z) - 0.4), y + 2.2, z) * CFrame.Angles(0, 0, 0), Color = P.Orange, Material = M.SmoothPlastic, CanCollide = false })
	end
end

---------------------------------------------------------------------------------------------
-- Fill: extra small clusters on free spots of the side bands, so big decks never look empty
---------------------------------------------------------------------------------------------

local FILL = {}

local function at(x, y, z, rot)
	return CFrame.new(x, y, z) * CFrame.Angles(0, rot or 0, 0)
end

FILL.EngineRoom = {
	{ 1.6, 1.6, function(ctx, x, y, z, _rng)
		-- a pipe column with a valve wheel
		ctx:part({ Name = "PipeColumn", Shape = Enum.PartType.Cylinder, Size = V3(S.DeckHeight - 1, 1.4, 1.4), CFrame = CFrame.new(x, y + (S.DeckHeight - 1) / 2, z) * Parts.UP, Color = rgb(150, 90, 60), Material = M.Metal })
		ctx:part({ Name = "PipeFlange", Shape = Enum.PartType.Cylinder, Size = V3(0.5, 2, 2), CFrame = CFrame.new(x, y + 4, z) * Parts.UP, Color = P.SteelDark, Material = M.Metal, CanCollide = false })
		ctx:part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = V3(0.3, 2.2, 2.2), CFrame = CFrame.new(x, y + 4.5, z + 1.1) * Parts.ALONG_Z, Color = P.Red, Material = M.Metal, CanCollide = false })
	end },
	{ 2.6, 1.6, function(ctx, x, y, z, _rng)
		-- a control panel with lit gauges
		ctx:part({ Name = "Panel", Size = V3(5, 5, 2), CFrame = at(x, y + 2.5, z), Color = rgb(60, 84, 80), Material = M.Metal })
		for i = -1, 1 do
			ctx:part({ Name = "Gauge", Shape = Enum.PartType.Cylinder, Size = V3(0.2, 1, 1), CFrame = CFrame.new(x + i * 1.4, y + 3.8, z - 1.05) * Parts.ALONG_Z, Color = if i == 0 then rgb(255, 90, 60) else P.Cream, Material = M.Neon, CanCollide = false, CastShadow = false })
		end
		ctx:part({ Name = "Levers", Size = V3(3.4, 0.6, 0.6), CFrame = CFrame.new(x, y + 2.2, z - 1.2), Color = P.Black, Material = M.Metal, CanCollide = false })
	end },
	{ 2.2, 2.2, function(ctx, x, y, z, rng)
		-- oil drums
		for i, o in ipairs({ { -0.9, -0.9 }, { 1, -0.6 }, { 0, 1.1 } }) do
			local opts = { Name = "OilDrum", Shape = Enum.PartType.Cylinder, Size = V3(2.8, 1.8, 1.8), CFrame = CFrame.new(x + o[1], y + 1.4, z + o[2]) * Parts.UP, Color = if i == 2 then rgb(170, 60, 40) else rgb(60, 90, 120), Material = M.Metal }
			if i == 3 and rng:NextNumber() < 0.5 then
				ctx:loose(opts)
			else
				ctx:part(opts)
			end
		end
	end },
	{ 3.2, 1.6, function(ctx, x, y, z, _rng)
		-- a pump engine: block, flywheel, piston
		ctx:part({ Name = "PumpBlock", Size = V3(4, 3, 2.6), CFrame = at(x, y + 1.5, z), Color = rgb(80, 96, 70), Material = M.Metal })
		ctx:part({ Name = "Flywheel", Shape = Enum.PartType.Cylinder, Size = V3(0.6, 4.4, 4.4), CFrame = CFrame.new(x + 2.4, y + 2.4, z), Color = P.SteelDark, Material = M.Metal })
		ctx:part({ Name = "Piston", Size = V3(1.2, 2.6, 1.2), CFrame = at(x - 0.8, y + 4.2, z), Color = P.Steel, Material = M.Metal })
	end },
}

FILL.CargoHold = {
	{ 2.6, 2.6, function(ctx, x, y, z, rng)
		crate(ctx, { Size = V3(4, 4, 4), CFrame = at(x, y + 2, z, rng:NextNumber(-0.2, 0.2)) })
		crate(ctx, { Size = V3(3, 3, 3), CFrame = at(x + 0.3, y + 5.5, z - 0.2, rng:NextNumber(-0.4, 0.4)), Color = P.WoodLight }, rng:NextNumber() < 0.4)
	end },
	{ 2.4, 2.4, function(ctx, x, y, z, _rng)
		-- a pallet of sacks
		ctx:part({ Name = "Pallet", Size = V3(4.4, 0.5, 4.4), CFrame = at(x, y + 0.25, z), Color = P.WoodLight, Material = M.WoodPlanks })
		for i, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } }) do
			ctx:part({ Name = "Sack", Size = V3(1.9, 1.2, 1.9), CFrame = CFrame.new(x + o[1], y + (if i == 5 then 1.9 else 1.1), z + o[2]), Color = rgb(196, 176, 130), Material = M.Fabric, CanCollide = i ~= 5 })
		end
	end },
	{ 1.8, 1.8, function(ctx, x, y, z, rng)
		for i, o in ipairs({ { -0.8, 0 }, { 0.8, 0.4 } }) do
			local opts = { Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = V3(2.8, 1.9, 1.9), CFrame = CFrame.new(x + o[1], y + 1.4, z + o[2]) * Parts.UP, Color = rgb(120, 80, 46), Material = M.Wood }
			if i == 2 and rng:NextNumber() < 0.5 then
				ctx:loose(opts)
			else
				ctx:part(opts)
			end
		end
	end },
	{ 2, 1.4, function(ctx, x, y, z, rng)
		-- a steamer trunk with brass corners
		ctx:part({ Name = "Trunk", Size = V3(3.6, 2.2, 2.2), CFrame = at(x, y + 1.1, z, rng:NextNumber(-0.3, 0.3)), Color = rgb(70, 50, 90), Material = M.Leather })
		ctx:part({ Name = "TrunkBand", Size = V3(3.7, 0.3, 2.3), CFrame = at(x, y + 1.6, z), Color = P.Brass, Material = M.Metal, CanCollide = false })
	end },
}

FILL.CrewQuarters = {
	{ 1.4, 2.2, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "Locker", Size = V3(2, 7, 4), CFrame = at(x, y + 3.5, z), Color = rgb(90, 120, 110), Material = M.Metal })
		ctx:part({ Name = "LockerVents", Size = V3(2.1, 0.4, 3.6), CFrame = at(x, y + 6, z), Color = P.SteelDark, Material = M.Metal, CanCollide = false })
	end },
	{ 2, 2, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "MessTable", Size = V3(3.6, 0.4, 3.6), CFrame = at(x, y + 2.6, z), Color = P.WoodLight, Material = M.Wood })
		ctx:part({ Name = "TableLeg", Size = V3(0.5, 2.4, 0.5), CFrame = at(x, y + 1.2, z), Color = P.SteelDark })
		ctx:loose({ Name = "Stool", Shape = Enum.PartType.Cylinder, Size = V3(1.6, 1.4, 1.4), CFrame = CFrame.new(x + 2.4, y + 0.8, z) * Parts.UP, Color = P.SteelDark, Material = M.Metal })
	end },
	{ 1.2, 1.2, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "LaundryBasket", Shape = Enum.PartType.Cylinder, Size = V3(1.6, 1.8, 1.8), CFrame = CFrame.new(x, y + 0.8, z) * Parts.UP, Color = rgb(190, 160, 110), Material = M.Fabric })
		ctx:part({ Name = "Laundry", Shape = Enum.PartType.Ball, Size = V3(1.6, 1, 1.6), CFrame = CFrame.new(x, y + 1.7, z), Color = rgb(220, 224, 230), Material = M.Fabric, CanCollide = false })
	end },
}

FILL.Cabins = {
	{ 1.4, 1.8, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "Wardrobe", Size = V3(2.2, 7, 3.4), CFrame = at(x, y + 3.5, z), Color = P.Wood, Material = M.Wood })
		ctx:part({ Name = "WardrobeTrim", Size = V3(2.3, 0.4, 3.5), CFrame = at(x, y + 7.1, z), Color = P.Brass, Material = M.Metal, CanCollide = false })
	end },
	{ 1.6, 1.6, function(ctx, x, y, z, rng)
		-- a writing desk with a lit lamp
		ctx:part({ Name = "Desk", Size = V3(2.8, 2.6, 2), CFrame = at(x, y + 1.3, z), Color = P.Wood, Material = M.Wood })
		local lamp = ctx:part({ Name = "DeskLamp", Shape = Enum.PartType.Ball, Size = V3(0.9, 0.9, 0.9), CFrame = CFrame.new(x + 0.8, y + 3.1, z), Color = P.Window, Material = M.Neon, CanCollide = false, CastShadow = false })
		if rng:NextNumber() < 0.3 then
			Parts.light(lamp, P.Window, 12, 0.8, false)
		end
	end },
	{ 1.4, 1.4, function(ctx, x, y, z, rng)
		ctx:loose({ Name = "Armchair", Size = V3(2.4, 2.4, 2.4), CFrame = at(x, y + 1.2, z, rng:NextNumber(-0.6, 0.6)), Color = rgb(110, 40, 50), Material = M.Fabric })
	end },
}

FILL.DiningHall = {
	{ 1.4, 1.4, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "Pot", Shape = Enum.PartType.Cylinder, Size = V3(1.8, 1.8, 1.8), CFrame = CFrame.new(x, y + 0.9, z) * Parts.UP, Color = P.Brass, Material = M.Metal })
		ctx:part({ Name = "Fern", Shape = Enum.PartType.Ball, Size = V3(3, 3.4, 3), CFrame = CFrame.new(x, y + 3.2, z), Color = rgb(60, 130, 70), Material = M.Grass, CanCollide = false })
	end },
	{ 1.4, 3, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "Sideboard", Size = V3(2, 3.4, 5.6), CFrame = at(x, y + 1.7, z), Color = rgb(96, 56, 32), Material = M.Wood })
		ctx:part({ Name = "SideboardTop", Size = V3(2.2, 0.3, 5.8), CFrame = at(x, y + 3.5, z), Color = P.Cream, Material = M.Marble })
		for i = -1, 1 do
			ctx:part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = V3(1, 0.5, 0.5), CFrame = CFrame.new(x, y + 4.1, z + i * 1.4) * Parts.UP, Color = rgb(40, 110, 60), Material = M.Glass, Transparency = 0.2, CanCollide = false })
		end
	end },
	{ 1.6, 1.6, function(ctx, x, y, z, rng)
		ctx:loose({ Name = "ServiceCart", Size = V3(2.2, 2.4, 3), CFrame = at(x, y + 1.2, z, rng:NextNumber(-0.4, 0.4)), Color = P.Brass, Material = M.Metal })
	end },
}

FILL.Promenade = {
	{ 1.2, 1.2, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "Planter", Size = V3(2, 1.6, 2), CFrame = at(x, y + 0.8, z), Color = P.WoodLight, Material = M.Wood })
		ctx:part({ Name = "Palm", Shape = Enum.PartType.Ball, Size = V3(2.8, 2.8, 2.8), CFrame = CFrame.new(x, y + 2.8, z), Color = rgb(60, 130, 70), Material = M.Grass, CanCollide = false })
	end },
	{ 1.6, 2.6, function(ctx, x, y, z, rng)
		ctx:loose({ Name = "DeckChair", Class = "WedgePart", Size = V3(2.4, 1.8, 4.6), CFrame = at(x, y + 0.9, z, if x > 0 then math.rad(90) else math.rad(-90)), Color = if rng:NextNumber() < 0.5 then P.Cream else rgb(120, 170, 200), Material = M.Fabric })
	end },
	{ 1.6, 1.6, function(ctx, x, y, z, _rng)
		ctx:part({ Name = "CafeTable", Shape = Enum.PartType.Cylinder, Size = V3(0.3, 2.6, 2.6), CFrame = CFrame.new(x, y + 2.6, z) * Parts.UP, Color = P.White, Material = M.Marble })
		ctx:part({ Name = "CafeStem", Size = V3(0.4, 2.5, 0.4), CFrame = at(x, y + 1.25, z), Color = P.Black, Material = M.Metal })
	end },
}

local FILL_COUNT = { EngineRoom = 3, CargoHold = 3, CrewQuarters = 2, Cabins = 2, DiningHall = 2, Promenade = 2 }

local function fill(ctx, d, c, rng)
	local plan = ctx.plan
	local deck = plan.decks[d]
	local list = FILL[deck.theme]
	if not list then
		return
	end
	local y = deck.y
	for i = 1, FILL_COUNT[deck.theme] or 2 do
		local item = list[rng:NextInteger(1, #list)]
		local side = if (c + i) % 2 == 0 then 1 else -1
		local x, z = ShipGen.freeSpot(plan, rng, d, c, item[1], item[2], side)
		if x and ctx:claim(d, c, x, z, item[1], item[2]) then
			item[3](ctx, x, y, z, rng)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Superstructure: deckhouse, helm, funnels, masts, empty davits
---------------------------------------------------------------------------------------------

local function superstructure(ctx)
	local plan = ctx.plan
	local def = plan.def
	local y = plan.decks[#plan.decks].y
	local dh = plan.deckhouse
	local hw = dh.halfWidth
	local houseH = 9
	local white, cream = P.White, P.Cream
	local zc, zl = (dh.z0 + dh.z1) / 2, dh.z1 - dh.z0
	ctx:part({ Name = "Deckhouse", Size = V3(hw * 2, houseH, zl), CFrame = CFrame.new(0, y + houseH / 2, zc), Color = white, Material = M.SmoothPlastic })
	for _, side in ipairs({ -1, 1 }) do
		ctx:part({ Name = "HouseWindows", Size = V3(0.4, 2.2, zl - 4), CFrame = CFrame.new(side * (hw + 0.1), y + 5, zc), Color = P.Window, Material = M.Neon, CastShadow = false })
		ctx:part({ Name = "HouseStripe", Size = V3(0.3, 0.6, zl), CFrame = CFrame.new(side * (hw + 0.1), y + 7.6, zc), Color = Parts.rgb(def.FunnelBand), Material = M.SmoothPlastic })
	end
	ctx:part({ Name = "HouseRoof", Size = V3(hw * 2 + 2, 0.8, zl + 2), CFrame = CFrame.new(0, y + houseH + 0.4, zc), Color = cream, Material = M.SmoothPlastic })
	local lowH = houseH
	if def.Order >= 2 then
		-- a second, set-back tier (a stepped superstructure)
		local hw2, zl2 = hw - 5, zl - 18
		local z2 = zc - 2
		ctx:part({ Name = "UpperHouse", Size = V3(hw2 * 2, 6, zl2), CFrame = CFrame.new(0, y + houseH + 3.8, z2), Color = white, Material = M.SmoothPlastic })
		for _, side in ipairs({ -1, 1 }) do
			ctx:part({ Name = "UpperWindows", Size = V3(0.4, 1.6, zl2 - 4), CFrame = CFrame.new(side * (hw2 + 0.1), y + houseH + 4, z2), Color = P.Window, Material = M.Neon, CastShadow = false })
		end
		ctx:part({ Name = "UpperRoof", Size = V3(hw2 * 2 + 1.5, 0.6, zl2 + 1.5), CFrame = CFrame.new(0, y + houseH + 7.1, z2), Color = cream, Material = M.SmoothPlastic })
		houseH += 6.6
	end
	-- bridge on the roof's forward end, with wings out to the sides
	local bz = dh.z1 - 5
	local bridgeW = math.min(hw * 2 - 4, 24)
	ctx:part({ Name = "Bridge", Size = V3(bridgeW, 6, 9), CFrame = CFrame.new(0, y + lowH + 3.8, bz), Color = white, Material = M.SmoothPlastic })
	ctx:part({ Name = "BridgeWindows", Size = V3(bridgeW - 2, 2, 0.4), CFrame = CFrame.new(0, y + lowH + 4.6, bz + 4.6), Color = P.WindowCool, Material = M.Neon, CastShadow = false })
	ctx:part({ Name = "BridgeRoof", Size = V3(bridgeW + 2, 0.6, 10.5), CFrame = CFrame.new(0, y + lowH + 7.1, bz), Color = cream, Material = M.SmoothPlastic })
	ctx:part({ Name = "BridgeWings", Size = V3(hw * 2 + 6, 0.6, 3.5), CFrame = CFrame.new(0, y + lowH + 1.2, bz + 2.5), Color = cream, Material = M.SmoothPlastic })
	-- funnels on the roof, raked back
	local n = def.Funnels
	for i = 1, n do
		local fz = dh.z0 + 8 + (zl - 22) * (if n == 1 then 0.5 else (i - 1) / (n - 1))
		local d = math.clamp(hw * 0.55, 6, 10)
		local base = CFrame.new(0, y + houseH + 0.8, fz) * CFrame.Angles(math.rad(-8), 0, 0)
		local fh = 12 + def.Order * 2
		ctx:part({ Name = "Funnel", Shape = Enum.PartType.Cylinder, Size = V3(fh, d, d * 1.25), CFrame = base * CFrame.new(0, fh / 2, 0) * Parts.UP, Color = Parts.rgb(def.Funnel), Material = M.SmoothPlastic })
		ctx:part({ Name = "FunnelBand", Shape = Enum.PartType.Cylinder, Size = V3(2.4, d + 0.2, d * 1.25 + 0.2), CFrame = base * CFrame.new(0, fh - 3.2, 0) * Parts.UP, Color = Parts.rgb(def.FunnelBand), Material = M.SmoothPlastic })
		local top = ctx:part({ Name = "FunnelTop", Shape = Enum.PartType.Cylinder, Size = V3(1.4, d + 0.3, d * 1.25 + 0.3), CFrame = base * CFrame.new(0, fh - 0.7, 0) * Parts.UP, Color = P.Black, Material = M.SmoothPlastic })
		if i == 1 then
			local smoke = Instance.new("ParticleEmitter")
			smoke.Name = "Smoke"
			smoke.Color = ColorSequence.new(rgb(60, 60, 66), rgb(120, 120, 128))
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			smoke.Lifetime = NumberRange.new(4, 7)
			smoke.Rate = 5
			smoke.Speed = NumberRange.new(4, 7)
			smoke.EmissionDirection = Enum.NormalId.Right
			smoke.Parent = top
		end
	end
	-- helm station in front of the deckhouse: ship's wheel, binnacle, telegraph
	local hz = dh.z1 + 6
	ctx:part({ Name = "HelmStand", Size = V3(1.2, 3.4, 1.2), CFrame = CFrame.new(0, y + 1.7, hz), Color = P.Wood, Material = M.Wood })
	ctx:part({ Name = "ShipsWheel", Shape = Enum.PartType.Cylinder, Size = V3(0.4, 4, 4), CFrame = CFrame.new(0, y + 3.8, hz + 0.8) * Parts.ALONG_Z, Color = P.Wood, Material = M.Wood, CanCollide = false })
	ctx:part({ Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = V3(0.8, 1, 1), CFrame = CFrame.new(0, y + 3.8, hz + 0.8) * Parts.ALONG_Z, Color = P.Brass, Material = M.Metal, CanCollide = false })
	for a = 0, 3 do
		ctx:part({ Name = "Spoke", Size = V3(0.3, 5.4, 0.3), CFrame = CFrame.new(0, y + 3.8, hz + 1) * CFrame.Angles(0, 0, math.rad(a * 45)), Color = P.WoodLight, Material = M.Wood, CanCollide = false })
	end
	ctx:part({ Name = "Binnacle", Shape = Enum.PartType.Cylinder, Size = V3(3.2, 1.6, 1.6), CFrame = CFrame.new(-3, y + 1.6, hz) * Parts.UP, Color = P.Brass, Material = M.Metal })
	ctx:part({ Name = "Telegraph", Size = V3(1, 3.6, 1), CFrame = CFrame.new(3, y + 1.8, hz), Color = P.Brass, Material = M.Metal })
	ctx:part({ Name = "TelegraphDial", Shape = Enum.PartType.Cylinder, Size = V3(0.6, 1.8, 1.8), CFrame = CFrame.new(3, y + 3.8, hz) * Parts.ALONG_Z, Color = P.Cream, Material = M.SmoothPlastic, CanCollide = false })
	-- cowl ventilators aft of the deckhouse, a cargo hatch forward
	for _, x in ipairs({ -3, 3 }) do
		local vz = dh.z0 - 8
		ctx:part({ Name = "VentPipe", Shape = Enum.PartType.Cylinder, Size = V3(4, 1.3, 1.3), CFrame = CFrame.new(x, y + 2, vz) * Parts.UP, Color = P.White, Material = M.SmoothPlastic })
		ctx:part({ Name = "VentCowl", Shape = Enum.PartType.Ball, Size = V3(2.4, 2.4, 2.4), CFrame = CFrame.new(x, y + 4.3, vz + 0.3), Color = P.Red, Material = M.SmoothPlastic })
	end
	local hatchZ = (dh.z1 + 6 + plan.length - S.CellLength * 2) / 2
	ctx:part({ Name = "Hatch", Size = V3(7, 1, 9), CFrame = CFrame.new(0, y + 0.5, hatchZ), Color = P.SteelDark, Material = M.Metal })
	ctx:part({ Name = "HatchCover", Size = V3(7.6, 0.3, 9.6), CFrame = CFrame.new(0, y + 1.1, hatchZ), Color = Color3.fromRGB(70, 90, 70), Material = M.Fabric })
	-- masts with lights
	for _, mz in ipairs({ plan.length - S.CellLength * 2, dh.z0 - 6 }) do
		local mh = 18 + def.Order * 3
		ctx:part({ Name = "Mast", Shape = Enum.PartType.Cylinder, Size = V3(mh, 1, 1), CFrame = CFrame.new(0, y + mh / 2, mz) * Parts.UP, Color = P.Cream, Material = M.Wood })
		ctx:part({ Name = "Yard", Size = V3(10, 0.5, 0.5), CFrame = CFrame.new(0, y + mh * 0.75, mz), Color = P.Cream, Material = M.Wood })
		local lamp = ctx:part({ Name = "MastLight", Shape = Enum.PartType.Ball, Size = V3(1, 1, 1), CFrame = CFrame.new(0, y + mh + 0.5, mz), Color = P.Window, Material = M.Neon, CanCollide = false, CastShadow = false })
		Parts.light(lamp, P.Window, 30, 1, false)
		for _, side in ipairs({ -1, 1 }) do
			ctx:beam(V3(0, y + mh * 0.75, mz), V3(side * (hullX(plan, mz) - 0.5), y + BULWARK, mz - 6), 0.15, 0.15, { Name = "Stay", Color = P.Black, Material = M.SmoothPlastic, CanCollide = false })
		end
	end
	-- empty davits along both sides: the other lifeboats are already gone
	local pairsPerSide = def.Order
	for i = 1, pairsPerSide do
		local z = dh.z0 + 6 + (zl - 12) * (if pairsPerSide == 1 then 0.5 else (i - 1) / (pairsPerSide - 1))
		for _, side in ipairs({ -1, 1 }) do
			local x = side * (hullX(plan, z) - 1)
			for _, dz in ipairs({ -4, 4 }) do
				ctx:part({ Name = "DavitPost", Size = V3(0.7, 7, 0.7), CFrame = CFrame.new(x, y + 3.5, z + dz), Color = P.Steel, Material = M.Metal })
				ctx:beam(V3(x, y + 7, z + dz), V3(x + side * 4, y + 8.5, z + dz), 0.7, 0.7, { Name = "DavitArm", Color = P.Steel, Material = M.Metal })
				ctx:part({ Name = "Rope", Size = V3(0.15, 5, 0.15), CFrame = CFrame.new(x + side * 4, y + 6, z + dz), Color = P.Rope, Material = M.Fabric, CanCollide = false })
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Connectors
---------------------------------------------------------------------------------------------

local function debris(ctx, x, y, z, rng)
	for i = 1, 3 do
		ctx:part({ Name = "Debris", Size = V3(rng:NextNumber(3, 6), 0.8, rng:NextNumber(0.8, 1.6)), CFrame = CFrame.new(x + rng:NextNumber(-1.5, 1.5), y + 0.6 + i * 0.7, z + rng:NextNumber(-2, 2)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5)), Color = if i == 2 then P.Wood else P.SteelDark, Material = if i == 2 then M.WoodPlanks else M.CorrodedMetal })
	end
	ctx:part({ Name = "Debris", Size = V3(4, 3, 3), CFrame = CFrame.new(x, y + 1.5, z) * CFrame.Angles(0, 0.5, 0.2), Color = P.Crate, Material = M.WoodPlanks })
end

local function connector(ctx, conn, rng)
	local plan = ctx.plan
	local y0 = plan.decks[conn.from].y
	local y1 = plan.decks[conn.to].y
	local rise = y1 - y0
	local x, cz = conn.x, conn.z
	local hx, hz = ShipGen.connectorFootprint(conn.kind)
	if conn.kind == "Stair" or conn.kind == "GrandStair" then
		local steps = math.floor(rise + 0.5)
		local run = (hz * 2 - 1) / steps
		local width = hx * 2 - 1
		local grand = conn.kind == "GrandStair"
		local stepColor = if grand then rgb(150, 30, 40) else P.Steel
		local stepMat = if grand then M.Fabric else M.DiamondPlate
		local zStart = cz - hz + 0.5
		for i = 1, steps do
			local top = y0 + i * rise / steps
			ctx:part({ Name = "Step", Size = V3(width, 0.8, run + 0.05), CFrame = CFrame.new(x, top - 0.4, zStart + (i - 0.5) * run), Color = stepColor, Material = stepMat })
		end
		local a = V3(x, y0, zStart)
		local b = V3(x, y1, zStart + steps * run)
		for _, s in ipairs({ -1, 1 }) do
			local off = V3(s * (width / 2 + 0.25), 0, 0)
			ctx:beam(a + off + V3(0, 0.2, 0), b + off + V3(0, 0.2, 0), 0.5, 1.4, { Name = "Stringer", Color = if grand then P.Wood else P.SteelDark, Material = if grand then M.Wood else M.Metal })
			ctx:beam(a + off + V3(0, 3.4, 0), b + off + V3(0, 3.4, 0), 0.35, 0.35, { Name = "Handrail", Color = if grand then P.Brass else P.Hazard, Material = M.Metal, CanCollide = false })
		end
		if grand then
			for _, s in ipairs({ -1, 1 }) do
				ctx:part({ Name = "Newel", Size = V3(1, 4, 1), CFrame = CFrame.new(x + s * (width / 2 + 0.3), y0 + 2, zStart - 0.2), Color = P.Wood, Material = M.Wood })
				ctx:part({ Name = "NewelCap", Shape = Enum.PartType.Ball, Size = V3(1.3, 1.3, 1.3), CFrame = CFrame.new(x + s * (width / 2 + 0.3), y0 + 4.4, zStart - 0.2), Color = P.Brass, Material = M.Metal })
			end
		end
		if conn.blocked then
			debris(ctx, x, y0 + rise * 0.45, cz, rng)
		else
			-- guard rail round the hole on the deck above (inboard side and stern end)
			local gx = x - (if x > 0 then 1 else -1) * hx
			ctx:part({ Name = "GuardRail", Size = V3(0.3, 3, hz * 2), CFrame = CFrame.new(gx, y1 + 1.5, cz), Color = P.Brass, Material = M.Metal, Transparency = 0.1 })
		end
	else
		-- ladder / service shaft: a climbable truss against the hull
		local truss = ctx:part({ Name = if conn.kind == "Shaft" then "ShaftLadder" else "Ladder", Class = "TrussPart", Size = V3(2, rise + 2, 2), CFrame = CFrame.new(x - (if x > 0 then 1 else -1) * 0.5, y0 + (rise + 2) / 2, cz), Color = if conn.kind == "Shaft" then P.Hazard else P.Steel, Material = M.Metal })
		truss:SetAttribute("Ladder", true)
		if conn.kind == "Shaft" then
			for _, dz in ipairs({ -2.4, 2.4 }) do
				ctx:part({ Name = "ShaftWall", Size = V3(4.6, rise - 1, 0.3), CFrame = CFrame.new(x, y0 + (rise - 1) / 2, cz + dz), Color = P.SteelDark, Material = M.Metal })
			end
			local sign = ctx:part({ Name = "ShaftSign", Size = V3(4, 1.4, 0.2), CFrame = CFrame.new(x, y0 + 8, cz - 2.6), Color = P.Hazard, Material = M.SmoothPlastic, CanCollide = false })
			ShipBuilder.nameplate(sign, "SERVICE SHAFT", P.Black)
		end
		if conn.blocked then
			debris(ctx, x, y0, cz, rng)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Obstacles and hazards (the services wire up prompts and behaviour)
---------------------------------------------------------------------------------------------

local function bulkhead(ctx, b)
	local plan = ctx.plan
	local y = plan.decks[b.deck].y
	local h = S.DeckHeight - 1
	local w = b.width
	local folder = Instance.new("Folder")
	folder.Name = "Bulkhead" .. b.id
	folder.Parent = ctx.record.obstacleFolder
	ctx.current = folder
	local doorHalf = 2.6
	for _, side in ipairs({ -1, 1 }) do
		local inner, outer = doorHalf, w / 2
		ctx:part({ Name = "BulkheadWall", Size = V3(outer - inner, h, 1), CFrame = CFrame.new(side * (inner + outer) / 2, y + h / 2, b.z), Color = P.SteelDark, Material = M.Metal })
		ctx:part({ Name = "HazardStripe", Size = V3(0.6, 7.6, 1.1), CFrame = CFrame.new(side * (doorHalf + 0.3), y + 3.8, b.z), Color = P.Hazard, Material = M.SmoothPlastic, CanCollide = false })
	end
	ctx:part({ Name = "BulkheadLintel", Size = V3(doorHalf * 2, h - 7.6, 1), CFrame = CFrame.new(0, y + 7.6 + (h - 7.6) / 2, b.z), Color = P.SteelDark, Material = M.Metal })
	local doorLocal = CFrame.new(0, y + 3.8, b.z)
	local door = ctx:part({ Name = "BulkheadDoor", Size = V3(doorHalf * 2, 7.6, 0.8), CFrame = doorLocal, Color = rgb(120, 60, 50), Material = M.DiamondPlate })
	ctx:part({ Name = "DoorWheel", Shape = Enum.PartType.Cylinder, Size = V3(0.3, 2.2, 2.2), CFrame = CFrame.new(0, y + 4, b.z + 0.55) * Parts.ALONG_Z, Color = P.Brass, Material = M.Metal, CanCollide = false })
	local record = { plan = b, door = door, doorLocal = doorLocal, levers = {}, folder = folder }
	record.wheel = folder:FindFirstChild("DoorWheel")
	for i, lever in ipairs(b.levers) do
		ctx:part({ Name = "LeverBase", Size = V3(1.6, 3.4, 1), CFrame = CFrame.new(lever.x, y + 1.7, lever.z), Color = P.SteelDark, Material = M.Metal })
		local handleLocal = CFrame.new(lever.x, y + 3.9, lever.z) * CFrame.Angles(math.rad(-30), 0, 0)
		local handle = ctx:part({ Name = "LeverHandle", Size = V3(0.4, 2.4, 0.4), CFrame = handleLocal, Color = P.Red, Material = M.SmoothPlastic, CanCollide = false })
		local lamp = ctx:part({ Name = "LeverLamp", Shape = Enum.PartType.Ball, Size = V3(0.7, 0.7, 0.7), CFrame = CFrame.new(lever.x, y + 3.6, lever.z - 0.6), Color = P.Red, Material = M.Neon, CanCollide = false, CastShadow = false })
		record.levers[i] = { plan = lever, handle = handle, lamp = lamp, handleLocal = handleLocal }
	end
	ctx.current = ctx.record.model
	table.insert(ctx.record.bulkheads, record)
end

local function valve(ctx, v)
	local plan = ctx.plan
	local y = plan.decks[v.deck].y
	local folder = Instance.new("Folder")
	folder.Name = "Valve" .. v.id
	folder.Parent = ctx.record.obstacleFolder
	ctx.current = folder
	local wx = v.x - v.side * 0.8
	ctx:part({ Name = "ValvePipe", Shape = Enum.PartType.Cylinder, Size = V3(2, 1, 1), CFrame = CFrame.new(v.x + v.side * 0.2, y + 4, v.z), Color = rgb(150, 90, 60), Material = M.Metal })
	ctx:part({ Name = "ValveRiser", Size = V3(0.9, 4, 0.9), CFrame = CFrame.new(v.x + v.side * 0.6, y + 2, v.z), Color = rgb(150, 90, 60), Material = M.Metal })
	local wheelLocal = CFrame.new(wx, y + 4, v.z)
	local wheel = ctx:part({ Name = "ValveWheel", Shape = Enum.PartType.Cylinder, Size = V3(0.35, 3, 3), CFrame = wheelLocal, Color = P.Red, Material = M.Metal })
	ctx:part({ Name = "ValveSpoke", Size = V3(0.3, 2.8, 0.3), CFrame = CFrame.new(wx - v.side * 0.1, y + 4, v.z), Color = P.Red, Material = M.Metal, CanCollide = false })
	ctx:part({ Name = "ValveSpoke", Size = V3(0.3, 0.3, 2.8), CFrame = CFrame.new(wx - v.side * 0.1, y + 4, v.z), Color = P.Red, Material = M.Metal, CanCollide = false })
	local tag = ctx:part({ Name = "ValveTag", Size = V3(2.4, 1, 0.2), CFrame = CFrame.new(v.x + v.side * 0.95, y + 6.4, v.z) * CFrame.Angles(0, if v.side > 0 then math.rad(90) else math.rad(-90), 0), Color = P.Hazard, Material = M.SmoothPlastic, CanCollide = false })
	ShipBuilder.nameplate(tag, "VALVE", P.Black)
	ctx.current = ctx.record.model
	table.insert(ctx.record.valves, { plan = v, wheel = wheel, wheelLocal = wheelLocal, folder = folder })
end

local function hazard(ctx, h)
	local plan = ctx.plan
	local y = plan.decks[h.deck].y
	local folder = Instance.new("Folder")
	folder.Name = h.kind .. h.id
	folder.Parent = ctx.record.hazardFolder
	ctx.current = folder
	local rec = { plan = h, folder = folder }
	if h.kind == "Steam" then
		ctx:part({ Name = "SteamPipe", Shape = Enum.PartType.Cylinder, Size = V3(10, 1.4, 1.4), CFrame = CFrame.new(h.x, y + 11, h.z) * Parts.ALONG_Z, Color = rgb(150, 90, 60), Material = M.Metal, CanCollide = false })
		local nozzle = ctx:part({ Name = "SteamNozzle", Size = V3(1.2, 1.4, 1.2), CFrame = CFrame.new(h.x, y + 10, h.z), Color = P.SteelDark, Material = M.Metal, CanCollide = false })
		rec.warn = ctx:part({ Name = "SteamWarn", Shape = Enum.PartType.Ball, Size = V3(0.8, 0.8, 0.8), CFrame = CFrame.new(h.x, y + 11.9, h.z), Color = rgb(255, 170, 40), Material = M.Neon, CanCollide = false, CastShadow = false })
		local steam = Instance.new("ParticleEmitter")
		steam.Name = "Steam"
		steam.Color = ColorSequence.new(rgb(240, 240, 240))
		steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 6) })
		steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		steam.Lifetime = NumberRange.new(0.8, 1.4)
		steam.Speed = NumberRange.new(14, 20)
		steam.Rate = 0
		steam.EmissionDirection = Enum.NormalId.Bottom
		steam.Parent = nozzle
		rec.emitter = steam
		rec.nozzle = nozzle
	elseif h.kind == "Chandelier" then
		local top = y + S.DeckHeight - 1
		local cz = h.z
		local model = Instance.new("Model")
		model.Name = "Chandelier"
		model.Parent = folder
		ctx.current = model
		local chainLocal = CFrame.new(0, top - 1, cz)
		ctx:part({ Name = "Chain", Size = V3(0.25, 2, 0.25), CFrame = chainLocal, Color = P.Brass, Material = M.Metal, CanCollide = false })
		local ringLocal = CFrame.new(0, top - 3, cz)
		local ring = ctx:part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = V3(0.5, 5, 5), CFrame = ringLocal * Parts.UP, Color = P.Brass, Material = M.Metal, CanCollide = false })
		local bulb = ctx:part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = V3(1.6, 1.6, 1.6), CFrame = CFrame.new(0, top - 3.6, cz), Color = rgb(255, 226, 170), Material = M.Neon, CanCollide = false, CastShadow = false })
		Parts.light(bulb, rgb(255, 214, 150), 30, 1.6, false)
		for i = 0, 3 do
			local a = i * math.pi / 2
			ctx:part({ Name = "Crystal", Shape = Enum.PartType.Ball, Size = V3(0.7, 0.9, 0.7), CFrame = CFrame.new(math.cos(a) * 2.4, top - 3.9, cz + math.sin(a) * 2.4), Color = rgb(230, 240, 255), Material = M.Glass, Transparency = 0.2, CanCollide = false })
		end
		ctx:part({ Name = "Arms", Size = V3(4.6, 0.25, 0.25), CFrame = CFrame.new(0, top - 3, cz) * CFrame.Angles(0, math.rad(45), 0), Color = P.Brass, Material = M.Metal, CanCollide = false })
		model.PrimaryPart = ring
		ctx.current = folder
		rec.model = model
		rec.ringLocal = ringLocal * Parts.UP
		rec.shadow = ctx:part({ Name = "Shadow", Shape = Enum.PartType.Cylinder, Size = V3(0.1, 8, 8), CFrame = CFrame.new(0, y + 0.08, cz) * Parts.UP, Color = rgb(10, 10, 14), Material = M.SmoothPlastic, Transparency = 1, CanCollide = false, CastShadow = false })
	elseif h.kind == "Wires" then
		ctx:part({ Name = "JunctionBox", Size = V3(1.6, 2, 1), CFrame = CFrame.new(h.x, y + 8, h.z + 1.5), Color = P.SteelDark, Material = M.Metal })
		ctx:beam(V3(h.x, y + 12.5, h.z), V3(h.x + 0.6, y + 0.6, h.z - 0.4), 0.3, 0.3, { Name = "Cable", Color = P.Black, Material = M.SmoothPlastic, CanCollide = false })
		local spark = ctx:part({ Name = "SparkPoint", Shape = Enum.PartType.Ball, Size = V3(0.7, 0.7, 0.7), CFrame = CFrame.new(h.x + 0.6, y + 0.8, h.z - 0.4), Color = rgb(140, 200, 255), Material = M.Neon, CanCollide = false, CastShadow = false })
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Color = ColorSequence.new(rgb(170, 220, 255))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.2)
		sparks.Lifetime = NumberRange.new(0.2, 0.4)
		sparks.Speed = NumberRange.new(8, 14)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 0
		sparks.Parent = spark
		rec.emitter = sparks
		rec.spark = spark
		local warn = ctx:part({ Name = "DangerSign", Size = V3(2, 1.2, 0.2), CFrame = CFrame.new(h.x, y + 9.8, h.z + 1.05), Color = P.Hazard, Material = M.SmoothPlastic, CanCollide = false })
		ShipBuilder.nameplate(warn, "DANGER", P.Black)
	end
	ctx.current = ctx.record.model
	table.insert(ctx.record.hazards, rec)
end

---------------------------------------------------------------------------------------------
-- The last lifeboat (its own Model inside the ship; launched by LifeboatService)
---------------------------------------------------------------------------------------------

local function lifeboat(ctx)
	local plan = ctx.plan
	local lb = plan.lifeboat
	local y = lb.y
	local cz = lb.z
	local model = Instance.new("Model")
	model.Name = "Lifeboat"
	model.Parent = ctx.record.model
	ctx.current = model
	local origin = CFrame.new(0, y + 1.6, cz)
	local root = ctx:part({ Name = "BoatRoot", Size = V3(1, 1, 1), CFrame = origin, Transparency = 1, CanCollide = false, CastShadow = false })
	model.PrimaryPart = root
	local function boat(opts)
		opts.CFrame = origin * opts.CFrame
		return ctx:part(opts)
	end
	boat({ Name = "Keel", Size = V3(5, 0.6, 11), CFrame = CFrame.new(0, -0.6, -0.5), Color = P.Orange, Material = M.SmoothPlastic })
	boat({ Name = "Boards", Size = V3(4.8, 0.2, 10.6), CFrame = CFrame.new(0, -0.2, -0.5), Color = P.Teak, Material = M.WoodPlanks })
	for _, side in ipairs({ -1, 1 }) do
		boat({ Name = "BoatSide", Size = V3(0.5, 2.4, 11.4), CFrame = CFrame.new(side * 2.9, 0.7, -0.6) * CFrame.Angles(0, 0, math.rad(-12 * side)), Color = P.White, Material = M.SmoothPlastic })
		boat({ Name = "Gunwale", Size = V3(0.7, 0.4, 11.6), CFrame = CFrame.new(side * 3.15, 1.95, -0.6), Color = P.Orange, Material = M.SmoothPlastic })
		boat({ Name = "BowPlate", Size = V3(0.5, 2.4, 4.4), CFrame = CFrame.new(side * 1.6, 0.7, 6.6) * CFrame.Angles(0, math.rad(-38 * side), math.rad(-10 * side)), Color = P.White, Material = M.SmoothPlastic })
		boat({ Name = "Oar", Size = V3(0.3, 0.3, 9), CFrame = CFrame.new(side * 1.4, 0.75, -1) * CFrame.Angles(0, math.rad(4 * side), 0), Color = P.WoodLight, Material = M.Wood, CanCollide = false })
		boat({ Name = "BoardingStep", Size = V3(1.6, 0.6, 3), CFrame = CFrame.new(side * 4.2, -1.1, -1), Color = P.Teak, Material = M.WoodPlanks })
	end
	boat({ Name = "BoatStern", Size = V3(5.6, 2.4, 0.5), CFrame = CFrame.new(0, 0.7, -6.3), Color = P.White, Material = M.SmoothPlastic })
	boat({ Name = "Stem", Size = V3(0.6, 2.8, 0.6), CFrame = CFrame.new(0, 0.9, 8.3), Color = P.Orange, Material = M.SmoothPlastic })
	for i, z in ipairs({ -4, -0.5, 3 }) do
		boat({ Name = "Thwart", Size = V3(5.2, 0.35, 1), CFrame = CFrame.new(0, 0.9, z), Color = P.Teak, Material = M.WoodPlanks, CanCollide = i ~= 2 })
	end
	local plate = boat({ Name = "BoatName", Size = V3(4.6, 0.8, 0.2), CFrame = CFrame.new(0, 1.2, -6.62), Transparency = 1, CanCollide = false })
	ShipBuilder.nameplate(plate, "LAST LIFEBOAT", P.Navy)
	-- a tall green beacon so everyone can find the boat
	boat({ Name = "BeaconPole", Size = V3(0.3, 8, 0.3), CFrame = CFrame.new(0, 4.6, 7.6), Color = P.Black, Material = M.Metal, CanCollide = false })
	local beacon = boat({ Name = "Beacon", Shape = Enum.PartType.Ball, Size = V3(1.4, 1.4, 1.4), CFrame = CFrame.new(0, 8.8, 7.6), Color = P.Green, Material = M.Neon, CanCollide = false, CastShadow = false })
	Parts.light(beacon, P.Green, 40, 2, false)
	local seat = GameConfig.Lifeboat.SeatZone
	local zone = boat({ Name = "SeatZone", Size = V3(seat[1], seat[2], seat[3]), CFrame = CFrame.new(0, seat[2] / 2 - 0.5, 0), Transparency = 1, CanCollide = false, CastShadow = false })
	for _, dz in ipairs({ -4.5, 4.5 }) do
		boat({ Name = "Rope", Size = V3(0.2, 9, 0.2), CFrame = CFrame.new(0, 6.5, dz), Color = P.Rope, Material = M.Fabric, CanCollide = false })
	end
	ctx.current = ctx.record.model
	-- cradle and the stern gantry davits (part of the ship)
	for _, dz in ipairs({ -3.5, 3.5 }) do
		ctx:part({ Name = "Cradle", Size = V3(5, 1, 1.2), CFrame = CFrame.new(0, y + 0.5, cz + dz), Color = P.SteelDark, Material = M.Metal })
	end
	for _, dz in ipairs({ -4.5, 4.5 }) do
		for _, side in ipairs({ -1, 1 }) do
			ctx:part({ Name = "GantryPost", Size = V3(0.9, 12, 0.9), CFrame = CFrame.new(side * 5.4, y + 6, cz + dz), Color = P.Steel, Material = M.Metal })
		end
		ctx:part({ Name = "GantryBeam", Size = V3(11.8, 1, 1), CFrame = CFrame.new(0, y + 12.3, cz + dz), Color = P.Steel, Material = M.Metal })
	end
	ctx:part({ Name = "Winch", Shape = Enum.PartType.Cylinder, Size = V3(3, 1.6, 1.6), CFrame = CFrame.new(7.5, y + 1.2, cz + 8), Color = P.Red, Material = M.Metal })
	local sign = ctx:part({ Name = "LaunchSign", Size = V3(6, 1.6, 0.3), CFrame = CFrame.new(0, y + 11, cz + 9.5) * CFrame.Angles(0, math.rad(180), 0), Color = P.Navy, Material = M.SmoothPlastic, CanCollide = false })
	ShipBuilder.nameplate(sign, "LIFEBOAT", P.Brass)
	ctx.record.lifeboat = { model = model, root = root, zone = zone, beacon = beacon, localCF = origin }
end

---------------------------------------------------------------------------------------------
-- Job
---------------------------------------------------------------------------------------------

function ShipBuilder.new(plan, parent, base)
	local model = Instance.new("Model")
	model.Name = "Ship_" .. plan.key
	model:SetAttribute("Ship", plan.key)
	model:SetAttribute("Length", plan.length)
	model:SetAttribute("Beam", plan.beam)
	model:SetAttribute("Height", plan.decks[#plan.decks].y + 20)
	model:SetAttribute("MaxTilt", plan.def.MaxTilt)
	local pivot = Parts.new({ Name = "Pivot", Size = V3(1, 1, 1), CFrame = base, Transparency = 1, CanCollide = false, CastShadow = false, Parent = model })
	model.PrimaryPart = pivot
	model.Parent = parent
	local looseFolder = Instance.new("Folder")
	looseFolder.Name = "LooseProps_" .. plan.key
	looseFolder.Parent = parent
	local record = {
		plan = plan,
		model = model,
		pivot = pivot,
		base = base,
		looseFolder = looseFolder,
		loose = {},
		lamps = {},
		bulkheads = {},
		valves = {},
		hazards = {},
		lifeboat = nil,
	}
	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		return f
	end
	record.obstacleFolder = folder("Obstacles")
	record.hazardFolder = folder("Hazards")
	record.lootFolder = folder("Loot")
	local N = plan.cellCount
	local ctx = setmetatable({ plan = plan, base = base, count = 1, record = record, current = model }, Ctx)
	local rng = Rng.new(plan.seed * 31 + 7)

	local tasks = {}
	local hullFolder = folder("Hull")
	for c = 1, N do
		table.insert(tasks, function()
			ctx.current = hullFolder
			hullCell(ctx, c)
		end)
	end
	table.insert(tasks, function()
		ctx.current = hullFolder
		hullEnds(ctx)
	end)
	for d, deck in ipairs(plan.decks) do
		local deckFolder = folder("Deck" .. d .. "_" .. deck.theme)
		for c = 1, N do
			table.insert(tasks, function()
				ctx.current = deckFolder
				deckCell(ctx, d, c)
			end)
		end
	end
	local connFolder = folder("Connectors")
	for _, conn in ipairs(plan.connectors) do
		table.insert(tasks, function()
			ctx.current = connFolder
			connector(ctx, conn, rng)
		end)
	end
	for _, b in ipairs(plan.bulkheads) do
		table.insert(tasks, function()
			bulkhead(ctx, b)
		end)
	end
	for _, v in ipairs(plan.valves) do
		table.insert(tasks, function()
			valve(ctx, v)
		end)
	end
	for _, h in ipairs(plan.hazards) do
		table.insert(tasks, function()
			hazard(ctx, h)
		end)
	end
	table.insert(tasks, function()
		lifeboat(ctx)
	end)
	local superFolder = folder("Superstructure")
	table.insert(tasks, function()
		ctx.current = superFolder
		superstructure(ctx)
	end)
	for d, deck in ipairs(plan.decks) do
		local decor = DECOR[deck.theme]
		local deckFolder = model:FindFirstChild("Deck" .. d .. "_" .. deck.theme)
		for c = 1, N do
			table.insert(tasks, function()
				ctx.current = deckFolder
				decor(ctx, d, c, rng)
				fill(ctx, d, c, rng)
			end)
		end
	end

	local job = setmetatable({ plan = plan, record = record, tasks = tasks, index = 1, ctx = ctx, done = false, model = model }, ShipBuilder)
	return job
end

-- Builds tasks until about `budget` parts were made this frame. Returns true when done.
function ShipBuilder:step(budget)
	local start = self.ctx.count
	while self.index <= #self.tasks and self.ctx.count - start < budget do
		self.tasks[self.index]()
		self.index += 1
	end
	if self.index > #self.tasks then
		self.done = true
		self.record.parts = self.ctx.count
	end
	return self.done
end

function ShipBuilder:progress()
	return math.clamp((self.index - 1) / #self.tasks, 0, 1)
end

function ShipBuilder.buildAll(plan, parent, base)
	local job = ShipBuilder.new(plan, parent, base)
	repeat
		local done = job:step(100000)
	until done
	return job.record, job
end

-- World CFrame of a ship-local CFrame under the ship's current pivot.
function ShipBuilder.toWorld(record, localCF)
	return record.model:GetPivot() * localCF
end

function ShipBuilder.destroy(record)
	if record.model then
		record.model:Destroy()
	end
	if record.looseFolder then
		record.looseFolder:Destroy()
	end
end

return ShipBuilder
