--[[
	Grades - the results screen's grade stamp and "vs last run" delta. Pure, so the server
	can put the grade in the results it sends and the tests can pin the thresholds.

	grade(score, previousBest): judged against YOUR personal best before this run:
	  S  new personal best (or within 2% of it)
	  A  >= 75% of your best
	  B  >= 50%
	  C  >= 25%
	  D  below that
	A first ever run (no previous best) is an S - it is a record by definition.

	delta(score, lastScore): percentage change versus your previous run, rounded to a
	whole percent; nil when there is no previous run to compare with.
]]

local Grades = {}

Grades.Order = { "S", "A", "B", "C", "D" }
Grades.Colors = {
	S = { 255, 200, 40 },
	A = { 92, 210, 110 },
	B = { 110, 170, 255 },
	C = { 200, 200, 210 },
	D = { 235, 120, 90 },
}

function Grades.grade(score, previousBest)
	score = tonumber(score) or 0
	previousBest = tonumber(previousBest) or 0
	if previousBest <= 0 or score >= previousBest * 0.98 then
		return "S"
	end
	local ratio = score / previousBest
	if ratio >= 0.75 then
		return "A"
	elseif ratio >= 0.5 then
		return "B"
	elseif ratio >= 0.25 then
		return "C"
	end
	return "D"
end

function Grades.delta(score, lastScore)
	score = tonumber(score)
	lastScore = tonumber(lastScore)
	if not score or not lastScore or lastScore <= 0 then
		return nil
	end
	local pct = (score - lastScore) / lastScore * 100
	return if pct >= 0 then math.floor(pct + 0.5) else -math.floor(-pct + 0.5)
end

function Grades.deltaText(delta)
	if delta == nil then
		return "First run - no comparison yet"
	end
	if delta == 0 then
		return "Same as last run"
	end
	return string.format("%s%d%% vs last run", if delta > 0 then "+" else "", delta)
end

return Grades
