--[[
	Progress - pure helpers for quests, achievements and daily objectives.
	Stats are plain counters in the profile (profile.Stats[statKey]); see QuestConfig.
]]

local QuestConfig = require(script.Parent.Config.QuestConfig)
local ScrapConfig = require(script.Parent.Config.ScrapConfig)
local Rng = require(script.Parent.Rng)
local Format = require(script.Parent.Format)

local Progress = {}

-- Stat keys bumped by collecting one object. Rarity counters mean "this rarity or better".
function Progress.collectStats(def)
	local keys = { "Collect", "CollectId:" .. def.Id }
	local rank = ScrapConfig.rank(def)
	for name, tier in pairs(ScrapConfig.Rarities) do
		if rank >= tier.Rank then
			table.insert(keys, "CollectRarity:" .. name)
		end
	end
	local class = ScrapConfig.weightClass(def)
	if class == "Medium" or class == "Heavy" then
		table.insert(keys, "CollectMedium")
	end
	if class == "Heavy" then
		table.insert(keys, "CollectHeavy")
	end
	return keys
end

-- UTC day number (server time). Days roll over at 00:00 UTC for everyone.
function Progress.dayNumber(unixTime)
	return math.floor((unixTime or 0) / 86400)
end

function Progress.secondsUntilNextDay(unixTime)
	return 86400 - (unixTime % 86400)
end

-- Deterministic daily objectives for a player and day (same result if rolled twice).
function Progress.rollDaily(userId, day, tier)
	local cfg = QuestConfig.Daily
	local rng = Rng.new((userId % 1000003) * 31 + day * 7)
	local pool = table.clone(cfg.Templates)
	local out = {}
	local scaleTier = math.max(0, (tier or 1) - 1)
	for _ = 1, math.min(cfg.Count, #pool) do
		local pick = table.remove(pool, rng:NextInteger(1, #pool))
		local target = math.max(1, math.floor(pick.Target * pick.Scale ^ scaleTier + 0.5))
		local reward = math.floor(pick.Reward * cfg.RewardScale ^ scaleTier + 0.5)
		local text = if pick.Money then string.format(pick.Text, Format.short(target)) else string.format(pick.Text, target)
		table.insert(out, { Id = pick.Id, Text = text, Stat = pick.Stat, Target = target, Reward = reward, Progress = 0, Done = false })
	end
	return out
end

-- Achievement target (-1 means the whole codex).
function Progress.achievementTarget(def)
	if def.Target == -1 then
		return #ScrapConfig.List
	end
	return def.Target
end

-- Value of a stat for a requirement (Zone / Tier / Discover are stored as levels, the rest as counters).
function Progress.statValue(stats, key)
	return (stats and stats[key]) or 0
end

return Progress
