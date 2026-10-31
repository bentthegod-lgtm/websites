--[[
	Mecha Sentinel Rocket Punch (Fiction, intensity 3) - planned for Stage 5.
	An original anime-style giant mecha fires its rocket fist along the highway.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "MechaSentinel",
	name = "Mecha Sentinel Rocket Punch",
	category = "Fiction",
	intensity = 3,
	weight = 4,
	duration = 12,
	warning = 4,
	tags = { "projectile", "sky" },
	conflictsWith = {},
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "highway", "open" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 5,
	description = "An original anime-style giant mecha fires its rocket fist along the highway.",
})
