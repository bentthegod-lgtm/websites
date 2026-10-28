--[[
	UpgradeService - coin purchases (upgrades, machine unlocks), machine selection and
	prestige ("Lab Certification"). Every request is validated here:
	  * the profile must be loaded;
	  * the price is computed on the server (Economy.cost) - never sent by the client;
	  * spending is atomic (DataService.spendCoins) and the level is set in the same step,
	    so a double-click can't buy twice with the same coins;
	  * requests are rate limited.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local MachineConfig = require(Shared.Config.MachineConfig)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Format = require(Shared.Format)

local RateLimit = require(script.Parent.RateLimit)

local UpgradeService = {}

local services
local cache = {}
local limiter = RateLimit.new(6, 6)

function UpgradeService.init(registry)
	services = registry
end

function UpgradeService.statsFor(player)
	if cache[player] then
		return cache[player]
	end
	local data = services.DataService.getProfile(player)
	local stats = Economy.stats(data)
	cache[player] = stats
	return stats
end

function UpgradeService.invalidate(player)
	cache[player] = nil
end

local function notify(player, text, kind)
	services.Remotes.Notify:FireClient(player, text, kind)
end

function UpgradeService.buy(player, key)
	local data = services.DataService.getProfile(player)
	local def = type(key) == "string" and UpgradeConfig.ByKey[key]
	if not data or not def then
		return false, "Unknown upgrade."
	end
	local level = data.Upgrades[key] or 0
	local price = Economy.cost(key, level)
	if not price then
		return false, def.Name .. " is already at max level."
	end
	if not services.DataService.spendCoins(player, price) then
		return false, string.format("Not enough coins: %s needs %s.", def.Name, Format.short(price))
	end
	data.Upgrades[key] = level + 1
	UpgradeService.invalidate(player)
	services.DataService.bump(player, "Upgrades", 1)
	if key == "Payload" then
		services.DataService.setStat(player, "Payload", level + 1)
	end
	services.QuestService.tutorialEvent(player, "Upgrade")
	services.Analytics.funnel(player, "FirstUpgrade")
	services.DataService.sendProfile(player)
	return true, string.format("%s upgraded to level %d!", def.Name, level + 1)
end

-- Values a requirement can check: records/counters + upgrade levels.
function UpgradeService.requirementValues(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return {}
	end
	local values = table.clone(data.Stats)
	for k, v in pairs(data.Upgrades) do
		values[k] = v
	end
	values.Prestige = data.Prestige.Count
	return values
end

function UpgradeService.unlockMachine(player, machineId)
	local data = services.DataService.getProfile(player)
	local def = type(machineId) == "string" and MachineConfig.ById[machineId]
	if not data or not def then
		return false, "Unknown machine."
	end
	if data.Machines[machineId] then
		return false, "You already own the " .. def.Name .. "."
	end
	if not Economy.meets(def.Requirement, UpgradeService.requirementValues(player)) then
		local req = def.Requirement
		return false, "Locked: " .. req.Text .. (if req.AndText then " " .. req.AndText else "") .. "."
	end
	if not services.DataService.spendCoins(player, def.Cost) then
		return false, string.format("The %s costs %s coins.", def.Name, Format.short(def.Cost))
	end
	data.Machines[machineId] = true
	local count = 0
	for _ in pairs(data.Machines) do
		count += 1
	end
	services.DataService.setStat(player, "Machines", count)
	services.Analytics.funnel(player, "FirstMachine")
	services.Remotes.Popup:FireClient(player, "Machine", { id = machineId, name = def.Name })
	UpgradeService.select(player, machineId)
	services.Remotes.Announce:FireAllClients(player.DisplayName .. " unlocked the " .. def.Name .. "!", { 255, 200, 60 })
	return true, def.Name .. " unlocked and selected!"
end

function UpgradeService.select(player, machineId)
	local data = services.DataService.getProfile(player)
	if not data or type(machineId) ~= "string" or not data.Machines[machineId] then
		return false, "You don't own that machine yet."
	end
	if services.LaunchService.isBusy(player) then
		return false, "Wait for the current launch to finish."
	end
	data.Selected = machineId
	services.DataService.markDirty(player)
	services.PadService.refreshMachine(player)
	services.DataService.sendProfile(player)
	return true, MachineConfig.ById[machineId].Name .. " selected."
end

function UpgradeService.prestigePreview(player)
	local data = services.DataService.getProfile(player)
	return data and Progress.prestige(data) or nil
end

-- Resets exactly what the preview lists, keeps everything else.
function UpgradeService.prestige(player, confirm)
	local data = services.DataService.getProfile(player)
	if not data or confirm ~= "CERTIFY" then
		return false, "Prestige needs confirmation."
	end
	if services.LaunchService.isBusy(player) then
		return false, "Wait for the current launch to finish."
	end
	local preview = Progress.prestige(data)
	if not preview.eligible then
		return false, string.format("Lab Certification needs the Air Cannon and a best score of %s.", Format.short(preview.needScore))
	end
	data.Prestige.Credits += preview.credits
	data.Prestige.Count += 1
	data.Coins = 0
	data.RunEarned = 0
	data.Upgrades = {}
	data.Machines = { Standard = true }
	data.Selected = "Standard"
	data.LastLaunch = { Power = 1, Angle = 45, Aim = 0, Spin = "None" }
	UpgradeService.invalidate(player)
	services.DataService.setStat(player, "Payload", 0)
	services.DataService.setStat(player, "Machines", 1)
	services.DataService.setStat(player, "Prestige", data.Prestige.Count)
	services.PadService.refreshMachine(player)
	services.Analytics.funnel(player, "FirstPrestige")
	services.Remotes.Popup:FireClient(player, "Prestige", { credits = preview.credits, total = data.Prestige.Credits })
	services.Remotes.Announce:FireAllClients(player.DisplayName .. " earned Lab Certification!", { 120, 220, 255 })
	services.DataService.sendProfile(player)
	return true, string.format("Certified! +%d Lab Credit%s.", preview.credits, if preview.credits == 1 then "" else "s")
end

-- Cheapest useful next upgrade (for the results screen).
function UpgradeService.recommend(player, result)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local priority
	if result and result.impacts >= UpgradeService.statsFor(player).ImpactCap then
		priority = { "Durability", "Power", "Angles", "Bonus" }
	elseif result and result.distance < 120 then
		priority = { "Power", "Angles", "Cooldown", "Durability" }
	else
		priority = { "Power", "Bonus", "Angles", "Durability", "Precision", "Payload", "Analyst", "Challenge", "Spin", "Cooldown" }
	end
	local best
	for _, key in ipairs(priority) do
		local price = Economy.cost(key, data.Upgrades[key] or 0)
		if price then
			local candidate = { key = key, name = UpgradeConfig.ByKey[key].Name, price = price, affordable = data.Coins >= price }
			if candidate.affordable then
				return candidate
			end
			best = best or candidate
		end
	end
	return best
end

function UpgradeService.onPlayerRemoving(player)
	cache[player] = nil
	limiter:forget(player)
end

function UpgradeService.onProfileLoaded(player)
	cache[player] = nil
end

function UpgradeService.start()
	local remotes = services.Remotes
	local function handle(player, fn, ...)
		if not limiter:allow(player) then
			return
		end
		local ok, message = fn(player, ...)
		if message then
			notify(player, message, if ok then "good" else "error")
		end
	end
	remotes.BuyUpgrade.OnServerEvent:Connect(function(player, key)
		handle(player, UpgradeService.buy, key)
	end)
	remotes.UnlockMachine.OnServerEvent:Connect(function(player, machineId)
		handle(player, UpgradeService.unlockMachine, machineId)
	end)
	remotes.SelectMachine.OnServerEvent:Connect(function(player, machineId)
		handle(player, UpgradeService.select, machineId)
	end)
	remotes.Prestige.OnServerEvent:Connect(function(player, confirm)
		handle(player, UpgradeService.prestige, confirm)
	end)
end

return UpgradeService
