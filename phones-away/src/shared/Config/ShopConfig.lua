--[[
	Robux shop.

	SETUP: in Creator Hub (create.roblox.com -> your experience -> Monetization) create a
	Developer Product for every entry in Products and a Game Pass for every entry in Passes,
	then paste the numeric IDs below. Robux values are DISPLAY ONLY: the real price is what
	you set in Creator Hub, so keep them in sync.

	While an ID is 0: in Studio the Buy button grants the item for free (testing; passes last
	for the session), in a live game it says "not available yet".

	Fairness (pay-to-win is bounded):
	  * Clout packs are fixed amounts; every upgrade can be bought with played Clout.
	  * Pass multipliers ADD and are capped at MaxCloutMultiplier.
	  * Silent Mode = earbuds tier 3 of 4, Extra Hide Speed = -0.05 s, Pro Phone = +1 answer per
	    screenshot capped at 5 (the best Clout phone already reveals 5). A free player can
	    still get an A+ by playing well.
	  * Detention / Hall passes work once per class each; Answer Key Peek once per test.
	  * Pizza Party helps EVERYONE in the server.
]]

return {
	Products = {
		{ Key = "Clout500", Category = "Clout", Name = "Pocket Clout", Description = "+500 Clout", Robux = 25, ProductId = 0, Grants = { Clout = 500 }, Color = { 255, 200, 80 } },
		{ Key = "Clout2000", Category = "Clout", Name = "Trending Clout", Description = "+2,000 Clout (+20% bonus)", Robux = 79, ProductId = 0, Grants = { Clout = 2000 }, Color = { 255, 170, 60 } },
		{ Key = "Clout7500", Category = "Clout", Name = "Viral Clout", Description = "+7,500 Clout (best value)", Robux = 249, ProductId = 0, Grants = { Clout = 7500 }, Color = { 255, 120, 60 } },

		{ Key = "DetentionPass", Category = "Passes", Name = "Get Out of Detention", Description = "Leave detention instantly and get your phone back (once per class). Saved if you aren't in detention.", Robux = 25, ProductId = 0, Grants = { DetentionPass = 1 }, Color = { 255, 90, 90 } },
		{ Key = "HallPass", Category = "Passes", Name = "Fake Hall Pass", Description = "Your next catch is forgiven. Used automatically, once per class.", Robux = 35, ProductId = 0, Grants = { HallPass = 1 }, Color = { 120, 220, 255 } },

		{ Key = "AnswerPeek", Category = "Passes", Name = "Answer Key Peek", Description = "Peek at the teacher's answer key: 1 answer revealed instantly, no phone needed. Max 1 per test (saved for the next test otherwise).", Robux = 29, ProductId = 0, Grants = { Peek = 1 }, Color = { 255, 230, 120 } },

		{ Key = "PizzaParty", Category = "Social", Name = "PIZZA PARTY!", Description = "The WHOLE server gets a chill, lenient teacher and 2x Clout for one class. Everyone sees who bought it!", Robux = 99, ProductId = 0, Grants = { PizzaParty = 1 }, Color = { 255, 150, 60 } },

		{ Key = "SkinCrate", Category = "Crates", Name = "Phone Skin Crate", Description = "One random phone skin, Rare or better. Odds are shown in CRATES.", Robux = 49, ProductId = 0, Grants = { Crate = "Skin" }, Random = true, Color = { 255, 120, 220 } },
	},

	Passes = {
		{ Key = "DoubleClout", Name = "2x Clout", Description = "Double Clout from your test grades and everything else.", Robux = 199, PassId = 0, Color = { 255, 200, 60 } },
		{ Key = "VIP", Name = "VIP", Description = "VIP tag + chat tag, +10% Clout, and the comfy gold VIP desk in the back row.", Robux = 149, PassId = 0, Color = { 255, 120, 200 } },
		{ Key = "SilentMode", Name = "Silent Mode", Description = "Permanent Noise-Cancel Pods (earbuds tier 3). Upgrade further with Clout.", Robux = 99, PassId = 0, Color = { 120, 200, 255 } },
		{ Key = "ExtraHide", Name = "Extra Hide Speed", Description = "Your phone hides 0.05 s faster on top of your upgrades.", Robux = 79, PassId = 0, Color = { 140, 255, 160 } },
		{ Key = "ProPhone", Name = "Pro Phone", Description = "The exclusive Prism Pro: +1 answer per screenshot (capped at 5, the same as the best Clout phone) and it looks amazing.", Robux = 249, PassId = 0, Color = { 120, 255, 230 } },
	},

	CategoryOrder = { "Clout", "Social", "Passes", "Crates", "GamePasses" },
	CategoryNames = { Clout = "CLOUT", Social = "SOCIAL", Passes = "TEST HELP", Crates = "CRATES", GamePasses = "GAME PASSES" },

	DoubleCloutBonus = 1.0,
	VipCloutBonus = 0.1,
	MaxCloutMultiplier = 2.2,
}
