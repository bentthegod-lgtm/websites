--[[
	RewardService - round payouts, the daily login streak, promo codes and the three session
	goals. Every grant goes through DataService (only once a profile is loaded).

	Session goals ("Escape 2 times", "Revive a teammate", "Bank a Rare or better") reset
	each time you join a server; progress comes from the stats DataService.bump() reports.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Progress = require(Shared.Progress)
local LootMath = require(Shared.LootMath)
local RateLimit = require(script.Parent.RateLimit)

local RewardService = {}

local services
local limit = RateLimit.new(1, 3)
local session = {}

function RewardService.init(registry)
	services = registry
end

local function today()
	return os.time() // 86400
end
RewardService.today = today

local function goals(player)
	local g = session[player]
	if not g then
		g = { progress = {}, done = {} }
		session[player] = g
	end
	return g
end

function RewardService.goalsView(player)
	local g = goals(player)
	local list = {}
	for _, goal in ipairs(GameConfig.SessionGoals) do
		table.insert(list, {
			id = goal.Id,
			text = goal.Text,
			progress = math.min(goal.Target, g.progress[goal.Id] or 0),
			target = goal.Target,
			done = g.done[goal.Id] == true,
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

-- Stat hook from DataService.bump: advances session goals.
function RewardService.onStat(player, stat, n)
	if not services.DataService.getProfile(player) then
		return
	end
	local g = goals(player)
	for _, goal in ipairs(GameConfig.SessionGoals) do
		if goal.Stat == stat and not g.done[goal.Id] then
			g.progress[goal.Id] = (g.progress[goal.Id] or 0) + (n or 1)
			if g.progress[goal.Id] >= goal.Target then
				g.done[goal.Id] = true
				services.DataService.addCoins(player, goal.Coins, true)
				services.Remotes.Notify:FireClient(player, string.format("Goal complete: %s  +%d coins", goal.Text, goal.Coins), "good")
			end
		end
	end
	services.DataService.sendProfile(player)
end

--[[
	Pays a finished round. summary = { escaped, items, shipKey, fullCrew, revives }.
	The x2 Loot pass is looked up here. Returns the LootMath.payout table.
]]
function RewardService.grantRound(player, summary)
	local data = services.DataService.getProfile(player)
	summary.double = summary.escaped and services.ShopService.ownsPass(player, "DoubleLoot") or false
	local pay = LootMath.payout(summary)
	if not data then
		return pay
	end
	services.DataService.addCoins(player, pay.coins, true)
	services.DataService.bump(player, "Rounds", 1)
	if summary.escaped then
		services.DataService.bump(player, "Escapes", 1)
		if pay.banked > 0 then
			services.DataService.bump(player, "LootBanked", pay.banked)
			services.DataService.record(player, "BestBank", pay.banked)
		end
		if pay.bestRank >= LootMath.rank("Rare") then
			services.DataService.bump(player, "BankedRarePlus", 1)
		end
		if summary.fullCrew then
			services.DataService.bump(player, "FullCrews", 1)
		end
	else
		services.DataService.bump(player, "LostAtSea", 1)
	end
	if not data.Tutorial.Done then
		data.Tutorial.Done = true
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	return pay
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
	if def.LifeJacket then
		data.Boosts.LifeJacket += def.LifeJacket
		table.insert(parts, "+" .. def.LifeJacket .. " Life Jacket")
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	if services.PlayerService then
		services.PlayerService.refresh(player)
	end
	return true, "Code redeemed: " .. table.concat(parts, ", ")
end

function RewardService.onPlayerRemoving(player)
	limit:forget(player)
	session[player] = nil
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
