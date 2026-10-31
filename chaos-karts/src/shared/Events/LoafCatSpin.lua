--[[
	Spinning Loaf Cat (Brainrot, intensity 1) - planned for Stage 4.
	A giant bread-shaped cat spins above a corner; its spin pulls karts slightly sideways.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "LoafCatSpin",
	name = "Spinning Loaf Cat",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 10,
	warning = 2,
	tags = { "area", "sky" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "sky", "turn" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "A giant bread-shaped cat spins above a corner; its spin pulls karts slightly sideways.",
})
