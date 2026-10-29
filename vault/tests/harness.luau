--[[
	Headless smoke harness for VAULT.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation (class / property / enum names are checked against the
	reflection database). Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, physics, rendering) are stubbed, and time is a fake clock
	the tests advance.

	Physics is NOT simulated by Lune, so characters are MOVED by the harness (their root
	CFrame is set where a player would walk). Everything else - the world build, loot
	spawning / claims / pooling, magnet and auto-collect, deposits, upgrades, depth unlocks,
	elevator rides, rare events, the book, achievements, dailies, rebirth, receipts,
	persistence and session locks, and the client controllers - is the real code.

	Usage (from vault/):
	  rojo build -o build/Vault.rbxlx && lune run tests/harness build/Vault.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/Vault.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))

---------------------------------------------------------------------------------------------
-- Fake clock
---------------------------------------------------------------------------------------------

local clock = 1000
local unixOffset = 1800000000
local function advance(seconds)
	clock += seconds
end
local fakeOs = {
	clock = function()
		return clock
	end,
	time = function()
		return math.floor(unixOffset + clock)
	end,
	date = os.date,
}

---------------------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------------------

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(self.handlers, fn)
				if i then
					table.remove(self.handlers, i)
				end
			end,
		}
	end
	function s:Fire(...)
		for _, fn in ipairs(table.clone(self.handlers)) do
			fn(...)
		end
	end
	function s:Wait()
		return nil
	end
	return s
end

