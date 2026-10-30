--[[
	ShipGen - plans a ship from its config and a seed. Pure data, no Instances (unit-tested);
	ShipBuilder turns the plan into parts.

	Ship-local frame: origin at the stern on the centreline at the waterline, +Z to the bow,
	+Y up, +X starboard. The hull is CellLength-long cells along Z; every deck is a row of
	those cells. The bow tapers over the last BowCells cells, the stern is slightly rounded.

	A plan holds:
	  decks       { index, theme, y (floor top) }
	  cells       { index, z0, z1, width (narrowest hull width over the cell) }
	  connectors  stairs / ladders / service shafts from deck d to d + 1, in a cell and a
	              lane (+X stairs, -X ladders and shafts). Some are BLOCKED by debris (route
	              choice); bow shafts are DIVE shortcuts (they flood first).
	  bulkheads   a wall across a deck at a cell boundary with a heavy door that needs two
	              levers (on its bow side). The ship stays fully connected with every bulkhead
	              shut, so they are shortcuts, never the only way.
	  valves      one wheel per interior deck
	  hazards     Steam pipes, Chandeliers (drop on a lurch), sparking Wires (flooded rooms)
	  loot        spots { deck, cell, x, z }
	  spawn       deck 1, at the bow
	  lifeboat    top deck, at the stern
	  reserved    per deck/cell rectangles the decorator keeps clear (connectors, levers...)

	The nav graph is one node per (deck, cell): walking along a deck links neighbouring
	cells (unless a shut bulkhead is between them), open connectors link decks.
]]

local GameConfig = require(script.Parent.Config.GameConfig)
local Rng = require(script.Parent.Rng)

local ShipGen = {}

local S = GameConfig.Ship

function ShipGen.node(deck, cell)
	return deck * 1000 + cell
end

-- Full hull width at local z (bow taper is a parabola, the stern is rounded off).
function ShipGen.widthAt(def, z)
	local L, B = def.Length, def.Beam
	local bowStart = L - S.BowCells * S.CellLength
	if z >= bowStart then
		local t = math.clamp((z - bowStart) / (L - bowStart), 0, 1)
		return S.BowTip + (B - S.BowTip) * (1 - t * t)
	elseif z < S.CellLength then
		local t = math.clamp(z / S.CellLength, 0, 1)
		return B * (S.SternRound + (1 - S.SternRound) * math.sqrt(t))
	end
	return B
end

function ShipGen.deckY(index)
	return S.DeckBase + (index - 1) * S.DeckHeight
end

-- Lane X for a connector kind in a cell of width w.
local function laneX(kind, w)
	if kind == "Stair" or kind == "GrandStair" then
		return w / 2 - (if kind == "GrandStair" then 6 else 4.5)
	end
	return -(w / 2 - 3)
end
ShipGen.laneX = laneX

-- Footprint (half sizes) a connector occupies in its cell, in X and Z.
function ShipGen.connectorFootprint(kind)
	if kind == "GrandStair" then
		return 5, 7.5
	elseif kind == "Stair" then
		return 3.5, 7.5
	end
	return 2.5, 2.5
end

local function rect(x, z, hx, hz)
	return { x - hx, x + hx, z - hz, z + hz }
end
ShipGen.rect = rect

function ShipGen.overlaps(a, b)
	return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4]
end

local function reserve(plan, deck, cell, r, tag)
	local key = ShipGen.node(deck, cell)
	plan.reserved[key] = plan.reserved[key] or {}
	r.tag = tag
	table.insert(plan.reserved[key], r)
end

function ShipGen.isFree(plan, deck, cell, r)
	for _, other in ipairs(plan.reserved[ShipGen.node(deck, cell)] or {}) do
		if ShipGen.overlaps(r, other) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Graph
---------------------------------------------------------------------------------------------

