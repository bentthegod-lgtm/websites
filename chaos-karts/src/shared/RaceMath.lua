--[[
	RaceMath - laps, checkpoints and positions (pure, unit-tested; the server runs it).

	Checkpoint gates are ordered (1 = the start / finish line). A racer must cross them IN
	ORDER: only the next expected gate counts, crossing any other gate (a skip, a cut, a
	reverse lap) is ignored and counted as a skip. Crossing gate 1 after every other gate
	completes a lap.

	racer progress: { lap = 0 (not started) .. totalLaps + 1 (finished), nextCp, lapStart,
	                  lapTimes = {}, best, skips, finished, finishTime }
]]

local RaceMath = {}

function RaceMath.newProgress()
	return { lap = 0, nextCp = 1, lapStart = nil, lapTimes = {}, best = nil, skips = 0, finished = false, finishTime = nil, wrongT = 0 }
end

--[[
	Did the move from -> to cross `gate` forwards? gate = { cframe, halfWidth }.
	Returns true and the crossing point.
]]
function RaceMath.crossed(gate, from, to)
	local cf = gate.cframe
	local origin = cf.Position
	local look = cf.LookVector
	local a = (from - origin):Dot(look)
	local b = (to - origin):Dot(look)
	if not (a < 0 and b >= 0) then
		return false
	end
	local t = -a / (b - a)
	local p = from + (to - from) * t
	local rel = p - origin
	if math.abs(rel:Dot(cf.RightVector)) > gate.halfWidth then
		return false
	end
	if math.abs(rel:Dot(cf.UpVector)) > (gate.height or 24) then
		return false
	end
	return true, p
end

-- Crossed backwards (to warn about a reverse crossing; never counts).
function RaceMath.crossedBackwards(gate, from, to)
	local reversed = { cframe = gate.cframe * CFrame.Angles(0, math.pi, 0), halfWidth = gate.halfWidth, height = gate.height }
	return RaceMath.crossed(reversed, from, to)
end

--[[
	Feeds one movement segment. Returns an event string or nil:
	  "start"      crossed the line for the first time (lap 1 begins)
	  "checkpoint" the next gate
	  "lap"        a lap completed (lapTime returned as the second value)
	  "finish"     the final lap completed
	  "skip"       crossed a gate out of order (ignored)
]]
function RaceMath.feed(progress, gates, from, to, now, totalLaps)
	if progress.finished then
		return nil
	end
	for k, gate in ipairs(gates) do
		if RaceMath.crossed(gate, from, to) then
			if k ~= progress.nextCp then
				progress.skips += 1
				return "skip"
			end
			if k == 1 then
				if progress.lap == 0 then
					progress.lap = 1
					progress.lapStart = now
					progress.nextCp = if #gates > 1 then 2 else 1
					return "start"
				end
				local lapTime = now - (progress.lapStart or now)
				table.insert(progress.lapTimes, lapTime)
				if not progress.best or lapTime < progress.best then
					progress.best = lapTime
				end
				progress.lap += 1
				progress.lapStart = now
				progress.nextCp = if #gates > 1 then 2 else 1
				if progress.lap > totalLaps then
					progress.finished = true
					progress.finishTime = now
					return "finish", lapTime
				end
				return "lap", lapTime
			end
			progress.nextCp = if k == #gates then 1 else k + 1
			return "checkpoint"
		end
	end
	return nil
end

-- How many gates this racer has passed in total (the main ranking key after laps).
function RaceMath.gatesPassed(progress, gateCount)
	if progress.lap == 0 then
		return 0
	end
	local inLap = if progress.nextCp == 1 then gateCount else progress.nextCp - 1
	return (progress.lap - 1) * gateCount + inLap
end

-- Distance along the track from `dist` to the next gate.
function RaceMath.toNext(progress, gates, dist, length)
	local target = gates[progress.nextCp].dist
	return (target - dist) % length
end

--[[
	Sorts racers into positions. Each entry: { progress, dist (along the main track),
	joinOrder }. Finished racers first (by finish time), then most gates passed, then the
	smallest distance to the next gate, then grid order. Returns the sorted list and sets
	entry.place.
]]
function RaceMath.rank(entries, gates, length)
	local n = #gates
	for _, e in ipairs(entries) do
		e._gates = RaceMath.gatesPassed(e.progress, n)
		e._toNext = RaceMath.toNext(e.progress, gates, e.dist or 0, length)
	end
	table.sort(entries, function(a, b)
		local pa, pb = a.progress, b.progress
		if pa.finished ~= pb.finished then
			return pa.finished
		end
		if pa.finished then
			if pa.finishTime ~= pb.finishTime then
				return pa.finishTime < pb.finishTime
			end
			return (a.joinOrder or 0) < (b.joinOrder or 0)
		end
		if a.dnf ~= b.dnf then
			return not a.dnf
		end
		if a._gates ~= b._gates then
			return a._gates > b._gates
		end
		if math.abs(a._toNext - b._toNext) > 1e-6 then
			return a._toNext < b._toNext
		end
		return (a.joinOrder or 0) < (b.joinOrder or 0)
	end)
	for i, e in ipairs(entries) do
		e.place = i
	end
	return entries
end

-- Facing / moving against the track direction?
function RaceMath.wrongWay(velocity, flat, minSpeed)
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	if planar.Magnitude < (minSpeed or 14) then
		return false
	end
	return planar.Unit:Dot(flat) < -0.35
end

--[[
	Rewards for a finishing place (GameConfig.Rewards). Places are 1-based; `field` is the
	number of racers (bots included). DNF gets the participation reward.
]]
function RaceMath.reward(rewards, place, field, dnf)
	if dnf or not place then
		return rewards.Participation, rewards.ParticipationXP
	end
	local coins = rewards.Places[place] or rewards.Participation
	local xp = rewards.XPBase + math.max(0, field - place) * rewards.XPPerBeaten
	if place == 1 then
		xp += rewards.WinXP
	end
	return coins, xp
end

return RaceMath
