--[[
	Economy math (pure, unit tested). All configs are passed in so this module has no
	Roblox dependencies and runs in Lune.
]]

local Economy = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
Economy.finite = finite

function Economy.blobbyIncome(species, mutationDef)
	return species.Income * (if mutationDef then mutationDef.Mult else 1)
end

function Economy.blobbyPrice(species, mutationDef)
	return math.floor(species.Price * (if mutationDef then mutationDef.PriceMult else 1))
end

function Economy.sellValue(price, refund)
	return math.max(1, math.floor(price * refund))
end

function Economy.rebirthMultiplier(rebirths, rebirthCfg)
	return 1 + math.max(0, rebirths) * rebirthCfg.MultPer
end

function Economy.rebirthCost(rebirths, rebirthCfg)
	return math.floor(rebirthCfg.BaseCost * rebirthCfg.CostGrowth ^ math.max(0, rebirths))
end

function Economy.friendBoost(friendCount, per, max)
	return math.clamp(friendCount * per, 0, max)
end

--[[
	opts = { rebirths, rebirthCfg, doubleCash: boolean, friends: number, friendPer, friendMax,
	         eventMult: number? }
]]
function Economy.playerMultiplier(opts)
	local mult = Economy.rebirthMultiplier(opts.rebirths or 0, opts.rebirthCfg)
	if opts.doubleCash then
		mult *= 2
	end
	mult *= 1 + Economy.friendBoost(opts.friends or 0, opts.friendPer or 0, opts.friendMax or 0)
	mult *= opts.eventMult or 1
	return mult
end

function Economy.slotCount(rebirths, vip, extraSlots, gameCfg)
	local slots = gameCfg.BaseSlots + math.min(math.max(0, rebirths), gameCfg.MaxRebirthSlots)
	if vip then
		slots += gameCfg.VipSlots
	end
	if extraSlots then
		slots += gameCfg.ExtraSlotsPass
	end
	return math.min(slots, gameCfg.MaxPedestals)
end

-- Rounds to 2 significant figures so packs read nicely: 12345 -> 12000.
function Economy.roundNice(n)
	if not finite(n) or n <= 0 then
		return 0
	end
	if n < 100 then
		return math.floor(n)
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / magnitude) * magnitude
end

function Economy.scaledReward(reward, incomePerSecond)
	local ips = if finite(incomePerSecond) then math.max(0, incomePerSecond) else 0
	return Economy.roundNice(math.max(reward.Minimum or 0, ips * (reward.Minutes or 0) * 60))
end

function Economy.cashPackAmount(pack, incomePerSecond)
	return Economy.scaledReward(pack, incomePerSecond)
end

-- Offline earnings for `elapsed` seconds away, capped and scaled by `rate`.
function Economy.offlineEarnings(incomePerSecond, elapsed, capSeconds, rate)
	if not finite(incomePerSecond) or not finite(elapsed) or elapsed <= 0 or incomePerSecond <= 0 then
		return 0
	end
	return math.floor(incomePerSecond * math.min(elapsed, capSeconds) * rate)
end

return Economy