-- opts.bulkheadsOpen: treat bulkhead doors as open; opts.noDive: skip dive shafts;
-- opts.deckFilter(deck): only walk these decks.
function ShipGen.neighbours(plan, node, opts)
	opts = opts or {}
	local deck, cell = node // 1000, node % 1000
	local out = {}
	local function walkable(c)
		return c >= 1 and c <= plan.cellCount
	end
	for _, dc in ipairs({ -1, 1 }) do
		local c = cell + dc
		if walkable(c) then
			local boundary = math.min(cell, c)
			local shut = plan.bulkheadAt[ShipGen.node(deck, boundary)]
			if not shut or opts.bulkheadsOpen then
				table.insert(out, ShipGen.node(deck, c))
			end
		end
	end
	for _, conn in ipairs(plan.connectors) do
		if not conn.blocked and conn.cell == cell and not (opts.noDive and conn.dive) then
			if conn.from == deck then
				table.insert(out, ShipGen.node(conn.to, cell))
			elseif conn.to == deck then
				table.insert(out, ShipGen.node(conn.from, cell))
			end
		end
	end
	return out
end

function ShipGen.reachable(plan, opts, from)
	local start = from or ShipGen.node(plan.spawn.deck, plan.spawn.cell)
	local seen = { [start] = 0 }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local node = queue[head]
		head += 1
		for _, n in ipairs(ShipGen.neighbours(plan, node, opts)) do
			if seen[n] == nil then
				seen[n] = seen[node] + 1
				table.insert(queue, n)
			end
		end
	end
	return seen
end

function ShipGen.allConnected(plan, opts)
	local seen = ShipGen.reachable(plan, opts)
	for d = 1, #plan.decks do
		for c = 1, plan.cellCount do
			if seen[ShipGen.node(d, c)] == nil then
				return false, d, c
			end
		end
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------------------------

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local function connectorCandidates(plan, d, lo, hi)
	local out = {}
	for c = math.max(2, lo), math.min(plan.cellCount - 1, hi) do
		if not plan.cellUsed[ShipGen.node(d, c)] and not plan.cellUsed[ShipGen.node(d + 1, c)] then
			table.insert(out, c)
		end
	end
	return out
end

local function addConnector(plan, kind, d, cell, extra)
	local w = plan.cells[cell].width
	local hx, hz = ShipGen.connectorFootprint(kind)
	local conn = {
		id = #plan.connectors + 1,
		kind = kind,
		from = d,
		to = d + 1,
		cell = cell,
		x = laneX(kind, w),
		z = (plan.cells[cell].z0 + plan.cells[cell].z1) / 2,
		blocked = false,
		dive = false,
	}
	for k, v in pairs(extra or {}) do
		conn[k] = v
	end
	table.insert(plan.connectors, conn)
	plan.cellUsed[ShipGen.node(d, cell)] = true
	plan.cellUsed[ShipGen.node(d + 1, cell)] = true
	-- the stair body on deck d, the hole in deck d + 1 (plus a landing in front of it)
	reserve(plan, d, cell, rect(conn.x, conn.z, hx + 1, hz + 1), "connector")
	reserve(plan, d + 1, cell, rect(conn.x, conn.z, hx + 1, hz + 1), "hole")
	return conn
end

-- Picks a free point in a cell's side bands (|x| > WalkwayHalf), avoiding reserved rects.
local function freeSpot(plan, rng, d, cell, hx, hz, side)
	local c = plan.cells[cell]
	local half = c.width / 2 - 1.5
	for _ = 1, 24 do
		local s = side or (if rng:NextNumber() < 0.5 then -1 else 1)
		local lo = S.WalkwayHalf + hx + 0.5
		local hi = half - hx
		if hi > lo then
			local x = s * rng:NextNumber(lo, hi)
			local z = rng:NextNumber(c.z0 + hz + 1, c.z1 - hz - 1)
			local r = rect(x, z, hx, hz)
			if ShipGen.isFree(plan, d, cell, r) then
				return x, z, r
			end
		end
	end
	return nil
end
ShipGen.freeSpot = freeSpot

