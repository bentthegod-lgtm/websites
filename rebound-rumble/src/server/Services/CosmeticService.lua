--[[
	CosmeticService - crates / spins (coins or Premium Spins), equipping cosmetics.
	All rolls happen on the server; the client only plays the reveal animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local CrateRoll = require(Shared.CrateRoll)
local Rng = require(Shared.Rng)

local CosmeticService = {}

local services
local rng
local lastOpen = {}

function CosmeticService.init(registry)
	services = registry
	rng = Rng.new(math.floor(os.clock() * 1e6) + os.time())
end

function CosmeticService.setSeed(seed)
	rng = Rng.new(seed)
end

function CosmeticService.item(id)
	return CrateRoll.find(CosmeticConfig, id)
end

-- Returns the equipped cosmetic item defs for a player: { ParryFx, Trail, Explosion }.
function CosmeticService.equippedFor(player)
	local profile = services.DataService.getProfile(player)
	local result = {}
	for _, category in ipairs(CosmeticConfig.Categories) do
		local id = profile and profile.Equipped[category]
		result[category] = id
	end
	return result
end

-- Builds a reel for the spin animation: random items ending with the winner.
local function reelFor(crate, winner)
	local reel = {}
	for _ = 1, 24 do
		local item = CrateRoll.roll(crate, CosmeticConfig, rng, 0)
		table.insert(reel, item.Id)
	end
	table.insert(reel, winner.Id)
	return reel
end

function CosmeticService.open(player, crateKey)
	local profile = services.DataService.getProfile(player)
	local crate = CosmeticConfig.Crates[crateKey]
	if not profile or not crate then
		return nil, "Unknown crate."
	end
	if crate.SpinCurrency then
		if (profile[crate.SpinCurrency] or 0) < 1 then
			return nil, "You have no Premium Spins. Get some in the shop!"
		end
		profile[crate.SpinCurrency] -= 1
	else
		if not services.DataService.spendCoins(player, crate.CoinPrice) then
			return nil, "Not enough coins."
		end
	end
	local item, info = CrateRoll.roll(crate, CosmeticConfig, rng, profile.Pity)
	if not item then
		return nil, "Crate is empty."
	end
	profile.Pity = info.pity
	profile.Stats.CratesOpened += 1
	local duplicate = profile.Owned[item.Category][item.Id] == true
	local refund = 0
	if duplicate then
		refund = CosmeticConfig.Rarities[item.Rarity].Refund
		profile.Coins += refund
	else
		profile.Owned[item.Category][item.Id] = true
	end
	services.DataService.markDirty(player)
	services.DataService.updateLeaderstats(player)
	local result = {
		crate = crateKey,
		itemId = item.Id,
		rarity = info.rarity,
		duplicate = duplicate,
		refund = refund,
		pityTriggered = info.pityTriggered,
		reel = reelFor(crate, item),
	}
	if info.rarity == "Legendary" or info.rarity == "Mythic" then
		services.Remotes.Announce:FireAllClients(string.format("%s unboxed %s %s!", player.DisplayName, string.upper(info.rarity), item.Name), info.rarity)
	end
	return result
end

function CosmeticService.equip(player, category, id)
	local profile = services.DataService.getProfile(player)
	if not profile or type(category) ~= "string" or type(id) ~= "string" then
		return false
	end
	local item = CosmeticService.item(id)
	if not item or item.Category ~= category or not profile.Owned[category] or not profile.Owned[category][id] then
		return false
	end
	if item.Pass and not services.ShopService.owns(player, item.Pass) then
		return false
	end
	profile.Equipped[category] = id
	services.DataService.markDirty(player)
	if services.MatchService then
		services.MatchService.refreshCosmetics(player)
	end
	return true
end

-- Called by DataService on PlayerRemoving, before the leave save.
function CosmeticService.onPlayerRemoving(player)
	lastOpen[player] = nil
end

function CosmeticService.start()
	services.Remotes.OpenCrate.OnServerEvent:Connect(function(player, crateKey)
		local now = os.clock()
		if type(crateKey) ~= "string" or (lastOpen[player] and now - lastOpen[player] < 1.5) then
			return
		end
		lastOpen[player] = now
		local result, err = CosmeticService.open(player, crateKey)
		if result then
			services.Remotes.CrateResult:FireClient(player, result)
		else
			services.Remotes.Notify:FireClient(player, err, "warn")
		end
		services.DataService.sendProfile(player)
	end)
	services.Remotes.EquipCosmetic.OnServerEvent:Connect(function(player, category, id)
		if CosmeticService.equip(player, category, id) then
			services.DataService.sendProfile(player)
		end
	end)
end

return CosmeticService
