--[[
	MazeGen - pure layout generation for the facility (no Roblox APIs).

	Produces a grid graph of cells:
	  1. A spanning tree grown from the start room (guarantees every cell is reachable).
	  2. Special rooms (exit, power room, security) placed on dead ends of the tree so each
	     has exactly one entrance - they can be locked without disconnecting anything.
	  3. Extra loop connections between ordinary cells so chases can be escaped.
	  4. Room kinds, floors, lighting, lockers and anomalies assigned per cell.

	Everything is drawn from the supplied Rng, so a seed reproduces a layout exactly.
]]

local MazeGen = {}

local DIRECTIONS = {
	{ dx = 1, dy = 0, name = "E" },
	{ dx = -1, dy = 0, name = "W" },
	{ dx = 0, dy = 1, name = "S" },
	{ dx = 0, dy = -1, name = "N" },
}

local QUADRANTS = { "NE", "NW", "SE", "SW" }
MazeGen.Quadrants = QUADRANTS

local function cellIndex(width, x, y)
	return y * width + x + 1
end

function MazeGen.edgeKey(a, b)
	if a > b then
		a, b = b, a
	end
	return a .. ":" .. b
end

local function neighbors(layout, cell)
	local result = {}
	for _, dir in ipairs(DIRECTIONS) do
		local nx, ny = cell.x + dir.dx, cell.y + dir.dy
		if nx >= 0 and ny >= 0 and nx < layout.width and ny < layout.height then
			table.insert(result, { cell = layout.cells[cellIndex(layout.width, nx, ny)], dir = dir.name })
		end
	end
	return result
end
MazeGen.neighbors = neighbors

local function link(layout, a, b)
	a.links[b.index] = true
	b.links[a.index] = true
	local key = MazeGen.edgeKey(a.index, b.index)
	local edge = { key = key, a = math.min(a.index, b.index), b = math.max(a.index, b.index), kind = "Open" }
	layout.edges[key] = edge
	return edge
end

local function degree(cell)
	local n = 0
	for _ in pairs(cell.links) do
		n += 1
	end
	return n
end
MazeGen.degree = degree

-- Breadth-first distances (in steps) from `fromIndex` over the current links.
function MazeGen.distances(layout, fromIndex)
	local dist = { [fromIndex] = 0 }
	local queue = { fromIndex }
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		for other in pairs(layout.cells[current].links) do
			if dist[other] == nil then
				dist[other] = dist[current] + 1
				table.insert(queue, other)
			end
		end
	end
	return dist
end

local function sortedLinks(cell)
	local list = {}
	for other in pairs(cell.links) do
		table.insert(list, other)
	end
	table.sort(list)
	return list
end
MazeGen.sortedLinks = sortedLinks

