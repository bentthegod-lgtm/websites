--[[
	Freak Blizzard (Disaster, intensity 2) - planned for Stage 5.
	A sudden blizzard: snow on screen and slippery roads everywhere.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "FreakBlizzard",
	name = "Freak Blizzard",
	category = "Disaster",
	intensity = 2,
	weight = 5,
	duration = 14,
	warning = 4,
	tags = { "track-wide", "screen-effect" },
	conflictsWith = { "FlashFlood" },
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 5,
	description = "A sudden blizzard: snow on screen and slippery roads everywhere.",
})
