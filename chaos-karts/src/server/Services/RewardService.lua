--[[
	RewardService - race payouts (coins + XP by finishing place), the daily login streak and
	promo codes (RELEASE, CHAOS). Every grant goes through DataService (only once a profile
	is loaded); every result is reported back to the player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local Progress = require(Shared.Progress)
local RaceMath = require(Shared.RaceMath)
local RateLimit = require(script.Parent.RateLimit)

local RewardService = {}

local services
local limit = RateLimit.new(1, 3)

function RewardService.init(registry)
	services = registry
end

local function today()
	return os.time() // 86400
end
RewardService.today = today

function RewardService.dailyView(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local canClaim, streak, index = Progress.daily(data.Daily, today())
	return {
		canClaim = canClaim,
		streak = if canClaim then data.Daily.Streak else streak,
		nextStreak = streak,
		reward = if index then GameConfig.DailyRewards[index] else nil,
		rewards = GameConfig.DailyRewards,
	}
end

--[[
	Pays a finished race. info = { place, field, dnf, time, bestLap, mapId, laps }.
	Returns { coins, xp, levelBefore, levelAfter, newBest }.
]]
function RewardService.grantRace(player, info)
	local data = services.DataService.getProfile(player)
	local coins, xp = RaceMath.reward(GameConfig.Rewards, info.place, info.field, info.dnf)
	local result = { coins = coins, xp = xp, newBest = false }
	if not data then
		return result
	end
	local DS = services.DataService
	if not info.dnf then
		coins += GameConfig.Rewards.FinishBonus
		DS.bump(player, "Finishes", 1)
		if info.place == 1 then
			DS.bump(player, "Wins", 1)
		end
		if info.place <= 3 then
			DS.bump(player, "Podiums", 1)
		end
		local bestFinish = data.Stats.BestFinish
		if not bestFinish or info.place < bestFinish then
			data.Stats.BestFinish = info.place
		end
	end
	if info.bestLap and DS.recordLap(player, info.mapId, info.bestLap) then
		result.newBest = true
		coins += GameConfig.Rewards.BestLapBonus
	end
	DS.bump(player, "Races", 1)
	DS.bump(player, "Laps", info.laps or 0)
	DS.addCoins(player, coins, true)
	local before, after = DS.addXP(player, xp)
	result.coins, result.levelBefore, result.levelAfter = coins, before, after
	DS.markDirty(player)
	DS.sendProfile(player)
	return result
end

function RewardService.claimDaily(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your profile is still loading."
	end
	local canClaim, streak, index = Progress.daily(data.Daily, today())
	if not canClaim then
		return false, "Already claimed today - come back tomorrow!"
	end
	local coins = GameConfig.DailyRewards[index]
	data.Daily.LastDay = today()
	data.Daily.Streak = streak
	services.DataService.addCoins(player, coins, true)
	services.DataService.sendProfile(player)
	return true, string.format("Day %d streak! +%d coins", streak, coins)
end

function RewardService.redeem(player, raw)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your profile is still loading."
	end
	local code = Progress.normalizeCode(raw)
	local def = code and GameConfig.Codes[code]
	if not def then
		return false, "That code doesn't exist."
	end
	if data.Codes[code] then
		return false, "You already used that code."
	end
	data.Codes[code] = os.time()
	local parts = {}
	if def.Coins then
		services.DataService.addCoins(player, def.Coins, false)
		table.insert(parts, "+" .. def.Coins .. " coins")
	end
	if def.XP then
		services.DataService.addXP(player, def.XP)
		table.insert(parts, "+" .. def.XP .. " XP")
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	return true, "Code redeemed: " .. table.concat(parts, ", ")
end

function RewardService.onPlayerRemoving(player)
	limit:forget(player)
end

function RewardService.start()
	local remotes = services.Remotes
	remotes.ClaimDaily.OnServerEvent:Connect(function(player)
		if not limit:allow(player) then
			return
		end
		local ok, message = RewardService.claimDaily(player)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
	remotes.RedeemCode.OnServerEvent:Connect(function(player, raw)
		if not limit:allow(player) then
			return
		end
		local ok, message = RewardService.redeem(player, raw)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
end

return RewardService
