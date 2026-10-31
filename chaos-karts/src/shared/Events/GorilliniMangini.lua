--[[
	Gorillini Mangini (Brainrot, intensity 2) - planned for Stage 4.
	A gorilla wearing half a mango (parody, own design) hurls giant mangos from the stadium; splats are sticky slow zones.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "GorilliniMangini",
	name = "Gorillini Mangini",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "projectile", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "stadium", "plaza" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "A gorilla wearing half a mango (parody, own design) hurls giant mangos from the stadium; splats are sticky slow zones.",
})
