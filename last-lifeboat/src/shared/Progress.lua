--[[
	Progress - daily streak, codes, ship unlocks and the ship vote (pure, unit-tested).
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Progress = {}

--[[
	Daily streak. `day` is the UTC day number (os.time() // 86400). Returns
	(canClaim, newStreak, rewardIndex). Missing a day resets the streak to 1; after 7 days
	the last reward repeats.
]]
function Progress.daily(state, day)
	local last = tonumber(state.LastDay) or -10
	if last == day then
		return false, state.Streak or 0, nil
	end
	local streak = if last == day - 1 then (state.Streak or 0) + 1 else 1
	local index = math.min(streak, #GameConfig.DailyRewards)
	return true, streak, index
end

function Progress.normalizeCode(raw)
	if type(raw) ~= "string" or #raw > 40 then
		return nil
	end
	local code = string.upper((raw:gsub("%s", "")))
	if code == "" then
		return nil
	end
	return code
end

function Progress.shipUnlocked(shipKey, escapes)
	local def = GameConfig.Ships[shipKey]
	return def ~= nil and (escapes or 0) >= def.UnlockEscapes
end

--[[
	votes: { [voterId] = { ship = key, escapes = n } }. A vote only counts for a ship the
	voter has unlocked. Most votes wins; a tie goes to the easier ship; no votes = the Gull.
	Returns (winner, counts).
]]
function Progress.tally(votes)
	local counts = {}
	for _, key in ipairs(GameConfig.ShipOrder) do
		counts[key] = 0
	end
	for _, vote in pairs(votes or {}) do
		if type(vote) == "table" and counts[vote.ship] ~= nil and Progress.shipUnlocked(vote.ship, vote.escapes) then
			counts[vote.ship] += 1
		end
	end
	local best, bestN = GameConfig.ShipOrder[1], 0
	for _, key in ipairs(GameConfig.ShipOrder) do
		if counts[key] > bestN then
			best, bestN = key, counts[key]
		end
	end
	return best, counts
end

return Progress
