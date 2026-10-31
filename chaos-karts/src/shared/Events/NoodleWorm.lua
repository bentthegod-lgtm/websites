--[[
	Noodle Worm Crossing (Brainrot, intensity 2) - planned for Stage 4.
	A colossal noodle worm wriggles across the bridge one lane at a time.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "NoodleWorm",
	name = "Noodle Worm Crossing",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "crosses-track", "blocks-lane", "chase" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "river", "bridge", "park" },
	blocksLanes = 1,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "A colossal noodle worm wriggles across the bridge one lane at a time.",
})
