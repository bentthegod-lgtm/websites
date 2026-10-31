--[[
	Beatbox Broccoli (Brainrot, intensity 1) - planned for Stage 4.
	A broccoli with headphones drops bass; every beat bounces nearby karts a little.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BeatboxBroccoli",
	name = "Beatbox Broccoli",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 10,
	warning = 2,
	tags = { "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "stadium", "plaza", "park" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "A broccoli with headphones drops bass; every beat bounces nearby karts a little.",
})
