--[[
	XP, levels and cosmetic unlocks. Nothing here affects survival odds (no pay-to-win).
]]

return {
	DataStoreName = "DeadAir_Profiles_v1",
	SchemaVersion = 1,
	AutosaveInterval = 120,

	Xp = {
		Escape = 120,
		ObjectiveStep = 15,
		BlackBoxEscape = 150,
		LoreNote = 20,
		Revive = 25,
		Survived60s = 10, -- per minute alive, capped
		SurvivalCap = 60,
		Death = 10, -- consolation
	},

	-- Total XP needed for level N is Base * (N-1)^Exponent
	LevelBase = 250,
	LevelExponent = 1.35,

	-- Flashlight beam tints. Unlocked by level or by a stat threshold.
	Cosmetics = {
		{ Id = "Standard", Name = "Standard Beam", Color = { 255, 244, 214 }, Level = 1 },
		{ Id = "Sodium", Name = "Sodium Amber", Color = { 255, 186, 102 }, Level = 3 },
		{ Id = "Cold", Name = "Cold Cathode", Color = { 190, 222, 255 }, Level = 5 },
		{ Id = "Signal", Name = "Signal Green", Color = { 176, 255, 186 }, Level = 8 },
		{ Id = "Survivor", Name = "Survivor's Red", Color = { 255, 140, 130 }, Stat = "Escapes", Threshold = 5 },
		{ Id = "Archivist", Name = "Archivist Violet", Color = { 210, 176, 255 }, Stat = "LoreFound", Threshold = 8 },
	},
}
