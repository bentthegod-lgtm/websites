--[[
	TrackQuery - the ANALYTIC ground query, built from the compiled map data (MapData).
	It implements the same interface as the in-game raycast query (client/WorldQuery):

	  q:ground(probe) -> height, normal, surface, course | nil
	     The highest surface at or below `probe` (within KartStats.MaxProbe):
	     the main road and its shoulders, shortcut roads (except their gaps), the grass
	     floor (with holes for the river, the tunnel trench and the Rooftop Leap pit).
	     surface: "Road", "Offroad", "Boost", "Jump".  course: "main", shortcut id, "floor".
	  q:walls(pos, radius) -> pushNormal (horizontal unit Vector3) | nil, depth
	     Track walls (low inside, tall outside; gaps where roads meet), shortcut walls and
	     obstacles (alley dumpsters).

	Used by the server bots, the server's checks, the harness and the unit tests. The
	TrackBuilder builds the real parts from the same data, so the two agree.
]]

local KartStats = require(script.Parent.Config.KartStats)

local TrackQuery = {}
TrackQuery.__index = TrackQuery

local Y = Vector3.new(0, 1, 0)

function TrackQuery.new(data)
	local self = setmetatable({ data = data, main = data.main }, TrackQuery)
	self.courses = { { id = "main", track = data.main, noSurface = {}, gapL = data.main.gapL or {}, gapR = data.main.gapR or {}, solid = false } }
	for _, sc in ipairs(data.shortcuts) do
		table.insert(self.courses, { id = sc.id, track = sc.track, noSurface = sc.noSurface, gapL = sc.gapL, gapR = sc.gapR, entry = sc, solid = true })
	end
	return self
end

local function padHit(pad, track, hit)
	local d = hit.dist - pad.dist
	if track.closed ~= false then
		d = (d + track.length / 2) % track.length - track.length / 2
	end
	return math.abs(d) <= pad.length / 2 and math.abs(hit.lateral - pad.lateral) <= pad.width / 2
end

function TrackQuery:surfaceAt(course, hit)
	local half = hit.w / 2
	if math.abs(hit.lateral) > half then
		return "Offroad"
	end
	if course.id == "main" then
		for _, pad in ipairs(self.data.kickers) do
			if padHit(pad, course.track, hit) then
				return "Jump"
			end
		end
		for _, pad in ipairs(self.data.pads) do
			if padHit(pad, course.track, hit) then
				return "Boost"
			end
		end
	elseif course.entry then
		for _, p in ipairs(course.entry.puddles) do
			if math.abs(hit.dist - p.dist) <= p.length / 2 and math.abs(hit.lateral - p.lateral) <= p.width / 2 then
				return "Offroad"
			end
		end
	end
	return "Road"
end

function TrackQuery:ground(probe)
	local bestH, bestCourse, bestI = nil, nil, nil
	local px, py, pz = probe.X, probe.Y, probe.Z
	local floorLimit = py - KartStats.MaxProbe
	for _, course in ipairs(self.courses) do
		local track = course.track
		local open = track.closed == false
		local lastSeg = track.n - 1
		for _, i in ipairs(track:candidates(px, pz)) do
			if not course.noSurface[i] then
				local t, lateral, _, height, g, inside = track:locate(i, px, pz)
				local ok = inside and math.abs(lateral) <= g.w / 2 + g.sh
				-- an open spline's end segments do not extend past its ends
				if ok and open and ((i == 1 and t <= 0) or (i == lastSeg and t >= 1)) then
					ok = false
				end
				if ok and height <= py + 1e-6 and height >= floorLimit and (bestH == nil or height > bestH + 1e-6) then
					bestH, bestCourse, bestI = height, course, i
				end
			end
		end
	end
	local fy = self.data.floorY
	-- the floor only counts where no road is (a road a hair below the grass is still road)
	if (bestH == nil or bestH < fy - 2) and fy <= py and fy >= floorLimit then
		for _, r in ipairs(self.data.floor) do
			if px >= r[1] and px <= r[3] and pz >= r[2] and pz <= r[4] then
				return fy, Y, "Offroad", "floor"
			end
		end
	end
	if not bestH then
		return nil
	end
	local g = bestCourse.track.segs[bestI]
	local surface = "Road"
	local _, lateral = bestCourse.track:locate(bestI, px, pz)
	if math.abs(lateral) > g.w / 2 then
		surface = "Offroad"
	elseif bestCourse.id == "main" or bestCourse.entry then
		local t = bestCourse.track:locate(bestI, px, pz)
		surface = self:surfaceAt(bestCourse, { dist = g.dist + t * g.span, lateral = lateral, w = g.w })
	end
	return bestH, g.normal, surface, bestCourse.id
