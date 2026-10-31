--[[
	Lirilì Larilà (Brainrot, intensity 2) - planned for Stage 4.
	The cactus-elephant in sandals stomps a clock and a slow-motion bubble spreads over part of the track; karts inside move at half speed.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "LiriliLarila",
	name = "Lirilì Larilà",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "area", "screen-effect" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "open", "park", "plaza" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "The cactus-elephant in sandals stomps a clock and a slow-motion bubble spreads over part of the track; karts inside move at half speed.",
})
