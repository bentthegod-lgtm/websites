--[[
	Audio references.

	IMPORTANT: no Roblox audio asset IDs are invented here. Every slot is either:
	  * "" (empty)  - the sound is simply skipped until you add an asset you own or that is
	                  marked usable in the Creator Store, e.g. "rbxassetid://123456789"; or
	  * an rbxasset:// path to a file that ships inside the Roblox client's content folder.
	    The fallbacks below are the files used by Roblox's own default character-sound
	    script (RbxCharacterSounds). They are re-pitched to sound heavier/creepier.

	Every playback call goes through AudioUtil.make(), which ignores empty ids, so the game
	is fully playable (and the gameplay noise system works) with no audio assets at all.
	Gameplay detection never depends on these files - see NoiseService.
]]

local BUILTIN_STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local BUILTIN_LAND = "rbxasset://sounds/action_jump_land.mp3"
local BUILTIN_WIND = "rbxasset://sounds/action_falling.mp3"
local BUILTIN_SWIM = "rbxasset://sounds/action_swim.mp3"
local BUILTIN_JUMP = "rbxasset://sounds/action_jump.mp3"
local BUILTIN_GETUP = "rbxasset://sounds/action_get_up.mp3"
local BUILTIN_SPLASH = "rbxasset://sounds/impact_water.mp3"

return {
	-- Player footsteps by surface. Pitch/volume vary per surface in AudioController.
	Footstep = {
		Carpet = { Id = BUILTIN_STEP, Volume = 0.18, Pitch = 0.75 },
		Tile = { Id = BUILTIN_STEP, Volume = 0.35, Pitch = 1.05 },
		Concrete = { Id = BUILTIN_STEP, Volume = 0.32, Pitch = 0.9 },
		Metal = { Id = BUILTIN_STEP, Volume = 0.45, Pitch = 1.35 },
		Default = { Id = BUILTIN_STEP, Volume = 0.3, Pitch = 1.0 },
	},
	Land = { Id = BUILTIN_LAND, Volume = 0.5, Pitch = 0.85 },
	Jump = { Id = BUILTIN_JUMP, Volume = 0.25, Pitch = 0.9 },

	-- Ambience (2D loops; quiet on purpose - silence matters)
	VentilationLoop = { Id = BUILTIN_WIND, Volume = 0.06, Pitch = 0.32, Looped = true },
	FluorescentBuzz = { Id = "", Volume = 0.08, Looped = true },
	ElectricalHum = { Id = "", Volume = 0.05, Looped = true },
	DistantImpact = { Id = BUILTIN_LAND, Volume = 0.35, Pitch = 0.35 },
	PipeCreak = { Id = BUILTIN_GETUP, Volume = 0.25, Pitch = 0.4 },

	-- Listener (3D, attached to the creature)
	MonsterBreath = { Id = BUILTIN_SWIM, Volume = 0.7, Pitch = 0.42, Looped = true, MaxDistance = 45 },
	MonsterStep = { Id = BUILTIN_STEP, Volume = 0.9, Pitch = 0.42, MaxDistance = 80 },
	MonsterVocal = { Id = "", Volume = 1.0, MaxDistance = 160 },
	MonsterScreech = { Id = "", Volume = 1.2, MaxDistance = 200 },
	MonsterListen = { Id = BUILTIN_SWIM, Volume = 0.5, Pitch = 0.3, MaxDistance = 40 },
	MonsterAttack = { Id = BUILTIN_SPLASH, Volume = 1.0, Pitch = 0.5, MaxDistance = 60 },

	-- Music layers (2D). Leave empty for a silence-first experience.
	ChaseLayer = { Id = "", Volume = 0.55, Looped = true },
	TensionLayer = { Id = "", Volume = 0.25, Looped = true },
	Heartbeat = { Id = "", Volume = 0.5, Looped = true },

	-- World / objective (3D)
	DoorOpen = { Id = BUILTIN_GETUP, Volume = 0.4, Pitch = 0.6 },
	DoorClose = { Id = BUILTIN_LAND, Volume = 0.45, Pitch = 0.7 },
	DoorSlam = { Id = BUILTIN_LAND, Volume = 0.9, Pitch = 0.5 },
	HeavyDoor = { Id = BUILTIN_WIND, Volume = 0.6, Pitch = 0.22 },
	Pickup = { Id = "", Volume = 0.4 },
	ItemDrop = { Id = BUILTIN_LAND, Volume = 0.5, Pitch = 1.4 },
	MetalDrop = { Id = BUILTIN_LAND, Volume = 0.8, Pitch = 1.8 },
	GlassBreak = { Id = BUILTIN_SPLASH, Volume = 0.8, Pitch = 2.2 },
	FuseInsert = { Id = BUILTIN_LAND, Volume = 0.6, Pitch = 2.4 },
	BreakerPull = { Id = BUILTIN_LAND, Volume = 1.0, Pitch = 0.6 },
	GeneratorLoop = { Id = BUILTIN_WIND, Volume = 0.5, Pitch = 0.18, Looped = true, MaxDistance = 90 },
	TerminalBeep = { Id = "", Volume = 0.4 },
	Alarm = { Id = "", Volume = 0.8, Looped = true, MaxDistance = 220 },
	ElevatorArrive = { Id = BUILTIN_WIND, Volume = 0.8, Pitch = 0.3 },

	-- Results
	EscapeSting = { Id = "", Volume = 0.6 },
	FailSting = { Id = "", Volume = 0.6 },
}
