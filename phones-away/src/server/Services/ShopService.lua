--[[
	ShopService - Robux purchases.

	Developer Products (MarketplaceService.ProcessReceipt):
	  * The receipt's PurchaseId is stored in the profile and the profile is SAVED before
	    PurchaseGranted is returned, so a purchase is granted exactly once even if Roblox
	    retries the receipt or the server crashes. If the profile isn't loaded, or (in a live
	    game) the profile can't be saved, NotProcessedYet is returned and Roblox retries.
	  * World effects (Pizza Party for the server, leaving detention) run only after the save.

	Game Passes: UserOwnsGamePassAsync (pcall, cached per session, looked up when the
	profile loads) + PromptGamePassPurchaseFinished for in-game purchases.

	Paid random items (the Phone Skin Crate): hidden and refused for players whose
	PolicyService info says ArePaidRandomItemsRestricted (or when the lookup fails), the same
	way Snatch Tycoon does it.

	IDs of 0 = not set up: Studio grants for free (testing), live game says "not available".
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local ShopConfig = require(Shared.Config.ShopConfig)
local Economy = require(Shared.Economy)

local ShopService = {}

local services
local productsByKey, productsById = {}, {}
local passesByKey, passesById = {}, {}
local passCache = {} -- [player] = { [key] = true }
local randomRestricted = {} -- [player] = true when paid random items are not allowed
local lastRequest = {}

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

---------------------------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------------------------

function ShopService.owns(player, key)
	return (passCache[player] or {})[key] == true
end

function ShopService.passesFor(player)
	local out = {}
	for _, pass in ipairs(ShopConfig.Passes) do
		out[pass.Key] = ShopService.owns(player, pass.Key)
	end
	return out
end

function ShopService.cloutMultiplier(player)
	return Economy.cloutMultiplier(ShopService.passesFor(player), ShopConfig)
end

local function onPassOwned(player, key)
	passCache[player] = passCache[player] or {}
	if passCache[player][key] then
		return
	end
	passCache[player][key] = true
	player:SetAttribute("PA_" .. key, true)
	if services.RoundService then
		services.RoundService.refreshTag(player)
	end
	if services.PhoneService then
		services.PhoneService.refreshStats(player)
	end
	services.DataService.sendProfile(player)
end
ShopService._grantPass = onPassOwned -- harness hook

function ShopService.refreshPasses(player)
	for _, pass in ipairs(ShopConfig.Passes) do
		if pass.PassId > 0 and not ShopService.owns(player, pass.Key) then
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
			end)
			if ok and owned then
				onPassOwned(player, pass.Key)
			elseif not ok then
				warn("[PhonesAway] Pass check for " .. pass.Key .. " errored: " .. tostring(owned))
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- PolicyService (paid random items)
---------------------------------------------------------------------------------------------

local function loadPolicy(player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- Fail safe: if the lookup fails, treat paid random items as restricted.
	randomRestricted[player] = not ok or type(info) ~= "table" or info.ArePaidRandomItemsRestricted == true
end
ShopService._loadPolicy = loadPolicy

function ShopService.randomItemsAllowed(player)
	return randomRestricted[player] ~= true
end

function ShopService.onProfileLoaded(player)
	passCache[player] = passCache[player] or {}
	loadPolicy(player)
	task.spawn(function()
		ShopService.refreshPasses(player)
	end)
end

---------------------------------------------------------------------------------------------
-- Developer products
---------------------------------------------------------------------------------------------

--[[
	Applies the profile part of a product. Returns undo() (reverts exactly this grant if the
	save fails) and after() (world effects, run once the receipt is safely saved).
]]
local function prepareGrant(player, profile, product)
	local g = product.Grants
	local undo, after = function() end, function() end
	if g.Clout then
		profile.Clout += g.Clout
		undo = function()
			profile.Clout = math.max(0, profile.Clout - g.Clout)
		end
		after = function()
			services.Remotes.Effect:FireClient(player, "Clout", { amount = g.Clout, big = true })
		end
	elseif g.DetentionPass then
		profile.Tokens.DetentionPass += g.DetentionPass
		undo = function()
			profile.Tokens.DetentionPass -= g.DetentionPass
		end
		after = function()
			-- Bought while sitting in detention: use it right away.
			if services.RoundService and services.RoundService.inDetention(player) then
				services.RoundService.useDetentionPass(player)
			end
		end
	elseif g.HallPass then
		profile.Tokens.HallPass += g.HallPass
		undo = function()
			profile.Tokens.HallPass -= g.HallPass
		end
		after = function()
			services.Remotes.Notify:FireClient(player, "Fake Hall Pass ready: your next catch is forgiven.", "good")
		end
	elseif g.PizzaParty then
		after = function()
			services.RoundService.startPizza(player)
		end
	elseif g.Crate then
		local result, revert = services.CosmeticService.rollCrate(player, profile, g.Crate)
		undo = revert or undo
		after = function()
			if result then
				services.CosmeticService.announceRoll(player, result)
			end
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
		warn("[PhonesAway] purchase effect failed: " .. tostring(err))
	end
	services.Remotes.Notify:FireClient(player, "Thank you! Purchased: " .. product.Name, "good")
	services.Remotes.Effect:FireClient(player, "Purchase", { key = product.Key })
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
	local ok, err = pcall(after)
	if not ok then
		warn("[PhonesAway] studio grant effect failed: " .. tostring(err))
	end
	services.Remotes.Notify:FireClient(player, "Studio test: granted " .. product.Name .. " for free", "info")
	services.DataService.sendProfile(player)
end

function ShopService.buy(player, key)
	local product = productsByKey[key]
	local pass = passesByKey[key]
	if product then
		if product.Random and not ShopService.randomItemsAllowed(player) then
			services.Remotes.Notify:FireClient(player, "Crates aren't available in your region.", "warn")
			return false
		end
		if product.ProductId > 0 then
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		elseif RunService:IsStudio() then
			studioGrant(player, product)
		else
			services.Remotes.Notify:FireClient(player, "This item isn't available yet.", "warn")
			return false
		end
		return true
	elseif pass then
		if ShopService.owns(player, key) then
			services.Remotes.Notify:FireClient(player, "You already own " .. pass.Name .. "!", "info")
			return false
		elseif pass.PassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
		elseif RunService:IsStudio() then
			onPassOwned(player, key)
			services.Remotes.Notify:FireClient(player, "Studio test: " .. pass.Name .. " enabled for this session", "info")
		else
			services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
			return false
		end
		return true
	end
	return false
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = ShopService.processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passesById[passId]
		if purchased and pass and player.Parent then
			onPassOwned(player, pass.Key)
			services.Remotes.Notify:FireClient(player, "Thank you! " .. pass.Name .. " is active.", "good")
			if pass.Key == "VIP" then
				services.Remotes.Announce:FireAllClients(player.DisplayName .. " just became a VIP student!", pass.Color)
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
	randomRestricted[player] = nil
end

return ShopService
