--[[
	Coins, daily rewards, codes, session goals.
]]

return {
	StartingCoins = 150,

	Rewards = {
		Participation = 10,
		Kill = 25, -- your deflect eliminated someone
		Win = 120,
		-- Survival: coins per full SurvivalStep seconds alive in a round, capped.
		SurvivalStep = 10,
		SurvivalCoins = 3,
		SurvivalCap = 45,
		-- Win streak bonus added to a win: StreakBonus per streak level, capped.
		StreakBonus = 15,
		StreakBonusCap = 90,
		Parry = 1, -- every clean parry (capped per round)
		ParryCap = 20,
	},

	-- Day 1..7 then the cycle repeats; missing a day (more than 48h) resets the streak.
	DailyRewards = { 100, 150, 200, 250, 300, 400, 750 },

	-- Redeemable codes (case-insensitive). Expires: os.time() or nil for never.
	Codes = {
		RELEASE = { Coins = 300 },
		PARRY = { Coins = 150 },
		LIKETHEGAME = { Coins = 200 }, -- shown in the lobby as "Like the game for a code"
		RUMBLE = { PremiumSpins = 1, Expires = nil },
	},

	-- Short goals shown on the HUD for each session; rewarded once per server session.
	SessionGoals = {
		{ Id = "parry10", Text = "Land 10 parries", Stat = "Parries", Target = 10, Coins = 60 },
		{ Id = "kill3", Text = "Get 3 deflect kills", Stat = "Kills", Target = 3, Coins = 90 },
		{ Id = "play3", Text = "Play 3 rounds", Stat = "Rounds", Target = 3, Coins = 50 },
	},

	-- Bonus for inviting friends (granted when an invite prompt is sent, once per session).
	InviteBonus = 50,
}