local SIGNAL_SUFFIXES = { "Added$", "Removing$", "Finished$", "Began$", "Ended$", "Changed$", "Released$", "Focused$", "^Heartbeat$", "^Stepped$", "^RenderStepped$", "^Prompt" }
local function stubObject(name, extra)
	local obj = extra or {}
	return setmetatable(obj, {
		__index = function(_, key)
			for _, pattern in ipairs(SIGNAL_SUFFIXES) do
				if string.match(key, pattern) then
					local s = signal()
					rawset(obj, key, s)
					return s
				end
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

local playerList = {}
local fakePlayers = stubObject("Players", {
	LocalPlayer = nil,
	GetPlayers = function()
		return table.clone(playerList)
	end,
	GetPlayerByUserId = function(_, id)
		for _, p in ipairs(playerList) do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end,
	GetNameFromUserIdAsync = function(_, id)
		return "User" .. tostring(id)
	end,
})

local prompts = {}
local analytics = {}
local collisionGroups, collidable = {}, {}
local networkOwners = {}
local isStudio = true
local stubServices = {
	TweenService = stubObject("TweenService", {
		Create = function(_, instance, _info, goals)
			return {
				Play = function()
					for k, v in pairs(goals) do
						instance[k] = v
					end
				end,
				Cancel = function() end,
				Completed = signal(),
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
			return isStudio
		end,
	}),
	Players = fakePlayers,
	DataStoreService = stubObject("DataStoreService", {
		GetDataStore = function()
			error("DataStores are not available in the harness")
		end,
		GetOrderedDataStore = function()
			error("DataStores are not available in the harness")
		end,
	}),
	MarketplaceService = stubObject("MarketplaceService", {
		UserOwnsGamePassAsync = function()
			return false
		end,
		PromptProductPurchase = function(_, player, id)
			table.insert(prompts, { player = player, id = id })
		end,
		PromptGamePassPurchase = function(_, player, id)
			table.insert(prompts, { player = player, id = id, pass = true })
		end,
	}),
	AnalyticsService = stubObject("AnalyticsService", {
		LogOnboardingFunnelStepEvent = function(_, player, step, name)
			table.insert(analytics, { player = player, step = step, name = name })
		end,
		LogCustomEvent = function() end,
	}),
	UserInputService = stubObject("UserInputService", { TouchEnabled = true, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }),
	PhysicsService = stubObject("PhysicsService", {
		RegisterCollisionGroup = function(_, name)
			collisionGroups[name] = true
		end,
		CollisionGroupSetCollidable = function(_, a, b, value)
			collidable[a .. "|" .. b] = value
		end,
	}),
	GuiService = stubObject("GuiService"),
	ProximityPromptService = stubObject("ProximityPromptService"),
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
		elseif key == "JobId" then
			return "harness-job"
		end
		return place[key]
	end,
})

local workspaceService = place:GetService("Workspace")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	assert(child, "WaitForChild would hang: " .. self:GetFullName() .. "." .. tostring(name))
	return child
end)
roblox.implementMethod("Model", "GetPivot", function(self)
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame
	end
	local first = self:FindFirstChildWhichIsA("BasePart", true)
	return if first then first.CFrame else roblox.CFrame.new()
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local pivot = if self.PrimaryPart then self.PrimaryPart.CFrame else roblox.CFrame.new()
	local delta = cf * pivot:Inverse()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
-- Lune keeps Position and CFrame separate; in Roblox Position is derived from CFrame.
-- syncPositions() copies CFrame.Position into Position for everything under a root.
local function syncPositions(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Position = d.CFrame.Position
		end
	end
end
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return unixOffset + clock
end)
local bulkMoves = 0
roblox.implementMethod("Workspace", "BulkMoveTo", function(_, parts, cframes)
	assert(#parts == #cframes, "BulkMoveTo size mismatch")
	for i, part in ipairs(parts) do
		part.CFrame = cframes[i]
	end
	bulkMoves += #parts
end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Part", "SetNetworkOwner", function(self, owner)
	networkOwners[self] = owner or "server"
end)
roblox.implementMethod("Instance", "ClearAllChildren", function(self)
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end)

local eventStore = {}
local function keyOf(instance)
	local id = instance:GetAttribute("__harnessId")
	if not id then
		id = tostring(math.random(1, 2 ^ 30)) .. tostring(clock)
		instance:SetAttribute("__harnessId", id)
	end
	return id
end
local function fakeEvent(className, eventName)
	roblox.implementProperty(className, eventName, function(self)
		local k = keyOf(self)
		eventStore[k] = eventStore[k] or {}
		eventStore[k][eventName] = eventStore[k][eventName] or signal()
		return eventStore[k][eventName]
	end)
end
for _, e in ipairs({ "Triggered", "PromptButtonHoldBegan", "PromptButtonHoldEnded" }) do
	fakeEvent("ProximityPrompt", e)
end
fakeEvent("Player", "CharacterAdded")
fakeEvent("Part", "Touched")
fakeEvent("Model", "DescendantAdded")
fakeEvent("Humanoid", "Died")
fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
for _, cls in ipairs({ "TextButton", "Frame", "TextLabel", "ImageButton", "TextBox" }) do
	for _, e in ipairs({ "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" }) do
		fakeEvent(cls, e)
	end
end
fakeEvent("TextButton", "Activated")
fakeEvent("CFrameValue", "Changed")
fakeEvent("NumberValue", "Changed")
fakeEvent("Folder", "Destroying")
fakeEvent("Model", "Destroying")
fakeEvent("TextBox", "FocusLost")
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return signal()
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return signal()
end)

---------------------------------------------------------------------------------------------
-- Module loader
---------------------------------------------------------------------------------------------

local cache = {}
local env
local trackedTask = setmetatable({}, { __index = task })
local deferred = {}
-- Background loops park on their first wait; deferred work runs when the test flushes.
trackedTask.wait = function()
	coroutine.yield()
end
trackedTask.defer = function(fn, ...)
	table.insert(deferred, { fn = fn, args = table.pack(...) })
end
local delayed = {}
trackedTask.delay = function(seconds, fn, ...)
	table.insert(delayed, { due = clock + (seconds or 0), fn = fn, args = table.pack(...) })
end
local function flushDeferred()
	for _ = 1, 5 do
		local list = deferred
		deferred = {}
		local keep = {}
		for _, d in ipairs(delayed) do
			if d.due <= clock + 1e-9 then
				table.insert(list, d)
			else
				table.insert(keep, d)
			end
		end
		delayed = keep
		for _, d in ipairs(list) do
			local co = coroutine.create(d.fn)
			local ok, err = coroutine.resume(co, table.unpack(d.args, 1, d.args.n))
			if not ok then
				error("deferred task failed: " .. tostring(err))
			end
		end
		if #deferred == 0 then
			return
		end
	end
end

local handlerErrors = 0
local warnings = {}

local function requireModule(moduleScript)
	if cache[moduleScript] ~= nil then
		return cache[moduleScript]
	end
	local e = table.clone(env)
	e.script = moduleScript
	local chunk = luau.load(moduleScript.Source, { debugName = moduleScript:GetFullName(), environment = e })
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

local Rng = luau.load(fs.readFile("src/shared/Rng.lua"))()
local seedCounter = 1
local RandomShim = {
	new = function(seed)
		seedCounter += 1
		return Rng.new(seed or (seedCounter * 7919))
	end,
}

env = {
	game = game,
	workspace = workspaceService,
	require = requireModule,
	Instance = {
		new = function(className, parent)
			local instance = roblox.Instance.new(className)
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	},
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	PhysicalProperties = roblox.PhysicalProperties,
	TweenInfo = stubCtor("TweenInfo"),
	Random = RandomShim,
	task = trackedTask,
	os = fakeOs,
	typeof = typeof,
	print = function() end,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		table.insert(warnings, message)
		if string.find(message, "error", 1, true) or string.find(message, "Failed to start", 1, true) or string.find(message, "failed", 1, true) then
			handlerErrors += 1
			print("[warn]", message)
		end
	end,
}

---------------------------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------------------------

local passed, failed = 0, 0
local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		print("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end

local RS = place:GetService("ReplicatedStorage")
local SSS = place:GetService("ServerScriptService")
local Shared = RS:FindFirstChild("Vault")
local ServerRoot = SSS:FindFirstChild("VaultServer")
local Services = ServerRoot:FindFirstChild("Services")

local GameConfig = requireModule(Shared.Config.GameConfig)
local LootConfig = requireModule(Shared.Config.LootConfig)
local DepthConfig = requireModule(Shared.Config.DepthConfig)
local UpgradeConfig = requireModule(Shared.Config.UpgradeConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local QuestConfig = requireModule(Shared.Config.QuestConfig)
local Economy = requireModule(Shared.Economy)
local V3, CF = roblox.Vector3, roblox.CFrame

-- A real product id so ProcessReceipt can be exercised (config tables are plain tables).
local BOOST_PRODUCT = 6161
for _, product in ipairs(ShopConfig.Products) do
	if product.Key == "ValueBoost" then
		product.ProductId = BOOST_PRODUCT
	end
end

check("all server and shared modules load", function()
	for _, root in ipairs({ Shared, ServerRoot }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("ModuleScript") then
				requireModule(d)
			end
		end
	end
end)

local world
check("world builds: 7 stacked depths, deposits, elevators, exit doors, previews, valid spawn points", function()
	local VaultBuilder = requireModule(ServerRoot.World.VaultBuilder)
	world = VaultBuilder.build()
	syncPositions(world.folder)
	assert(#world.depths == 7, "expected 7 depths")
	local counts = {}
	for d, record in ipairs(world.depths) do
		assert(math.abs(record.y0 + (d - 1) * GameConfig.DepthSpacing) < 1e-6, "depth " .. d .. " floor height")
		assert(#record.deposits >= 1 and record.terminal and record.elevator and record.exitDoor, "depth " .. d .. " is missing a machine")
		assert(record.elevator.arrival and record.elevator.doors.left and record.elevator.doors.right, "elevator " .. d)
		assert(record.exitDoor.model:GetAttribute("ExitDoor") and record.exitDoor.model:GetAttribute("NextDepth") == d + 1, "exit door tag " .. d)
		assert(#record.points >= 100, "depth " .. d .. " has only " .. #record.points .. " spawn points")
		for _, point in ipairs(record.points) do
			assert(VaultBuilder.validatePoint(record, point), "invalid spawn point on depth " .. d)
			assert(DepthConfig.depthAtY(point.cframe.Position.Y, GameConfig.DepthSpacing) == d, "spawn point outside its height band")
		end
		assert(record.landmark and record.rarePoint, "depth " .. d .. " landmark / rare point")
		assert(record.preview and #record.preview.cframes == 3, "preview room " .. d)
		-- The arrival spot is inside the cabin, facing out of the doors (+Z, into the room).
		local arrival = record.elevator.arrival
		assert(arrival.LookVector.Z > 0.9, "arrival faces the back wall on depth " .. d)
		table.insert(counts, string.format("B%d %d", d, record.parts))
	end
	assert(world.machines.D1_1 and world.machines.D1_2 and world.machines.D7_1, "deposit machine ids")
	assert(world.boards and world.boards.Earned and world.boards.Depth and world.boards.Loot and world.boards.Deposit, "4 leaderboards")
	assert(world.partCount < 9000, "part budget exceeded: " .. world.partCount)
	print("        world parts: " .. world.partCount .. " (" .. table.concat(counts, ", ") .. ")")
end)

local Pools = requireModule(ServerRoot.World.Pools)
local Reach = requireModule(ServerRoot.World.Reach)
local DoorMath = requireModule(Shared.DoorMath)

check("pools: deep basin, walkable profile within Humanoid step / slope limits", function()
	local prof = Pools.Profile
	assert(prof[1].h0 == 0, "the descent starts at the rim")
	local shallow, deep = math.huge, -math.huge
	for i, seg in ipairs(prof) do
		if i > 1 then
			assert(math.abs(seg.z0 - prof[i - 1].z1) < 1e-6 and math.abs(seg.h0 - prof[i - 1].h1) < 1e-6, "profile segment " .. i .. " does not meet the previous one")
		end
		if seg.kind == "stairs" then
			local rise = (seg.h0 - seg.h1) / seg.steps
			local run = (seg.z1 - seg.z0) / seg.steps
			assert(rise <= 1.0 + 1e-6 and run >= 1.5, string.format("steps rise %.2f over %.2f", rise, run))
		elseif seg.kind == "ramp" then
			local angle = math.deg(math.atan2(seg.h0 - seg.h1, seg.z1 - seg.z0))
			assert(angle > 0 and angle <= 40, string.format("ramp %d is %.1f degrees", i, angle))
		end
		shallow = math.min(shallow, -seg.h0)
		deep = math.max(deep, -seg.h1)
	end
	assert(Pools.Pool.depth >= 30 and deep == Pools.Pool.depth, "the pool must be 30+ studs deep (" .. deep .. ")")
	assert(-Pools.surface(-20) < -Pools.surface(45), "the deep end must be deeper than the shallow end")
	-- Tunnel slopes too.
	local T = Pools.Tunnel
	local aAngle = math.deg(math.atan2(T.aDrop, T.aEnd - T.aRampStart))
	local cAngle = math.deg(math.atan2(T.landing.y - T.cY, T.cTop - T.cBottom))
	assert(aAngle <= 40 and cAngle <= 40, string.format("tunnel ramps %.1f / %.1f degrees", aAngle, cAngle))
	assert(T.cY == -GameConfig.DepthSpacing, "the tunnel must end exactly on the next depth's rim")
end)

local function walkFor(d, roots)
	local record = world.depths[d]
	local VaultBuilder = requireModule(ServerRoot.World.VaultBuilder)
	local idx = Reach.index(roots or record.folder)
	return idx, Reach.walk(idx, VaultBuilder.walkBounds(record.y0), VaultBuilder.walkStart(record.y0))
end

check("reachability: every spawn point, machine and the vault door is reachable on foot from the rim", function()
	local lines = {}
	for d, record in ipairs(world.depths) do
		local y0 = record.y0
		local idx, walk = walkFor(d)
		assert(#walk.list > 2000, "depth " .. d .. ": walk graph too small (" .. #walk.list .. " nodes)")
		local lowest = math.huge
		for _, n in ipairs(walk.list) do
			lowest = math.min(lowest, n.Y - y0)
		end
		assert(lowest <= -Pools.Pool.depth + 0.1, string.format("B%d: walking only reaches %.1f below the rim", d, -lowest))
		local shallow, deeper, bonusShallow, bonusDeep = 0, 0, 0, 0
		for _, point in ipairs(record.points) do
			local ok, why = Reach.pointOk(idx, walk, point.cframe.Position)
			assert(ok, string.format("B%d point at %s: %s", d, tostring(point.cframe.Position), tostring(why)))
			if point.cframe.Position.Y - y0 > -21 then
				shallow += 1
				bonusShallow += point.bonus
			else
				deeper += 1
				bonusDeep += point.bonus
			end
		end
		assert(deeper > shallow and bonusDeep / deeper > bonusShallow / shallow, string.format("B%d: loot should be denser and luckier deeper (%d shallow, %d deep)", d, shallow, deeper))
		assert(Reach.pointOk(idx, walk, record.rarePoint.Position), "B" .. d .. " rare-event point unreachable")
		for _, machine in ipairs(record.deposits) do
			assert(Reach.reachable(walk, machine.zone.cframe.Position - V3.new(0, 3, 0), 2.5), machine.id .. " deposit zone unreachable")
		end
		assert(Reach.reachable(walk, record.terminal.cframe.Position, 4), "B" .. d .. " upgrade terminal unreachable")
		assert(Reach.reachable(walk, record.exitDoorPosition, 3), "B" .. d .. " vault door unreachable from the rim")
		assert(not Reach.pointOk(idx, walk, V3.new(-GameConfig.RoomWidth / 2 - 1, y0 + 2, 0)), "a point inside the wall passed")
		assert(not Reach.pointOk(idx, walk, V3.new(0, y0 - 60, 0)), "a point under the pool passed")
		table.insert(lines, string.format("B%d %d pts (%d deep)", d, #record.points, deeper))
	end
	print("        " .. table.concat(lines, ", "))
end)

local function setDoor(record, alpha)
	local leaf = record.exitDoor.leaf
	local hinge = record.exitDoor.closedHinge or leaf:GetPivot()
	record.exitDoor.closedHinge = hinge
	leaf:PivotTo(DoorMath.pivot(hinge, alpha))
end

check("vault doors: locked doors block the tunnel; opened, the tunnel walks down to the next rim", function()
	for d = 1, 7 do
		local record = world.depths[d]
		local nextRecord = world.depths[d + 1]
		local roots = if nextRecord then { record.folder, nextRecord.folder } else { record.folder }
		local landing = V3.new(-20, record.y0 + Pools.Tunnel.landing.y, (Pools.Tunnel.landing.z0 + Pools.Tunnel.landing.z1) / 2)
		local _, closed = walkFor(d, roots)
		assert(not Reach.reachable(closed, landing, 3), "B" .. d .. ": the tunnel is reachable with the door closed")
		setDoor(record, 1)
		local _, open = walkFor(d, roots)
		setDoor(record, 0)
		assert(Reach.reachable(open, landing, 3), "B" .. d .. ": the open door does not lead to the tunnel landing")
		if nextRecord then
			local nextRim = V3.new(Pools.Tunnel.arrivalX, nextRecord.y0, GameConfig.RoomBack - 4)
			assert(Reach.reachable(open, nextRim, 3), "B" .. d .. ": the tunnel does not reach B" .. (d + 1) .. "'s rim")
			assert(Reach.reachable(open, nextRecord.elevator.arrival.Position - V3.new(0, 3, 0) + V3.new(0, 0, 8), 4), "B" .. d .. ": walking down does not lead on to B" .. (d + 1) .. "'s arrival deck")
			assert(record.tunnelEnd and math.abs(record.tunnelEnd.Y - nextRecord.y0) < 1e-6, "tunnel end is not on the next rim")
		else
			assert(record.tunnelEnd == nil, "B7's tunnel must end at the sealed Ancient Vault")
		end
		assert(nextRecord == nil or nextRecord.y0 < record.y0 - Pools.Pool.depth, "the next depth must sit below this pool's bottom")
	end
end)

-- Remote stubs that record traffic.
local log = {}
local function stubRemote(name)
	log[name] = {}
	return {
		FireAllClients = function(_, ...)
			table.insert(log[name], { all = true, args = table.pack(...) })
		end,
		FireClient = function(_, player, ...)
			table.insert(log[name], { player = player, args = table.pack(...) })
		end,
		OnServerEvent = signal(),
	}
end
local remotes = setmetatable({}, {
	__index = function(t, k)
		local r = stubRemote(k)
		rawset(t, k, r)
		return r
	end,
})
local function count(name, pattern, player)
	local n = 0
	for _, entry in ipairs(log[name] or {}) do
		if (not player or entry.player == player or entry.all) and (not pattern or string.find(tostring(entry.args[1]), pattern, 1, true)) then
			n += 1
		end
	end
	return n
end
local function lastFor(name, player)
	local list = log[name] or {}
	for i = #list, 1, -1 do
		if list[i].player == player or (list[i].all and not player) then
			return list[i]
		end
	end
	return nil
end

local registry
local ORDER = { "Analytics", "DataService", "PlayerService", "ShopService", "UpgradeService", "QuestService", "LootService", "DepositService", "ElevatorService", "LeaderboardService" }
check("services initialise and start (same order as Main.server); every depth is stocked", function()
	registry = { Remotes = remotes }
	for _, name in ipairs(ORDER) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs(ORDER) do
		registry[name].init(registry)
	end
	for _, name in ipairs(ORDER) do
		if registry[name].setWorld then
			registry[name].setWorld(world)
		end
	end
	for _, name in ipairs(ORDER) do
		if name ~= "DataService" and registry[name].start then
			registry[name].start()
		end
	end
	registry.DataService.start()
	assert(type(stubServices.MarketplaceService.ProcessReceipt) == "function", "ProcessReceipt not bound")
	local LS = registry.LootService
	for d = 1, 7 do
		local n = LS.count(d)
		assert(n >= math.floor(DepthConfig.get(d).ActiveLoot * 0.85), "depth " .. d .. " stocked with " .. n)
		for _, entry in pairs(LS.items(d)) do
			assert(entry.def.Depth == d and not entry.def.Special, "wrong loot on depth " .. d)
			assert(entry.model and entry.model.Parent == world.lootFolder and entry.model:GetAttribute("LootId") == entry.id and entry.model:GetAttribute("Depth") == d, "loot model not registered")
		end
	end
end)

local nextUserId = 3000
local function makeCharacter(player, position)
	local character = roblox.Instance.new("Model")
	character.Name = player.Name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3.new(2, 2, 1)
	root.CFrame = CF.new(position or V3.new(0, 3, -64))
	root.Position = root.CFrame.Position
	root.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspaceService
	player.Character = character
	player.CharacterAdded:Fire(character)
	flushDeferred()
	return root, humanoid
end
local function makePlayer(name, position)
	nextUserId += 1
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = nextUserId
	player.Parent = place:GetService("Players")
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	local root = makeCharacter(player, position)
	return player, root
end
local function leave(player)
	local i = table.find(playerList, player)
	if i then
		table.remove(playerList, i)
	end
	fakePlayers.PlayerRemoving:Fire(player)
	player.Parent = nil
	flushDeferred()
end
local function moveTo(root, position)
	root.CFrame = CF.new(position)
	root.Position = position
end

local DS, LS, DepS, US, ES, QS
-- Advances the fake clock in 1/30 s steps, running the same Heartbeat work as Main.server.
local function tick(seconds, script)
	local dt = 1 / 30
	local t = 0
	while t < seconds - 1e-9 do
		advance(dt)
		t += dt
		if script then
			script(t)
		end
		LS.step(dt)
		DepS.step(dt)
		flushDeferred()
	end
	flushDeferred()
end

-- Nearest loose normal item to a point on a depth.
local function nearestItem(depth, position, filter)
	local best, bestDist
	for _, entry in pairs(LS.items(depth)) do
		if not entry.def.Special and (not filter or filter(entry)) then
			local d = (entry.position - position).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = entry, d
			end
		end
	end
	return best
end
-- Walks to an item and asks for it through the real remote.
local function grab(player, root, entry)
	moveTo(root, entry.position + V3.new(0, 2.5, 0))
	remotes.Collect.OnServerEvent:Fire(player, entry.id)
	flushDeferred()
end

local alice, aliceRoot, bob, bobRoot
check("player joins: default profile, placed in the B1 elevator, leaderstats, told saving is off", function()
	DS, LS, DepS, US, ES, QS = registry.DataService, registry.LootService, registry.DepositService, registry.UpgradeService, registry.ElevatorService, registry.QuestService
	alice, aliceRoot = makePlayer("Alice", V3.new(0, 50, 0))
	local p = DS.getProfile(alice)
	assert(p and p.Cash == 0 and p.Tokens == 0 and p.HighestDepth == 1 and p.Carried.Count == 0, "bad default profile")
	assert(not DS.isPersistent(alice), "persistent without a DataStore")
	assert(alice:FindFirstChild("leaderstats"), "no leaderstats")
	assert(count("Notify", "saving is unavailable", alice) >= 1, "not told that saving is off")
	local arrival = world.depths[1].elevator.arrival.Position
	assert((aliceRoot.CFrame.Position - arrival).Magnitude < 3, "not placed in the B1 elevator")
	assert(p.Tutorial.Step == 1 and not p.Tutorial.Done, "tutorial state")
	assert(alice:GetAttribute("V_Count") == 0 and alice:GetAttribute("V_Capacity") == 10, "stack attributes")
end)

check("collect: server checks distance, depth and cooldown; value fixed at pickup; model pooled", function()
	local p = DS.getProfile(alice)
	local entry = nearestItem(1, V3.new(0, 0, 0))
	-- Too far: standing at the elevator.
	moveTo(aliceRoot, world.depths[1].elevator.arrival.Position)
	local ok, reason = LS.collect(alice, entry.id)
	assert(not ok and reason == "too far", "collected from across the room: " .. tostring(reason))
	-- Another depth's item.
	local deep = nearestItem(2, V3.new(0, world.depths[2].y0, 0))
	moveTo(aliceRoot, entry.position + V3.new(0, 2.5, 0))
	ok, reason = LS.collect(alice, deep.id)
	assert(not ok, "collected an item on another depth")
	-- Junk ids.
	assert(not LS.collect(alice, 0 / 0) and not LS.collect(alice, "x") and not LS.collect(alice, -5), "junk id accepted")
	local model = entry.model
	local before = LS.count(1)
	grab(alice, aliceRoot, entry)
	assert(p.Carried.Count == 1 and p.Carried.Items[entry.def.Id] == 1, "pickup not carried")
	assert(p.Carried.Value == Economy.itemValue(entry.def, DS.stats(alice)), "value not fixed at pickup")
	assert(LS.get(entry.id) == nil and model.Parent == nil and LS.count(1) == before - 1, "item not removed from the world")
	assert(count("Collected", nil) >= 1 and count("Inventory", nil, alice) >= 1, "clients not told")
	assert(alice:GetAttribute("V_Count") == 1 and string.find(alice:GetAttribute("V_Stack"), "Cash=1", 1, true), "stack attribute not updated")
	-- Cooldown: a second pickup straight away is refused, after the interval it works.
	local second = nearestItem(1, entry.position)
	moveTo(aliceRoot, second.position + V3.new(0, 2.5, 0))
	ok, reason = LS.collect(alice, second.id)
	assert(not ok and reason == "cooldown", "no pickup cooldown: " .. tostring(reason))
	advance(0.7)
	ok = LS.collect(alice, second.id)
	assert(ok and p.Carried.Count == 2, "pickup after the cooldown failed")
	-- Pool: a respawn reuses a released model.
	local reusedBefore = LS.Debug.reused
	tick(6)
	assert(LS.Debug.reused > reusedBefore, "models are not pooled")
end)

check("two-player race for the same item: exactly one gets it", function()
	bob, bobRoot = makePlayer("Bob")
	advance(1)
	for _ = 1, 5 do
		local entry = nearestItem(1, V3.new(20, 0, 10))
		local a0, b0 = DS.getProfile(alice).Carried.Count, DS.getProfile(bob).Carried.Count
		moveTo(aliceRoot, entry.position + V3.new(0.5, 2.5, 0))
		moveTo(bobRoot, entry.position + V3.new(-0.5, 2.5, 0))
		remotes.Collect.OnServerEvent:Fire(alice, entry.id)
		remotes.Collect.OnServerEvent:Fire(bob, entry.id)
		flushDeferred()
		local gained = (DS.getProfile(alice).Carried.Count - a0) + (DS.getProfile(bob).Carried.Count - b0)
		assert(gained == 1, "race produced " .. gained .. " pickups")
		advance(0.7)
	end
end)

-- Collects until the stack is full (real pickups, real cooldown).
local function fillStack(player, root, depth)
	local p = DS.getProfile(player)
	for _ = 1, 400 do
		if p.Carried.Slots >= DS.stats(player).Capacity then
			return true
		end
		local entry = nearestItem(depth, root.CFrame.Position, function(e)
			return Economy.slotsFor(e.def, DS.stats(player)) + p.Carried.Slots <= DS.stats(player).Capacity
		end)
		if not entry then
			tick(3)
		else
			grab(player, root, entry)
			advance(0.7)
		end
	end
	return p.Carried.Slots >= DS.stats(player).Capacity
end

check("capacity: a full stack refuses pickups, says so once, counts a full stack", function()
	assert(fillStack(alice, aliceRoot, 1), "could not fill the stack")
	local p = DS.getProfile(alice)
	assert(p.Carried.Slots <= DS.stats(alice).Capacity, "over capacity")
	assert((p.Stats.FullStacks or 0) == 1, "full stack not counted")
	local popups = count("Popup", "StackFull", alice)
	local entry = nearestItem(1, aliceRoot.CFrame.Position)
	moveTo(aliceRoot, entry.position + V3.new(0, 2.5, 0))
	local ok, reason = LS.collect(alice, entry.id)
	assert(not ok and reason == "full", "collected past capacity")
	assert(LS.get(entry.id), "a refused item must stay in the world")
	advance(0.5)
	LS.collect(alice, entry.id)
	assert(count("Popup", "StackFull", alice) - popups <= 1, "full notice spammed")
end)

check("deposit: prompt pays exactly once; a duplicate request and the auto zone add nothing", function()
	local p = DS.getProfile(alice)
	local machine = world.machines.D1_1
	local value = p.Carried.Value
	local expected = Economy.depositPayout(value, DS.stats(alice))
	-- Anywhere the machine's prompt can be triggered (at root height) passes the range check.
	local promptPos = machine.prompt.Parent.Position
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local at = V3.new(promptPos.X + math.cos(a) * machine.prompt.MaxActivationDistance, machine.cframe.Position.Y + 3, promptPos.Z + math.sin(a) * machine.prompt.MaxActivationDistance)
		assert((at - machine.cframe.Position).Magnitude <= GameConfig.DepositRange, "prompt reaches past the server's deposit range")
	end
	-- Too far away first.
	moveTo(aliceRoot, V3.new(30, 3, 20))
	assert(not DepS.deposit(alice, "D1_1"), "deposited from across the room")
	-- Turn the auto-deposit zone on and stand in it, then also press the prompt the same frame.
	p.Settings.AutoDeposit = true
	moveTo(aliceRoot, machine.zone.cframe.Position)
	assert(DepS.inZone(machine, aliceRoot.CFrame.Position), "zone check")
	machine.prompt.Triggered:Fire(alice)
	remotes.Deposit.OnServerEvent:Fire(alice, "D1_1")
	tick(2)
	assert(p.Cash == expected, string.format("paid %d, expected exactly %d", p.Cash, expected))
	assert(p.Carried.Count == 0 and p.Carried.Value == 0 and p.Carried.Slots == 0, "stack not emptied")
	assert(count("Deposited", nil) == 1, "deposit announced " .. count("Deposited", nil) .. " times")
	assert(p.BestDeposit == expected and (p.Stats.Deposits or 0) == 1, "record / stats")
	local summary = lastFor("Deposited").args[2]
	assert(summary.payout == expected and summary.record == true and summary.count > 0, "summary")
	assert(alice:GetAttribute("V_Count") == 0 and alice:GetAttribute("V_Stack") == "", "stack visuals not cleared")
	-- Wrong depth machine.
	grab(alice, aliceRoot, nearestItem(1, aliceRoot.CFrame.Position))
	moveTo(aliceRoot, world.machines.D2_1.cframe.Position + V3.new(0, 3, 4))
	assert(not DepS.deposit(alice, "D2_1"), "deposited on a depth that isn't unlocked (teleported there)")
	local deepItem = nearestItem(2, aliceRoot.CFrame.Position)
	moveTo(aliceRoot, deepItem.position + V3.new(0, 2.5, 0))
	advance(1)
	assert(not LS.collect(alice, deepItem.id), "collected on a depth that isn't unlocked")
	p.Settings.AutoDeposit = false
end)

check("upgrades: server price, stats change, locked ones refused, spam can't overspend", function()
	local p = DS.getProfile(alice)
	p.Cash = 1000
	local capBefore = DS.stats(alice).Capacity
	local price = Economy.upgradeCost("CarryCapacity", 0)
	local ok = US.buy(alice, "CarryCapacity")
	assert(ok and p.Upgrades.CarryCapacity == 1 and p.Cash == 1000 - price, "upgrade not bought at the server price")
	assert(DS.stats(alice).Capacity > capBefore, "capacity did not change")
	assert(alice:GetAttribute("V_Capacity") == DS.stats(alice).Capacity, "capacity attribute")
	local moveBefore = alice.Character.Humanoid.WalkSpeed
	p.Cash += 500
	US.buy(alice, "MoveSpeed")
	assert(alice.Character.Humanoid.WalkSpeed > moveBefore, "walk speed not applied")
	-- Locked until a deeper depth.
	p.Cash = 1e9
	local okMagnet, msg = US.buy(alice, "CashMagnet")
	assert(not okMagnet and string.find(msg, "unlocks", 1, true), "magnet bought on B1")
	assert(not US.buy(alice, "AutoCollect"), "auto-collect bought on B1")
	-- Spam: 30 requests in one frame through the remote.
	p.Cash = 5000
	local level0 = p.Upgrades.PickupSpeed or 0
	for _ = 1, 30 do
		remotes.BuyUpgrade.OnServerEvent:Fire(alice, "PickupSpeed")
	end
	local bought = (p.Upgrades.PickupSpeed or 0) - level0
	assert(bought >= 1 and bought <= 4, "spam bought " .. bought .. " levels")
	assert(p.Cash >= 0, "cash went negative")
	-- Junk arguments.
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, { "x" })
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, nil)
	remotes.BuyPerk.OnServerEvent:Fire(alice, "GoldenTouch") -- 0 tokens
	assert((p.Perks.GoldenTouch or 0) == 0, "perk bought without tokens")
end)

check("depths: unlock in order with both prices; elevator validates and moves the rider", function()
	local p = DS.getProfile(alice)
	p.Cash = 1000
	assert(not US.unlockDepth(alice, 2), "unlocked without the money")
	p.Cash = DepthConfig.get(2).UnlockCash + 50
	assert(not US.unlockDepth(alice, 3), "skipped a depth")
	assert(US.unlockDepth(alice, 2) and p.HighestDepth == 2 and p.Cash == 50, "unlock B2")
	assert(not US.unlockDepth(alice, 2), "unlocked twice")
	assert(count("Popup", "DepthUnlocked", alice) == 1, "unlock popup")
	-- Tokens are required too (B4).
	p.Cash = 1e12
	US.unlockDepth(alice, 3)
	p.Tokens = 0
	assert(not US.unlockDepth(alice, 4) and p.HighestDepth == 3 and p.Cash == 1e12 - DepthConfig.get(3).UnlockCash, "B4 unlocked without tokens or cash taken")
	-- Travel: locked floors refused; must be at the cabin.
	assert(not ES.travel(alice, 5), "travelled to a locked floor")
	moveTo(aliceRoot, V3.new(30, 3, 30))
	assert(not ES.travel(alice, 2), "travelled from across the room")
	moveTo(aliceRoot, world.depths[1].elevator.arrival.Position)
	advance(2)
	local ok, duration = ES.travel(alice, 2)
	assert(ok and duration > 1 and duration <= 3.6, "travel refused at the cabin")
	assert(not ES.travel(alice, 3), "second ride while riding")
	local depart = lastFor("Elevator", alice)
	assert(depart.args[1] == "Depart" and depart.args[2].to == 2, "no Depart")
	tick(duration * 0.5)
	assert(registry.PlayerService.depthOf(alice) == 1, "moved before the ride ended")
	tick(duration * 0.5 + 0.2)
	assert(lastFor("Elevator", alice).args[1] == "Arrive", "no Arrive")
	assert(registry.PlayerService.depthOf(alice) == 2 and p.CurrentDepth == 2, "not on B2 after the ride")
	assert((aliceRoot.CFrame.Position - world.depths[2].elevator.arrival.Position).Magnitude < 3, "not in the B2 cabin")
	assert((p.Stats["Visit:2"] or 0) == 1, "visit stat")
end)

check("deeper loot is worth more (same player, same upgrades)", function()
	local stats = DS.stats(alice)
	local function avg(depth)
		local sum, n = 0, 0
		for _, entry in pairs(LS.items(depth)) do
			sum += Economy.itemValue(entry.def, stats) / Economy.slotsFor(entry.def, stats)
			n += 1
		end
		return sum / n
	end
	for d = 2, 7 do
		assert(avg(d) > avg(d - 1) * 3, "depth " .. d .. " loot is not worth clearly more")
	end
	local p = DS.getProfile(alice)
	local before = p.Carried.Value
	local count0 = p.Carried.Count
	local entry = nearestItem(2, aliceRoot.CFrame.Position)
	advance(1)
	grab(alice, aliceRoot, entry)
	assert(p.Carried.Count == count0 + 1 and p.Carried.Value - before >= LootConfig.ById.GoldBar.Value, "B2 pickup")
end)

check("magnet pulls loot toward its owner; auto-collect picks up nearby loot", function()
	local p = DS.getProfile(alice)
	p.HighestDepth = 5
	p.Upgrades.CashMagnet = 4
	p.Upgrades.AutoCollect = 3
	p.Upgrades.CarryCapacity = 30
	local stats = DS.stats(alice)
	assert(stats.MagnetRadius > 0 and stats.AutoRadius > 0, "stats")
	-- Stand in the middle of B2's chamber and let the magnet work.
	local spot = nearestItem(2, V3.new(0, world.depths[2].y0 - 20, 10)).position + V3.new(0, 2.5, 0)
	moveTo(aliceRoot, spot)
	local entry = nearestItem(2, spot, function(e)
		local flat = V3.new(e.position.X - spot.X, 0, e.position.Z - spot.Z).Magnitude
		return flat > 3 and flat < stats.MagnetRadius - 1 and not e.pulledBy
	end)
	assert(entry, "no item in magnet range")
	local d0 = V3.new(entry.position.X - spot.X, 0, entry.position.Z - spot.Z).Magnitude
	local collected0 = p.Stats.Collect or 0
	tick(0.5)
	local still = LS.get(entry.id)
	if still then
		local d1 = V3.new(still.position.X - spot.X, 0, still.position.Z - spot.Z).Magnitude
		assert(d1 < d0, "magnet did not pull")
		assert(still.pulledBy == alice, "pulled item not reserved")
		-- Bob can't snatch an item alice's magnet is pulling.
		moveTo(bobRoot, still.position + V3.new(0, 2.5, 0))
		DS.getProfile(bob).HighestDepth = 2
		DS.getProfile(bob).CurrentDepth = 2
		advance(1)
		local ok, reason = LS.collect(bob, still.id)
		assert(not ok and reason == "reserved", "reserved item taken by another player: " .. tostring(reason))
		moveTo(bobRoot, V3.new(-30, 3, 0))
	end
	tick(4)
	assert((p.Stats.Collect or 0) > collected0, "auto-collect / magnet never collected anything")
	-- A full stack: Auto-Collect stops instead of repeating the "stack full" notice.
	local slots0 = p.Carried.Slots
	p.Carried.Slots = DS.stats(alice).Capacity
	local fullPopups = count("Popup", "StackFull", alice)
	local collectedFull = p.Stats.Collect or 0
	tick(6)
	assert(count("Popup", "StackFull", alice) == fullPopups, "auto-collect spammed the full notice")
	assert((p.Stats.Collect or 0) == collectedFull, "auto-collect picked up past capacity")
	p.Carried.Slots = slots0
	p.Upgrades.CashMagnet, p.Upgrades.AutoCollect, p.Upgrades.CarryCapacity = nil, nil, 1
	p.HighestDepth = 3
end)

check("rare events: one at a time, announced, per-depth cooldown, expire cleanly", function()
	local function waitClear()
		for _ = 1, 3 do
			if not LS.rareEntry() then
				return
			end
			advance(GameConfig.RareEvent.Lifetime + 1)
			tick(0.2)
		end
	end
	waitClear()
	local spawned = count("RareEvent", "Spawn")
	local entry = LS.rareEntry() or LS.spawnRare(2)
	assert(entry and entry.def.Special and entry.def.Depth == entry.depth, "spawnRare")
	local spawnDepth, spawnedAt = entry.depth, clock
	assert(count("RareEvent", "Spawn") >= spawned + 1 or entry ~= nil, "not announced")
	assert(LS.spawnRare(3) == nil, "two rare events at once")
	advance(GameConfig.RareEvent.Lifetime + 1)
	tick(0.2)
	assert(LS.get(entry.id) == nil and LS.rareEntry() ~= entry, "rare item did not expire")
	assert(count("RareEvent", "Gone") >= 1, "expiry not announced")
	-- Run the background timer: the same depth must not get another event inside its cooldown.
	local seen = #log.RareEvent
	for _ = 1, 120 do
		advance(5)
		tick(0.1)
		for i = seen + 1, #log.RareEvent do
			local e = log.RareEvent[i]
			if e.args[1] == "Spawn" and e.args[2].depth == spawnDepth then
				assert(clock - spawnedAt >= GameConfig.RareEvent.DepthCooldown, string.format("B%d repeated after %.0f s (cooldown %d)", spawnDepth, clock - spawnedAt, GameConfig.RareEvent.DepthCooldown))
			end
		end
		seen = #log.RareEvent
	end
	assert(count("RareEvent", "Spawn") > spawned + 1, "the background timer never spawned an event in 10 minutes")
	-- Collecting a special pays tokens and announces it.
	waitClear()
	local special = LS.spawnRare(1)
	assert(special, "could not spawn on B1")
	local tokens = DS.getProfile(bob).Tokens
	advance(1)
	moveTo(bobRoot, special.position + V3.new(0, 2.5, 0))
	local ok, reason = LS.collect(bob, special.id)
	assert(ok, "special not collected: " .. tostring(reason))
	assert(DS.getProfile(bob).Tokens > tokens and count("Popup", "RareFind", bob) >= 1, "special find reward")
	assert(LS.rareEntry() == nil, "rare entry not cleared after collection")
	DS.getProfile(bob).Carried = DS.emptyCarried()
end)

check("collection book and achievements fire once each", function()
	local p = DS.getProfile(alice)
	local discoveries = {}
	for _, entry in ipairs(log.Popup) do
		if entry.player == alice and entry.args[1] == "Discovery" then
			local id = entry.args[2].id
			assert(not discoveries[id], id .. " discovered twice")
			discoveries[id] = true
		end
	end
	assert(discoveries.Bill or discoveries.CashStack, "B1 discovery missing")
	for id in pairs(discoveries) do
		assert(p.Book[id] and p.Book[id].n >= 1, id .. " not in the book")
	end
	local achieved = {}
	for _, entry in ipairs(log.Popup) do
		if entry.player == alice and entry.args[1] == "Achievement" then
			local id = entry.args[2].id
			assert(not achieved[id], id .. " awarded twice")
			achieved[id] = true
		end
	end
	assert(achieved.FirstPickup and achieved.FirstDeposit and achieved.FirstUpgrade and achieved.FirstFullStack and achieved.FirstNewDepth, "first achievements")
	local tokens = p.Tokens
	DS.bump(alice, "Collect", 1)
	DS.bump(alice, "Deposits", 1)
	assert(p.Tokens == tokens, "achievement paid twice")
	assert(p.Stats.Discovered and p.Stats.Discovered >= 2, "discovered stat")
end)

check("daily challenges: UTC roll, progress, reward exactly once; codes once", function()
	local p = DS.getProfile(alice)
	QS.ensureDaily(alice)
	assert(#p.Daily.List == QuestConfig.Daily.Count, "daily list")
	local c = p.Daily.List[1]
	local cash, tokens = p.Cash, p.Tokens
	DS.bump(alice, c.Stat, c.Target + 5)
	assert(c.Done and p.Cash >= cash + c.Cash and p.Tokens >= tokens + c.Tokens, "daily not rewarded")
	local cash2 = p.Cash
	DS.bump(alice, c.Stat, c.Target)
	assert(p.Cash == cash2, "daily rewarded twice")
	local ok = QS.redeem(alice, "release")
	assert(ok, "code RELEASE")
	local cash3 = p.Cash
	assert(not QS.redeem(alice, "RELEASE") and p.Cash == cash3, "code used twice")
	assert(not QS.redeem(alice, string.rep("A", 5000)) and not QS.redeem(alice, 5), "junk code")
end)

check("rebirth: needs depth + earnings AND typed confirmation; resets exactly what it says", function()
	local p = DS.getProfile(alice)
	p.HighestDepth = 3
	assert(not US.rebirth(alice, "REBIRTH"), "rebirth before B4")
	p.HighestDepth = 4
	p.EarnedSinceRebirth = UpgradeConfig.rebirthRequirement(0)
	p.Cash = 777
	p.Tokens = 3
	p.Perks.DeepPockets = 1
	local bookSize = 0
	for _ in pairs(p.Book) do
		bookSize += 1
	end
	assert(not US.rebirth(alice, nil) and not US.rebirth(alice, "rebirth?") and p.Rebirths == 0, "rebirth without confirmation")
	local ok = US.rebirth(alice, "REBIRTH")
	assert(ok and p.Rebirths == 1, "rebirth refused")
	assert(p.Cash == 0 and next(p.Upgrades) == nil and p.HighestDepth == 1 and p.CurrentDepth == 1 and p.Carried.Count == 0, "reset incomplete")
	assert(p.Tokens >= 3 + UpgradeConfig.Rebirth.Tokens and p.Perks.DeepPockets == 1, "tokens / perks not kept")
	local kept = 0
	for _ in pairs(p.Book) do
		kept += 1
	end
	assert(kept == bookSize, "book not kept")
	assert(math.abs(DS.stats(alice).ValueMult - 1.25) < 1e-6, "rebirth bonus")
	assert(registry.PlayerService.depthOf(alice) == 1, "not sent back to B1")
	assert(not US.rebirth(alice, "REBIRTH"), "second rebirth without new earnings")
end)

local function receipt(player, purchaseId)
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = BOOST_PRODUCT, PurchaseId = purchaseId })
end
check("receipts: granted exactly once, refused when the profile can't persist live", function()
	local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	local notYet = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	local p = DS.getProfile(alice)
	assert(receipt(alice, "r-1") == granted, "first receipt")
	local boost = p.BoostUntil
	assert(boost > fakeOs.time() and p.Receipts["r-1"], "boost not granted")
	assert(receipt(alice, "r-1") == granted and p.BoostUntil == boost, "retry granted twice")
	for i = 2, 8 do
		receipt(alice, "r-" .. i)
	end
	assert(p.BoostUntil <= fakeOs.time() + ShopConfig.BoostMax, "boost exceeded its cap")
	isStudio = false
	local decision = receipt(bob, "r-live")
	isStudio = true
	assert(decision == notYet and DS.getProfile(bob).BoostUntil == 0, "live purchase granted on a non-persistent profile")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 999999, ProductId = BOOST_PRODUCT, PurchaseId = "x" }) == notYet, "unknown player")
	-- Shop items with id 0: Studio grants for testing, a live game refuses.
	isStudio = false
	registry.ShopService.buy(bob, "GoldenGlow")
	isStudio = true
	assert(not DS.getProfile(bob).Cosmetics.Owned["Theme:GoldenGlow"], "id-0 product granted in a live game")
	-- stats() (used inside atomic claims / deposits) never calls the yielding pass lookup, and
	-- a failed lookup is cached instead of retried on every call.
	local vip = ShopConfig.Passes[1]
	local market = stubServices.MarketplaceService
	local lookups, ownsAsync = 0, market.UserOwnsGamePassAsync
	vip.PassId = 4242
	market.UserOwnsGamePassAsync = function()
		lookups += 1
		error("throttled")
	end
	registry.ShopService.onPlayerRemoving(bob)
	DS.stats(bob)
	assert(lookups == 0, "stats() made a pass lookup")
	registry.ShopService.ownsPass(bob, "VIP")
	registry.ShopService.ownsPass(bob, "VIP")
	assert(lookups == 1, "a failed pass lookup was retried on every call")
	vip.PassId = 0
	market.UserOwnsGamePassAsync = ownsAsync
	-- Cosmetics never change stats.
	local before = DS.stats(bob)
	registry.ShopService.buy(bob, "GoldenGlow")
	registry.ShopService.equip(bob, "Theme", "GoldenGlow")
	local after = DS.stats(bob)
	for k, v in pairs(before) do
		assert(after[k] == v, "cosmetic changed " .. k)
	end
	assert(bob:GetAttribute("V_Theme") == "GoldenGlow", "theme attribute")
	assert(not registry.ShopService.equip(bob, "Theme", "NeonVault"), "equipped an unowned theme")
end)

check("settings and junk remotes: only legal values saved, nothing breaks", function()
	local p = DS.getProfile(bob)
	local cash0, depth0, rebirths0 = p.Cash, p.HighestDepth, p.Rebirths
	remotes.SaveSettings.OnServerEvent:Fire(bob, { Music = 0.3, Master = 7, Effects = 0 / 0, CameraShake = "yes", AutoDeposit = true, Hack = true })
	assert(p.Settings.Music == 0.3 and p.Settings.Master == 1 and p.Settings.Effects == 1, "numbers not validated")
	assert(p.Settings.CameraShake == true and p.Settings.AutoDeposit == true and p.Settings.Hack == nil, "settings")
	remotes.SaveSettings.OnServerEvent:Fire(bob, "nope")
	remotes.Collect.OnServerEvent:Fire(bob, { 1 })
	remotes.Collect.OnServerEvent:Fire(bob, math.huge)
	remotes.Deposit.OnServerEvent:Fire(bob, 42)
	remotes.Travel.OnServerEvent:Fire(bob, 0 / 0)
	remotes.Travel.OnServerEvent:Fire(bob, "B7")
	remotes.UnlockDepth.OnServerEvent:Fire(bob, -1)
	remotes.Rebirth.OnServerEvent:Fire(bob, { "REBIRTH" })
	remotes.BuyCosmetic.OnServerEvent:Fire(bob, "Theme", "GoldenGlow")
	remotes.Equip.OnServerEvent:Fire(bob, 1, 2)
	remotes.ShopBuy.OnServerEvent:Fire(bob, string.rep("x", 300))
	remotes.Tutorial.OnServerEvent:Fire(bob, {})
	remotes.RedeemCode.OnServerEvent:Fire(bob, nil)
	flushDeferred()
	assert(p.Cash == cash0 and p.HighestDepth == depth0 and p.Rebirths == rebirths0, "junk changed the profile")
end)

check("death and leaving: rides cancel, carried loot is kept, pulls released, no errors", function()
	-- Death mid-ride: the ride is cancelled; the carried stack stays (rule: loot is kept on death).
	local p = DS.getProfile(bob)
	p.HighestDepth = 2
	p.CurrentDepth = 1
	advance(1)
	local entry = nearestItem(1, V3.new(0, 0, 0))
	grab(bob, bobRoot, entry)
	local carried = p.Carried.Count
	assert(carried >= 1, "bob carries nothing")
	moveTo(bobRoot, world.depths[1].elevator.arrival.Position)
	advance(2)
	assert(ES.travel(bob, 2), "ride refused")
	local humanoid = bob.Character.Humanoid
	humanoid.Health = 0
	humanoid.Died:Fire()
	assert(not ES.isRiding(bob) and lastFor("Elevator", bob).args[1] == "Cancel", "ride not cancelled on death")
	tick(4)
	assert(registry.PlayerService.depthOf(bob) == 1 and p.CurrentDepth == 1, "a dead rider arrived")
	assert(p.Carried.Count == carried, "carried loot lost on death")
	-- Respawn: placed back in the elevator of the saved depth.
	local root = makeCharacter(bob, V3.new(0, 80, 0))
	bobRoot = root
	assert((root.CFrame.Position - world.depths[1].elevator.arrival.Position).Magnitude < 3, "respawn not placed at the saved depth")
	-- Leave mid-ride and mid-magnet.
	local carl, carlRoot = makePlayer("Carl")
	local cp = DS.getProfile(carl)
	cp.HighestDepth = 3
	cp.Upgrades.CashMagnet = 5
	moveTo(carlRoot, world.depths[1].elevator.arrival.Position)
	advance(2)
	assert(ES.travel(carl, 3), "carl ride")
	local item = nearestItem(1, V3.new(0, 0, 0))
	item.pulledBy = carl
	item.pulledAt = clock
	local warnsBefore = handlerErrors
	leave(carl)
	tick(5)
	assert(handlerErrors == warnsBefore, "errors while cleaning up a leaving player")
	assert(LS.get(item.id) == nil or LS.get(item.id).pulledBy == nil, "pull not released on leave")
	assert(not ES.isRiding(carl) and DS.getProfile(carl) == nil, "leaver not cleaned up")
	-- Collect / deposit for a player who has left does nothing.
	assert(not LS.collect(carl, item.id) and not DepS.deposit(carl, "D1_1"), "acted for a departed player")
end)

check("safety: out-of-bounds and locked-depth players return to the rim; walking down records the depth", function()
	local PS = registry.PlayerService
	local dana, danaRoot = makePlayer("Dana")
	local p = DS.getProfile(dana)
	local rim1 = world.depths[1].elevator.arrival.Position
	-- In the pool and on the rim: left alone.
	moveTo(danaRoot, V3.new(0, Pools.surface(20) + 3, 20))
	advance(1)
	PS.step(1)
	assert((danaRoot.CFrame.Position - V3.new(0, Pools.surface(20) + 3, 20)).Magnitude < 0.01, "a player in the pool was moved")
	-- Fell under the pool / out of the map: back on the rim.
	local rescues = PS.Rescues
	for _, pos in ipairs({ V3.new(0, -60, 0), V3.new(200, 3, 0), V3.new(0, 3, 400), V3.new(-60, -30, 20) }) do
		moveTo(danaRoot, pos)
		advance(1)
		PS.step(1)
		assert((danaRoot.CFrame.Position - rim1).Magnitude < 3, "not rescued from " .. tostring(pos))
	end
	assert(PS.Rescues == rescues + 4, "rescue count")
	-- Past a locked door onto B2: rescued; once B2 is unlocked, walking down counts as arriving.
	local rim2 = world.depths[2].y0
	moveTo(danaRoot, V3.new(Pools.Tunnel.arrivalX, rim2 + 3, GameConfig.RoomBack - 4))
	advance(1)
	PS.step(1)
	assert((danaRoot.CFrame.Position - rim1).Magnitude < 3 and p.CurrentDepth == 1, "a player walked onto a locked depth")
	p.HighestDepth = 2
	moveTo(danaRoot, V3.new(Pools.Tunnel.arrivalX, rim2 + 3, GameConfig.RoomBack - 4))
	advance(1)
	PS.step(1)
	assert(p.CurrentDepth == 2 and (p.Stats["Visit:2"] or 0) >= 1, "walking down to B2 was not recorded")
	assert(registry.PlayerService.depthOf(dana) == 2 and (danaRoot.CFrame.Position - V3.new(Pools.Tunnel.arrivalX, rim2 + 3, GameConfig.RoomBack - 4)).Magnitude < 0.01, "a legitimate walker was moved")
	-- The deep-end chute pays 85%.
	local chute = world.machines.D2_B
	assert(chute and chute.bottom and math.abs(chute.payoutFactor - Pools.ChutePayout) < 1e-9, "B2 chute machine")
	local entry = nearestItem(2, V3.new(0, rim2 - 42, 40))
	advance(1)
	grab(dana, danaRoot, entry)
	local value = p.Carried.Value
	assert(value > 0, "dana carries nothing")
	moveTo(danaRoot, chute.zone.cframe.Position)
	advance(1)
	local cash = p.Cash
	local ok, summary = DepS.deposit(dana, "D2_B")
	assert(ok and summary.chute and p.Cash - cash == math.floor(Economy.depositPayout(value, DS.stats(dana)) * Pools.ChutePayout + 0.5), "chute payout")
	leave(dana)
end)

check("session lock: load locks, a taken-over profile stops saving, leaving unlocks", function()
	local stored = {}
	local function copy(v)
		if type(v) ~= "table" then
			return v
		end
		local t = {}
		for k, x in pairs(v) do
			t[k] = copy(x)
		end
		return t
	end
	local fakeStore = {
		UpdateAsync = function(_, k, fn)
			local new = fn(copy(stored[k]))
			if new ~= nil then
				stored[k] = copy(new)
			end
			return copy(new)
		end,
	}
	stubServices.DataStoreService.GetDataStore = function()
		return fakeStore
	end
	DS.init(registry)
	local ok, err = pcall(function()
		stored["player_" .. (nextUserId + 1)] = { Cash = 777, Upgrades = { LootValue = 999, Bogus = 3 }, HighestDepth = 99, CurrentDepth = 5, Carried = { Items = { Bill = 3, Fake = 9 }, Value = 30 } }
		local erin = makePlayer("Erin")
		local key = "player_" .. erin.UserId
		local p = DS.getProfile(erin)
		assert(DS.isPersistent(erin) and p.Cash == 777, "saved profile not loaded")
		assert(p.Upgrades.LootValue == UpgradeConfig.ByKey.LootValue.Max and p.Upgrades.Bogus == nil, "upgrades not validated")
		assert(p.HighestDepth == 7 and p.CurrentDepth == 5, "depth not clamped")
		assert(p.Carried.Count == 3 and p.Carried.Items.Fake == nil, "carried stack not validated")
		assert(type(stored[key].Lock) == "table", "profile not locked on load")
		p.Cash = 800
		assert(DS.save(erin) and stored[key].Cash == 800, "save failed")
		stored[key].Lock = { Session = "other-server", At = fakeOs.time() }
		p.Cash = 1
		assert(not DS.save(erin), "saved over another server's lock")
		assert(stored[key].Cash == 800 and not DS.isPersistent(erin), "still persistent after losing the lock")
		isStudio = false
		local decision = receipt(erin, "lock-1")
		isStudio = true
		assert(decision == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "granted after losing the lock")
		leave(erin)
		assert(stored[key].Cash == 800, "left player overwrote the new owner")
		stored["player_" .. (nextUserId + 1)] = { Cash = 55, Lock = { Session = "crashed", At = fakeOs.time() - 100000 } }
		local finn = makePlayer("Finn")
		local finnKey = "player_" .. finn.UserId
		assert(DS.isPersistent(finn) and DS.getProfile(finn).Cash == 55, "stale lock blocked the load")
		-- A persistent receipt is saved before it is acknowledged.
		assert(receipt(finn, "p-1") == roblox.Enum.ProductPurchaseDecision.PurchaseGranted and stored[finnKey].Receipts["p-1"], "receipt not saved before granting")
		DS.getProfile(finn).Cash = 99
		leave(finn)
		assert(stored[finnKey].Cash == 99 and stored[finnKey].Lock == nil, "leave save did not persist and unlock")
		-- Leaving mid-receipt: refused so Roblox retries later.
		stored["player_" .. (nextUserId + 1)] = { Cash = 5 }
		local gus = makePlayer("Gus")
		fakePlayers.PlayerRemoving:Fire(gus) -- leave hooks run, profile released
		assert(receipt(gus, "late") == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "late receipt granted")
		leave(gus)
	end)
	stubServices.DataStoreService.GetDataStore = function()
		error("DataStores are not available in the harness")
	end
	DS.init(registry)
	assert(ok, err)
end)

check("analytics: onboarding funnel steps logged once each", function()
	local seen = {}
	for _, a in ipairs(analytics) do
		if a.player == alice then
			assert(not seen[a.name], a.name .. " logged twice")
			seen[a.name] = true
		end
	end
	for _, name in ipairs({ "FirstPickup", "FirstFullStack", "FirstDeposit", "FirstUpgrade", "FirstNewDepth", "FirstRebirth" }) do
		assert(seen[name], name .. " not logged")
	end
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise (Main.client order) and handle real server traffic", function()
	local snapshot = DS.sendProfileNow(bob)
	assert(snapshot and snapshot.daily and snapshot.rebirth and snapshot.owned and snapshot.settings, "snapshot incomplete")
	requireModule(Shared.Net).setup()
	-- Client remotes route straight into the server handlers (as bob).
	roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
		remotes[self.Name].OnServerEvent:Fire(bob, ...)
	end)
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = bob
	fakePlayers.LocalPlayer = bob
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera
	local clientRoot = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("VaultClient")
	local folder = clientRoot:FindFirstChild("Controllers")
	-- Same order as Main.client.
	local mainSource = clientRoot:FindFirstChild("Main").Source
	local names = {}
	for name in string.gmatch(string.match(mainSource, "local ORDER = (%b{})"), "\"(%w+)\"") do
		table.insert(names, name)
	end
	assert(#names == 11, "expected 11 controllers in Main.client, found " .. #names)
	local c = {}
	for _, name in ipairs(names) do
		c[name] = requireModule(folder[name])
		local ok, err = pcall(c[name].init)
		assert(ok, name .. ".init failed: " .. tostring(err))
	end
	local CS = c.ClientState
	CS.profile = snapshot
	CS.settings = table.clone(snapshot.settings)
	CS.inventory = LS.inventoryView(bob)
	CS.ProfileChanged:Fire(snapshot)
	CS.InventoryChanged:Fire(CS.inventory)
	for _, name in ipairs({ "VaultHud", "VaultMenus", "VaultElevator", "VaultTutorial" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
	end
	-- Targeting finds the nearest item in reach and the pickup button sends a real claim.
	local entry = nearestItem(1, V3.new(10, 0, 10))
	moveTo(bobRoot, entry.position + V3.new(0, 2.5, 0))
	advance(1)
	c.CollectController.refresh()
	local target = c.CollectController.target()
	assert(target and target.id == entry.id, "client did not target the nearest item")
	local before = DS.getProfile(bob).Carried.Count
	c.InputController.setHeld("touch", true)
	c.InputController.setHeld("touch", false)
	assert(DS.getProfile(bob).Carried.Count == before + 1, "client pickup did not reach the server")
	-- Feed the server's own messages to the client.
	local collected = lastFor("Collected").args
	CS.Collected:Fire(collected[1], collected[2], collected[3], collected[4], collected[5])
	CS.inventory = LS.inventoryView(bob)
	CS.InventoryChanged:Fire(CS.inventory)
	-- Carried stack visuals: pieces welded to the root, mode changes with the count.
	local StackLayout = requireModule(Shared.StackLayout)
	bob:SetAttribute("V_Stack", "Cash=30;Gold=8")
	c.StackController.refreshAll()
	advance(0.5)
	flushDeferred()
	local stack = bob.Character:FindFirstChild("CarriedStack")
	assert(stack, "no carried stack model")
	local pieces = 0
	for _, d in ipairs(stack:GetChildren()) do
		if d:IsA("Model") then
			pieces += 1
			local root = d:FindFirstChild("PieceRoot")
			assert(root and root:FindFirstChildOfClass("Weld") and root:FindFirstChildOfClass("Weld").Part0 == bobRoot, "piece not welded to the root")
		end
	end
	assert(pieces == #StackLayout.layout({ Cash = 30, Gold = 8 }, 24).pieces, "piece count")
	bob:SetAttribute("V_Stack", "Gold=200")
	c.StackController.refreshAll()
	assert(stack:FindFirstChild("CarryCrate"), "crate mode not shown")
	bob:SetAttribute("V_Stack", "")
	c.StackController.refreshAll()
	assert(not bob.Character:FindFirstChild("CarriedStack"), "empty stack not cleared")
	-- Deposit, elevator, rare event, popups and toasts from real payloads.
	DS.getProfile(bob).Settings.AutoDeposit = false
	moveTo(bobRoot, world.machines.D1_1.zone.cframe.Position)
	assert(DepS.deposit(bob, "D1_1"), "bob deposit")
	local dep = lastFor("Deposited").args
	CS.Deposited:Fire(dep[1], dep[2])
	flushDeferred()
	CS.ElevatorEvent:Fire("Depart", { from = 1, to = 2, duration = 1.75, code = "B2", name = "Gold Reserve" })
	CS.ElevatorEvent:Fire("Arrive", { depth = 2, code = "B2", name = "Gold Reserve" })
	CS.ElevatorEvent:Fire("Cancel", {})
	CS.RareEvent:Fire("Spawn", { depth = 1, item = "GoldenBundle", name = "Golden Bundle", rarity = "Legendary", position = V3.new(0, 1, 18), lifetime = 180 })
	CS.RareEvent:Fire("Gone", { depth = 1, item = "GoldenBundle" })
	for _, kind in ipairs({ "Achievement", "Discovery", "RareFind", "DepthUnlocked", "Daily", "TutorialDone", "Rebirth", "StackFull" }) do
		CS.PopupRequested:Fire(kind, { id = "GoldBar", name = "X", text = "Y", rarity = "Rare", tokens = 1, count = 1, total = 35, code = "B2", cash = 10, bonus = 1.25 })
	end
	CS.Notified:Fire("Hello", "good")
	CS.Notified:Fire("Nope", "error")
	CS.Announced:Fire("Big find!", { 255, 200, 60 })
	-- Every window opens and renders real data.
	local Ui = requireModule(folder.Ui)
	CS.leaderboard = { Earned = { { userId = alice.UserId, name = "Alice", value = 12000 } }, Depth = {}, Loot = {}, Deposit = {} }
	for _, name in ipairs({ "Upgrades", "Depths", "Book", "Achievements", "Daily", "Stats", "Leaderboards", "Shop", "Settings", "Elevator" }) do
		Ui.openWindow(name)
		assert(Ui.isOpen(name), name .. " did not open")
	end
	-- Upgrade cards show server prices; locked ones say where they unlock.
	Ui.openWindow("Upgrades")
	local cards, locked = 0, 0
	for _, d in ipairs(playerGui.VaultMenus:GetDescendants()) do
		if d:IsA("TextLabel") and string.find(d.Text, "LV ", 1, true) then
			cards += 1
		elseif d:IsA("TextLabel") and string.find(d.Text, "UNLOCKS AT", 1, true) then
			locked += 1
		end
	end
	assert(cards >= 3 and locked >= 1, string.format("upgrade cards %d, locked %d", cards, locked))
	-- The elevator panel lists all 7 depths plus the sealed complex.
	Ui.openWindow("Elevator")
	local codes = {}
	for _, d in ipairs(playerGui.VaultElevator:GetDescendants()) do
		if d:IsA("TextLabel") and string.match(d.Text, "^B%d$") then
			codes[d.Text] = true
		end
	end
	for d = 1, 7 do
		assert(codes["B" .. d], "elevator panel misses B" .. d)
	end
	-- Book: 35 cells, undiscovered ones as "???".
	Ui.openWindow("Book")
	local unknown = 0
	for _, d in ipairs(playerGui.VaultMenus:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text == "???" then
			unknown += 1
		end
	end
	assert(unknown > 0 and unknown < 35, "book silhouettes: " .. unknown)
	Ui.closeAll()
	-- Exit doors open on the client only once the depth behind them is unlocked.
	CS.ProfileChanged:Fire(snapshot)
	assert(c.EffectsController.doorOpen(snapshot.highestDepth + 1) == false, "a locked door is open")
	local unlocked = table.clone(snapshot)
	unlocked.highestDepth = snapshot.highestDepth + 1
	CS.profile = unlocked
	CS.ProfileChanged:Fire(unlocked)
	assert(c.EffectsController.doorOpen(snapshot.highestDepth + 1) == true, "the door did not open after unlocking")
	CS.profile = snapshot
	-- Lighting follows the character's depth.
	moveTo(bobRoot, world.depths[3].elevator.arrival.Position)
	c.EffectsController.init() -- re-run the depth check now
	assert(c.EffectsController.depth() == 3, "effects did not track the depth")
	local LightingPresets = requireModule(Shared.LightingPresets)
	assert(place:GetService("Lighting").Ambient == LightingPresets.DiamondChamber.Lighting.Ambient, "B3 lighting not applied")
	stubServices.RunService.IsServer = function()
		return true
	end
	print("        controllers: " .. table.concat(names, ", "))
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were reported through warn()", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
process.exit(0)
