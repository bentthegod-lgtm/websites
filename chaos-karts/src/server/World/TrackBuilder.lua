--[[
	TrackBuilder - turns the compiled map data (MapData) into part specs for a BuildJob:

	  Track/Ground   what karts drive on (the in-game raycast ground): road segments,
	                 shoulders (off-road), shortcut roads, boost pads, the jump kicker,
	                 alley slime, the grass floor. Attributes: Surface, Course.
	  Track/Walls    what karts bounce off (the in-game wall rays): barriers (low inside,
	                 tall outside / elevated), shortcut walls, alley dumpsters.
	  Track/Deco     curbs on turns, lane markings, edge lines, pillars and embankments,
	                 the tunnel ceiling and lights, portals, river, pit, the start / finish
	                 gantry with its 5 start lights, the checkered line, grid boxes, chevrons.
	  Track/Checkpoints, Track/ItemSpots, Track/EventZones   invisible markers (data for
	                 later stages and Studio debugging).

	Long straight stretches merge into single long parts; curves get short segments with a
	small overlap so the outside edge never shows a gap. Everything comes from the same
	samples the analytic TrackQuery uses, so the bots' world and the real one agree.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Parts = require(Shared.Parts)
local KartStats = require(Shared.Config.KartStats)

local TrackBuilder = {}

local P = Parts.Palette
local M = Enum.Material
local rgb = Color3.fromRGB

local ROAD_T = 2 -- road slab thickness
local MAX_SEG = 96

local function sameTags(a, b, keys)
	for _, k in ipairs(keys) do
		if (a.tags[k] == true) ~= (b.tags[k] == true) then
			return false
		end
	end
	return true
end

local GROUP_TAGS = { "tunnel", "highway", "elevated", "bridge", "downtown", "hill", "jump", "banked", "hairpin", "chicane", "stadium", "park" }

--[[
	Groups consecutive samples into straight-enough segments. Returns a list of
	{ a = first sample, b = the sample the segment ends at, samples = {...} }.
]]
function TrackBuilder.segments(track, flags)
	flags = flags or {}
	local out = {}
	local n = track.n
	local last = if track.closed then n else n - 1
	local i = 1
	while i <= last do
		local first = track.samples[i]
		local j = i
		while j < last do
			local nxt = track.samples[track:wrap(j + 1)]
			local d = (nxt.pos - first.pos).Magnitude
			local turn = math.deg(math.acos(math.clamp(first.flat:Dot(nxt.flat), -1, 1)))
			local slope = math.abs(nxt.tangent.Y - first.tangent.Y)
			local ok = d < MAX_SEG and turn < 2.6 and math.abs(nxt.bank - first.bank) < 1.2 and slope < 0.025 and math.abs(nxt.w - first.w) < 0.8 and math.abs(nxt.sh - first.sh) < 0.5 and math.abs(nxt.wl - first.wl) < 1 and math.abs(nxt.wr - first.wr) < 1 and sameTags(first, nxt, GROUP_TAGS)
			for _, f in ipairs({ flags.noSurface, flags.gapL, flags.gapR }) do
				if f and (f[j + 1] == true) ~= (f[i] == true) then
					ok = false
				end
			end
			if not ok then
				break
			end
			j += 1
		end
		local endSample = track.samples[track:wrap(j + 1)]
		table.insert(out, { a = first, b = endSample, from = i, to = j })
		i = j + 1
	end
	return out
end

-- Frame of a segment: CFrame at the centre of the road SURFACE, X = across, Y = normal.
local function segmentFrame(seg)
	local a, b = seg.a, seg.b
	local fwd = b.pos - a.pos
	local len = fwd.Magnitude
	fwd = if len > 1e-6 then fwd.Unit else a.tangent
	local normal = (a.normal + b.normal).Unit
	local right = fwd:Cross(normal).Unit
	normal = right:Cross(fwd).Unit
	local mid = (a.pos + b.pos) / 2
	local turn = math.acos(math.clamp(a.flat:Dot(b.flat), -1, 1))
	return CFrame.fromMatrix(mid, right, normal, -fwd), len, turn
end
TrackBuilder.segmentFrame = segmentFrame

local function add(job, folder, spec)
	return job:add(folder, spec)
end

local function stripe(i)
	return if i % 2 == 0 then P.CurbRed else P.CurbWhite
end

--[[
	Builds one road (main or shortcut) into the job. opts: course id, flags
	(noSurface / gapL / gapR), solid (walls & fill reach the ground), palette tweaks.
]]
local function buildRoad(job, track, opts)
	local segments = TrackBuilder.segments(track, opts.flags)
	local count = 0
	local curbIndex = 0
	local dashAcc = 0
	local pillarAcc = 0
	for k, seg in ipairs(segments) do
		local a = seg.a
		if not (opts.flags.noSurface and opts.flags.noSurface[seg.from]) then
			local cf, len, turn = segmentFrame(seg)
			local w = (a.w + seg.b.w) / 2
			local sh = (a.sh + seg.b.sh) / 2
			local overlap = (w / 2 + sh) * math.tan(turn / 2) * 2 + 0.3
			local L = len + overlap
			local tunnel = a.tags.tunnel
			local downtown = a.tags.downtown
			local elevated = a.tags.highway or a.tags.elevated or a.tags.bridge
			local thick = if elevated then 3 else ROAD_T
			-- road
			add(job, "Track/Ground", {
				Name = "Road",
				Size = Vector3.new(w, thick, L),
				CFrame = cf * CFrame.new(0, -thick / 2, 0),
				Color = if opts.alley then rgb(52, 46, 58) elseif k % 2 == 0 then P.Asphalt else rgb(49, 51, 61),
				Material = M.Asphalt,
				Attributes = { Surface = "Road", Course = opts.course },
			})
			count += 1
			-- shoulders (off-road strips)
			if sh > 0.5 then
				for _, side in ipairs({ -1, 1 }) do
					add(job, "Track/Ground", {
						Name = "Shoulder",
						Size = Vector3.new(sh, thick, L),
						CFrame = cf * CFrame.new(side * (w / 2 + sh / 2), -thick / 2 - 0.02, 0),
						Color = if downtown or elevated or tunnel then P.Sidewalk else P.Grass,
						Material = if downtown or elevated or tunnel then M.Concrete else M.Grass,
						Attributes = { Surface = "Offroad", Course = opts.course },
					})
					count += 1
				end
			end
			-- walls (a concrete skirt closes the gap down to the ground under raised edges:
			-- the outside of the banked bowl, and solid shortcut ramps / roofs)
			for _, side in ipairs({ -1, 1 }) do
				local wh = math.min(if side < 0 then a.wl else a.wr, if side < 0 then seg.b.wl else seg.b.wr)
				local gaps = if side < 0 then opts.flags.gapL else opts.flags.gapR
				if wh > 0.5 and not (gaps and gaps[seg.from]) then
					local edgeY = (cf * CFrame.new(side * (w / 2 + sh), 0, 0)).Position.Y
					local down = 0
					if opts.solid or (a.tags.banked and edgeY > 0.5) then
						down = math.max(0, edgeY)
					end
					local tall = wh >= 8
					add(job, "Track/Walls", {
						Name = "Wall",
						Size = Vector3.new(1.6, wh, L),
						CFrame = cf * CFrame.new(side * (w / 2 + sh + 0.8), wh / 2, 0),
						Color = if opts.alley then P.Brick elseif tunnel then P.ConcreteDark elseif tall then (if k % 2 == 0 then P.CurbRed else P.Barrier) else (if k % 2 == 0 then P.BarrierBlue else P.Barrier),
						Material = if opts.alley then M.Brick elseif tunnel then M.Concrete else M.SmoothPlastic,
					})
					count += 1
					if down > 0.5 then
						local wallCF = cf * CFrame.new(side * (w / 2 + sh + 0.8), 0, 0)
						local base = wallCF.Position
						add(job, "Track/Walls", {
							Name = "WallSkirt",
							Size = Vector3.new(1.6, down + 0.2, L),
							CFrame = CFrame.lookAt(Vector3.new(base.X, base.Y - down / 2, base.Z), Vector3.new(base.X + wallCF.LookVector.X, base.Y - down / 2, base.Z + wallCF.LookVector.Z)),
							Color = if opts.solid then P.ConcreteDark else rgb(70, 64, 104),
							Material = M.Concrete,
						})
						add(job, "Track/Deco", {
							Name = "SkirtNeon",
							Size = Vector3.new(1.8, 0.6, L),
							CFrame = CFrame.lookAt(Vector3.new(base.X, base.Y - 1.2, base.Z), Vector3.new(base.X + wallCF.LookVector.X, base.Y - 1.2, base.Z + wallCF.LookVector.Z)),
							Color = if opts.solid then P.NeonCyan else P.NeonPink,
							Material = M.Neon,
							CanCollide = false,
							CastShadow = false,
						})
						count += 2
					end
				end
			end
			-- curbs on turns (both edges, alternating red / white)
			local curv = math.max(math.abs(a.curvature), math.abs(seg.b.curvature))
			if curv > 1 / 260 and not tunnel and not opts.alley then
				curbIndex += 1
				for _, side in ipairs({ -1, 1 }) do
					add(job, "Track/Deco", {
						Name = "Curb",
						Size = Vector3.new(2.6, 0.2, L),
						CFrame = cf * CFrame.new(side * (w / 2 - 1.3), 0.08, 0),
						Color = stripe(curbIndex + (if side > 0 then 1 else 0)),
						CanCollide = false,
						CastShadow = false,
					})
					count += 1
				end
			elseif not opts.alley and len >= 30 then
				-- edge lines on straights
				for _, side in ipairs({ -1, 1 }) do
					add(job, "Track/Deco", { Name = "EdgeLine", Size = Vector3.new(0.7, 0.1, L), CFrame = cf * CFrame.new(side * (w / 2 - 2), 0.04, 0), Color = P.Line, CanCollide = false, CastShadow = false })
					count += 1
				end
			end
			-- dashed centre line (straights) / tunnel lights
			if not opts.alley and curv < 1 / 500 and w > 44 then
				dashAcc += len
				local dashes = math.floor(dashAcc / 26)
				dashAcc -= dashes * 26
				for d = 1, dashes do
					local z = -len / 2 + (d - 0.5) * (len / math.max(1, dashes))
					add(job, "Track/Deco", { Name = "LaneDash", Size = Vector3.new(0.8, 0.1, 10), CFrame = cf * CFrame.new(0, 0.04, z), Color = if downtown then P.LineYellow else P.Line, CanCollide = false, CastShadow = false })
					count += 1
				end
			end
			if tunnel and a.pos.Y < -3 then
				-- glass ceiling under the river + light strips
				add(job, "Track/Deco", {
					Name = "TunnelCeiling",
					Size = Vector3.new(w + sh * 2 + 3.2, 1.2, L),
					CFrame = cf * CFrame.new(0, 14.6, 0),
					Color = rgb(70, 150, 190),
					Material = M.Glass,
					Transparency = 0.45,
					CanCollide = false,
				})
				count += 1
				if k % 2 == 0 then
					for _, side in ipairs({ -1, 1 }) do
						add(job, "Track/Deco", { Name = "TunnelLight", Size = Vector3.new(0.4, 0.6, math.max(4, L - 2)), CFrame = cf * CFrame.new(side * (w / 2 + sh - 0.1), 7, 0), Color = P.NeonCyan, Material = M.Neon, CanCollide = false, CastShadow = false, Light = if k % 4 == 0 then { Color = P.NeonCyan, Range = 24, Brightness = 1.2 } else nil })
						count += 1
					end
				end
			end
			-- what holds the road up: pillars under elevated roads, embankments elsewhere
			local lowY = math.min(a.pos.Y, seg.b.pos.Y)
			if elevated and lowY > 6 then
				pillarAcc += len
				if pillarAcc >= 48 then
					pillarAcc = 0
					for _, side in ipairs({ -1, 1 }) do
						local top = cf * CFrame.new(side * (w / 2 - 7), -thick, 0)
						local base = Vector3.new(top.Position.X, 0, top.Position.Z)
						local h = top.Position.Y
						local clash = opts.main and opts.main:project(base, nil, 80)
						local onRoad = clash and math.abs(clash.lateral) < clash.w / 2 + clash.sh + 4 and math.abs(clash.height) < 4
						if h > 2 and not onRoad then
							add(job, "Track/Deco", { Name = "Pillar", Size = Vector3.new(5, h, 5), CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)), Color = P.Concrete, Material = M.Concrete, CanCollide = false })
							count += 1
						end
					end
					add(job, "Track/Deco", { Name = "Girder", Size = Vector3.new(w + sh * 2, 2.4, 6), CFrame = cf * CFrame.new(0, -thick - 1.2, 0), Color = P.ConcreteDark, Material = M.Concrete, CanCollide = false })
					count += 1
				end
			elseif (opts.solid or a.tags.hill or a.tags.jump or (lowY > 0.6 and not a.tags.banked)) and not tunnel and lowY > 0.6 and not (opts.solid and lowY > 20) then
				local h = lowY - thick
				if h > 0.3 then
					add(job, "Track/Deco", {
						Name = "Embankment",
						Size = Vector3.new(w + sh * 2 + 3.2, h, L),
						CFrame = CFrame.lookAt(Vector3.new(cf.Position.X, h / 2, cf.Position.Z), Vector3.new(cf.Position.X - cf.LookVector.X, h / 2, cf.Position.Z - cf.LookVector.Z)),
						Color = if opts.solid then P.ConcreteDark else P.GrassDark,
						Material = if opts.solid then M.Concrete else M.Grass,
						CanCollide = false,
					})
					count += 1
				end
			end
		end
	end
	return count, #segments
