--[[
	Laser Llama Disco (Brainrot, intensity 3) - planned for Stage 4.
	A llama in a disco suit fires sweeping laser beams from the stadium roof.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "LaserLlamaDisco",
	name = "Laser Llama Disco",
	category = "Brainrot",
	intensity = 3,
	weight = 4,
	duration = 12,
	warning = 4,
	tags = { "projectile", "area" },
	conflictsWith = {},
	minLap = 2,
	finalLapBoost = 1.6,
	zoneTags = { "stadium", "park" },
	blocksLanes = 0,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "A llama in a disco suit fires sweeping laser beams from the stadium roof.",
})
