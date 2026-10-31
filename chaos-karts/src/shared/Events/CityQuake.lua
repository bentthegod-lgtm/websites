--[[
	City Quake (Disaster, intensity 3) - planned for Stage 5.
	The ground shakes city-wide: the camera rattles and cracks slow you down.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "CityQuake",
	name = "City Quake",
	category = "Disaster",
	intensity = 3,
	weight = 4,
	duration = 10,
	warning = 4,
	tags = { "track-wide", "screen-effect" },
	conflictsWith = { "Gorgantor" },
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 5,
	description = "The ground shakes city-wide: the camera rattles and cracks slow you down.",
})
