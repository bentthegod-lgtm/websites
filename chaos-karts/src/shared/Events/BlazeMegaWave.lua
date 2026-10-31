--[[
	Blaze: MEGA WAVE (Fiction, intensity 3) - planned for Stage 5.
	Blaze, an original spiky-haired anime-style fighter, charges up on a rooftop and fires a giant energy beam down one lane (charge-up warning, then BOOM).
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BlazeMegaWave",
	name = "Blaze: MEGA WAVE",
	category = "Fiction",
	intensity = 3,
	weight = 4,
	duration = 10,
	warning = 5,
	tags = { "projectile", "blocks-lane", "screen-effect" },
	conflictsWith = {},
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "straight", "highway" },
	blocksLanes = 1,
	effects = { "launch" },
	implemented = false,
	stage = 5,
	description = "Blaze, an original spiky-haired anime-style fighter, charges up on a rooftop and fires a giant energy beam down one lane (charge-up warning, then BOOM).",
})