function ShipGen.plan(shipKey, seed)
	local def = GameConfig.Ships[shipKey]
	assert(def, "unknown ship " .. tostring(shipKey))
	local rng = Rng.new(seed or 1)
	local cellCount = math.floor(def.Length / S.CellLength + 0.5)
	assert(cellCount * S.CellLength == def.Length, "ship length must be a whole number of cells")
	local plan = {
		key = shipKey,
		def = def,
		seed = seed or 1,
		length = def.Length,
		beam = def.Beam,
		cellCount = cellCount,
		decks = {},
		cells = {},
		connectors = {},
		bulkheads = {},
		bulkheadAt = {},
		valves = {},
		hazards = {},
		loot = {},
		reserved = {},
		cellUsed = {},
	}
	for c = 1, cellCount do
		local z0, z1 = (c - 1) * S.CellLength, c * S.CellLength
		local w = math.min(ShipGen.widthAt(def, z0), ShipGen.widthAt(def, z1), ShipGen.widthAt(def, (z0 + z1) / 2))
		plan.cells[c] = { index = c, z0 = z0, z1 = z1, width = w, wFront = ShipGen.widthAt(def, z1), wBack = ShipGen.widthAt(def, z0) }
	end
	local n = #def.Decks
	for i, theme in ipairs(def.Decks) do
		plan.decks[i] = { index = i, theme = theme, y = ShipGen.deckY(i), top = i == n }
	end
	plan.topDeck = n
	local N = cellCount

	-- Spawn: the lowest deck, at the bow (the first tapered cell is still roomy).
	plan.spawn = { deck = 1, cell = N - S.BowCells + 1 }
	local sc = plan.cells[plan.spawn.cell]
	plan.spawn.x, plan.spawn.z = 0, (sc.z0 + sc.z1) / 2
	reserve(plan, 1, plan.spawn.cell, rect(0, plan.spawn.z, 6, 6), "spawn")

	-- Lifeboat: top deck, stern (cell 1), on the centreline.
	plan.lifeboat = { deck = n, cell = 1, x = 0, z = 9, y = ShipGen.deckY(n) }
	reserve(plan, n, 1, rect(0, 9, 9, 9), "lifeboat")
	reserve(plan, n, 2, rect(0, 17, 9, 2), "lifeboat")

	-- The deckhouse on the top deck (bridge and funnels on its roof). Players walk the side
	-- passages around it, so it is reserved before anything else is placed up there.
	local half = def.Beam / 2 - 9
	plan.deckhouse = { z0 = math.floor(N * 0.32) * S.CellLength, z1 = math.floor(N * 0.66) * S.CellLength, halfWidth = half }
	for c = 1, N do
		local cell = plan.cells[c]
		if cell.z1 > plan.deckhouse.z0 and cell.z0 < plan.deckhouse.z1 then
			reserve(plan, n, c, { -half - 0.5, half + 0.5, math.max(cell.z0, plan.deckhouse.z0), math.min(cell.z1, plan.deckhouse.z1) }, "deckhouse")
		end
	end
	-- the helm station in front of it
	local helmCell = math.min(N, math.floor((plan.deckhouse.z1 + 6) / S.CellLength) + 1)
	reserve(plan, n, helmCell, rect(0, plan.deckhouse.z1 + 6, 5, 2.5), "helm")

	-- Connectors, boundary by boundary.
	for d = 1, n - 1 do
		local primaryKind = if def.Decks[d] == "DiningHall" then "GrandStair" else "Stair"
		local lo, hi
		if d == n - 1 then
			lo, hi = 3, math.floor(N * 0.4)
		elseif d % 2 == 1 then
			lo, hi = 2, math.floor(N * 0.45)
		else
			lo, hi = math.floor(N * 0.4), math.floor(N * 0.65)
		end
		local list = connectorCandidates(plan, d, lo, hi)
		if #list == 0 then
			list = connectorCandidates(plan, d, 2, N - 1)
		end
		local primary = addConnector(plan, primaryKind, d, pick(rng, list))
		local others = {}
		for minGap = 3, 1, -1 do
			for _, c in ipairs(connectorCandidates(plan, d, 2, N - 1)) do
				if math.abs(c - primary.cell) >= minGap then
					table.insert(others, c)
				end
			end
			if #others > 0 then
				break
			end
		end
		local ladder = nil
		if #others > 0 then
			ladder = addConnector(plan, "Ladder", d, pick(rng, others))
		end
		-- The flooded service shaft: a bow shortcut between the lower decks.
		if d < n - 1 then
			local bow = connectorCandidates(plan, d, N - S.BowCells, N - 1)
			if #bow > 0 then
				addConnector(plan, "Shaft", d, pick(rng, bow), { dive = true })
			end
		end
		-- Route choice: sometimes debris blocks one of the two dry routes.
		if ladder and rng:NextNumber() < 0.55 then
			local victim = if rng:NextNumber() < 0.5 then primary else ladder
			victim.blocked = true
		end
	end

	-- Bulkheads (shortcuts only: the ship must stay connected with them all shut).
	for d = 1, n - 1 do
		if N >= 10 and rng:NextNumber() < 0.75 then
			-- Between two open dry connectors that touch this deck, so each side has a way out.
			local touch = {}
			for _, conn in ipairs(plan.connectors) do
				if not conn.blocked and not conn.dive and (conn.from == d or conn.to == d) then
					table.insert(touch, conn.cell)
				end
			end
			table.sort(touch)
			local options = {}
			if #touch >= 2 then
				for b = math.max(3, touch[1]), math.min(N - S.BowCells - 1, touch[#touch] - 1) do
					if not plan.cellUsed[ShipGen.node(d, b)] and not plan.cellUsed[ShipGen.node(d, b + 1)] then
						table.insert(options, b)
					end
				end
			end
			if #options > 0 then
				local b = pick(rng, options)
				local key = ShipGen.node(d, b)
				plan.bulkheadAt[key] = true
				if ShipGen.allConnected(plan, { noDive = true }) then
					local bowCell = plan.cells[b + 1]
					local wz = bowCell.z0
					local lx = bowCell.width / 2 - 3.5
					local bulkhead = {
						id = #plan.bulkheads + 1,
						deck = d,
						boundary = b,
						z = wz,
						width = math.min(plan.cells[b].width, bowCell.width),
						levers = { { x = -lx, z = wz + 3 }, { x = lx, z = wz + 3 } },
					}
					table.insert(plan.bulkheads, bulkhead)
					reserve(plan, d, b + 1, rect(-lx, wz + 3, 2, 2.5), "lever")
					reserve(plan, d, b + 1, rect(lx, wz + 3, 2, 2.5), "lever")
					reserve(plan, d, b + 1, rect(0, wz + 1, bulkhead.width / 2, 1.5), "bulkhead")
					reserve(plan, d, b, rect(0, wz - 1, bulkhead.width / 2, 1.5), "bulkhead")
					plan.cellUsed[ShipGen.node(d, b)] = true
					plan.cellUsed[ShipGen.node(d, b + 1)] = true
				else
					plan.bulkheadAt[key] = nil
				end
			end
		end
	end

	-- Valve wheels: one per interior deck, against the hull.
	for d = 1, n - 1 do
		for _ = 1, 30 do
			local cell = rng:NextInteger(2, N - 2)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local c = plan.cells[cell]
			local x = side * (c.width / 2 - 2)
			local z = (c.z0 + c.z1) / 2 + rng:NextNumber(-4, 4)
			local r = rect(x, z, 2, 2)
			if ShipGen.isFree(plan, d, cell, r) then
				reserve(plan, d, cell, r, "valve")
				table.insert(plan.valves, { id = #plan.valves + 1, deck = d, cell = cell, x = x, z = z, side = side })
				break
			end
		end
	end

	-- Hazards.
	local function addHazard(kind, d, cell, x, z, extra)
		local h = { id = #plan.hazards + 1, kind = kind, deck = d, cell = cell, x = x, z = z, phase = rng:NextNumber(0, 1) }
		for k, v in pairs(extra or {}) do
			h[k] = v
		end
		table.insert(plan.hazards, h)
		return h
	end
	for d = 1, n - 1 do
		local theme = def.Decks[d]
		local steam = if theme == "EngineRoom" then 2 elseif theme == "CrewQuarters" or theme == "CargoHold" then 1 else 0
		for _ = 1, steam do
			for _ = 1, 20 do
				local cell = rng:NextInteger(2, N - 2)
				local x = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0, S.WalkwayHalf)
				local c = plan.cells[cell]
				local z = (c.z0 + c.z1) / 2
				local r = rect(x, z, 3, 3)
				if ShipGen.isFree(plan, d, cell, r) then
					reserve(plan, d, cell, r, "steam")
					addHazard("Steam", d, cell, x, z)
					break
				end
			end
		end
		if theme == "DiningHall" then
			for cell = 2, N - S.BowCells, 2 do
				local c = plan.cells[cell]
				addHazard("Chandelier", d, cell, 0, (c.z0 + c.z1) / 2, { drops = true })
			end
		end
		if theme == "EngineRoom" or theme == "CargoHold" or theme == "CrewQuarters" then
			for _ = 1, 20 do
				local cell = rng:NextInteger(math.floor(N * 0.45), N - 1)
				local x, z, r = freeSpot(plan, rng, d, cell, 1.5, 1.5)
				if x then
					reserve(plan, d, cell, r, "wires")
					addHazard("Wires", d, cell, x, z)
					break
				end
			end
		end
	end

	-- Loot spots: more on the lower (riskier) decks, fewer up top.
	for d = 1, n do
		local count = def.LootPerDeck + (if d <= math.ceil(n / 2) then 1 else 0) - (if d == n then 3 else 0)
		local placed, tries = 0, 0
		while placed < count and tries < 200 do
			tries += 1
			local cell = rng:NextInteger(1, N)
			local x, z, r = freeSpot(plan, rng, d, cell, 1.2, 1.2)
			if x then
				reserve(plan, d, cell, r, "loot")
				table.insert(plan.loot, { id = #plan.loot + 1, deck = d, cell = cell, x = x, z = z })
				placed += 1
			end
		end
	end

	plan.partEstimate = ShipGen.estimateParts(plan)
	return plan
end

---------------------------------------------------------------------------------------------
-- Part estimate (calibrated against ShipBuilder; the harness checks the real count too)
---------------------------------------------------------------------------------------------

ShipGen.PartsPerCell = {
	EngineRoom = 24,
	CargoHold = 22,
	CrewQuarters = 23,
	Cabins = 23,
	DiningHall = 23,
	Promenade = 16,
	TopDeck = 7,
}
ShipGen.PartsPer = {
	HullCell = 9, -- keel, hull plates, boot stripe, white band, deck edge...
	DeckCellBase = 5, -- floor, lining, a share of lamps and portholes
	Stair = 22,
	GrandStair = 30,
	Ladder = 6,
	Shaft = 8,
	Bulkhead = 14,
	Valve = 6,
	Steam = 5,
	Chandelier = 10,
	Wires = 4,
	Loot = 4,
	Funnel = 6,
	Superstructure = 120,
	Lifeboat = 40,
}

function ShipGen.estimateParts(plan)
	local P = ShipGen.PartsPer
	local total = plan.cellCount * P.HullCell + P.Superstructure + P.Lifeboat + plan.def.Funnels * P.Funnel
	for _, deck in ipairs(plan.decks) do
		total += plan.cellCount * (P.DeckCellBase + (ShipGen.PartsPerCell[deck.theme] or 8))
	end
	for _, conn in ipairs(plan.connectors) do
		total += P[conn.kind] or 8
	end
	total += #plan.bulkheads * P.Bulkhead + #plan.valves * P.Valve + #plan.loot * P.Loot
	for _, h in ipairs(plan.hazards) do
		total += P[h.kind] or 4
	end
	return total
end

-- Ship-local position of a deck point (feet height).
function ShipGen.localPoint(plan, deck, x, z, up)
	return x, plan.decks[deck].y + (up or 0), z
end

return ShipGen
