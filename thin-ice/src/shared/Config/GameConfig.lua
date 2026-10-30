--[[
	GameConfig - every tunable number for THIN ICE in one place.

	Distances are studs, times seconds, rates per second. The lake is a grid of square ice
	tiles (Lake.TileSize) running away from the shore; see LakeGen for the layout rules.
]]

local GameConfig = {}

GameConfig.SchemaVersion = 1
GameConfig.DataStoreName = "ThinIce_Profiles_v1"
GameConfig.LeaderboardStoreName = "ThinIce_Escapes_v1"
GameConfig.AutosaveInterval = 60
GameConfig.MaxPlayers = 6
GameConfig.Leaderboard = { WriteInterval = 120, Refresh = 90 }

---------------------------------------------------------------------------------------------
-- Lake geometry
---------------------------------------------------------------------------------------------

GameConfig.Lake = {
	TileSize = 8,
	Columns = 26, -- 208 studs wide
	RowsPerZone = 10, -- 5 zones -> 50 rows -> 400 studs out from the shore
	ShoreZ = 40, -- the first ice row starts here; the lobby plaza is at Z < ShoreZ
	IceTop = 0.6, -- top surface of a tile (players walk at about Y = 3.6)
	TilesPerStep = 64, -- the lake is built this many tiles per server frame (no long freeze)
	-- Fog thickens the further you walk from the shore (client Atmosphere density, by Z).
	FogNear = 0.3,
	FogFar = 0.56,
}

-- Lobby / shore landmarks (world positions, Y = ground top). The shore is safe: the
-- Antlered never leaves the ice.
GameConfig.Lobby = {
	GroundTop = 0.6,
	Spawn = { 0, -38 },
	Campfire = { -18, 2 },
	Beacon = { 26, 26 },
	Sled = { -32, 28 },
	Hut = { 0, -56 },
	Board = { 34, -24 },
	BankHeight = 14, -- snow cliffs on three sides of the lake (no walking around the ice)
}

GameConfig.Zones = {
	{ Id = "PineShallows", Name = "Pine Shallows", Thin = 0.08, Holes = 0.02, Rocks = 0.04, Drifts = 4, Tint = { 205, 228, 240 } },
	{ Id = "ThinFlats", Name = "Thin Flats", Thin = 0.38, Holes = 0.06, Rocks = 0.02, Drifts = 3, Tint = { 176, 214, 236 } },
	{ Id = "BoulderIsles", Name = "Boulder Isles", Thin = 0.2, Holes = 0.05, Rocks = 0.16, Drifts = 4, Tint = { 190, 220, 236 } },
	{ Id = "WreckBay", Name = "Wreck Bay", Thin = 0.3, Holes = 0.1, Rocks = 0.06, Drifts = 3, Tint = { 160, 200, 228 } },
	-- The far end: black water, ice spires and a half-sunken lighthouse. The Antlered sleeps here.
	{ Id = "DeepHollow", Name = "The Deep Hollow", Thin = 0.34, Holes = 0.13, Rocks = 0.05, Drifts = 3, Tint = { 112, 150, 196 }, Dark = true },
}

---------------------------------------------------------------------------------------------
-- Difficulties (players vote in the lobby; ties go to the easier one)
---------------------------------------------------------------------------------------------

GameConfig.DifficultyOrder = { "Easy", "Normal", "Hard", "Nightmare" }
-- (The lake is ~2x the original; cores, braziers and time limits were scaled so a round
-- still takes 8-11 minutes. MonsterSearch: how much longer it hunts around a lost sound.)
GameConfig.Difficulties = {
	Easy = { Cores = 4, ThinScale = 0.7, HoleScale = 0.6, Braziers = 10, WarmthDrain = 0.7, MonsterSpeed = 15, MonsterHearing = 0.8, MonsterSearch = 1, Grace = 30, TimeLimit = 720, Reward = 1, Color = { 120, 220, 140 } },
	Normal = { Cores = 5, ThinScale = 1, HoleScale = 1, Braziers = 8, WarmthDrain = 1, MonsterSpeed = 17, MonsterHearing = 1, MonsterSearch = 1, Grace = 24, TimeLimit = 660, Reward = 1.4, Color = { 140, 200, 255 } },
	Hard = { Cores = 6, ThinScale = 1.25, HoleScale = 1.3, Braziers = 7, WarmthDrain = 1.2, MonsterSpeed = 19, MonsterHearing = 1.15, MonsterSearch = 1.5, Grace = 18, TimeLimit = 630, Reward = 2, Color = { 255, 170, 90 } },
	Nightmare = { Cores = 7, ThinScale = 1.5, HoleScale = 1.6, Braziers = 6, WarmthDrain = 1.4, MonsterSpeed = 21, MonsterHearing = 1.3, MonsterSearch = 2, Grace = 14, TimeLimit = 600, Reward = 3, Color = { 255, 90, 110 } },
}