end

-- A flat panel on the road at (dist, lateral) of the main track.
local function roadPanel(job, main, dist, lateral, length, width, raise, spec)
	local cf = main:frame(dist, lateral, raise)
	spec.Size = Vector3.new(width, 0.12, length)
	spec.CFrame = cf
	return job:add(spec.Folder or "Track/Deco", spec)
end

function TrackBuilder.plan(data, job)
	local main = data.main
	local stats = { parts = 0 }
	local function count(n)
		stats.parts += n
	end

	count(buildRoad(job, main, { course = "main", flags = { gapL = main.gapL, gapR = main.gapR }, main = main }))
	for _, sc in ipairs(data.shortcuts) do
		count(buildRoad(job, sc.track, { course = sc.id, flags = { noSurface = sc.noSurface, gapL = sc.gapL, gapR = sc.gapR }, solid = true, alley = sc.id == "NeonAlley", main = main }))
		for i, o in ipairs(sc.obstacles) do
			job:add("Track/Walls", { Name = "Dumpster", Size = o.size, CFrame = o.cframe, Color = if i % 2 == 0 then rgb(40, 120, 70) else rgb(60, 90, 160), Material = M.DiamondPlate })
			job:add("Track/Deco", { Name = "DumpsterLid", Size = Vector3.new(o.size.X + 0.4, 0.5, o.size.Z + 0.4), CFrame = o.cframe * CFrame.new(0, o.size.Y / 2 + 0.25, 0), Color = P.Black, CanCollide = false })
			count(2)
		end
		for _, p in ipairs(sc.puddles) do
			local cf = sc.track:frame(p.dist, p.lateral, 0.06)
			job:add("Track/Ground", { Name = "Slime", Size = Vector3.new(p.width, 0.12, p.length), CFrame = cf, Color = P.NeonGreen, Material = M.Neon, Transparency = 0.15, Attributes = { Surface = "Offroad", Course = sc.id } })
			count(1)
		end
		-- neon arrows into the shortcut mouth
		local mouth = sc.track:frame(26, 0, 0.1)
		local half = sc.def.w / 2 + sc.def.sh + 1.5
		for _, side in ipairs({ -1, 1 }) do
			job:add("Track/Deco", { Name = "ShortcutPost", Size = Vector3.new(1.2, 20, 1.2), CFrame = mouth * CFrame.new(side * half, 10, 0), Color = P.NeonYellow, Material = M.Neon, CanCollide = false })
		end
		job:add("Track/Deco", { Name = "ShortcutSign", Size = Vector3.new(half * 2 + 2, 4, 0.6), CFrame = mouth * CFrame.new(0, 21, 0), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Back, Text = string.upper(sc.def.Name) .. "  >>", Color = P.NeonYellow } })
		count(3)
	end

	-- boost pads and the kicker (Ground: their surface boosts / launches)
	for _, pad in ipairs(data.pads) do
		roadPanel(job, main, pad.dist, pad.lateral, pad.length, pad.width, 0.06, { Folder = "Track/Ground", Name = "BoostPad", Color = P.NeonOrange, Material = M.Neon, Attributes = { Surface = "Boost", Course = "main" } })
		for c = -1, 1 do
			roadPanel(job, main, pad.dist + c * pad.length / 3.5, pad.lateral, 1.4, pad.width * 0.7, 0.14, { Name = "Chevron", Color = P.NeonYellow, Material = M.Neon, CanCollide = false, CastShadow = false })
		end
		count(4)
	end
	for _, k in ipairs(data.kickers) do
		roadPanel(job, main, k.dist, k.lateral, k.length, k.width, 0.06, { Folder = "Track/Ground", Name = "JumpKicker", Color = P.NeonPink, Material = M.Neon, Attributes = { Surface = "Jump", Course = "main" } })
		for _, side in ipairs({ -1, 1 }) do
			local cf = main:frame(k.dist, side * (k.width / 2 + 4), 0)
			job:add("Track/Deco", { Name = "JumpFlag", Size = Vector3.new(1, 14, 1), CFrame = cf * CFrame.new(0, 7, 0), Color = P.White, CanCollide = false })
			job:add("Track/Deco", { Name = "JumpBanner", Size = Vector3.new(0.4, 4, 7), CFrame = cf * CFrame.new(0, 12, 3.5), Color = P.NeonPink, Material = M.Neon, CanCollide = false })
		end
		local cf = main:frame(k.dist - 60, 0, 0)
		job:add("Track/Deco", { Name = "JumpSign", Size = Vector3.new(30, 8, 1), CFrame = cf * CFrame.new(0, 26, 0), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Back, Text = "BIG JUMP!", Color = P.NeonPink } })
		count(6)
	end

	-- start / finish: checkered line, gantry with 5 start lights, grid boxes
	local cf0 = main:frame(0, 0, 0)
	local w0 = main:at(0).w
	local squares = 12
	for row = 0, 1 do
		for i = 0, squares - 1 do
			local x = -w0 / 2 + (i + 0.5) * (w0 / squares)
			job:add("Track/Deco", { Name = "Checker", Size = Vector3.new(w0 / squares, 0.12, 3), CFrame = cf0 * CFrame.new(x, 0.06, -1.5 + row * 3), Color = if (i + row) % 2 == 0 then P.White else P.Black, CanCollide = false, CastShadow = false })
		end
	end
	count(squares * 2)
	local span = w0 + 22
	for _, side in ipairs({ -1, 1 }) do
		job:add("Track/Deco", { Name = "GantryLeg", Size = Vector3.new(3, 26, 3), CFrame = cf0 * CFrame.new(side * span / 2, 13, 0), Color = P.SteelDark, Material = M.Metal })
		job:add("Track/Deco", { Name = "GantryNeon", Size = Vector3.new(0.6, 24, 0.6), CFrame = cf0 * CFrame.new(side * (span / 2 - 1.8), 13, -1.6), Color = P.NeonCyan, Material = M.Neon, CanCollide = false })
	end
	job:add("Track/Deco", { Name = "GantryBeam", Size = Vector3.new(span + 3, 5, 4), CFrame = cf0 * CFrame.new(0, 28, 0), Color = P.Black, Material = M.Metal, Text = { Face = Enum.NormalId.Back, Text = "CHAOS KARTS  -  START / FINISH", Color = P.NeonYellow } })
	job:add("Track/Deco", { Name = "GantryBack", Size = Vector3.new(span + 3, 5, 0.4), CFrame = cf0 * CFrame.new(0, 28, 2.2), Color = P.Black, CanCollide = false, Text = { Face = Enum.NormalId.Front, Text = "FINAL LAP = MAXIMUM CHAOS", Color = P.NeonPink } })
	job:add("Track/Deco", { Name = "LightBar", Size = Vector3.new(26, 4, 2), CFrame = cf0 * CFrame.new(0, 22.5, -1), Color = P.Black, Material = M.Metal })
	for i = 1, 5 do
		job:add("Track/Deco", { Name = "StartLight" .. i, Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2), CFrame = cf0 * CFrame.new(-10 + (i - 1) * 5, 22.5, -2.2), Color = rgb(60, 20, 20), Material = M.Neon, CanCollide = false, Tag = "StartLights", Light = { Color = P.Red, Range = 18, Brightness = 0 } })
	end
	count(4 + 4 + 5)
	for slot, cf in ipairs(data.grid) do
		local ground = cf * CFrame.new(0, -KartStats.RideHeight + 0.06, 0)
		job:add("Track/Deco", { Name = "GridBox", Size = Vector3.new(9, 0.1, 0.8), CFrame = ground * CFrame.new(0, 0, -5.5), Color = P.White, CanCollide = false, CastShadow = false, Text = { Face = Enum.NormalId.Top, Text = tostring(slot), Color = P.White, PixelsPerStud = 10 } })
		count(1)
	end

	-- river, banks and the rooftop pit
	local river = data.def.River
	if river then
		local zc, zw = (river.z0 + river.z1) / 2, river.z1 - river.z0
		job:add("Track/Deco", { Name = "River", Size = Vector3.new(3450, 1, zw), CFrame = CFrame.new(0, river.y, zc), Color = P.Water, Material = M.Glass, Transparency = 0.25, CanCollide = false, CastShadow = false })
		job:add("Track/Deco", { Name = "RiverBed", Size = Vector3.new(3450, 2, zw + 4), CFrame = CFrame.new(0, -34, zc), Color = rgb(30, 60, 80), CanCollide = false })
		-- the banks stop where the tunnel passes under the river (gaps over the main road)
		local spans = { { -1725, 1725 } }
		for _, s in ipairs(main.samples) do
			if s.tags.tunnel and s.pos.Z > river.z0 - 10 and s.pos.Z < river.z1 + 10 then
				local half = s.w / 2 + s.sh + 4
				local out = {}
				for _, sp in ipairs(spans) do
					local a, b = s.pos.X - half, s.pos.X + half
					if b <= sp[1] or a >= sp[2] then
						table.insert(out, sp)
					else
						if a > sp[1] then
							table.insert(out, { sp[1], a })
						end
						if b < sp[2] then
							table.insert(out, { b, sp[2] })
						end
					end
				end
				spans = out
			end
		end
		for _, z in ipairs({ river.z0, river.z1 }) do
			for _, sp in ipairs(spans) do
				job:add("Track/Deco", { Name = "RiverBank", Size = Vector3.new(sp[2] - sp[1], 30, 3), CFrame = CFrame.new((sp[1] + sp[2]) / 2, -15.2, z + (if z == river.z0 then 1.5 else -1.5)), Color = P.ConcreteDark, Material = M.Concrete, CanCollide = false })
				count(1)
			end
		end
		count(2)
	end
	local pit = data.def.Pit
	if pit then
		local cx, cz = (pit.x0 + pit.x1) / 2, (pit.z0 + pit.z1) / 2
		local sx, sz = pit.x1 - pit.x0, pit.z1 - pit.z0
		job:add("Track/Deco", { Name = "PitFloor", Size = Vector3.new(sx, 1, sz), CFrame = CFrame.new(cx, -38, cz), Color = rgb(20, 20, 24), CanCollide = false })
		for _, e in ipairs({ { cx, pit.z0, sx, 1 }, { cx, pit.z1, sx, 1 }, { pit.x0, cz, 1, sz }, { pit.x1, cz, 1, sz } }) do
			job:add("Track/Deco", { Name = "PitEdge", Size = Vector3.new(e[3], 1.2, e[4]), CFrame = CFrame.new(e[1], 0.2, e[2]), Color = P.Hazard, Material = M.Neon, CanCollide = false })
		end
		count(5)
	end

	-- the grass floor (with holes) - karts that land here are off the course
	for _, r in ipairs(data.floor) do
		local sx, sz = r[3] - r[1], r[4] - r[2]
		job:add("Track/Ground", { Name = "Floor", Size = Vector3.new(sx, 4, sz), CFrame = CFrame.new((r[1] + r[3]) / 2, data.floorY - 2, (r[2] + r[4]) / 2), Color = P.Grass, Material = M.Grass, Attributes = { Surface = "Offroad", Course = "floor" } })
		count(1)
	end

	-- invisible markers for later stages / Studio debugging
	for _, cp in ipairs(data.checkpoints) do
		job:add("Track/Checkpoints", { Name = "Checkpoint" .. cp.index, Size = Vector3.new(cp.halfWidth * 2, 24, 1), CFrame = cp.cframe * CFrame.new(0, 12, 0), Transparency = 1, CanCollide = false, CastShadow = false, Attributes = { Index = cp.index, Dist = cp.dist } })
	end
	for i, spot in ipairs(data.itemSpots) do
		job:add("Track/ItemSpots", { Name = "ItemSpot" .. i, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(spot.position), Transparency = 1, CanCollide = false, CastShadow = false, Attributes = { Dist = spot.dist, Lateral = spot.lateral, Stage = 3 } })
	end
	for _, z in ipairs(data.zones) do
		job:add("Track/EventZones", { Name = z.id, Size = Vector3.new(z.width, 30, math.max(20, math.min(z.span, 400))), CFrame = CFrame.new(z.centre + Vector3.new(0, 15, 0)), Transparency = 1, CanCollide = false, CastShadow = false, Attributes = { Tags = table.concat(z.tagList, ","), Lanes = z.lanes, From = z.from, Span = z.span } })
	end
	count(#data.checkpoints + #data.itemSpots + #data.zones)
	return stats
end

return TrackBuilder
