--[[
	Toaster Downpour (Brainrot, intensity 1) - planned for Stage 4.
	Chrome toasters rain from the sky and pop toast where they land. A direct hit spins you out.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "ToasterDownpour",
	name = "Toaster Downpour",
	category = "Brainrot",
	intensity = 1,
	weight = 9,
	duration = 9,
	warning = 3,
	tags = { "projectile", "sky", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "sky" },
	blocksLanes = 0,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "Chrome toasters rain from the sky and pop toast where they land. A direct hit spins you out.",
})
