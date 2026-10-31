--[[
	Neon Blackout (Disaster, intensity 2) - planned for Stage 5.
	Every neon sign in the city goes dark; only headlights and lightning flashes light the road.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "NeonBlackout",
	name = "Neon Blackout",
	category = "Disaster",
	intensity = 2,
	weight = 5,
	duration = 12,
	warning = 4,
	tags = { "track-wide", "screen-effect", "sky" },
	conflictsWith = { "SunglassesSun", "DiscoBananaFever" },
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = {},
	implemented = false,
	stage = 5,
	description = "Every neon sign in the city goes dark; only headlights and lightning flashes light the road.",
})
