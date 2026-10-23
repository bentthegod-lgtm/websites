--[[
	DataService - persistent progression via DataStoreService, with a safe in-memory
	fallback when DataStores are unavailable (Studio without API access, outages).

	Profile: XP / level, statistics, discovered lore, cosmetic unlocks, settings.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local ProgressionConfig = require(Shared.Config.ProgressionConfig)

local DataService = {}

local services
local profiles = {}
local store
local storeError

local SETTINGS_SCHEMA = {
	Master = { 0, 1, 1 },
	Music = { 0, 1, 0.8 },
	Sfx = { 0, 1, 1 },
	Sensitivity = { 0.2, 3, 1 },
	Fov = { 60, 100, 78 },
	Brightness = { -0.3, 0.6, 0 },
	HeadBob = { false, true, true },
	ReduceFlicker = { false, true, false },
	CameraShake = { false, true, true },
	LargeText = { false, true, false },
}

local function defaultSettings()
	local settings = {}
	for key, spec in pairs(SETTINGS_SCHEMA) do
		settings[key] = spec[3]
	end
	return settings
end

local function defaultProfile()
	return {
		Version = ProgressionConfig.SchemaVersion,
		Xp = 0,
		Stats = {
			Runs = 0,
			Escapes = 0,
			Deaths = 0,
			ItemsCollected = 0,
			LoreFound = 0,
			Revives = 0,
			BlackBoxes = 0,
			ObjectivesCompleted = 0,
		},
		Lore = {},
		Unlocked = { Standard = true },
		Equipped = "Standard",
		Settings = defaultSettings(),
	}
end

-- Fills any fields missing from an older/partial profile.
local function reconcile(data)
	local defaults = defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	for key, value in pairs(defaults) do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	data.Version = ProgressionConfig.SchemaVersion
	return data
end

function DataService.init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(ProgressionConfig.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
		warn("[DeadAir] DataStore unavailable, progress will not persist: " .. storeError)
	end
end

function DataService.levelFor(xp)
	local level = 1
	while ProgressionConfig.LevelBase * (level ^ ProgressionConfig.LevelExponent) <= xp do
		level += 1
		if level > 999 then
			break
		end
	end
	return level
end

function DataService.xpForLevel(level)
	if level <= 1 then
		return 0
	end
	return math.floor(ProgressionConfig.LevelBase * ((level - 1) ^ ProgressionConfig.LevelExponent))
end

function DataService.cosmeticColor(id)
	for _, c in ipairs(ProgressionConfig.Cosmetics) do
		if c.Id == id then
			return Color3.fromRGB(c.Color[1], c.Color[2], c.Color[3])
		end
	end
	local c = ProgressionConfig.Cosmetics[1].Color
	return Color3.fromRGB(c[1], c[2], c[3])
end

function DataService.getProfile(player)
	local entry = profiles[player]
	return entry and entry.data
end

function DataService.isPersistent(player)
	local entry = profiles[player]
	return entry ~= nil and entry.persistent
end

function DataService.sendProfile(player)
	local entry = profiles[player]
	if not entry or not player.Parent then
		return
	end
	local data = entry.data
	local level = DataService.levelFor(data.Xp)
	services.Remotes.Profile:FireClient(player, {
		xp = data.Xp,
		level = level,
		levelXp = DataService.xpForLevel(level),
		nextLevelXp = DataService.xpForLevel(level + 1),
		stats = data.Stats,
		unlocked = data.Unlocked,
		equipped = data.Equipped,
		settings = data.Settings,
		cosmetics = ProgressionConfig.Cosmetics,
		persistent = entry.persistent,
		loreCount = data.Stats.LoreFound,
	})
end

local function key(player)
	return "player_" .. player.UserId
end

local function load(player)
	local data
	local persistent = false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(key(player))
			end)
			if ok then
				data = result
				persistent = true
				break
			end
			warn(string.format("[DeadAir] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
			task.wait(1.5 * attempt)
		end
	end
	profiles[player] = { data = reconcile(data), persistent = persistent, dirty = false }
	DataService.checkUnlocks(player)
	DataService.sendProfile(player)
	if not persistent then
		services.Remotes.Notify:FireClient(player, "Progress saving unavailable (Studio or DataStore offline).", "warn")
	end
end

function DataService.save(player)
	local entry = profiles[player]
	if not entry or not entry.persistent or not store then
		return false
	end
	local data = entry.data
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[DeadAir] Profile save failed for " .. player.Name .. ": " .. tostring(err))
	end
	entry.dirty = not ok
	return ok
end

function DataService.checkUnlocks(player)
	local data = DataService.getProfile(player)
	if not data then
		return {}
	end
	local level = DataService.levelFor(data.Xp)
	local newly = {}
	for _, c in ipairs(ProgressionConfig.Cosmetics) do
		if not data.Unlocked[c.Id] then
			local byLevel = c.Level ~= nil and level >= c.Level
			local byStat = c.Stat ~= nil and (data.Stats[c.Stat] or 0) >= c.Threshold
			if byLevel or byStat then
				data.Unlocked[c.Id] = true
				table.insert(newly, c.Name)
			end
		end
	end
	return newly
end

function DataService.addLore(player, noteId)
	local data = DataService.getProfile(player)
	if not data or data.Lore[noteId] then
		return false
	end
	data.Lore[noteId] = true
	data.Stats.LoreFound += 1
	return true
end

--[[
	summary = { escaped, died, objectives, items, revives, lore, blackBox, survivedSeconds, xpMultiplier, teamSteps }
	Returns a breakdown for the results screen.
]]
function DataService.awardRun(player, summary)
	local data = DataService.getProfile(player)
	if not data then
		return nil
	end
	local xp = ProgressionConfig.Xp
	local lines = {}
	local total = 0
	local function add(label, amount)
		if amount > 0 then
			table.insert(lines, { label = label, amount = amount })
			total += amount
		end
	end
	if summary.escaped then
		add("Escaped", xp.Escape)
	elseif summary.died then
		add("Consolation", xp.Death)
	end
	add("Objectives", summary.teamSteps * xp.ObjectiveStep)
	add("Lore", summary.lore * xp.LoreNote)
	add("Revives", summary.revives * xp.Revive)
	if summary.blackBox and summary.escaped then
		add("Black box recovered", xp.BlackBoxEscape)
	end
	add("Survival", math.min(xp.SurvivalCap, math.floor(summary.survivedSeconds / 60) * xp.Survived60s))
	total = math.floor(total * summary.xpMultiplier)

	local levelBefore = DataService.levelFor(data.Xp)
	data.Xp += total
	local stats = data.Stats
	stats.Runs += 1
	if summary.escaped then
		stats.Escapes += 1
	end
	if summary.died then
		stats.Deaths += 1
	end
	stats.ItemsCollected += summary.items
	stats.Revives += summary.revives
	stats.ObjectivesCompleted += summary.objectives
	if summary.blackBox and summary.escaped then
		stats.BlackBoxes += 1
	end
	local unlocks = DataService.checkUnlocks(player)
	task.spawn(DataService.save, player)
	return {
		lines = lines,
		total = total,
		multiplier = summary.xpMultiplier,
		levelBefore = levelBefore,
		levelAfter = DataService.levelFor(data.Xp),
		unlocks = unlocks,
	}
end

local function sanitizeSettings(incoming)
	local clean = {}
	if type(incoming) ~= "table" then
		return nil
	end
	for k, spec in pairs(SETTINGS_SCHEMA) do
		local v = incoming[k]
		if type(spec[1]) == "boolean" then
			if type(v) == "boolean" then
				clean[k] = v
			end
		elseif type(v) == "number" and v == v then
			clean[k] = math.clamp(v, spec[1], spec[2])
		end
	end
	return clean
end

function DataService.start()
	local remotes = services.Remotes
	local lastSettingsSave = {}
	remotes.SaveSettings.OnServerEvent:Connect(function(player, incoming)
		local data = DataService.getProfile(player)
		local now = os.clock()
		if not data or (lastSettingsSave[player] and now - lastSettingsSave[player] < 1) then
			return
		end
		lastSettingsSave[player] = now
		local clean = sanitizeSettings(incoming)
		if clean then
			for k, v in pairs(clean) do
				data.Settings[k] = v
			end
			profiles[player].dirty = true
		end
	end)
	remotes.EquipCosmetic.OnServerEvent:Connect(function(player, id)
		local data = DataService.getProfile(player)
		if not data or type(id) ~= "string" or not data.Unlocked[id] then
			return
		end
		data.Equipped = id
		profiles[player].dirty = true
		services.PlayerService.setFlashlightColor(player, DataService.cosmeticColor(id))
		DataService.sendProfile(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
		lastSettingsSave[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(ProgressionConfig.AutosaveInterval)
			for player, entry in pairs(profiles) do
				if entry.dirty then
					DataService.save(player)
				end
			end
		end
	end)
end

return DataService
