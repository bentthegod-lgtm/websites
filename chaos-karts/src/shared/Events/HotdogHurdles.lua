--[[
	Hot Dog Hurdles (Brainrot, intensity 1) - planned for Stage 4.
	Giant hot dogs spring up across a lane as hurdles. Hop them or get launched.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "HotdogHurdles",
	name = "Hot Dog Hurdles",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 10,
	warning = 3,
	tags = { "blocks-lane", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "straight" },
	blocksLanes = 1,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "Giant hot dogs spring up across a lane as hurdles. Hop them or get launched.",
})
