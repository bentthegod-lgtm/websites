--[[
	ShopService - Robux purchases.

	Developer Products (consumables) go through MarketplaceService.ProcessReceipt:
	  1. the profile-side grant is applied (cash, queued crate Blobby, lock token) and the
	     receipt's PurchaseId is recorded in the profile,
	  2. the profile is saved; if the save fails the grant is undone and Roblox is told
	     NotProcessedYet so it retries later. A profile that can't be saved (load failed,
	     DataStores down) never gets a grant in a live game: NotProcessedYet as well,
	  3. only then world effects run (server luck, placing the Blobby, locking the door)
	     and PurchaseGranted is returned.
	  A receipt seen before returns PurchaseGranted without granting again.

	Game Passes are checked with UserOwnsGamePassAsync (pcall, cached per session) and
	PromptGamePassPurchaseFinished.

	IDs of 0 mean "not created yet": in Studio the Buy button grants the item for free, in
	a live game it says it isn't available.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local ShopConfig = require(Shared.Config.ShopConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Spawner = require(Shared.Spawner)

local ShopService = {}

local services
local productsByKey, productsById = {}, {}
local passesByKey, passesById = {}, {}
local owned = {} -- [player] = { [passKey] = true }
local randomItemsRestricted = {} -- [player] = true when paid random items are not allowed
local lastRequest = {}
local rng = Random.new()

function ShopService.init(registry)
	services = registry
	productsByKey, productsById, passesByKey, passesById = {}, {}, {}, {}
	for _, product in ipairs(ShopConfig.Products) do
		productsByKey[product.Key] = product
		if product.ProductId and product.ProductId > 0 then
			productsById[product.ProductId] = product
		end
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		passesByKey[pass.Key] = pass
		if pass.PassId and pass.PassId > 0 then
			passesById[pass.PassId] = pass
		end
	end
end

---------------------------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------------------------

function ShopService.owns(player, passKey)
	local set = owned[player]
	return set ~= nil and set[passKey] == true
end

local function onPassGranted(player, pass)
	owned[player] = owned[player] or {}
	owned[player][pass.Key] = true
	if pass.Key == "VIP" or pass.Key == "ExtraSlots" then
		services.PlotService.applySlots(player)
		services.BlobbyService.flushQueue(player)
	end
	if pass.Key == "VIP" then
		services.PlayerService.updateNameplate(player)
	end
	services.PlayerService.sendProfile(player)
end

local function loadPasses(player)
	owned[player] = owned[player] or {}
	for _, pass in ipairs(ShopConfig.Passes) do
		if pass.PassId and pass.PassId > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
			end)
			if ok and has then
				owned[player][pass.Key] = true
			elseif not ok then
				warn("[SnatchTycoon] Pass check failed for " .. pass.Key .. ": " .. tostring(has))
			end
		end
	end
end

