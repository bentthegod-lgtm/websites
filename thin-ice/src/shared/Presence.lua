--[[
	Presence - the pure maths behind how the Antlered makes itself felt on each client
	(unit-tested; AudioController / EffectsController / LightingController use it).

	By distance to it (flat studs):
	  > FarCall         now and then a distant call echoes across the lake
	  < Near            its breathing and the crunch of its steps
	  < Heartbeat       your heartbeat and frost creeping in at the screen edges
	  Silhouette band   now and then its outline shows through the fog
	Hunting YOU        a chase music layer on top
	Fog                thicker the further out you are (and a hard whiteout in blizzards)
	Ambient scares     small client-only scares (never in a round's first minute)
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Presence = {}

local P = GameConfig.Presence
local L = GameConfig.Lake

Presence.ScareKinds = { "IceGroan", "DistantScream", "Footprints", "UnderIceShadow" }

local function valid(d)
	return type(d) == "number" and d == d and d ~= math.huge
end

-- Which cues are on at this distance. (state = the monster's brain state attribute.)
function Presence.cues(distance, state, huntingMe)
	local awake = state ~= nil and state ~= "Dormant"
	local out = { call = false, breath = false, steps = false, heartbeat = false, vignette = 0, chase = false, silhouette = false }
	if not awake or not valid(distance) then
		return out
	end
	out.call = distance > P.FarCall
	out.breath = distance <= P.Near
	out.steps = distance <= P.Near and state ~= "Listen" and state ~= "Recover"
	out.heartbeat = distance <= P.Heartbeat
	out.vignette = Presence.vignette(distance)
	out.chase = huntingMe == true and state == "Hunt"
	out.silhouette = distance >= P.SilhouetteMin and distance <= P.SilhouetteMax
	return out
end

-- 0 at the heartbeat range, 1 when it's right on top of you.
function Presence.vignette(distance)
	if not valid(distance) then
		return 0
	end
	return math.clamp((P.Heartbeat - distance) / (P.Heartbeat - 6), 0, 1)
end

-- Heartbeat rate (playback speed) - faster as it closes in.
function Presence.heartRate(distance)
	return 0.85 + Presence.vignette(distance) * 0.75
end

-- Atmosphere density by how far out on the lake you are; whiteouts close it right in.
function Presence.fog(z, whiteout, reduced)
	local lakeLen = L.RowsPerZone * #GameConfig.Zones * L.TileSize
	local t = if type(z) == "number" and z == z then math.clamp((z - L.ShoreZ) / lakeLen, 0, 1) else 0
	local density = L.FogNear + (L.FogFar - L.FogNear) * t
	if whiteout then
		density = math.max(density, 0.82)
	end
	if reduced then
		density = math.min(density, 0.45)
	end
	return density
end

-- Can an ambient scare play now? (in a round, past the grace minute, gap elapsed)
function Presence.scareAllowed(now, roundStart, lastScare)
	if not roundStart or now - roundStart < P.ScareGraceTime then
		return false
	end
	return lastScare == nil or now - lastScare >= P.ScareGapMin
end

-- Next scare time after `now` (rng: Random-like).
function Presence.nextScareAt(now, rng)
	return now + P.ScareGapMin + (if rng then rng:NextNumber() else 0.5) * (P.ScareGapMax - P.ScareGapMin)
end

-- Picks a scare, never the same one twice in a row.
function Presence.pickScare(rng, last)
	for _ = 1, 8 do
		local kind = Presence.ScareKinds[(if rng then rng:NextInteger(1, #Presence.ScareKinds) else 1)]
		if kind ~= last then
			return kind
		end
	end
	return Presence.ScareKinds[1] == last and Presence.ScareKinds[2] or Presence.ScareKinds[1]
end

-- Next distant-call time.
function Presence.nextCallAt(now, rng)
	return now + P.CallGapMin + (if rng then rng:NextNumber() else 0.5) * (P.CallGapMax - P.CallGapMin)
end

--[[
	The head's slow idle: a creepy tilt (roll) and a little nodding (pitch), both in radians.
	Listening: it freezes, cocks its head hard to one side and lifts its snout.
]]
function Presence.headPose(t, state)
	if state == "Listen" or state == "Recover" then
		return math.rad(28) + math.sin(t * 0.7) * math.rad(3), math.rad(-14)
	elseif state == "Hunt" then
		return math.sin(t * 6) * math.rad(4), math.rad(6)
	end
	return math.sin(t * 0.55) * math.rad(14), math.sin(t * 0.31) * math.rad(6)
end

return Presence
