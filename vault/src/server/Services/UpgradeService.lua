--[[
	UpgradeService - Cash upgrades, Vault Token perks, depth unlocks and rebirth.
	Every purchase is checked here (exists, unlocked at the player's depth, not maxed, can
	afford) and the price is taken atomically before the level goes up. Requests are rate
	limited, so a double-click or a spammed remote buys at most what the player can afford,
	one level per accepted request.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local RateLimit = require(script.Parent.RateLimit)

local UpgradeService = {}

local services
local limiter = RateLimit.new(8, 4)

function UpgradeService.init(registry)
	services = registry
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
	if data.HighestDepth < def.UnlockDepth then
		return false, string.format("%s unlocks at %s.", def.Name, DepthConfig.get(def.UnlockDepth).Name)
	end
	local level = data.Upgrades[key] or 0
	local cost = Economy.upgradeCost(key, level)
	if not cost then
		return false, def.Name .. " is already at max level."
	end
	if not services.DataService.spendCash(player, cost) then
		return false, string.format("%s costs $%s - you have $%s.", def.Name, Format.short(cost), Format.short(data.Cash))
	end
	data.Upgrades[key] = level + 1
	services.DataService.markDirty(player)
	services.DataService.bump(player, "Upgrades", 1)
	services.QuestService.tutorialEvent(player, "Upgrade")
	services.Analytics.funnel(player, "FirstUpgrade")
	services.PlayerService.applyStats(player)
	services.LootService.sendInventory(player) -- capacity may have changed
	services.DataService.sendProfile(player)
	return true, string.format("%s upgraded to level %d!", def.Name, level + 1)
end

function UpgradeService.buyPerk(player, key)
	local data = services.DataService.getProfile(player)
	local def = type(key) == "string" and UpgradeConfig.PerkByKey[key]
	if not data or not def then
		return false, "Unknown perk."
	end
	local level = data.Perks[key] or 0
	local cost = Economy.perkCost(key, level)
	if not cost then
		return false, def.Name .. " is already at max level."
	end
	if not services.DataService.spendTokens(player, cost) then
		return false, string.format("%s costs %d Vault Tokens.", def.Name, cost)
	end
	data.Perks[key] = level + 1
	services.DataService.markDirty(player)
	services.PlayerService.applyStats(player)
	services.LootService.sendInventory(player)
	services.DataService.sendProfile(player)
	return true, string.format("%s is now level %d!", def.Name, level + 1)
end

-- Requirements for the next depth (shown on the depth panel and elevator).
function UpgradeService.nextDepthView(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local def = DepthConfig.get(data.HighestDepth + 1)
	if not def then
		return nil
	end
	return { depth = def.Depth, name = def.Name, cash = def.UnlockCash, tokens = def.UnlockTokens, affordable = data.Cash >= def.UnlockCash and data.Tokens >= def.UnlockTokens }
end

function UpgradeService.unlockDepth(player, depth)
	local data = services.DataService.getProfile(player)
	if not data or type(depth) ~= "number" or depth ~= depth then
		return false, "Invalid depth."
	end
	depth = math.floor(depth)
	local def = DepthConfig.get(depth)
	if not def then
		return false, "There is nothing deeper - yet."
	end
	if depth <= data.HighestDepth then
		return false, def.Name .. " is already unlocked."
	end
	if depth ~= data.HighestDepth + 1 then
		return false, "Unlock the depths in order."
	end
	if data.Cash < def.UnlockCash or data.Tokens < def.UnlockTokens then
		local need = "$" .. Format.short(def.UnlockCash)
		if def.UnlockTokens > 0 then
			need ..= " and " .. def.UnlockTokens .. " Vault Tokens"
		end
		return false, string.format("%s needs %s.", def.Name, need)
	end
	-- Both prices were checked above; take both (neither can fail now).
	services.DataService.spendCash(player, def.UnlockCash)
	services.DataService.spendTokens(player, def.UnlockTokens)
	data.HighestDepth = depth
	services.DataService.markDirty(player)
	services.DataService.setStat(player, "DepthLevel", depth)
	services.QuestService.tutorialEvent(player, "UnlockDepth")
	services.Analytics.funnel(player, "FirstNewDepth")
	services.Remotes.Popup:FireClient(player, "DepthUnlocked", { depth = depth, name = def.Name, code = def.Code })
	services.Remotes.Announce:FireAllClients(string.format("%s unlocked %s - %s!", player.DisplayName, def.Code, def.Name), def.Palette.Accent)
	services.DataService.sendProfile(player)
	return true, def.Name .. " unlocked! Take the elevator down."
end

-- Rebirth -------------------------------------------------------------------------------------

UpgradeService.Resets = { "Cash", "All Cash upgrades", "Unlocked depths (back to B1)", "Your carried stack" }
UpgradeService.Keeps = { "Vault Tokens and token perks", "Collection Book, achievements and stats", "Cosmetics and settings", "Best deposit and leaderboards" }

function UpgradeService.rebirthPreview(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local r = UpgradeConfig.Rebirth
	local requirement = UpgradeConfig.rebirthRequirement(data.Rebirths)
	return {
		count = data.Rebirths,
		minDepth = r.MinDepth,
		requirement = requirement,
		progress = data.EarnedSinceRebirth,
		eligible = data.HighestDepth >= r.MinDepth and data.EarnedSinceRebirth >= requirement,
		bonusNow = 1 + r.ValueBonus * data.Rebirths,
		bonusNext = 1 + r.ValueBonus * (data.Rebirths + 1),
		tokens = r.Tokens,
		resets = UpgradeService.Resets,
		keeps = UpgradeService.Keeps,
	}
end

function UpgradeService.rebirth(player, confirm)
	local data = services.DataService.getProfile(player)
	local preview = UpgradeService.rebirthPreview(player)
	if not data or not preview then
		return false, "Not loaded."
	end
	if confirm ~= UpgradeConfig.Rebirth.Confirm then
		return false, "Type REBIRTH to confirm."
	end
	if data.HighestDepth < preview.minDepth then
		return false, "Rebirth opens once you reach " .. DepthConfig.get(preview.minDepth).Name .. "."
	end
	if not preview.eligible then
		return false, string.format("Earn $%s since your last rebirth first ($%s so far).", Format.short(preview.requirement), Format.short(preview.progress))
	end
	data.Cash = 0
	data.Upgrades = {}
	data.HighestDepth = 1
	data.CurrentDepth = 1
	data.EarnedSinceRebirth = 0
	data.Carried = services.DataService.emptyCarried()
	data.Rebirths += 1
	services.DataService.addTokens(player, UpgradeConfig.Rebirth.Tokens)
	services.DataService.markDirty(player)
	services.DataService.bump(player, "Rebirths", 1)
	services.Analytics.funnel(player, "FirstRebirth")
	services.ElevatorService.cancel(player)
	services.PlayerService.place(player, 1)
	services.PlayerService.applyStats(player)
	services.Remotes.Popup:FireClient(player, "Rebirth", { count = data.Rebirths, bonus = preview.bonusNext, tokens = UpgradeConfig.Rebirth.Tokens })
	services.Remotes.Announce:FireAllClients(string.format("%s was reborn! (Rebirth %d)", player.DisplayName, data.Rebirths), { 255, 200, 80 })
	services.LootService.sendInventory(player)
	services.DataService.sendProfile(player)
	return true, "Reborn! Your loot is now worth more forever."
end

function UpgradeService.onPlayerRemoving(player)
	limiter:forget(player)
end

function UpgradeService.start()
	local remotes = services.Remotes
	local function handle(fn)
		return function(player, arg)
			if not limiter:allow(player) then
				return
			end
			local ok, message = fn(player, arg)
			notify(player, message, if ok then "good" else "error")
		end
	end
	remotes.BuyUpgrade.OnServerEvent:Connect(handle(UpgradeService.buy))
	remotes.BuyPerk.OnServerEvent:Connect(handle(UpgradeService.buyPerk))
	remotes.UnlockDepth.OnServerEvent:Connect(handle(UpgradeService.unlockDepth))
	remotes.Rebirth.OnServerEvent:Connect(handle(UpgradeService.rebirth))
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
end

return UpgradeService
