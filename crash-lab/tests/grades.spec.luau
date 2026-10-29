local L = require("./loader")
local Grades = L.shared("Grades")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Grades: " .. name, fn = fn })
end

test("grade vs personal best: S/A/B/C/D thresholds", function()
	assert(Grades.grade(100, 0) == "S", "first run should be S")
	assert(Grades.grade(100, nil) == "S")
	assert(Grades.grade(1200, 1000) == "S", "new best is S")
	assert(Grades.grade(980, 1000) == "S", "within 2% is S")
	assert(Grades.grade(979, 1000) == "A")
	assert(Grades.grade(750, 1000) == "A")
	assert(Grades.grade(749, 1000) == "B")
	assert(Grades.grade(500, 1000) == "B")
	assert(Grades.grade(499, 1000) == "C")
	assert(Grades.grade(250, 1000) == "C")
	assert(Grades.grade(249, 1000) == "D")
	assert(Grades.grade(0, 1000) == "D")
	for _, g in ipairs(Grades.Order) do
		assert(Grades.Colors[g], "no colour for " .. g)
	end
end)

test("delta vs last run: rounded percent, nil without a previous run", function()
	assert(Grades.delta(150, 100) == 50)
	assert(Grades.delta(50, 100) == -50)
	assert(Grades.delta(100, 100) == 0)
	assert(Grades.delta(1005, 1000) == 1, "0.5% rounds up")
	assert(Grades.delta(995, 1000) == -1, "-0.5% rounds away from zero")
	assert(Grades.delta(100, nil) == nil and Grades.delta(100, 0) == nil)
	assert(Grades.deltaText(nil) == "First run - no comparison yet")
	assert(Grades.deltaText(0) == "Same as last run")
	assert(Grades.deltaText(12) == "+12% vs last run")
	assert(Grades.deltaText(-7) == "-7% vs last run")
end)

return cases
