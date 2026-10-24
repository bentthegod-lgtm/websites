--[[
	ShopService - Robux purchases.

	Developer Products (consumables) go through MarketplaceService.ProcessReceipt. Each
	receipt's PurchaseId is recorded in the profile and saved BEFORE PurchaseGranted is
	returned, so a purchase is granted exactly once even if the server crashes. If the
	profile isn't loaded, or the save fails, NotProcessedYet is returned and Roblox retries.

	Game Passes are checked with UserOwnsGamePassAsync (pcall, cached per session) and
	updated live through PromptGamePassPurchaseFinished.

	IDs of 0 = not set up yet: Studio grants for free (testing), live games say "not
	available yet".
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local ShopConfig = require(Shared.Config.ShopConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Economy = require(Shared.Economy)
local Clock = require(Shared.Clock)

local ShopService = {}

local services
local productByKey, productById = {}, {}
local passByKey, passById = {}, {}
local passCache = {} -- [player] = { [passKey] = true }
local lastRequest = {}

function ShopService.init(registry)
	services = registry
	for _, product in ipairs(ShopConfig.Products) do
		productByKey[product.Key] = product
		if product.ProductId and product.ProductId > 0 then
			productById[product.ProductId] = product
		end
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		passByKey[pass.Key] = pass
		if pass.PassId and pass.PassId > 0 then
			passById[pass.PassId] = pass
		end
	end
end

---------------------------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------------------------

function ShopService.passesFor(player)
	return passCache[player] or {}
end

function ShopService.owns(player, passKey)
	return (passCache[player] or {})[passKey] == true
end

function ShopService.coinMultiplier(player)
	local passes = ShopService.passesFor(player)
	return Economy.coinMultiplier({ VIP = passes.VIP, DoubleCoins = passes.DoubleCoins }, ShopConfig)
end

local function onPassOwned(player, passKey)
	passCache[player] = passCache[player] or {}
	passCache[player][passKey] = true
	-- Pass-exclusive cosmetics are unlocked while the pass is owned.
	local profile = services.DataService.getProfile(player)
	if profile then
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Pass == passKey then
				profile.Owned[item.Category][item.Id] = true
			end
		end
	end
	if passKey == "VIP" then
		player:SetAttribute("RR_VIP", true) -- read by the client for the [VIP] chat tag
		if services.MatchService then
			services.MatchService.refreshTags(player)
		end
	end
end

-- Looks up every pass (yields). Safe to call repeatedly.
function ShopService.refreshPasses(player)
	passCache[player] = passCache[player] or {}
	for _, pass in ipairs(ShopConfig.Passes) do
		if pass.PassId and pass.PassId > 0 and not passCache[player][pass.Key] then
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
			end)
			if ok and owned then
				onPassOwned(player, pass.Key)
			end
		end
	end
	-- Exclusive cosmetics from passes the player no longer owns are hidden (not equipped).
	local profile = services.DataService.getProfile(player)
	if profile then
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Pass and not passCache[player][item.Pass] then
				profile.Owned[item.Category][item.Id] = nil
				if profile.Equipped[item.Category] == item.Id then
					for _, d in ipairs(CosmeticConfig.Items) do
						if d.Category == item.Category and d.Default then
							profile.Equipped[item.Category] = d.Id
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Developer products
---------------------------------------------------------------------------------------------

local function grantProduct(profile, product)
	local g = product.Grants
	if g.Coins then
		profile.Coins += g.Coins
	end
	if g.PremiumSpins then
		profile.PremiumSpins += g.PremiumSpins
	end
end

local function undoProduct(profile, product)
	local g = product.Grants
	if g.Coins then
		profile.Coins -= g.Coins
	end
	if g.PremiumSpins then
		profile.PremiumSpins -= g.PremiumSpins
	end
end

-- Server-wide effects that only apply after the receipt is safely recorded.
local function applyServerEffects(player, product)
	if product.Grants.ExplosionParty then
		ShopService.startExplosionParty(player, product.Grants.ExplosionParty)
	end
end

function ShopService.startExplosionParty(player, seconds)
	local now = Clock.now()
	local current = workspace:GetAttribute("RR_PartyUntil") or 0
	local base = math.max(now, current)
	local untilTime = math.min(base + seconds, now + ShopConfig.ExplosionPartyMax)
	workspace:SetAttribute("RR_PartyUntil", untilTime)
	workspace:SetAttribute("RR_PartyBy", player.DisplayName)
	services.Remotes.Announce:FireAllClients(string.format("%s started a SERVER EXPLOSION PARTY! Every explosion is confetti for %d minutes!", player.DisplayName, math.floor((untilTime - now) / 60 + 0.5)), "party")
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
	local product = productById[receipt.ProductId]
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
	grantProduct(profile, product)
	profile.Receipts[id] = os.time()
	trimReceipts(profile)
	if services.DataService.isPersistent(player) and not services.DataService.save(player) then
		undoProduct(profile, product)
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	services.DataService.markDirty(player)
	applyServerEffects(player, product)
	services.Remotes.Notify:FireClient(player, "Purchased: " .. product.Name .. "!", "good")
	services.DataService.updateLeaderstats(player)
	services.DataService.sendProfile(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function rateLimited(player)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 1 then
		return true
	end
	lastRequest[player] = now
	return false
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = ShopService.processReceipt

	services.Remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" or rateLimited(player) then
			return
		end
		local product = productByKey[key]
		if not product then
			return
		end
		if product.ProductId and product.ProductId > 0 then
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		elseif RunService:IsStudio() then
			local profile = services.DataService.getProfile(player)
			if profile then
				grantProduct(profile, product)
				services.DataService.markDirty(player)
				applyServerEffects(player, product)
				services.Remotes.Notify:FireClient(player, "Studio test: granted " .. product.Name .. " for free", "info")
				services.DataService.updateLeaderstats(player)
				services.DataService.sendProfile(player)
			end
		else
			services.Remotes.Notify:FireClient(player, "This item isn't available yet.", "warn")
		end
	end)

	services.Remotes.BuyPass.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" or rateLimited(player) then
			return
		end
		local pass = passByKey[key]
		if not pass or ShopService.owns(player, key) then
			return
		end
		if pass.PassId and pass.PassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
		elseif RunService:IsStudio() then
			onPassOwned(player, key)
			services.Remotes.Notify:FireClient(player, "Studio test: granted pass " .. pass.Name .. " for this session", "info")
			services.DataService.sendProfile(player)
		else
			services.Remotes.Notify:FireClient(player, "This pass isn't available yet.", "warn")
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passById[passId]
		if purchased and pass then
			onPassOwned(player, pass.Key)
			services.Remotes.Notify:FireClient(player, "Thanks! " .. pass.Name .. " unlocked.", "good")
			services.DataService.sendProfile(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		passCache[player] = nil
	end)
end

-- Test hook (harness): give a pass without MarketplaceService.
ShopService._grantPass = onPassOwned

return ShopService
