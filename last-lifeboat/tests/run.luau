--[[
	Lune test runner for LAST LIFEBOAT's pure gameplay logic.
	Run from last-lifeboat/:  lune run tests/run
]]

local process = require("@lune/process")

local specs = {
	require("./shipgen.spec"),
	require("./lurch.spec"),
	require("./survival.spec"),
	require("./loot.spec"),
	require("./upgrades.spec"),
	require("./progress.spec"),
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