end

-- Is this position on a road or shoulder (any course)? Used for off-course checks.
function TrackQuery:onCourse(pos)
	local h, _, _, course = self:ground(pos + Vector3.new(0, KartStats.StepUp, 0))
	return h ~= nil and course ~= "floor", course
end

local function obstaclePush(o, pos, radius)
	local rel = o.cframe:PointToObjectSpace(pos)
	local hx, hz = o.size.X / 2, o.size.Z / 2
	if math.abs(rel.Y) > o.size.Y / 2 + 2 then
		return nil
	end
	local cx = math.clamp(rel.X, -hx, hx)
	local cz = math.clamp(rel.Z, -hz, hz)
	local dx, dz = rel.X - cx, rel.Z - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if d >= radius then
		return nil
	end
	local localNormal
	local depth
	if d > 1e-4 then
		localNormal = Vector3.new(dx / d, 0, dz / d)
		depth = radius - d
	else
		-- centre inside the box: push out along the shallowest axis
		local px, pz = hx - math.abs(rel.X), hz - math.abs(rel.Z)
		if px < pz then
			localNormal = Vector3.new(if rel.X >= 0 then 1 else -1, 0, 0)
			depth = px + radius
		else
			localNormal = Vector3.new(0, 0, if rel.Z >= 0 then 1 else -1)
			depth = pz + radius
		end
	end
	local n = o.cframe:VectorToWorldSpace(localNormal)
	n = Vector3.new(n.X, 0, n.Z).Unit
	return n, depth
end

function TrackQuery:walls(pos, radius)
	local bestN, bestD = nil, 0
	local px, py, pz = pos.X, pos.Y, pos.Z
	local bottom = py - KartStats.RideHeight
	for _, course in ipairs(self.courses) do
		local track = course.track
		local open = track.closed == false
		local lastSeg = track.n - 1
		for _, i in ipairs(track:candidates(px, pz)) do
			if not course.noSurface[i] then
				local t, lateral, _, height, g, inside = track:locate(i, px, pz)
				local endCap = open and ((i == 1 and t <= 0) or (i == lastSeg and t >= 1))
				if inside and not endCap then
					local wallLat = g.w / 2 + g.sh
					for side = -1, 1, 2 do
						local wh = if side < 0 then g.wl else g.wr
						local gap = if side < 0 then course.gapL[i] else course.gapR[i]
						if wh > 0.5 and not gap then
							local d = side * lateral
							if d > wallLat - radius and d < wallLat + radius + 2 then
								local base = height - (if course.solid then 80 else 3)
								local top = height + wh
								if bottom < top and py > base then
									local depth = d - (wallLat - radius)
									if depth > bestD then
										bestD = depth
										bestN = g.right * (-side)
									end
								end
							end
						end
					end
				end
			end
		end
		if course.entry then
			for _, o in ipairs(course.entry.obstacles) do
				local n, depth = obstaclePush(o, pos, radius)
				if n and depth > bestD then
					bestN, bestD = n, depth
				end
			end
		end
	end
	return bestN, bestD
end

return TrackQuery
