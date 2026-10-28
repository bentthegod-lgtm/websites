--[[
	Economy - pure maths shared by server and client (the client only uses it to DISPLAY
	prices and stats; the server recomputes everything itself).

	* cost(key, level): coins to go from `level` to `level + 1`.
	* stats(profile): every gameplay value derived from upgrade levels and prestige.
	* launch(machine, stats, request, padYaw, rng): the validated launch velocity. The
	  request's power / angle / aim / spin are clamped to what the player has unlocked.
	* reach(machine, stats): rough maximum distance (used to pick a fair featured objective).
]]

local MachineConfig = require(script.Parent.Config.MachineConfig)
local UpgradeConfig = require(script.Parent.Config.UpgradeConfig)
local ScoringConfig = require(script.Parent.Config.ScoringConfig)

local Economy = {}

local GRAVITY = 196.2
Economy.Gravity = GRAVITY
Economy.MaxAim = 12 -- degrees left / right players can nudge the aim

function Economy.level(profile, key)
	local upgrades = profile and profile.Upgrades
	return (upgrades and upgrades[key]) or 0
end

function Economy.cost(key, level)
	local def = UpgradeConfig.ByKey[key]
	if not def or level >= def.Max then
		return nil
	end
	return math.floor(def.Base * def.Growth ^ level)
end

function Economy.stats(profile)
	local L = function(key)
		return Economy.level(profile, key)
	end
	local credits = (profile and profile.Prestige and profile.Prestige.Credits) or 0
	local angle = UpgradeConfig.AngleRanges[math.clamp(L("Angles"), 0, 3)]
	local spinModes = {}
	for _, mode in ipairs(MachineConfig.SpinModes) do
		if L("Spin") >= mode.Level then
			table.insert(spinModes, mode.Id)
		end
	end
	return {
		SpeedMultiplier = 1 + 0.07 * L("Power"),
		Dummy = MachineConfig.Dummies[math.clamp(L("Payload"), 0, #MachineConfig.Dummies - 1) + 1],
		CooldownReduction = L("Cooldown"),
		AngleMin = angle[1],
		AngleMax = angle[2],
		AngleStep = angle[3],
		ChargeMultiplier = 1 - 0.1 * L("Precision"), -- down to 50%
		SpreadDegrees = 3 * (1 - L("Precision") / 5), -- 3 deg random spread -> none
		ImpactCap = ScoringConfig.Impact.BaseCap + ScoringConfig.Impact.CapPerLevel * L("Durability"),
		ImpactMultiplier = 1 + ScoringConfig.Impact.DurabilityBonus * L("Durability"),
		SpinModes = spinModes,
		BonusMultiplier = 1 + ScoringConfig.BonusPerLevel * L("Bonus"),
		FeaturedMultiplier = ScoringConfig.FeaturedMultiplier[math.clamp(L("Challenge"), 0, 3)],
		CoinMultiplier = (1 + ScoringConfig.AnalystPerLevel * L("Analyst")) * (1 + math.min(ScoringConfig.MaxCreditBonus, ScoringConfig.CreditBonus * credits)),
	}
end

function Economy.cooldown(machine, stats)
	return math.max(2, machine.Cooldown - stats.CooldownReduction)
end

function Economy.chargeTime(machine, stats)
	return machine.ChargeTime * stats.ChargeMultiplier
end

function Economy.speed(machine, stats, power)
	return math.min(ScoringConfig.MaxLaunchSpeed, machine.BaseSpeed * stats.SpeedMultiplier * power)
end

local function snap(v, min, max, step)
	v = math.clamp(v, min, max)
	if step and step > 0 then
		v = min + math.floor((v - min) / step + 0.5) * step
	end
	return math.clamp(v, min, max)
end

local function finite(v, default)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

-- Clamps a client request to legal values. Returns a sanitised copy.
function Economy.sanitise(machine, stats, request)
	request = if type(request) == "table" then request else {}
	local power = snap(finite(request.Power, 1), machine.MinPower, 1, 0.05)
	local angle = snap(finite(request.Angle, 45), stats.AngleMin, stats.AngleMax, stats.AngleStep)
	local aim = snap(finite(request.Aim, 0), -Economy.MaxAim, Economy.MaxAim, 2)
	local spin = if type(request.Spin) == "string" and table.find(stats.SpinModes, request.Spin) then request.Spin else "None"
	return { Power = power, Angle = angle, Aim = aim, Spin = spin }
end

-- Launch direction and spin. `padYaw` (radians) is the pad's base heading (toward the
-- course centre line); `rng` adds the precision spread. Pure: returns vectors.
function Economy.launch(machine, stats, request, padYaw, rng)
	local r = Economy.sanitise(machine, stats, request)
	local elevation = math.clamp(r.Angle + machine.AngleOffset, 8, 82)
	local yaw = padYaw + math.rad(r.Aim)
	if rng and stats.SpreadDegrees > 0 then
		elevation += rng:NextNumber(-stats.SpreadDegrees, stats.SpreadDegrees)
		yaw += math.rad(rng:NextNumber(-stats.SpreadDegrees, stats.SpreadDegrees) * 0.5)
	end
	local e = math.rad(elevation)
	-- Yaw 0 = straight down +Z.
	local horizontal = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local direction = (horizontal * math.cos(e) + Vector3.new(0, math.sin(e), 0)).Unit
	local speed = Economy.speed(machine, stats, r.Power)
	local spinMode = MachineConfig.SpinById[r.Spin]
	local spin = machine.Spin + (if spinMode then spinMode.Spin else Vector3.zero)
	return {
		Direction = direction,
		Speed = speed,
		Velocity = direction * speed,
		Spin = spin,
		Elevation = elevation,
		Request = r,
	}
end

-- Rough best-case reach in studs (ballistic range at the best allowed angle + slide).
function Economy.reach(machine, stats)
	local v = Economy.speed(machine, stats, 1)
	local best = 0
	local a = stats.AngleMin
	while a <= stats.AngleMax + 1e-6 do
		local e = math.rad(math.clamp(a + machine.AngleOffset, 8, 82))
		best = math.max(best, v * v * math.sin(2 * e) / GRAVITY)
		a += math.max(1, stats.AngleStep)
	end
	return best * 1.2
end

-- Requirement check for machines / facilities. `values` maps stat names to numbers.
function Economy.meets(requirement, values)
	if not requirement then
		return true
	end
	if (values[requirement.Stat] or 0) < requirement.Value then
		return false
	end
	if requirement.AndStat and (values[requirement.AndStat] or 0) < requirement.AndValue then
		return false
	end
	return true
end

return Economy
