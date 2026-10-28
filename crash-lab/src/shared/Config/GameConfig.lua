--[[
	GameConfig - global tuning: data stores, save cadence, run limits and the arena frame.
	Everything gameplay-related lives in the other Config modules.
]]

return {
	SchemaVersion = 1,
	DataStoreName = "CrashLab_Profiles_v1",
	LeaderboardScoreStore = "CrashLab_BestScore_v1",
	LeaderboardDistanceStore = "CrashLab_BestDistance_v1",
	AutosaveInterval = 60,
	LeaderboardWriteInterval = 120,
	LeaderboardRefresh = 75,

	-- Run limits (server-enforced).
	Run = {
		SampleRate = 12, -- samples per second the server takes of the dummy's position
		MaxDuration = 22, -- hard time limit for a run (seconds)
		SettleSpeed = 4, -- studs/s: below this the dummy counts as "still"
		SettleTime = 1.4, -- still for this long = run over
		MinAirTime = 0.8, -- settle detection only after this long
		StuckWindow = 4, -- if the dummy moved < StuckDistance in this window it is stuck
		StuckDistance = 1.5,
		AnomalyLimit = 3, -- impossible samples before a run is voided
		CleanupDelay = 1.2, -- dummy stays visible this long after the run ends
	},

	-- The arena: launch line at Z = LaunchZ, the course runs toward +Z.
	Arena = {
		LaunchZ = 0,
		FloorY = 0,
		Length = 540, -- the far catch net sits here
		HalfWidth = 78, -- side nets
		Ceiling = 320, -- anything above this is out of bounds (top Air Cannon arc peaks ~251)
		KillY = -40,
		LobbyZ = -90, -- lobby centre (behind the launch line)
	},

	PadCount = 6,
	PadSpacing = 18,
}
