--[[
	Espresso Ninjetto (Brainrot, intensity 1) - planned for Stage 4.
	A coffee-cup ninja (parody, own design) dashes along the road leaving coffee puddles: slow if you hit the middle, boost if you skim the foam edge.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "EspressoNinjetto",
	name = "Espresso Ninjetto",
	category = "Brainrot",
	intensity = 1,
	weight = 7,
	duration = 10,
	warning = 3,
	tags = { "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "straight", "highway", "tunnel" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "A coffee-cup ninja (parody, own design) dashes along the road leaving coffee puddles: slow if you hit the middle, boost if you skim the foam edge.",
})
