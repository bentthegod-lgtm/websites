--[[
	ShopService - the wardrobe (coin outfits / lanterns, level unlocks, equipping) and the
	OPTIONAL Robux items: cosmetic products, the VIP pass, and the Thermos Flask (a
	consumable that thaws you once - a friend can always thaw you for free).

	Developer Products go through MarketplaceService.ProcessReceipt:
	  * the PurchaseId is recorded in the profile and the profile is SAVED before
	    PurchaseGranted is returned, so a purchase is granted exactly once;
	  * if the profile isn't loaded, can't persist in a live game, is mid leave/shutdown
	    save, or the save fails, the grant is undone and NotProcessedYet is returned
	    (Roblox retries later).
	Game Passes: UserOwnsGamePassAsync (pcall, cached per session) and
	PromptGamePassPurchaseFinished. IDs of 0: Studio grants for free, live says "not
	available". Ownership keys are "<Kind>:<Id>" (e.g. "Outfit:Polar").
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local ShopConfig = require(Shared.Config.ShopConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Format = require(Shared.Format)
local Progress = require(Shared.Progress)

local ShopService = {}

local services
local productsByKey, productsById = {}, {}
local passesByKey, passesById = {}, {}
local passCache = {}
local lastRequest = {}
local lastEquip = {}

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

-- Does the player own this cosmetic (any source)?
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
	if def.Source == "Level" then
		return Progress.levelFor(data.Xp) >= (def.Level or 1)
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		if pass.Grants[kind] == id and ShopService.ownsPass(player, pass.Key) then
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

function ShopService.buyWithCoins(player, kind, id)
	local catalog = type(kind) == "string" and CosmeticConfig.Kinds[kind]
	local def = catalog and type(id) == "string" and catalog[id]
	if not def or def.Source ~= "Coins" then
		return false, "That item isn't sold for coins."
	end
	if ShopService.owns(player, kind, id) then
		return false, "You already own " .. def.Name .. "."
	end
	if not services.DataService.getProfile(player) then
		return false, "Your profile is still loading."
	end
	if not services.DataService.spendCoins(player, def.Cost) then
		return false, string.format("%s costs %s coins.", def.Name, Format.short(def.Cost))
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
	if services.PlayerService then
		services.PlayerService.applyLook(player)
	end
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

-- Applies a product's grants; returns a function that undoes them exactly.
local function grantProduct(profile, product)
	local undo = {}
	for kind, value in pairs(product.Grants) do
		if kind == "Flask" then
			profile.Boosts.Flask += value
			table.insert(undo, function()
				profile.Boosts.Flask = math.max(0, profile.Boosts.Flask - value)
			end)
		elseif CosmeticConfig.Kinds[kind] then
			local key = kind .. ":" .. value
			local had = profile.Cosmetics.Owned[key] == true
			profile.Cosmetics.Owned[key] = true
			table.insert(undo, function()
				if not had then
					profile.Cosmetics.Owned[key] = nil
				end
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
	if product.Grants.Flask then
		return string.format("Thank you! +%d Thermos Flask%s - it thaws you once if you freeze.", product.Grants.Flask, if product.Grants.Flask == 1 then "" else "s")
	end
	return "Thank you! " .. product.Name .. " is yours - equip it in the Wardrobe."
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
	services.Remotes.Notify:FireClient(player, thanks(product), "good")
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
			if services.PlayerService then
				services.PlayerService.refreshTags(player)
			end
			services.DataService.sendProfile(player)
		else
			services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
		end
	end
end

function ShopService.onPlayerRemoving(player)
	passCache[player] = nil
	lastRequest[player] = nil
	lastEquip[player] = nil
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = ShopService.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passesById[passId]
		if purchased and pass then
			passCache[player] = passCache[player] or {}
			passCache[player][pass.Key] = true
			services.Remotes.Notify:FireClient(player, "Thank you! VIP unlocked - the Golden Parka is in your Wardrobe.", "good")
			if services.PlayerService then
				services.PlayerService.refreshTags(player)
			end
			services.DataService.sendProfile(player)
		end
	end)
	local remotes = services.Remotes
	local function throttled(player, gap, map)
		local t = os.clock()
		if map[player] and t - map[player] < gap then
			return true
		end
		map[player] = t
		return false
	end
	remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" or #key > 40 or throttled(player, 0.75, lastRequest) then
			return
		end
		ShopService.buy(player, key)
	end)
	remotes.BuyCosmetic.OnServerEvent:Connect(function(player, kind, id)
		if throttled(player, 0.4, lastRequest) then
			return
		end
		local ok, message = ShopService.buyWithCoins(player, kind, id)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
	remotes.Equip.OnServerEvent:Connect(function(player, kind, id)
		if throttled(player, 0.3, lastEquip) then
			return
		end
		local ok, message = ShopService.equip(player, kind, id)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
end

return ShopService
