--[[
	EconomyConfig - every price and per-level effect in one place, so balance can be tuned
	without touching scripts.

	Upgrade price for buying level L+1 (L = current level, starting at 0):
	    round(Base * Growth ^ L)
	Each upgrade's Per value is applied by Economy.stats().
]]

local EconomyConfig = {}

EconomyConfig.StartingCoins = 0

EconomyConfig.Categories = { "Magnet", "Capacity", "Movement", "Economy" }

EconomyConfig.Upgrades = {
	-- Magnet
	{ Key = "Strength", Category = "Magnet", Name = "Coil Strength", Icon = "STR", Base = 60, Growth = 1.55, Max = 12, Per = 0.4, Unit = "strength", Description = "Stronger pull: lifts heavier objects and drags big ones in faster." },
	{ Key = "Range", Category = "Magnet", Name = "Field Range", Icon = "RNG", Base = 22, Growth = 1.45, Max = 15, Per = 2.5, Unit = "studs", Description = "Reach scrap further away." },
	{ Key = "Speed", Category = "Magnet", Name = "Pull Speed", Icon = "SPD", Base = 40, Growth = 1.5, Max = 10, Per = 0.1, Unit = "x speed", Description = "Scrap flies to you faster." },
	{ Key = "Pulse", Category = "Magnet", Name = "Pulse Emitter", Icon = "PLS", Base = 80, Growth = 1.55, Max = 10, Per = 4, Unit = "studs", Description = "Bigger magnetic pulse (R) and a shorter cooldown." },
	{ Key = "Heavy", Category = "Magnet", Name = "Heavy-Lift Clamps", Icon = "HVY", Base = 400, Growth = 1.9, Max = 5, Per = 1, Unit = "heavy at once", Description = "Pull more heavy objects at once, with less wind-up." },
	-- Capacity
	{ Key = "Capacity", Category = "Capacity", Name = "Scrap Capacity", Icon = "CAP", Base = 20, Growth = 1.32, Max = 25, Per = 0, Unit = "capacity", Description = "Carry a bigger pile before you have to sell." },
	{ Key = "Efficiency", Category = "Capacity", Name = "Multi-Grip", Icon = "EFF", Base = 50, Growth = 1.6, Max = 10, Per = 1, Unit = "objects at once", Description = "Pull more objects at the same time." },
	{ Key = "Organization", Category = "Capacity", Name = "Pile Packing", Icon = "PCK", Base = 150, Growth = 1.7, Max = 6, Per = 0.06, Unit = "capacity", Description = "Packs the pile tighter: +6% capacity per level and a neater pile." },
	-- Movement
	{ Key = "Move", Category = "Movement", Name = "Work Boots", Icon = "MOV", Base = 35, Growth = 1.5, Max = 10, Per = 0.8, Unit = "walk speed", Description = "Walk faster." },
	{ Key = "Sprint", Category = "Movement", Name = "Sprint Servos", Icon = "SPR", Base = 120, Growth = 1.6, Max = 6, Per = 0.04, Unit = "sprint", Description = "Sprint (Shift) faster." },
	-- Economy
	{ Key = "Sell", Category = "Economy", Name = "Shredder Contract", Icon = "SEL", Base = 100, Growth = 1.6, Max = 15, Per = 0.1, Unit = "x value", Description = "Every sale pays more." },
	{ Key = "Rare", Category = "Economy", Name = "Lucky Detector", Icon = "LCK", Base = 250, Growth = 1.7, Max = 8, Per = 0.03, Unit = "lucky chance", Description = "Chance for a Lucky Find (+50% value) on every pickup." },
}

EconomyConfig.ByKey = {}
for index, def in ipairs(EconomyConfig.Upgrades) do
	def.Order = index
	EconomyConfig.ByKey[def.Key] = def
end

-- Lucky Find bonus multiplier.
EconomyConfig.LuckyMultiplier = 1.5

-- Prestige: reset coins, upgrades, magnet tier and zone unlocks for Magnet Cores.
EconomyConfig.Prestige = {
	RequiresZone = "MetroWreck",
	MinRunEarned = 500000,
	CoresBase = 3, -- cores = floor(CoresBase * sqrt(runEarned / MinRunEarned))
	ValuePerCore = 0.08,
	SpeedPerCore = 0.03,
}

-- Sells this big get the "big sale" machine effect.
EconomyConfig.BigSale = 2000

return EconomyConfig
