--[[
	Server events. "Admin" events rotate every GameConfig.Events.AdminInterval seconds
	(think "admin abuse" hours in other games, but automatic and fair for everyone).
	Effects:
	  Luck          multiplies Rare+ spawn weights
	  MythicBoost   multiplies Mythic and Secret weights on top of luck
	  MutationBoost multiplies mutation chances
	  SpawnRate     divides the carpet spawn interval
	  SpeedMult     carpet walk speed
	  IncomeMult    everyone's income
	  CashRain      coins fall over the carpet; touch them for cash
]]

return {
	Admin = {
		{ Id = "CashRain", Name = "CASH RAIN", Description = "Coins are falling from the sky! Grab them!", Color = { 255, 214, 60 }, CashRain = true },
		{ Id = "MythicMadness", Name = "MYTHIC MADNESS", Description = "Mythic and Secret Blobbies are 8x more likely!", Color = { 255, 64, 112 }, MythicBoost = 8 },
		{ Id = "MutationMayhem", Name = "MUTATION MAYHEM", Description = "Gold, Diamond and Rainbow mutations are 4x more likely!", Color = { 150, 236, 255 }, MutationBoost = 4 },
		{ Id = "Stampede", Name = "BLOBBY STAMPEDE", Description = "Blobbies pour out of the portal twice as fast!", Color = { 120, 230, 120 }, SpawnRate = 2.2, SpeedMult = 1.4 },
		{ Id = "DoubleCash", Name = "DOUBLE CASH", Description = "Everyone earns 2x cash!", Color = { 90, 255, 140 }, IncomeMult = 2 },
	},
	LuckyHour = { Id = "LuckyHour", Name = "LUCKY HOUR", Description = "Server luck x2 for everyone!", Color = { 120, 255, 120 }, Luck = 2 },
	ServerLuck = { Id = "ServerLuck", Name = "SERVER LUCK x2", Description = "A generous player boosted everyone's luck!", Color = { 90, 200, 255 }, Luck = 2 },
}
