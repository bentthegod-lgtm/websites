--[[
	Loads src/shared modules for the Lune unit tests with Roblox-style `script.Parent.X`
	requires and the Roblox datatypes (Vector3, CFrame...) that the pure modules use.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local cache = {}
local loadPath

local function node(path)
	return setmetatable({ __path = path }, {
		__index = function(self, key)
			if key == "Parent" then
				return node(string.match(rawget(self, "__path"), "^(.*)/[^/]+$"))
			end
			return node(rawget(self, "__path") .. "/" .. key)
		end,
	})
end

local function req(target)
	if type(target) == "table" and rawget(target, "__path") then
		return loadPath(rawget(target, "__path"))
	end
	error("unsupported require in unit tests: " .. tostring(target))
end

function loadPath(path)
	if cache[path] ~= nil then
		return cache[path]
	end
	local source = fs.readFile(path .. ".lua")
	local chunk = luau.load(source, {
		debugName = path,
		environment = {
			script = node(path),
			require = req,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			typeof = typeof,
		},
	})
	local result = chunk()
	cache[path] = result
	return result
end

return function(name)
	-- "server/..." loads from src/server (e.g. the server-only QuestionBank).
	if string.sub(name, 1, 7) == "server/" then
		return loadPath("src/" .. name)
	end
	return loadPath("src/shared/" .. name)
end
