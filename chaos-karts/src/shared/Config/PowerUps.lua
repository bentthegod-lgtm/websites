--[[
	PowerUps - the 12 planned items (Stage 3). Catalog only in Stage 1: implemented = false,
	and the F key / item button is a stub. Item rolls (ItemOdds) are WEIGHTED by race
	position: karts further back get better odds of strong items, but no item is ever
	guaranteed (every roll keeps every item possible).

	Fields: id, name, tier (1 weak .. 3 strong), effect (the KartEffects it uses), notes.
]]

local PowerUps = {}

PowerUps.ORDER = {
	"HomingMissile",
	"NuclearBomb",
	"MegaWave",
	"BlackHole",
	"MeteorStrike",
	"Lightning",
	"BoxingGlove",
	"FreezeRay",
	"BananaBomb",
	"UfoAbduction",
	"SpeedBoost",
	"ForceField",
}

PowerUps.Items = {
	HomingMissile = { name = "Homing Missile", tier = 2, effect = "launch", implemented = false, notes = "Locks on to the kart ahead and flips it." },
	NuclearBomb = { name = "Nuclear Bomb", tier = 3, effect = "launch", implemented = false, notes = "A cartoon mushroom-cloud bomb with a big, telegraphed blast radius." },
	MegaWave = { name = "Mega Wave", tier = 3, effect = "knockback", implemented = false, notes = "A charged energy beam fired straight ahead along the track." },
	BlackHole = { name = "Black Hole", tier = 3, effect = "slow", implemented = false, notes = "Drops a swirling black hole that pulls nearby karts in." },
	MeteorStrike = { name = "Meteor Strike", tier = 3, effect = "spinOut", implemented = false, notes = "Meteors rain on the leaders, with warning circles." },
	Lightning = { name = "Lightning", tier = 3, effect = "slow", implemented = false, notes = "Shrinks everyone ahead of you for a few seconds." },
	BoxingGlove = { name = "Giant Boxing Glove", tier = 1, effect = "knockback", implemented = false, notes = "Punches the nearest kart sideways." },
	FreezeRay = { name = "Freeze Ray", tier = 2, effect = "freeze", implemented = false, notes = "Freezes the kart in front into an ice cube." },
	BananaBomb = { name = "Banana Bomb", tier = 1, effect = "spinOut", implemented = false, notes = "Throws a bomb that splits into a ring of bananas." },
	UfoAbduction = { name = "UFO Abduction", tier = 2, effect = "launch", implemented = false, notes = "A UFO lifts the kart ahead and drops it a little back." },
	SpeedBoost = { name = "Speed Boost", tier = 1, effect = "boost", implemented = false, notes = "Three boosts (the Rooftop Leap's best friend)." },
	ForceField = { name = "Force Field", tier = 2, effect = "shield", implemented = false, notes = "Blocks the next hit for 8 seconds." },
}

-- Tier weights at the front (place 1) and the back (last place); interpolated between.
PowerUps.TierWeights = {
	Front = { 70, 25, 5 },
	Back = { 15, 35, 50 },
}

return PowerUps
