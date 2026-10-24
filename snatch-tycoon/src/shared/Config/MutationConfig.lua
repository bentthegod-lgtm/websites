--[[
	Mutations roll on top of a spawned Blobby. They multiply both its price and its income,
	change its look, and are always announced to the whole server.
]]

return {
	Order = { "Rainbow", "Diamond", "Gold" }, -- rolled rarest first
	Types = {
		Gold = { Name = "Gold", Chance = 0.04, Mult = 2, PriceMult = 2, Color = { 255, 200, 48 } },
		Diamond = { Name = "Diamond", Chance = 0.015, Mult = 3, PriceMult = 3, Color = { 150, 236, 255 } },
		Rainbow = { Name = "Rainbow", Chance = 0.004, Mult = 6, PriceMult = 6, Color = { 255, 120, 220 } },
	},
	-- Upper bound for a boosted mutation chance (sum of all types) so luck can never make
	-- every Blobby mutated.
	MaxTotalChance = 0.5,
}
