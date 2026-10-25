--[[
	Lesson - builds the phase schedule of one class period (pure, seeded).

	A class always opens with the teacher writing on the board, has a Pop Quiz around the
	middle, at least TeacherConfig.MinWalks walks along the rows, and at most one random
	event. FireDrill and LunchBell replace the phase they land in; Principal is an overlay
	(a second, strict observer) on whatever phase is running.

	Lesson.build(cfg, duration, rng, eventName) -> {
		phases = { { phase, start, duration } ... },   -- contiguous, covers [0, duration]
		event = { name, start, duration } or nil,
	}
]]

local Lesson = {}

local NORMAL = { "Board", "Lecture", "Walk" }
local WEIGHTS = { Board = 1, Lecture = 1.1, Walk = 1 }

local function pickNormal(rng, last)
	local total = 0
	for _, phase in ipairs(NORMAL) do
		if phase ~= last then
			total += WEIGHTS[phase]
		end
	end
	local roll = rng:next() * total
	for _, phase in ipairs(NORMAL) do
		if phase ~= last then
			roll -= WEIGHTS[phase]
			if roll < 0 then
				return phase
			end
		end
	end
	return "Lecture"
end

-- Picks a random event key (weighted, in EventOrder so the result is seed-stable).
function Lesson.rollEvent(cfg, rng, exclude)
	local total = 0
	for _, key in ipairs(cfg.EventOrder) do
		if not (exclude and exclude[key]) then
			total += cfg.Events[key].Weight
		end
	end
	local roll = rng:next() * total
	for _, key in ipairs(cfg.EventOrder) do
		if not (exclude and exclude[key]) then
			roll -= cfg.Events[key].Weight
			if roll < 0 then
				return key
			end
		end
	end
	return "None"
end

function Lesson.build(cfg, duration, rng, eventName)
	local specials = {}
	local quizAt = math.floor(duration * rng:range(cfg.QuizWindow[1], cfg.QuizWindow[2]))
	table.insert(specials, { phase = "Quiz", at = quizAt, duration = cfg.Phases.Quiz.Duration[1] })
	local event
	local eventDef = eventName and cfg.Events[eventName]
	if eventDef and eventDef.Window then
		local at = math.floor(duration * rng:range(eventDef.Window[1], eventDef.Window[2]))
		-- Keep events clear of the quiz.
		if math.abs(at - quizAt) < 22 then
			at = if at < quizAt then math.max(24, quizAt - 24) else math.min(duration - 20, quizAt + 22)
		end
		if eventName == "FireDrill" then
			table.insert(specials, { phase = "FireDrill", at = at, duration = cfg.Phases.FireDrill.Duration[1] })
			event = { name = eventName, start = at, duration = cfg.Phases.FireDrill.Duration[1] }
		elseif eventName == "LunchBell" then
			table.insert(specials, { phase = "LunchCheck", at = at, duration = cfg.Phases.LunchCheck.Duration[1] })
			event = { name = eventName, start = at, duration = cfg.Phases.LunchCheck.Duration[1] }
		elseif eventName == "Principal" then
			event = { name = eventName, start = at, duration = eventDef.Seconds }
		end
	elseif eventDef and eventName ~= "None" then
		event = { name = eventName, start = 0, duration = duration } -- Substitute: whole class
	end
	table.sort(specials, function(a, b)
		return a.at < b.at
	end)

	local phases = {}
	local cursor = 0
	local function push(phase, length)
		length = math.min(length, duration - cursor)
		if length <= 0 then
			return
		end
		table.insert(phases, { phase = phase, start = cursor, duration = length })
		cursor += length
	end

	push(cfg.FirstPhase, cfg.FirstPhaseSeconds)
	local last = cfg.FirstPhase
	local nextSpecial = 1
	while cursor < duration - 0.01 do
		local special = specials[nextSpecial]
		if special and cursor >= special.at - 0.01 then
			push(special.phase, special.duration)
			last = special.phase
			nextSpecial += 1
		else
			local phase = pickNormal(rng, last)
			local range = cfg.Phases[phase].Duration
			local length = math.floor(rng:range(range[1], range[2]))
			if special and cursor + length > special.at then
				length = special.at - cursor
				if length < 6 and #phases > 0 then
					-- Too short to be a phase: stretch the previous one up to the special.
					phases[#phases].duration += length
					cursor += length
					length = 0
				end
			end
			if length > 0 then
				push(phase, length)
				last = phase
			end
		end
	end

	-- Guarantee enough walks (the tensest part of class).
	local walks = 0
	for _, p in ipairs(phases) do
		if p.phase == "Walk" then
			walks += 1
		end
	end
	for i = #phases, 2, -1 do
		if walks >= cfg.MinWalks then
			break
		end
		local p = phases[i]
		local prev, nxt = phases[i - 1], phases[i + 1]
		if (p.phase == "Lecture" or p.phase == "Board") and prev.phase ~= "Walk" and (not nxt or nxt.phase ~= "Walk") then
			p.phase = "Walk"
			walks += 1
		end
	end

	return { phases = phases, event = event, duration = duration }
end

function Lesson.phaseAt(lesson, t)
	for i, p in ipairs(lesson.phases) do
		if t < p.start + p.duration then
			return p, i
		end
	end
	return lesson.phases[#lesson.phases], #lesson.phases
end

function Lesson.eventActive(lesson, t)
	local e = lesson.event
	return e ~= nil and t >= e.start and t < e.start + e.duration
end

-- Wall clock text for elapsed class time (e.g. "10:23").
function Lesson.schoolClock(t, duration, startMinutes, endMinutes)
	local minutes = startMinutes + (endMinutes - startMinutes) * math.clamp(t / duration, 0, 1)
	local h = math.floor(minutes / 60)
	local m = math.floor(minutes % 60)
	return string.format("%d:%02d", h, m), minutes
end

return Lesson
