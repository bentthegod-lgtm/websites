--[[
	PerformanceConfig - visual budgets. Gameplay never depends on these.
]]

return {
	StackPiecesOwn = 24, -- carried-stack pieces drawn for your own character
	StackPiecesOthers = 12, -- for other players (fewer, they are further away)
	OthersStackRange = 140, -- other players' stacks are hidden beyond this distance
	FlyingPickups = 10, -- simultaneous pickup fly-in effects
	FloatingTexts = 8,
	TargetScanRate = 10, -- nearest-loot scans per second
	ReducedEffectsScale = 0.4,
}
