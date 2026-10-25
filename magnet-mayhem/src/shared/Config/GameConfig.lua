--[[
	GameConfig - general settings: data stores, saving, codes and tick rates.
]]

return {
	DataStoreName = "MagnetMayhem_Profiles_v1",
	LeaderboardValueStore = "MagnetMayhem_TotalScrapValue_v1",
	LeaderboardRareStore = "MagnetMayhem_RareFinds_v1",
	SchemaVersion = 1,
	AutosaveInterval = 60,
	LeaderboardWriteInterval = 120,
	LeaderboardRefresh = 60,

	-- Server magnet tick (claims, completions, validation) in seconds.
	MagnetTick = 0.1,
	-- A claimed object is only awarded if the player is still within Range * this.
	CompletionRangeSlack = 2.2,
	-- Selling: standing on the sell pad sells automatically, at most once per this many seconds.
	SellCooldown = 1.2,

	-- Codes: one use per player.
	Codes = {
		MAGNET = { Coins = 150 },
		SCRAPPY = { Coins = 400 },
		RUSTYARD = { Coins = 750 },
	},
}
