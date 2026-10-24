--[[
	ShopService - Robux purchases of one-run boosts (Developer Products).

	* Purchases go through MarketplaceService.ProcessReceipt. Each receipt's PurchaseId is
	  recorded in the player's profile and saved before the purchase is confirmed, so a
	  purchase is granted exactly once even if the server crashes mid-way.
	* Products with ProductId = 0 are not set up yet: in Studio the Buy button grants them
	  for free (for testing); in a live game it says the item is not available.
	* Players switch boosts on for their next run in the shop; RoundService consumes them
	  when the run starts.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local ShopConfig = require(Shared.Config.ShopConfig)

local ShopService = {}

local services
local byKey, byProductId = {}, {}
local lastRequest = {}

function ShopService.init(registry)
	services = registry
	for _, product in ipairs(ShopConfig.Products) do
		byKey[product.Key] = product
		if product.ProductId and product.ProductId > 0 then
			byProductId[product.ProductId] = product
		end
	end
end

local function grant(profile, product)
	for boost, count in pairs(product.Grants) do
		profile.Boosts[boost] = (profile.Boosts[boost] or 0) + count
	end
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

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = byProductId[receipt.ProductId]
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
	grant(profile, product)
	profile.Receipts[id] = os.time()
	trimReceipts(profile)
	if services.DataService.isPersistent(player) and not services.DataService.save(player) then
		-- Could not save: undo and let Roblox retry the receipt later.
		for boost, count in pairs(product.Grants) do
			profile.Boosts[boost] -= count
		end
		profile.Receipts[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	services.Remotes.Notify:FireClient(player, "Purchased: " .. product.Name, "info")
	services.DataService.sendProfile(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	services.Remotes.ShopBuy.OnServerEvent:Connect(function(player, key)
		local now = os.clock()
		if type(key) ~= "string" or (lastRequest[player] and now - lastRequest[player] < 1) then
			return
		end
		lastRequest[player] = now
		local product = byKey[key]
		if not product then
			return
		end
		if product.ProductId and product.ProductId > 0 then
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		elseif RunService:IsStudio() then
			local profile = services.DataService.getProfile(player)
			if profile then
				grant(profile, product)
				services.DataService.markDirty(player)
				services.Remotes.Notify:FireClient(player, "Studio test: granted " .. product.Name .. " for free", "info")
				services.DataService.sendProfile(player)
			end
		else
			services.Remotes.Notify:FireClient(player, "This item isn't available yet.", "warn")
		end
	end)

	services.Remotes.ShopArm.OnServerEvent:Connect(function(player, boost, on)
		local profile = services.DataService.getProfile(player)
		if not profile or type(boost) ~= "string" or type(on) ~= "boolean" or not ShopConfig.Boosts[boost] then
			return
		end
		profile.Armed[boost] = if on and (profile.Boosts[boost] or 0) > 0 then true else nil
		services.DataService.markDirty(player)
		services.DataService.sendProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

-- Uses up the boosts a player switched on, returning their keys.
function ShopService.consumeForRun(player)
	local profile = services.DataService.getProfile(player)
	local used = {}
	if not profile then
		return used
	end
	for _, boost in ipairs(ShopConfig.BoostOrder) do
		if profile.Armed[boost] and (profile.Boosts[boost] or 0) > 0 then
			profile.Boosts[boost] -= 1
			table.insert(used, boost)
			if profile.Boosts[boost] <= 0 then
				profile.Armed[boost] = nil
			end
		end
	end
	if #used > 0 then
		services.DataService.markDirty(player)
		services.DataService.sendProfile(player)
	end
	return used
end

return ShopService
