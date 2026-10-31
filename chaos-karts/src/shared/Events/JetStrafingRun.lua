--[[
	Jet Strafing Run (Disaster, intensity 2) - planned for Stage 5.
	Generic cartoon fighter jets (no real aircraft or insignia) scream low over a straight and strafe one lane with paint-ball rockets.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "JetStrafingRun",
	name = "Jet Strafing Run",
	category = "Disaster",
	intensity = 2,
	weight = 5,
	duration = 12,
	warning = 4,
	tags = { "sky", "projectile", "blocks-lane" },
	conflictsWith = { "BombardiroCrocodilo" },
	minLap = 2,
	finalLapBoost = 1.6,
	zoneTags = { "straight", "highway", "sky" },
	blocksLanes = 1,
	effects = { "spinOut" },
	implemented = false,
	stage = 5,
	description = "Generic cartoon fighter jets (no real aircraft or insignia) scream low over a straight and strafe one lane with paint-ball rockets.",
})
