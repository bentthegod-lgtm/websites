-- Exports the lobby and one generated facility as JSON for a browser 3D preview.
-- Usage (from dead-air/): lune run tools/export_preview build/DeadAir.rbxlx <seed> build/preview.json
--[[
	Headless smoke harness.

	Loads the Rojo-built place file in Lune and executes the real game modules against
	Lune's Roblox instance implementation (which validates class and property names against
	the Roblox reflection database). Engine services Lune does not simulate (physics,
	pathfinding, tweens, players, data stores) are stubbed.

	This catches typos in instance properties, enum names, wrong value types and nil errors
	in world-building / UI code. It does NOT simulate gameplay physics.

	Usage (from dead-air/):  rojo build -o build/DeadAir.rbxlx && lune run tests/harness build/DeadAir.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/DeadAir.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))

---------------------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------------------

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, fn in ipairs(self.handlers) do
			fn(...)
		end
	end
	function s:Wait()
		return nil
	end
	return s
end

local function stubObject(name, extra)
	local obj = extra or {}
	return setmetatable(obj, {
		__index = function(_, key)
			if string.match(key, "^%u%w*Added$") or string.match(key, "^%u%w*Removing$") or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" then
				local s = signal()
				rawset(obj, key, s)
				return s
			end
			return function()
				return nil
			end
		end,
		__tostring = function()
			return name
		end,
	})
end

local fakePlayers = stubObject("Players", {
	LocalPlayer = nil,
	CharacterAutoLoads = false,
	GetPlayers = function()
		return {}
	end,
	GetPlayerByUserId = function()
		return nil
	end,
	GetPlayerFromCharacter = function()
		return nil
	end,
})

local stubServices = {
	CollectionService = stubObject("CollectionService", {
		AddTag = function(_, inst, tag)
			inst:AddTag(tag)
		end,
		GetTagged = function()
			return {}
		end,
		GetInstanceAddedSignal = function()
			return signal()
		end,
		GetInstanceRemovedSignal = function()
			return signal()
		end,
	}),
	TweenService = stubObject("TweenService", {
		Create = function(_, instance, _info, goals)
			return {
				Play = function()
					for k, v in pairs(goals) do
						instance[k] = v
					end
				end,
				Completed = signal(),
				Instance = instance,
			}
		end,
	}),
	RunService = stubObject("RunService", {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
	}),
	Players = fakePlayers,
	PathfindingService = stubObject("PathfindingService", {
		CreatePath = function()
			return stubObject("Path", { Status = roblox.Enum.PathStatus.NoPath })
		end,
	}),
	DataStoreService = stubObject("DataStoreService", {
		GetDataStore = function()
			error("DataStores are not available in the harness")
		end,
	}),
	Debris = stubObject("Debris"),
	UserInputService = stubObject("UserInputService", {
		TouchEnabled = false,
		KeyboardEnabled = true,
		GamepadEnabled = false,
	}),
	ContextActionService = stubObject("ContextActionService"),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
}

local game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				if stubServices[name] then
					return stubServices[name]
				end
				return place:GetService(name)
			end
		elseif key == "BindToClose" then
			return function() end
		end
		return place[key]
	end,
})

local workspaceService = place:GetService("Workspace")

-- Engine methods Lune's instance implementation does not provide.
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	assert(child, "WaitForChild would hang: " .. self:GetFullName() .. "." .. tostring(name))
	return child
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	self:SetAttribute("HarnessPivot", cf.Position)
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
-- Lune has no engine events; give the ones the game connects to a fake signal.
local eventStore = setmetatable({}, { __mode = "k" })
local function fakeEvent(className, eventName)
	roblox.implementProperty(className, eventName, function(self)
		eventStore[self] = eventStore[self] or {}
		eventStore[self][eventName] = eventStore[self][eventName] or signal()
		return eventStore[self][eventName]
	end)
end
for _, e in ipairs({ "Triggered", "PromptButtonHoldBegan", "PromptButtonHoldEnded" }) do
	fakeEvent("ProximityPrompt", e)
end
fakeEvent("Humanoid", "Died")
fakeEvent("Instance", "ChildAdded")
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
roblox.implementMethod("Humanoid", "MoveTo", function() end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)

---------------------------------------------------------------------------------------------
-- Module loader (Roblox-style require on ModuleScript instances)
---------------------------------------------------------------------------------------------

local cache = {}
proxyOf = setmetatable({}, { __mode = "k" })
function unwrap(v)
	return proxyOf[v] or v
end
local env
-- Track every thread the game starts so they can be cancelled before exiting.
local threads = {}
local trackedTask = setmetatable({}, { __index = task })
-- Background loops are parked forever on their first wait: the harness checks that
-- they start, not what they do over time.
trackedTask.wait = function()
	coroutine.yield()
end
for _, name in ipairs({ "spawn", "delay", "defer" }) do
	trackedTask[name] = function(...)
		local thread = task[name](...)
		table.insert(threads, thread)
		return thread
	end
end
local handlerErrors = 0

