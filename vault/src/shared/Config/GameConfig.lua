--[[
	GameConfig - global tuning: data stores, timers, world scale, codes.
	Balance numbers for loot, upgrades and depths live in their own config modules.
]]

return {
	SchemaVersion = 1,
	DataStoreName = "Vault_Profiles_v1",
	-- OrderedDataStores for the four boards (a "_Studio" suffix is added in Studio).
	Leaderboards = {
		{ Key = "Earned", Store = "Vault_TotalEarned_v1", Title = "TOTAL EARNED", Money = true },
		{ Key = "Depth", Store = "Vault_HighestDepth_v1", Title = "DEEPEST VAULT", Money = false },
		{ Key = "Loot", Store = "Vault_TotalLoot_v1", Title = "LOOT COLLECTED", Money = false },
		{ Key = "Deposit", Store = "Vault_BestDeposit_v1", Title = "BEST DEPOSIT", Money = true },
	},
	LeaderboardRefresh = 60,
	LeaderboardWriteInterval = 120,
	AutosaveInterval = 60,

	-- World scale: depth d's floor sits at y = -(d - 1) * DepthSpacing, all depths share one
	-- vertical elevator shaft behind their arrival halls.
	DepthSpacing = 150,
	RoomWidth = 140, -- x from -70 to 70
	RoomFront = -72, -- z of the arrival hall's back wall (elevator wall)
	RoomBack = 60, -- z of the chamber's far wall (the exit door to the next depth)
	CeilingHeight = 30,
	LootScale = 1.5, -- loose loot is shown 1.5x life size so it reads from across a room

	-- Collection
	CollectSlack = 2.5, -- studs of latency tolerance on top of the collection radius
	CooldownTolerance = 0.85, -- the server accepts a pickup after 85% of the interval
	MagnetTick = 0.1,
	MagnetMaxPull = 8, -- loot items one player's magnet moves at once
	AutoDepositCooldown = 1.5,
	DepositRange = 12,
	ElevatorRange = 16,

	-- Rare loot events
	RareEvent = { MinGap = 120, MaxGap = 240, DepthCooldown = 420, Lifetime = 180 },

	-- Codes (once per player)
	Codes = {
		RELEASE = { Cash = 500, Tokens = 2 },
		VAULT = { Cash = 1500 },
		DEEPER = { Tokens = 3 },
	},
}
