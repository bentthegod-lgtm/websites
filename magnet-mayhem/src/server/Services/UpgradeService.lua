--[[
	UpgradeService - magnet upgrades, magnet tiers and prestige. Every request is validated
	here: the client only names what it wants; prices and effects come from config.

	statsFor(player) caches Economy.stats() per player; anything that changes upgrades,
	tier or prestige calls invalidate().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Economy = require(Shared.Economy)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MagnetConfig = require(Shared.Config.MagnetConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Format = require(Shared.Format)

local UpgradeService = {}

local services
local cache = {}
local lastRequest = {}

function UpgradeService.init(registry)
	services = registry
end

function UpgradeService.invalidate(player)
	cache[player] = nil
end

function UpgradeService.statsFor(player)
	local cached = cache[player]
	if cached then
		return cached
	end
	local data = services.DataService.getProfile(player)
	if not data then
		return Economy.stats({}, 1, 0)
	end
	local stats = Economy.stats(data.Upgrades, data.Tier, data.Prestige.Cores)
	cache[player] = stats
	return stats
end

local function throttled(player)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.15 then
		return true
	end
	lastRequest[player] = now
	return false
end

local function changed(player)
	UpgradeService.invalidate(player)
	services.PlayerService.applyStats(player)
	services.DataService.sendProfile(player)
end

-- Returns ok, message.
function UpgradeService.buyUpgrade(player, key)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your data is still loading."
	end
	local def = EconomyConfig.ByKey[key]
	if not def then
		return false, "Unknown upgrade."
	end
	local level = data.Upgrades[key] or 0
	local price = Economy.upgradePrice(key, level)
	if not price then
		return false, def.Name .. " is maxed."
	end
	if not services.DataService.spendCoins(player, price) then
		return false, string.format("Need %s more coins.", Format.short(price - data.Coins))
	end
	data.Upgrades[key] = level + 1
	changed(player)
	services.DataService.bump(player, "Upgrade", 1)
	services.QuestService.tutorialEvent(player, "Upgrade")
	services.Analytics.funnel(player, "FirstUpgrade")
	services.Remotes.Popup:FireClient(player, "Upgrade", { key = key, level = level + 1, name = def.Name })
	return true, string.format("%s upgraded to level %d!", def.Name, level + 1)
end

function UpgradeService.buyTier(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your data is still loading."
	end
	local nextTier = data.Tier + 1
	local def = MagnetConfig.Tiers[nextTier]
	if not def then
		return false, "You already have the best magnet."
	end
	if not services.DataService.spendCoins(player, def.Price) then
		return false, string.format("Need %s more coins.", Format.short(def.Price - data.Coins))
	end
	data.Tier = nextTier
	changed(player)
	services.PlayerService.refreshMagnet(player)
	services.DataService.setStat(player, "Tier", nextTier)
	services.QuestService.tutorialEvent(player, "Tier")
	services.Remotes.Popup:FireClient(player, "Tier", { tier = nextTier, name = def.Name })
	services.Remotes.Announce:FireAllClients(string.format("%s upgraded to the %s magnet!", player.DisplayName, def.Name), { 255, 200, 60 })
	return true, "New magnet: " .. def.Name .. "!"
end

-- Prestige -------------------------------------------------------------------------------

function UpgradeService.prestigePreview(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local p = EconomyConfig.Prestige
	local cores = Economy.prestigeCores(data.RunEarned)
	local reasons = {}
	if not data.Zones[p.RequiresZone] then
		table.insert(reasons, "Unlock " .. ZoneConfig.ById[p.RequiresZone].Name)
	end
	if data.RunEarned < p.MinRunEarned then
		table.insert(reasons, string.format("Earn %s coins this run (%s so far)", Format.short(p.MinRunEarned), Format.short(data.RunEarned)))
	end
	return {
		eligible = #reasons == 0 and cores > 0,
		cores = cores,
		reasons = reasons,
		resets = { "Coins", "All upgrades", "Magnet tier", "Zone unlocks (except Rustyard)", "Carried scrap" },
		keeps = { "Magnet Cores", "Achievements", "Scrap Codex", "Quests", "Cosmetics", "Settings", "Leaderboard totals" },
	}
end

function UpgradeService.prestige(player, confirm)
	if confirm ~= "CONFIRM" then
		return false, "Prestige needs confirmation."
	end
	local data = services.DataService.getProfile(player)
	local preview = UpgradeService.prestigePreview(player)
	if not data or not preview or not preview.eligible then
		return false, "Not eligible to prestige yet."
	end
	services.MagnetService.cancelAll(player)
	data.Coins = 0
	data.Upgrades = {}
	data.Tier = 1
	data.Zones = { [ZoneConfig.StartZone] = true }
	data.Carried = {}
	data.RunEarned = 0
	data.Prestige.Cores += preview.cores
	data.Prestige.Count += 1
	services.DataService.markDirty(player)
	changed(player)
	services.PlayerService.refreshMagnet(player)
	services.PlayerService.updatePileAttributes(player)
	services.ZoneService.enforce(player)
	services.DataService.bump(player, "Prestige", 1)
	services.DataService.setStat(player, "Tier", 1)
	services.DataService.setStat(player, "Zone", 1)
	services.Analytics.funnel(player, "FirstPrestige")
	services.Remotes.Popup:FireClient(player, "Prestige", { cores = preview.cores, total = data.Prestige.Cores })
	services.Remotes.Announce:FireAllClients(string.format("%s prestiged for %d Magnet Cores!", player.DisplayName, preview.cores), { 255, 150, 60 })
	return true, string.format("Prestiged! +%d Magnet Cores.", preview.cores)
end

function UpgradeService.onProfileLoaded(player)
	UpgradeService.invalidate(player)
end

function UpgradeService.onPlayerRemoving(player)
	cache[player] = nil
	lastRequest[player] = nil
end

function UpgradeService.start()
	local remotes = services.Remotes
	local function reply(player, ok, message)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end
	remotes.BuyUpgrade.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" or #key > 32 or throttled(player) then
			return
		end
		reply(player, UpgradeService.buyUpgrade(player, key))
	end)
	remotes.BuyTier.OnServerEvent:Connect(function(player)
		if throttled(player) then
			return
		end
		reply(player, UpgradeService.buyTier(player))
	end)
	remotes.Prestige.OnServerEvent:Connect(function(player, confirm)
		if type(confirm) ~= "string" or throttled(player) then
			return
		end
		reply(player, UpgradeService.prestige(player, confirm))
	end)
end

return UpgradeService
