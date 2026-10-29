--[[
	Progress - pure helpers for daily challenges, achievements and the Collection Book.
	Days are UTC days of server time (os.time()), so everyone resets at 00:00 UTC.
]]

local QuestConfig = require(script.Parent.Config.QuestConfig)
local LootConfig = require(script.Parent.Config.LootConfig)
local Rng = require(script.Parent.Rng)
local Format = require(script.Parent.Format)

local Progress = {}

function Progress.dayNumber(unixTime)
	return math.floor((unixTime or 0) / 86400)
end

function Progress.secondsUntilNextDay(unixTime)
	return 86400 - ((unixTime or 0) % 86400)
end

-- Deterministic: the same player, day and depth always roll the same challenges.
function Progress.rollDaily(userId, day, depth)
	local cfg = QuestConfig.Daily
	depth = math.max(1, math.floor(depth or 1))
	local rng = Rng.new((userId % 1000003) * 31 + day * 7 + depth)
	local pool = {}
	for _, t in ipairs(cfg.Templates) do
		if depth >= t.MinDepth then
			table.insert(pool, t)
		end
	end
	local scale = cfg.MoneyScale ^ (depth - 1)
	local out = {}
	for _ = 1, math.min(cfg.Count, #pool) do
		local t = table.remove(pool, rng:NextInteger(1, #pool))
		local target = if t.Money then math.floor(t.Target * scale) else t.Target
		local stat = t.Stat
		if stat == "VisitDeepest" then
			stat = "Visit:" .. depth
		end
		table.insert(out, {
			Id = t.Id,
			Text = string.format(t.Text, if t.Money then Format.short(target) else tostring(target)),
			Stat = stat,
			Target = target,
			Cash = math.floor(t.Cash * scale),
			Tokens = t.Tokens,
			Progress = 0,
			Done = false,
		})
	end
	return out
end

-- Number of entries in the Collection Book.
function Progress.bookSize()
	return #LootConfig.List
end

-- Achievement target: -1 = the whole book, -2 = half of it (rounded up).
function Progress.achievementTarget(def)
	if def.Target == -1 then
		return Progress.bookSize()
	elseif def.Target == -2 then
		return math.ceil(Progress.bookSize() / 2)
	end
	return def.Target
end

-- Stat keys bumped by collecting one item.
function Progress.collectStats(def)
	return { "Collect", "Collect:" .. def.Category, "CollectId:" .. def.Id }
end

function Progress.isRareFind(def)
	return LootConfig.rank(def) >= 4
end

return Progress
