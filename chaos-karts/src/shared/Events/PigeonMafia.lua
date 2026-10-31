--[[
	Pigeon Mafia Flyover (Brainrot, intensity 1) - planned for Stage 4.
	Pigeons in tiny fedoras drop bread crumbs that become slippery puddles.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "PigeonMafia",
	name = "Pigeon Mafia Flyover",
	category = "Brainrot",
	intensity = 1,
	weight = 9,
	duration = 10,
	warning = 3,
	tags = { "sky", "projectile" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "sky" },
	blocksLanes = 0,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "Pigeons in tiny fedoras drop bread crumbs that become slippery puddles.",
})