---------------------------------------------------------------------------------------------
-- Round flow
---------------------------------------------------------------------------------------------

GameConfig.Round = {
	Countdown = 8, -- after everyone in the lobby is ready (or MinReady + timeout)
	ReadyTimeout = 25, -- once someone is ready, start this long after even if others aren't
	SledWait = 60, -- after the last core is in, the sled waits this long (horn at 10 s)
	SledHornAt = 10,
	ResultsTime = 9,
	BeaconRadius = 14, -- deliver a core by walking within this distance of the beacon
	SledRadius = 10,
	ChipTime = 3, -- hold the prompt this long to chip a core out of its ice (LOUD)
	PickupTime = 0.6, -- picking up a dropped core
}

---------------------------------------------------------------------------------------------
-- Movement, stamina, warmth
---------------------------------------------------------------------------------------------

GameConfig.Move = {
	Sneak = 8,
	Walk = 14,
	Sprint = 22,
	CarryMultiplier = 0.85,
	WaterSpeed = 6,
	-- Anti-speed: a flat move longer than (allowed speed * Tolerance * window + Slack) over
	-- a check window is snapped back. Slack is a flat allowance in studs (not per second):
	-- position updates from a laggy client arrive in bursts, so one window can hold ~0.5 s
	-- of extra travel, and a short window must not punish that.
	Tolerance = 1.35,
	Slack = 8,
	TeleportGrace = 0.75, -- after a server move (climb-out, thaw, snap) the client's stale positions are ignored this long
}

GameConfig.Stamina = {
	Max = 100,
	SprintDrain = 22,
	Regen = 14,
	RegenDelay = 0.8,
	RecoverTo = 35, -- once exhausted, no sprinting until stamina is back to this
}

GameConfig.Warmth = {
	Max = 100,
	IceDrain = 1.3, -- per second on the ice (scaled by difficulty)
	WaterDrain = 11,
	GustDrain = 1.6,
	FireWarmth = 14,
	FireRadius = 14,
	ShoreRegen = 6,
	ThawTo = 35,
	ThawHold = 3, -- seconds a friend holds the thaw prompt
	FrozenLostAfter = 45, -- frozen this long = lost for the run
	FlaskDelay = 8, -- Thermos Flask self-thaw after this long frozen (once per run)
	ClimbOutTime = 2.5, -- in the water this long, then you haul yourself onto the nearest ice
	ThawDistance = 10, -- a rescuer must be this close to the ice block
}

---------------------------------------------------------------------------------------------
-- Ice
---------------------------------------------------------------------------------------------

GameConfig.Ice = {
	-- Strength by thickness (1 = thin, 2 = normal, 3 = thick). Stress builds while someone
	-- stands on a tile and breaks it at 100% of its strength.
	Strength = { [1] = 26, [2] = 70, [3] = 170 },
	Stress = { Idle = 1.2, Sneak = 2.2, Walk = 6, Sprint = 17, Carry = 6 },
	Recover = 3, -- per second when nobody stands on it
	CrackAt = 0.5, -- visible cracks + a crack noise at this fraction
	RefreezeAfter = 40, -- a broken tile freezes over again (thin) after this long
}

---------------------------------------------------------------------------------------------
-- Snowballs
---------------------------------------------------------------------------------------------

GameConfig.Snowball = {
	Max = 5,
	Start = 3,
	Range = 46,
	MinRange = 12,
	Cooldown = 0.6,
	DriftRefillCooldown = 8,
}

