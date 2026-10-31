--[[
	Krunchjaw the City Kaiju (Fiction, intensity 3) - planned for Stage 5.
	A towering original kaiju stomps through downtown in classic monster-movie style; footprints shake the road.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "KaijuKrunchjaw",
	name = "Krunchjaw the City Kaiju",
	category = "Fiction",
	intensity = 3,
	weight = 4,
	duration = 16,
	warning = 5,
	tags = { "area", "sky", "blocks-lane", "chase" },
	conflictsWith = { "CityQuake" },
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "downtown", "plaza" },
	blocksLanes = 1,
	effects = { "knockback", "launch" },
	implemented = false,
	stage = 5,
	description = "A towering original kaiju stomps through downtown in classic monster-movie style; footprints shake the road.",
})
