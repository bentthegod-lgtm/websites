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
		{ Id = "snap1", Text = "Screenshot your test and reveal answers", Stat = "Revealed", Target = 2, Clout = 30 },
		{ Id = "gradeB", Text = "Get a B or better on a test", Stat = "GoodGrades", Target = 1, Clout = 60 },
		{ Id = "plane", Text = "Distract her with a paper airplane", Stat = "Planes", Target = 1, Clout = 30 },
		{ Id = "walkby", Text = "Snap a screenshot while she walks the rows", Stat = "WalkSnaps", Target = 1, Clout = 80 },
		{ Id = "quiz", Text = "Get the bonus question right", Stat = "QuizCorrect", Target = 1, Clout = 40 },
		{ Id = "clean", Text = "Finish a test without detention", Stat = "CleanClasses", Target = 1, Clout = 50 },
		{ Id = "ghost", Text = "GHOST a test: cheat and never get a '?'", Stat = "Ghosts", Target = 1, Clout = 90 },
		{ Id = "reveal10", Text = "Reveal 10 answers with your phone", Stat = "Revealed", Target = 10, Clout = 70 },
		{ Id = "aplus", Text = "Get an A+ (10 / 10)", Stat = "APlus", Target = 1, Clout = 120 },
		{ Id = "class400", Text = "Earn 400 Clout in one class", Stat = "BestClass", Target = 400, Clout = 150, Max = true },
	},
	ActiveGoals = 3,
}
