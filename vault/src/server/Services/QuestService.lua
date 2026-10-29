--[[
	QuestService - onboarding, achievements, daily challenges, the Collection Book, rare
	discoveries and codes. Everything advances from server events (DataService.bump /
	tutorialEvent / discover); the client can only ask to skip or replay onboarding.

	Rewards are granted exactly once: the achievement flag / daily Done flag / book entry /
	code flag is set BEFORE any cash or tokens are added.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local QuestConfig = require(Shared.Config.QuestConfig)
local LootConfig = require(Shared.Config.LootConfig)
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

-- Onboarding ----------------------------------------------------------------------------------

function QuestService.tutorialStep(player)
	local data = profile(player)
	if not data or data.Tutorial.Done then
		return nil
	end
	return QuestConfig.Tutorial[data.Tutorial.Step]
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

function QuestService.tutorialProgress(player)
	return tutorialCounts[player] or 0
end

-- Achievements --------------------------------------------------------------------------------

local function grantCosmetic(data, cosmetic)
	if cosmetic then
		data.Cosmetics.Owned[cosmetic] = true
	end
end

local function checkAchievements(player, data, key)
	for _, def in ipairs(QuestConfig.Achievements) do
		if (key == nil or def.Stat == key) and not data.Achievements[def.Id] then
			if (data.Stats[def.Stat] or 0) >= Progress.achievementTarget(def) then
				data.Achievements[def.Id] = os.time() -- mark first, then reward
				grantCosmetic(data, def.Cosmetic)
				services.DataService.addTokens(player, def.Tokens or 0)
				services.DataService.markDirty(player)
				services.Remotes.Popup:FireClient(player, "Achievement", { id = def.Id, name = def.Name, text = def.Text, tokens = def.Tokens })
				services.DataService.sendProfile(player)
			end
		end
	end
end

-- Daily challenges (UTC days of server time) ----------------------------------------------

function QuestService.ensureDaily(player)
	local data = profile(player)
	if not data then
		return
	end
	local day = Progress.dayNumber(os.time())
	if data.Daily.Day ~= day or #data.Daily.List == 0 then
		data.Daily = { Day = day, List = Progress.rollDaily(player.UserId, day, data.HighestDepth) }
		services.DataService.markDirty(player)
	end
end

local function bumpDaily(player, data, key, n)
	QuestService.ensureDaily(player)
	for _, c in ipairs(data.Daily.List) do
		if c.Stat == key and not c.Done then
			c.Progress = math.min(c.Target, c.Progress + (n or 1))
			if c.Progress >= c.Target then
				c.Done = true -- mark first, then reward
				services.DataService.addCash(player, c.Cash, true)
				services.DataService.addTokens(player, c.Tokens)
				services.Remotes.Popup:FireClient(player, "Daily", { text = c.Text, cash = c.Cash, tokens = c.Tokens })
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

-- Stat hook (DataService.bump / setStat) ----------------------------------------------------

local LEVEL_STATS = { DepthLevel = true, Discovered = true }

function QuestService.onStat(player, key, n)
	local data = profile(player)
	if not data then
		return
	end
	if not LEVEL_STATS[key] then
		bumpDaily(player, data, key, n)
	end
	checkAchievements(player, data, key)
end

-- Collection Book -----------------------------------------------------------------------------

function QuestService.discover(player, def)
	local data = profile(player)
	if not data then
		return
	end
	local entry = data.Book[def.Id]
	local first = entry == nil
	if first then
		entry = { n = 0, first = os.time() }
		data.Book[def.Id] = entry
	end
	entry.n += 1
	if first then
		local count = 0
		for _ in pairs(data.Book) do
			count += 1
		end
		services.DataService.setStat(player, "Discovered", count)
		if LootConfig.rank(def) >= 4 then
			services.DataService.addTokens(player, 1)
		end
		services.Remotes.Popup:FireClient(player, "Discovery", { id = def.Id, name = def.Name, rarity = def.Rarity, count = count, total = Progress.bookSize() })
	end
end

-- A rare-event special was collected: bonus Vault Tokens.
function QuestService.specialFound(player, def)
	local tokens = if def.Rarity == "Mythic" then 5 else 2
	services.DataService.addTokens(player, tokens)
	services.Remotes.Popup:FireClient(player, "RareFind", { id = def.Id, name = def.Name, rarity = def.Rarity, tokens = tokens })
end

-- Codes ---------------------------------------------------------------------------------------

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
	if def.Cash then
		services.DataService.addCash(player, def.Cash, false)
	end
	if def.Tokens then
		services.DataService.addTokens(player, def.Tokens)
	end
	services.DataService.sendProfile(player)
	local parts = {}
	if def.Cash then
		table.insert(parts, "$" .. Format.short(def.Cash))
	end
	if def.Tokens then
		table.insert(parts, def.Tokens .. " Vault Tokens")
	end
	return true, "Code redeemed: " .. table.concat(parts, " + ")
end

function QuestService.onProfileLoaded(player)
	local data = profile(player)
	tutorialCounts[player] = 0
	QuestService.ensureDaily(player)
	services.DataService.setStat(player, "DepthLevel", data.HighestDepth)
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
