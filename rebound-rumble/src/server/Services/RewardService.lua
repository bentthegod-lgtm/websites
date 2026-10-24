--[[
	RewardService - daily login streak, codes, friend-invite bonus, session goals and
	end-of-round coin payouts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Economy = require(Shared.Economy)

local RewardService = {}

local services
local session = {} -- [player] = { Parries, Kills, Rounds, done = {}, invited }
local lastRequest = {}

function RewardService.init(registry)
	services = registry
end

local function sessionFor(player)
	local s = session[player]
	if not s then
		s = { Parries = 0, Kills = 0, Rounds = 0, done = {}, invited = false }
		session[player] = s
	end
	return s
end

function RewardService.goalsSnapshot(player)
	local s = sessionFor(player)
	local list = {}
	for _, goal in ipairs(ProgressionConfig.SessionGoals) do
		table.insert(list, { id = goal.Id, text = goal.Text, progress = math.min(goal.Target, s[goal.Stat] or 0), target = goal.Target, coins = goal.Coins, done = s.done[goal.Id] == true })
	end
	return list
end

function RewardService.sendGoals(player)
	services.Remotes.Goals:FireClient(player, RewardService.goalsSnapshot(player))
end

-- stat: "Parries" | "Kills" | "Rounds"
function RewardService.track(player, stat, amount)
	if not player or not player.Parent then
		return
	end
	local s = sessionFor(player)
	s[stat] = (s[stat] or 0) + (amount or 1)
	for _, goal in ipairs(ProgressionConfig.SessionGoals) do
		if goal.Stat == stat and not s.done[goal.Id] and s[stat] >= goal.Target then
			s.done[goal.Id] = true
			services.DataService.addCoins(player, goal.Coins)
			services.Remotes.Notify:FireClient(player, string.format("Goal complete: %s  +%d coins", goal.Text, goal.Coins), "good")
		end
	end
	RewardService.sendGoals(player)
end

function RewardService.claimDaily(player)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return false
	end
	local d = Economy.daily(profile.Daily, os.time(), ProgressionConfig.DailyRewards)
	if not d.claimable then
		return false
	end
	profile.Daily.Last = Economy.dayNumber(os.time())
	profile.Daily.Streak = d.streak
	services.DataService.addCoins(player, d.amount)
	services.Remotes.Notify:FireClient(player, string.format("Daily reward day %d: +%d coins!", d.streak, d.amount), "good")
	return true, d.amount
end

function RewardService.redeem(player, text)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return false, "Profile still loading."
	end
	local ok, def, code = Economy.redeem(ProgressionConfig.Codes, profile.Codes, text, os.time())
	if not ok then
		return false, def
	end
	profile.Codes[code] = true
	local parts = {}
	if def.Coins then
		profile.Coins += def.Coins
		table.insert(parts, "+" .. def.Coins .. " coins")
	end
	if def.PremiumSpins then
		profile.PremiumSpins += def.PremiumSpins
		table.insert(parts, "+" .. def.PremiumSpins .. " Premium Spin")
	end
	services.DataService.markDirty(player)
	services.DataService.updateLeaderstats(player)
	return true, "Code redeemed: " .. table.concat(parts, ", ")
end

--[[
	Pays out a finished round. summary = { kills, won, survivedSeconds, parries, ranked }
	Returns the reward breakdown (for the results screen).
]]
function RewardService.payRound(player, summary)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return nil
	end
	local stats = profile.Stats
	stats.Rounds += 1
	stats.Kills += summary.kills
	stats.Parries += summary.parries
	if summary.won then
		if summary.ranked then
			stats.Wins += 1
			profile.WinStreak += 1
			profile.BestStreak = math.max(profile.BestStreak, profile.WinStreak)
		else
			stats.PracticeWins += 1
		end
	else
		stats.Deaths += 1
		if summary.ranked then
			profile.WinStreak = 0
		end
	end
	local reward = Economy.matchReward({
		kills = summary.kills,
		won = summary.won,
		survivedSeconds = summary.survivedSeconds,
		parries = summary.parries,
		winStreak = if summary.won and summary.ranked then profile.WinStreak else 1,
	}, ProgressionConfig.Rewards, services.ShopService.coinMultiplier(player))
	profile.Coins += reward.total
	services.DataService.markDirty(player)
	services.DataService.updateLeaderstats(player)
	RewardService.track(player, "Rounds", 1)
	if summary.won and summary.ranked and services.LeaderboardService then
		services.LeaderboardService.submit(player, stats.Wins)
	end
	task.spawn(services.DataService.save, player)
	return reward
end

local function limited(player, gap)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < gap then
		return true
	end
	lastRequest[player] = now
	return false
end

-- Called by DataService on PlayerRemoving, before the leave save.
function RewardService.onPlayerRemoving(player)
	session[player] = nil
	lastRequest[player] = nil
end

function RewardService.start()
	local remotes = services.Remotes
	remotes.ClaimDaily.OnServerEvent:Connect(function(player)
		if limited(player, 1) then
			return
		end
		RewardService.claimDaily(player)
		services.DataService.sendProfile(player)
	end)
	remotes.RedeemCode.OnServerEvent:Connect(function(player, text)
		if limited(player, 1.5) then
			remotes.CodeResult:FireClient(player, false, "Slow down!")
			return
		end
		local ok, message = RewardService.redeem(player, text)
		remotes.CodeResult:FireClient(player, ok, message)
		if ok then
			services.DataService.sendProfile(player)
		end
	end)
	remotes.InviteSent.OnServerEvent:Connect(function(player)
		local s = sessionFor(player)
		if s.invited then
			return
		end
		s.invited = true
		services.DataService.addCoins(player, ProgressionConfig.InviteBonus)
		remotes.Notify:FireClient(player, string.format("Thanks for inviting friends! +%d coins", ProgressionConfig.InviteBonus), "good")
		services.DataService.sendProfile(player)
	end)
end

return RewardService
