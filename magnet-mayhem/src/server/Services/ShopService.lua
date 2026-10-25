--[[
	ShopService - OPTIONAL Robux cosmetics (no stats, no progression) and equipping.

	Developer Products (permanent cosmetics) go through MarketplaceService.ProcessReceipt:
	  * the PurchaseId is recorded in the profile and the profile is SAVED before
	    PurchaseGranted is returned, so a purchase is granted exactly once;
	  * if the profile isn't loaded, can't persist in a live game, or the save fails, the
	    grant is undone and NotProcessedYet is returned (Roblox retries later).
	Game Passes: UserOwnsGamePassAsync (pcall, cached per session) and
	PromptGamePassPurchaseFinished. IDs of 0: Studio grants for free, live says "not available".

	Equip requests are validated against ownership (achievements, products, passes).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local ShopConfig = require(Shared.Config.ShopConfig)
local MagnetConfig = require(Shared.Config.MagnetConfig)

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
	return false
end

function ShopService.passesFor(player)
	local out = {}
	for _, pass in ipairs(ShopConfig.Passes) do
		out[pass.Key] = ShopService.owns(player, pass.Key)
	end
	return out
end

-- Does the player own this skin / trail (any source)?
function ShopService.ownsCosmetic(player, kind, id)
	local data = services.DataService.getProfile(player)
	if not data then
		return false
	end
	if data.Cosmetics.Owned[id] then
		return true
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		if ((kind == "Skin" and pass.Skin == id) or (kind == "Trail" and pass.Trail == id)) and ShopService.owns(player, pass.Key) then
			return true
		end
	end
	return false
end

function ShopService.equip(player, kind, id)
	local data = services.DataService.getProfile(player)
	if not data or type(id) ~= "string" then
		return false, "Not available."
	end
	local catalog = if kind == "Skin" then MagnetConfig.Skins elseif kind == "Trail" then MagnetConfig.Trails else nil
	if not catalog or not catalog[id] then
		return false, "Unknown item."
	end
	if not ShopService.ownsCosmetic(player, kind, id) then
		return false, "You don't own " .. catalog[id].Name .. " yet."
	end
	data.Cosmetics[kind] = id
	services.DataService.markDirty(player)
	services.PlayerService.refreshMagnet(player)
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

local function grantProduct(profile, product)
	local id = product.Skin or product.Trail
	local had = profile.Cosmetics.Owned[id] == true
	profile.Cosmetics.Owned[id] = true
	return function()
		if not had then
			profile.Cosmetics.Owned[id] = nil
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
	local undo = grantProduct(profile, product)
	profile.Receipts[id] = os.time()
	trimReceipts(profile)
	if services.DataService.isPersistent(player) and not services.DataService.save(player) then
		undo()
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	services.DataService.markDirty(player)
	services.Remotes.Notify:FireClient(player, "Thank you! " .. product.Name .. " is yours - equip it in Settings > Cosmetics.", "good")
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
		if ShopService.owns(player, key) then
			services.Remotes.Notify:FireClient(player, "You already own " .. pass.Name .. "!", "info")
		elseif pass.PassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
		elseif RunService:IsStudio() then
			passCache[player] = passCache[player] or {}
			passCache[player][key] = true
			services.Remotes.Notify:FireClient(player, "Studio test: " .. pass.Name .. " enabled for this session", "info")
			services.DataService.sendProfile(player)
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
			passCache[player] = passCache[player] or {}
			passCache[player][pass.Key] = true
			services.Remotes.Notify:FireClient(player, "Thank you! " .. pass.Name .. " unlocked - equip it in Settings > Cosmetics.", "good")
			services.DataService.sendProfile(player)
		end
	end)
	local remotes = services.Remotes
	remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		local t = os.clock()
		if type(key) ~= "string" or #key > 40 or (lastRequest[player] and t - lastRequest[player] < 0.75) then
			return
		end
		lastRequest[player] = t
		ShopService.buy(player, key)
	end)
	remotes.Equip.OnServerEvent:Connect(function(player, kind, id)
		if type(kind) ~= "string" or type(id) ~= "string" then
			return
		end
		local ok, message = ShopService.equip(player, kind, id)
		remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
end

return ShopService
