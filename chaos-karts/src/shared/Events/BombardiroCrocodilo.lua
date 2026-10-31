--[[
	Bombardiro Crocodilo (Brainrot, intensity 3) - planned for Stage 4.
	The crocodile-plane swoops over the track dropping cartoon bombs (pies and confetti blasts, no real planes or places). Red target circles warn where they land.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "BombardiroCrocodilo",
	name = "Bombardiro Crocodilo",
	category = "Brainrot",
	intensity = 3,
	weight = 5,
	duration = 14,
	warning = 4,
	tags = { "sky", "projectile", "area" },
	conflictsWith = { "MayorMissileAlert", "JetStrafingRun" },
	minLap = 1,
	finalLapBoost = 1.8,
	zoneTags = { "sky" },
	blocksLanes = 0,
	effects = { "launch", "spinOut" },
	implemented = false,
	stage = 4,
	description = "The crocodile-plane swoops over the track dropping cartoon bombs (pies and confetti blasts, no real planes or places). Red target circles warn where they land.",
})
