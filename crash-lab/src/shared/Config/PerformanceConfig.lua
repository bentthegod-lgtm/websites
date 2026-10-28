--[[
	PerformanceConfig - budgets that keep repeated launches stable.
]]

return {
	MaxActiveDebris = 60, -- server-wide cap on loose fragments
	DebrisLifetime = 4, -- seconds before fragments are cleaned up
	RespawnDelay = 9, -- broken props come back after this long
	MaxActiveRuns = 12, -- server-wide cap on simultaneous dummies (one per player anyway)
	MovingTargetRate = 30, -- server updates per second for moving targets
	ClientImpactFx = 8, -- max simultaneous impact bursts drawn per client
	ReducedParticles = 0.35, -- particle rate multiplier in reduced-effects mode
}
