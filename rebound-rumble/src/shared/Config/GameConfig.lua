--[[
	Core match tuning: lobby flow, the ball, parry timing, bots.
	Every value here is read by the server; the client only uses it for visuals/HUD.
]]

return {
	DataStoreName = "ReboundRumble_Profiles_v1",
	LeaderboardStoreName = "ReboundRumble_Wins_v1",
	SchemaVersion = 2,
	AutosaveInterval = 90,

	Lobby = {
		-- Seconds of countdown once enough players are ready.
		Countdown = 15,
		-- Shorter countdown once a real 2+ player lobby is ready.
		CountdownFull = 10,
		-- Humans needed to start without bots. With fewer, bots fill in (solo allowed).
		MinHumans = 2,
		AllowSoloWithBots = true,
		-- Bots fill a match up to this many contestants when the server is near-empty.
		FillToContestants = 5,
		MaxContestants = 16,
		-- Pause on the results banner before players are returned to the lobby.
		ResultsSeconds = 6,
	},

	Ball = {
		BaseSpeed = 42, -- studs/s on spawn
		-- After each deflect: speed = speed * DeflectMultiplier + DeflectAdd (capped).
		DeflectMultiplier = 1.07,
		DeflectAdd = 4,
		MaxSpeed = 300,
		-- Homing: max turn rate (radians/s) grows with speed so fast balls still connect.
		TurnRate = 2.6,
		TurnRatePerSpeed = 0.022,
		-- Close to the target the ball turns harder (no endless orbits).
		CloseTurnBoost = 3,
		CloseDistance = 18,
		-- Upper bound on the turning circle radius (studs) so fast balls never orbit.
		MaxTurnRadius = 14,
		-- A deflected ball first flies in the aim direction, then curves: lower = wider arc.
		CurveDelay = 0.12,
		HitRadius = 3.6,
		SpawnHeight = 22,
		SpawnPause = 1.6, -- charging time before the first target
		RespawnDelay = 1.8, -- after an elimination
		-- Overtime: after this many seconds in a round, the ball speeds up on its own.
		OvertimeAfter = 100,
		OvertimeAccel = 6, -- studs/s gained per second during overtime
		SyncRate = 15, -- server -> client ball state updates per second
		HistorySeconds = 1.0,
	},

	Parry = {
		-- Base reach of a parry (studs); the reach grows with ball speed so the timing window
		-- stays around WindowSeconds wide in time.
		BaseRange = 9,
		WindowSeconds = 0.22,
		MaxRange = 70,
		-- Lag compensation: how far back in time a client's timestamp may rewind the ball.
		MaxRewind = 0.25,
		-- Timestamps from the future beyond this are treated as "now".
		FutureTolerance = 0.05,
		-- When the ball reaches its target the server waits this long for in-flight parries.
		HitGrace = 0.12,
		-- Cooldowns (seconds). A whiff (early press or pressing while not targeted) locks
		-- you out much longer than a clean parry, so spamming fails.
		SuccessCooldown = 0.25,
		WhiffCooldown = 0.9,
		-- Server rate limit for the remote itself.
		MinInterval = 0.08,
		-- Target picking: candidates inside this cone (dot product) of the camera aim are
		-- preferred; otherwise the closest-to-aim player is used.
		AimConeDot = 0.55,
	},

	Bots = {
		Names = { "Volt", "Pixel", "Nova", "Blitz", "Echo", "Rook", "Zephyr", "Comet", "Jinx", "Orbit", "Flux", "Kite" },
		-- Skill 0..1 is drawn per bot from this range.
		SkillMin = 0.55,
		SkillMax = 0.9,
		-- Success chance = skill - SpeedPenalty * (speed - BaseSpeed) / 100, clamped.
		SpeedPenalty = 0.11,
		MinChance = 0.08,
		MaxChance = 0.97,
		-- Bots "react" at a random fraction of their parry range.
		ReactMin = 0.35,
		ReactMax = 0.9,
		WalkSpeed = 18,
		Label = "[BOT]",
	},

	-- Kill-streak call-outs inside a single round.
	KillStreakNames = { [2] = "DOUBLE DEFLECT", [3] = "TRIPLE THREAT", [4] = "RAMPAGE", [5] = "UNSTOPPABLE", [6] = "GODLIKE" },
	-- Win-streak call-outs, announced server-wide.
	WinStreakAnnounceFrom = 2,
}
