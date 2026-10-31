--[[
	Squalo Scarpalino (Brainrot, intensity 2) - planned for Stage 4.
	An original sneaker-wearing shark (parody, own design) surfs across the river and bridge on a wave, shoving karts aside.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SqualoScarpalino",
	name = "Squalo Scarpalino",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "chase", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "river", "bridge", "straight" },
	blocksLanes = 0,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "An original sneaker-wearing shark (parody, own design) surfs across the river and bridge on a wave, shoving karts aside.",
})
