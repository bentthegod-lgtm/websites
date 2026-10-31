--[[
	GameConfig - every gameplay number in CHAOS KARTS that isn't kart physics (those live in
	KartStats and are identical for every kart).

	CONTENT TARGETS for the full game (Stage 1 builds the core; see README roadmap):
	  25 vehicles (cosmetic only), 12 power-ups, 35 world events (25 brainrot / 5 fiction-
	  style / 5 disasters), 4 maps.
]]

local GameConfig = {}

GameConfig.GameName = "CHAOS KARTS"
GameConfig.SchemaVersion = 1
GameConfig.DataStoreName = "ChaosKarts_Profiles_v1"
GameConfig.AutosaveInterval = 90
GameConfig.MaxPlayers = 12

GameConfig.ContentTargets = {
	Vehicles = 25,
	PowerUps = 12,
	Events = 35,
	EventSplit = { Brainrot = 25, Fiction = 5, Disaster = 5 },
	Maps = 4,
}

GameConfig.Stage = 1
GameConfig.Roadmap = {
	{ Stage = 1, Title = "Core race, driving, Chaos City, Event Director architecture" },
	{ Stage = 2, Title = "All 25 vehicles (cosmetic, identical physics)" },
	{ Stage = 3, Title = "All 12 power-ups with position-weighted item rolls" },
	{ Stage = 4, Title = "World events, part 1 (brainrot / meme events)" },
	{ Stage = 5, Title = "World events, part 2 (fiction-style and disasters); all 35 live" },
	{ Stage = 6, Title = "Maps: Supermarket, Volcano Island, Space Madness" },
	{ Stage = 7, Title = "Polish and the cosmetic shop" },
}

GameConfig.Race = {
	Map = "ChaosCity",
	Laps = 3,
	MaxRacers = 12,
	MinToStart = 1,
	AutoStartAfter = 20, -- seconds after the first player readies up
	IntroTime = 3, -- grid flyover before the lights
	CountdownTime = 3, -- 3-2-1-GO
	DnfTimer = 30, -- after the first finisher
	ResultsTime = 12,
	MaxRaceTime = 600, -- a hard cap (10 min) so a race always ends
	OrbitTime = 6, -- finish camera orbit
	SpectatorsJoinNext = true,
}

GameConfig.Bots = {
	Enabled = true, -- fill empty grid slots so a solo player still races a full field
	FillTo = 8, -- grid size with bots (>= 6)
	Names = { "Turbo Tortellini", "Captain Bumper", "Sir Skids-a-Lot", "Nitro Noodle", "Wobble Wizard", "Drift Goblin", "Zoomer Zed", "Pixel Pickle", "Mega Mango", "Rusty Rocket", "Bloop Bot", "Chaos Cadet" },
	Colors = { { 255, 92, 92 }, { 92, 170, 255 }, { 255, 210, 70 }, { 120, 230, 120 }, { 200, 120, 255 }, { 255, 150, 60 }, { 80, 220, 220 }, { 255, 120, 200 }, { 180, 180, 190 }, { 140, 255, 180 }, { 255, 255, 255 }, { 120, 120, 255 } },
}

GameConfig.Net = {
	SendRate = 20, -- client kart state updates per second
	BroadcastRate = 15, -- server kart snapshots per second
	InterpDelay = 0.1, -- remote karts render this far in the past (buffered)
	StateRateLimit = 40, -- max accepted client updates per second (burst-tolerant)
}

GameConfig.AntiCheat = {
	SpeedSlack = 1.25, -- the travel budget refills at MaxLegalSpeed * slack (+ flat slack once)
	FlatSlack = 14,
	MaxDt = 0.6, -- the speed budget banks at most this many seconds of travel (lag-spike bursts)
	StrikesBeforeTeleport = 1, -- an impossible move is rejected and teleported back
	RespawnCooldown = 2.5, -- seconds between respawn requests
	VerticalSlack = 60,
}

GameConfig.Respawn = {
	AutoBelowY = -40, -- (also KillY of the map)
	StuckTime = 3, -- holding gas but not moving
	OffCourseTime = 2.5, -- on the grass with no road under you (e.g. fell off the rooftop)
	WrongWayTime = 1.2, -- seconds moving backwards before WRONG WAY shows
}

GameConfig.Rewards = {
	Places = { 120, 90, 70, 55, 45, 40, 35, 30, 26, 22, 20, 18 },
	Participation = 15,
	ParticipationXP = 20,
	XPBase = 40,
	XPPerBeaten = 10,
	WinXP = 60,
	FinishBonus = 10,
	BestLapBonus = 25, -- a new personal best lap
}

-- XP needed for level L+1 = Base + Step * L
GameConfig.Levels = { Base = 100, Step = 40, Max = 200 }

GameConfig.DailyRewards = { 50, 75, 100, 125, 150, 200, 300 }

GameConfig.Codes = {
	RELEASE = { Coins = 250 },
	CHAOS = { Coins = 150, XP = 50 },
}

GameConfig.Leaderboard = {
	Rows = 10,
	Refresh = 60,
	WriteInterval = 120,
	Stores = { Wins = "ChaosKarts_Wins_v1", BestLap = "ChaosKarts_BestLap_ChaosCity_v1" },
}

--[[
	Event Director. Interval = seconds between event attempts. FINAL LAP: intervals x0.55,
	cooldowns x0.6, intensity-3 events weighted x2.5 (and unlocked by their minLap) - still
	inside the same budget, conflict and lane rules.
]]
GameConfig.Events = {
	Enabled = true,
	GraceSeconds = 15, -- no events right after GO
	Interval = 26,
	FinalLapIntervalMul = 0.55,
	DefaultCooldown = 60,
	FinalLapCooldownMul = 0.6,
	Intensity3NormalMul = 0.5,
	FinalLapIntensity3Mul = 2.5,
	MaxMajor = 1, -- intensity >= 2 at once
	MaxMinor = 1, -- intensity 1 at once
	ExclusiveTags = { "blocks-lane", "screen-effect" },
	OneEventPerZone = true,
	HardTimeoutSlack = 5, -- an instance is force-cleaned this long after its planned end
	HitCooldown = 1.5, -- seconds before the same event can hit the same kart again
}

GameConfig.Effects = {
	-- KartEffects the server can apply (never an elimination)
	Allowed = { "spinOut", "slow", "launch", "freeze", "knockback", "respawnToCheckpoint" },
	PerKindCooldown = 0.8,
	SpeedSlackTime = 2.5, -- the anti-cheat allows extra speed this long after an effect
}

GameConfig.Camera = {
	Distance = 15,
	Height = 5.6,
	LookAhead = 0.32, -- rad of yaw look into turns at full steer
	Smooth = 9,
	BaseFov = 70,
	BoostFov = 84,
	SpeedFov = 6, -- extra FOV at top speed
	ShakeLand = 0.5,
	ShakeWall = 0.7,
}

GameConfig.Effects.TireMarks = { Max = 140, Life = 6, Every = 0.05 }
GameConfig.Effects.DriftColors = {
	{ 90, 170, 255 }, -- level 1 blue
	{ 255, 150, 40 }, -- level 2 orange
	{ 200, 90, 255 }, -- level 3 purple
}

return GameConfig
