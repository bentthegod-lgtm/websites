--[[
	KartEffects - the ONLY way world events (and, from Stage 3, power-ups) touch a kart.
	A small, fixed set of effects, all survivable - nothing ever eliminates a racer:

	  spinOut { duration }          spin, lose some speed, no steering for a moment
	  slow { mul, duration }        lower top speed for a while
	  launch { up, spin }           popped into the air
	  freeze { duration }           an ice cube: coast to a stop, then carry on
	  knockback { impulse }         shoved (capped at 80 studs/s)
	  respawnToCheckpoint {}        put back at the last checkpoint (ghosted)

	Bots: applied to their server state. Players: sent to the owning client
	(KartEffect remote), which applies it to its own predicted kart; the anti-cheat allows
	extra speed for a short window afterwards. Ghosted karts (just respawned) are immune,
	and the same kind can't hit the same kart twice within PerKindCooldown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)

local KartEffects = {}

local services
local recent = {} -- [racerId] = { [kind] = time }
KartEffects.log = {}

local function now()
	return workspace:GetServerTimeNow()
end

function KartEffects.init(registry)
	services = registry
end

local function sanitize(kind, params)
	params = if type(params) == "table" then params else {}
	local out = {}
	if kind == "knockback" then
		local v = params.impulse
		if typeof(v) ~= "Vector3" then
			return nil
		end
		if v.Magnitude > 80 then
			v = v.Unit * 80
		end
		out.impulse = v
	elseif kind == "launch" then
		out.up = math.clamp(tonumber(params.up) or 45, 0, 90)
		out.spin = math.clamp(tonumber(params.spin) or 0.6, 0, 2)
	elseif kind == "spinOut" or kind == "freeze" then
		out.duration = math.clamp(tonumber(params.duration) or 1.2, 0.2, 3)
	elseif kind == "slow" then
		out.mul = math.clamp(tonumber(params.mul) or 0.6, 0.3, 1)
		out.duration = math.clamp(tonumber(params.duration) or 2.5, 0.2, 6)
	end
	return out
end

-- Applies an effect to a racer. Returns true if it landed.
function KartEffects.apply(racer, kind, params, source)
	if not table.find(GameConfig.Effects.Allowed, kind) then
		return false
	end
	if not racer or racer.left or racer.progress.finished then
		return false
	end
	local t = now()
	if t < (racer.ghostUntil or 0) then
		return false
	end
	recent[racer.id] = recent[racer.id] or {}
	local last = recent[racer.id][kind]
	if last and t - last < GameConfig.Effects.PerKindCooldown then
		return false
	end
	if kind == "respawnToCheckpoint" then
		recent[racer.id][kind] = t
		return services.RaceService.respawn(racer, "event")
	end
	local clean = sanitize(kind, params)
	if not clean then
		return false
	end
	recent[racer.id][kind] = t
	racer.effectUntil = t + GameConfig.Effects.SpeedSlackTime
	table.insert(KartEffects.log, { racer = racer.id, kind = kind, source = source, at = t })
	if #KartEffects.log > 200 then
		table.remove(KartEffects.log, 1)
	end
	if racer.kind == "bot" then
		return services.BotService.applyEffect(racer, kind, clean) == true
	end
	if racer.player and racer.player.Parent then
		services.Remotes.KartEffect:FireClient(racer.player, kind, clean, source)
		return true
	end
	return false
end

function KartEffects.reset()
	recent = {}
end

return KartEffects
