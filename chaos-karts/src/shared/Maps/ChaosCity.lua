--[[
	CHAOS CITY - the Stage 1 track. Pure data: TrackMath turns it into the racing line,
	MapData compiles the gameplay data (checkpoints, grid, pads, zones), the TrackBuilder
	builds the parts and TrackQuery answers "where is the ground" for bots and the harness.

	Plan (x east, z south; the lap runs clockwise on the minimap):
	  Downtown straight (start / finish gantry, Neon Plaza)  ->  the Big Banked Bowl (a 180
	  degree banked U-turn, ROOFTOP LEAP shortcut across the parking garage in its infield)
	  ->  the Skyline Highway climbs to 40 studs, crosses OVER the north leg and the park
	  ->  dives straight down into the RIVER TUNNEL under the river (-25 studs)  ->  the
	  stadium bulge (NEON ALLEY shortcut straight through the block)  ->  the north leg over
	  the river bridge, the BIG JUMP off the hill crest, UNDER the highway  ->  the S-curve
	  chicane  ->  the hairpin  ->  back onto the straight.

	Point fields: { x, y, z, w = width, bank = degrees (+ = right side low), sh = shoulder
	(off-road strip), wl / wr = wall height left / right, tags }. Walls are low on the
	inside of turns and tall on the outside / on anything elevated.
]]

local ChaosCity = {}

ChaosCity.Id = "ChaosCity"
ChaosCity.Name = "Chaos City"
ChaosCity.Laps = 3
ChaosCity.TargetLap = { 80, 95 } -- seconds, for a clean lap at racing pace (tested)

