--[[
	PerformanceConfig - budgets that keep the game smooth on phones. Clients lower some of
	these further when "Reduced effects" or low particle quality is chosen in Settings.
]]

return {
	MaxActiveScrapTotal = 300, -- across all zones (each zone also has ZoneConfig.MaxScrap)
	SpawnPerSecond = 6, -- refill rate per zone
	GridCell = 24, -- spatial hash cell size (studs)
	MaxClaimsPerTick = 4, -- per player per server tick
	MaxInFlightPerPlayer = 16,

	PileDetailedLocal = 42, -- pieces drawn around your own character
	PileDetailedOther = 14, -- pieces drawn around each other player
	PileOtherUpdateHz = 15,
	PileHideDistance = 220, -- other players' piles beyond this are not drawn
	MaxVisualFlights = 70, -- client: simultaneous animated flights (extra ones snap)

	Particles = { High = 1, Medium = 0.6, Low = 0.25 },
	MaxPopupsPerSecond = 6,
}
