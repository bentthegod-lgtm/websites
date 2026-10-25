--[[
	Levels, school-year ranks, daily streak, codes, session goals and invite bonus.
]]

return {
	-- XP needed to go from level n to n+1 = Base + Step * (n - 1)
	XP = { Base = 60, Step = 25, MaxLevel = 60, LevelUpClout = 40 },
	XPPerClout = 0.5,
	XPPerClass = 15,

	Ranks = {
		{ Name = "Freshman", MinLevel = 1, Color = { 140, 220, 120 } },
		{ Name = "Sophomore", MinLevel = 5, Color = { 90, 180, 255 } },
		{ Name = "Junior", MinLevel = 10, Color = { 190, 120, 255 } },
		{ Name = "Senior", MinLevel = 16, Color = { 255, 170, 60 } },
		{ Name = "Legend", MinLevel = 25, Color = { 255, 80, 150 } },
	},

	DailyRewards = { 50, 80, 120, 160, 220, 300, 500 },

	Codes = {
		RELEASE = { Clout = 250 },
		NOPHONES = { Clout = 150 },
		SKIPCLASS = { Clout = 100, HallPass = 1 },
		LIKE1K = { Clout = 300 },
	},

	InviteBonus = 75,

	-- Session goals (3 active at a time; finishing one replaces it with the next in line).
	-- Stat names are tracked by RewardService.track.
	Goals = {
		{ Id = "walkby", Text = "Use your phone for 30s while she walks the rows", Stat = "WalkPhoneSeconds", Target = 30, Clout = 80 },
		{ Id = "class150", Text = "Earn 150 Clout in one class", Stat = "BestClass", Target = 150, Clout = 60, Max = true },
		{ Id = "quiz", Text = "Ace a Pop Quiz", Stat = "QuizCorrect", Target = 1, Clout = 40 },
		{ Id = "plane", Text = "Distract her with a paper airplane", Stat = "Planes", Target = 1, Clout = 30 },
		{ Id = "selfie3", Text = "Snap 3 selfies in class", Stat = "Selfies", Target = 3, Clout = 60 },
		{ Id = "clean", Text = "Finish a class without detention", Stat = "CleanClasses", Target = 1, Clout = 50 },
		{ Id = "texts10", Text = "Send 10 texts", Stat = "Texts", Target = 10, Clout = 50 },
		{ Id = "perfect5", Text = "Hit 5 PERFECT taps in Tap Dash", Stat = "Perfects", Target = 5, Clout = 50 },
		{ Id = "board60", Text = "Use your phone 60s while she writes on the board", Stat = "BoardPhoneSeconds", Target = 60, Clout = 50 },
		{ Id = "class400", Text = "Earn 400 Clout in one class", Stat = "BestClass", Target = 400, Clout = 150, Max = true },
	},
	ActiveGoals = 3,
}
