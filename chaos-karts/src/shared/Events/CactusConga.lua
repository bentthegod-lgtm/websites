--[[
	Cactus Conga Line (Brainrot, intensity 1) - planned for Stage 4.
	A conga line of dancing cacti in sombreros snakes across the road.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "CactusConga",
	name = "Cactus Conga Line",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 12,
	warning = 3,
	tags = { "area", "crosses-track", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "plaza", "park", "open" },
	blocksLanes = 1,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "A conga line of dancing cacti in sombreros snakes across the road.",
})
