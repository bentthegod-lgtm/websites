--[[
	ScoringConfig - how a run turns into points and coins. All of it is applied on the
	server by the pure Scoring module; the client only displays the breakdown it is sent.

	Impacts are NOT raw physics impulses: each contact is classified into a tier by the
	dummy's speed at that moment, the same object only counts after a debounce and at most
	PerObjectMax times, the floor is one grouped object, and the run has a cap
	(BaseCap + Durability * CapPerLevel). Below MinSpeed a touch is not an impact at all.
]]

return {
	MaxLaunchSpeed = 310, -- hard server clamp on any launch, whatever the upgrades

	DistancePoints = 1, -- per stud travelled down the course (furthest valid point)
	HeightPoints = 0.5, -- per stud of maximum height above the floor
	MaxCountedHeight = 220,

	Impact = {
		MinSpeed = 22, -- studs/s: slower touches are ignored
		Tiers = {
			{ Name = "Light", Speed = 22, Points = 6 },
			{ Name = "Medium", Speed = 55, Points = 16 },
			{ Name = "Heavy", Speed = 100, Points = 40 },
			{ Name = "Massive", Speed = 160, Points = 75 },
		},
		Debounce = 0.5, -- same object counts again only after this long
		PerObjectMax = 3,
		FloorMax = 5, -- floor bounces counted per run
		BaseCap = 10,
		CapPerLevel = 3,
		DurabilityBonus = 0.1, -- +10% impact points per Durability level
	},

	TargetPoints = 60, -- default for a target / destructible without its own value
	BonusPerLevel = 0.15, -- Objective Bonus upgrade
	FeaturedMultiplier = { [0] = 2, [1] = 2.5, [2] = 3, [3] = 3.5 },

	CoinsPerPoint = 0.5,
	AnalystPerLevel = 0.06,
	MinCoins = 8, -- even a flop earns something
	VoidCoins = 5, -- a run voided by impossible samples still gives a token amount
	MaxCoinsPerRun = 1000000,

	-- Prestige ("Lab Certification") bonus per Lab Credit.
	CreditBonus = 0.05,
	MaxCreditBonus = 1.0,
}
