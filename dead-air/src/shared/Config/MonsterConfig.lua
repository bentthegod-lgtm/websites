--[[
	THE LISTENER - behaviour tuning. Speeds are studs/second (players walk at 10,
	sprint at 19). Difficulty multipliers in DifficultyConfig scale many of these.
]]

return {
	Name = "The Listener",
	TickRate = 0.1, -- AI decision interval (seconds)

	Speeds = {
		Patrol = 8,
		Search = 9,
		Suspicion = 3.5,
		InvestigateLow = 10,
		InvestigateMid = 14,
		InvestigateHigh = 19, -- "rush": strong or repeated noise
		Lost = 15,
		Chase = 19.5,
		ChaseStart = 12, -- chase speed ramps from here...
		ChaseRampTime = 1.8, -- ...to Chase over this many seconds
	},
	Acceleration = 14, -- studs/s^2 toward the desired speed outside of chase ramps

	Hearing = {
		Threshold = 0.06, -- perceived loudness below this is ignored
		SuspicionBelow = 0.2, -- single quiet noises only make it stop and turn
		HighIntensity = 0.55, -- at or above this it rushes the location
		MidIntensity = 0.25,
		SeriesWindow = 7, -- seconds
		SeriesRadius = 18, -- studs
		SeriesForRush = 3, -- this many noises near each other = rush
		RecoverWakeThreshold = 0.35,
		RetargetRatio = 0.6, -- a new noise must be this loud relative to the current one to steal focus
		ChaseHearRadius = 26, -- during chase, noise this close to the last known position refreshes it
	},

	Sight = {
		Range = 72,
		DarkRangeMultiplier = 0.55,
		FieldOfView = 115, -- degrees
		CloseRange = 7, -- inside this range players are noticed regardless of facing
		InstantChaseRange = 9, -- visible within this range = immediate chase
		GainPerSecond = 1.7, -- awareness per second at point-blank, scales down with distance
		DecayPerSecond = 0.3,
		SuspicionAt = 0.3,
		ChaseAt = 1.0,
		CrouchMultiplier = 0.55,
		SprintMultiplier = 1.4,
		-- No eyes: players moving slower than this (standing still) are not sensed at all,
		-- unless closer than StillDetectRange (it bumps into you).
		MotionThreshold = 1.0,
		StillDetectRange = 4,
		FlashlightMultiplier = 1.7,
		FlashlightRangeBonus = 26,
	},

	Suspicion = {
		Duration = 2.6,
	},

	Investigate = {
		ArriveRadius = 4,
		ListenTime = 1.8, -- pause and listen on arrival
		MaxTime = 30,
	},

	Search = {
		Points = 4,
		Radius = 42,
		PauseMin = 1.0,
		PauseMax = 2.6,
		Duration = 24,
		AfterChasePoints = 6,
		AfterChaseRadius = 48,
		AfterChaseDuration = 38,
		HidingCheckChance = 0.35, -- chance to check a hiding spot on a search route
		HidingEvidenceRadius = 14, -- hiding spots this close to evidence are always checked
		HidingCheckDuration = 1.5,
	},

	Chase = {
		LoseSightTime = 2.4,
		PredictTime = 1.3,
		MaxDuration = 50,
		RepathInterval = 0.4,
		RepathDistance = 4,
		DirectRange = 32, -- with clear line of sight it skips pathfinding below this distance
		AttackRange = 5.5,
		AttackReach = 7.5,
		AttackWindup = 0.42,
		AttackTimeout = 2,
	},

	Recover = {
		Duration = 5, -- pause after a hunt; scaled by difficulty
		AfterAttackDuration = 3.5,
	},

	Patrol = {
		ListenChance = 0.35,
		ListenMin = 1.5,
		ListenMax = 3.5,
		HeatBias = 0.55, -- 0..1 how much noise heat pulls patrol destinations
		MaxPointDistance = 120,
	},

	HidingFind = {
		BaseChance = 0.18,
		SawEntryChance = 0.92,
		PantingChance = 0.75,
		SawEntryMemory = 20, -- seconds the monster remembers seeing someone enter a hiding spot
	},

	Stuck = {
		CheckInterval = 1.5,
		MinProgress = 1.2,
		MaxRepaths = 3,
		DoorPause = 0.45,
		DoorReach = 7,
	},

	Path = {
		AgentRadius = 2,
		AgentHeight = 10,
		WaypointSpacing = 5,
		ReachDistance = 3,
		ComputeCooldown = 0.25,
	},

	-- Client warning cues
	Cues = {
		FlickerRadius = 38, -- lights near the Listener flicker on clients
		BreathingRadius = 30,
		ShakeRadius = 18,
	},

	-- Visual
	Height = 11,
	SkinColor = { 178, 170, 152 },
	FinColor = { 150, 128, 122 },
}