local function requireModule(moduleScript)
	if cache[moduleScript] ~= nil then
		return cache[moduleScript]
	end
	local source = moduleScript.Source
	local chunk = luau.load(source, {
		debugName = moduleScript:GetFullName(),
		environment = (function()
			-- luau.load copies the environment's own keys, so build a flat table.
			local e = table.clone(env)
			e.script = moduleScript
			return e
		end)(),
	})
	local result = chunk()
	cache[moduleScript] = result
	return result
end

local function stubCtor(name)
	return {
		new = function(...)
			return setmetatable({ args = { ... } }, {
				__index = function()
					return nil
				end,
				__tostring = function()
					return name
				end,
			})
		end,
	}
end

env = setmetatable({
	game = game,
	workspace = workspaceService,
	require = requireModule,
	-- Lune stores BasePart.Position separately from CFrame and has no default for it, so
	-- give new parts one (values are not kept in sync; the harness checks for errors only).
	Instance = {
		new = function(className, parent)
			local instance = roblox.Instance.new(className)
			if parent then
				instance.Parent = parent
			end
			local isPart = instance:IsA("BasePart")
			if isPart then
				instance.Position = roblox.Vector3.zero
			end
			-- Proxy: writing Position moves CFrame, as it does in Roblox.
			local proxy = {}
			proxyOf[proxy] = instance
			return setmetatable(proxy, {
				__index = function(_, key)
					if key == "Position" and isPart then
						return instance.CFrame.Position
					end
					local v = instance[key]
					if type(v) == "function" then
						return function(_, ...)
							local args = table.pack(...)
							for i = 1, args.n do
								args[i] = unwrap(args[i])
							end
							return v(instance, table.unpack(args, 1, args.n))
						end
					end
					return v
				end,
				__newindex = function(_, key, value)
					value = unwrap(value)
					if key == "Position" and isPart then
						instance.CFrame = instance.CFrame - instance.CFrame.Position + value
					else
						instance[key] = value
					end
				end,
			})
		end,
	},
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	RaycastParams = stubCtor("RaycastParams"),
	TweenInfo = stubCtor("TweenInfo"),
	task = trackedTask,
	typeof = typeof,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		print("[warn]", message)
		-- Signal swallows handler errors with a warning; surface them as failures.
		if string.find(message, "handler error", 1, true) or string.find(message, "Failed to start", 1, true) then
			handlerErrors += 1
		end
	end,
}, nil)


---------------------------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------------------------
-- Every Instance property write from non-proxied instances (welds, prompts) may receive a
-- proxy; unwrap them on the real instance class too.
local RS = place:GetService("ReplicatedStorage")
local Services = place:GetService("ServerScriptService"):FindFirstChild("DeadAirServer"):FindFirstChild("Services")
local Shared = RS:FindFirstChild("DeadAir")
local Rng = requireModule(Shared.Rng)
local MazeGen = requireModule(Shared.MazeGen)
local MapConfig = requireModule(Shared.Config.MapConfig)
local ObjectiveConfig = requireModule(Shared.Config.ObjectiveConfig)
local MapBuilder = requireModule(Services.MapBuilder)
local LobbyBuilder = requireModule(Services.LobbyBuilder)

local function r(n) return math.floor(n * 100 + 0.5) / 100 end
local function dumpFolder(folder, offset)
	local parts = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local cf = d.CFrame
			local pos = cf.Position - offset
			local x, y, z = cf:ToOrientation()
			local c = d.Color
			local light = nil
			for _, l in ipairs(d:GetChildren()) do
				if (l:IsA("PointLight") or l:IsA("SpotLight")) and l.Enabled then
					light = { math.floor(l.Color.R * 255), math.floor(l.Color.G * 255), math.floor(l.Color.B * 255), r(l.Range), r(l.Brightness) }
				end
			end
			table.insert(parts, {
				p = { r(pos.X), r(pos.Y), r(pos.Z) },
				o = { r(x), r(y), r(z) },
				s = { r(d.Size.X), r(d.Size.Y), r(d.Size.Z) },
				c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
				t = r(d.Transparency),
				m = d.Material.Name,
				sh = if d:IsA("Part") then d.Shape.Name else "Block",
				l = light,
				n = d.Name,
			})
		end
	end
	return parts
end

local lobby = LobbyBuilder.build()
local rng = Rng.new(tonumber(process.args[2]) or 20261023)
local layout = MazeGen.generate(MapConfig, rng)
local map = MapBuilder.build(layout, ObjectiveConfig.Chains.PowerGrid, rng, { fuseCount = 3, runLabel = "RUN PREVIEW" })
map:setPower(false)
local serde = require("@lune/serde")
local out = {
	lobby = dumpFolder(lobby.folder, lobby.origin),
	facility = dumpFolder(map.folder, roblox.Vector3.zero),
	facilitySize = { MapConfig.GridWidth * MapConfig.CellSize, MapConfig.GridHeight * MapConfig.CellSize },
}
fs.writeFile(process.args[3] or "build/preview.json", serde.encode("json", out))
print("lobby parts", #out.lobby, "facility parts", #out.facility)
process.exit(0)
