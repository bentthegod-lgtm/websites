local Loader = require("./loader")
local MapData = Loader.shared("MapData")
local ChaosCity = Loader.shared("Maps/ChaosCity")
local TrackQuery = Loader.shared("TrackQuery")
local KP = Loader.shared("KartPhysics")
local S = Loader.shared("Config/KartStats")
local Registry = Loader.shared("Events/Registry")
local EventRules = Loader.shared("EventRules")
local V3 = Loader.roblox.Vector3

local data = MapData.compile(ChaosCity)
local main = data.main
local q = TrackQuery.new(data)

local function shortcut(id)
	return data.byId[id]
end

-- Drives a kart along a shortcut's centre line (simple pursuit) from `startDist` with an
-- initial speed; `boost` keeps a boost running. Returns the lowest Y reached after the gap
-- and whether it ended on a road.
local function leap(id, speed, boost)
	local sc = shortcut(id)
	local track = sc.track
	local cf = track:frame(sc.gapStart - 90, 0, S.RideHeight)
	local k = KP.new(cf)
	k.vel = cf.LookVector * speed
	k.grounded = true
	local minY = math.huge
	local onRoad = false
	for _ = 1, 60 * 4 do
		if boost then
			k.boostT = math.max(k.boostT, 0.5)
		end
		local hit = track:project(k.pos)
		local target = track:point((hit and hit.dist or 0) + 30, 0)
		local fwd = KP.forward(k.yaw)
		local right = V3.new(-fwd.Z, 0, fwd.X)
		local to = target - k.pos
		local steer = math.clamp(math.atan2(to:Dot(right), to:Dot(fwd)) * 2, -1, 1)
		KP.step(k, { gas = 1, steer = steer }, q, S.FixedStep)
		if hit and hit.dist > sc.gapEnd then
			minY = math.min(minY, k.pos.Y)
		end
		if k.pos.Y < -20 then
			break
		end
		if hit and hit.dist > sc.gapEnd + 25 and k.grounded then
			onRoad = k.course ~= "floor"
			break
		end
	end
	return minY, onRoad, k
end

