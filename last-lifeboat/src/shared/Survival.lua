--[[
	Survival - oxygen and downed / revive timers (pure, unit-tested).

	Oxygen is in seconds of breath. Underwater it drains 1 per second; above water it comes
	back at Oxygen.Regen per second. At 0 you are DOWNED: you float, can't move, and bleed
	out after Downed.BleedOut seconds unless a teammate holds E beside you for
	Downed.ReviveHold seconds (you come back with Oxygen.ReviveTo of your max).
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Survival = {}

local O = GameConfig.Oxygen
local D = GameConfig.Downed

function Survival.headUnderwater(headY, seaLevel)
	return headY < (seaLevel or GameConfig.World.SeaLevel) - O.HeadDepth
end

-- Returns the new oxygen and whether it just ran out.
function Survival.stepOxygen(oxygen, maxOxygen, underwater, dt)
	if underwater then
		local after = math.max(0, oxygen - dt)
		return after, oxygen > 0 and after <= 0
	end
	return math.min(maxOxygen, oxygen + O.Regen * dt), false
end

function Survival.zap(oxygen)
	return math.max(0, oxygen - O.ZapLoss)
end

function Survival.reviveOxygen(maxOxygen)
	return maxOxygen * O.ReviveTo
end

function Survival.bleedLeft(downedAt, now)
	return math.max(0, D.BleedOut - (now - downedAt))
end

function Survival.bledOut(downedAt, now)
	return now - downedAt >= D.BleedOut
end

function Survival.reviveProgress(startedAt, now)
	if not startedAt then
		return 0
	end
	return math.clamp((now - startedAt) / D.ReviveHold, 0, 1)
end

-- Life jacket: used if you have one and haven't used the per-round allowance.
function Survival.jacketAvailable(owned, usedThisRound)
	return (owned or 0) > 0 and (usedThisRound or 0) < D.LifeJacketsPerRound
end

-- How far up a downed body floats: to just above the water, but never through a ceiling.
-- `ceilingY` is the hit height straight above (nil = open sky).
function Survival.floatY(currentY, seaLevel, ceilingY)
	local target = math.max(currentY, (seaLevel or 0) + 0.5)
	if ceilingY then
		target = math.min(target, ceilingY - D.FloatClearance)
	end
	return math.max(currentY, target)
end

return Survival
