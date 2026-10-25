--[[
	QuestConfig - tutorial steps, the starter quest chain, achievements and daily objective
	templates. All progress is driven by server events (Progress.lua lists the stat names):

	  Collect      objects collected            CollectRarity:<Rarity>  by rarity
	  CollectHeavy heavy objects collected       CollectMedium           medium objects
	  CollectId:<ScrapId>                        a specific object
	  SellCount    sales made                    SellValue               coins from sales
	  Upgrade      upgrades bought               Tier                    magnet tier reached
	  Pulse        pulses used                   Zone                    zones unlocked
	  Discover     codex entries discovered      Storm                   storm participations
	  Prestige     prestiges done                Earned                  coins earned (all)
]]

local QuestConfig = {}

-- Interactive tutorial. Each step advances when its Event fires on the server.
QuestConfig.Tutorial = {
	{ Id = "Activate", Text = "ACTIVATE YOUR MAGNET", Hint = "Hold Left Mouse (or the MAGNET button) near scrap.", Event = "Claim" },
	{ Id = "Collect", Text = "COLLECT 8 PIECES OF SCRAP", Hint = "Keep the magnet on. Watch your pile grow!", Event = "Collect", Count = 8 },
	{ Id = "Sell", Text = "SELL YOUR SCRAP AT THE SHREDDER", Hint = "Follow the arrow to the big yellow shredder.", Event = "Sell", Target = "Shredder" },
	{ Id = "Upgrade", Text = "BUY YOUR FIRST UPGRADE", Hint = "Open UPGRADES at the station (or the HUD button).", Event = "Upgrade", Target = "Station" },
	{ Id = "Heavy", Text = "STRONGER MAGNETS PULL HEAVIER SCRAP", Hint = "Collect a medium object like a pipe or sign.", Event = "CollectMedium" },
	{ Id = "Explore", Text = "HEAD INTO THE YARD", Hint = "Bigger scrap waits near the cranes. Save up for the Copper Coil!", Event = "Tier", Target = "Yard" },
}

-- Starter quests: done one after another; each pays coins once.
QuestConfig.Starter = {
	{ Id = "Q1", Text = "Collect 25 scrap", Stat = "Collect", Target = 25, Reward = 40 },
	{ Id = "Q2", Text = "Make 3 sales", Stat = "SellCount", Target = 3, Reward = 60 },
	{ Id = "Q3", Text = "Buy 3 upgrades", Stat = "Upgrade", Target = 3, Reward = 90 },
	{ Id = "Q4", Text = "Collect 3 uncommon objects", Stat = "CollectRarity:Uncommon", Target = 3, Reward = 160 },
	{ Id = "Q5", Text = "Use the magnetic pulse 5 times", Stat = "Pulse", Target = 5, Reward = 200 },
	{ Id = "Q6", Text = "Upgrade to the Copper Coil magnet", Stat = "Tier", Target = 2, Reward = 300 },
	{ Id = "Q7", Text = "Pull a heavy object", Stat = "CollectHeavy", Target = 1, Reward = 600 },
	{ Id = "Q8", Text = "Earn 5,000 coins", Stat = "Earned", Target = 5000, Reward = 1000 },
	{ Id = "Q9", Text = "Reach the Steel Dynamo magnet", Stat = "Tier", Target = 3, Reward = 2000 },
	{ Id = "Q10", Text = "Unlock Metro Wreck", Stat = "Zone", Target = 2, Reward = 4000 },
	{ Id = "Q11", Text = "Discover 15 codex entries", Stat = "Discover", Target = 15, Reward = 8000 },
	{ Id = "Q12", Text = "Collect a rare object", Stat = "CollectRarity:Rare", Target = 1, Reward = 10000 },
}

-- One-time achievements.
QuestConfig.Achievements = {
	{ Id = "FirstCollect", Name = "Magnetic Personality", Text = "Collect your first scrap.", Stat = "Collect", Target = 1 },
	{ Id = "FirstSale", Name = "Shred It", Text = "Make your first sale.", Stat = "SellCount", Target = 1 },
	{ Id = "FirstUpgrade", Name = "Tinkerer", Text = "Buy your first upgrade.", Stat = "Upgrade", Target = 1 },
	{ Id = "FirstRare", Name = "Shiny!", Text = "Discover a rare object.", Stat = "CollectRarity:Rare", Target = 1 },
	{ Id = "FirstHeavy", Name = "Heavy Lifter", Text = "Pull a heavy object.", Stat = "CollectHeavy", Target = 1 },
	{ Id = "FirstZone", Name = "New Horizons", Text = "Unlock a new zone.", Stat = "Zone", Target = 2 },
	{ Id = "FirstPrestige", Name = "Reborn in Rust", Text = "Prestige once. Unlocks the Hazard Stripes skin.", Stat = "Prestige", Target = 1 },
	{ Id = "Collect1000", Name = "Scrap Hoarder", Text = "Collect 1,000 scrap. Unlocks the Rust Dust trail.", Stat = "Collect", Target = 1000 },
	{ Id = "Collect10000", Name = "Junk Royalty", Text = "Collect 10,000 scrap.", Stat = "Collect", Target = 10000 },
	{ Id = "Earn100K", Name = "Six Figures", Text = "Earn 100,000 coins.", Stat = "Earned", Target = 100000 },
	{ Id = "Earn10M", Name = "Scrap Tycoon", Text = "Earn 10,000,000 coins.", Stat = "Earned", Target = 10000000 },
	{ Id = "Legendary", Name = "The Real Treasure", Text = "Collect a legendary object.", Stat = "CollectRarity:Legendary", Target = 1 },
	{ Id = "Storm", Name = "Storm Chaser", Text = "Take part in a Magnetic Storm.", Stat = "Storm", Target = 1 },
	{ Id = "Codex", Name = "Archivist", Text = "Discover every codex entry.", Stat = "Discover", Target = -1 }, -- -1 = whole catalog
}

-- Daily objectives: three are rolled per UTC day from these templates. Targets and
-- rewards scale with the player's magnet tier (Scale ^ (tier - 1)).
QuestConfig.Daily = {
	Count = 3,
	Templates = {
		{ Id = "DCollect", Text = "Collect %d scrap objects", Stat = "Collect", Target = 100, Reward = 120, Scale = 1.4 },
		{ Id = "DSell", Text = "Earn %s coins from sales", Stat = "SellValue", Target = 600, Reward = 150, Scale = 3.2, Money = true },
		{ Id = "DMedium", Text = "Pull %d medium objects", Stat = "CollectMedium", Target = 6, Reward = 140, Scale = 1.2 },
		{ Id = "DUncommon", Text = "Discover %d uncommon objects", Stat = "CollectRarity:Uncommon", Target = 4, Reward = 160, Scale = 1.15 },
		{ Id = "DPulse", Text = "Use the magnetic pulse %d times", Stat = "Pulse", Target = 8, Reward = 100, Scale = 1 },
		{ Id = "DSales", Text = "Make %d sales", Stat = "SellCount", Target = 5, Reward = 110, Scale = 1 },
	},
	RewardScale = 3.2,
}

return QuestConfig
