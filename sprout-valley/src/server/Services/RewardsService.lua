--[[
	RewardsService - daily login streak, codes and short session goals.

	* Daily: one claim per UTC day; claiming on consecutive days grows the streak (7-day
	  cycle in GameConfig.Daily); missing a day resets it to day 1. VIP: +50% coins.
	* Codes: case-insensitive, once per player, optional Expires (unix seconds).
	* Goals: three active per session; finishing one pays out and rolls a harder one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Rewards = require(Shared.Rewards)
local Format = require(Shared.Format)

local RateLimit = require(script.Parent.RateLimit)

local RewardsService = {}

local services
local sessions = {} -- [player] = { goals = {...}, level = n }
local rng = Random.new()
local codeLimiter = RateLimit.new(0.5, 3)
local dailyLimiter = RateLimit.new(1, 2)

function RewardsService.init(registry)
	services = registry
end

local function dailyBundle(player, index)
	local base = GameConfig.Daily[index]
	local bundle = { Coins = base.Coins, Seeds = base.Seeds, Gear = base.Gear }
	if bundle.Coins and services.ShopService.owns(player, "VIP") then
		bundle.Coins = math.floor(bundle.Coins * ShopConfig.VipDailyBonus)
	end
	return bundle
end

function RewardsService.dailyView(player)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return nil
	end
	local status = Rewards.dailyStatus(profile.Daily.LastDay, profile.Daily.Streak, os.time(), #GameConfig.Daily)
	return {
		canClaim = status.canClaim,
		streak = status.streak,
		day = status.rewardIndex,
		secondsLeft = status.secondsLeft,
		lastStreak = profile.Daily.Streak,
	}
end

function RewardsService.claimDaily(player)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return nil
	end
	local now = os.time()
	local status = Rewards.dailyStatus(profile.Daily.LastDay, profile.Daily.Streak, now, #GameConfig.Daily)
	if not status.canClaim then
		services.Remotes.Notify:FireClient(player, "Come back in " .. Format.duration(status.secondsLeft) .. " for your next reward!", "info")
		return nil
	end
	profile.Daily.LastDay = Rewards.dayNumber(now)
	profile.Daily.Streak = status.streak
	local lines = services.DataService.grantBundle(player, dailyBundle(player, status.rewardIndex))
	services.Remotes.Effect:FireClient(player, "Daily", { day = status.rewardIndex, streak = status.streak, lines = lines })
	services.Remotes.Notify:FireClient(player, string.format("Day %d reward: %s", status.streak, table.concat(lines, ", ")), "good")
	services.DataService.sendProfile(player)
	return lines
end

function RewardsService.redeem(player, raw)
	local profile = services.DataService.getProfile(player)
	local code = Rewards.normalizeCode(raw)
	if not profile or not code then
		return false, "Invalid code."
	end
	local def = GameConfig.Codes[code]
	if not def or (def.Expires and os.time() > def.Expires) then
		return false, "That code doesn't exist (or expired)."
	end
	if profile.Codes[code] then
		return false, "You already used that code."
	end
	profile.Codes[code] = os.time()
	local lines = services.DataService.grantBundle(player, def)
	services.Remotes.Effect:FireClient(player, "Code", { lines = lines })
	services.DataService.sendProfile(player)
	return true, "Code redeemed: " .. table.concat(lines, ", ")
end

---------------------------------------------------------------------------------------------
-- Session goals
---------------------------------------------------------------------------------------------

local function session(player)
	local s = sessions[player]
	if not s then
		s = { level = 0, goals = {} }
		s.goals = Rewards.pickGoals(GameConfig.Goals, GameConfig.GoalsActive, rng, 0, GameConfig.GoalScale, {})
		sessions[player] = s
	end
	return s
end

local function goalText(goal)
	for _, def in ipairs(GameConfig.Goals) do
		if def.Id == goal.id then
			return string.format(def.Text, if def.Money then Format.coins(goal.target) else goal.target)
		end
	end
	return goal.id
end

function RewardsService.goalsView(player)
	local out = {}
	for _, goal in ipairs(session(player).goals) do
		table.insert(out, { id = goal.id, text = goalText(goal), progress = goal.progress, target = goal.target, reward = goal.reward })
	end
	return out
end

function RewardsService.event(player, eventId, amount)
	if not services.DataService.getProfile(player) then
		return
	end
	local s = session(player)
	local done = Rewards.progressGoals(s.goals, eventId, amount)
	for _, goal in ipairs(done) do
		services.DataService.addCoins(player, goal.reward, false)
		services.Remotes.Effect:FireClient(player, "Goal", { text = goalText(goal), reward = goal.reward })
		services.Remotes.Notify:FireClient(player, string.format("Goal complete: %s  +%s Coins", goalText(goal), Format.coins(goal.reward)), "good")
		local index = table.find(s.goals, goal)
		table.remove(s.goals, index)
		s.level += 1
		local level = math.floor(s.level / GameConfig.GoalsActive) + 1
		local fresh = Rewards.pickGoals(GameConfig.Goals, 1, rng, level, GameConfig.GoalScale, s.goals)
		if fresh[1] then
			table.insert(s.goals, index, fresh[1])
		end
	end
	if #done > 0 then
		services.DataService.sendProfile(player)
	end
end

function RewardsService.onProfileLoaded(player)
	session(player)
	local view = RewardsService.dailyView(player)
	if view and view.canClaim then
		services.Remotes.Notify:FireClient(player, "Your daily reward is ready! Open REWARDS.", "good")
	end
end

function RewardsService.onPlayerRemoving(player)
	sessions[player] = nil
	codeLimiter:forget(player)
	dailyLimiter:forget(player)
end

function RewardsService.start()
	local remotes = services.Remotes
	remotes.ClaimDaily.OnServerEvent:Connect(function(player)
		if dailyLimiter:allow(player) then
			RewardsService.claimDaily(player)
		end
	end)
	remotes.RedeemCode.OnServerEvent:Connect(function(player, code)
		if type(code) ~= "string" or not codeLimiter:allow(player) then
			return
		end
		local ok, message = RewardsService.redeem(player, code)
		remotes.Notify:FireClient(player, message, if ok then "good" else "warn")
	end)
	remotes.SetSetting.OnServerEvent:Connect(function(player, settingKey, value)
		local profile = services.DataService.getProfile(player)
		if not profile or type(value) ~= "boolean" or (settingKey ~= "AcceptGifts" and settingKey ~= "Music") then
			return
		end
		profile.Settings[settingKey] = value
		services.DataService.markDirty(player)
		services.DataService.sendProfile(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return RewardsService
