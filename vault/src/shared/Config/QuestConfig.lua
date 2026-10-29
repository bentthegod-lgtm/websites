--[[
	QuestConfig - onboarding steps, achievements and daily challenge templates.

	Stats are counters in profile.Stats, bumped by the server only:
	  Collect, Collect:<Category>, CollectId:<lootId>, Deposits, DepositValue, Upgrades,
	  FullStacks, RareFinds, Earned, DepthLevel (highest unlocked), Discovered, Rebirths,
	  Visit:<depth> (times arrived on that depth by elevator).
	Achievements and daily challenges reward Vault Tokens (and sometimes cash or a cosmetic);
	none of them is ever required to progress.
]]

local QuestConfig = {}

-- Onboarding: each step advances on a real gameplay event, never on a timer.
QuestConfig.Tutorial = {
	{ Event = "Collect", Count = 3, Title = "COLLECT CASH", Text = "Walk up to loose cash and press E (or tap PICKUP)." },
	{ Event = "Deposit", Title = "DEPOSIT IT", Text = "Carry your stack to the Deposit Machine and drop it in." },
	{ Event = "Upgrade", Title = "UPGRADE", Text = "Buy an upgrade at the Upgrade Terminal - try Carrying Capacity." },
	{ Event = "UnlockDepth", Title = "GO DEEPER", Text = "Save up and unlock the Gold Reserve at the elevator panel." },
	{ Event = "TravelDeep", Title = "DESCEND", Text = "Ride the elevator down to B2 - gold is worth far more." },
}

QuestConfig.Achievements = {
	{ Id = "FirstPickup", Name = "First Pickup", Text = "Collect your first loot.", Stat = "Collect", Target = 1, Tokens = 1 },
	{ Id = "FirstDeposit", Name = "First Deposit", Text = "Deposit loot at a machine.", Stat = "Deposits", Target = 1, Tokens = 1 },
	{ Id = "FirstUpgrade", Name = "First Upgrade", Text = "Buy an upgrade.", Stat = "Upgrades", Target = 1, Tokens = 1 },
	{ Id = "FirstFullStack", Name = "Full Stack", Text = "Fill your carrying capacity.", Stat = "FullStacks", Target = 1, Tokens = 2 },
	{ Id = "FirstGold", Name = "Struck Gold", Text = "Collect a gold item.", Stat = "Collect:Gold", Target = 1, Tokens = 2 },
	{ Id = "FirstDiamond", Name = "Diamond Hands", Text = "Collect a diamond.", Stat = "Collect:Diamond", Target = 1, Tokens = 3 },
	{ Id = "FirstEmerald", Name = "Green Light", Text = "Collect an emerald.", Stat = "Collect:Emerald", Target = 1, Tokens = 4 },
	{ Id = "FirstPlatinum", Name = "Precious Metal", Text = "Collect platinum.", Stat = "Collect:Platinum", Target = 1, Tokens = 5 },
	{ Id = "FirstArtifact", Name = "Archaeologist", Text = "Collect an artifact.", Stat = "Collect:Artifact", Target = 1, Tokens = 6 },
	{ Id = "FirstLegendary", Name = "Legend", Text = "Collect legendary treasure.", Stat = "Collect:Legendary", Target = 1, Tokens = 10, Cosmetic = "Theme:Royal" },
	{ Id = "FirstNewDepth", Name = "Going Down", Text = "Unlock a new depth.", Stat = "DepthLevel", Target = 2, Tokens = 2 },
	{ Id = "MidVault", Name = "Halfway Down", Text = "Unlock the Emerald Reserve.", Stat = "DepthLevel", Target = 4, Tokens = 6 },
	{ Id = "DeepDiver", Name = "Rock Bottom", Text = "Unlock the Legendary Reserve.", Stat = "DepthLevel", Target = 7, Tokens = 20 },
	{ Id = "FirstRare", Name = "Rare Find", Text = "Discover Epic or rarer loot.", Stat = "RareFinds", Target = 1, Tokens = 3 },
	{ Id = "Collector100", Name = "Collector", Text = "Collect 100 items.", Stat = "Collect", Target = 100, Tokens = 2 },
	{ Id = "Collector1000", Name = "Hoarder", Text = "Collect 1,000 items.", Stat = "Collect", Target = 1000, Tokens = 5, Cosmetic = "Theme:Gilded" },
	{ Id = "Collector10000", Name = "Vault Legend", Text = "Collect 10,000 items.", Stat = "Collect", Target = 10000, Tokens = 15 },
	{ Id = "Millionaire", Name = "Millionaire", Text = "Earn $1M in total.", Stat = "Earned", Target = 1000000, Tokens = 5 },
	{ Id = "Billionaire", Name = "Billionaire", Text = "Earn $1B in total.", Stat = "Earned", Target = 1000000000, Tokens = 15 },
	{ Id = "BookHalf", Name = "Half the Book", Text = "Discover half of the Collection Book.", Stat = "Discovered", Target = -2, Tokens = 5 },
	{ Id = "BookComplete", Name = "Complete Collection", Text = "Discover every item in the Collection Book.", Stat = "Discovered", Target = -1, Tokens = 25, Cosmetic = "Theme:Prismatic" },
	{ Id = "Reborn", Name = "Reborn", Text = "Rebirth for the first time.", Stat = "Rebirths", Target = 1, Tokens = 10 },
}

-- Daily challenges: Count are rolled per player per UTC day from templates their highest
-- depth allows. Money targets scale with that depth (MoneyScale ^ (depth - 1)).
QuestConfig.Daily = {
	Count = 3,
	MoneyScale = 22,
	Templates = {
		{ Id = "Collect", Text = "Collect %s items", Stat = "Collect", Target = 150, MinDepth = 1, Cash = 400, Tokens = 1 },
		{ Id = "Deposit", Text = "Deposit $%s", Stat = "DepositValue", Target = 3000, Money = true, MinDepth = 1, Cash = 600, Tokens = 1 },
		{ Id = "Trips", Text = "Make %s deposits", Stat = "Deposits", Target = 12, MinDepth = 1, Cash = 500, Tokens = 1 },
		{ Id = "Upgrades", Text = "Buy %s upgrades", Stat = "Upgrades", Target = 3, MinDepth = 1, Cash = 300, Tokens = 1 },
		{ Id = "Gold", Text = "Collect %s gold items", Stat = "Collect:Gold", Target = 40, MinDepth = 2, Cash = 2000, Tokens = 2 },
		{ Id = "Gems", Text = "Collect %s diamonds", Stat = "Collect:Diamond", Target = 30, MinDepth = 3, Cash = 20000, Tokens = 2 },
		{ Id = "Rare", Text = "Discover %s Epic+ item", Stat = "RareFinds", Target = 1, MinDepth = 1, Cash = 1000, Tokens = 2 },
		{ Id = "Visit", Text = "Ride the elevator to your deepest floor %s times", Stat = "VisitDeepest", Target = 2, MinDepth = 2, Cash = 800, Tokens = 1 },
	},
}

return QuestConfig
