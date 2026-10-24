--[[
	Retention rewards: daily login streak, codes and session goals.
	Cash rewards with Minutes scale with the player's income per second so they stay
	meaningful at every stage; Minimum is the floor for new players.
]]

return {
	Daily = {
		{ Kind = "Cash", Minutes = 5, Minimum = 500, Text = "Cash" },
		{ Kind = "Cash", Minutes = 10, Minimum = 1500, Text = "More cash" },
		{ Kind = "ServerLuck", Seconds = 300, Text = "Server Luck x2 (5 min) for everyone" },
		{ Kind = "Cash", Minutes = 20, Minimum = 5000, Text = "Big cash" },
		{ Kind = "Blobby", Rarity = "Rare", Text = "A free Rare Blobby" },
		{ Kind = "Cash", Minutes = 45, Minimum = 20000, Text = "Huge cash" },
		{ Kind = "Blobby", Rarity = "Legendary", Text = "A free LEGENDARY Blobby" },
	},

	-- Codes are case-insensitive and can be redeemed once per player.
	Codes = {
		RELEASE = { Cash = 1000 },
		BLOBBY = { Cash = 2500 },
		SNATCH = { Blobby = "Rare" },
		LIKE = { Cash = 5000 }, -- "Like the game for a code!" message in the Codes panel
	},
	LikeMessage = "Like and favorite the game! Codes drop at like milestones. Try LIKE",

	-- Session goals: three are active at once; when one completes the next one from the
	-- pool takes its place. After the pool runs out it loops with bigger targets.
	GoalsActive = 3,
	Goals = {
		{ Id = "buy1", Stat = "Buy", Target = 1, Text = "Buy a Blobby from the carpet", Reward = { Minutes = 1, Minimum = 100 } },
		{ Id = "collect", Stat = "Collect", Target = 250, Text = "Collect $%s from your pedestals", Reward = { Minutes = 2, Minimum = 150 } },
		{ Id = "lock", Stat = "Lock", Target = 1, Text = "Lock your laser door", Reward = { Minutes = 2, Minimum = 200 } },
		{ Id = "buy3", Stat = "Buy", Target = 3, Text = "Buy %s Blobbies", Reward = { Minutes = 3, Minimum = 300 } },
		{ Id = "slap", Stat = "Slap", Target = 3, Text = "Slap %s players", Reward = { Minutes = 3, Minimum = 300 } },
		{ Id = "minutes", Stat = "Minutes", Target = 5, Text = "Play for %s minutes", Reward = { Minutes = 4, Minimum = 500 } },
		{ Id = "steal", Stat = "Steal", Target = 1, Text = "Steal a Blobby and bring it home", Reward = { Minutes = 6, Minimum = 1000 } },
		{ Id = "collectBig", Stat = "Collect", Target = 5000, Text = "Collect $%s from your pedestals", Reward = { Minutes = 5, Minimum = 1000 } },
		{ Id = "sell", Stat = "Sell", Target = 1, Text = "Sell a Blobby to make room", Reward = { Minutes = 2, Minimum = 300 } },
		{ Id = "epic", Stat = "BuyEpic", Target = 1, Text = "Buy an Epic (or better) Blobby", Reward = { Minutes = 8, Minimum = 3000 } },
		{ Id = "defend", Stat = "Defend", Target = 1, Text = "Slap a thief to save a Blobby", Reward = { Minutes = 6, Minimum = 1000 } },
		{ Id = "coins", Stat = "Coin", Target = 10, Text = "Grab %s coins during Cash Rain", Reward = { Minutes = 5, Minimum = 1000 } },
	},
}
