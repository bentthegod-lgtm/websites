--[[
	Bombombini Gusini (Brainrot, intensity 2) - planned for Stage 4.
	A jet-powered goose squadron dive-bombs lanes with honking egg bombs that leave spin-out splats.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BombombiniGusini",
	name = "Bombombini Gusini",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "sky", "projectile" },
	conflictsWith = { "BombardiroCrocodilo" },
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "sky" },
	blocksLanes = 0,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "A jet-powered goose squadron dive-bombs lanes with honking egg bombs that leave spin-out splats.",
})
