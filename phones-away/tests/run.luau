--[[
	Lune test runner for PHONES AWAY!'s pure gameplay logic.
	Run from phones-away/:  lune run tests/run
]]

local process = require("@lune/process")

local specs = {
	require("./detection.spec"),
	require("./teacher.spec"),
	require("./test.spec"),
	require("./economy.spec"),
	require("./crate.spec"),
	require("./seating.spec"),
	require("./config.spec"),
}

local passed, failed = 0, 0
for _, spec in ipairs(specs) do
	for _, case in ipairs(spec) do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
			print("  PASS  " .. case.name)
		else
			failed += 1
			print("  FAIL  " .. case.name .. "\n        " .. tostring(err))
		end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
