--[[
	Economy - pure maths for player stats, loot value, capacity use and deposit payouts.
	Shared by the server (authoritative) and the client (display only: the HUD and upgrade
	cards show the same numbers the server will use).

	`state` is a profile-like table: { Upgrades = {...}, Perks = {...}, Rebirths = n,
	BoostUntil = unixTime?, Vip = bool? } - missing fields mean level 0 / off.
]]

local UpgradeConfig = require(script.Parent.Config.UpgradeConfig)

local Economy = {}

local BASE = {
	PickupInterval = 0.65,
	MinPickupInterval = 0.15,
	Radius = 7,
	Capacity = 10,
	WalkSpeed = 16,
}
Economy.Base = BASE

local function level(state, key)
	local upgrades = state and state.Upgrades
	return math.max(0, math.floor((upgrades and upgrades[key]) or 0))
end

local function perk(state, key)
	local perks = state and state.Perks
	return math.max(0, math.floor((perks and perks[key]) or 0))
end

-- Every stat the game uses, from upgrade levels, token perks, rebirths and boosts.
function Economy.stats(state, now)
	local s = {}
	s.PickupInterval = math.max(BASE.MinPickupInterval, BASE.PickupInterval * 0.9 ^ level(state, "PickupSpeed") * (1 - 0.05 * perk(state, "QuickHands")))
	s.Radius = BASE.Radius + 0.8 * level(state, "CollectionRadius")
	local magnet = level(state, "CashMagnet")
	s.MagnetRadius = if magnet > 0 then 10 + 3 * magnet else 0
	s.MagnetSpeed = if magnet > 0 then 14 + 2 * magnet else 0
	local auto = level(state, "AutoCollect")
	s.AutoRadius = if auto > 0 then 4 + 0.6 * auto else 0
	s.AutoInterval = if auto > 0 then math.max(0.2, 1.4 - 0.1 * auto) else 0
	local rawCapacity = BASE.Capacity + 5 * level(state, "CarryCapacity") + 5 * perk(state, "DeepPockets")
	s.Capacity = math.floor(rawCapacity * (1 + 0.06 * level(state, "StackSize")))
	s.LargeSlotFactor = 1 - 0.08 * level(state, "AdvancedCapacity")
	s.WalkSpeed = BASE.WalkSpeed + level(state, "MoveSpeed")
	local rebirths = math.max(0, math.floor((state and state.Rebirths) or 0))
	local boosted = state and state.BoostUntil and now and now < state.BoostUntil
	s.ValueMult = (1 + 0.08 * level(state, "LootValue")) * (1 + 0.1 * perk(state, "GoldenTouch")) * (1 + UpgradeConfig.Rebirth.ValueBonus * rebirths) * (if boosted then 1.25 else 1)
	s.DepositMult = (1 + 0.05 * level(state, "DepositBonus")) * (if state and state.Vip then 1.1 else 1)
	s.Luck = math.min(2, 1 + 0.1 * level(state, "RareLuck"))
	return s
end

-- Capacity slots an item uses: big items shrink with Advanced Loot Capacity, never below 1.
function Economy.slotsFor(def, stats)
	if def.Slots <= 1 then
		return 1
	end
	return math.max(1, math.floor(def.Slots * (stats.LargeSlotFactor or 1) + 0.5))
end

-- Cash value of one picked-up item (fixed at pickup time).
function Economy.itemValue(def, stats)
	return math.max(1, math.floor(def.Value * (stats.ValueMult or 1) + 0.5))
end

function Economy.depositPayout(carriedValue, stats)
	if type(carriedValue) ~= "number" or carriedValue ~= carriedValue or carriedValue <= 0 then
		return 0
	end
	return math.floor(carriedValue * (stats.DepositMult or 1) + 0.5)
end

function Economy.upgradeCost(key, currentLevel)
	local def = UpgradeConfig.ByKey[key]
	if not def or currentLevel >= def.Max then
		return nil
	end
	return UpgradeConfig.cost(def, currentLevel)
end

function Economy.perkCost(key, currentLevel)
	local def = UpgradeConfig.PerkByKey[key]
	if not def or currentLevel >= def.Max then
		return nil
	end
	return def.Costs[currentLevel + 1]
end

local function fmt(v)
	if math.abs(v - math.floor(v)) < 1e-6 then
		return tostring(math.floor(v))
	end
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

-- What a level of an upgrade does, as card text: returns (now, next) strings.
function Economy.effectText(key, state)
	local current = Economy.stats(state)
	local nextState = { Upgrades = table.clone((state and state.Upgrades) or {}), Perks = state and state.Perks, Rebirths = state and state.Rebirths }
	nextState.Upgrades[key] = level(state, key) + 1
	local nxt = Economy.stats(nextState)
	local function pair(field, prefix, suffix, mult)
		mult = mult or 1
		return prefix .. fmt(current[field] * mult) .. suffix, prefix .. fmt(nxt[field] * mult) .. suffix
	end
	if key == "PickupSpeed" then
		return pair("PickupInterval", "", "s delay")
	elseif key == "CollectionRadius" then
		return pair("Radius", "", " stud reach")
	elseif key == "CashMagnet" then
		return (if current.MagnetRadius > 0 then fmt(current.MagnetRadius) .. " stud pull" else "Off"), fmt(nxt.MagnetRadius) .. " stud pull"
	elseif key == "AutoCollect" then
		return (if current.AutoRadius > 0 then fmt(current.AutoRadius) .. " studs" else "Off"), fmt(nxt.AutoRadius) .. " studs"
	elseif key == "CarryCapacity" or key == "StackSize" then
		return pair("Capacity", "", " slots")
	elseif key == "AdvancedCapacity" then
		return pair("LargeSlotFactor", "", "% large-item size", 100)
	elseif key == "MoveSpeed" then
		return pair("WalkSpeed", "", " speed")
	elseif key == "LootValue" then
		return pair("ValueMult", "x", " value")
	elseif key == "DepositBonus" then
		return pair("DepositMult", "x", " payout")
	elseif key == "RareLuck" then
		return pair("Luck", "x", " rare chance")
	end
	return "", ""
end

return Economy