---------------------------------------------------------------------------------------------
-- Noise and hearing
---------------------------------------------------------------------------------------------

GameConfig.Noise = {
	Categories = {
		StepSneak = { Loudness = 0.08, Radius = 10 },
		StepWalk = { Loudness = 0.35, Radius = 34 },
		StepSprint = { Loudness = 0.8, Radius = 64 },
		Crack = { Loudness = 0.7, Radius = 52 },
		Splash = { Loudness = 1, Radius = 80 },
		Chip = { Loudness = 0.85, Radius = 60 },
		Snowball = { Loudness = 1, Radius = 58 },
		Deliver = { Loudness = 0.6, Radius = 60 },
		Thaw = { Loudness = 0.5, Radius = 40 },
	},
	StepInterval = { StepSneak = 0.7, StepWalk = 0.45, StepSprint = 0.3 },
	HearThreshold = 0.12,
	HuntThreshold = 0.55,
	GustHearing = 0.5, -- whiteouts halve what it hears
}

---------------------------------------------------------------------------------------------
-- The monster ("the Antlered" - blind, hunts by sound)
---------------------------------------------------------------------------------------------

GameConfig.Monster = {
	ProwlSpeed = 7,
	InvestigateSpeed = 12,
	-- Hunt speed comes from the difficulty.
	CatchRadius = 4.5,
	FeelRadius = 7, -- it feels footsteps through the ice this close, even sneaking (not standing still)
	InvestigateTime = 6,
	SearchTime = 9,
	RecoverTime = 4,
	ListenPause = 2.2,
	StepInterval = 0.12, -- how often it listens / decides (it moves every frame)
	ReplanInterval = 0.5, -- it re-plans its path over the ice at most this often (never per frame)
	TrailLength = 24, -- tiles of cracked ice it leaves behind (cosmetic)
	StuckTime = 10, -- awake but hasn't got 1.5 tiles from where it was in this long: it dives and resurfaces elsewhere
}

-- Whiteouts: a blizzard drops visibility hard for 15-20 s. It hears less, but it moves faster.
GameConfig.Weather = {
	CalmMin = 70,
	CalmMax = 110,
	WhiteoutMin = 15,
	WhiteoutMax = 20,
	WhiteoutSpeed = 1.3, -- the Antlered's speed multiplier during a whiteout
}

-- Client-side dread: what you hear / see of the Antlered by distance (see shared/Presence).
GameConfig.Presence = {
	FarCall = 70, -- beyond this: an occasional distant call
	CallGapMin = 18,
	CallGapMax = 34,
	Near = 35, -- breathing and crunching footsteps
	Heartbeat = 30, -- heartbeat + frost vignette
	SilhouetteMin = 55, -- glimpse its outline through the fog between these distances
	SilhouetteMax = 120,
	SilhouetteGap = 25,
	ScareGraceTime = 60, -- no ambient scares in a round's first minute
	ScareGapMin = 40,
	ScareGapMax = 75,
}

---------------------------------------------------------------------------------------------
-- Rewards / progression
---------------------------------------------------------------------------------------------

GameConfig.Rewards = {
	Played = 20,
	PerCore = 30,
	PerRescue = 25,
	Escaped = 80,
	XpPerCoin = 1,
	VipBonus = 0.1,
}

GameConfig.DailyRewards = { 50, 75, 100, 125, 150, 200, 300 }

GameConfig.Codes = {
	THINICE = { Coins = 150 },
	ANTLERS = { Coins = 100, Flask = 1 },
	COLDFEET = { Coins = 75 },
}

GameConfig.Goals = {
	{ Id = "Deliver", Text = "Deliver a frozen core", Stat = "Cores", Target = 1, Coins = 40 },
	{ Id = "Rescue", Text = "Thaw a frozen friend", Stat = "Rescues", Target = 1, Coins = 40 },
	{ Id = "Lure", Text = "Throw 5 snowballs", Stat = "Snowballs", Target = 5, Coins = 25 },
	{ Id = "Escape", Text = "Escape on the sled", Stat = "Escapes", Target = 1, Coins = 60 },
}

return GameConfig
