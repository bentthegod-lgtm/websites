--[[
	Wandering Sword Saint's Slash (Fiction, intensity 2) - planned for Stage 5.
	An original wandering swordsman sends a crescent slash wave across the bridge.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SwordSaintSlash",
	name = "Wandering Sword Saint's Slash",
	category = "Fiction",
	intensity = 2,
	weight = 5,
	duration = 8,
	warning = 3,
	tags = { "projectile", "crosses-track" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "bridge", "straight" },
	blocksLanes = 0,
	effects = { "spinOut" },
	implemented = false,
	stage = 5,
	description = "An original wandering swordsman sends a crescent slash wave across the bridge.",
})
