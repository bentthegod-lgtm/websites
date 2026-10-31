--[[
	Sunglasses Sun (Brainrot, intensity 1) - planned for Stage 4.
	The sun puts on giant sunglasses and the whole screen flashes cool.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SunglassesSun",
	name = "Sunglasses Sun",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 8,
	warning = 2,
	tags = { "screen-effect", "sky" },
	conflictsWith = { "DiscoBananaFever", "NeonBlackout" },
	minLap = 1,
	finalLapBoost = 1.2,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = {},
	implemented = false,
	stage = 4,
	description = "The sun puts on giant sunglasses and the whole screen flashes cool.",
})
