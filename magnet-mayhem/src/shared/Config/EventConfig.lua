--[[
	EventConfig - server-wide timed events. EventService runs them in a loop; add a new
	entry with a new Kind and handle it in EventService.start.
]]

return {
	MagneticStorm = {
		Name = "MAGNETIC STORM",
		FirstDelay = 360, -- seconds after the server starts
		IntervalMin = 720,
		IntervalMax = 1080,
		Duration = 120,
		SpawnMultiplier = 2.5, -- extra scrap while it lasts (still capped by MaxActiveScrap)
		ValueMultiplier = 1.25, -- scrap collected during the storm is worth more
		StormShardChance = 0.12, -- chance each spawn is a Storm Shard
		ParticipationTarget = 15, -- objects collected during the storm to earn the reward
		RewardSeconds = 60, -- reward = this many seconds of the player's recent earning rate
		RewardMin = 150,
	},
}
