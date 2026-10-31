--[[
	Twister Alley (Disaster, intensity 3) - planned for Stage 5.
	A tornado tears across the park, picking up karts and dropping them further on.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "TwisterAlley",
	name = "Twister Alley",
	category = "Disaster",
	intensity = 3,
	weight = 4,
	duration = 14,
	warning = 5,
	tags = { "area", "chase", "sky" },
	conflictsWith = { "SpaghettiTornado" },
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "open", "park", "plaza" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 5,
	description = "A tornado tears across the park, picking up karts and dropping them further on.",
})
