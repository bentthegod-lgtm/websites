--[[
	ParryJudge - pure, server-side decision of whether a parry press counts.

	The client sends the server-synchronised time at which the button was pressed. The
	server rewinds the ball's recorded path to that moment (bounded by MaxRewind, so a
	laggy or lying client cannot rewind far) and checks the distance against the parry
	range. Pressing while the ball is still too far away, or while it is not targeting you,
	is a whiff: it triggers the long cooldown, so spamming the button fails.
]]

local BallMath = require(script.Parent.BallMath)

local ParryJudge = {}

-- Returns how many seconds to rewind for a client timestamp (0 if missing/invalid).
function ParryJudge.rewindFor(clientTime, now, cfg)
	if type(clientTime) ~= "number" or clientTime ~= clientTime or clientTime == math.huge or clientTime == -math.huge then
		return 0
	end
	local delta = now - clientTime
	if delta < -cfg.FutureTolerance then
		return 0 -- timestamp from the future: ignore it
	end
	return math.clamp(delta, 0, cfg.MaxRewind)
end

-- Cooldown / rate-limit gate. `memo` is per contestant: { readyAt, lastPress }.
function ParryJudge.canAttempt(memo, now, cfg)
	if memo.lastPress and now - memo.lastPress < cfg.MinInterval then
		return false, "rate"
	end
	if memo.readyAt and now < memo.readyAt then
		return false, "cooldown"
	end
	return true
end

function ParryJudge.applyCooldown(memo, now, success, cfg)
	memo.lastPress = now
	memo.readyAt = now + (if success then cfg.SuccessCooldown else cfg.WhiffCooldown)
end

--[[
	args = {
		now: number, clientTime: number?, history, playerPos: Vector3,
		isTarget: boolean, speed: number, hitTime: number? (set while a hit is pending)
	}
	Returns { ok: boolean, reason: string, distance: number?, range: number?, rewind: number }
]]
function ParryJudge.judge(args, cfg)
	local rewind = ParryJudge.rewindFor(args.clientTime, args.now, cfg)
	if not args.isTarget then
		return { ok = false, reason = "not_target", rewind = rewind }
	end
	local t = args.now - rewind
	-- While a hit is pending, a press only counts if it happened before the hit.
	if args.hitTime and t > args.hitTime + cfg.FutureTolerance then
		return { ok = false, reason = "late", rewind = rewind }
	end
	local ballPos = BallMath.sample(args.history, t)
	if not ballPos then
		return { ok = false, reason = "no_ball", rewind = rewind }
	end
	local distance = (ballPos - args.playerPos).Magnitude
	local range = BallMath.parryRange(args.speed, cfg)
	if distance <= range then
		return { ok = true, reason = "parry", distance = distance, range = range, rewind = rewind }
	end
	return { ok = false, reason = "early", distance = distance, range = range, rewind = rewind }
end

return ParryJudge
