--[[
	TrackMath - turns a data-driven track definition (Maps/*.lua) into an arc-length sampled
	racing line with frames. Pure: used by the TrackBuilder (parts), TrackQuery (the analytic
	ground for bots / the harness / server checks), RaceMath (progress), the minimap and the
	unit tests.

	Control point: { x, y, z, w = width, bank = degrees (+ = right side low), sh = shoulder,
	wl / wr = wall height left / right (0 = none), tags = { ... } }.
	The line is a centripetal Catmull-Rom spline through the points (closed for a circuit,
	open for a shortcut), resampled every `step` studs so that distance along the track is
	exact.

	Sample fields: pos (centre of the road surface), dist, tangent (3D unit), flat (XZ unit),
	right (XZ unit), across (unit along the banked surface, to the right), normal, w, sh,
	wl, wr, bank, curvature (rad / stud, + = turning right), tags (set), index.
]]

local TrackMath = {}
TrackMath.__index = TrackMath

local Y = Vector3.new(0, 1, 0)
local DENSE = 48 -- spline evaluations per control segment before resampling
local CELL = 48 -- spatial hash cell size

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- Centripetal Catmull-Rom (Barry-Goldman) between p1 and p2.
local function catmull(p0, p1, p2, p3, u)
	local function knot(t, a, b)
		local d = (b - a).Magnitude
		return t + math.max(1e-4, math.sqrt(d))
	end
	local t0 = 0
	local t1 = knot(t0, p0, p1)
	local t2 = knot(t1, p1, p2)
	local t3 = knot(t2, p2, p3)
	local t = lerp(t1, t2, u)
	local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
end

local SCALARS = { "w", "bank", "sh", "wl", "wr" }

local function pointOf(def, i)
	local p = def.points[i]
	local d = def.defaults or {}
	return {
		pos = Vector3.new(p[1], p[2], p[3]),
		w = p.w or d.w or 56,
		bank = p.bank or d.bank or 0,
		sh = p.sh or d.sh or 6,
		wl = p.wl or d.wl or 5,
		wr = p.wr or d.wr or 5,
		tags = p.tags or {},
	}
end

--[[
	build(def, closed) -> track. def = { points = {...}, step = 6, defaults = {...} }.
]]
function TrackMath.build(def, closed)
	if closed == nil then
		closed = def.closed ~= false
	end
	local n = #def.points
	assert(n >= (if closed then 4 else 2), "track needs more control points")
	local pts = {}
	for i = 1, n do
		pts[i] = pointOf(def, i)
	end
	local function P(i)
		if closed then
			return pts[(i - 1) % n + 1]
		end
		if i < 1 then
			-- mirror the first segment so the open spline starts straight
			return { pos = pts[1].pos * 2 - pts[2].pos }
		elseif i > n then
			return { pos = pts[n].pos * 2 - pts[n - 1].pos }
		end
		return pts[i]
	end

	-- dense evaluation
	local dense = {}
	local segCount = if closed then n else n - 1
	for i = 1, segCount do
		local a, b = P(i), P(i + 1)
		local p0, p3 = P(i - 1).pos, P(i + 2).pos
		for k = 0, DENSE - 1 do
			local u = k / DENSE
			local s = smooth(u)
			local entry = { pos = catmull(p0, a.pos, b.pos, p3, u), seg = i, u = u }
			for _, key in ipairs(SCALARS) do
				entry[key] = lerp(a[key], b[key], if key == "bank" then s else u)
			end
			entry.tagsA, entry.tagsB = a.tags, b.tags
			table.insert(dense, entry)
		end
	end
	if closed then
		local first = dense[1]
		table.insert(dense, { pos = first.pos, seg = n + 1, u = 0, w = first.w, bank = first.bank, sh = first.sh, wl = first.wl, wr = first.wr, tagsA = first.tagsA, tagsB = first.tagsB })
	else
		local last = pts[n]
		table.insert(dense, { pos = last.pos, seg = n, u = 1, w = last.w, bank = last.bank, sh = last.sh, wl = last.wl, wr = last.wr, tagsA = last.tags, tagsB = last.tags })
	end
	local cum = { 0 }
	for i = 2, #dense do
		cum[i] = cum[i - 1] + (dense[i].pos - dense[i - 1].pos).Magnitude
	end
	local length = cum[#dense]
	local step = def.step or 6
	local count = math.max(4, math.floor(length / step + 0.5))
	step = length / count

	local samples = {}
	local j = 1
	local total = if closed then count else count + 1
	for k = 1, total do
		local d = (k - 1) * step
		while j < #dense - 1 and cum[j + 1] < d do
			j += 1
		end
		local span = cum[j + 1] - cum[j]
		local t = if span > 1e-9 then math.clamp((d - cum[j]) / span, 0, 1) else 0
		local a, b = dense[j], dense[j + 1]
		local s = {
			index = k,
			dist = d,
			pos = a.pos:Lerp(b.pos, t),
			w = lerp(a.w, b.w, t),
			bank = lerp(a.bank, b.bank, t),
			sh = lerp(a.sh, b.sh, t),
			wl = lerp(a.wl, b.wl, t),
			wr = lerp(a.wr, b.wr, t),
			tags = {},
			seg = a.seg,
		}
		-- tags: a control point's tags apply from halfway before it to halfway after it
		local tagsFrom = if a.u + (b.u - a.u) * t < 0.5 then a.tagsA else a.tagsB
		for _, tag in ipairs(tagsFrom or {}) do
			s.tags[tag] = true
		end
		samples[k] = s
	end

	local self = setmetatable({ samples = samples, n = #samples, length = length, step = step, closed = closed, def = def, grid = {} }, TrackMath)
	self:_frames()
	self:_index()
	return self
end

function TrackMath:wrap(i)
	if self.closed then
		return (i - 1) % self.n + 1
	end
	return math.clamp(i, 1, self.n)
end

function TrackMath:_frames()
	local samples = self.samples
	for i, s in ipairs(samples) do
		local prev = samples[self:wrap(i - 1)]
		local nxt = samples[self:wrap(i + 1)]
		local tangent = nxt.pos - prev.pos
		if tangent.Magnitude < 1e-6 then
			tangent = Vector3.new(1, 0, 0)
		end
		tangent = tangent.Unit
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		flat = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(1, 0, 0)
		local right = flat:Cross(Y).Unit
		local roll = math.rad(s.bank)
		local across = right * math.cos(roll) - Y * math.sin(roll)
		local normal = across:Cross(tangent).Unit
		s.tangent, s.flat, s.right, s.across, s.normal = tangent, flat, right, across, normal
	end
	for i, s in ipairs(samples) do
		local prev = samples[self:wrap(i - 1)]
		local nxt = samples[self:wrap(i + 1)]
		local cross = prev.flat:Cross(nxt.flat).Y
		local dot = math.clamp(prev.flat:Dot(nxt.flat), -1, 1)
		local angle = math.atan2(-cross, dot)
		local span = if self.closed or (i > 1 and i < self.n) then 2 * self.step else self.step
		s.curvature = angle / span
	end
end

local function cellKey(cx, cz)
	return cx * 65536 + cz
end

function TrackMath:_index()
	local grid = self.grid
	local last = if self.closed then self.n else self.n - 1
	for i = 1, last do
		local a = self.samples[i]
		local b = self.samples[self:wrap(i + 1)]
		local reach = math.max(a.w, b.w) / 2 + math.max(a.sh, b.sh) + 14
		local x0 = math.min(a.pos.X, b.pos.X) - reach
		local x1 = math.max(a.pos.X, b.pos.X) + reach
		local z0 = math.min(a.pos.Z, b.pos.Z) - reach
		local z1 = math.max(a.pos.Z, b.pos.Z) + reach
		for cx = math.floor(x0 / CELL), math.floor(x1 / CELL) do
			for cz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
				local key = cellKey(cx, cz)
				local list = grid[key]
				if not list then
					list = {}
					grid[key] = list
				end
				table.insert(list, i)
			end
		end
	end
end

-- Segment indices whose road (plus shoulder and walls) may cover world (x, z).
function TrackMath:candidates(x, z)
	return self.grid[cellKey(math.floor(x / CELL), math.floor(z / CELL))] or {}
end

--[[
	Projects a world position onto segment i (sample i -> i+1). Returns a table:
	{ index, t, dist, lateral, height (road plane height under the point), normal, right,
	  flat, w, sh, wl, wr, centre }.
]]
function TrackMath:onSegment(i, pos)
	local a = self.samples[i]
	local b = self.samples[self:wrap(i + 1)]
	local ax, az = a.pos.X, a.pos.Z
	local dx, dz = b.pos.X - ax, b.pos.Z - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-9 then
		t = math.clamp(((pos.X - ax) * dx + (pos.Z - az) * dz) / len2, 0, 1)
	end
	local centre = a.pos:Lerp(b.pos, t)
	local right = a.right:Lerp(b.right, t)
	right = if right.Magnitude > 1e-6 then right.Unit else a.right
	local normal = a.normal:Lerp(b.normal, t).Unit
	local ox, oz = pos.X - centre.X, pos.Z - centre.Z
	local lateral = ox * right.X + oz * right.Z
	local height = centre.Y
	if math.abs(normal.Y) > 1e-4 then
		height = centre.Y - (normal.X * ox + normal.Z * oz) / normal.Y
	end
	local dist = a.dist + t * self.step
	if not self.closed then
		dist = a.dist + t * (b.dist - a.dist)
	end
	return {
		index = i,
		t = t,
		dist = dist,
		lateral = lateral,
		height = height,
		normal = normal,
		right = right,
		flat = a.flat:Lerp(b.flat, t).Unit,
		w = a.w + (b.w - a.w) * t,
		sh = a.sh + (b.sh - a.sh) * t,
		wl = a.wl + (b.wl - a.wl) * t,
		wr = a.wr + (b.wr - a.wr) * t,
		centre = centre,
		sample = a,
	}
end

--[[
	project(pos, hint?) -> the best on-segment projection (nil if far from the track).
	Prefers segments whose road height is close to pos.Y (overpasses), then the smallest
	lateral offset, then continuity with the hint index.
]]
function TrackMath:project(pos, hint, maxLateral)
	local best, bestScore = nil, math.huge
	local limit = maxLateral or math.huge
	local function consider(i)
		local hit = self:onSegment(i, pos)
		local excess = math.max(0, math.abs(hit.lateral) - (hit.w / 2 + hit.sh))
		local vertical = math.abs(pos.Y - hit.height)
		local score = math.abs(hit.lateral) * 0.25 + excess * 2 + vertical * 1.5
		if hint then
			local gap = math.abs(i - hint)
			if self.closed then
				gap = math.min(gap, self.n - gap)
			end
			score += math.max(0, gap - 20) * 0.5
		end
		if score < bestScore and math.abs(hit.lateral) <= limit then
			best, bestScore = hit, score
		end
	end
	local list = self:candidates(pos.X, pos.Z)
	for _, i in ipairs(list) do
		consider(i)
	end
	if not best and maxLateral == nil then
		-- far from every segment: brute force (rare: only for wildly off-track positions)
		local last = if self.closed then self.n else self.n - 1
		for i = 1, last do
			consider(i)
		end
	end
	return best
end

-- Interpolated sample at a distance along the track (wraps on a closed track).
function TrackMath:at(dist)
	local L = self.length
	if self.closed then
		dist = dist % L
	else
		dist = math.clamp(dist, 0, L)
	end
	local f = dist / self.step
	local i = math.floor(f) + 1
	local t = f - math.floor(f)
	if not self.closed and i >= self.n then
		return self.samples[self.n], 0
	end
	local a = self.samples[self:wrap(i)]
	local b = self.samples[self:wrap(i + 1)]
	return {
		pos = a.pos:Lerp(b.pos, t),
		flat = a.flat:Lerp(b.flat, t).Unit,
		right = a.right:Lerp(b.right, t).Unit,
		normal = a.normal:Lerp(b.normal, t).Unit,
		tangent = a.tangent:Lerp(b.tangent, t).Unit,
		w = a.w + (b.w - a.w) * t,
		sh = a.sh + (b.sh - a.sh) * t,
		bank = a.bank + (b.bank - a.bank) * t,
		curvature = a.curvature + (b.curvature - a.curvature) * t,
		tags = a.tags,
		dist = dist,
		index = a.index,
	}
end

-- World point on the road surface at (dist, lateral offset).
function TrackMath:point(dist, lateral)
	local s = self:at(dist)
	local roll = math.rad(s.bank)
	local across = s.right * math.cos(roll) - Y * math.sin(roll)
	return s.pos + across * (lateral or 0), s
end

-- CFrame on the road at (dist, lateral), facing along the track, up = road normal.
function TrackMath:frame(dist, lateral, heightAbove)
	local p, s = self:point(dist, lateral)
	local up = s.normal
	local look = (s.tangent - up * s.tangent:Dot(up)).Unit
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(p + up * (heightAbove or 0), right, up, -look), s
end

-- Signed shortest distance a -> b along a closed track (in (-L/2, L/2]).
function TrackMath:delta(a, b)
	local d = b - a
	if self.closed then
		local L = self.length
		d = (d + L / 2) % L - L / 2
	end
	return d
end

return TrackMath
