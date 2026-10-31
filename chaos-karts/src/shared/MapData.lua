--[[
	MapData - compiles a map definition (Maps/*.lua) into everything the game needs:
	  main        the circuit (TrackMath)
	  shortcuts   { id, def, track, startDist / endDist on the main track, gap flags,
	                obstacles (world boxes), puddles }
	  checkpoints ordered gates { index, dist, cframe, halfWidth } (1 = start / finish)
	  grid        12 starting CFrames behind the line
	  pads, kickers, itemSpots, zones (with main-track spans and lanes)
	  wall gaps   main.gapL / gapR and shortcut gap flags where roads meet
	Pure; the result is cached per map id.
]]

local TrackMath = require(script.Parent.TrackMath)
local KartStats = require(script.Parent.Config.KartStats)

local MapData = {}

local cache = {}

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- Distance along `track` of control point i of its definition.
local function controlDist(track, def, i)
	local p = def.points[i]
	local hit = track:project(Vector3.new(p[1], p[2], p[3]))
	return hit.dist
end

local function onRoad(track, pos, margin, flags)
	local hit = track:project(pos, nil, 400)
	if not hit then
		return false
	end
	if flags and flags[hit.index] then
		return false
	end
	return math.abs(hit.lateral) <= hit.w / 2 + hit.sh + (margin or 0) and math.abs(pos.Y - hit.height) < 7
end

-- The highest point of the main road surface under (x, z) near height y.
local function mainHeight(main, x, y, z)
	local hit = main:project(Vector3.new(x, y, z))
	return hit and hit.height or y
end

function MapData.compile(def)
	if cache[def.Id] then
		return cache[def.Id]
	end
	local main = TrackMath.build(def.Track, true)
	local data = { def = def, id = def.Id, main = main, shortcuts = {}, byId = {} }

	-- control point distances
	data.pointDist = {}
	for i = 1, #def.Track.points do
		data.pointDist[i] = controlDist(main, def.Track, i)
	end

	-- shortcuts
	for _, sc in ipairs(def.Shortcuts or {}) do
		local points = {}
		for i, p in ipairs(sc.points) do
			local y = p[2]
			if p.snap then
				y = mainHeight(main, p[1], p[2] + 20, p[3])
			end
			points[i] = { p[1], y, p[3], w = sc.w, sh = sc.sh, wl = sc.wall, wr = sc.wall }
		end
		local track = TrackMath.build({ points = points, step = 4, defaults = { w = sc.w, sh = sc.sh, wl = sc.wall, wr = sc.wall } }, false)
		local entry = {
			id = sc.Id,
			def = sc,
			track = track,
			noSurface = {},
			gapL = {},
			gapR = {},
			obstacles = {},
			puddles = {},
		}
		local pdist = {}
		for i = 1, #points do
			pdist[i] = track:project(Vector3.new(points[i][1], points[i][2], points[i][3])).dist
		end
		entry.pointDist = pdist
		for _, gap in ipairs(sc.gaps or {}) do
			local d0, d1 = pdist[gap.from], pdist[gap.to]
			for _, s in ipairs(track.samples) do
				if s.dist > d0 + 0.5 and s.dist < d1 - 0.5 then
					entry.noSurface[s.index] = true
				end
			end
			entry.gapStart, entry.gapEnd = d0, d1
		end
		for _, o in ipairs(sc.obstacles or {}) do
			local cf = track:frame(o[1] * track.length, o[2], o[5] / 2)
			table.insert(entry.obstacles, { cframe = cf, size = Vector3.new(o[4], o[5], o[3]) })
		end
		for _, o in ipairs(sc.puddles or {}) do
			table.insert(entry.puddles, { dist = o[1] * track.length, lateral = o[2], length = o[3], width = o[4] })
		end
		local first, last = track.samples[1].pos, track.samples[track.n].pos
		entry.startDist = main:project(first).dist
		entry.endDist = main:project(last).dist
		entry.mainSpan = main:delta(entry.startDist, entry.endDist)
		table.insert(data.shortcuts, entry)
		data.byId[sc.Id] = entry
	end

	-- wall gaps where roads meet (main <-> shortcut mouths)
	main.gapL, main.gapR = {}, {}
	for _, s in ipairs(main.samples) do
		for _, side in ipairs({ -1, 1 }) do
			local w = s.pos + s.right * (side * (s.w / 2 + s.sh + 1))
			for _, sc in ipairs(data.shortcuts) do
				if onRoad(sc.track, w, 1.5, sc.noSurface) then
					if side < 0 then
						main.gapL[s.index] = true
					else
						main.gapR[s.index] = true
					end
				end
			end
		end
	end
	for _, sc in ipairs(data.shortcuts) do
		for _, s in ipairs(sc.track.samples) do
			for _, side in ipairs({ -1, 1 }) do
				local w = s.pos + s.right * (side * (s.w / 2 + s.sh + 1))
				if onRoad(main, w, 1.5) then
					if side < 0 then
						sc.gapL[s.index] = true
					else
						sc.gapR[s.index] = true
					end
				end
			end
		end
	end

	-- checkpoints
	data.checkpoints = {}
	for k, pointIndex in ipairs(def.Checkpoints) do
		local d = data.pointDist[pointIndex]
		local cf, s = main:frame(d, 0, 0)
		table.insert(data.checkpoints, { index = k, point = pointIndex, dist = d, cframe = cf, halfWidth = s.w / 2 + s.sh + 6 })
	end
	table.sort(data.checkpoints, function(a, b)
		return a.dist < b.dist
	end)
	for k, cp in ipairs(data.checkpoints) do
		cp.index = k
	end

	-- starting grid (behind the line)
	data.grid = {}
	local g = def.Grid
	for slot = 1, g.slots do
		local row = (slot - 1) // 2
		local col = (slot - 1) % 2
		local d = -(g.firstRow + row * g.rowGap + col * g.stagger)
		local lateral = (if col == 0 then -1 else 1) * g.columnLateral
		data.grid[slot] = main:frame(d % main.length, lateral, KartStats.RideHeight)
	end

	-- boost pads / kickers / item rows (main track)
	local function padList(list, surface)
		local out = {}
		for _, p in ipairs(list or {}) do
			local d = data.pointDist[p[1]] + p[2]
			table.insert(out, { track = "main", dist = d % main.length, lateral = p[3], length = p[4], width = p[5], surface = surface })
		end
		return out
	end
	data.pads = padList(def.BoostPads, "Boost")
	data.kickers = padList(def.Kickers, "Jump")
	data.itemSpots = {}
	for _, row in ipairs(def.ItemRows or {}) do
		local d = (data.pointDist[row[1]] + row[2]) % main.length
		local s = main:at(d)
		local usable = s.w - 12
		for i = 1, row[3] do
			local lateral = -usable / 2 + usable * (i - 0.5) / row[3]
			local p = main:point(d, lateral)
			table.insert(data.itemSpots, { dist = d, lateral = lateral, position = p + Vector3.new(0, 3.5, 0) })
		end
	end

	-- event zones
	data.zones = {}
	data.zoneById = {}
	for _, z in ipairs(def.Zones or {}) do
		local d0, d1 = data.pointDist[z.from], data.pointDist[z.to]
		local span = (d1 - d0) % main.length
		if z.trackWide then
			d0, span = 0, main.length
		end
		local mid = (d0 + span / 2) % main.length
		local s = main:at(mid)
		local tags = {}
		for _, t in ipairs(z.tags) do
			tags[t] = true
		end
		local zone = {
			id = z.Id,
			name = z.Name,
			from = d0,
			to = (d0 + span) % main.length,
			span = span,
			centre = s.pos,
			width = s.w,
			lanes = z.lanes,
			tags = tags,
			tagList = z.tags,
			shortcut = z.shortcut,
			trackWide = z.trackWide == true,
		}
		table.insert(data.zones, zone)
		data.zoneById[z.Id] = zone
	end

	data.floor = def.Floor
	data.floorY = def.FloorY or 0
	data.killY = def.KillY or -50
	data.lobby = { centre = v3(def.Lobby.centre), portal = v3(def.Lobby.portal), portalRadius = def.Lobby.portalRadius }
	cache[def.Id] = data
	return data
end

-- Zone overlap on the main track (spans may wrap around the finish line).
function MapData.spansOverlap(main, a0, aSpan, b0, bSpan)
	if aSpan >= main.length or bSpan >= main.length then
		return true
	end
	local function inside(x, s0, span)
		return (x - s0) % main.length <= span
	end
	return inside(a0, b0, bSpan) or inside(b0, a0, aSpan)
end

return MapData
