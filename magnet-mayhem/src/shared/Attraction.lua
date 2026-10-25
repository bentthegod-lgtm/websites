--[[
	Attraction - pure maths for the magnet pull, shared by the server (timing, validation)
	and the client (the flight animation). No Roblox APIs, so it is unit-tested.

	Timeline of one pulled object:
	  [0, anticipation)        wind-up: it vibrates and lifts a little (longer for heavy ones)
	  [anticipation, total)    flight: accelerates toward the player along an arc, spinning
	  total                    joins the pile; the server awards it at this moment
]]

local ScrapConfig = require(script.Parent.Config.ScrapConfig)
local MagnetConfig = require(script.Parent.Config.MagnetConfig)

local Attraction = {}

local ANTICIPATION = { Light = 0.08, Medium = 0.28, Heavy = 0.65 }

-- Can this magnet pull this object at all?
function Attraction.canPull(def, stats)
	if stats.MagnetStrength + 1e-6 < def.MinStrength then
		return false, "TooHeavy"
	end
	return true
end

function Attraction.anticipation(def, stats)
	local class = ScrapConfig.weightClass(def)
	local t = ANTICIPATION[class]
	if class == "Heavy" then
		-- Heavy-Lift Clamps shorten the wind-up, but a heavy object never winds up faster
		-- than a medium one (it should always feel heavier).
		t = math.max(ANTICIPATION.Medium + 0.06, t * math.max(0.35, 1 - (stats.HeavyObjectCapability - 1) * 0.13))
	end
	if def.Rarity == "Legendary" then
		t += 0.35
	end
	return t
end

-- Flight speed in studs/second: light objects zip, heavy ones are dragged; spare
-- strength above the requirement speeds heavy objects up.
function Attraction.speed(def, stats)
	local massFactor = math.clamp(1.45 - def.Mass / 36, 0.32, 1.45)
	local spare = math.max(0, stats.MagnetStrength - def.MinStrength)
	local strengthFactor = math.min(1.7, 1 + spare * 0.05)
	return MagnetConfig.Base.FlightSpeed * stats.AttractionSpeed * massFactor * strengthFactor
end

-- Total seconds from claim to award.
function Attraction.duration(def, distance, stats)
	local flight = math.max(0.18, distance / Attraction.speed(def, stats))
	return math.min(3.4, Attraction.anticipation(def, stats) + flight)
end

--[[
	Flight curve. `u` is flight progress 0..1 (after anticipation). Returns
	(along, lift, spin): along = 0..1 share of the straight path covered (accelerating),
	lift = extra height in studs from the arc, spin = radians of rotation so far.
]]
function Attraction.curve(u, distance, def)
	u = math.clamp(u, 0, 1)
	local along = u * u * (3 - 2 * u) * 0.35 + u * u * 0.65 -- accelerate in, no overshoot
	local arc = math.clamp(distance * 0.18, 0.6, 5)
	local lift = math.sin(u * math.pi) * arc
	local weight = ScrapConfig.weightClass(def)
	local spinRate = if weight == "Light" then 9 elseif weight == "Medium" then 5 else 2.2
	return along, lift, u * spinRate
end

-- Wind-up shake amplitude (studs) and lift (studs) at time t inside the anticipation.
function Attraction.windup(t, anticipation, def)
	if anticipation <= 0 then
		return 0, 0
	end
	local k = math.clamp(t / anticipation, 0, 1)
	local weight = ScrapConfig.weightClass(def)
	local amp = if weight == "Heavy" then 0.18 elseif weight == "Medium" then 0.1 else 0.05
	return amp * (0.5 + k), k * (if weight == "Heavy" then 1.2 else 0.6)
end

return Attraction
