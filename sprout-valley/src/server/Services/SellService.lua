--[[
	SellService - selling produce at the Sell Stand, favourites (locked fruit is never sold
	by "Sell All"), one-way gifting, and the friends-in-server sell bonus.

	Trading is deliberately NOT implemented: a two-sided trade needs an escrow UI that is
	scam-proof (both sides confirm the exact final offer, cooldowns, logs) and trade scams
	are a top source of reports in this genre. One-way gifts to someone standing next to you
	give the social moment without the scam surface.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local CropConfig = require(Shared.Config.CropConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local RateLimit = require(script.Parent.RateLimit)

local SellService = {}

local services
local friends = {} -- [player] = { [otherPlayer] = true }
local sellLimiter = RateLimit.new(3, 6)
local giftLimiter = RateLimit.new(0.5, 2)
local favLimiter = RateLimit.new(8, 16)

function SellService.init(registry)
	services = registry
end

function SellService.friendCount(player)
	local n = 0
	for other in pairs(friends[player] or {}) do
		if other.Parent then
			n += 1
		end
	end
	return n
end

function SellService.multiplier(player)
	return Economy.sellMultiplier(services.ShopService.owns(player, "DoubleSell"), SellService.friendCount(player), GameConfig, ShopConfig)
end

local function findItem(profile, id)
	for i, item in ipairs(profile.Backpack) do
		if item.id == id then
			return item, i
		end
	end
	return nil
end

local function validId(id)
	return type(id) == "number" and id == id and id % 1 == 0 and id >= 1 and id < 2 ^ 40
end

function SellService.sell(player, mode, itemId)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return 0
	end
	if not services.StockService.nearStall(player, "SellStand") then
		services.Remotes.Notify:FireClient(player, "Bring your produce to the Sell Stand.", "info")
		return 0
	end
	-- Before touching the backpack: the pass check can yield (UserOwnsGamePassAsync), and
	-- the player leaving mid-yield would save a backpack with the fruit gone but no coins.
	local multiplier = SellService.multiplier(player)
	local sold = {}
	if mode == "All" then
		local kept = {}
		for _, item in ipairs(profile.Backpack) do
			if item.f then
				table.insert(kept, item)
			else
				table.insert(sold, item)
			end
		end
		profile.Backpack = kept
	elseif mode == "Item" and validId(itemId) then
		local item, index = findItem(profile, itemId)
		if item then
			table.remove(profile.Backpack, index)
			table.insert(sold, item)
		end
	end
	if #sold == 0 then
		services.Remotes.Notify:FireClient(player, "Nothing to sell (favourited fruit is kept).", "info")
		return 0
	end
	local base = Economy.itemsValue(sold, CropConfig.ById, MutationConfig)
	local total = math.floor(base * multiplier + 0.5)
	services.DataService.addCoins(player, total, true)
	profile.Stats.Sold += #sold
	services.Remotes.Effect:FireClient(player, "Sell", { amount = total, count = #sold })
	services.RewardsService.event(player, "Sell", total)
	services.DataService.sendProfile(player)
	return total
end

function SellService.toggleFavorite(player, itemId)
	local profile = services.DataService.getProfile(player)
	if not profile or not validId(itemId) then
		return
	end
	local item = findItem(profile, itemId)
	if item then
		item.f = if item.f then nil else true
		services.DataService.markDirty(player)
		services.DataService.sendProfile(player)
	end
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function SellService.gift(player, targetUserId, itemId)
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId or not validId(itemId) then
		return false
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local profile = services.DataService.getProfile(player)
	local targetProfile = target and services.DataService.getProfile(target)
	if not profile or not targetProfile or target == player then
		return false
	end
	local a, b = rootOf(player), rootOf(target)
	if not a or not b or (a.CFrame.Position - b.CFrame.Position).Magnitude > GameConfig.GiftRange then
		services.Remotes.Notify:FireClient(player, "Stand next to " .. target.DisplayName .. " to give a gift.", "info")
		return false
	end
	if targetProfile.Settings.AcceptGifts == false then
		services.Remotes.Notify:FireClient(player, target.DisplayName .. " isn't accepting gifts right now.", "info")
		return false
	end
	if #targetProfile.Backpack >= services.DataService.backpackCapacity(target) then
		services.Remotes.Notify:FireClient(player, target.DisplayName .. "'s backpack is full.", "info")
		return false
	end
	local item, index = findItem(profile, itemId)
	if not item then
		return false
	end
	if item.f then
		services.Remotes.Notify:FireClient(player, "Unfavourite that fruit before gifting it.", "info")
		return false
	end
	table.remove(profile.Backpack, index)
	item.id = targetProfile.NextItemId
	targetProfile.NextItemId += 1
	item.f = nil
	table.insert(targetProfile.Backpack, item)
	profile.Stats.Gifts += 1
	services.DataService.markDirty(player)
	services.DataService.markDirty(target)
	local crop = CropConfig.ById[item.c]
	local value = Economy.fruitValue(crop, item.kg, item.m, item.v, MutationConfig)
	services.Remotes.Notify:FireClient(player, string.format("You gave %s a %s!", target.DisplayName, crop.Name), "good")
	services.Remotes.Notify:FireClient(target, string.format("%s gave you a %s (%s, worth %s)!", player.DisplayName, crop.Name, Format.kg(item.kg), Format.coins(value)), "good")
	services.Remotes.Effect:FireClient(target, "Gift", { from = player.DisplayName, crop = crop.Id })
	services.DataService.sendProfile(player)
	services.DataService.sendProfile(target)
	return true
end

local function checkFriendship(a, b)
	task.spawn(function()
		local ok, isFriend = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		if ok and isFriend and a.Parent and b.Parent then
			friends[a] = friends[a] or {}
			friends[b] = friends[b] or {}
			friends[a][b] = true
			friends[b][a] = true
			services.Remotes.Notify:FireClient(a, b.DisplayName .. " (your friend) is here: +10% sell value!", "good")
			services.Remotes.Notify:FireClient(b, a.DisplayName .. " (your friend) is here: +10% sell value!", "good")
			services.DataService.sendProfile(a)
			services.DataService.sendProfile(b)
		end
	end)
end

function SellService.onProfileLoaded(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			checkFriendship(player, other)
		end
	end
end

function SellService.onPlayerRemoving(player)
	for other in pairs(friends[player] or {}) do
		if friends[other] then
			friends[other][player] = nil
			services.DataService.sendProfile(other)
		end
	end
	friends[player] = nil
	sellLimiter:forget(player)
	giftLimiter:forget(player)
	favLimiter:forget(player)
end

function SellService.start()
	local remotes = services.Remotes
	remotes.Sell.OnServerEvent:Connect(function(player, mode, itemId)
		if (mode == "All" or mode == "Item") and sellLimiter:allow(player) then
			SellService.sell(player, mode, itemId)
		end
	end)
	remotes.Favorite.OnServerEvent:Connect(function(player, itemId)
		if favLimiter:allow(player) then
			SellService.toggleFavorite(player, itemId)
		end
	end)
	remotes.Gift.OnServerEvent:Connect(function(player, targetUserId, itemId)
		if giftLimiter:allow(player) then
			SellService.gift(player, targetUserId, itemId)
		end
	end)
end

return SellService
