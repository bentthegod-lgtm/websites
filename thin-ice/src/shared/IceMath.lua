--[[
	IceMath - the pure numbers behind ice stress, stamina, warmth, movement speed and how
	loud things sound. Services call these every step; the unit tests check them directly.
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local IceMath = {}

local Ice = GameConfig.Ice
local Move = GameConfig.Move
local Stamina = GameConfig.Stamina
local Warmth = GameConfig.Warmth
local Noise = GameConfig.Noise

---------------------------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------------------------

-- The walk speed the server allows for a requested mode.
function IceMath.speed(mode, carrying, inWater)
	if inWater then
		return Move.WaterSpeed
	end
	local base = Move[mode] or Move.Walk
	if carrying then
		base *= Move.CarryMultiplier
	end
	return base
end

-- Largest flat distance a player may cover in dt before the server snaps them back.
function IceMath.maxStep(allowedSpeed, dt)
	return allowedSpeed * Move.Tolerance * dt + Move.Slack
end

---------------------------------------------------------------------------------------------
-- Stamina
---------------------------------------------------------------------------------------------

-- Returns stamina, exhausted, sinceSprint, and the mode actually allowed this step.
-- Sprinting needs stamina; at zero you are exhausted until stamina recovers to RecoverTo.
function IceMath.stepStamina(stamina, exhausted, sinceSprint, mode, moving, dt)
	local effective = mode
	if mode == "Sprint" and (exhausted or not moving) then
		effective = "Walk"
	end
	if effective == "Sprint" then
		stamina = math.max(0, stamina - Stamina.SprintDrain * dt)
		sinceSprint = 0
		if stamina <= 0 then
			exhausted = true
			effective = "Walk"
		end
	else
		sinceSprint += dt
		if sinceSprint >= Stamina.RegenDelay then
			stamina = math.min(Stamina.Max, stamina + Stamina.Regen * dt)
		end
		if exhausted and stamina >= Stamina.RecoverTo then
			exhausted = false
		end
	end
	return stamina, exhausted, sinceSprint, effective
end

---------------------------------------------------------------------------------------------
-- Warmth
---------------------------------------------------------------------------------------------

--[[
	ctx = { onShore, inWater, nearFire, gust, drainScale }
	The shore is safe (you slowly warm up); fires warm you quickly; the ice chills you
	slowly, the water fast, and blizzard gusts add to the chill out on the lake.
]]
function IceMath.stepWarmth(warmth, ctx, dt)
	local delta
	if ctx.inWater then
		delta = -Warmth.WaterDrain * (ctx.drainScale or 1)
	elseif ctx.nearFire then
		delta = Warmth.FireWarmth
	elseif ctx.onShore then
		delta = Warmth.ShoreRegen
	else
		delta = -Warmth.IceDrain * (ctx.drainScale or 1)
	end
	if ctx.gust and not ctx.onShore and not ctx.nearFire then
		delta -= Warmth.GustDrain
	end
	return math.clamp(warmth + delta * dt, 0, Warmth.Max)
end

---------------------------------------------------------------------------------------------
-- Ice stress
---------------------------------------------------------------------------------------------

function IceMath.strength(thick)
	return Ice.Strength[thick] or Ice.Strength[2]
end

-- Stress per second one player adds to the tile under them.
function IceMath.stressRate(mode, moving, carrying)
	local rate = if moving then (Ice.Stress[mode] or Ice.Stress.Walk) else Ice.Stress.Idle
	if carrying then
		rate += Ice.Stress.Carry
	end
	return rate
end

--[[
	Advances one tile's stress. `load` is the summed stress rate of everyone on it (0 when
	empty). Returns the new stress and an event: "crack" the moment it passes CrackAt,
	"break" when it reaches the tile's strength, or nil.
]]
function IceMath.stepStress(stress, thick, load, dt, alreadyCracked)
	local strength = IceMath.strength(thick)
	if load > 0 then
		stress += load * dt
	else
		stress = math.max(0, stress - Ice.Recover * dt)
	end
	if stress >= strength then
		return strength, "break"
	end
	if not alreadyCracked and stress >= strength * Ice.CrackAt then
		return stress, "crack"
	end
	return stress, nil
end

-- 0..1 how close a tile is to breaking (for its colour / crack decals).
function IceMath.damage(stress, thick)
	return math.clamp(stress / IceMath.strength(thick), 0, 1)
end

---------------------------------------------------------------------------------------------
-- Noise
---------------------------------------------------------------------------------------------

-- The footstep noise category for a gait (nil when standing still).
function IceMath.gait(mode, moving)
	if not moving then
		return nil
	end
	if mode == "Sneak" then
		return "StepSneak"
	elseif mode == "Sprint" then
		return "StepSprint"
	end
	return "StepWalk"
end

-- How loud a noise is to a listener `distance` away (0 = inaudible). Linear falloff to
-- the category radius, scaled by the listener's hearing (difficulty x weather).
function IceMath.perceived(category, distance, hearing)
	local def = Noise.Categories[category]
	if not def or distance ~= distance then
		return 0
	end
	if distance >= def.Radius then
		return 0
	end
	return def.Loudness * (1 - distance / def.Radius) * (hearing or 1)
end

return IceMath
