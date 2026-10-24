--[[
	Difficulty presets. Every multiplier is relative to MonsterConfig / PlayerConfig values.
	The host picks one in the lobby. Consecutive successful escapes add "pressure", which
	slowly raises the monster's speed and senses for the next run on the same server.
]]

return {
	Order = { "Easy", "Normal", "Hard", "Nightmare" },
	Default = "Normal",

	Presets = {
		Easy = {
			MonsterSpeed = 0.86,
			Hearing = 0.8,
			Sight = 0.8,
			SearchTime = 0.8,
			RecoverTime = 1.6,
			MonsterSpawnDelay = 40,
			ExtractionTime = 35,
			DownedEnabled = true,
			BleedOutTime = 50,
			ItemSpares = 3,
			Supplies = 5,
			Throwables = 15,
			XpMultiplier = 0.75,
		},
		Normal = {
			MonsterSpeed = 1.0,
			Hearing = 1.0,
			Sight = 1.0,
			SearchTime = 1.0,
			RecoverTime = 1.0,
			MonsterSpawnDelay = 28,
			ExtractionTime = 45,
			DownedEnabled = true,
			BleedOutTime = 35,
			ItemSpares = 2,
			Supplies = 5,
			Throwables = 12,
			XpMultiplier = 1.0,
		},
		Hard = {
			MonsterSpeed = 1.07,
			Hearing = 1.2,
			Sight = 1.15,
			SearchTime = 1.25,
			RecoverTime = 0.6,
			MonsterSpawnDelay = 18,
			ExtractionTime = 55,
			DownedEnabled = true,
			BleedOutTime = 25,
			ItemSpares = 2,
			Supplies = 4,
			Throwables = 10,
			XpMultiplier = 1.4,
		},
		Nightmare = {
			MonsterSpeed = 1.14,
			Hearing = 1.4,
			Sight = 1.3,
			SearchTime = 1.5,
			RecoverTime = 0.4,
			MonsterSpawnDelay = 10,
			ExtractionTime = 65,
			DownedEnabled = false,
			BleedOutTime = 0,
			ItemSpares = 1,
			Supplies = 3,
			Throwables = 8,
			XpMultiplier = 2.0,
		},
	},

	Pressure = {
		PerEscape = 0.04, -- +4% monster speed / hearing / sight per consecutive escape
		MaxStacks = 5,
	},
}
