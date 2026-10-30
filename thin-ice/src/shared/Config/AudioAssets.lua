--[[
	AudioAssets - every sound slot in THIN ICE. Every slot is filled.

	ID RULE: no audio IDs are invented. Every rbxassetid here is one the DEAD AIR project
	in this repo already uses (dead-air/src/shared/Config/AudioAssets.lua - Roblox's licensed
	partner libraries, free to use in experiences). A unit test enforces it. Many are
	STAND-INS re-pitched / layered to fit a frozen lake (marked "stand-in"): replace them with
	better-fitting licensed audio when you can - see README "Sound".

	Fields: Id (or Layers = { { Id, Volume, Pitch, Delay } } played together), Volume, Pitch,
	Looped, Group (Effects / Ambient / Music / UI - each has a volume slider), MaxDistance /
	MinDistance (3D roll-off), Duration (one-shot lifetime), Fade (fade-out at the end).
	The AudioController adds +-6% pitch variation and throttles repeats.
]]

return {
	-- Players --------------------------------------------------------------------------
	Step = { Id = "rbxassetid://9113473249", Volume = 0.22, Pitch = 1.5, MaxDistance = 40 }, -- DEAD AIR "Land", pitched up into a snow crunch (stand-in)
	Pickup = { Id = "rbxassetid://9116173869", Volume = 0.4, Group = "UI" },
	Thaw = { Id = "rbxassetid://9117864897", Volume = 0.5, Pitch = 1.4, MaxDistance = 60, Duration = 2.2, Fade = 0.8 }, -- "FuelPour" hiss as the ice melts (stand-in)
	Snowball = { Id = "rbxassetid://9120851227", Volume = 0.5, Pitch = 0.7, MaxDistance = 90 }, -- "ItemDrop" thud
	Splash = {
		-- "MetalDrop" + "CanClatter" pitched way down into a heavy plunge (stand-in)
		Volume = 0.7,
		MaxDistance = 120,
		Layers = { { Id = "rbxassetid://9116537007", Volume = 0.9, Pitch = 0.45 }, { Id = "rbxassetid://9116612715", Volume = 0.4, Pitch = 0.5, Delay = 0.05 } },
	},

	-- Ice ------------------------------------------------------------------------------
	Crack = {
		-- "GlassBreak" pitched up (the snap) over "DoorSlam" pitched down (the boom under it)
		Volume = 0.6,
		MaxDistance = 110,
		Layers = { { Id = "rbxassetid://9114591515", Volume = 0.6, Pitch = 1.7 }, { Id = "rbxassetid://1837829565", Volume = 0.35, Pitch = 0.6 } },
	},
	Break = {
		Volume = 0.8,
		MaxDistance = 140,
		Layers = { { Id = "rbxassetid://9114591515", Volume = 0.9, Pitch = 1.1 }, { Id = "rbxassetid://1837829565", Volume = 0.5, Pitch = 0.5 } },
	},
	IceGroan = {
		-- ambient scare: the lake groaning under you ("PipeCreak" + "DistantImpact", low)
		Volume = 0.45,
		Group = "Ambient",
		Duration = 4,
		Fade = 1.5,
		Layers = { { Id = "rbxassetid://9116892199", Volume = 0.8, Pitch = 0.45 }, { Id = "rbxassetid://9113134899", Volume = 0.4, Pitch = 0.5, Delay = 0.6 } },
	},
	Chip = {
		-- hammering a core out of the ice: "CanClatter" up + a glassy tick
		Volume = 0.55,
		MaxDistance = 90,
		Layers = { { Id = "rbxassetid://9116612715", Volume = 0.7, Pitch = 1.6 }, { Id = "rbxassetid://9114591515", Volume = 0.25, Pitch = 2.2 } },
	},
	Deliver = {
		-- a core slotting into the beacon: DEAD AIR's breaker-pull layers
		Volume = 0.7,
		MaxDistance = 220,
		Duration = 4,
		Fade = 1.5,
		Layers = { { Id = "rbxassetid://9120098454", Volume = 1 }, { Id = "rbxassetid://9116892199", Volume = 0.6, Pitch = 1.3, Delay = 0.15 } },
	},
	BrazierCrackle = { Id = "rbxassetid://9117864897", Volume = 0.18, Pitch = 0.5, Looped = true, MaxDistance = 32, MinDistance = 4, Group = "Ambient" }, -- "FuelPour" pitched into a fire hiss (stand-in - a real fire loop would be better)

	-- The Antlered (3D, attached to / at the monster) ---------------------------------
	MonsterBreath = { Id = "rbxassetid://9113983944", Volume = 0.5, Pitch = 0.75, Looped = true, MaxDistance = 45, MinDistance = 6 },
	MonsterStep = { Id = "rbxassetid://9113473249", Volume = 0.8, Pitch = 0.4, MaxDistance = 70, MinDistance = 8 }, -- heavy crunch ("Land", pitched down)
	MonsterCall = { Id = "rbxassetid://9113985466", Volume = 0.35, Pitch = 0.6, MaxDistance = 400, MinDistance = 60, Duration = 4, Fade = 1.5 }, -- distant call: "MonsterVocal" pitched down, quiet
	MonsterVocal = { Id = "rbxassetid://9113985466", Volume = 0.8, Pitch = 0.75, MaxDistance = 180, Duration = 3.5, Fade = 1 },
	MonsterHunt = { Id = "rbxassetid://9113980319", Volume = 0.9, Pitch = 0.8, MaxDistance = 220, MinDistance = 15, Duration = 3 }, -- "MonsterChaseRoar"
	MonsterListen = { Id = "rbxassetid://9125475729", Volume = 0.7, Pitch = 0.7, MaxDistance = 50, Duration = 1.5 },
	Spotted = { Id = "rbxassetid://1839909461", Volume = 0.8, Group = "Music", Duration = 3.5, Fade = 1 }, -- "SpottedSting", only to the player it starts hunting
	Caught = {
		-- the catch scare: DEAD AIR's jumpscare layers at reduced volume (13+, not deafening)
		Volume = 0.55,
		Duration = 2.4,
		Fade = 0.6,
		Layers = {
			{ Id = "rbxassetid://9043338036", Volume = 1 },
			{ Id = "rbxassetid://9043345728", Volume = 0.7, Pitch = 1.05 },
			{ Id = "rbxassetid://9125474518", Volume = 0.6, Pitch = 0.7 },
		},
	},
	Heartbeat = { Id = "rbxassetid://9043365842", Volume = 0.45, Looped = true },

	-- Ambience ---------------------------------------------------------------------------
	Wind = { Id = "rbxassetid://9125446564", Volume = 0.35, Pitch = 0.55, Looped = true, Group = "Ambient" }, -- "VentilationLoop" pitched down into wind (stand-in)
	WindHum = { Id = "rbxassetid://9112889082", Volume = 0.05, Pitch = 0.5, Looped = true, Group = "Ambient" }, -- "ElectricalHum" very low under the wind
	GustWind = { Id = "rbxassetid://9125446564", Volume = 0.45, Pitch = 0.8, Looped = true, Group = "Ambient" }, -- whiteout: the same wind, louder and higher
	WindHowl = { Id = "rbxassetid://9125446564", Volume = 0.35, Pitch = 2.1, Group = "Ambient", Duration = 3.5, Fade = 1.5, MaxDistance = 400, MinDistance = 60 }, -- ambient scare: a distant scream-like gust (stand-in)
	ShadowSwell = { Id = "rbxassetid://9113134899", Volume = 0.45, Pitch = 0.35, Group = "Ambient", Duration = 3, Fade = 1 }, -- ambient scare: something huge passing under the ice

	-- Music --------------------------------------------------------------------------------
	LobbyMusic = { Id = "rbxassetid://134959834418523", Volume = 0.3, Looped = true, Group = "Music" },
	LakeMusic = { Id = "rbxassetid://9043359885", Volume = 0.3, Pitch = 0.9, Looped = true, Group = "Music" }, -- "TensionLayer": the tension bed out on the ice
	Chase = { Id = "rbxassetid://80586845389169", Volume = 0.45, Looped = true, Group = "Music" }, -- "ChaseLayer": only while it hunts YOU

	-- Round / UI ---------------------------------------------------------------------------
	Countdown = { Id = "rbxassetid://9113880475", Volume = 0.5, Group = "UI" }, -- "TerminalBeep"
	UIClick = { Id = "rbxassetid://9113880475", Volume = 0.25, Pitch = 1.4, Group = "UI" }, -- "TerminalBeep", higher and soft
	AllCores = { Id = "rbxassetid://9119661709", Volume = 0.45, Pitch = 1.2, Duration = 1.6, Fade = 0.6 }, -- "Alarm", short
	Horn = { Id = "rbxassetid://9119661709", Volume = 0.8, Pitch = 0.55, MaxDistance = 600, MinDistance = 40, Duration = 1.8, Fade = 0.6 }, -- sled horn: "Alarm" pitched way down, briefly (stand-in)
	Escape = { Id = "rbxassetid://1837953706", Volume = 0.6, Group = "Music" }, -- "EscapeSting"
	Fail = { Id = "rbxassetid://9043338697", Volume = 0.6, Group = "Music" }, -- "FailSting"
}
