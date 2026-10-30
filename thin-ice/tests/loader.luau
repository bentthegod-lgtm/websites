-- Loads src/shared modules in Lune: resolves require(script.Parent.X.Y) to files, and
-- provides the Roblox datatypes from @lune/roblox. Used by the unit specs.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}
local cache = {}
local loadFile

local function node(path)
	return setmetatable({ __path = path }, {
		__index = function(self, key)
			if key == "Parent" then
				local parent = string.match(rawget(self, "__path"), "^(.*)/[^/]+$")
				return node(parent)
			end
			local child = rawget(self, "__path") .. "/" .. key
			return node(child)
		end,
	})
end

local function requireNode(n)
	local path = rawget(n, "__path")
	return loadFile(path .. ".lua")
end

loadFile = function(file)
	if cache[file] ~= nil then
		return cache[file]
	end
	local env = {
		script = node((string.gsub(file, "%.lua$", ""))),
		require = requireNode,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		NumberSequence = roblox.NumberSequence,
		ColorSequence = roblox.ColorSequence,
		NumberRange = roblox.NumberRange,
	}
	env.math, env.string, env.table, env.os = math, string, table, os
	env.pairs, env.ipairs, env.type, env.tostring, env.tonumber = pairs, ipairs, type, tostring, tonumber
	env.select, env.error, env.assert, env.pcall, env.setmetatable = select, error, assert, pcall, setmetatable
	env.getmetatable, env.next, env.print, env.rawget, env.rawset, env.typeof = getmetatable, next, print, rawget, rawset, typeof
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
	local result = chunk()
	cache[file] = result
	return result
end

function Loader.shared(name)
	return loadFile("src/shared/" .. name .. ".lua")
end

Loader.roblox = roblox

return Loader
