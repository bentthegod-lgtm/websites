--[[
	RewardService - retention features:
	  * daily login streak (7-day cycle, rewards scale with income)
	  * codes (RewardConfig.Codes, once per player, case-insensitive)
	  * session goals (three at a time, see Goals.lua)
	  * offline earnings (capped, shown on join)
	  * friends-in-server income boost (+10% per friend, max +30%)
	  * gifting Blobbies by rarity (daily reward, codes, Mythic Crate)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local RewardConfig = require(Shared.Config.RewardConfig)
local BlobbyConfig = require(Shared.Config.BlobbyConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Goals = require(Shared.Goals)
local Spawner = require(Shared.Spawner)
local Timers = require(Shared.Timers)

local RewardService = {}

local services
local goalStates = {}
local rng = Random.new()

local function rand()
	return rng:NextNumber()
end

function RewardService.init(registry)
	services = registry
end

function RewardService.goalState(player)
	return goalStates[player]
end

---------------------------------------------------------------------------------------------
-- Gifts
---------------------------------------------------------------------------------------------

-- Rolls a species of `rarity` (normal mutation odds) and gives it. Returns species, mutation.
function RewardService.rollBlobby(rarity)
	local species = Spawner.rollSpecies(BlobbyConfig, rarity, rand)
	local mutation = Spawner.rollMutation(MutationConfig, rand, 1)
	return species, mutation
end

function RewardService.giveBlobby(player, rarity, source)
	local species, mutation = RewardService.rollBlobby(rarity)
	local plot = services.PlotService.plotOf(player)
	local from = plot and (plot.doorstep * CFrame.new(0, 0.3, 0)).Position
	services.BlobbyService.add(player, species.Id, mutation, { from = from, source = source })
	services.Remotes.Popup:FireClient(player, "Reveal", { species = species.Id, mutation = mutation, rarity = rarity, source = source })
	return species, mutation
end

---------------------------------------------------------------------------------------------
-- Goals
---------------------------------------------------------------------------------------------

function RewardService.recordGoal(player, stat, amount)
	local state = goalStates[player]
	if not state then
		return
	end
	local completed = Goals.record(state, RewardConfig.Goals, stat, amount)
	if #completed == 0 then
		if stat ~= "Collect" and stat ~= "Coin" then
			services.PlayerService.sendProfile(player)
		end
		return
	end
	local ips = services.PlayerService.incomePerSecond(player)
	for _, done in ipairs(completed) do
		local reward = Economy.scaledReward(done.goal.Reward, ips)
		services.PlayerService.addCash(player, reward)
		services.Remotes.Popup:FireClient(player, "Goal", {
			text = Goals.describe(done.goal, done.entry, if done.goal.Stat == "Collect" then Format.short else nil),
			reward = reward,
		})
		services.Remotes.Sfx:FireClient(player, "Reward")
	end
	services.PlayerService.sendProfile(player)
end

---------------------------------------------------------------------------------------------
-- Daily
---------------------------------------------------------------------------------------------

function RewardService.claimDaily(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return false
	end
	local today = Timers.dayIndex(os.time())
	local canClaim, streak, index = Timers.dailyStatus(data.Daily, today, #RewardConfig.Daily)
	if not canClaim then
		services.Remotes.Notify:FireClient(player, "Come back tomorrow for day " .. (index % #RewardConfig.Daily + 1) .. "!", "info")
		return false
	end
	data.Daily.LastDay = today
	data.Daily.Streak = streak
	services.DataService.markDirty(player)
	local reward = RewardConfig.Daily[index]
	local text
	if reward.Kind == "Cash" then
		local amount = Economy.scaledReward(reward, services.PlayerService.incomePerSecond(player))
		services.PlayerService.addCash(player, amount)
		text = Format.cash(amount)
	elseif reward.Kind == "ServerLuck" then
		services.EventService.addServerLuck(reward.Seconds, player.DisplayName .. "'s daily reward")
		text = reward.Text
	elseif reward.Kind == "Blobby" then
		local species = RewardService.giveBlobby(player, reward.Rarity, "daily")
		text = species.Name
	end
	services.Remotes.Popup:FireClient(player, "Daily", { day = index, streak = streak, text = text })
	services.Remotes.Sfx:FireClient(player, "Reward")
	services.PlayerService.sendProfile(player)
	return true, index
end

---------------------------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------------------------

function RewardService.redeem(player, raw)
	local data = services.DataService.getProfile(player)
	if not data or type(raw) ~= "string" or #raw == 0 or #raw > 32 then
		return false, "Invalid code"
	end
	local code = string.upper((string.gsub(raw, "%s+", "")))
	local reward = RewardConfig.Codes[code]
	if not reward then
		services.Remotes.Notify:FireClient(player, "That code doesn't exist (yet!)", "warn")
		return false, "Unknown"
	end
	if data.Codes[code] then
		services.Remotes.Notify:FireClient(player, "You already used that code.", "warn")
		return false, "Used"
	end
	data.Codes[code] = true
	services.DataService.markDirty(player)
	if reward.Cash then
		services.PlayerService.addCash(player, reward.Cash)
		services.Remotes.Popup:FireClient(player, "Code", { code = code, text = Format.cash(reward.Cash) })
	end
	if reward.Blobby then
		local species = RewardService.giveBlobby(player, reward.Blobby, "code")
		services.Remotes.Popup:FireClient(player, "Code", { code = code, text = species.Name })
	end
	services.Remotes.Sfx:FireClient(player, "Reward")
	services.PlayerService.sendProfile(player)
	return true
end

---------------------------------------------------------------------------------------------
-- Friends boost
---------------------------------------------------------------------------------------------

local function isFriend(a, b)
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	return ok and result == true
end

function RewardService.refreshFriends()
	local list = services.DataService.loadedPlayers()
	for _, player in ipairs(list) do
		local session = services.PlayerService.session(player)
		if session then
			session.friendSet = session.friendSet or {}
			local count = 0
			for _, other in ipairs(list) do
				if other ~= player then
					if session.friendSet[other] == nil then
						session.friendSet[other] = isFriend(player, other)
						if session.friendSet[other] then
							services.Remotes.Notify:FireClient(player, "Your friend " .. other.DisplayName .. " is here! +10% cash", "good")
						end
					end
					if session.friendSet[other] then
						count += 1
					end
				end
			end
			session.friends = count
		end
	end
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

function RewardService.start()
	local DataService = services.DataService
	DataService.ProfileLoaded:Connect(function(player, data, info)
		goalStates[player] = Goals.new(RewardConfig.Goals, RewardConfig.GoalsActive)
		RewardService.refreshFriends()
		-- Offline earnings (blobbies were placed by BlobbyService just before this).
		if info and info.offlineSeconds >= GameConfig.OfflineMinimumSeconds then
			local ips = services.PlayerService.incomePerSecond(player)
			local amount = Economy.offlineEarnings(ips, info.offlineSeconds, GameConfig.OfflineCapHours * 3600, GameConfig.OfflineRate)
			if amount > 0 then
				services.PlayerService.addCash(player, amount)
				services.Remotes.Popup:FireClient(player, "Offline", {
					amount = amount,
					seconds = math.min(info.offlineSeconds, GameConfig.OfflineCapHours * 3600),
					capped = info.offlineSeconds > GameConfig.OfflineCapHours * 3600,
				})
			end
		end
		if info and info.firstJoin then
			services.Remotes.Popup:FireClient(player, "Welcome", {})
		end
		services.PlayerService.sendProfile(player)
		data.LastSeen = os.time()
	end)
	DataService.Releasing:Connect(function(player)
		goalStates[player] = nil
		task.defer(RewardService.refreshFriends)
	end)

	local remotes = services.Remotes
	local lastClaim, lastCode = {}, {}
	remotes.ClaimDaily.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastClaim[player] and now - lastClaim[player] < 1 then
			return
		end
		lastClaim[player] = now
		RewardService.claimDaily(player)
	end)
	remotes.RedeemCode.OnServerEvent:Connect(function(player, code)
		local now = os.clock()
		if lastCode[player] and now - lastCode[player] < 2 then
			services.Remotes.Notify:FireClient(player, "Slow down!", "warn")
			return
		end
		lastCode[player] = now
		RewardService.redeem(player, code)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
		lastCode[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			for player in pairs(goalStates) do
				RewardService.recordGoal(player, "Minutes", 1)
			end
		end
	end)
end

return RewardService
