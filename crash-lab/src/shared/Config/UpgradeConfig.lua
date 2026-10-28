--[[
	UpgradeConfig - every coin upgrade, grouped into the four shop categories.

	Cost of level n -> n+1 = floor(Base * Growth ^ n). Effects are read by Economy.stats;
	each one changes how a launch plays, not just a number on a card:
	  Power      faster launches = longer flights
	  Payload    heavier dummy class (breaks sturdier props, bounces lower, slides further)
	  Cooldown   shorter wait between launches
	  Angles     unlocks a wider aim range (fixed 45 deg at first)
	  Precision  shorter charge time and less random spread on the launch direction
	  Durability the dummy survives more counted impacts, and each is worth more
	  Spin       unlocks spin modes (Flip / Corkscrew / Chaos) for wild tumbles
	  Bonus      objective and target bonuses worth more
	  Challenge  bigger multiplier for the featured objective
	  Analyst    more coins per point
]]

local UpgradeConfig = {}

UpgradeConfig.Categories = { "Launch Power", "Launcher Mechanics", "Dummy Technology", "Scoring" }

UpgradeConfig.List = {
	{ Key = "Power", Category = "Launch Power", Name = "Launch Power", Max = 12, Base = 60, Growth = 1.55, Icon = "PWR", Text = "+7% launch speed per level" },
	{ Key = "Payload", Category = "Launch Power", Name = "Payload Class", Max = 3, Base = 900, Growth = 4.5, Icon = "KG", Text = "Heavier dummy: breaks sturdier props, bounces lower, slides further" },
	{ Key = "Cooldown", Category = "Launcher Mechanics", Name = "Quick Reload", Max = 5, Base = 150, Growth = 1.9, Icon = "CD", Text = "-1s launcher cooldown per level" },
	{ Key = "Angles", Category = "Launcher Mechanics", Name = "Aim Range", Max = 3, Base = 120, Growth = 3.2, Icon = "ANG", Text = "Unlocks a wider launch-angle range" },
	{ Key = "Precision", Category = "Launcher Mechanics", Name = "Precision Rig", Max = 5, Base = 220, Growth = 1.9, Icon = "PRC", Text = "Faster charge, less random launch spread" },
	{ Key = "Durability", Category = "Dummy Technology", Name = "Durability", Max = 5, Base = 200, Growth = 2.0, Icon = "DUR", Text = "+3 counted impacts per run and +10% impact points" },
	{ Key = "Spin", Category = "Dummy Technology", Name = "Spin Module", Max = 3, Base = 400, Growth = 3.5, Icon = "SPN", Text = "Unlocks Flip, Corkscrew, then Chaos spin" },
	{ Key = "Bonus", Category = "Scoring", Name = "Objective Bonus", Max = 5, Base = 180, Growth = 1.95, Icon = "OBJ", Text = "+15% objective and target bonuses" },
	{ Key = "Challenge", Category = "Scoring", Name = "Challenge Multiplier", Max = 3, Base = 500, Growth = 3.0, Icon = "x2", Text = "Featured objective pays x2 -> x2.5 -> x3 -> x3.5" },
	{ Key = "Analyst", Category = "Scoring", Name = "Lab Analyst", Max = 8, Base = 300, Growth = 1.75, Icon = "$", Text = "+6% coins per point" },
}

UpgradeConfig.ByKey = {}
for _, def in ipairs(UpgradeConfig.List) do
	UpgradeConfig.ByKey[def.Key] = def
end

-- Aim range per Angles level: { min, max, step } in degrees.
UpgradeConfig.AngleRanges = {
	[0] = { 45, 45, 5 },
	[1] = { 35, 55, 5 },
	[2] = { 25, 65, 5 },
	[3] = { 15, 75, 5 },
}

return UpgradeConfig
