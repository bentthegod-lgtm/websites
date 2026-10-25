local load = require("./loader")
local TeacherBrain = load("TeacherBrain")
local Lesson = load("Lesson")
local Detection = load("Detection")
local Rng = load("Rng")
local TeacherConfig = load("Config/TeacherConfig")
local GameConfig = load("Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Teacher: " .. name, fn = fn })
end

local L = GameConfig.Classroom

local function run(brain, seconds, start, ctx)
	local t = start or 0
	for _ = 1, math.floor(seconds * 10) do
		t += 0.1
		brain:update(0.1, t, ctx)
	end
	return t
end

test("board phase: back to the class, sight 0 except during a telegraphed glance", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(3))
	brain:setPhase("Board", 0)
	local sawWarn, sawGlance, maxSightNoWarn = false, false, 0
	local t = 0
	local warnedBefore = false
	for _ = 1, 600 do
		t += 0.1
		brain:update(0.1, t)
		if brain.warn then
			sawWarn = true
			warnedBefore = true
		end
		if brain.pose == "Glance" then
			sawGlance = true
			assert(warnedBefore, "glanced without a warning pause first")
		end
		if brain.pose == "Write" then
			maxSightNoWarn = math.max(maxSightNoWarn, brain.sight)
			warnedBefore = false
		end
	end
	assert(sawWarn and sawGlance, "no glance in 60 s")
	assert(maxSightNoWarn < 0.05, "sees while writing: " .. maxSightNoWarn)
end)

test("lecture: faces the class and turns slowly", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(4))
	brain.heading = math.pi
	brain:setPhase("Lecture", 0)
	brain:update(0.1, 0.1)
	local turned = math.abs(Detection.wrap(brain.heading - math.pi))
	assert(turned <= math.rad(TeacherConfig.Turn.Lecture) * 0.1 + 1e-6, "turned too fast")
	run(brain, 8, 0.1)
	assert(math.abs(brain.heading) < math.rad(TeacherConfig.LectureSweep + 5), "not facing the class")
	assert(brain.sight == 1)
end)

test("lecture: drifts her gaze toward a suspicious student", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(5))
	brain:setPhase("Lecture", 0)
	run(brain, 6, 0, { focus = { 15, 14 } })
	local want = Detection.headingTo(brain.x, brain.z, 15, 14)
	assert(math.abs(Detection.wrap(brain.heading - want)) < math.rad(3))
end)

test("walk: moves through the aisles and checks desks", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(6))
	brain.x, brain.z = L.LectureSpot[1], L.LectureSpot[2]
	brain:setPhase("Walk", 0)
	local maxZ = -100
	local t = 0
	for _ = 1, 200 do
		t += 0.1
		brain:update(0.1, t)
		maxZ = math.max(maxZ, brain.z)
		assert(brain.checking)
	end
	assert(maxZ > 15, "never reached the back of the room: " .. maxZ)
end)

test("paper airplane distracts her toward the noise; caught pose overrides", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(7))
	brain:setPhase("Lecture", 0)
	brain:update(0.1, 0.1)
	assert(brain:distract(-20, 10, 0.1, 3))
	run(brain, 2, 0.1)
	assert(brain.pose == "Distracted")
	local want = Detection.headingTo(brain.x, brain.z, -20, 10)
	assert(math.abs(Detection.wrap(brain.heading - want)) < math.rad(4))
	brain:caught(15, 14, 2.2)
	brain:update(0.1, 2.3)
	assert(brain.pose == "Point")
	run(brain, 4, 2.3)
	assert(brain.pose ~= "Point" and brain.pose ~= "Distracted")
end)

test("sleepy substitute naps (sight 0) and global detection scales senses", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(8), { substitute = true, detection = 0.55 })
	brain:setPhase("Lecture", 0)
	local napped = false
	local t = 0
	for _ = 1, 400 do
		t += 0.1
		brain:update(0.1, t)
		if brain.pose == "Nap" then
			napped = true
			assert(brain.sight == 0)
		elseif brain.pose == "Lecture" then
			assert(math.abs(brain.sight - 0.55) < 1e-6, "sight " .. brain.sight)
		end
	end
	assert(napped, "never napped")
end)

