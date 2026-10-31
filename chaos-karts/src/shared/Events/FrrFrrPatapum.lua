--[[
	Frr Frr Patapum (Brainrot, intensity 2) - planned for Stage 4.
	A grumpy tree creature (parody, own design) stomps and roots burst out of the road as jump-or-crash hurdles across one lane.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "FrrFrrPatapum",
	name = "Frr Frr Patapum",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "area", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "park", "open" },
	blocksLanes = 1,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "A grumpy tree creature (parody, own design) stomps and roots burst out of the road as jump-or-crash hurdles across one lane.",
})
