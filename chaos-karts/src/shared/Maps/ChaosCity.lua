--[[
	CHAOS CITY - the Stage 1 track. Pure data: TrackMath turns it into the racing line,
	MapData compiles the gameplay data (checkpoints, grid, pads, zones), the TrackBuilder
	builds the parts and TrackQuery answers "where is the ground" for bots and the harness.

	Plan (x east, z south; the layout was drawn at 1:1.15 and scaled so a clean lap at
	racing pace lands in the 80-95 s window; the lap runs clockwise on the minimap):
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
	minY = 0, -- the road never dips below the ground...
	minYExempt = { "tunnel" }, -- ...except in the river tunnel
	defaults = { w = 56, sh = 7, wl = 4, wr = 4, bank = 0 },
	points = {
		-- Downtown straight (heading east). Point 1 is the finish line.
		{ 0, 0, 0, w = 66, sh = 8, wl = 6, wr = 6, tags = { "finish", "downtown", "straight" } },
		{ 230, 0, 0, w = 66, sh = 8, wl = 6, wr = 4, tags = { "downtown", "straight", "plaza" } },
		{ 460, 0, 3, w = 62, wl = 6, tags = { "downtown", "straight" } },
		-- The Big Banked Bowl (right-hand U-turn, banked up to 22 degrees; banking pivots
	-- around the low inside edge, so the outside rises ~28 studs)
		{ 656, 0, 28, w = 60, bank = 6, wl = 9, tags = { "banked" } },
		{ 805, 0, 110, w = 60, bank = 14, wl = 10, tags = { "banked" } },
		{ 903, 0, 248, w = 62, bank = 20, wl = 11, tags = { "banked" } },
		{ 929, 0, 398, w = 62, bank = 22, wl = 11, tags = { "banked" } },
		{ 892, 0, 547, w = 62, bank = 20, wl = 11, tags = { "banked" } },
		{ 789, 0, 662, w = 60, bank = 14, wl = 10, tags = { "banked" } },
		{ 644, 0, 729, w = 60, bank = 5, wl = 8 },
		-- Skyline Highway (heading west, climbing to 40 studs)
		{ 483, 2, 754, w = 56, sh = 4, wl = 6, wr = 6, tags = { "highway" } },
		{ 345, 16, 777, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ 195, 32, 800, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ 46, 40, 812, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated", "overpass" } },
		{ -126, 40, 820, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ -299, 34, 837, w = 56, sh = 3, wl = 6, wr = 6, tags = { "highway", "elevated" } },
		{ -443, 21, 903, w = 56, sh = 3, bank = -6, wl = 6, wr = 9, tags = { "highway", "elevated" } },
		{ -540, 6, 1000, w = 54, sh = 3, bank = -6, wl = 6, wr = 9, tags = { "highway" } },
		-- River Tunnel (dives under the river)
		{ -575, -6, 1087, w = 52, sh = 3, wl = 10, wr = 10, tags = { "tunnel" } },
		{ -583, -18, 1150, w = 50, sh = 3, wl = 20, wr = 20, tags = { "tunnel" } },
		{ -584, -25, 1208, w = 50, sh = 3, wl = 27, wr = 27, tags = { "tunnel" } },
		{ -580, -18, 1265, w = 50, sh = 3, wl = 20, wr = 20, tags = { "tunnel" } },
		{ -572, -6, 1334, w = 52, sh = 3, wl = 10, wr = 10, tags = { "tunnel" } },
		{ -554, 0, 1426, w = 56, wr = 8 },
		-- South side: left turn, then the stadium bulge (Neon Alley cuts across it)
		{ -506, 0, 1529, w = 58, bank = -6, wr = 9 },
		{ -414, 0, 1602, w = 58, bank = -3 },
		{ -301, 0, 1615, w = 58 },
		{ -209, 0, 1667, w = 56, bank = 5, wl = 8, tags = { "stadium" } },
		{ -126, 0, 1759, w = 56, bank = 3, wl = 8, tags = { "stadium" } },
		{ -23, 0, 1777, w = 56, wr = 8, tags = { "stadium" } },
		{ 57, 0, 1702, w = 56, bank = -5, wr = 8, tags = { "stadium" } },
		{ 110, 0, 1615, w = 56, bank = -3 },
		{ 159, 0, 1483, w = 54 },
		-- North leg: river bridge, hill crest jump, under the highway
		{ 172, 4, 1346, w = 52, sh = 4, wl = 6, wr = 6, tags = { "bridge" } },
		{ 175, 8, 1208, w = 52, sh = 3, wl = 6, wr = 6, tags = { "bridge" } },
		{ 171, 4, 1098, w = 52, sh = 4, wl = 6, wr = 6, tags = { "bridge" } },
		{ 162, 11, 1041, w = 54, wl = 6, wr = 6, tags = { "hill" } },
		{ 153, 18, 991, w = 56, wl = 6, wr = 6, tags = { "jump" } },
		{ 140, 6, 908, w = 58, tags = { "hill" } },
		{ 126, 0, 822, w = 56, tags = { "underpass" } },
		{ 113, 0, 690, w = 56, tags = { "park" } },
		{ 86, 0, 523, w = 56, tags = { "park" } },
		{ 23, 0, 398, w = 56, bank = -4, wr = 8 },
		{ -103, 0, 345, w = 56 },
		-- S-curve chicane (left-right-left)
		{ -230, 0, 324, w = 54, bank = 3, tags = { "chicane" } },
		{ -334, 0, 359, w = 54, bank = -3, tags = { "chicane" } },
		{ -443, 0, 308, w = 54, bank = 3, tags = { "chicane" } },
		{ -552, 0, 202, w = 56 },
		{ -667, 0, 159, w = 56 },
		-- Hairpin (tight right-hander), then onto the straight
		{ -750, 0, 152, w = 52, bank = 4, wl = 10, tags = { "hairpin" } },
		{ -814, 0, 113, w = 52, bank = 6, wl = 10, tags = { "hairpin" } },
		{ -830, 0, 51, w = 52, bank = 6, wl = 10, tags = { "hairpin" } },
		{ -793, 0, 5, w = 54, bank = 4, wl = 10, tags = { "hairpin" } },
		{ -713, 0, -12, w = 60, wl = 6 },
		{ -518, 0, -2, w = 66, sh = 8, wl = 6, wr = 6, tags = { "downtown", "straight" } },
		{ -253, 0, 0, w = 66, sh = 8, wl = 6, wr = 6, tags = { "downtown", "straight", "grid" } },
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
		Hint = "Ramp onto the parking garage roof and leap the gap - with a boost (a mini-turbo released on the roof, or a Speed Boost item). Too slow = the pit.",
		NeedsBoost = true,
		w = 30,
		sh = 2,
		wall = 3,
		points = {
			{ 791, 0, 120, snap = true },
			{ 811, 3, 190 },
			{ 814, 13, 255 },
			{ 812, 24, 328 },
			{ 803, 24, 437 },
			{ 787, 25.5, 520 },
			{ 772, 10, 568 }, -- the landing ramp starts here (gap before it)
			{ 736, 2, 665 },
			{ 690, 0, 704, snap = true },
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
			{ -301, 0, 1612, snap = true },
			{ -218, 0, 1609 },
			{ -115, 0, 1607 },
			{ -12, 0, 1603 },
			{ 57, 0, 1594 },
			{ 129, 0, 1555, snap = true },
		},
		obstacles = { -- dumpsters (walls) at { distance fraction, lateral, length, width, height }
			{ 0.28, -6, 11, 8, 6 },
			{ 0.52, 6, 11, 8, 6 },
			{ 0.74, -5, 10, 8, 6 },
		},
		puddles = { -- off-road slime { distance fraction, lateral, length, width }
			{ 0.4, 3, 22, 13 },
			{ 0.63, -3, 22, 13 },
		},
	},
}

-- Checkpoint gates, by main-track control point (1 = start / finish). None may fall inside
-- a shortcut's span (tested), so a shortcut can never skip one.
ChaosCity.Checkpoints = { 1, 3, 10, 12, 14, 16, 18, 20, 22, 24, 26, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56 }

-- Boost pads: { control point, offset along (studs), lateral, length, width }
ChaosCity.BoostPads = {
	{ 2, 0, -15, 18, 13 },
	{ 2, 0, 15, 18, 13 },
	{ 4, 40, 17, 20, 14 }, -- inner lane before the Rooftop Leap branch: take it to make the jump
	{ 12, 0, 0, 18, 14 },
	{ 24, 0, -11, 18, 13 },
	{ 37, -30, 0, 18, 14 }, -- run-up to the Big Jump
	{ 54, 12, 11, 18, 13 }, -- hairpin exit
}

-- Kicker ramps (Jump surface): { control point, offset, lateral, length, width }
ChaosCity.Kickers = {
	{ 38, -4, 0, 16, 52 }, -- THE BIG JUMP: off the hill crest
}

-- Item box rows (Stage 3 places the boxes): { control point, offset, count }
ChaosCity.ItemRows = {
	{ 2, 46, 5 },
	{ 6, 0, 4 },
	{ 13, 0, 4 },
	{ 25, 0, 5 },
	{ 35, 0, 4 },
	{ 41, 0, 5 },
	{ 47, 0, 4 },
}

--[[
	Event interaction zones (Stages 4-5). Each sits on a stretch of the main track (from / to
	control points) and is tagged with what kinds of events can use it. `lanes` splits the
	road across: an event that blocks lanes blocks some of them, never all (EventRules).
	`sky = true` zones have open sky above (meteors, UFOs, flyovers).
]]
ChaosCity.Zones = {
	{ Id = "NeonPlaza", Name = "Neon Plaza", from = 1, to = 3, lanes = 4, tags = { "plaza", "straight", "open", "sky", "downtown" } },
	{ Id = "StartStraight", Name = "Downtown Straight", from = 55, to = 1, lanes = 4, tags = { "straight", "sky", "downtown" } },
	{ Id = "BankedBowl", Name = "Big Banked Bowl", from = 5, to = 9, lanes = 4, tags = { "turn", "banked", "sky", "open" } },
	{ Id = "Rooftops", Name = "Garage Rooftop", from = 5, to = 9, lanes = 2, tags = { "rooftop", "sky", "shortcut" }, shortcut = "RooftopLeap" },
	{ Id = "SkylineHighway", Name = "Skyline Highway", from = 11, to = 14, lanes = 3, tags = { "straight", "highway", "elevated", "sky" } },
	{ Id = "Overpass", Name = "Highway Overpass", from = 14, to = 16, lanes = 3, tags = { "bridge", "elevated", "highway", "sky" } },
	{ Id = "RiverTunnel", Name = "River Tunnel", from = 19, to = 23, lanes = 3, tags = { "tunnel", "enclosed" } },
	{ Id = "Stadium", Name = "Stadium Bulge", from = 28, to = 32, lanes = 3, tags = { "plaza", "stadium", "open", "sky", "turn" } },
	{ Id = "NeonAlley", Name = "Neon Alley", from = 27, to = 33, lanes = 1, tags = { "alley", "shortcut" }, shortcut = "NeonAlley" },
	{ Id = "RiverBridge", Name = "River Bridge", from = 34, to = 36, lanes = 3, tags = { "bridge", "river", "sky", "straight" } },
	{ Id = "BigJump", Name = "Big Jump", from = 37, to = 39, lanes = 3, tags = { "jump", "sky", "air" } },
	{ Id = "Park", Name = "Chaos Park", from = 40, to = 43, lanes = 4, tags = { "park", "open", "straight", "sky" } },
	{ Id = "Chicane", Name = "S-Curve Chicane", from = 44, to = 48, lanes = 3, tags = { "turn", "chicane", "sky" } },
	{ Id = "Hairpin", Name = "Hairpin", from = 49, to = 53, lanes = 3, tags = { "turn", "hairpin", "sky" } },
	{ Id = "Skyline", Name = "Sky Over The City", from = 1, to = 1, lanes = 0, trackWide = true, tags = { "sky", "track-wide", "global" } },
}

-- Ground (Grass, y = -0.2): rectangles { x0, z0, x1, z1 }. The holes between them are the
-- river (z 1010..1090), the tunnel trench (x -550..-460) and the Rooftop Leap pit.
ChaosCity.Floor = {
	{ -1725, -1265, 1725, 523 },
	{ -1725, 523, 690, 604 },
	{ 891, 523, 1725, 604 },
	{ -1725, 604, 1725, 1041 },
	{ -1725, 1041, -635, 1162 },
	{ -527, 1041, 1725, 1162 },
	{ -1725, 1254, -635, 1397 },
	{ -527, 1254, 1725, 1397 },
	{ -1725, 1397, 1725, 2415 },
}
ChaosCity.FloorY = -0.2
ChaosCity.River = { z0 = 1162, z1 = 1254, y = -3.5 }
ChaosCity.Pit = { x0 = 690, z0 = 523, x1 = 891, z1 = 604 }
ChaosCity.KillY = -45

-- The lobby (north of downtown) and the race portal.
ChaosCity.Lobby = { centre = { 0, 0, -874 }, portal = { 0, 0, -765 }, portalRadius = 18 }

-- The starting grid: 12 slots, two columns, staggered, behind the line.
ChaosCity.Grid = { slots = 12, firstRow = 16, rowGap = 15, columnLateral = 13, stagger = 7 }

return ChaosCity
