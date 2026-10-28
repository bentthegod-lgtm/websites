--[[
	Progress - pure helpers for daily challenges, prestige and stat lookups.

	* dayNumber(unix): UTC day index (same on every server and every time zone).
	* dailyFor(day, userId, stats, ownedMachines): three deterministic challenges for that
	  player and day, scaled to their own records so they are always achievable.
	* prestige(profile): eligibility and how many Lab Credits it would grant.
]]

local QuestConfig = require(script.Parent.Config.QuestConfig)
local MachineConfig = require(script.Parent.Config.MachineConfig)
local Rng = require(script.Parent.Rng)

local Progress = {}

function Progress.dayNumber(unix)
	return math.floor((tonumber(unix) or 0) / 86400)
end

function Progress.statValue(stats, key)
	return (stats and stats[key]) or 0
end

local function scaled(def, stats)
	local target = def.Base
	if def.Scale then
		target = math.max(def.Base, math.floor((Progress.statValue(stats, def.Scale) * def.Factor) / 10) * 10)
	end
	return math.min(target, def.Max)
end

-- Returns a list of { Id, Stat, Text, Target, Reward, Single, Machine }.
function Progress.dailyFor(day, userId, stats, ownedMachines)
	local rng = Rng.new(day * 7919 + (tonumber(userId) or 0) % 100003 + 17)
	local pool = table.clone(QuestConfig.Daily)
	local list = {}
	local bestScore = Progress.statValue(stats, "BestScore")
	local reward = math.clamp(math.floor((60 + bestScore * 0.25) / 5) * 5, 60, 5000)
	while #list < QuestConfig.DailyCount and #pool > 0 do
		local def = table.remove(pool, rng:NextInteger(1, #pool))
		local entry = { Id = def.Id, Stat = def.Stat, Single = def.Single == true, Reward = reward }
		if def.Id == "Machine" then
			local owned = ownedMachines or { "Standard" }
			local machineId = owned[rng:NextInteger(1, #owned)]
			entry.Machine = machineId
			entry.Stat = "Machine:" .. machineId
			entry.Target = def.Base
			entry.Text = string.format(def.Text, def.Base, MachineConfig.ById[machineId].Name)
		else
			entry.Target = scaled(def, stats)
			entry.Text = string.format(def.Text, entry.Target)
		end
		table.insert(list, entry)
	end
	return list
end

-- Prestige ("Lab Certification"): needs the Air Cannon and a best score of 3,000.
Progress.PrestigeScore = 3000
function Progress.prestige(profile)
	local stats = profile.Stats or {}
	local eligible = profile.Machines and profile.Machines.AirCannon == true and Progress.statValue(stats, "BestScore") >= Progress.PrestigeScore
	local credits = math.max(1, math.floor((profile.RunEarned or 0) / 60000) + 1)
	return {
		eligible = eligible == true,
		credits = credits,
		needScore = Progress.PrestigeScore,
		resets = { "Coins", "All upgrades", "Spring Cannon and Air Cannon (buy them again)" },
		keeps = { "Lab Credits (+5% coins each)", "Achievements", "Personal records", "Cosmetics", "Settings", "Facility access" },
	}
end

return Progress
