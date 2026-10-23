--[[
	SoundMath - pure helpers for noise propagation. Used by NoiseService and the tests.
]]

local SoundMath = {}

-- 1 at the source, 0 at (radius * hearingMultiplier), smooth curve in between.
function SoundMath.falloff(distance, radius, hearingMultiplier)
	local reach = radius * (hearingMultiplier or 1)
	if reach <= 0 or distance >= reach then
		return 0
	end
	local t = 1 - distance / reach
	return t ^ 1.5
end

-- Remaining fraction of loudness after passing through obstacles.
function SoundMath.occlusion(wallHits, doorHits, propHits, cfg)
	local factor = (cfg.Wall ^ wallHits) * (cfg.Door ^ doorHits) * (cfg.Prop ^ (propHits or 0))
	return math.max(factor, cfg.MinFactor)
end

function SoundMath.perceived(loudness, radius, distance, occlusionFactor, hearingMultiplier)
	return loudness * SoundMath.falloff(distance, radius, hearingMultiplier) * (occlusionFactor or 1)
end

-- How far (studs) the listener's estimate of the source position may be off.
function SoundMath.uncertainty(distance, occlusionFactor, cfg)
	local muffled = 2 - math.clamp(occlusionFactor or 1, 0, 1)
	return math.min(distance * cfg.Uncertainty * muffled, cfg.MaxJitter)
end

-- Exponential decay helper for patrol heat.
function SoundMath.decay(value, elapsed, halfLife)
	if halfLife <= 0 then
		return 0
	end
	return value * 0.5 ^ (elapsed / halfLife)
end

-- Classifies horizontal speed into a gait for footstep noise.
function SoundMath.gait(speed, playerConfig)
	if speed < 0.6 then
		return nil
	elseif speed <= playerConfig.CrouchSpeed + 1.2 then
		return "Crouch"
	elseif speed <= playerConfig.WalkSpeed + 2 then
		return "Walk"
	end
	return "Sprint"
end

return SoundMath