-- Paid random items (the Mythic Crate) must be hidden for players whose region/policy
-- restricts them. If the policy check fails we err on the safe side and hide it.
local function loadPolicy(player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	randomItemsRestricted[player] = not ok or type(info) ~= "table" or info.ArePaidRandomItemsRestricted == true
end

function ShopService.randomItemsAllowed(player)
	return randomItemsRestricted[player] ~= true
end

---------------------------------------------------------------------------------------------
-- Products
---------------------------------------------------------------------------------------------

local function noop() end

--[[
	Applies the profile part of a product. Returns two functions: one that applies the world
	part, and one that undoes exactly this grant (used when the save fails). Only the grant
	is undone, so income, buys and sells that happened while the save was yielding stay.
]]
function ShopService.applyProduct(player, profile, product)
	if product.Kind == "Cash" then
		local amount = Economy.cashPackAmount(product.Pack, services.PlayerService.incomePerSecond(player))
		profile.Cash += amount
		profile.TotalEarned += amount
		return function()
			services.Remotes.Popup:FireClient(player, "Cash", { amount = amount, big = true })
		end, function()
			profile.Cash = math.max(0, profile.Cash - amount)
			profile.TotalEarned = math.max(0, profile.TotalEarned - amount)
		end
	elseif product.Kind == "Crate" then
		local rarity = Spawner.rollCrate(product.Odds, function()
			return rng:NextNumber()
		end)
		local species, mutation = services.RewardService.rollBlobby(rarity)
		-- Saved in the queue first so it survives a crash; placed right after.
		local queued = { Species = species.Id, Mutation = mutation }
		table.insert(profile.Queued, queued)
		return function()
			services.BlobbyService.flushQueue(player)
			services.Remotes.Popup:FireClient(player, "Reveal", { species = species.Id, mutation = mutation, rarity = rarity, source = "crate" })
			services.FeedService.announce(string.format("%s opened a Mythic Crate and got a %s%s %s!", player.DisplayName, if mutation then string.upper(mutation) .. " " else "", string.upper(rarity), species.Name), { 255, 64, 112 }, true)
		end, function()
			local index = table.find(profile.Queued, queued)
			if index then
				table.remove(profile.Queued, index)
			end
		end
	elseif product.Kind == "LockNow" then
		profile.LockTokens = (profile.LockTokens or 0) + 1
		return function()
			services.PlotService.useLockToken(player)
		end, function()
			profile.LockTokens = math.max(0, profile.LockTokens - 1)
		end
	elseif product.Kind == "ServerLuck" then
		return function()
			services.EventService.addServerLuck(GameConfig.Events.ServerLuckPerPurchase, player.DisplayName)
		end, noop
	end
	return noop, noop
end

local function trimReceipts(profile)
	local ids = {}
	for id, at in pairs(profile.Receipts) do
		table.insert(ids, { id = id, at = at })
	end
	if #ids <= 100 then
		return
	end
	table.sort(ids, function(a, b)
		return a.at > b.at
	end)
	for i = 101, #ids do
		profile.Receipts[ids[i].id] = nil
	end
end

function ShopService.processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = productsById[receipt.ProductId]
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = services.DataService.getProfile(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(receipt.PurchaseId)
	if profile.Receipts[id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local persistent = services.DataService.isPersistent(player)
	if not persistent and not RunService:IsStudio() then
		-- The grant could never be saved: let Roblox retry when the profile loads properly.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local after, undo = ShopService.applyProduct(player, profile, product)
	profile.Receipts[id] = os.time()
	if persistent and not services.DataService.save(player) then
		undo()
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	trimReceipts(profile)
	services.DataService.markDirty(player)
	after()
	services.Remotes.Notify:FireClient(player, "Thanks! " .. product.Name .. " delivered.", "good")
	services.Remotes.Sfx:FireClient(player, "Purchase")
	services.PlayerService.sendProfile(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Validation before prompting, so players aren't charged for something useless right now.
local function canBuyProduct(player, product)
	if product.Kind == "Crate" and not ShopService.randomItemsAllowed(player) then
		return false, "The Mythic Crate isn't available for your account."
	end
	if product.Kind == "Crate" and not services.BlobbyService.freeSlot(player) then
		return false, "Free up a pedestal first - the crate Blobby needs a spot!"
	end
	if product.Kind == "LockNow" and not services.PlotService.canPaidLock(player) then
		return false, "Your base is already locked (or just opened). Try again in a few seconds."
	end
	return true
end

local function rateLimited(player)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 1 then
		return true
	end
	lastRequest[player] = now
	return false
end

function ShopService.requestProduct(player, key)
	if type(key) ~= "string" or rateLimited(player) then
		return
	end
	local product = productsByKey[key]
	local profile = services.DataService.getProfile(player)
	if not product or not profile then
		return
	end
	local ok, reason = canBuyProduct(player, product)
	if not ok then
		services.Remotes.Notify:FireClient(player, reason, "warn")
		return
	end
	if product.ProductId and product.ProductId > 0 then
		MarketplaceService:PromptProductPurchase(player, product.ProductId)
	elseif RunService:IsStudio() then
		local after = ShopService.applyProduct(player, profile, product)
		services.DataService.markDirty(player)
		after()
		services.Remotes.Notify:FireClient(player, "Studio test: " .. product.Name .. " granted for free", "info")
		services.PlayerService.sendProfile(player)
	else
		services.Remotes.Notify:FireClient(player, "This item isn't available yet.", "warn")
	end
end

function ShopService.requestPass(player, key)
	if type(key) ~= "string" or rateLimited(player) then
		return
	end
	local pass = passesByKey[key]
	if not pass or not services.DataService.getProfile(player) then
		return
	end
	if ShopService.owns(player, key) then
		services.Remotes.Notify:FireClient(player, "You already own " .. pass.Name .. "!", "info")
		return
	end
	if pass.PassId and pass.PassId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
	elseif RunService:IsStudio() then
		onPassGranted(player, pass)
		services.Remotes.Notify:FireClient(player, "Studio test: " .. pass.Name .. " granted for this session", "info")
	else
		services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
	end
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = ShopService.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passesById[passId]
		if purchased and pass and player.Parent then
			onPassGranted(player, pass)
			services.Remotes.Notify:FireClient(player, "Thanks! " .. pass.Name .. " unlocked forever.", "good")
			services.Remotes.Sfx:FireClient(player, "Purchase")
			services.FeedService.announce(player.DisplayName .. " unlocked " .. pass.Name .. "!", pass.Color, false)
		end
	end)
	services.DataService.ProfileLoaded:Connect(function(player)
		loadPolicy(player)
		loadPasses(player)
		services.PlotService.applySlots(player)
		services.PlayerService.updateNameplate(player)
	end)
	services.DataService.Releasing:Connect(function(player)
		owned[player] = nil
		lastRequest[player] = nil
		randomItemsRestricted[player] = nil
	end)
	services.Remotes.ShopBuy.OnServerEvent:Connect(ShopService.requestProduct)
	services.Remotes.PassBuy.OnServerEvent:Connect(ShopService.requestPass)
end

return ShopService
