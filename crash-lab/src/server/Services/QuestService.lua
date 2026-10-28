--[[
	QuestService - tutorial, achievements, daily challenges, codes and the featured
	objective. Everything advances from server events (stats bumped by the server, run
	results computed by the server); the client can only ask to skip / replay the
	tutorial or redeem a code.

	Rewards are granted exactly once: the achievement flag / daily Done flag / code flag
	is set BEFORE coins are added.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local QuestConfig = require(Shared.Config.QuestConfig)
local CourseConfig = require(Shared.Config.CourseConfig)
local MachineConfig = require(Shared.Config.MachineConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Progress = require(Shared.Progress)
local Economy = require(Shared.Economy)

local QuestService = {}

local services
local featured = {} -- [player] = objective id
local lastCode = {}
local lastTutorial = {}
local rng = Random.new()

function QuestService.init(registry)
	services = registry
end

local function profile(player)
	return services.DataService.getProfile(player)
end

-- Tutorial -----------------------------------------------------------------------------

function QuestService.tutorialStep(player)
	local data = profile(player)
	if not data or data.Tutorial.Done then
		return nil
	end
	return QuestConfig.Tutorial[data.Tutorial.Step]
end

function QuestService.tutorialEvent(player, eventName)
	local data = profile(player)
	local step = QuestService.tutorialStep(player)
	if not data or not step or step.Event ~= eventName then
		return
	end
	data.Tutorial.Step += 1
	if data.Tutorial.Step > #QuestConfig.Tutorial then
		data.Tutorial.Done = true
		services.Analytics.funnel(player, "TutorialDone")
		services.Remotes.Popup:FireClient(player, "TutorialDone", {})
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
end

-- Achievements -------------------------------------------------------------------------

local function checkAchievements(player, data, key)
	for _, def in ipairs(QuestConfig.Achievements) do
		if (key == nil or def.Stat == key) and not data.Achievements[def.Id] then
			if Progress.statValue(data.Stats, def.Stat) >= def.Target then
				data.Achievements[def.Id] = os.time() -- flag first, then reward
				if def.Reward > 0 then
					services.DataService.addCoins(player, def.Reward, true)
				end
				local cosmetic = def.Cosmetic and CosmeticConfig.Skins[def.Cosmetic]
				services.Remotes.Popup:FireClient(player, "Achievement", { id = def.Id, name = def.Name, text = def.Text, reward = def.Reward, cosmetic = cosmetic and cosmetic.Name or nil })
				services.DataService.markDirty(player)
				services.DataService.sendProfile(player)
			end
		end
	end
end

-- Daily challenges ---------------------------------------------------------------------

local function ownedMachines(data)
	local list = {}
	for _, id in ipairs(MachineConfig.Order) do
		if data.Machines[id] then
			table.insert(list, id)
		end
	end
	return list
end

local function dailyList(player, data)
	local day = Progress.dayNumber(os.time())
	if data.Daily.Day ~= day then
		data.Daily = { Day = day, Progress = {}, Done = {}, Seed = { Stats = { BestDistance = data.Stats.BestDistance or 0, BestScore = data.Stats.BestScore or 0 }, Machines = ownedMachines(data) } }
		services.DataService.markDirty(player)
	end
	-- Targets are frozen at the start of the day (from that morning's records), so
	-- beating a record mid-day doesn't move the goalposts.
	local seed = data.Daily.Seed or { Stats = data.Stats, Machines = ownedMachines(data) }
	return Progress.dailyFor(day, player.UserId, seed.Stats, seed.Machines), day
end

local function completeDaily(player, data, index, challenge)
	if data.Daily.Done[tostring(index)] then
		return
	end
	data.Daily.Done[tostring(index)] = true -- flag first, then reward
	services.DataService.addCoins(player, challenge.Reward, true)
	services.Remotes.Popup:FireClient(player, "Challenge", { text = challenge.Text, reward = challenge.Reward })
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
end

local function addDaily(player, data, stat, n, singleValue)
	local list = dailyList(player, data)
	for i, c in ipairs(list) do
		if not data.Daily.Done[tostring(i)] then
			local key = tostring(i)
			if c.Single and singleValue and c.Stat == stat then
				if singleValue >= c.Target then
					data.Daily.Progress[key] = c.Target
					completeDaily(player, data, i, c)
				else
					data.Daily.Progress[key] = math.max(data.Daily.Progress[key] or 0, singleValue)
				end
			elseif not c.Single and c.Stat == stat and n then
				data.Daily.Progress[key] = math.min(c.Target, (data.Daily.Progress[key] or 0) + n)
				if data.Daily.Progress[key] >= c.Target then
					completeDaily(player, data, i, c)
				end
			end
		end
	end
end

function QuestService.dailyView(player)
	local data = profile(player)
	if not data then
		return nil
	end
	local list, day = dailyList(player, data)
	local view = { day = day, resetsIn = (day + 1) * 86400 - os.time(), list = {} }
	for i, c in ipairs(list) do
		local key = tostring(i)
		table.insert(view.list, { text = c.Text, target = c.Target, progress = math.min(c.Target, data.Daily.Progress[key] or 0), reward = c.Reward, done = data.Daily.Done[key] == true })
	end
	return view
end

-- Stat hook (DataService.bump / record / setStat).
function QuestService.onStat(player, key, n)
	local data = profile(player)
	if not data then
		return
	end
	checkAchievements(player, data, key)
	if n and not string.find(key, "^Best") then
		addDaily(player, data, key, n, nil)
	end
end

-- Run hook (ScoringService.finish).
function QuestService.onRun(player, result, _run)
	local data = profile(player)
	if not data or result.voided then
		return
	end
	addDaily(player, data, "RunDistance", nil, result.distance)
	addDaily(player, data, "RunScore", nil, result.score)
end

-- Featured objective ---------------------------------------------------------------------

-- Picks an objective the player's current setup can plausibly reach.
function QuestService.rerollFeatured(player)
	local data = profile(player)
	if not data then
		return
	end
	local machine = MachineConfig.ById[data.Selected] or MachineConfig.ById.Standard
	local reach = Economy.reach(machine, services.UpgradeService.statsFor(player))
	local pool = {}
	for _, o in ipairs(CourseConfig.Objectives) do
		if o.MinReach <= reach and o.Id ~= featured[player] then
			table.insert(pool, o.Id)
		end
	end
	if #pool == 0 then
		pool = { "Reach100" }
	end
	featured[player] = pool[rng:NextInteger(1, #pool)]
end

function QuestService.featuredId(player)
	if not featured[player] then
		QuestService.rerollFeatured(player)
	end
	return featured[player]
end

function QuestService.featuredView(player)
	local id = QuestService.featuredId(player)
	local o = id and CourseConfig.ObjectiveById[id]
	if not o then
		return nil
	end
	local stats = services.UpgradeService.statsFor(player)
	return { id = o.Id, name = o.Name, points = o.Points, multiplier = stats.FeaturedMultiplier }
end

-- Codes --------------------------------------------------------------------------------

function QuestService.redeem(player, raw)
	local data = profile(player)
	if not data or type(raw) ~= "string" or #raw > 32 then
		return false, "Invalid code."
	end
	local code = string.upper((raw:gsub("%s", "")))
	local def = QuestConfig.Codes[code]
	if not def then
		return false, "That code doesn't exist."
	end
	if data.Codes[code] then
		return false, "You already used that code."
	end
	data.Codes[code] = os.time()
	services.DataService.addCoins(player, def.Coins or 0, false)
	services.DataService.sendProfile(player)
	return true, string.format("Code redeemed: +%d coins!", def.Coins or 0)
end

function QuestService.onProfileLoaded(player)
	local data = profile(player)
	if data then
		dailyList(player, data)
		checkAchievements(player, data, nil)
		QuestService.rerollFeatured(player)
	end
end

function QuestService.onPlayerRemoving(player)
	featured[player] = nil
	lastCode[player] = nil
	lastTutorial[player] = nil
end

function QuestService.start()
	local remotes = services.Remotes
	remotes.Tutorial.OnServerEvent:Connect(function(player, action)
		local data = profile(player)
		local t = os.clock()
		if not data or (lastTutorial[player] and t - lastTutorial[player] < 1) then
			return
		end
		lastTutorial[player] = t
		if action == "Skip" then
			data.Tutorial.Done = true
		elseif action == "Replay" then
			data.Tutorial.Done = false
			data.Tutorial.Step = 1
		else
			return
		end
		services.DataService.markDirty(player)
		services.DataService.sendProfile(player)
	end)
	remotes.RedeemCode.OnServerEvent:Connect(function(player, code)
		local t = os.clock()
		if lastCode[player] and t - lastCode[player] < 2 then
			return
		end
		lastCode[player] = t
		local ok, message = QuestService.redeem(player, code)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
	-- Midnight UTC: refresh everyone's dailies.
	task.spawn(function()
		local lastDay = Progress.dayNumber(os.time())
		while true do
			task.wait(30)
			local day = Progress.dayNumber(os.time())
			if day ~= lastDay then
				lastDay = day
				for _, player in ipairs(Players:GetPlayers()) do
					if profile(player) then
						services.DataService.sendProfile(player)
					end
				end
			end
		end
	end)
end

return QuestService
