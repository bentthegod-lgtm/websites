--[[
	RewardService - daily login streak, codes, friend-invite bonus and session goals.

	Session goals: 3 active at a time from ProgressionConfig.Goals; finishing one pays Clout
	and pulls in the next. Stats with Max = true track the best single value (e.g. best
	class), everything else accumulates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Economy = require(Shared.Economy)

local RewardService = {}

local services
local sessions = {} -- [player] = { stats = {}, active = { goalIndex... }, nextIndex, invited, done = n }
local lastRequest = {}

function RewardService.init(registry)
	services = registry
end

local function session(player)
	local s = sessions[player]
	if not s then
		s = { stats = {}, active = {}, nextIndex = 1, invited = false, done = 0 }
		for _ = 1, ProgressionConfig.ActiveGoals do
			table.insert(s.active, s.nextIndex)
			s.nextIndex += 1
		end
		sessions[player] = s
	end
	return s
end

function RewardService.goalsView(player)
	local s = session(player)
	local out = {}
	for _, index in ipairs(s.active) do
		local g = ProgressionConfig.Goals[index]
		if g then
			table.insert(out, { id = g.Id, text = g.Text, progress = math.min(g.Target, math.floor(s.stats[g.Stat] or 0)), target = g.Target, clout = g.Clout })
		end
	end
	return out
end

-- stat: a goal Stat name. `isMax` keeps the best value instead of adding.
function RewardService.track(player, stat, amount, isMax)
	if not player or not player.Parent then
		return
	end
	local s = session(player)
	if isMax then
		s.stats[stat] = math.max(s.stats[stat] or 0, amount or 0)
	else
		s.stats[stat] = (s.stats[stat] or 0) + (amount or 1)
	end
	local completed = false
	for i = #s.active, 1, -1 do
		local g = ProgressionConfig.Goals[s.active[i]]
		if g and g.Stat == stat and (s.stats[stat] or 0) >= g.Target then
			completed = true
			s.done += 1
			services.DataService.addClout(player, g.Clout, false)
			services.Remotes.Effect:FireClient(player, "Goal", { text = g.Text, clout = g.Clout })
			-- Replace with the next goal (wrapping around with a harder version if we run out).
			local nextGoal = ProgressionConfig.Goals[s.nextIndex]
			if nextGoal then
				s.active[i] = s.nextIndex
				s.nextIndex += 1
			else
				table.remove(s.active, i)
			end
		end
	end
	if completed then
		services.DataService.sendProfile(player)
	end
end

function RewardService.dailyView(player)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return nil
	end
	return Economy.daily(profile.Daily, os.time(), ProgressionConfig.DailyRewards)
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
	local amount = d.amount
	if services.ShopService.owns(player, "VIP") then
		amount = math.floor(amount * 1.5)
	end
	services.DataService.addClout(player, amount, false)
	services.Remotes.Effect:FireClient(player, "Daily", { streak = d.streak, clout = amount })
	services.DataService.sendProfile(player)
	return true, amount
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
	if def.Clout then
		services.DataService.addClout(player, def.Clout, false)
		table.insert(parts, "+" .. def.Clout .. " Clout")
	end
	if def.HallPass then
		profile.Tokens.HallPass += def.HallPass
		table.insert(parts, "+" .. def.HallPass .. " Fake Hall Pass")
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	return true, "Code redeemed: " .. table.concat(parts, ", ")
end

local function limited(player, gap)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < gap then
		return true
	end
	lastRequest[player] = now
	return false
end

function RewardService.invited(player)
	local s = session(player)
	if s.invited then
		return false
	end
	s.invited = true
	services.DataService.addClout(player, ProgressionConfig.InviteBonus, false)
	services.Remotes.Notify:FireClient(player, string.format("Thanks for bringing your class! +%d Clout", ProgressionConfig.InviteBonus), "good")
	services.DataService.sendProfile(player)
	return true
end

function RewardService.onPlayerRemoving(player)
	sessions[player] = nil
	lastRequest[player] = nil
end

function RewardService.start()
	local remotes = services.Remotes
	remotes.ClaimDaily.OnServerEvent:Connect(function(player)
		if limited(player, 1) then
			return
		end
		RewardService.claimDaily(player)
	end)
	remotes.RedeemCode.OnServerEvent:Connect(function(player, text)
		if limited(player, 1.5) then
			remotes.CodeResult:FireClient(player, false, "Slow down!")
			return
		end
		local ok, message = RewardService.redeem(player, text)
		remotes.CodeResult:FireClient(player, ok, message)
	end)
	remotes.InviteSent.OnServerEvent:Connect(function(player)
		if limited(player, 2) then
			return
		end
		RewardService.invited(player)
	end)
end

return RewardService
