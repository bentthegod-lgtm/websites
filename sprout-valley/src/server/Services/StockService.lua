--[[
	StockService - the Seed Shop restock (every GameConfig.RestockInterval seconds, aligned
	to the real clock so the countdown is identical for everyone) and the Gear Shop.

	* Scheduled stock is rolled from the window index -> every server sells the same seeds.
	* Each player can buy up to the listed quantity per restock (so nobody can buy out a
	  rare seed before the others see it).
	* Rare seeds in stock are announced server-wide.
	* The Instant Restock developer product rolls a fresh stock for this server and
	  announces the buyer.

	workspace attributes for clients: SV_NextRestock (unix seconds), SV_StockSerial.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local CropConfig = require(Shared.Config.CropConfig)
local GearConfig = require(Shared.Config.GearConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local Stock = require(Shared.Stock)
local Format = require(Shared.Format)

local RateLimit = require(script.Parent.RateLimit)

local StockService = {}

local services
local stalls
local current = { serial = 0, items = {}, nextAt = 0, windowIndex = -1 }
local bought = {} -- [userId] = { serial = n, counts = { [cropId] = n } }
local limiter = RateLimit.new(6, 12)

function StockService.init(registry)
	services = registry
end

function StockService.setStalls(s)
	stalls = s
end

function StockService.current()
	return current
end

local function countsFor(player)
	local b = bought[player.UserId]
	if not b or b.serial ~= current.serial then
		b = { serial = current.serial, counts = {} }
		bought[player.UserId] = b
	end
	return b.counts
end

function StockService.viewFor(player)
	local counts = countsFor(player)
	local items = {}
	for _, item in ipairs(current.items) do
		table.insert(items, { crop = item.crop, qty = item.qty, left = math.max(0, item.qty - (counts[item.crop] or 0)) })
	end
	return { serial = current.serial, nextAt = current.nextAt, items = items }
end

function StockService.sendTo(player)
	services.Remotes.Stock:FireClient(player, StockService.viewFor(player))
end

local function broadcast()
	workspace:SetAttribute("SV_NextRestock", current.nextAt)
	workspace:SetAttribute("SV_StockSerial", current.serial)
	for _, player in ipairs(Players:GetPlayers()) do
		StockService.sendTo(player)
	end
end

local function announceRare(prefix)
	for _, cropId in ipairs(Stock.rare(current.items, CropConfig.ById, RarityConfig)) do
		local crop = CropConfig.ById[cropId]
		services.Remotes.Announce:FireAllClients(
			string.format("%s%s %s seed is in the Seed Shop! Hurry!", prefix, crop.Rarity:upper(), crop.Name),
			RarityConfig.Tiers[crop.Rarity].Color
		)
	end
end

function StockService.restock(rng, reason)
	current.serial += 1
	current.items = Stock.roll(CropConfig.List, rng)
	broadcast()
	if reason ~= "init" then
		services.Remotes.Effect:FireAllClients("Restock", { serial = current.serial })
	end
	announceRare("A ")
end

function StockService.scheduledRestock(now, reason)
	local index = Stock.index(now, GameConfig.RestockInterval)
	current.windowIndex = index
	current.nextAt = Stock.nextAt(now, GameConfig.RestockInterval)
	StockService.restock(Random.new(Stock.seedFor(index)), reason)
end

-- Instant Restock developer product (whole server).
function StockService.instantRestock(buyer)
	StockService.restock(Random.new(), "purchase")
	services.Remotes.Announce:FireAllClients(
		string.format("%s restocked the Seed Shop for EVERYONE! Go go go!", buyer and buyer.DisplayName or "Someone"),
		{ 120, 230, 120 }
	)
end

local function nearStall(player, key)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local stall = stalls and stalls[key]
	if not root or not stall then
		return false
	end
	return (root.CFrame.Position - stall.position).Magnitude <= GameConfig.StallRange
end
StockService.nearStall = nearStall

function StockService.buySeed(player, cropId)
	local crop = type(cropId) == "string" and CropConfig.ById[cropId]
	local profile = services.DataService.getProfile(player)
	if not crop or not profile then
		return false
	end
	if not nearStall(player, "SeedShop") then
		services.Remotes.Notify:FireClient(player, "Visit the Seed Shop to buy seeds.", "info")
		return false
	end
	local listed
	for _, item in ipairs(current.items) do
		if item.crop == crop.Id then
			listed = item
			break
		end
	end
	local counts = countsFor(player)
	if not listed or (counts[crop.Id] or 0) >= listed.qty then
		services.Remotes.Notify:FireClient(player, crop.Name .. " is sold out! Restock in " .. Format.clock(current.nextAt - os.time()), "warn")
		return false
	end
	if not services.DataService.spendCoins(player, crop.SeedPrice) then
		services.Remotes.Notify:FireClient(player, "Not enough Coins for " .. crop.Name .. ".", "warn")
		return false
	end
	counts[crop.Id] = (counts[crop.Id] or 0) + 1
	profile.Seeds[crop.Id] = (profile.Seeds[crop.Id] or 0) + 1
	services.Remotes.Effect:FireClient(player, "Purchase", { crop = crop.Id })
	services.RewardsService.event(player, "BuySeed", 1)
	StockService.sendTo(player)
	services.DataService.sendProfile(player)
	return true
end

function StockService.buyGear(player, gearId)
	local def = type(gearId) == "string" and GearConfig.Gear[gearId]
	local profile = services.DataService.getProfile(player)
	if not def or not profile then
		return false
	end
	if not nearStall(player, "GearShop") then
		services.Remotes.Notify:FireClient(player, "Visit the Gear Shop to buy gear.", "info")
		return false
	end
	if def.Permanent and (profile.Gear[gearId] or 0) > 0 then
		services.Remotes.Notify:FireClient(player, "You already own a " .. def.Name .. ".", "info")
		return false
	end
	if not services.DataService.spendCoins(player, def.Price) then
		services.Remotes.Notify:FireClient(player, "Not enough Coins for " .. def.Name .. ".", "warn")
		return false
	end
	profile.Gear[gearId] = (profile.Gear[gearId] or 0) + (def.Uses or 1)
	services.Remotes.Effect:FireClient(player, "Purchase", { gear = gearId })
	services.DataService.sendProfile(player)
	return true
end

function StockService.onProfileLoaded(player)
	StockService.sendTo(player)
end

function StockService.start()
	StockService.scheduledRestock(os.time(), "init")
	services.Remotes.BuySeed.OnServerEvent:Connect(function(player, cropId)
		if limiter:allow(player) then
			StockService.buySeed(player, cropId)
		end
	end)
	services.Remotes.BuyGear.OnServerEvent:Connect(function(player, gearId)
		if limiter:allow(player) then
			StockService.buyGear(player, gearId)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			if now >= current.nextAt then
				local ok, err = pcall(StockService.scheduledRestock, now, "scheduled")
				if not ok then
					warn("[SproutValley] restock failed: " .. tostring(err))
					current.nextAt = now + GameConfig.RestockInterval
				end
			end
		end
	end)
end

return StockService
