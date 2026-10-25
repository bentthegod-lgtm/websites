--[[
	Core tuning for PHONES AWAY! Round timing, store names, classroom layout.
	All times are seconds, all distances studs.
]]

return {
	SchemaVersion = 1,
	DataStoreName = "PhonesAway_Profiles_v1",
	LeaderboardStoreName = "PhonesAway_TotalClout_v1",
	AutosaveInterval = 90,

	MaxPlayers = 12,

	-- Round flow: Hallway (intermission) -> Bell (find your seat) -> Class -> Results -> Hallway
	HallwaySeconds = 20,
	HallwaySecondsSolo = 12,
	BellSeconds = 5,
	ClassSeconds = 200, -- 3:20 of class (the wall clock shows 10:05 -> 10:55)
	ResultsSeconds = 9,
	TickRate = 10, -- detection / teacher updates per second

	-- The fake school time shown on the wall clock and HUD (minutes after midnight).
	SchoolClockStart = 10 * 60 + 5,
	SchoolClockEnd = 10 * 60 + 55,

	-- Classroom layout (classroom centred on the origin; the board is on the -Z wall).
	Classroom = {
		Origin = { 0, 0, 0 },
		Width = 60, -- X
		Depth = 50, -- Z
		WallHeight = 16,
		DeskColumns = { -15, -5, 5, 15 },
		DeskRows = { -6, 4, 14 }, -- front, middle, back
		BoardSpot = { 0, -19 }, -- where the teacher writes
		LectureSpot = { 0, -15 },
		DoorSpot = { 27, 18 },
		Aisles = { -10, 0, 10 },
		FrontAisleZ = -13,
		BackAisleZ = 20,
		DetentionDesk = { -25, 19 },
		HallwayX = 38, -- centre line of the hallway (outside the door)
	},

	-- Detention
	DetentionBailBase = 60, -- Clout cost to buy your way back (scales with level)
	DetentionBailPerLevel = 6,
	DetentionReturnSuspicion = 0.45,
	DetentionPhoneCooldown = 8,
	CatchPendingLoss = 0.5, -- caught: lose this share of the Clout earned this class

	-- Teacher's Pet
	Pet = {
		MaxReports = 3,
		Cooldown = 20,
		SuspicionAdded = 0.22,
		FalseReportPenalty = 0.15, -- the tattletale gets the stink eye instead
		Reward = 6,
		QuizBonus = 0.25,
	},

	-- Paper airplane / notes
	Plane = { Cooldown = 18, MaxPerClass = 3, DistractSeconds = 3.2, ThrowSeenSuspicion = 0.3, Reward = 2 },
	Note = { Cooldown = 15, MaxPerClass = 4, Reward = 8, Noise = 0.35 },

	-- Pop quiz
	Quiz = { Seconds = 9, Reward = 25, XP = 20, WrongSuspicion = 0.18 },

	-- Pizza Party (developer product): queued rounds are capped.
	PizzaMaxQueued = 3,
	PizzaCloutMultiplier = 2,
	PizzaDetectionMultiplier = 0.5,
}
