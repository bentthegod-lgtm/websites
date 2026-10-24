--[[
	ShopService - Robux purchases.

	Developer Products (MarketplaceService.ProcessReceipt):
	  * The receipt's PurchaseId is stored in the profile and the profile is SAVED before
	    PurchaseGranted is returned, so a purchase is granted exactly once even if Roblox
	    retries the receipt or the server crashes. If the profile isn't loaded or the save
	    fails, the grant is undone and NotProcessedYet is returned (Roblox retries later).
	  * Server-wide effects (instant restock, weather totems) run only after the save.

	Game Passes (UserOwnsGamePassAsync, cached per session, pcall) +
	PromptGamePassPurchaseFinished for in-game purchases.

	IDs of 0 = not set up: Studio grants for free (testing), live game says "not available".
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local ShopConfig = require(Shared.Config.ShopConfig)
local CropConfig = require(Shared.Config.CropConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local Crate = require(Shared.Crate)

local ShopService = {}

local services
local productsByKey, productsById = {}, {}
local passesByKey, passesById = {}, {}
local passCache = {} -- [player] = { [key] = bool }
local lastRequest = {}
local rng = Random.new()

function ShopService.init(registry)
	services = registry
	for _, product in ipairs(ShopConfig.Products) do
		productsByKey[product.Key] = product
		if product.ProductId > 0 then
			productsById[product.ProductId] = product
		end
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		passesByKey[pass.Key] = pass
		if pass.PassId > 0 then
			passesById[pass.PassId] = pass
		end
	end
end

---------------------------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------------------------

function ShopService.owns(player, key)
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[key] ~= nil then
		return cache[key]
	end
	local pass = passesByKey[key]
	if not pass or pass.PassId <= 0 then
		return false
	end
	local ok, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
	end)
	if ok then
		cache[key] = owned == true
		return cache[key]
	end
	return false -- not cached: try again next time
end

function ShopService.passesFor(player)
	local out = {}
	for _, pass in ipairs(ShopConfig.Passes) do
		out[pass.Key] = ShopService.owns(player, pass.Key)
	end
	return out
end

local function applyPass(player, key)
	player:SetAttribute("SV_" .. key, true)
	if key == "VIP" then
		if services.PlotService then
			services.PlotService.refreshTiles(player)
		end
		if services.PlayerService then
			services.PlayerService.refreshTag(player)
		end
	end
	services.DataService.sendProfile(player)
end

local function grantPassForSession(player, key)
	passCache[player] = passCache[player] or {}
	passCache[player][key] = true
	applyPass(player, key)
end

function ShopService.onProfileLoaded(player)
	for _, pass in ipairs(ShopConfig.Passes) do
		if ShopService.owns(player, pass.Key) then
			player:SetAttribute("SV_" .. pass.Key, true)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Developer products
---------------------------------------------------------------------------------------------

--[[
	Applies the profile part of a product. Returns undo() and after() callbacks:
	undo reverts the profile change if saving fails; after runs world effects once saved.
]]
local function prepareGrant(player, profile, product)
	local undo, after = function() end, function() end
	if product.Coins then
		profile.Coins += product.Coins
		undo = function()
			profile.Coins -= product.Coins
		end
		after = function()
			services.Remotes.Effect:FireClient(player, "Coins", { amount = product.Coins })
		end
	elseif product.Key == "GrowthSkip" then
		profile.Tokens.GrowthSkip = (profile.Tokens.GrowthSkip or 0) + 1
		undo = function()
			profile.Tokens.GrowthSkip -= 1
		end
		after = function()
			services.PlotService.applyPendingSkip(player)
		end
	elseif product.Crate then
		local crate = ShopConfig.Crates[product.Crate]
		local rolls = {}
		for _ = 1, product.Rolls or 1 do
			local cropId = Crate.roll(crate, CropConfig.List, rng)
			table.insert(rolls, cropId)
			profile.Seeds[cropId] = (profile.Seeds[cropId] or 0) + 1
		end
		undo = function()
			for _, cropId in ipairs(rolls) do
				profile.Seeds[cropId] -= 1
			end
		end
		after = function()
			local names = {}
			for _, cropId in ipairs(rolls) do
				local crop = CropConfig.ById[cropId]
				table.insert(names, crop.Name)
				if RarityConfig.Tiers[crop.Rarity].Rank >= RarityConfig.AnnounceHarvestRank then
					services.Remotes.Announce:FireAllClients(string.format("%s opened a %s seed from a Seed Crate!", player.DisplayName, crop.Name), RarityConfig.Tiers[crop.Rarity].Color)
				end
			end
			services.Remotes.Effect:FireClient(player, "Crate", { crops = rolls })
			services.Remotes.Notify:FireClient(player, "Seed Crate: " .. table.concat(names, ", "), "good")
		end
	elseif product.Key == "InstantRestock" then
		after = function()
			services.StockService.instantRestock(player)
		end
	elseif product.Weather then
		after = function()
			services.WeatherService.request(product.Weather, player)
		end
	end
	return undo, after
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
	-- Live game without a saved profile (DataStore down / load failed / lock lost): a grant
	-- would vanish on leave and the PurchaseId would never be recorded. Let Roblox retry.
	if not services.DataService.isPersistent(player) and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local undo, after = prepareGrant(player, profile, product)
	profile.Receipts[id] = os.time()
	trimReceipts(profile)
	if services.DataService.isPersistent(player) and not services.DataService.save(player) then
		undo()
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	services.DataService.markDirty(player)
	local ok, err = pcall(after)
	if not ok then
		warn("[SproutValley] purchase effect failed: " .. tostring(err))
	end
	services.Remotes.Notify:FireClient(player, "Thank you! Purchased: " .. product.Name, "good")
	services.DataService.sendProfile(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio-only free grant for products whose ProductId is still 0.
local function studioGrant(player, product)
	local profile = services.DataService.getProfile(player)
	if not profile then
		return
	end
	local _, after = prepareGrant(player, profile, product)
	services.DataService.markDirty(player)
	after()
	services.Remotes.Notify:FireClient(player, "Studio test: granted " .. product.Name .. " for free", "info")
	services.DataService.sendProfile(player)
end

function ShopService.buy(player, key)
	local product = productsByKey[key]
	local pass = passesByKey[key]
	if product then
		if product.ProductId > 0 then
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		elseif RunService:IsStudio() then
			studioGrant(player, product)
		else
			services.Remotes.Notify:FireClient(player, "This item isn't available yet.", "warn")
		end
	elseif pass then
		if ShopService.owns(player, key) then
			services.Remotes.Notify:FireClient(player, "You already own " .. pass.Name .. "!", "info")
		elseif pass.PassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
		elseif RunService:IsStudio() then
			grantPassForSession(player, key)
			services.Remotes.Notify:FireClient(player, "Studio test: " .. pass.Name .. " enabled for this session", "info")
		else
			services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
		end
	end
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = ShopService.processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passesById[passId]
		if purchased and pass then
			grantPassForSession(player, pass.Key)
			services.Remotes.Notify:FireClient(player, "Thank you! " .. pass.Name .. " is active.", "good")
			if pass.Key == "VIP" then
				services.Remotes.Announce:FireAllClients(player.DisplayName .. " just became a VIP Gardener!", pass.Color)
			end
		end
	end)

	services.Remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		local now = os.clock()
		if type(key) ~= "string" or #key > 40 or (lastRequest[player] and now - lastRequest[player] < 0.75) then
			return
		end
		lastRequest[player] = now
		ShopService.buy(player, key)
	end)
end

function ShopService.onPlayerRemoving(player)
	passCache[player] = nil
	lastRequest[player] = nil
end

return ShopService
