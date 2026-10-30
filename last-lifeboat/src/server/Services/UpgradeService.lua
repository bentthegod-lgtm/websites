--[[
	UpgradeService - coin upgrades bought at the ticket booth / in the menu: Lung Capacity,
	Swim Speed, Grip, Loot Slots and Climb Speed (5 levels each, Config.Upgrades). The
	effects reach the client as player attributes (LL_OxygenMax, LL_SwimMult, LL_GripMult,
	LL_ClimbMult, LL_Slots) and are applied by the services that use them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Upgrades = require(Shared.Upgrades)
local LootMath = require(Shared.LootMath)
local Format = require(Shared.Format)
local RateLimit = require(script.Parent.RateLimit)

local UpgradeService = {}

local services
local limit = RateLimit.new(3, 5)

function UpgradeService.init(registry)
	services = registry
end

function UpgradeService.level(player, key)
	local data = services.DataService.getProfile(player)
	return if data then data.Upgrades[key] or 0 else 0
end

function UpgradeService.effect(player, key)
	return Upgrades.effect(key, UpgradeService.level(player, key))
end

function UpgradeService.slots(player)
	local vip = services.ShopService and services.ShopService.ownsPass(player, "VIP") or false
	return LootMath.slots(UpgradeService.level(player, "Slots"), vip)
end

function UpgradeService.applyAttributes(player)
	if not services.DataService.getProfile(player) or not player.Parent then
		return
	end
	player:SetAttribute("LL_OxygenMax", UpgradeService.effect(player, "Lungs"))
	player:SetAttribute("LL_SwimMult", UpgradeService.effect(player, "Swim"))
	player:SetAttribute("LL_GripMult", UpgradeService.effect(player, "Grip"))
	player:SetAttribute("LL_ClimbMult", UpgradeService.effect(player, "Climb"))
	player:SetAttribute("LL_Slots", UpgradeService.slots(player))
end

function UpgradeService.buy(player, key)
	local data = services.DataService.getProfile(player)
	local def = type(key) == "string" and GameConfig.Upgrades[key]
	if not data or not def then
		return false, "Unknown upgrade."
	end
	local level = data.Upgrades[key] or 0
	local cost = Upgrades.cost(key, level)
	if not cost then
		return false, def.Name .. " is maxed out!"
	end
	if not services.DataService.spendCoins(player, cost) then
		return false, string.format("%s level %d costs %s coins.", def.Name, level + 1, Format.short(cost))
	end
	data.Upgrades[key] = level + 1
	services.DataService.markDirty(player)
	UpgradeService.applyAttributes(player)
	services.DataService.sendProfile(player)
	return true, string.format("%s upgraded to level %d!", def.Name, level + 1)
end

function UpgradeService.onProfileLoaded(player)
	UpgradeService.applyAttributes(player)
end

function UpgradeService.onPlayerRemoving(player)
	limit:forget(player)
end

function UpgradeService.start()
	services.Remotes.BuyUpgrade.OnServerEvent:Connect(function(player, key)
		if not limit:allow(player) then
			return
		end
		local ok, message = UpgradeService.buy(player, key)
		services.Remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
end

return UpgradeService
