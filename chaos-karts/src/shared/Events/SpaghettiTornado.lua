--[[
	Spaghetti Tornado (Brainrot, intensity 2) - planned for Stage 4.
	A swirling tornado of spaghetti and meatballs wanders across an open area.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SpaghettiTornado",
	name = "Spaghetti Tornado",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "area", "chase" },
	conflictsWith = { "TwisterAlley" },
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "open", "park", "plaza" },
	blocksLanes = 0,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "A swirling tornado of spaghetti and meatballs wanders across an open area.",
})
