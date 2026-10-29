--[[
	ShopService - OPTIONAL purchases: Robux cosmetics, the VIP pass, the Value Boost, and
	Vault Token cosmetics; plus equipping. The base game never needs any of it.

	Developer Products go through MarketplaceService.ProcessReceipt:
	  * the PurchaseId is recorded in the profile and the profile is SAVED before
	    PurchaseGranted is returned, so a purchase is granted exactly once;
	  * if the profile isn't loaded, can't persist in a live game, is mid leave / shutdown
	    save, or the save fails, the grant is undone and NotProcessedYet is returned
	    (Roblox retries later).
	Game Passes: UserOwnsGamePassAsync (pcall, cached per session) and
	PromptGamePassPurchaseFinished. IDs of 0: Studio grants for free (testing), a live game
	says "not available yet". Ownership keys are "<Kind>:<Id>" (e.g. "Theme:GoldenGlow").
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local ShopConfig = require(Shared.Config.ShopConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)

local ShopService = {}

local services
local productsByKey, productsById = {}, {}
local passesByKey, passesById = {}, {}
local passCache = {}
local lastRequest = {}

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

-- Re-reads the config (used by tests after setting a real product id).
function ShopService.reindex()
	table.clear(productsById)
	for _, product in ipairs(ShopConfig.Products) do
		productsByKey[product.Key] = product
		if product.ProductId > 0 then
			productsById[product.ProductId] = product
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
	-- Failed (throttled / outage): cache "not owned" so later calls never yield again, and
	-- retry once in the background.
	cache[key] = false
	task.delay(30, function()
		if passCache[player] == cache and cache[key] == false and player.Parent then
			cache[key] = nil
			ShopService.ownsPass(player, key)
		end
	end)
	return false
end

-- Never yields: only what is already cached (stats() is used inside atomic claims and
-- deposits, which must not yield between their checks and their writes).
function ShopService.cachedPass(player, key)
	local cache = passCache[player]
	return cache ~= nil and cache[key] == true
end

function ShopService.owns(player, kind, id)
	local data = services.DataService.getProfile(player)
	local catalog = CosmeticConfig.Kinds[kind]
	local def = catalog and catalog[id]
	if not data or not def then
		return false
	end
	if def.Source == "Default" or data.Cosmetics.Owned[kind .. ":" .. id] then
		return true
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		if pass.Kind == kind and pass.Item == id and ShopService.ownsPass(player, pass.Key) then
			return true
		end
	end
	return false
end

function ShopService.ownedList(player)
	local out = {}
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		for id in pairs(catalog) do
			if ShopService.owns(player, kind, id) then
				out[kind .. ":" .. id] = true
			end
		end
	end
	return out
end

function ShopService.buyWithTokens(player, kind, id)
	local catalog = type(kind) == "string" and CosmeticConfig.Kinds[kind]
	local def = catalog and type(id) == "string" and catalog[id]
	if not def or def.Source ~= "Tokens" then
		return false, "That item isn't sold for Vault Tokens."
	end
	if ShopService.owns(player, kind, id) then
		return false, "You already own " .. def.Name .. "."
	end
	if not services.DataService.spendTokens(player, def.Cost) then
		return false, string.format("%s costs %d Vault Tokens.", def.Name, def.Cost)
	end
	services.DataService.getProfile(player).Cosmetics.Owned[kind .. ":" .. id] = true
	ShopService.equip(player, kind, id)
	return true, def.Name .. " unlocked and equipped!"
end

function ShopService.equip(player, kind, id)
	local data = services.DataService.getProfile(player)
	local catalog = type(kind) == "string" and CosmeticConfig.Kinds[kind]
	if not data or not catalog or type(id) ~= "string" or not catalog[id] then
		return false, "Unknown item."
	end
	if not ShopService.owns(player, kind, id) then
		return false, "You don't own " .. catalog[id].Name .. " yet."
	end
	data.Cosmetics[kind] = id
	services.DataService.markDirty(player)
	services.PlayerService.updateAttributes(player)
	services.DataService.sendProfile(player)
	return true, catalog[id].Name .. " equipped."
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

-- Applies a product to a profile; returns an undo function.
local function grantProduct(profile, product)
	if product.Boost then
		local before = profile.BoostUntil
		local now = os.time()
		profile.BoostUntil = math.min(math.max(now, profile.BoostUntil) + product.Boost, now + ShopConfig.BoostMax)
		return function()
			profile.BoostUntil = before
		end
	end
	local key = product.Kind .. ":" .. product.Item
	local had = profile.Cosmetics.Owned[key] == true
	profile.Cosmetics.Owned[key] = true
	return function()
		if not had then
			profile.Cosmetics.Owned[key] = nil
		end
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
	if services.DataService.isPersistent(player) and not services.DataService.save(player) then
		undo()
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	services.DataService.markDirty(player)
	services.Remotes.Notify:FireClient(player, "Thank you! " .. product.Name .. " is yours.", "good")
	services.PlayerService.updateAttributes(player)
	services.DataService.sendProfile(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
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
				services.DataService.markDirty(player)
				services.Remotes.Notify:FireClient(player, "Studio test: granted " .. product.Name .. " for free", "info")
				services.PlayerService.updateAttributes(player)
				services.DataService.sendProfile(player)
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
			passCache[player] = passCache[player] or {}
			passCache[player][key] = true
			services.Remotes.Notify:FireClient(player, "Studio test: " .. pass.Name .. " enabled for this session", "info")
			services.PlayerService.updateAttributes(player)
			services.DataService.sendProfile(player)
		else
			services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
		end
	end
end

function ShopService.onProfileLoaded(player)
	-- Warm the pass cache so the first deposit already sees VIP.
	for _, pass in ipairs(ShopConfig.Passes) do
		ShopService.ownsPass(player, pass.Key)
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
			passCache[player] = passCache[player] or {}
			passCache[player][pass.Key] = true
			services.Remotes.Notify:FireClient(player, "Thank you! " .. pass.Name .. " unlocked.", "good")
			services.PlayerService.updateAttributes(player)
			services.DataService.sendProfile(player)
		end
	end)
	local remotes = services.Remotes
	local function throttled(player, gap)
		local t = os.clock()
		if lastRequest[player] and t - lastRequest[player] < gap then
			return true
		end
		lastRequest[player] = t
		return false
	end
	remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" or #key > 40 or throttled(player, 0.75) then
			return
		end
		ShopService.buy(player, key)
	end)
	remotes.BuyCosmetic.OnServerEvent:Connect(function(player, kind, id)
		if throttled(player, 0.4) then
			return
		end
		local ok, message = ShopService.buyWithTokens(player, kind, id)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
	remotes.Equip.OnServerEvent:Connect(function(player, kind, id)
		if throttled(player, 0.3) then
			return
		end
		local ok, message = ShopService.equip(player, kind, id)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
end

return ShopService
