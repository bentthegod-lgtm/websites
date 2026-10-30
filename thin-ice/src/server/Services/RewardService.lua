--[[
	RewardService - coins, XP and levels from rounds, the daily login streak, daily goals
	and promo codes. Every grant goes through DataService (only once a profile is loaded).

	Daily goals reset each UTC day; progress comes from the stats DataService.bump()
	reports (Cores, Rescues, Snowballs, Escapes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local Progress = require(Shared.Progress)
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

local function freshGoals(data)
	local day = today()
	if data.Goals.Day ~= day then
		data.Goals.Day = day
		data.Goals.Progress = {}
		data.Goals.Done = {}
	end
end

function RewardService.goalsView(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return {}
	end
	local list = {}
	local current = data.Goals.Day == today()
	for _, goal in ipairs(GameConfig.Goals) do
		table.insert(list, {
			id = goal.Id,
			text = goal.Text,
			progress = if current then math.min(goal.Target, data.Goals.Progress[goal.Id] or 0) else 0,
			target = goal.Target,
			done = current and data.Goals.Done[goal.Id] == true,
			coins = goal.Coins,
		})
	end
	return list
end

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

-- Stat hook from DataService.bump: advances today's goals.
function RewardService.onStat(player, stat, n)
	local data = services.DataService.getProfile(player)
	if not data then
		return
	end
	if data.Goals.Day ~= today() then
		freshGoals(data)
		services.DataService.markDirty(player)
	end
	for _, goal in ipairs(GameConfig.Goals) do
		if goal.Stat == stat and not data.Goals.Done[goal.Id] then
			local progress = (data.Goals.Progress[goal.Id] or 0) + (n or 1)
			data.Goals.Progress[goal.Id] = progress
			if progress >= goal.Target then
				data.Goals.Done[goal.Id] = true
				services.DataService.addCoins(player, goal.Coins, true)
				services.Remotes.Notify:FireClient(player, string.format("Goal complete: %s  +%d coins", goal.Text, goal.Coins), "good")
			end
			services.DataService.markDirty(player)
		end
	end
	services.DataService.sendProfile(player)
end

-- Pays a finished round. Returns the reward table and the new level if it went up.
function RewardService.grantRound(player, summary)
	local data = services.DataService.getProfile(player)
	local reward = Progress.roundReward(summary)
	if not data then
		return reward, nil
	end
	local before = Progress.levelFor(data.Xp)
	services.DataService.addCoins(player, reward.coins, true)
	data.Xp += reward.xp
	services.DataService.bump(player, "Runs", 1)
	if summary.escaped then
		services.DataService.bump(player, "Escapes", 1)
	end
	local after = Progress.levelFor(data.Xp)
	local leveled = nil
	if after > before then
		leveled = after
		services.Remotes.Notify:FireClient(player, string.format("LEVEL UP! You're level %d.", after), "good")
		if services.PlayerService then
			services.PlayerService.refreshTags(player)
		end
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	return reward, leveled
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
	services.DataService.markDirty(player)
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
	if def.Flask then
		data.Boosts.Flask += def.Flask
		table.insert(parts, "+" .. def.Flask .. " Thermos Flask")
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	return true, "Code redeemed: " .. table.concat(parts, ", ")
end

function RewardService.onProfileLoaded(player)
	local data = services.DataService.getProfile(player)
	if data and data.Goals.Day ~= today() then
		freshGoals(data)
		services.DataService.markDirty(player)
	end
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