return {
	{
		name = "Track: closed spline, continuous (uniform spacing, smooth heading and elevation)",
		fn = function()
			local n = main.n
			assert(n > 500, "too few samples")
			for i = 1, n do
				local a = main.samples[i]
				local b = main.samples[main:wrap(i + 1)]
				local d = (b.pos - a.pos).Magnitude
				assert(d > main.step * 0.75 and d < main.step * 1.35, string.format("gap %.2f at sample %d", d, i))
				local turn = math.acos(math.clamp(a.flat:Dot(b.flat), -1, 1))
				assert(turn < 0.2, string.format("heading kink %.2f rad at %d", turn, i))
				local slope = math.abs(b.pos.Y - a.pos.Y) / d
				assert(slope < 0.4, string.format("slope %.2f at %d", slope, i))
			end
			-- the loop closes: the last sample leads straight back into the first
			local last, first = main.samples[n], main.samples[1]
			assert((first.pos - last.pos).Magnitude < main.step * 1.35, "loop doesn't close")
			assert(main.closed and math.abs(main.length - n * main.step) < 1e-6)
			assert(main.length > 6800 and main.length < 8000, "length " .. main.length)
		end,
	},
	{
		name = "Track: widths, shoulders and walls are sane; real elevation (highway up, tunnel down)",
		fn = function()
			local minY, maxY, maxBank = math.huge, -math.huge, 0
			for _, s in ipairs(main.samples) do
				assert(s.w >= 44 and s.w <= 72, "width " .. s.w)
				assert(s.sh >= 2 and s.sh <= 10, "shoulder " .. s.sh)
				assert(s.wl >= 3 and s.wr >= 3, "missing walls at " .. s.index)
				minY = math.min(minY, s.pos.Y)
				maxY = math.max(maxY, s.pos.Y)
				maxBank = math.max(maxBank, math.abs(s.bank))
				if s.tags.tunnel then
					assert(s.pos.Y <= 8, "tunnel above ground")
				end
			end
			assert(maxY >= 38, "no elevated section: max " .. maxY)
			assert(minY <= -20, "no dip under the river: min " .. minY)
			assert(maxBank >= 20, "no banked turn")
			-- the hairpin is tight, the bowl is wide
			local hairpin, bowl = 0, 0
			for _, s in ipairs(main.samples) do
				if s.tags.hairpin then
					hairpin = math.max(hairpin, math.abs(s.curvature))
				end
				if s.tags.banked then
					bowl = math.max(bowl, math.abs(s.curvature))
				end
			end
			assert(1 / hairpin < 95, "hairpin radius " .. 1 / hairpin)
			assert(1 / bowl > 150, "bowl radius " .. 1 / bowl)
			local tags = {}
			for _, s in ipairs(main.samples) do
				for t in pairs(s.tags) do
					tags[t] = true
				end
			end
			for _, want in ipairs({ "finish", "downtown", "banked", "highway", "elevated", "overpass", "tunnel", "stadium", "bridge", "jump", "underpass", "park", "chicane", "hairpin" }) do
				assert(tags[want], "no " .. want .. " section")
			end
		end,
	},
	{
		name = "Track: the analytic ground covers the whole lap (road under every sample, walls at the edges)",
		fn = function()
			for _, s in ipairs(main.samples) do
				local h, n, surface, course = q:ground(s.pos + V3.new(0, S.StepUp, 0))
				assert(h and math.abs(h - s.pos.Y) < 0.6, "no road at sample " .. s.index)
				assert(course ~= "floor" and (surface == "Road" or surface == "Boost" or surface == "Jump"), "surface " .. tostring(surface) .. " at " .. s.index)
				assert(n.Y > 0.85, "normal")
			end
			-- shoulders are off-road; walls push back in
			local s = main:at(300)
			local shoulder = s.pos + s.right * (s.w / 2 + s.sh / 2)
			local _, _, surface = q:ground(shoulder + V3.new(0, 2, 0))
			assert(surface == "Offroad", "shoulder surface " .. tostring(surface))
			local edge = s.pos + s.right * (s.w / 2 + s.sh - 1) + V3.new(0, S.RideHeight, 0)
			local nrm, depth = q:walls(edge, S.Radius)
			assert(nrm and depth > 0 and nrm:Dot(s.right) < -0.9, "no wall push at the edge")
			-- the overpass: the north leg passes UNDER the highway
			local under = main:point(data.pointDist[40], 0)
			local hLow = q:ground(under + V3.new(0, 3, 0))
			local hHigh = q:ground(V3.new(under.X, 80, under.Z))
			assert(math.abs(hLow - under.Y) < 1, "underpass road")
			assert(hHigh and hHigh > 30, "highway above the underpass: " .. tostring(hHigh))
			-- falling into the river finds no ground; the pit has none either
			assert(q:ground(V3.new(-300, 5, (ChaosCity.River.z0 + ChaosCity.River.z1) / 2)) == nil, "river has a floor")
			local pit = ChaosCity.Pit
			assert(q:ground(V3.new((pit.x0 + pit.x1) / 2, 3, (pit.z0 + pit.z1) / 2)) == nil, "the pit has a floor")
		end,
	},
	{
		name = "Track: checkpoints cover the loop in order; none inside a shortcut's span",
		fn = function()
			local cps = data.checkpoints
			assert(#cps >= 12, "checkpoints " .. #cps)
			assert(cps[1].dist < 1, "checkpoint 1 is not the finish line")
			local biggest = 0
			for i = 1, #cps do
				local a = cps[i].dist
				local b = if i < #cps then cps[i + 1].dist else main.length
				assert(b > a, "out of order")
				biggest = math.max(biggest, b - a)
			end
			assert(biggest <= 1250, "checkpoint gap " .. biggest)
			for _, sc in ipairs(data.shortcuts) do
				for _, cp in ipairs(cps) do
					local into = (cp.dist - sc.startDist) % main.length
					assert(not (into > 0 and into < sc.mainSpan), cp.index .. " is inside " .. sc.id)
				end
			end
		end,
	},
	{
		name = "Track: both shortcuts leave and rejoin the road between two consecutive checkpoints and are shorter",
		fn = function()
			assert(#data.shortcuts >= 2)
			for _, sc in ipairs(data.shortcuts) do
				local track = sc.track
				for _, i in ipairs({ 1, track.n }) do
					local hit = main:project(track.samples[i].pos)
					assert(math.abs(hit.lateral) <= hit.w / 2 + hit.sh, sc.id .. " end " .. i .. " is not on the main road")
				end
				-- crossing order: the gate before the entry, then (after rejoining) the gate after
				local before, after = nil, nil
				for k, cp in ipairs(data.checkpoints) do
					if (sc.startDist - cp.dist) % main.length < (sc.startDist - (before and data.checkpoints[before].dist or 0)) % main.length or not before then
						before = k
					end
					local _ = after
				end
				local nextCp = data.checkpoints[before % #data.checkpoints + 1]
				local toNext = (nextCp.dist - sc.startDist) % main.length
				assert(toNext > sc.mainSpan, sc.id .. " rejoins after the next checkpoint")
				assert(track.length < sc.mainSpan, string.format("%s is not shorter (%.0f vs %.0f)", sc.id, track.length, sc.mainSpan))
				-- walls open where the shortcut leaves
				local gaps = 0
				for _ in pairs(main.gapL) do
					gaps += 1
				end
				for _ in pairs(main.gapR) do
					gaps += 1
				end
				assert(gaps > 6, "no wall gaps at the shortcut mouths")
			end
			assert(#shortcut("NeonAlley").obstacles >= 3 and #shortcut("NeonAlley").puddles >= 2, "the alley isn't risky")
		end,
	},
	{
		name = "Track: the Rooftop Leap needs a boost (top speed falls in the pit, boosted makes it)",
		fn = function()
			local slowMin, slowRoad = leap("RooftopLeap", S.TopSpeed, false)
			assert(not slowRoad and slowMin < -5, string.format("made the leap without a boost (min y %.1f)", slowMin))
			local fastMin, fastRoad = leap("RooftopLeap", S.TopSpeed * S.BoostTopMul, true)
			assert(fastRoad and fastMin > -1, string.format("boosted leap failed (min y %.1f)", fastMin))
		end,
	},
	{
		name = "Track: grid of 12 on the road behind the line; pads, kickers and item spots on the road",
		fn = function()
			assert(#data.grid == 12)
			for i, cf in ipairs(data.grid) do
				local h, _, surface, course = q:ground(cf.Position + V3.new(0, 2, 0))
				assert(h and course == "main" and surface ~= "Offroad", "slot " .. i .. " off the road")
				local hit = main:project(cf.Position)
				assert(main:delta(hit.dist, 0) > 0 and main:delta(hit.dist, 0) < 160, "slot " .. i .. " not behind the line")
				assert(cf.LookVector:Dot(hit.flat) > 0.98, "slot " .. i .. " not facing the track")
				for j = 1, i - 1 do
					assert((cf.Position - data.grid[j].Position).Magnitude > S.Radius * 2 + 1, "slots overlap")
				end
			end
			for _, pad in ipairs(data.pads) do
				local p = main:point(pad.dist, pad.lateral)
				local _, _, surface = q:ground(p + V3.new(0, 2, 0))
				assert(surface == "Boost", "pad not boosting: " .. tostring(surface))
			end
			local k = data.kickers[1]
			local _, _, ks = q:ground(main:point(k.dist, 0) + V3.new(0, 2, 0))
			assert(ks == "Jump", "kicker surface")
			assert(#data.itemSpots >= 25, "item spots " .. #data.itemSpots)
			for _, spot in ipairs(data.itemSpots) do
				local _, _, surface = q:ground(spot.position)
				assert(surface and surface ~= "Offroad", "item spot off the road")
			end
		end,
	},
	{
		name = "Track: event zones are tagged with lanes; every planned event has somewhere to happen",
		fn = function()
			assert(#data.zones >= 12)
			for _, z in ipairs(data.zones) do
				assert(next(z.tags), z.id .. " has no tags")
				if not z.trackWide then
					assert(z.lanes >= 1 and z.span > 0, z.id .. " lanes / span")
				end
			end
			for _, def in ipairs(Registry.catalog) do
				assert(#EventRules.zonesFor(def, data.zones) > 0, def.id .. " has no usable zone on Chaos City")
			end
		end,
	},
}