test("lunch check walks to the door and faces the hallway", function()
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(9))
	brain.x, brain.z = 0, -15
	brain:setPhase("LunchCheck", 0)
	run(brain, 12, 0)
	assert(brain.pose == "Door", brain.pose)
	assert(math.abs(Detection.wrap(brain.heading - math.pi / 2)) < 0.1)
end)

test("lesson: contiguous phases, board first, a quiz, enough walks, for many seeds", function()
	for seed = 1, 200 do
		local rng = Rng.new(seed)
		local event = Lesson.rollEvent(TeacherConfig, rng)
		local lesson = Lesson.build(TeacherConfig, GameConfig.ClassSeconds, rng, event)
		local cursor, quiz, walks = 0, 0, 0
		assert(lesson.phases[1].phase == "Board", "seed " .. seed .. " starts with " .. lesson.phases[1].phase)
		for i, p in ipairs(lesson.phases) do
			assert(math.abs(p.start - cursor) < 1e-6, "gap at phase " .. i)
			assert(p.duration > 0)
			cursor += p.duration
			if p.phase == "Quiz" then
				quiz += 1
			elseif p.phase == "Walk" then
				walks += 1
			end
			if i > 1 then
				assert(not (p.phase == "Walk" and lesson.phases[i - 1].phase == "Walk"), "two walks in a row")
			end
		end
		assert(math.abs(cursor - GameConfig.ClassSeconds) < 1e-6, "seed " .. seed .. " covers " .. cursor)
		assert(quiz == 1, "seed " .. seed .. " quizzes " .. quiz)
		assert(walks >= TeacherConfig.MinWalks, "seed " .. seed .. " walks " .. walks)
		if event == "FireDrill" or event == "LunchBell" then
			local want = if event == "FireDrill" then "FireDrill" else "LunchCheck"
			local found = false
			for _, p in ipairs(lesson.phases) do
				found = found or p.phase == want
			end
			assert(found, "seed " .. seed .. " event phase missing")
		end
		if event == "Principal" then
			assert(lesson.event and lesson.event.duration == TeacherConfig.Events.Principal.Seconds)
			assert(Lesson.eventActive(lesson, lesson.event.start + 1))
		end
	end
end)

test("she walks around the desks, never through them (door, back aisle -> board, 200 seeds)", function()
	-- Real footprint of a desk + its chair (ClassroomBuilder), plus her half-width.
	local function insideDesk(x, z)
		for _, row in ipairs(L.DeskRows) do
			for _, col in ipairs(L.DeskColumns) do
				if math.abs(x - col) < 2 + 0.9 and z > row - 1.3 - 0.9 and z < row + 3.45 + 0.9 then
					return true
				end
			end
		end
		return false
	end
	local phases = { "Board", "LunchCheck", "Lecture", "Walk", "LunchCheck", "Walk", "Board", "FireDrill", "Walk", "Quiz" }
	for seed = 1, 200 do
		local rng = Rng.new(seed)
		local brain = TeacherBrain.new(TeacherConfig, L, rng)
		local t = 0
		for _, phase in ipairs(phases) do
			brain:setPhase(phase, t)
			for _ = 1, math.floor(rng:range(4, 14) * 10) do
				t += 0.1
				brain:update(0.1, t)
				assert(not insideDesk(brain.x, brain.z), string.format("seed %d: walked through a desk at (%.1f, %.1f) in %s", seed, brain.x, brain.z, phase))
				assert(brain.x == brain.x and brain.heading == brain.heading, "NaN position / heading")
			end
		end
	end
	-- And she still gets to the door during the early lunch bell.
	local brain = TeacherBrain.new(TeacherConfig, L, Rng.new(1))
	brain:setPhase("LunchCheck", 0)
	run(brain, 20, 0)
	assert(math.abs(brain.x - (L.DoorSpot[1] - 2)) < 0.1 and math.abs(brain.z - L.DoorSpot[2]) < 0.1, "never reached the door")
	assert(brain.pose == "Door")
end)

test("school clock runs 10:05 -> 10:55", function()
	assert(Lesson.schoolClock(0, 200, GameConfig.SchoolClockStart, GameConfig.SchoolClockEnd) == "10:05")
	assert(Lesson.schoolClock(200, 200, GameConfig.SchoolClockStart, GameConfig.SchoolClockEnd) == "10:55")
	assert(Lesson.schoolClock(100, 200, GameConfig.SchoolClockStart, GameConfig.SchoolClockEnd) == "10:30")
end)

return cases
