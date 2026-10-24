local load = require("./loader")
local Economy = load("Economy")
local ShopConfig = load("Config/ShopConfig")
local ProgressionConfig = load("Config/ProgressionConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Economy: " .. name, fn = fn })
end

local R = ProgressionConfig.Rewards

test("pass multipliers add up and are capped", function()
	assert(Economy.coinMultiplier({}, ShopConfig) == 1)
	assert(Economy.coinMultiplier({ VIP = true }, ShopConfig) == 1.5)
	assert(Economy.coinMultiplier({ DoubleCoins = true }, ShopConfig) == 2)
	local both = Economy.coinMultiplier({ VIP = true, DoubleCoins = true }, ShopConfig)
	assert(both <= ShopConfig.MaxCoinMultiplier and both == 2.5)
end)

test("match reward: kills, survival cap, win + streak", function()
	local r = Economy.matchReward({ kills = 2, won = false, survivedSeconds = 35, parries = 4 }, R, 1)
	assert(r.total == R.Participation + 2 * R.Kill + 4 * R.Parry + 3 * R.SurvivalCoins, "loss total " .. r.total)
	local long = Economy.matchReward({ kills = 0, survivedSeconds = 99999 }, R, 1)
	assert(long.total == R.Participation + R.SurvivalCap, "survival not capped")
	local win = Economy.matchReward({ kills = 0, won = true, survivedSeconds = 0, winStreak = 4 }, R, 2)
	assert(win.total == (R.Participation + R.Win + 3 * R.StreakBonus) * 2, "win " .. win.total)
	local huge = Economy.matchReward({ won = true, winStreak = 1000, parries = 1000 }, R, 1)
	assert(huge.total == R.Participation + R.Win + R.StreakBonusCap + R.ParryCap, "caps " .. huge.total)
end)

test("daily streak: claim, same day, next day, missed day", function()
	local rewards = ProgressionConfig.DailyRewards
	local day = 86400
	local t0 = 20000 * day + 3600
	local first = Economy.daily({ Last = 0, Streak = 0 }, t0, rewards)
	assert(first.claimable and first.streak == 1 and first.amount == rewards[1])
	local again = Economy.daily({ Last = Economy.dayNumber(t0), Streak = 1 }, t0 + 60, rewards)
	assert(not again.claimable and again.nextIn > 0)
	local nextDay = Economy.daily({ Last = Economy.dayNumber(t0), Streak = 1 }, t0 + day, rewards)
	assert(nextDay.claimable and nextDay.streak == 2 and nextDay.amount == rewards[2])
	local missed = Economy.daily({ Last = Economy.dayNumber(t0), Streak = 5 }, t0 + 3 * day, rewards)
	assert(missed.streak == 1, "missed day should reset")
	local wrap = Economy.daily({ Last = Economy.dayNumber(t0), Streak = #rewards }, t0 + day, rewards)
	assert(wrap.amount == rewards[1], "cycle should wrap")
end)

test("codes: normalised, once only, expiry, junk rejected", function()
	local codes = { RELEASE = { Coins = 5 }, OLD = { Coins = 1, Expires = 10 } }
	local used = {}
	local ok, def, code = Economy.redeem(codes, used, "  release ", 0)
	assert(ok and def.Coins == 5 and code == "RELEASE")
	used[code] = true
	assert(not Economy.redeem(codes, used, "RELEASE", 0))
	assert(not Economy.redeem(codes, used, "OLD", 11))
	assert(not Economy.redeem(codes, used, "nope", 0))
	assert(not Economy.redeem(codes, used, string.rep("A", 100), 0))
	assert(not Economy.redeem(codes, used, "a-b;drop", 0))
	assert(not Economy.redeem(codes, used, 42, 0))
	for name in pairs(ProgressionConfig.Codes) do
		assert(Economy.normalizeCode(name) == name, "config code not normalised: " .. name)
	end
end)

return cases
