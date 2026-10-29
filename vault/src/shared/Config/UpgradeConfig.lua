--[[
	UpgradeConfig - every Cash upgrade and Vault Token perk.

	Cost of the next level = floor(BaseCost * Growth ^ level). UnlockDepth: the upgrade is
	only for sale once that depth is unlocked (advanced upgrades appear deeper down;
	Auto-Collect is never available at the start). Effects are applied by Economy.stats,
	and the Effect text is what the upgrade card shows ("Pickup delay 0.65s -> 0.59s").
]]

local UpgradeConfig = {}

UpgradeConfig.Categories = { "Collection", "Capacity", "Movement", "Earnings" }

UpgradeConfig.List = {
	-- Collection
	{ Key = "PickupSpeed", Name = "Pickup Speed", Category = "Collection", Max = 15, BaseCost = 60, Growth = 1.55, UnlockDepth = 1, Icon = "Hand", Description = "Shorter delay between pickups." },
	{ Key = "CollectionRadius", Name = "Collection Radius", Category = "Collection", Max = 15, BaseCost = 150, Growth = 1.6, UnlockDepth = 1, Icon = "Ring", Description = "Collect loot from farther away." },
	{ Key = "CashMagnet", Name = "Cash Magnet", Category = "Collection", Max = 10, BaseCost = 60000, Growth = 1.75, UnlockDepth = 3, Icon = "Magnet", Description = "Nearby loot slides toward you." },
	{ Key = "AutoCollect", Name = "Auto-Collect", Category = "Collection", Max = 10, BaseCost = 30000000, Growth = 1.85, UnlockDepth = 5, Icon = "Auto", Description = "Collects loot right next to you automatically." },
	-- Capacity
	{ Key = "CarryCapacity", Name = "Carrying Capacity", Category = "Capacity", Max = 40, BaseCost = 100, Growth = 1.42, UnlockDepth = 1, Icon = "Bag", Description = "Carry more loot before depositing." },
	{ Key = "StackSize", Name = "Stack Size", Category = "Capacity", Max = 10, BaseCost = 8000, Growth = 1.7, UnlockDepth = 2, Icon = "Stack", Description = "Stack loot tighter: +6% capacity per level." },
	{ Key = "AdvancedCapacity", Name = "Advanced Loot Capacity", Category = "Capacity", Max = 6, BaseCost = 3000000, Growth = 1.9, UnlockDepth = 4, Icon = "Crate", Description = "Large loot takes less space (min 1 slot)." },
	-- Movement
	{ Key = "MoveSpeed", Name = "Movement Speed", Category = "Movement", Max = 14, BaseCost = 120, Growth = 1.55, UnlockDepth = 1, Icon = "Boot", Description = "Walk faster between loot and the deposit machine." },
	-- Earnings
	{ Key = "LootValue", Name = "Loot Value", Category = "Earnings", Max = 40, BaseCost = 250, Growth = 1.45, UnlockDepth = 1, Icon = "Coin", Description = "Every item you pick up is worth more." },
	{ Key = "DepositBonus", Name = "Deposit Bonus", Category = "Earnings", Max = 20, BaseCost = 20000, Growth = 1.6, UnlockDepth = 2, Icon = "Machine", Description = "Deposits pay out more." },
	{ Key = "RareLuck", Name = "Rare Loot Luck", Category = "Earnings", Max = 10, BaseCost = 100000, Growth = 1.8, UnlockDepth = 3, Icon = "Clover", Description = "Rarer loot spawns more often (capped at 2x)." },
}

-- Vault Token perks: permanent, kept through rebirth.
UpgradeConfig.Perks = {
	{ Key = "GoldenTouch", Name = "Golden Touch", Max = 5, Costs = { 5, 10, 15, 25, 40 }, Description = "+10% loot value per level. Kept through rebirth." },
	{ Key = "DeepPockets", Name = "Deep Pockets", Max = 5, Costs = { 3, 6, 10, 15, 25 }, Description = "+5 carrying capacity per level. Kept through rebirth." },
	{ Key = "QuickHands", Name = "Quick Hands", Max = 3, Costs = { 8, 16, 30 }, Description = "-5% pickup delay per level. Kept through rebirth." },
}

UpgradeConfig.ByKey = {}
for _, def in ipairs(UpgradeConfig.List) do
	UpgradeConfig.ByKey[def.Key] = def
end
UpgradeConfig.PerkByKey = {}
for _, def in ipairs(UpgradeConfig.Perks) do
	UpgradeConfig.PerkByKey[def.Key] = def
end

function UpgradeConfig.cost(def, level)
	return math.floor(def.BaseCost * def.Growth ^ level)
end

-- Rebirth: optional, from Depth 4 onward. Each rebirth needs more cash earned since the
-- last one, and adds a permanent value multiplier plus Vault Tokens.
UpgradeConfig.Rebirth = {
	MinDepth = 4,
	BaseRequirement = 2500000,
	RequirementGrowth = 4,
	ValueBonus = 0.25, -- +25% loot value per rebirth (multiplicative with upgrades)
	Tokens = 10,
	Confirm = "REBIRTH",
}

function UpgradeConfig.rebirthRequirement(count)
	local r = UpgradeConfig.Rebirth
	return math.floor(r.BaseRequirement * r.RequirementGrowth ^ count)
end

return UpgradeConfig
