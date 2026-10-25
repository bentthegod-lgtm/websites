--[[
	QuestService - tutorial, starter quests, achievements, daily objectives, the Scrap Codex
	and codes. Everything advances from server events (DataService.bump / tutorialEvent /
	discover); the client can only ask to skip or replay the tutorial.

	Rewards are granted exactly once: the quest index / achievement flag / daily Done flag
	is set BEFORE coins are added.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local QuestConfig = require(Shared.Config.QuestConfig)
local ScrapConfig = require(Shared.Config.ScrapConfig)
local MagnetConfig = require(Shared.Config.MagnetConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Progress = require(Shared.Progress)
local Format = require(Shared.Format)

local QuestService = {}

local services
local tutorialCounts = {}
local lastCode = {}

function QuestService.init(registry)
	services = registry
end

local function profile(player)
	return services.DataService.getProfile(player)
end

-- Tutorial -------------------------------------------------------------------------------

function QuestService.tutorialStep(player)
	local data = profile(player)
	if not data or data.Tutorial.Done then
		return nil
	end
	return QuestConfig.Tutorial[data.Tutorial.Step]
end

local function advanceTutorial(player, data)
	data.Tutorial.Step += 1
	tutorialCounts[player] = 0
	if data.Tutorial.Step > #QuestConfig.Tutorial then
		data.Tutorial.Done = true
		services.Analytics.funnel(player, "TutorialDone")
		services.Remotes.Popup:FireClient(player, "TutorialDone", {})
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
end

function QuestService.tutorialEvent(player, event)
	local data = profile(player)
	local step = QuestService.tutorialStep(player)
	if not data or not step or step.Event ~= event then
		return
	end
	if step.Count then
		tutorialCounts[player] = (tutorialCounts[player] or 0) + 1
		if tutorialCounts[player] < step.Count then
			services.DataService.sendProfile(player)
			return
		end
	end
	advanceTutorial(player, data)
end

function QuestService.tutorialProgress(player)
	return tutorialCounts[player] or 0
end

-- Starter quests -------------------------------------------------------------------------

local function checkStarter(player, data)
	local guard = 0
	while guard < #QuestConfig.Starter do
		guard += 1
		local quest = QuestConfig.Starter[data.Quest.Index]
		if not quest then
			return
		end
		if Progress.statValue(data.Stats, quest.Stat) < quest.Target then
			return
		end
		data.Quest.Index += 1 -- mark first, then reward (never twice)
		services.DataService.addCoins(player, quest.Reward, true)
		services.Remotes.Popup:FireClient(player, "Quest", { text = quest.Text, reward = quest.Reward })
		services.DataService.sendProfile(player)
	end
end

function QuestService.questView(player)
	local data = profile(player)
	if not data then
		return nil
	end
	local quest = QuestConfig.Starter[data.Quest.Index]
	if not quest then
		return { done = true, index = data.Quest.Index, total = #QuestConfig.Starter }
	end
	return {
		index = data.Quest.Index,
		total = #QuestConfig.Starter,
		text = quest.Text,
		progress = math.min(quest.Target, Progress.statValue(data.Stats, quest.Stat)),
		target = quest.Target,
		reward = quest.Reward,
	}
end

-- Achievements ---------------------------------------------------------------------------

local function grantCosmetic(data, achievementId)
	for skinId, skin in pairs(MagnetConfig.Skins) do
		if skin.Achievement == achievementId then
			data.Cosmetics.Owned[skinId] = true
		end
	end
	for trailId, trail in pairs(MagnetConfig.Trails) do
		if trail.Achievement == achievementId then
			data.Cosmetics.Owned[trailId] = true
		end
	end
end

local function checkAchievements(player, data, key)
	for _, def in ipairs(QuestConfig.Achievements) do
		if (key == nil or def.Stat == key) and not data.Achievements[def.Id] then
			if Progress.statValue(data.Stats, def.Stat) >= Progress.achievementTarget(def) then
				data.Achievements[def.Id] = os.time()
				grantCosmetic(data, def.Id)
				services.DataService.markDirty(player)
				services.Remotes.Popup:FireClient(player, "Achievement", { id = def.Id, name = def.Name, text = def.Text })
				services.DataService.sendProfile(player)
			end
		end
	end
end

-- Daily objectives (UTC days, server time) ------------------------------------------------

function QuestService.ensureDaily(player)
	local data = profile(player)
	if not data then
		return
	end
	local day = Progress.dayNumber(os.time())
	if data.Daily.Day ~= day or type(data.Daily.List) ~= "table" or #data.Daily.List == 0 then
		data.Daily = { Day = day, List = Progress.rollDaily(player.UserId, day, data.Tier) }
		services.DataService.markDirty(player)
	end
end

local function bumpDaily(player, data, key, n)
	QuestService.ensureDaily(player)
	for _, objective in ipairs(data.Daily.List) do
		if objective.Stat == key and not objective.Done then
			objective.Progress = math.min(objective.Target, objective.Progress + (n or 1))
			if objective.Progress >= objective.Target then
				objective.Done = true -- mark first, then reward
				services.DataService.addCoins(player, objective.Reward, true)
				services.Remotes.Popup:FireClient(player, "Daily", { text = objective.Text, reward = objective.Reward })
			end
		end
	end
end

function QuestService.dailyView(player)
	local data = profile(player)
	if not data then
		return nil
	end
	QuestService.ensureDaily(player)
	return { list = data.Daily.List, resetIn = Progress.secondsUntilNextDay(os.time()) }
end

-- Stat hook (called by DataService.bump / setStat) ------------------------------------------

local LEVEL_STATS = { Tier = true, Zone = true, Discover = true }

function QuestService.onStat(player, key, n)
	local data = profile(player)
	if not data then
		return
	end
	if not LEVEL_STATS[key] then
		bumpDaily(player, data, key, n)
	end
	checkStarter(player, data)
	checkAchievements(player, data, key)
end

-- Scrap Codex ------------------------------------------------------------------------------

function QuestService.discover(player, def, value)
	local data = profile(player)
	if not data then
		return
	end
	local entry = data.Codex[def.Id]
	local first = entry == nil
	if first then
		entry = { n = 0, best = 0, first = os.time() }
		data.Codex[def.Id] = entry
	end
	entry.n += 1
	entry.best = math.max(entry.best, value)
	if first then
		local count = 0
		for _ in pairs(data.Codex) do
			count += 1
		end
		services.DataService.setStat(player, "Discover", count)
		services.Remotes.Popup:FireClient(player, "Discovery", { id = def.Id, name = def.Name, rarity = def.Rarity, count = count, total = #ScrapConfig.List })
	end
end

-- Codes ------------------------------------------------------------------------------------

function QuestService.redeem(player, raw)
	local data = profile(player)
	if not data or type(raw) ~= "string" then
		return false, "Invalid code."
	end
	local code = string.upper((raw:gsub("%s+", "")))
	local def = GameConfig.Codes[code]
	if #code == 0 or #code > 24 or not def then
		return false, "That code doesn't exist."
	end
	if data.Codes[code] then
		return false, "You already used that code."
	end
	data.Codes[code] = os.time()
	services.DataService.addCoins(player, def.Coins or 0, false)
	services.DataService.sendProfile(player)
	return true, string.format("Code redeemed: +%s coins!", Format.short(def.Coins or 0))
end

function QuestService.onProfileLoaded(player)
	local data = profile(player)
	tutorialCounts[player] = 0
	QuestService.ensureDaily(player)
	checkStarter(player, data)
	checkAchievements(player, data, nil)
end

function QuestService.onPlayerRemoving(player)
	tutorialCounts[player] = nil
	lastCode[player] = nil
end

function QuestService.start()
	local remotes = services.Remotes
	remotes.Tutorial.OnServerEvent:Connect(function(player, action)
		local data = profile(player)
		if not data then
			return
		end
		if action == "Skip" and not data.Tutorial.Done then
			data.Tutorial.Done = true
			services.DataService.markDirty(player)
			services.DataService.sendProfile(player)
		elseif action == "Replay" then
			data.Tutorial = { Step = 1, Done = false }
			tutorialCounts[player] = 0
			services.DataService.markDirty(player)
			services.DataService.sendProfile(player)
		end
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
end

return QuestService
