--[[
	Disco Banana Fever (Brainrot, intensity 1) - planned for Stage 4.
	The whole city turns into a disco; bananas dance on the barriers. Pure screen effect.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "DiscoBananaFever",
	name = "Disco Banana Fever",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 10,
	warning = 2,
	tags = { "screen-effect", "track-wide" },
	conflictsWith = { "MegaBomb" },
	minLap = 1,
	finalLapBoost = 1.2,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = {},
	implemented = false,
	stage = 4,
	description = "The whole city turns into a disco; bananas dance on the barriers. Pure screen effect.",
})