local function manhattan(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

local function pickFloor(config, kind, rng)
	local floor = config.FloorByKind[kind] or "Concrete"
	if type(floor) == "table" then
		return rng:pick(floor)
	end
	return floor
end

local function tryGenerate(config, rng)
	local width, height = config.GridWidth, config.GridHeight
	local layout = {
		width = width,
		height = height,
		cells = {},
		edges = {},
		specials = {},
		lockers = {},
	}

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local index = cellIndex(width, x, y)
			layout.cells[index] = {
				index = index,
				x = x,
				y = y,
				links = {},
				kind = "Unassigned",
				quadrants = {},
			}
		end
	end

	local startX = math.clamp(config.StartX or math.floor(width / 2), 0, width - 1)
	local startY = math.clamp(config.StartY or 0, 0, height - 1)
	local start = layout.cells[cellIndex(width, startX, startY)]
	layout.start = start.index

	-- 1. Growing-tree spanning tree.
	local visited = { [start.index] = true }
	local active = { start }
	while #active > 0 do
		local i = if rng:chance(config.BranchBias) then rng:integer(1, #active) else #active
		local cell = active[i]
		local options = {}
		for _, n in ipairs(neighbors(layout, cell)) do
			if not visited[n.cell.index] then
				table.insert(options, n.cell)
			end
		end
		if #options == 0 then
			table.remove(active, i)
		else
			local nextCell = rng:pick(options)
			link(layout, cell, nextCell)
			visited[nextCell.index] = true
			table.insert(active, nextCell)
		end
	end

	-- 2. Special rooms on dead ends.
	local treeDist = MazeGen.distances(layout, start.index)
	local maxDist = 0
	for _, d in pairs(treeDist) do
		maxDist = math.max(maxDist, d)
	end

	local leaves = {}
	for index = 1, width * height do
		local cell = layout.cells[index]
		if index ~= start.index and degree(cell) == 1 and treeDist[index] >= config.MinSpecialDistance then
			table.insert(leaves, cell)
		end
	end
	if #leaves < #config.SpecialRooms then
		return nil
	end

	local chosen = {}
	for order, roomName in ipairs(config.SpecialRooms) do
		local best, bestScore = nil, -math.huge
		for _, leaf in ipairs(leaves) do
			if not leaf.special then
				local score
				if order == 1 then
					-- The exit is the deepest dead end.
					score = treeDist[leaf.index] * 10 + rng:next()
				else
					-- Others spread away from start and from previously placed specials.
					local spread = math.huge
					for _, other in ipairs(chosen) do
						spread = math.min(spread, manhattan(leaf, other))
					end
					score = math.min(spread, 6) * 4 + math.min(treeDist[leaf.index], maxDist * 0.7) + rng:next() * 2
				end
				if score > bestScore then
					best, bestScore = leaf, score
				end
			end
		end
		if not best then
			return nil
		end
		best.special = roomName
		best.kind = roomName
		layout.specials[roomName] = best.index
		table.insert(chosen, best)
		local entrance = sortedLinks(best)[1]
		local edge = layout.edges[MazeGen.edgeKey(best.index, entrance)]
		edge.kind = "Door"
		edge.heavy = true
		edge.special = roomName
		best.entrance = entrance
	end

	-- 3. Loops between ordinary cells.
	for index = 1, width * height do
		local cell = layout.cells[index]
		for _, n in ipairs(neighbors(layout, cell)) do
			local other = n.cell
			if other.index > cell.index and not cell.links[other.index] and not cell.special and not other.special then
				if rng:chance(config.LoopChance) then
					link(layout, cell, other)
				end
			end
		end
	end

	-- 4. Edge kinds for ordinary connections.
	local edgeKeys = {}
	for key in pairs(layout.edges) do
		table.insert(edgeKeys, key)
	end
	table.sort(edgeKeys)
	for _, key in ipairs(edgeKeys) do
		local edge = layout.edges[key]
		if not edge.special then
			-- The safe room always has doors; other connections are doors by chance.
			if edge.a == start.index or edge.b == start.index or rng:chance(config.DoorChance) then
				edge.kind = "Door"
			else
				edge.kind = "Open"
			end
		end
	end
	layout.edgeKeys = edgeKeys

	-- 5. Room kinds.
	start.kind = "Start"
	local finalDist = MazeGen.distances(layout, start.index)
	layout.distanceFromStart = finalDist
	local ordinary = {}
	for index = 1, width * height do
		local cell = layout.cells[index]
		cell.distance = finalDist[index]
		if cell.kind == "Unassigned" then
			cell.kind = rng:weighted(config.RoomWeights)
			table.insert(ordinary, cell)
		end
	end

	-- Anomalies and struggle rooms (ordinary cells away from start).
	local candidates = {}
	for _, cell in ipairs(ordinary) do
		if cell.distance >= 3 then
			table.insert(candidates, cell)
		end
	end
	rng:shuffle(candidates)
	local used = 0
	for _, cell in ipairs(candidates) do
		if used >= config.AnomalyCount then
			break
		end
		cell.kind = "Anomaly"
		cell.variant = rng:pick(config.AnomalyVariants)
		used += 1
	end
	local struggle = 0
	for _, cell in ipairs(candidates) do
		if struggle >= config.StruggleCount then
			break
		end
		if cell.kind ~= "Anomaly" then
			cell.struggle = true
			struggle += 1
		end
	end

	-- Floors, lighting.
	for index = 1, width * height do
		local cell = layout.cells[index]
		cell.floor = pickFloor(config, cell.kind, rng)
		if cell.kind == "Start" then
			cell.lit = true
			cell.flicker = false
		else
			cell.lit = rng:chance(config.LitChanceBeforePower)
			cell.flicker = cell.lit and rng:chance(config.FlickerChance)
		end
		local acousticKey = if cell.variant == "TallRoom" then "TallRoom" else cell.kind
		cell.acoustics = config.Acoustics[acousticKey] or 1
	end

	-- 6. Quadrant contents: lockers first, then props.
	local lockerCells = {}
	for _, cell in ipairs(ordinary) do
		if config.LockerKinds[cell.kind] then
			table.insert(lockerCells, cell)
		end
	end
	rng:shuffle(lockerCells)
	local lockersPlaced = 0
	-- Objective rooms are loud places: always leave a hiding spot right outside each one.
	for _, roomName in ipairs(config.SpecialRooms) do
		local entrance = layout.cells[layout.cells[layout.specials[roomName]].entrance]
		if entrance.kind ~= "Start" then
			local free = {}
			for _, q in ipairs(QUADRANTS) do
				if entrance.quadrants[q] == nil then
					table.insert(free, q)
				end
			end
			local q = rng:pick(free)
			if q then
				entrance.quadrants[q] = "Locker"
				lockersPlaced += 1
				table.insert(layout.lockers, { cell = entrance.index, quadrant = q, nearObjective = roomName })
			end
		end
	end
	local pass = 0
	while lockersPlaced < config.LockerCount and pass < config.MaxLockersPerCell and #lockerCells > 0 do
		pass += 1
		for _, cell in ipairs(lockerCells) do
			if lockersPlaced >= config.LockerCount then
				break
			end
			local free = {}
			for _, q in ipairs(QUADRANTS) do
				if cell.quadrants[q] == nil then
					table.insert(free, q)
				end
			end
			local q = rng:pick(free)
			if q then
				cell.quadrants[q] = "Locker"
				lockersPlaced += 1
				table.insert(layout.lockers, { cell = cell.index, quadrant = q })
			end
		end
	end

	for index = 1, width * height do
		local cell = layout.cells[index]
		for _, q in ipairs(QUADRANTS) do
			if cell.quadrants[q] == nil then
				if cell.kind == "Start" or cell.special then
					cell.quadrants[q] = "Reserved"
				elseif rng:chance(config.PropChance) then
					cell.quadrants[q] = "Prop"
				else
					cell.quadrants[q] = "Empty"
				end
			end
		end
	end

	-- 7. Monster spawn: the farthest ordinary cell from the start.
	local farthest, farDist = nil, -1
	for _, cell in ipairs(ordinary) do
		if cell.distance > farDist then
			farthest, farDist = cell, cell.distance
		end
	end
	layout.monsterSpawn = farthest.index

	return layout
end

function MazeGen.generate(config, rng)
	for attempt = 1, 50 do
		local layout = tryGenerate(config, rng)
		if layout then
			layout.attempts = attempt
			local ok, reason = MazeGen.validate(layout, config)
			if ok then
				return layout
			end
			warn("[DeadAir] MazeGen discarded a layout: " .. tostring(reason))
		end
	end
	error("MazeGen: unable to produce a valid layout")
end

-- Picks `count` ordinary cells for item placement, preferring deeper cells and spreading
-- picks out. `exclude` is an optional set of cell indices already used.
function MazeGen.pickItemCells(layout, rng, count, exclude, minDistance)
	exclude = exclude or {}
	minDistance = minDistance or 2
	local pool = {}
	for index, cell in ipairs(layout.cells) do
		if not cell.special and cell.kind ~= "Start" and (cell.distance or 0) >= minDistance and not exclude[index] then
			table.insert(pool, cell)
		end
	end
	local picks = {}
	for _ = 1, count do
		if #pool == 0 then
			break
		end
		local best, bestScore, bestIndex = nil, -math.huge, nil
		for i, cell in ipairs(pool) do
			local spread = 6
			for _, p in ipairs(picks) do
				spread = math.min(spread, manhattan(cell, p))
			end
			local score = spread * 1.6 + (cell.distance or 0) * 0.35 + rng:next() * 3
			if score > bestScore then
				best, bestScore, bestIndex = cell, score, i
			end
		end
		table.insert(picks, best)
		table.remove(pool, bestIndex)
	end
	return picks
end

-- Structural checks used by generation and by the test suite.
function MazeGen.validate(layout, config)
	local total = layout.width * layout.height
	local dist = MazeGen.distances(layout, layout.start)
	for index = 1, total do
		if dist[index] == nil then
			return false, "cell " .. index .. " unreachable"
		end
	end
	for _, roomName in ipairs(config.SpecialRooms) do
		local index = layout.specials[roomName]
		if not index then
			return false, "missing special " .. roomName
		end
		local cell = layout.cells[index]
		if degree(cell) ~= 1 then
			return false, roomName .. " must have exactly one entrance"
		end
		if dist[index] < config.MinSpecialDistance then
			return false, roomName .. " too close to start"
		end
		local entranceCell = layout.cells[cell.entrance]
		if entranceCell.special then
			return false, roomName .. " entrance leads into another special room"
		end
	end
	-- Removing all special rooms must leave the rest connected (locks never cut off items).
	local seen = { [layout.start] = true }
	local queue = { layout.start }
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		for other in pairs(layout.cells[current].links) do
			if not seen[other] and not layout.cells[other].special then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	for index = 1, total do
		if not layout.cells[index].special and not seen[index] then
			return false, "ordinary cell " .. index .. " only reachable through a special room"
		end
	end
	return true
end

return MazeGen
