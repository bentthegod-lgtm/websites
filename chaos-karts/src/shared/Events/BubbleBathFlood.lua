--[[
	Bubble Bath Flood (Brainrot, intensity 2) - planned for Stage 4.
	Bubble bath foam floods an area; it slows you and pops into rubber ducks.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BubbleBathFlood",
	name = "Bubble Bath Flood",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "area" },
	conflictsWith = { "FlashFlood" },
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "plaza", "tunnel" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "Bubble bath foam floods an area; it slows you and pops into rubber ducks.",
})
