--[[
	ShopService - the optional Robux items.

	Developer Products (Life Jacket, Rescue Flare, coin packs) go through
	MarketplaceService.ProcessReceipt:
	  * the PurchaseId is recorded in the profile and the profile is SAVED before
	    PurchaseGranted is returned, so a purchase is granted exactly once (a retried receipt
	    with the same PurchaseId is acknowledged without granting again);
	  * if the profile isn't loaded, can't persist in a live game, is mid leave / shutdown
	    save, or the save fails, the grant is undone and NotProcessedYet is returned (Roblox
	    retries later).
	Game Passes (x2 Loot, Grapple Hook, Captain's Outfit, VIP): UserOwnsGamePassAsync
	(pcall, cached per session) and PromptGamePassPurchaseFinished.
	IDs of 0: Studio grants for free; a live game says "not available yet".
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local ShopConfig = require(Shared.Config.ShopConfig)
local Format = require(Shared.Format)

local ShopService = {}

local services
local productsByKey, productsById = {}, {}
local passesByKey, passesById = {}, {}
local passCache = {}
local lastRequest = {}
local inFlight = {} -- PurchaseIds whose grant is being saved right now

function ShopService.init(registry)
	services = registry
	productsByKey, productsById, passesByKey, passesById = {}, {}, {}, {}
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

function ShopService.ownsPass(player, key)
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
	return false
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

-- Applies a product's grants; returns a function that undoes them exactly.
local function grantProduct(profile, product)
	local undo = {}
	for kind, value in pairs(product.Grants) do
		if kind == "Coins" then
			profile.Coins += value
			table.insert(undo, function()
				profile.Coins = math.max(0, profile.Coins - value)
			end)
		elseif kind == "LifeJacket" or kind == "Flare" then
			profile.Boosts[kind] += value
			table.insert(undo, function()
				profile.Boosts[kind] = math.max(0, profile.Boosts[kind] - value)
			end)
		end
	end
	return function()
		for _, fn in ipairs(undo) do
			fn()
		end
	end
end
ShopService.grantProduct = grantProduct

local function thanks(product)
	local g = product.Grants
	if g.Coins then
		return string.format("Thank you! +%s coins.", Format.exact(g.Coins))
	elseif g.LifeJacket then
		return "Thank you! +1 Life Jacket - it auto-revives you once when you go down."
	elseif g.Flare then
		return "Thank you! +1 Rescue Flare - press F (or the FLARE button) during a round."
	end
	return "Thank you! " .. product.Name .. " is yours."
end

local function afterGrant(player)
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	if services.PlayerService then
		services.PlayerService.refresh(player)
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
	-- Roblox can call again while the first call is still saving. Receipts[id] is already set
	-- then, but the save may still fail and be undone: never acknowledge it from here.
	if inFlight[id] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if profile.Receipts[id] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not services.DataService.isPersistent(player) and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Leaving / shutting down: the final save may already have run (and released the lock),
	-- so a grant now could be acknowledged without ever being saved. Roblox retries later.
	if services.DataService.isLeaving(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local undo = grantProduct(profile, product)
	profile.Receipts[id] = os.time()
	trimReceipts(profile)
	inFlight[id] = true
	local saved = not services.DataService.isPersistent(player) or services.DataService.save(player)
	inFlight[id] = nil
	if not saved then
		undo()
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	services.Remotes.Notify:FireClient(player, thanks(product), "good")
	afterGrant(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function passThanks(pass)
	return string.format("Thank you! %s unlocked.", pass.Name)
end

function ShopService.grantPassSession(player, key)
	passCache[player] = passCache[player] or {}
	passCache[player][key] = true
	afterGrant(player)
end

function ShopService.buy(player, key)
	local product = productsByKey[key]
	local pass = passesByKey[key]
	if product then
		if product.ProductId > 0 then
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		elseif RunService:IsStudio() then
			local profile = services.DataService.getProfile(player)
			if profile then
				grantProduct(profile, product)
				services.Remotes.Notify:FireClient(player, "Studio test: granted " .. product.Name .. " for free", "info")
				afterGrant(player)
			end
		else
			services.Remotes.Notify:FireClient(player, "This item isn't available yet.", "warn")
		end
	elseif pass then
		if ShopService.ownsPass(player, key) then
			services.Remotes.Notify:FireClient(player, "You already own " .. pass.Name .. "!", "info")
		elseif pass.PassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
		elseif RunService:IsStudio() then
			services.Remotes.Notify:FireClient(player, "Studio test: " .. pass.Name .. " enabled for this session", "info")
			ShopService.grantPassSession(player, key)
		else
			services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
		end
	end
end

function ShopService.onPlayerRemoving(player)
	passCache[player] = nil
	lastRequest[player] = nil
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = ShopService.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passesById[passId]
		if purchased and pass then
			services.Remotes.Notify:FireClient(player, passThanks(pass), "good")
			ShopService.grantPassSession(player, pass.Key)
		end
	end)
	services.Remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" or #key > 40 then
			return
		end
		local t = os.clock()
		if lastRequest[player] and t - lastRequest[player] < 0.75 then
			return
		end
		lastRequest[player] = t
		ShopService.buy(player, key)
	end)
end

return ShopService
