-- Compiles every Luau source file to catch syntax errors the linter might miss.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failures = 0
local count = 0
local function walk(dir)
	for _, name in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif name:match("%.luau?$") then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failures += 1
				print("COMPILE ERROR " .. path .. "\n  " .. tostring(err))
			end
		end
	end
end
walk("src")
print(string.format("compiled %d files, %d failures", count, failures))
if failures > 0 then
	process.exit(1)
end
