--[[
	Bouncy Castle Drop (Brainrot, intensity 2) - planned for Stage 4.
	A bouncy castle parachutes onto the track. Drive over it and you bounce sky-high.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BouncyCastleDrop",
	name = "Bouncy Castle Drop",
	category = "Brainrot",
	intensity = 2,
	weight = 7,
	duration = 10,
	warning = 3,
	tags = { "area", "sky", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "straight", "open" },
	blocksLanes = 1,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "A bouncy castle parachutes onto the track. Drive over it and you bounce sky-high.",
})
