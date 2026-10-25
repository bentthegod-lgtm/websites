local load = require("./loader")
local Economy = load("Economy")
local ShopConfig = load("Config/ShopConfig")
local UpgradeConfig = load("Config/UpgradeConfig")
local ProgressionConfig = load("Config/ProgressionConfig")
local GameConfig = load("Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Economy: " .. name, fn = fn })
end

test("pass multipliers add up and are capped", function()
	assert(Economy.cloutMultiplier({}, ShopConfig) == 1)
	assert(Economy.cloutMultiplier({ DoubleClout = true }, ShopConfig) == 2)
	local both = Economy.cloutMultiplier({ DoubleClout = true, VIP = true }, ShopConfig)
	assert(math.abs(both - 2.1) < 1e-9 and both <= ShopConfig.MaxCloutMultiplier)
end)

test("phone stats: defaults, upgrades and bounded passes", function()
	local base = Economy.phoneStats({}, {}, UpgradeConfig)
	assert(base.answers == 2 and base.scan == 6 and base.glow == 1 and base.noise == 1 and base.cover == 1)
	assert(base.hide == 0.45 and base.linger == 1.0 and base.watch == nil)
	local maxed = Economy.phoneStats({ Phone = 4, Scanner = 4, Case = 4, Earbuds = 4, Cover = 3, Hide = 4, Backpack = 2, Watch = 2 }, {}, UpgradeConfig)
	assert(maxed.answers == 5 and maxed.scan < base.scan and maxed.glow < base.glow and maxed.noise < base.noise and maxed.hide == 0.2)
	assert(maxed.watch and maxed.watch.cooldown > 0 and maxed.watch.glance > 0)
	local passes = Economy.phoneStats({}, { ProPhone = true, SilentMode = true, ExtraHide = true }, UpgradeConfig)
	assert(passes.answers == 3, "pro phone should add exactly 1 answer")
	local proMaxed = Economy.phoneStats({ Phone = 4 }, { ProPhone = true }, UpgradeConfig)
	assert(proMaxed.answers == UpgradeConfig.MaxAnswersPerSnap, "pro phone beats the free max")
	assert(passes.noise == UpgradeConfig.Earbuds.Tiers[3].Noise, "silent mode not tier 3")
	assert(passes.noise > maxed.noise, "silent mode beats the best Clout earbuds")
	assert(math.abs(passes.hide - 0.4) < 1e-9)
	local best = Economy.phoneStats({ Hide = 4 }, { ExtraHide = true }, UpgradeConfig)
	assert(best.hide >= UpgradeConfig.MinHideSeconds)
	-- Garbage tiers are clamped.
	local junk = Economy.phoneStats({ Phone = 999, Case = -4 }, {}, UpgradeConfig)
	assert(junk.answers == 5 and junk.glow == 1)
end)

test("upgrade prices go up and stop at the max tier", function()
	for _, key in ipairs(UpgradeConfig.Order) do
		local def = UpgradeConfig[key]
		local tier = def.Start
		local last = 0
		while true do
			local price, nextTier = Economy.nextUpgrade(UpgradeConfig, key, tier)
			if not price then
				break
			end
			assert(price > last, key .. " price does not increase")
			last = price
			tier = nextTier
		end
		assert(tier == Economy.maxTier(UpgradeConfig, key), key .. " stops early")
	end
end)

test("XP levels up across several levels and ranks follow the school year", function()
	local level, xp, gained = Economy.addXP(1, 0, 1000, ProgressionConfig.XP)
	assert(level > 3 and gained == level - 1 and xp < Economy.xpToNext(level, ProgressionConfig.XP))
	assert(Economy.rankFor(1, ProgressionConfig.Ranks).Name == "Freshman")
	assert(Economy.rankFor(5, ProgressionConfig.Ranks).Name == "Sophomore")
	assert(Economy.rankFor(12, ProgressionConfig.Ranks).Name == "Junior")
	assert(Economy.rankFor(16, ProgressionConfig.Ranks).Name == "Senior")
	assert(Economy.rankFor(60, ProgressionConfig.Ranks).Name == "Legend")
	local capped = Economy.addXP(ProgressionConfig.XP.MaxLevel, 0, 1e9, ProgressionConfig.XP)
	assert(capped == ProgressionConfig.XP.MaxLevel)
end)

test("daily streak: claim, already claimed, continue, reset", function()
	local day = 86400
	local now = 20000 * day + 100
	local d = Economy.daily({ Last = 0, Streak = 0 }, now, ProgressionConfig.DailyRewards)
	assert(d.claimable and d.streak == 1 and d.amount == ProgressionConfig.DailyRewards[1])
	local again = Economy.daily({ Last = 20000, Streak = 1 }, now, ProgressionConfig.DailyRewards)
	assert(not again.claimable and again.nextIn > 0)
	local nextDay = Economy.daily({ Last = 20000, Streak = 1 }, now + day, ProgressionConfig.DailyRewards)
	assert(nextDay.claimable and nextDay.streak == 2)
	local missed = Economy.daily({ Last = 20000, Streak = 5 }, now + 3 * day, ProgressionConfig.DailyRewards)
	assert(missed.streak == 1)
	local wrap = Economy.daily({ Last = 20000, Streak = 7 }, now + day, ProgressionConfig.DailyRewards)
	assert(wrap.amount == ProgressionConfig.DailyRewards[1])
end)

test("codes: RELEASE, NOPHONES and SKIPCLASS exist, case-insensitive, once each", function()
	for _, code in ipairs({ "RELEASE", "NOPHONES", "SKIPCLASS" }) do
		assert(ProgressionConfig.Codes[code], code .. " missing")
	end
	local ok, def, code = Economy.redeem(ProgressionConfig.Codes, {}, " nophones ", 0)
	assert(ok and def.Clout and code == "NOPHONES")
	assert(not Economy.redeem(ProgressionConfig.Codes, { NOPHONES = true }, "NOPHONES", 0))
	assert(not Economy.redeem(ProgressionConfig.Codes, {}, "NOT_A_CODE", 0))
	assert(not Economy.redeem(ProgressionConfig.Codes, {}, "<script>", 0))
	assert(not Economy.redeem(ProgressionConfig.Codes, {}, string.rep("A", 80), 0))
	assert(not Economy.redeem(ProgressionConfig.Codes, {}, nil, 0))
end)

test("detention bail scales with level", function()
	assert(Economy.bailCost(1, GameConfig) == GameConfig.DetentionBailBase)
	assert(Economy.bailCost(11, GameConfig) > Economy.bailCost(1, GameConfig))
end)

return cases
