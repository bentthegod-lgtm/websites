--[[
	Robux shop: one-run boosts.

	Each boost is consumed when a run starts (if the player switched it on for their next
	run). They help without making the Listener harmless, so free players can still win.

	SETUP: create a Developer Product for each entry below in Creator Hub
	(create.roblox.com -> your experience -> Monetization -> Developer Products), then paste
	its numeric ID into ProductId. While ProductId is 0 the Buy button grants the boost for
	free in Studio (for testing) and shows "not available yet" in the live game.
]]

return {
	Boosts = {
		QuietShoes = {
			Name = "Padded Soles",
			Description = "Your footsteps are 40% quieter for one run.",
			Color = { 150, 200, 255 },
		},
		SecondWind = {
			Name = "Second Wind",
			Description = "50% more stamina and sprint drains 25% slower for one run.",
			Color = { 140, 230, 150 },
		},
		LithiumCell = {
			Name = "Lithium Cell",
			Description = "Your flashlight battery lasts twice as long for one run.",
			Color = { 255, 230, 120 },
		},
		LureKit = {
			Name = "Lure Kit",
			Description = "Start a run with 2 tin cans and an alarm clock.",
			Color = { 255, 170, 110 },
		},
		XRay = {
			Name = "X-Ray Goggles",
			Description = "See the Listener glowing red through walls for one run.",
			Color = { 255, 90, 90 },
		},
		Adrenaline = {
			Name = "Adrenaline Shot",
			Description = "Once per run, when you go down you get back up on your own after 6 seconds - even solo.",
			Color = { 255, 120, 120 },
		},
	},

	-- Display order in the shop.
	BoostOrder = { "XRay", "QuietShoes", "SecondWind", "LithiumCell", "LureKit", "Adrenaline" },

	Products = {
		{ Key = "QuietShoes1", Name = "Padded Soles", Robux = 10, ProductId = 0, Grants = { QuietShoes = 1 } },
		{ Key = "SecondWind1", Name = "Second Wind", Robux = 10, ProductId = 0, Grants = { SecondWind = 1 } },
		{ Key = "LithiumCell1", Name = "Lithium Cell", Robux = 5, ProductId = 0, Grants = { LithiumCell = 1 } },
		{ Key = "LureKit1", Name = "Lure Kit", Robux = 8, ProductId = 0, Grants = { LureKit = 1 } },
		{ Key = "Adrenaline1", Name = "Adrenaline Shot", Robux = 15, ProductId = 0, Grants = { Adrenaline = 1 } },
		{ Key = "XRay1", Name = "X-Ray Goggles", Robux = 20, ProductId = 0, Grants = { XRay = 1 } },
		{
			Key = "SurvivorPack",
			Name = "Survivor Pack (3 of every boost)",
			Robux = 99,
			ProductId = 0,
			Grants = { QuietShoes = 3, SecondWind = 3, LithiumCell = 3, LureKit = 3, Adrenaline = 3, XRay = 3 },
		},
	},

	-- Effect tuning
	QuietShoesMultiplier = 0.6,
	SecondWindStamina = 1.5,
	SecondWindDrain = 0.75,
	LithiumDrain = 0.5,
	AdrenalineDelay = 6,
}
