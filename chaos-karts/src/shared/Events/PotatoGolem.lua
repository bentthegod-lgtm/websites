--[[
	Potato Golem Stroll (Brainrot, intensity 2) - planned for Stage 4.
	A lumpy potato golem with a tiny top hat strolls down one lane.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "PotatoGolem",
	name = "Potato Golem Stroll",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 14,
	warning = 3,
	tags = { "chase", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "straight", "park" },
	blocksLanes = 1,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "A lumpy potato golem with a tiny top hat strolls down one lane.",
})
