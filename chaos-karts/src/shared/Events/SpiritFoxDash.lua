--[[
	Nine-Tail Spirit Fox Dash (Fiction, intensity 2) - planned for Stage 5.
	A glowing nine-tailed spirit fox races the pack through the park, trailing blue fire.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SpiritFoxDash",
	name = "Nine-Tail Spirit Fox Dash",
	category = "Fiction",
	intensity = 2,
	weight = 6,
	duration = 10,
	warning = 3,
	tags = { "chase", "screen-effect" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "park", "chicane" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 5,
	description = "A glowing nine-tailed spirit fox races the pack through the park, trailing blue fire.",
})
