--[[
	CosmeticService - Clout purchases: phone upgrades, cosmetics (phone skins, desk decor,
	wallpapers), equipping, and crates (Locker Crate for Clout here; the Robux Phone Skin
	Crate goes through ShopService and calls rollCrate).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CrateRoll = require(Shared.CrateRoll)
local Economy = require(Shared.Economy)
local Rng = require(Shared.Rng)

local CosmeticService = {}

local services
local rng = Rng.new(os.time() % 100000 + 7)
local lastRequest = {}

function CosmeticService.init(registry)
	services = registry
end

local function limited(player, gap)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < gap then
		return true
	end
	lastRequest[player] = now
	return false
end

local function changed(player)
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	if services.PhoneService then
		services.PhoneService.refreshStats(player)
	end
end

function CosmeticService.buyUpgrade(player, key)
	local profile = services.DataService.getProfile(player)
	if not profile or type(key) ~= "string" or not UpgradeConfig[key] or not table.find(UpgradeConfig.Order, key) then
		return false, "Unknown upgrade."
	end
	local price, nextTier, def = Economy.nextUpgrade(UpgradeConfig, key, profile.Upgrades[key])
	if not price then
		return false, "Already maxed out!"
	end
	if not services.DataService.spendClout(player, price) then
		return false, "Not enough Clout."
	end
	profile.Upgrades[key] = nextTier
	changed(player)
	services.Remotes.Notify:FireClient(player, string.format("Upgraded: %s", def.Name), "good")
	services.Remotes.Effect:FireClient(player, "Upgrade", { key = key, name = def.Name })
	return true
end

function CosmeticService.buyCosmetic(player, category, id)
	local profile = services.DataService.getProfile(player)
	if not profile or type(category) ~= "string" or type(id) ~= "string" then
		return false
	end
	local item = CrateRoll.find(CosmeticConfig, category, id)
	if not item or not item.Price then
		return false, "That item is crate-only."
	end
	if profile.Owned[category][id] then
		return false, "You already own that."
	end
	if not services.DataService.spendClout(player, item.Price) then
		return false, "Not enough Clout."
	end
	profile.Owned[category][id] = true
	profile.Equipped[category] = id
	changed(player)
	services.Remotes.Notify:FireClient(player, "Unlocked: " .. item.Name, "good")
	if services.RoundService then
		services.RoundService.refreshDesk(player)
	end
	return true
end

function CosmeticService.equip(player, category, id)
	local profile = services.DataService.getProfile(player)
	if not profile or type(category) ~= "string" or type(id) ~= "string" or not profile.Owned[category] then
		return false
	end
	if not profile.Owned[category][id] or not CrateRoll.find(CosmeticConfig, category, id) then
		return false
	end
	profile.Equipped[category] = id
	changed(player)
	if services.RoundService then
		services.RoundService.refreshDesk(player)
	end
	return true
end

--[[
	Rolls a crate into the profile (pity, duplicate refund). Returns result, undo.
	result = { crate, category, id, name, rarity, duplicate, refund }
]]
function CosmeticService.rollCrate(_player, profile, crateKey)
	local crate = CosmeticConfig.Crates[crateKey]
	if not crate then
		return nil, nil
	end
	local item, info = CrateRoll.roll(crate, CosmeticConfig, rng, profile.Pity)
	if not item then
		return nil, nil
	end
	local oldPity = profile.Pity
	profile.Pity = info.pity
	local duplicate = profile.Owned[item.Category][item.Id] == true
	local refund = 0
	if duplicate then
		refund = CosmeticConfig.Rarities[item.Rarity].Refund
		profile.Clout += refund
	else
		profile.Owned[item.Category][item.Id] = true
	end
	local result = { crate = crateKey, category = item.Category, id = item.Id, name = item.Name, rarity = item.Rarity, duplicate = duplicate, refund = refund, pity = info.pityTriggered }
	local function undo()
		profile.Pity = oldPity
		if duplicate then
			profile.Clout = math.max(0, profile.Clout - refund)
		else
			profile.Owned[item.Category][item.Id] = nil
		end
	end
	return result, undo
end

function CosmeticService.announceRoll(player, result)
	services.Remotes.CrateResult:FireClient(player, result)
	if CrateRoll.rankOf(CosmeticConfig, result.rarity) >= CosmeticConfig.AnnounceRank then
		services.Remotes.Announce:FireAllClients(string.format("%s unboxed %s %s!", player.DisplayName, string.upper(result.rarity), result.name), CosmeticConfig.Rarities[result.rarity].Color)
	end
	services.DataService.sendProfile(player)
end

-- Clout crates only (the Robux crate is a developer product).
function CosmeticService.openCrate(player, crateKey)
	local profile = services.DataService.getProfile(player)
	local crate = type(crateKey) == "string" and CosmeticConfig.Crates[crateKey]
	if not profile or not crate then
		return false
	end
	if crate.Product then
		return services.ShopService.buy(player, crate.Product)
	end
	if not services.DataService.spendClout(player, crate.CloutPrice) then
		services.Remotes.Notify:FireClient(player, "Not enough Clout for a " .. crate.Name .. ".", "warn")
		return false
	end
	local result = CosmeticService.rollCrate(player, profile, crateKey)
	services.DataService.markDirty(player)
	CosmeticService.announceRoll(player, result)
	return true, result
end

function CosmeticService.onPlayerRemoving(player)
	lastRequest[player] = nil
end

function CosmeticService.start()
	local remotes = services.Remotes
	remotes.BuyUpgrade.OnServerEvent:Connect(function(player, key)
		if limited(player, 0.3) then
			return
		end
		local ok, message = CosmeticService.buyUpgrade(player, key)
		if not ok and message then
			remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	remotes.BuyCosmetic.OnServerEvent:Connect(function(player, category, id)
		if limited(player, 0.3) then
			return
		end
		local ok, message = CosmeticService.buyCosmetic(player, category, id)
		if not ok and message then
			remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	remotes.Equip.OnServerEvent:Connect(function(player, category, id)
		if limited(player, 0.2) then
			return
		end
		CosmeticService.equip(player, category, id)
	end)
	remotes.OpenCrate.OnServerEvent:Connect(function(player, crateKey)
		if limited(player, 1) then
			return
		end
		CosmeticService.openCrate(player, crateKey)
	end)
end

return CosmeticService
