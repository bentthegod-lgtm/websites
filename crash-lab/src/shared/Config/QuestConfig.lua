--[[
	QuestConfig - tutorial steps, achievements, daily challenge templates and codes.
	Every step / achievement / challenge advances from server-side gameplay stats only.

	Stats are profile.Stats counters (bumped by the server) or records:
	  Launches, Runs, Impacts, Targets, Destroyed, Objectives, Rings, Upgrades, Earned,
	  BestDistance, BestHeight, BestScore, BestImpacts (records), Machines (count owned),
	  Prestige, RunScore / RunDistance / RunTargets / RunDestroyed (single-run values, for
	  daily challenges), "Machine:<Id>" (runs with a machine).
]]

local QuestConfig = {}

-- Interactive tutorial: each step advances on a real server event.
QuestConfig.Tutorial = {
	{ Event = "ClaimPad", Text = "Walk onto a glowing LAUNCH PAD and press E (or tap USE)" },
	{ Event = "Launch", Text = "Press LAUNCH to fire your crash-test dummy!" },
	{ Event = "RunDone", Text = "Watch it fly... and crash" },
	{ Event = "Upgrade", Text = "You earned coins! Open UPGRADES and buy Launch Power" },
	{ Event = "Launch", Text = "Launch again - feel the extra power" },
	{ Event = "Objective", Text = "Try the FEATURED OBJECTIVE shown above the launch panel" },
}

QuestConfig.Achievements = {
	{ Id = "FirstLaunch", Name = "Liftoff", Text = "Launch your first dummy", Stat = "Launches", Target = 1, Reward = 25 },
	{ Id = "FirstUpgrade", Name = "Tinkerer", Text = "Buy your first upgrade", Stat = "Upgrades", Target = 1, Reward = 40 },
	{ Id = "Dist100", Name = "Century", Text = "Reach 100 studs in one run", Stat = "BestDistance", Target = 100, Reward = 80 },
	{ Id = "Dist250", Name = "Long Haul", Text = "Reach 250 studs in one run", Stat = "BestDistance", Target = 250, Reward = 300 },
	{ Id = "Dist400", Name = "Into Orbit", Text = "Reach 400 studs in one run", Stat = "BestDistance", Target = 400, Reward = 1200, Cosmetic = "Astro" },
	{ Id = "Height100", Name = "Sky High", Text = "Fly 100 studs high", Stat = "BestHeight", Target = 100, Reward = 400 },
	{ Id = "Impacts12", Name = "Pinball", Text = "Make 12 impacts in one run", Stat = "BestImpacts", Target = 12, Reward = 350, Cosmetic = "Pinball" },
	{ Id = "FirstTarget", Name = "Bullseye Hunter", Text = "Hit a target", Stat = "Targets", Target = 1, Reward = 60 },
	{ Id = "FirstObjective", Name = "On Task", Text = "Complete an objective", Stat = "Objectives", Target = 1, Reward = 60 },
	{ Id = "Destroy25", Name = "Demolition Crew", Text = "Break 25 props", Stat = "Destroyed", Target = 25, Reward = 250, Cosmetic = "Hazard" },
	{ Id = "Ring3", Name = "Ringmaster", Text = "Fly through 3 rings", Stat = "Rings", Target = 3, Reward = 300 },
	{ Id = "Spring", Name = "Spring Loaded", Text = "Unlock the Spring Cannon", Stat = "Machines", Target = 2, Reward = 200 },
	{ Id = "AirCannon", Name = "Under Pressure", Text = "Unlock the Experimental Air Cannon", Stat = "Machines", Target = 3, Reward = 1500 },
	{ Id = "Score1500", Name = "Top Marks", Text = "Score 1,500 in one run", Stat = "BestScore", Target = 1500, Reward = 600 },
	{ Id = "Launch100", Name = "Lab Regular", Text = "Launch 100 dummies", Stat = "Launches", Target = 100, Reward = 1000, Cosmetic = "Gold" },
	{ Id = "Certified", Name = "Certified", Text = "Earn Lab Certification (prestige)", Stat = "Prestige", Target = 1, Reward = 0, Cosmetic = "Chrome" },
}
QuestConfig.AchievementById = {}
for _, a in ipairs(QuestConfig.Achievements) do
	QuestConfig.AchievementById[a.Id] = a
end

-- Daily challenges: three per UTC day, picked from these. Targets scale with the player's
-- own best results (never above what they can already roughly do), rewards scale with
-- their best score. No purchase is ever needed.
QuestConfig.Daily = {
	{ Id = "Distance", Stat = "RunDistance", Single = true, Text = "Reach %d studs in one run", Base = 80, Scale = "BestDistance", Factor = 0.85, Max = 480 },
	{ Id = "Score", Stat = "RunScore", Single = true, Text = "Score %d in one run", Base = 150, Scale = "BestScore", Factor = 0.8, Max = 4000 },
	{ Id = "Targets", Stat = "Targets", Text = "Hit %d targets or props", Base = 4, Max = 20 },
	{ Id = "Destroy", Stat = "Destroyed", Text = "Break %d props", Base = 6, Max = 30 },
	{ Id = "Launches", Stat = "Launches", Text = "Launch %d times", Base = 8, Max = 25 },
	{ Id = "Objectives", Stat = "Objectives", Text = "Complete %d objectives", Base = 2, Max = 8 },
	{ Id = "Machine", Stat = "Machine", Text = "Complete %d runs with the %s", Base = 3, Max = 6 },
}
QuestConfig.DailyCount = 3

QuestConfig.Codes = {
	CRASHLAB = { Coins = 150 },
	BUCKLEUP = { Coins = 300 },
}

return QuestConfig
