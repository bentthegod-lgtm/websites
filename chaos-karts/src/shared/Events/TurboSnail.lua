--[[
	Turbo Snail Overtake (Brainrot, intensity 2) - planned for Stage 4.
	A snail with a jet engine overtakes everyone, leaving a slick trail.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "TurboSnail",
	name = "Turbo Snail Overtake",
	category = "Brainrot",
	intensity = 2,
	weight = 7,
	duration = 10,
	warning = 3,
	tags = { "chase" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "straight", "highway", "tunnel" },
	blocksLanes = 0,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "A snail with a jet engine overtakes everyone, leaving a slick trail.",
})
