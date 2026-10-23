--[[
	Gameplay sound (noise) tuning.

	These are NOT audio files. Every entry describes a server-side noise event the
	Listener can perceive: how loud it is at its source (Loudness, ~0..1.5) and how far
	it can travel before it is inaudible (Radius, studs). Audio playback is configured
	separately in AudioAssets.
]]

return {
	Categories = {
		-- Movement
		-- Creeping while crouched makes no footstep noise at all (see SoundMath.gait).
		FootstepCrouch = { Loudness = 0.10, Radius = 9 }, -- slow walking while standing
		FootstepCrouchRun = { Loudness = 0.2, Radius = 16 },
		FootstepWalk = { Loudness = 0.28, Radius = 24 },
		FootstepSprint = { Loudness = 0.72, Radius = 56 },
		Jump = { Loudness = 0.30, Radius = 24 },
		LandSoft = { Loudness = 0.40, Radius = 30 },
		LandHard = { Loudness = 0.90, Radius = 72 },
		Breathing = { Loudness = 0.16, Radius = 13 },

		-- Sudden noises
		ItemDrop = { Loudness = 0.45, Radius = 36 },
		MetalDrop = { Loudness = 0.95, Radius = 78 },
		GlassBreak = { Loudness = 1.0, Radius = 80 },
		DoorOpen = { Loudness = 0.32, Radius = 28 },
		DoorClose = { Loudness = 0.42, Radius = 34 },
		DoorSlam = { Loudness = 0.85, Radius = 70 },
		HeavyDoor = { Loudness = 1.05, Radius = 95 },
		LockerEnter = { Loudness = 0.24, Radius = 18 },
		LockerExit = { Loudness = 0.28, Radius = 20 },
		PropKnock = { Loudness = 0.70, Radius = 52 },
		Pickup = { Loudness = 0.12, Radius = 10 },

		-- Objective noises
		KeycardSwipe = { Loudness = 0.35, Radius = 28 },
		FuseInsert = { Loudness = 0.55, Radius = 44 },
		BreakerPull = { Loudness = 1.25, Radius = 150 },
		FuelPour = { Loudness = 0.45, Radius = 34 },
		GeneratorStart = { Loudness = 1.10, Radius = 115 },
		GeneratorRun = { Loudness = 0.55, Radius = 60 },
		Terminal = { Loudness = 0.45, Radius = 38 },
		ElevatorCall = { Loudness = 1.0, Radius = 120 },
		Alarm = { Loudness = 1.3, Radius = 210 },
		BlackBoxStatic = { Loudness = 0.48, Radius = 42 },
		Revive = { Loudness = 0.30, Radius = 22 },
		NoteRead = { Loudness = 0.08, Radius = 8 },
	},

	-- Footstep multiplier per abstract floor name (see MapConfig.FloorByKind).
	Surfaces = {
		Carpet = 0.6,
		Tile = 1.0,
		Concrete = 1.0,
		Metal = 1.55,
		Default = 1.0,
	},

	-- Doing an interaction while crouched scales its noise by this.
	CrouchInteractionMultiplier = 0.45,

	-- Distance moved per footstep (studs) for each gait.
	Stride = { Crouch = 3.2, CrouchRun = 3.8, Walk = 4.4, Sprint = 5.8 },

	-- Falls shorter than SoftLandHeight are silent; longer than HardLandHeight are hard landings.
	SoftLandHeight = 3.5,
	HardLandHeight = 9,

	Occlusion = {
		Wall = 0.45, -- remaining loudness per wall between source and listener
		Door = 0.65, -- per closed door
		Prop = 0.85, -- per large prop (partitions, shelves)
		MaxHits = 4,
		MinFactor = 0.06,
	},

	-- Listener never receives the exact source position: it receives a point jittered by up
	-- to Distance * Uncertainty (more when muffled), capped at MaxJitter.
	Uncertainty = 0.12,
	MaxJitter = 9,

	-- Noise events of the same category from the same source within this window and
	-- distance are merged into one (prevents spam from repeated actions).
	MergeWindow = 0.2,
	MergeDistance = 5,
	EventLifetime = 8,
	MaxActiveEvents = 64,

	-- Per-player cap on noise events per second (anything beyond is merged).
	MaxEventsPerSecondPerSource = 8,

	-- Heat left in a cell by noise, used to bias patrol routes toward places where things
	-- have been heard. Decays exponentially.
	HeatHalfLife = 45,

	-- Server-side debug visualisation of noise events (transparent spheres).
	-- Toggle with the workspace attribute DeadAirDebugNoise = true while play-testing.
	DebugAttribute = "DeadAirDebugNoise",
}
