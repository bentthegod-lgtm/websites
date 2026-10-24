--[[
	Timer logic (pure, unit tested): base lock, daily streak, event schedule, Lucky Hour.
	All times are plain numbers (seconds) passed in by the caller.
]]

local Timers = {}

---------------------------------------------------------------------------------------------
-- Base lock: { lockedUntil = number, cooldownUntil = number }
---------------------------------------------------------------------------------------------

function Timers.newLock()
	return { lockedUntil = 0, cooldownUntil = 0 }
end

-- Returns "Locked" | "Cooldown" | "Ready", secondsRemaining
function Timers.lockStatus(lock, now)
	if now < lock.lockedUntil then
		return "Locked", lock.lockedUntil - now
	elseif now < lock.cooldownUntil then
		return "Cooldown", lock.cooldownUntil - now
	end
	return "Ready", 0
end

-- paid = the Lock Base Now product: skips the cooldown, but never while locked and never
-- right after a lock ended (the base always opens for MinGapAfterPaid seconds).
function Timers.tryLock(lock, now, lockCfg, paid)
	local status = Timers.lockStatus(lock, now)
	if status == "Locked" then
		return false, "Already locked"
	end
	if status == "Cooldown" then
		if not paid then
			return false, "Cooldown"
		end
		if lock.lockedUntil > 0 and now - lock.lockedUntil < lockCfg.MinGapAfterPaid then
			return false, "Too soon"
		end
	end
	lock.lockedUntil = now + lockCfg.Duration
	lock.cooldownUntil = lock.lockedUntil + lockCfg.Cooldown
	return true
end

-- Can the paid product be used right now? (checked before prompting the purchase)
function Timers.canPaidLock(lock, now, lockCfg)
	local status = Timers.lockStatus(lock, now)
	if status == "Locked" then
		return false
	end
	return lock.lockedUntil <= 0 or now - lock.lockedUntil >= lockCfg.MinGapAfterPaid
end

---------------------------------------------------------------------------------------------
-- Daily streak. day = floor(unixTime / 86400). daily = { LastDay, Streak }
---------------------------------------------------------------------------------------------

function Timers.dayIndex(unixTime)
	return math.floor(unixTime / 86400)
end

-- Returns canClaim, streakIfClaimed, rewardIndex (1..cycleLength)
function Timers.dailyStatus(daily, today, cycleLength)
	local last = daily.LastDay or 0
	local streak = daily.Streak or 0
	if last == today then
		return false, streak, ((math.max(streak, 1) - 1) % cycleLength) + 1
	end
	local nextStreak = if last == today - 1 then streak + 1 else 1
	return true, nextStreak, ((nextStreak - 1) % cycleLength) + 1
end

function Timers.secondsUntilNextDay(unixTime)
	return 86400 - (unixTime % 86400)
end

---------------------------------------------------------------------------------------------
-- Admin event schedule, from seconds since the server started.
-- Returns { active, cycle, remaining, nextIn }
---------------------------------------------------------------------------------------------

function Timers.adminPhase(elapsed, eventsCfg)
	local t = elapsed - eventsCfg.FirstAdminDelay
	if t < 0 then
		return { active = false, cycle = -1, remaining = 0, nextIn = -t }
	end
	local cycle = math.floor(t / eventsCfg.AdminInterval)
	local into = t - cycle * eventsCfg.AdminInterval
	if into < eventsCfg.AdminDuration then
		return { active = true, cycle = cycle, remaining = eventsCfg.AdminDuration - into, nextIn = eventsCfg.AdminInterval - into }
	end
	return { active = false, cycle = cycle, remaining = 0, nextIn = eventsCfg.AdminInterval - into }
end

-- Lucky Hour: the first `minutes` of every UTC hour. Returns active, secondsRemainingOrUntil
function Timers.luckyHour(unixTime, minutes)
	local into = unixTime % 3600
	local length = minutes * 60
	if into < length then
		return true, length - into
	end
	return false, 3600 - into
end

-- Adds server luck time, capped. Returns the new "until" time.
function Timers.extendUntil(currentUntil, now, seconds, cap)
	local base = math.max(currentUntil, now)
	return math.min(base + seconds, now + cap)
end

return Timers
