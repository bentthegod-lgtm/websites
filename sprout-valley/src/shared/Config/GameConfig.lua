--[[
	General tuning: data, plots, backpack, restock, rewards, codes and session goals.
]]

return {
	DataStoreName = "SproutValley_Profiles_v1",
	LeaderboardStoreName = "SproutValley_TotalEarned_v1",
	SchemaVersion = 1,
	AutosaveInterval = 90,

	StartingCoins = 40,
	StartingSeeds = { Carrot = 4, Strawberry = 1 },
	StartingGear = { WateringCan = 5 },

	Plot = {
		Cols = 6,
		Rows = 10,
		TileSize = 4,
		StartRows = 3,
		VipBonusRows = 1,
		ExpansionBaseCost = 300,
		ExpansionGrowth = 2.1,
		Count = 6,
	},

	BackpackBase = 60,
	BackpackPass = 200,

	RestockInterval = 300,
	-- Offline growth is capped so a plant left for months doesn't overflow anything.
	OfflineGrowthCap = 3 * 86400,

	-- Server-side distance checks (studs)
	InteractRange = 46,
	StallRange = 22,
	GiftRange = 30,

	-- +10% sell value for each friend in the server (max +30%).
	FriendBoostPer = 0.1,
	FriendBoostMax = 0.3,

	-- A harvest worth at least this many times its crop's base value is announced.
	AnnounceValueMultiple = 20,
	-- Chance for a harvest to roll a "Huge" weight (x2.5 - x4).
	HugeChance = 0.02,

	-- Daily login streak: one claim per UTC day; missing a day resets to day 1.
	Daily = {
		{ Coins = 100 },
		{ Coins = 200, Seeds = { Tomato = 1 } },
		{ Coins = 350, Gear = { WateringCan = 10 } },
		{ Coins = 500, Seeds = { Corn = 2 } },
		{ Coins = 800, Gear = { Sprinkler = 1 } },
		{ Coins = 1200, Seeds = { Pumpkin = 1 } },
		{ Coins = 2500, Seeds = { Apple = 1 }, Gear = { LuckyFertilizer = 1 } },
	},

	-- Codes are case-insensitive. Add more any time; remove or set Expires (unix) to retire.
	Codes = {
		RELEASE = { Coins = 500, Seeds = { Blueberry = 2 } },
		SPROUT = { Gear = { WateringCan = 10 } },
		RAINYDAY = { Coins = 250, Gear = { Sprinkler = 1 } },
		-- Promise this one in the game description: "Like the game for a code at 1K likes!"
		LIKE1K = { Coins = 1500, Seeds = { Grape = 1 } },
	},

	-- Short session goals. Three are active at a time; finishing one rolls a new one.
	-- Target / reward scale up with how many goals the player has finished this session.
	Goals = {
		{ Id = "Harvest", Text = "Harvest %d crops", Base = 8, Reward = 60 },
		{ Id = "Plant", Text = "Plant %d seeds", Base = 6, Reward = 40 },
		{ Id = "Sell", Text = "Earn %s coins selling", Base = 300, Reward = 80, Money = true },
		{ Id = "Mutation", Text = "Harvest %d mutated fruit", Base = 1, Reward = 150 },
		{ Id = "BuySeed", Text = "Buy %d seeds", Base = 5, Reward = 50 },
		{ Id = "Water", Text = "Water plants %d times", Base = 5, Reward = 40 },
	},
	GoalsActive = 3,
	GoalScale = 1.6,

	-- Hint shown in the codes panel (social growth).
	CodesHint = "Like the game and join the group for new codes!",
}
