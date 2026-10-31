--[[
	Bonk Bonk Bonko (Brainrot, intensity 2) - planned for Stage 4.
	An original wooden log-drum guy (parody nod to a famous brainrot chaser, clearly different design) sprints after the leaders shouting BONK and bat-swats karts sideways.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BonkBonkBonko",
	name = "Bonk Bonk Bonko",
	category = "Brainrot",
	intensity = 2,
	weight = 7,
	duration = 14,
	warning = 3,
	tags = { "chase", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "straight", "plaza" },
	blocksLanes = 0,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "An original wooden log-drum guy (parody nod to a famous brainrot chaser, clearly different design) sprints after the leaders shouting BONK and bat-swats karts sideways.",
})