ChaosCity.Track = {
	step = 6,
	defaults = { w = 56, sh = 7, wl = 4, wr = 4, bank = 0 },
	points = {
		-- Downtown straight (heading east). Point 1 is the finish line.
		{ 0, 0, 0, w = 66, sh = 8, wl = 6, wr = 6, tags = { "finish", "downtown", "straight" } },
		{ 200, 0, 0, w = 66, sh = 8, wl = 6, wr = 4, tags = { "downtown", "straight", "plaza" } },
		{ 400, 0, 3, w = 62, wl = 6, tags = { "downtown", "straight" } },
		-- The Big Banked Bowl (right-hand U-turn, banked up to 22 degrees)
		{ 570, 2, 24, w = 60, bank = 6, wl = 9, tags = { "banked" } },
		{ 700, 8, 96, w = 60, bank = 14, wl = 10, tags = { "banked" } },
		{ 785, 13, 216, w = 62, bank = 20, wl = 11, tags = { "banked" } },
		{ 808, 15, 346, w = 62, bank = 22, wl = 11, tags = { "banked" } },
		{ 776, 13, 476, w = 62, bank = 20, wl = 11, tags = { "banked" } },
		{ 686, 8, 576, w = 60, bank = 14, wl = 10, tags = { "banked" } },
		{ 560, 2, 634, w = 60, bank = 5, wl = 8 },
		-- Skyline Highway (heading west, climbing to 40 studs)
		{ 420, 2, 656, w = 56, sh = 4, wl = 6, wr = 6, tags = { "highway" } },
		{ 300, 16, 676, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ 170, 32, 696, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ 40, 40, 706, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated", "overpass" } },
		{ -110, 40, 713, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ -260, 34, 728, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ -385, 21, 785, w = 56, sh = 3, bank = -6, wl = 6, wr = 9, tags = { "highway", "elevated" } },
		{ -470, 6, 870, w = 54, sh = 3, bank = -6, wl = 6, wr = 9, tags = { "highway" } },
		-- River Tunnel (dives under the river)
		{ -500, -6, 945, w = 52, sh = 3, wl = 10, wr = 10, tags = { "tunnel" } },
		{ -507, -18, 1000, w = 50, sh = 3, wl = 20, wr = 20, tags = { "tunnel" } },
		{ -508, -25, 1050, w = 50, sh = 3, wl = 27, wr = 27, tags = { "tunnel" } },
		{ -504, -18, 1100, w = 50, sh = 3, wl = 20, wr = 20, tags = { "tunnel" } },
		{ -497, -6, 1160, w = 52, sh = 3, wl = 10, wr = 10, tags = { "tunnel" } },
		{ -482, 0, 1240, w = 56, wr = 8 },
		-- South side: left turn, then the stadium bulge (Neon Alley cuts across it)
		{ -440, 0, 1330, w = 58, bank = -6, wr = 9 },
		{ -360, 0, 1393, w = 58, bank = -3 },
		{ -262, 0, 1404, w = 58 },
		{ -182, 0, 1450, w = 56, bank = 5, wl = 8, tags = { "stadium" } },
		{ -110, 0, 1530, w = 56, bank = 3, wl = 8, tags = { "stadium" } },
		{ -20, 0, 1545, w = 56, wr = 8, tags = { "stadium" } },
		{ 50, 0, 1480, w = 56, bank = -5, wr = 8, tags = { "stadium" } },
		{ 96, 0, 1404, w = 56, bank = -3 },
		{ 138, 0, 1290, w = 54 },
		-- North leg: river bridge, hill crest jump, under the highway
		{ 150, 4, 1170, w = 52, sh = 4, wl = 6, wr = 6, tags = { "bridge" } },
		{ 152, 8, 1050, w = 52, sh = 3, wl = 6, wr = 6, tags = { "bridge" } },
		{ 149, 4, 955, w = 52, sh = 4, wl = 6, wr = 6, tags = { "bridge" } },
		{ 141, 11, 905, w = 54, wl = 6, wr = 6, tags = { "hill" } },
		{ 133, 18, 862, w = 56, wl = 6, wr = 6, tags = { "jump" } },
		{ 122, 6, 790, w = 58, tags = { "hill" } },
		{ 110, 0, 715, w = 56, tags = { "underpass" } },
		{ 98, 0, 600, w = 56, tags = { "park" } },
		{ 75, 0, 455, w = 56, tags = { "park" } },
		{ 20, 0, 346, w = 56, bank = -4, wr = 8 },
		{ -90, 0, 300, w = 56 },
		-- S-curve chicane (left-right-left)
		{ -200, 0, 282, w = 54, bank = 3, tags = { "chicane" } },
		{ -290, 0, 312, w = 54, bank = -3, tags = { "chicane" } },
		{ -385, 0, 268, w = 54, bank = 3, tags = { "chicane" } },
		{ -480, 0, 176, w = 56 },
		{ -580, 0, 138, w = 56 },
		-- Hairpin (tight right-hander), then onto the straight
		{ -652, 0, 132, w = 52, bank = 4, wl = 10, tags = { "hairpin" } },
		{ -708, 0, 98, w = 52, bank = 6, wl = 10, tags = { "hairpin" } },
		{ -722, 0, 44, w = 52, bank = 6, wl = 10, tags = { "hairpin" } },
		{ -690, 0, 4, w = 54, bank = 4, wl = 10, tags = { "hairpin" } },
		{ -620, 0, -10, w = 60, wl = 6 },
		{ -450, 0, -2, w = 66, sh = 8, wl = 6, wr = 6, tags = { "downtown", "straight" } },
		{ -220, 0, 0, w = 66, sh = 8, wl = 6, wr = 6, tags = { "downtown", "straight", "grid" } },
	},
}

--[[
	Shortcuts: open splines that leave and rejoin the main road. Points with `snap = true`
	take their height from the main road surface. `gaps` are stretches (in the shortcut's own
	distance, as fractions between two of its points) with no surface: you jump them.
	`solid = true` means the shortcut is built on a solid base (walls reach the ground).
]]
ChaosCity.Shortcuts = {
	{
		Id = "RooftopLeap",
		Name = "Rooftop Leap",
		Hint = "Hit the boost pad, ramp onto the parking garage roof and leap the gap. Too slow = the pit.",
		NeedsBoost = true,
		w = 30,
		sh = 2,
		wall = 3,
		points = {
			{ 688, 0, 104, snap = true },
			{ 705, 3, 165 },
			{ 708, 13, 222 },
			{ 706, 24, 285 },
			{ 698, 24, 380 },
			{ 684, 25.5, 452 },
			{ 669, 10, 506 }, -- the landing ramp starts here (gap before it)
			{ 640, 2, 578 },
			{ 600, 0, 612, snap = true },
		},
		gaps = { { from = 6, to = 7 } }, -- between points 6 and 7: the leap
	},
	{
		Id = "NeonAlley",
		Name = "Neon Alley",
		Hint = "A narrow back alley straight through the block: shorter, but dumpsters and slime puddles.",
		NeedsBoost = false,
		w = 24,
		sh = 0,
		wall = 7,
		points = {
			{ -262, 0, 1402, snap = true },
			{ -190, 0, 1399 },
			{ -100, 0, 1397 },
			{ -10, 0, 1394 },
			{ 50, 0, 1386 },
			{ 112, 0, 1352, snap = true },
		},
		obstacles = { -- dumpsters (walls) at { distance fraction, lateral, length, width, height }
			{ 0.28, -6, 10, 8, 6 },
			{ 0.52, 6, 10, 8, 6 },
			{ 0.74, -5, 9, 8, 6 },
		},
		puddles = { -- off-road slime { distance fraction, lateral, length, width }
			{ 0.4, 3, 18, 12 },
			{ 0.63, -3, 18, 12 },
		},
	},
}

-- Checkpoint gates, by main-track control point (1 = start / finish). None may fall inside
-- a shortcut's span (tested), so a shortcut can never skip one.
ChaosCity.Checkpoints = { 1, 3, 10, 12, 14, 16, 18, 20, 22, 24, 26, 33, 35, 37, 39, 41, 43, 45, 47, 50, 53, 55 }

-- Boost pads: { control point, offset along (studs), lateral, length, width }
ChaosCity.BoostPads = {
	{ 2, 0, -14, 16, 12 },
	{ 2, 0, 14, 16, 12 },
	{ 4, 34, 16, 18, 14 }, -- inner lane before the Rooftop Leap branch: take it to make the jump
	{ 12, 0, 0, 16, 14 },
	{ 24, 0, -10, 16, 12 },
	{ 36, -30, 0, 16, 14 }, -- run-up to the Big Jump
	{ 53, 10, 10, 16, 12 },
}

-- Kicker ramps (Jump surface): { control point, offset, lateral, length, width }
ChaosCity.Kickers = {
	{ 37, -4, 0, 14, 50 }, -- THE BIG JUMP: off the hill crest
}

-- Item box rows (Stage 3 places the boxes): { control point, offset, count }
ChaosCity.ItemRows = {
	{ 2, 40, 5 },
	{ 6, 0, 4 },
	{ 13, 0, 4 },
	{ 25, 0, 5 },
	{ 34, 0, 4 },
	{ 40, 0, 5 },
	{ 46, 0, 4 },
}

--[[
	Event interaction zones (Stages 4-5). Each sits on a stretch of the main track (from / to
	control points) and is tagged with what kinds of events can use it. `lanes` splits the
	road across: an event that blocks lanes blocks some of them, never all (EventRules).
	`sky = true` zones have open sky above (meteors, UFOs, flyovers).
]]
ChaosCity.Zones = {
	{ Id = "NeonPlaza", Name = "Neon Plaza", from = 1, to = 3, lanes = 4, tags = { "plaza", "straight", "open", "sky", "downtown" } },
	{ Id = "StartStraight", Name = "Downtown Straight", from = 54, to = 1, lanes = 4, tags = { "straight", "sky", "downtown" } },
	{ Id = "BankedBowl", Name = "Big Banked Bowl", from = 5, to = 9, lanes = 4, tags = { "turn", "banked", "sky", "open" } },
	{ Id = "Rooftops", Name = "Garage Rooftop", from = 5, to = 9, lanes = 2, tags = { "rooftop", "sky", "shortcut" }, shortcut = "RooftopLeap" },
	{ Id = "SkylineHighway", Name = "Skyline Highway", from = 11, to = 14, lanes = 3, tags = { "straight", "highway", "elevated", "sky" } },
	{ Id = "Overpass", Name = "Highway Overpass", from = 14, to = 16, lanes = 3, tags = { "bridge", "elevated", "highway", "sky" } },
	{ Id = "RiverTunnel", Name = "River Tunnel", from = 19, to = 23, lanes = 3, tags = { "tunnel", "enclosed" } },
	{ Id = "Stadium", Name = "Stadium Bulge", from = 27, to = 31, lanes = 3, tags = { "plaza", "stadium", "open", "sky", "turn" } },
	{ Id = "NeonAlley", Name = "Neon Alley", from = 26, to = 32, lanes = 1, tags = { "alley", "shortcut" }, shortcut = "NeonAlley" },
	{ Id = "RiverBridge", Name = "River Bridge", from = 33, to = 35, lanes = 3, tags = { "bridge", "river", "sky", "straight" } },
	{ Id = "BigJump", Name = "Big Jump", from = 36, to = 38, lanes = 3, tags = { "jump", "sky", "air" } },
	{ Id = "Park", Name = "Chaos Park", from = 39, to = 42, lanes = 4, tags = { "park", "open", "straight", "sky" } },
	{ Id = "Chicane", Name = "S-Curve Chicane", from = 43, to = 47, lanes = 3, tags = { "turn", "chicane", "sky" } },
	{ Id = "Hairpin", Name = "Hairpin", from = 48, to = 52, lanes = 3, tags = { "turn", "hairpin", "sky" } },
	{ Id = "Skyline", Name = "Sky Over The City", from = 1, to = 1, lanes = 0, trackWide = true, tags = { "sky", "track-wide", "global" } },
}

-- Ground (Grass, y = -0.2): rectangles { x0, z0, x1, z1 }. The holes between them are the
-- river (z 1010..1090), the tunnel trench (x -550..-460) and the Rooftop Leap pit.
ChaosCity.Floor = {
	{ -1500, -1100, 1500, 455 },
	{ -1500, 455, 600, 525 },
	{ 775, 455, 1500, 525 },
	{ -1500, 525, 1500, 905 },
	{ -1500, 905, -552, 1010 },
	{ -458, 905, 1500, 1010 },
	{ -1500, 1090, -552, 1215 },
	{ -458, 1090, 1500, 1215 },
	{ -1500, 1215, 1500, 2100 },
}
ChaosCity.FloorY = -0.2
ChaosCity.River = { z0 = 1010, z1 = 1090, y = -3.5 }
ChaosCity.Pit = { x0 = 600, z0 = 455, x1 = 775, z1 = 525 }
ChaosCity.KillY = -45

-- The lobby (north of downtown) and the race portal.
ChaosCity.Lobby = { centre = { 0, 0, -760 }, portal = { 0, 0, -665 }, portalRadius = 18 }

-- The starting grid: 12 slots, two columns, staggered, behind the line.
ChaosCity.Grid = { slots = 12, firstRow = 16, rowGap = 15, columnLateral = 13, stagger = 7 }

return ChaosCity
