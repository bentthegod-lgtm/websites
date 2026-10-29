--[[
	Headless smoke harness for CRASH LAB.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation (class / property / enum names are checked against the
	reflection database). Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, physics, rendering) are stubbed, and time is a fake clock
	the tests advance.

	Physics is NOT simulated by Lune, so flights are SCRIPTED: the harness moves the
	server's dummy root along a trajectory each tick and feeds contacts through the real
	CrashService.contact / Touched path. Everything else (launch validation, sampling,
	scoring, rewards, persistence, pads, props, objectives, duels, shop, client UI) is the
	real code.

	Usage (from crash-lab/):
	  rojo build -o build/CrashLab.rbxlx && lune run tests/harness build/CrashLab.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/CrashLab.rbxlx"
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

local SIGNAL_SUFFIXES = { "Added$", "Removing$", "Finished$", "Began$", "Ended$", "Changed$", "Released$", "Focused$", "^Heartbeat$", "^Stepped$", "^RenderStepped$" }
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
trackedTask.delay = function(_seconds, fn, ...)
	table.insert(deferred, { fn = fn, args = table.pack(...) })
end
local function flushDeferred()
	for _ = 1, 5 do
		local list = deferred
		deferred = {}
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
local Shared = RS:FindFirstChild("CrashLab")
local ServerRoot = SSS:FindFirstChild("CrashLabServer")
local Services = ServerRoot:FindFirstChild("Services")

local GameConfig = requireModule(Shared.Config.GameConfig)
local MachineConfig = requireModule(Shared.Config.MachineConfig)
local UpgradeConfig = requireModule(Shared.Config.UpgradeConfig)
local CourseConfig = requireModule(Shared.Config.CourseConfig)
local ScoringConfig = requireModule(Shared.Config.ScoringConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local CosmeticConfig = requireModule(Shared.Config.CosmeticConfig)
local Economy = requireModule(Shared.Economy)
local V3, CF = roblox.Vector3, roblox.CFrame

-- A real product id so ProcessReceipt can be exercised (config tables are plain tables).
ShopConfig.Products[1].ProductId = 5151

check("all server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
	requireModule(ServerRoot.World.FacilityBuilder)
end)

check("crash dummy: ragdoll rig with limited joints, no self-collision, decorations inert", function()
	local DummyModel = requireModule(Shared.DummyModel)
	for _, skin in ipairs(CosmeticConfig.SkinOrder) do
		local model, parts = DummyModel.build(skin, CF.new(0, 10, 0), { ragdoll = true, physics = MachineConfig.Dummies[2] })
		assert(model.PrimaryPart == parts.Root, "root is not the primary part")
		local body = DummyModel.bodyParts(model)
		assert(#body == 11, "body parts: " .. #body)
		local sockets, noCollide = 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BallSocketConstraint") then
				sockets += 1
				assert(d.LimitsEnabled and d.TwistLimitsEnabled and d.UpperAngle <= 95, "joint without limits: " .. d.Name)
				assert(d.Attachment0 and d.Attachment1 and d.Attachment0.Parent ~= d.Attachment1.Parent, "joint attachments")
			elseif d:IsA("NoCollisionConstraint") then
				noCollide += 1
			elseif d:IsA("BasePart") and d.Name == "Deco" then
				assert(d.Massless and not d.CanCollide and not d.CanQuery and not d.CanTouch, "decoration can touch the course")
				assert(d:FindFirstChildOfClass("WeldConstraint"), "decoration not welded")
			end
		end
		assert(sockets == 10 and noCollide >= 10, string.format("sockets %d, no-collide %d", sockets, noCollide))
		for _, p in ipairs(body) do
			assert(not p.Anchored and p.CanCollide and not p.CanQuery, p.Name .. " physics flags")
		end
	end
	local statue = DummyModel.build("Default", CF.new(), { ragdoll = false })
	for _, d in ipairs(statue:GetDescendants()) do
		assert(not d:IsA("BallSocketConstraint"), "static dummy has joints")
		if d:IsA("BasePart") then
			assert(d.Anchored, "static dummy part not anchored")
		end
	end
end)

check("three machines build: distinct models, movers, anchored and non-colliding", function()
	local MachineModels = requireModule(Shared.MachineModels)
	local counts = {}
	for _, id in ipairs(MachineConfig.Order) do
		local model, rig = MachineModels.build(id, CF.new(0, 1, 0))
		assert(rig.mover and rig.mover.PrimaryPart, id .. " has no moving part")
		assert(rig.launchOffset.Position.Y > 3, id .. " launch point too low")
		-- The ragdoll spawns standing at the launch point: its feet must clear the pad top
		-- (the pad part is 0.3 studs thick), or it starts inside the pad and gets ejected.
		local DummyModel = requireModule(Shared.DummyModel)
		assert(rig.launchOffset.Position.Y - DummyModel.RootHeight > 0.3 + 0.1, id .. " spawns the dummy's feet inside the pad")
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				assert(d.Anchored and not d.CanCollide and not d.CanQuery, id .. "." .. d.Name .. " could snag the dummy")
			end
		end
		counts[id] = n
		assert(n >= 20 and n <= 120, id .. " part count " .. n)
	end
	assert(counts.Standard ~= counts.Spring and counts.Spring ~= counts.AirCannon, "machines look like copies")
	local _, spring = MachineModels.build("Spring", CF.new())
	assert(#spring.extras.coils >= 5 and spring.extras.piston, "spring has no coils / piston")
	local _, air = MachineModels.build("AirCannon", CF.new())
	assert(air.extras.beacon and air.extras.beaconLight and air.extras.needle, "air cannon has no beacon / gauge")
end)

local world
check("facility builds: lobby, 6 pads, rings, targets, zones, props, tags, part budget", function()
	local FacilityBuilder = requireModule(ServerRoot.World.FacilityBuilder)
	world = FacilityBuilder.build()
	syncPositions(world.folder)
	assert(world.spawn:IsA("SpawnLocation"))
	assert(#world.pads == GameConfig.PadCount, "pads " .. #world.pads)
	for _, pad in ipairs(world.pads) do
		assert(pad.prompt:IsA("ProximityPrompt") and pad.slot and pad.ownerLabel, "pad " .. pad.index .. " incomplete")
		-- Every pad heads down the course.
		local forward = pad.cframe:VectorToWorldSpace(V3.new(0, 0, 1))
		assert(forward.Z > 0.95, "pad " .. pad.index .. " doesn't face the course")
		assert(pad.stand.LookVector.Z > 0.95, "pad " .. pad.index .. " stands the owner facing away from the course")
		assert(pad.stand.Position.Z < pad.cframe.Position.Z - 5, "owner stands in front of the machine")
	end
	local n = 0
	for _ in pairs(world.rings) do
		n += 1
	end
	assert(n == #CourseConfig.Rings)
	for _, def in ipairs(CourseConfig.Targets) do
		assert(world.targets[def.Id] and world.targets[def.Id].part:GetAttribute("CL_Target") == def.Id, def.Id .. " missing")
	end
	for _, def in ipairs(CourseConfig.LandingZones) do
		assert(world.zones[def.Id], def.Id .. " missing")
	end
	local props, groups = 0, {}
	for _, prop in pairs(world.props) do
		props += 1
		groups[prop.group] = true
		assert(prop.part:GetAttribute("CL_Prop") == prop.id)
	end
	assert(props >= 40 and groups.Fence and groups.PanelWall and groups.Boxes and groups.Pins and groups.Tower, "props: " .. props)
	for _, o in ipairs(CourseConfig.Objectives) do
		if o.Kind == "Break" then
			assert(groups[o.Group], o.Id .. " needs a missing group " .. o.Group)
		end
	end
	local floors = 0
	for _, d in ipairs(world.folder:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("CL_Floor") then
			floors += 1
		end
	end
	assert(floors >= 6, "floor not tagged")
	assert(world.stationPrompt and world.lockerPrompt and world.gate.prompt, "lobby prompts missing")
	assert(#world.boards.score.rows == 10 and #world.resultsBoard.rows == 6)
	assert(world.partCount < 4500, "part count " .. world.partCount)
	print("        facility parts: " .. world.partCount)
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
		if list[i].player == player then
			return list[i]
		end
	end
	return nil
end

local registry
local ORDER = { "Analytics", "DataService", "UpgradeService", "PadService", "LaunchService", "CrashService", "CourseService", "ScoringService", "QuestService", "DuelService", "ShopService", "PlayerService", "LeaderboardService" }
check("services initialise and start (same order as Main.server)", function()
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
	assert(collisionGroups.CL_Dummy and collisionGroups.CL_Player and collisionGroups.CL_Debris, "collision groups not registered")
	assert(collidable["CL_Dummy|CL_Dummy"] == false and collidable["CL_Dummy|CL_Player"] == false, "dummies would collide with each other / players")
end)

local nextUserId = 2000
local function makePlayer(name, position)
	nextUserId += 1
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = nextUserId
	player.Parent = place:GetService("Players")
	local character = roblox.Instance.new("Model")
	character.Name = name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3.new(2, 2, 1)
	root.CFrame = CF.new(position or V3.new(0, 3, -60))
	root.Position = root.CFrame.Position
	root.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspaceService
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	player.CharacterAdded:Fire(character)
	flushDeferred()
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

local DS, LS, CS, PS, US
-- Advances the fake clock in 1/30 s steps, running the same Heartbeat work as Main.server.
-- `script(t)` is called every step to move dummies (Lune has no physics).
local function tick(seconds, script)
	local dt = 1 / 30
	local t = 0
	while t < seconds - 1e-9 do
		advance(dt)
		t += dt
		if script then
			script(t)
		end
		LS.step()
		syncPositions(world.dummyFolder)
		CS.step()
		registry.CourseService.step(dt)
	end
	flushDeferred()
end
local function setRoot(run, position)
	run.root.CFrame = CF.new(position)
	run.root.Position = position
end
-- Ballistic path from the launch velocity, landing on the floor and sliding to a stop.
local function ballistic(run, onFloor)
	local v0 = run.launch.Velocity
	local p0 = run.tracker.last
	local start = clock
	local landed, landPos = false, nil
	return function()
		if run.ended then
			return
		end
		local t = clock - start
		if not landed then
			local p = p0 + v0 * t + V3.new(0, -0.5 * 196.2 * t * t, 0)
			if p.Y <= 1 then
				landed = true
				landPos = V3.new(p.X, 1, p.Z)
				if onFloor then
					onFloor(run, landPos, (v0 + V3.new(0, -196.2 * t, 0)).Magnitude)
				end
				p = landPos
			end
			setRoot(run, p)
		else
			setRoot(run, landPos)
		end
	end
end

local function floorPart()
	for _, d in ipairs(world.folder.Arena:GetChildren()) do
		if d:GetAttribute("CL_Floor") then
			return d
		end
	end
end

local alice, aliceRoot, bob, bobRoot
check("player joins: default profile, leaderstats, told saving is off, character in player group", function()
	DS, LS, CS, PS, US = registry.DataService, registry.LaunchService, registry.CrashService, registry.PadService, registry.UpgradeService
	alice, aliceRoot = makePlayer("Alice")
	local p = DS.getProfile(alice)
	assert(p and p.Coins == 0 and p.Machines.Standard and not p.Machines.Spring and p.Selected == "Standard", "bad default profile")
	assert(not DS.isPersistent(alice))
	assert(alice:FindFirstChild("leaderstats"), "no leaderstats")
	assert(count("Notify", "saving is unavailable", alice) >= 1, "not told that saving is off")
	assert(aliceRoot.CollisionGroup == "CL_Player", "character not in the player collision group")
	assert(p.Tutorial.Step == 1 and not p.Tutorial.Done)
end)

check("launch is refused without a pad; pad claim needs proximity; one player per pad", function()
	assert(not LS.request(alice, { Power = 1 }), "launched without a pad")
	moveTo(aliceRoot, V3.new(300, 3, 300))
	local ok = PS.claim(alice, 3)
	assert(not ok, "claimed a pad from far away")
	local pad = world.pads[3]
	moveTo(aliceRoot, pad.cframe.Position + V3.new(0, 3, -8))
	assert(PS.claim(alice, 3), "claim failed")
	assert(PS.padOf(alice) == pad and pad.owner == alice)
	assert(pad.slot:FindFirstChild("Machine_Standard"), "machine not built on the pad")
	assert(not pad.prompt.Enabled, "taken pad still prompts")
	assert(DS.getProfile(alice).Tutorial.Step == 2, "tutorial did not advance on claim")
	bob, bobRoot = makePlayer("Bob", pad.cframe.Position + V3.new(0, 3, -8))
	local okBob, message = PS.claim(bob, 3)
	assert(not okBob and string.find(message, "in use", 1, true), "two players on one pad")
	assert(count("PadState") > 0, "pad state not broadcast")
end)

local firstResult
check("first launch: charge -> fire -> server-owned ragdoll with server velocity -> scored once", function()
	local p = DS.getProfile(alice)
	assert(LS.request(alice, { Power = 1, Angle = 89, Aim = 0, Spin = "Chaos" }), "valid launch refused")
	assert(LS.isCharging(alice), "not charging")
	-- Spam while charging is refused.
	assert(not LS.request(alice, { Power = 1 }), "second launch accepted while charging")
	assert(p.LastLaunch.Angle == 45 and p.LastLaunch.Spin == "None", "client request not clamped")
	tick(MachineConfig.ById.Standard.ChargeTime + 0.05)
	local run = CS.runOf(alice)
	assert(run and not run.ended, "no run after the charge")
	assert(run.model.Parent == world.dummyFolder and run.model:GetAttribute("Owner") == alice.UserId)
	for _, part in ipairs(run.body) do
		assert(networkOwners[part] == "server", part.Name .. " not server-owned")
		assert(part.CollisionGroup == "CL_Dummy", part.Name .. " not in the dummy group")
		assert((part.AssemblyLinearVelocity - run.launch.Velocity).Magnitude < 1e-3, part.Name .. " not given the launch velocity")
	end
	assert(run.launch.Speed <= ScoringConfig.MaxLaunchSpeed and math.abs(run.launch.Speed - MachineConfig.ById.Standard.BaseSpeed) < 1, "unexpected speed " .. run.launch.Speed)
	assert(p.Stats.Launches == 1 and p.Achievements.FirstLaunch, "launch not counted")
	assert(not LS.request(alice, { Power = 1 }), "launched a second dummy mid-flight")
	-- Fly it: land on the floor, plus a burst of floor contacts that must be grouped.
	local floor = floorPart()
	tick(6, ballistic(run, function(r, pos, speed)
		for _ = 1, 40 do
			CS.contact(r, floor, speed, pos)
		end
	end))
	assert(run.ended and run.reason == "settled", "run did not settle: " .. tostring(run.reason))
	local results = lastFor("Results", alice)
	assert(results, "no results sent")
	firstResult = results.args[1]
	assert(firstResult.distance > 40 and firstResult.distance < 90, "distance " .. firstResult.distance)
	assert(firstResult.impacts == 1, "floor contact spam counted " .. firstResult.impacts .. " impacts")
	local QuestConfig = requireModule(Shared.Config.QuestConfig)
	local achievementCoins = 0
	for id in pairs(p.Achievements) do
		achievementCoins += QuestConfig.AchievementById[id].Reward
	end
	assert(p.Coins == firstResult.coins + achievementCoins and firstResult.coins >= ScoringConfig.MinCoins, "coins not paid exactly once: " .. p.Coins)
	assert(p.Stats.BestDistance == math.floor(firstResult.distance) and firstResult.records.BestDistance, "record not saved")
	assert(firstResult.recommend and firstResult.recommend.key == "Power", "no recommendation")
	-- Paying twice is impossible.
	registry.ScoringService.finish(run, {}, "settled")
	CS.finish(run, "settled")
	assert(p.Coins == firstResult.coins + achievementCoins, "paid twice")
	assert(count("Results", nil, alice) == 1, "results sent twice")
	assert(p.Tutorial.Step == 4, "tutorial should now ask for an upgrade, step " .. p.Tutorial.Step)
	-- Cleanup: the dummy is removed after the delay.
	assert(run.model.Parent == nil, "dummy not cleaned up")
	assert(CS.runOf(alice) == nil)
end)

check("cooldown is enforced on the server", function()
	tick(10)
	assert(LS.request(alice, { Power = 1 }))
	tick(1)
	assert(CS.runOf(alice), "no run")
	CS.cancel(alice) -- run gone, launcher still cooling down
	assert(not LS.request(alice, { Power = 1 }), "launched during cooldown")
	assert(count("Notify", "cooling down", alice) >= 1, "player not told about the cooldown")
	tick(10)
end)

check("upgrade: server price, atomic spend, insufficient funds refused, next launch is faster", function()
	local p = DS.getProfile(alice)
	p.Coins = 10
	local ok, msg = US.buy(alice, "Power")
	assert(not ok and string.find(msg, "Not enough", 1, true) and p.Coins == 10 and (p.Upgrades.Power or 0) == 0, "bought without coins")
	p.Coins = 1000
	local price = Economy.cost("Power", 0)
	assert(US.buy(alice, "Power"))
	-- (the first upgrade also completes the "Tinkerer" achievement, which pays its reward)
	assert(p.Coins == 1000 - price + requireModule(Shared.Config.QuestConfig).AchievementById.FirstUpgrade.Reward and p.Upgrades.Power == 1, "wrong price taken: " .. p.Coins)
	assert(not US.buy(alice, "Bogus"), "unknown upgrade bought")
	assert(p.Tutorial.Step == 5, "tutorial did not advance on upgrade")
	tick(10)
	assert(LS.request(alice, { Power = 1 }), "launch after upgrade refused")
	tick(1)
	local run = CS.runOf(alice)
	assert(run.launch.Speed > MachineConfig.ById.Standard.BaseSpeed * 1.06, "upgrade made no difference")
	tick(6, ballistic(run))
	local r = lastFor("Results", alice).args[1]
	assert(r.distance > firstResult.distance * 1.08, string.format("upgraded flight %.1f vs %.1f", r.distance, firstResult.distance))
	assert(p.Stats.BestDistance == math.floor(r.distance), "record not raised")
end)

check("objectives: ring + prop + target + landing zone, featured bonus, achievements", function()
	local p = DS.getProfile(alice)
	tick(10)
	registry.QuestService.rerollFeatured(alice)
	-- Force the featured objective to the low ring for a deterministic check.
	local Quest = registry.QuestService
	local realFeatured = Quest.featuredId
	Quest.featuredId = function()
		return "RingLow"
	end
	assert(LS.request(alice, { Power = 1 }))
	Quest.featuredId = realFeatured
	tick(1)
	local run = CS.runOf(alice)
	assert(run.featuredId == "RingLow")
	local ring = CourseConfig.RingById.RingLow
	local zone = CourseConfig.ZoneById.GreenZone
	local box
	for _, prop in pairs(world.props) do
		if prop.kind == "Cardboard" and not prop.broken then
			box = prop
			break
		end
	end
	local target = world.targets.SwingTarget.part
	-- Scripted path: through the low ring, smash a box, clip the swinging target, land in the green zone.
	local path = {
		{ 0.7, ring.Position + V3.new(0, 0, -12) },
		{ 0.9, ring.Position + V3.new(0, 0, 12) },
		{ 1.25, V3.new(0, 8, 140) },
		{ 1.5, zone.Position + V3.new(2, 1, 0) },
	}
	local start = clock
	local hit = false
	local boxBroken = false
	local debrisAtHit = 0
	tick(5, function()
		local t = clock - start
		local pos = path[#path][2]
		for i, step in ipairs(path) do
			if t <= step[1] then
				local prev = if i == 1 then run.tracker.last else path[i - 1][2]
				local t0 = if i == 1 then 0 else path[i - 1][1]
				pos = prev:Lerp(step[2], math.clamp((t - t0) / (step[1] - t0), 0, 1))
				break
			end
		end
		setRoot(run, pos)
		if not hit and t > 1.1 then
			hit = true
			CS.contact(run, box.part, 80, pos)
			CS.contact(run, box.part, 80, pos) -- repeated contact on the same prop
			CS.contact(run, target, 90, pos)
			boxBroken = box.broken and box.part.Transparency == 1 and not box.part.CanCollide
			debrisAtHit = registry.CourseService.activeDebris()
		end
	end)
	assert(run.ended, "run did not end")
	local r = lastFor("Results", alice).args[1]
	local has = {}
	for _, id in ipairs(r.objectives) do
		has[id] = true
	end
	assert(has.RingLow and has.GreenZone and has.SwingTarget and has.MultiTarget == nil, "objectives: " .. table.concat(r.objectives, ","))
	assert(r.featuredDone and r.featuredPoints > 0, "featured bonus missing")
	assert(boxBroken, "box not broken")
	local props = 0
	for _, b in ipairs(r.bonuses) do
		if b.kind == "Prop" then
			props += 1
		end
	end
	assert(props == 1, "prop awarded " .. props .. " times")
	assert(p.Achievements.FirstObjective and p.Achievements.FirstTarget, "achievements not granted")
	assert(debrisAtHit > 0, "no debris")
	-- Debris cleans up and the prop respawns (timed tasks run on flush).
	flushDeferred()
	assert(not box.broken and box.part.CanCollide, "prop did not respawn")
	assert(registry.CourseService.activeDebris() == 0, "debris left behind")
	assert(p.Tutorial.Done, "tutorial not finished after the objective")
end)

check("destructibles: heavy panels bounce a light dummy; debris is capped", function()
	local panel
	for _, prop in pairs(world.props) do
		if prop.kind == "Panel" then
			panel = prop
			break
		end
	end
	assert(registry.CourseService.hitProp(panel.id, 200, 1) == "bounced" and not panel.broken, "standard dummy broke a panel")
	assert(registry.CourseService.hitProp(panel.id, 10, 4) == nil, "slow touch broke a panel")
	assert(registry.CourseService.hitProp(panel.id, 200, 2) == "broken" and panel.broken)
	assert(registry.CourseService.hitProp(panel.id, 200, 2) == nil, "broken prop hit again")
	local broken = 0
	for id, prop in pairs(world.props) do
		if not prop.broken and registry.CourseService.hitProp(id, 200, 4) == "broken" then
			broken += 1
		end
	end
	assert(broken > 20)
	assert(registry.CourseService.activeDebris() <= requireModule(Shared.Config.PerformanceConfig).MaxActiveDebris, "debris cap exceeded")
	flushDeferred()
	for _, prop in pairs(world.props) do
		assert(not prop.broken, "prop never respawned")
	end
end)

check("anti-teleport: impossible samples are rejected; repeated ones void the run", function()
	local p = DS.getProfile(alice)
	tick(10)
	assert(LS.request(alice, { Power = 1 }))
	tick(1)
	local run = CS.runOf(alice)
	local coins = p.Coins
	local best = p.Stats.BestDistance
	local n = 0
	tick(2, function()
		n += 1
		-- Every few frames the dummy "teleports" deep down the course.
		setRoot(run, if n % 4 == 0 then V3.new(0, 20, 500) else run.tracker.last)
	end)
	assert(run.ended and run.reason == "voided", "run not voided: " .. tostring(run.reason))
	local r = lastFor("Results", alice).args[1]
	assert(r.voided and r.score == 0 and r.coins == ScoringConfig.VoidCoins, "voided run paid " .. r.coins)
	assert(p.Coins == coins + ScoringConfig.VoidCoins and p.Stats.BestDistance == best, "teleport changed rewards or records")
end)

check("runs end safely: out of bounds, timeout, broken rig", function()
	tick(10)
	assert(LS.request(alice, { Power = 1 }))
	tick(1)
	local run = CS.runOf(alice)
	tick(1, function()
		setRoot(run, run.tracker.last + V3.new(0, -8, 0)) -- falls through the world
	end)
	assert(run.ended and run.reason == "outOfBounds", "fell out without ending: " .. tostring(run.reason))
	tick(10)
	assert(LS.request(alice, { Power = 1 }))
	tick(1)
	run = CS.runOf(alice)
	local k = 0
	local center = run.tracker.last + V3.new(0, 3, 10)
	tick(GameConfig.Run.MaxDuration + 1, function()
		k += 1
		-- Keeps moving (never settles, never stuck) until the time limit.
		setRoot(run, center + V3.new(math.sin(k / 6) * 10, 0, math.cos(k / 6) * 10 - 10))
	end)
	assert(run.ended and run.reason == "timeout", "time limit not enforced: " .. tostring(run.reason))
	tick(10)
	assert(LS.request(alice, { Power = 1 }))
	tick(1)
	run = CS.runOf(alice)
	run.body[3]:Destroy()
	tick(0.2)
	assert(run.ended and run.reason == "broken", "broken rig not handled")
	tick(3)
	assert(CS.activeCount() == 0, "runs left active")
end)

check("two players: isolated runs, ownership, rewards go to the right player", function()
	local bp = DS.getProfile(bob)
	local pad4 = world.pads[4]
	moveTo(bobRoot, pad4.cframe.Position + V3.new(0, 3, -8))
	assert(PS.claim(bob, 4), "bob could not claim pad 4")
	tick(10)
	local aliceCoins = DS.getProfile(alice).Coins
	assert(LS.request(alice, { Power = 1 }) and LS.request(bob, { Power = 0.5 }), "simultaneous launches refused")
	tick(1)
	local ra, rb = CS.runOf(alice), CS.runOf(bob)
	assert(ra and rb and ra ~= rb and ra.model ~= rb.model, "runs not separate")
	assert(rb.model:GetAttribute("Owner") == bob.UserId)
	-- Contacts on Alice's run never touch Bob's tracker.
	local floor = floorPart()
	CS.contact(ra, floor, 150, ra.root.Position)
	assert(ra.tracker.impactCount == 1 and rb.tracker.impactCount == 0, "contact leaked between runs")
	-- A dummy part touching another dummy is ignored.
	CS.contact(ra, rb.body[1], 200, ra.root.Position)
	assert(ra.tracker.impactCount == 1, "dummy-dummy contact counted")
	local fa, fb = ballistic(ra), ballistic(rb)
	tick(6, function(t)
		fa(t)
		fb(t)
	end)
	assert(ra.ended and rb.ended)
	local resultA = lastFor("Results", alice).args[1]
	local resultB = lastFor("Results", bob).args[1]
	assert(resultA ~= resultB and resultB.distance < resultA.distance, "half power should fly shorter")
	assert(DS.getProfile(alice).Coins == aliceCoins + resultA.coins, "alice paid wrong")
	local bobAchievements = 0
	for id in pairs(bp.Achievements) do
		bobAchievements += requireModule(Shared.Config.QuestConfig).AchievementById[id].Reward
	end
	assert(bp.Coins == resultB.coins + bobAchievements, "bob paid wrong: " .. bp.Coins)
end)

check("leaving mid-run: run cancelled, dummy removed, pad freed, nothing paid", function()
	local carol, carolRoot = makePlayer("Carol")
	local pad = world.pads[1]
	moveTo(carolRoot, pad.cframe.Position + V3.new(0, 3, -8))
	assert(PS.claim(carol, 1))
	assert(LS.request(carol, { Power = 1 }))
	tick(1)
	local run = CS.runOf(carol)
	assert(run and run.model.Parent, "carol has no run")
	local model = run.model
	leave(carol)
	assert(run.ended and not run.paid, "a leaver was paid")
	assert(model.Parent == nil, "leaver's dummy left in the world")
	assert(pad.owner == nil and pad.prompt.Enabled, "pad not freed")
	assert(CS.runOf(carol) == nil)
	tick(1)
	assert(count("Results", nil, carol) == 0)
	-- Leaving while charging also cleans up.
	local dan, danRoot = makePlayer("Dan")
	moveTo(danRoot, pad.cframe.Position + V3.new(0, 3, -8))
	assert(PS.claim(dan, 1) and LS.request(dan, { Power = 1 }))
	leave(dan)
	tick(2)
	assert(CS.runOf(dan) == nil and not LS.isCharging(dan), "charge survived the leave")
end)

check("machines: unlock needs requirement + coins, selection rebuilds the pad machine", function()
	local p = DS.getProfile(alice)
	p.Coins = 100000
	local best = p.Stats.BestDistance
	p.Stats.BestDistance = 10
	local ok = US.unlockMachine(alice, "Spring")
	assert(not ok and not p.Machines.Spring, "unlocked without the requirement")
	p.Stats.BestDistance = math.max(best, 150)
	local coins = p.Coins
	assert(US.unlockMachine(alice, "Spring"), "unlock failed")
	local springReward = requireModule(Shared.Config.QuestConfig).AchievementById.Spring.Reward
	assert(p.Machines.Spring and p.Selected == "Spring" and p.Coins == coins - MachineConfig.ById.Spring.Cost + springReward, "unlock price wrong: " .. p.Coins)
	assert(not US.unlockMachine(alice, "Spring"), "bought twice")
	assert(PS.padOf(alice).slot:FindFirstChild("Machine_Spring"), "pad machine not rebuilt")
	assert(p.Achievements.Spring, "machine achievement missing")
	assert(not US.unlockMachine(alice, "AirCannon"), "air cannon without payload")
	assert(not US.select(alice, "AirCannon"), "selected an unowned machine")
	tick(10)
	assert(LS.request(alice, { Power = 1, Angle = 45 }))
	tick(2)
	local run = CS.runOf(alice)
	assert(run.machine.Id == "Spring" and run.launch.Elevation < 45, "spring should fire flatter")
	-- Unlocking mid-launch doesn't claim "selected": it queues and switches after the run.
	local payload = p.Upgrades.Payload
	p.Upgrades.Payload = 1
	p.Stats.BestDistance = math.max(p.Stats.BestDistance, 300)
	local unlocked, unlockMsg = US.unlockMachine(alice, "AirCannon")
	assert(unlocked and string.find(unlockMsg, "as soon as", 1, true), "mid-run unlock message: " .. tostring(unlockMsg))
	assert(p.Selected == "Spring" and US.pending(alice) == "AirCannon", "mid-run unlock changed the selection / not queued")
	-- Backspin is applied to the whole ragdoll as one rigid body (w on every part, v + w x r).
	local omega = run.root.AssemblyAngularVelocity
	assert(omega.Magnitude > 1, "spring backspin not applied")
	local centre = run.root.CFrame.Position
	for _, part in ipairs(run.body) do
		assert((part.AssemblyAngularVelocity - omega).Magnitude < 1e-3, part.Name .. " not spinning with the body")
		local expected = run.launch.Velocity + omega:Cross(part.CFrame.Position - centre)
		assert((part.AssemblyLinearVelocity - expected).Magnitude < 1e-3, part.Name .. " velocity doesn't match the spin")
	end
	-- Touched fires after the solver: a part stopped dead by a wall reads ~0 st/s. The tier
	-- comes from the speed it had going in (previous Heartbeat).
	local bumper = world.folder.Arena:FindFirstChild("Bumper1")
	run.root.AssemblyLinearVelocity = V3.new(0, 0, 120)
	CS.step()
	run.root.AssemblyLinearVelocity = V3.new(0, 0, 0)
	run.root.Touched:Fire(bumper)
	local hit = run.tracker.impacts[#run.tracker.impacts]
	assert(hit and hit.key == "Bumper1" and hit.tier == "Heavy", "wall impact tiered from post-contact speed")
	tick(6, ballistic(run))
	assert(p.Selected == "AirCannon" and US.pending(alice) == nil, "queued machine not selected after the run")
	assert(US.select(alice, "Standard"))
	p.Machines.AirCannon = nil
	p.Upgrades.Payload = payload
end)

check("moving targets: anchored movers get the velocity that matches their motion", function()
	local Course = registry.CourseService
	for _, id in ipairs({ "SwingTarget", "SlideTarget" }) do
		local target = world.targets[id]
		Course.step(0.37)
		local v = Course.targetVelocity(id)
		assert(v.Magnitude > 0.1, id .. " not moving")
		for _, m in ipairs(target.movers) do
			assert((m.AssemblyLinearVelocity - v).Magnitude < 1e-3, id .. " mover " .. m.Name .. " has the wrong velocity " .. tostring(m.AssemblyLinearVelocity) .. " vs " .. tostring(v))
		end
		local expected = Course.targetPosition(id)
		assert((target.part.CFrame.Position - (CF.new(expected) * target.base[target.part]).Position).Magnitude < 1e-3, id .. " not where its motion says")
	end
end)

check("daily challenges and codes reward exactly once", function()
	local p = DS.getProfile(alice)
	local view = registry.QuestService.dailyView(alice)
	assert(view and #view.list == 3, "no daily list")
	local before = p.Coins
	for _ = 1, 40 do
		DS.bump(alice, "Launches", 1)
		DS.bump(alice, "Targets", 1)
		DS.bump(alice, "Destroyed", 1)
		DS.bump(alice, "Objectives", 1)
		DS.bump(alice, "Machine:Standard", 1)
	end
	registry.QuestService.onRun(alice, { distance = 9999, score = 99999 }, nil)
	view = registry.QuestService.dailyView(alice)
	local gained = p.Coins - before
	local rewards = 0
	for _, c in ipairs(view.list) do
		assert(c.done, "challenge not completed: " .. c.text)
		rewards += c.reward
	end
	registry.QuestService.onRun(alice, { distance = 9999, score = 99999 }, nil)
	assert(p.Coins - before == gained, "daily paid twice")
	assert(gained >= rewards, "daily rewards missing")
	-- New UTC day: fresh challenges.
	advance(86400)
	view = registry.QuestService.dailyView(alice)
	assert(view.list[1].done == false, "dailies did not reset")
	local c1 = p.Coins
	assert(registry.QuestService.redeem(alice, " crashlab "))
	assert(not registry.QuestService.redeem(alice, "CRASHLAB"), "code used twice")
	assert(not registry.QuestService.redeem(alice, "NOPE"))
	assert(p.Coins == c1 + requireModule(Shared.Config.QuestConfig).Codes.CRASHLAB.Coins)
end)

check("duel: invite -> accept -> both runs -> winner paid once", function()
	local D = registry.DuelService
	assert(D.invite(alice, bob.UserId))
	assert(not D.invite(alice, alice.UserId), "duel with yourself")
	assert(D.respond(bob, true))
	assert(D.duelOf(alice) and D.duelOf(alice) == D.duelOf(bob))
	local ac, bc = DS.getProfile(alice).Coins, DS.getProfile(bob).Coins
	D.onRunFinished(alice, { score = 900, voided = false })
	D.onRunFinished(alice, { score = 5000, voided = false }) -- only the first run counts
	D.onRunFinished(bob, { score = 400, voided = false })
	assert(D.duelOf(alice) == nil, "duel not settled")
	assert(DS.getProfile(alice).Coins == ac + math.floor(400 * 0.25) + 50, "winner bonus wrong")
	assert(DS.getProfile(bob).Coins == bc + 25, "consolation wrong")
	assert(not D.respond(bob, true), "accepted an expired invite")
end)

check("prestige: needs confirmation + eligibility, resets exactly what it says", function()
	local p = DS.getProfile(alice)
	assert(not US.prestige(alice, "yes"), "no confirmation needed")
	assert(not US.prestige(alice, "CERTIFY"), "prestige without the Air Cannon")
	p.Machines.AirCannon = true
	p.Stats.BestScore = 5000
	p.Stats.CycleBestScore = 5000
	local achievements = 0
	for _ in pairs(p.Achievements) do
		achievements += 1
	end
	local best = p.Stats.BestDistance
	assert(US.prestige(alice, "CERTIFY"))
	assert(p.Coins == 0 and next(p.Upgrades) == nil and not p.Machines.Spring and not p.Machines.AirCannon and p.Selected == "Standard", "not reset")
	assert(p.Prestige.Credits >= 1 and p.Prestige.Count == 1, "no credits")
	assert(p.Stats.BestDistance == best, "records lost")
	local after = 0
	for _ in pairs(p.Achievements) do
		after += 1
	end
	assert(after >= achievements and p.Achievements.Certified, "achievements lost / certified missing")
	assert(US.statsFor(alice).CoinMultiplier > 1, "credits give no bonus")
	-- Each cycle must beat the requirement again: the old best doesn't carry over.
	assert(p.Stats.CycleBestScore == 0, "cycle best not reset")
	p.Machines.AirCannon = true
	local ok, msg = US.prestige(alice, "CERTIFY")
	assert(not ok and p.Prestige.Count == 1, "prestiged twice on the old best: " .. tostring(msg))
	p.Machines.AirCannon = nil
end)

check("cosmetics: coins purchase, achievement unlock, equip only owned, nothing changes stats", function()
	local SS = registry.ShopService
	local p = DS.getProfile(alice)
	local stats = US.statsFor(alice)
	p.Coins = 10
	assert(not SS.buyWithCoins(alice, "Skin", "Safety"), "bought without coins")
	assert(not SS.equip(alice, "Skin", "Safety"), "equipped unowned")
	p.Coins = 5000
	assert(SS.buyWithCoins(alice, "Skin", "Safety") and p.Cosmetics.Skin == "Safety")
	assert(not SS.buyWithCoins(alice, "Skin", "Neon"), "robux item bought with coins")
	assert(SS.owns(alice, "Skin", "Chrome"), "achievement cosmetic (Certified) not owned")
	assert(SS.equip(alice, "Skin", "Chrome"))
	assert(not SS.equip(alice, "Skin", "Bogus"))
	US.invalidate(alice)
	local after = US.statsFor(alice)
	for k, v in pairs(stats) do
		if type(v) == "number" then
			assert(after[k] == v, "cosmetic changed stat " .. k)
		end
	end
end)

local function receipt(player, purchaseId)
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = 5151, PurchaseId = purchaseId })
end
check("receipts: granted exactly once, refused when the profile can't persist live", function()
	local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	local notYet = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	assert(receipt(alice, "r-1") == granted)
	assert(DS.getProfile(alice).Cosmetics.Owned["Skin:Neon"] and DS.getProfile(alice).Receipts["r-1"])
	assert(receipt(alice, "r-1") == granted, "retry not acknowledged")
	local n = 0
	for _ in pairs(DS.getProfile(alice).Receipts) do
		n += 1
	end
	assert(n == 1, "receipt stored twice")
	isStudio = false
	local decision = receipt(bob, "r-live")
	isStudio = true
	assert(decision == notYet and not DS.getProfile(bob).Cosmetics.Owned["Skin:Neon"], "live purchase granted on a non-persistent profile")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 999999, ProductId = 5151, PurchaseId = "x" }) == notYet)
end)

check("settings: only known keys with legal values are saved", function()
	local p = DS.getProfile(bob)
	registry.PlayerService.saveSettings(bob, { Music = 0.3, Master = 7, Effects = 0 / 0, CameraShake = "yes", FollowCam = false, Hack = true })
	assert(p.Settings.Music == 0.3 and p.Settings.Master == 1, "numbers not clamped")
	assert(p.Settings.Effects == 1, "NaN accepted")
	assert(p.Settings.CameraShake == true and p.Settings.FollowCam == false and p.Settings.Hack == nil)
end)

check("remote spam and junk arguments are rejected", function()
	tick(15)
	local accepted = 0
	for _ = 1, 20 do
		if LS.request(bob, { Power = 1 }) then
			accepted += 1
		end
	end
	assert(accepted == 1, "accepted " .. accepted .. " launches from spam")
	tick(2)
	local run = CS.runOf(bob)
	tick(6, ballistic(run))
	remotes.Launch.OnServerEvent:Fire(bob, "garbage")
	remotes.Launch.OnServerEvent:Fire(bob, { Power = 0 / 0, Angle = math.huge, Aim = -1e9, Spin = {} })
	remotes.BuyUpgrade.OnServerEvent:Fire(bob, { "Power" })
	remotes.ClaimPad.OnServerEvent:Fire(bob, 0 / 0)
	remotes.UnlockMachine.OnServerEvent:Fire(bob, nil)
	remotes.Equip.OnServerEvent:Fire(bob, "Skin", 42)
	remotes.Duel.OnServerEvent:Fire(bob, "Invite", "nobody")
	remotes.Prestige.OnServerEvent:Fire(bob, 123)
	remotes.RedeemCode.OnServerEvent:Fire(bob, string.rep("A", 5000))
	tick(3)
	local p = DS.getProfile(bob)
	assert(p.Coins >= 0 and (p.Upgrades.Power or 0) <= 1, "junk changed the profile")
	local r = CS.runOf(bob)
	if r then
		assert(r.launch.Speed == r.launch.Speed and r.launch.Speed <= ScoringConfig.MaxLaunchSpeed, "NaN launch")
	end
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
		stored["player_" .. (nextUserId + 1)] = { Coins = 777, Upgrades = { Power = 999, Bogus = 3 }, Machines = { Standard = true, Rocket = true }, Selected = "Rocket" }
		local erin = makePlayer("Erin")
		local key = "player_" .. erin.UserId
		local p = DS.getProfile(erin)
		assert(DS.isPersistent(erin) and p.Coins == 777, "saved profile not loaded")
		assert(p.Upgrades.Power == UpgradeConfig.ByKey.Power.Max and p.Upgrades.Bogus == nil and p.Machines.Rocket == nil and p.Selected == "Standard", "saved data not validated")
		assert(type(stored[key].Lock) == "table", "profile not locked on load")
		p.Coins = 800
		assert(DS.save(erin) and stored[key].Coins == 800, "save failed")
		stored[key].Lock = { Session = "other-server", At = fakeOs.time() }
		p.Coins = 1
		assert(not DS.save(erin), "saved over another server's lock")
		assert(stored[key].Coins == 800 and not DS.isPersistent(erin))
		isStudio = false
		local decision = receipt(erin, "lock-1")
		isStudio = true
		assert(decision == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "granted after losing the lock")
		leave(erin)
		assert(stored[key].Coins == 800, "left player overwrote the new owner")
		stored["player_" .. (nextUserId + 1)] = { Coins = 55, Lock = { Session = "crashed", At = fakeOs.time() - 100000 } }
		local finn = makePlayer("Finn")
		local finnKey = "player_" .. finn.UserId
		assert(DS.isPersistent(finn) and DS.getProfile(finn).Coins == 55, "stale lock blocked the load")
		DS.getProfile(finn).Coins = 99
		leave(finn)
		assert(stored[finnKey].Coins == 99 and stored[finnKey].Lock == nil, "leave save did not persist and unlock")
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
	for _, name in ipairs({ "FirstLaunch", "FirstResult", "FirstUpgrade", "TutorialDone", "FirstObjective", "FirstMachine", "FirstPrestige" }) do
		assert(seen[name], name .. " not logged")
	end
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise and render real server data", function()
	local snapshot = DS.sendProfileNow(bob)
	assert(snapshot and snapshot.daily and snapshot.featured and snapshot.prestigePreview and snapshot.owned, "snapshot incomplete")
	requireModule(Shared.Net).setup()
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
	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("CrashLabClient"):FindFirstChild("Controllers")
	local names = { "ClientState", "AudioController", "CameraController", "InputController", "LaunchController", "HudController", "ResultsController", "JuiceController", "EffectsController", "TutorialController", "MenuController" }
	local controllers = {}
	for _, name in ipairs(names) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local ClientState = controllers.ClientState
	ClientState.profile = snapshot
	ClientState.settings = table.clone(snapshot.settings)
	ClientState.pads = registry.PadService.state()
	ClientState.ProfileChanged:Fire(snapshot)
	ClientState.PadsChanged:Fire(ClientState.pads)
	for _, name in ipairs({ "CrashHUD", "CrashLaunch", "CrashResults", "CrashMenu", "CrashTutorial" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
	end
	-- Bob owns pad 4: the launch panel is shown and clamps like the server.
	local Launch = controllers.LaunchController
	Launch.render()
	assert(playerGui.CrashLaunch.LaunchPanel.Visible, "launch panel hidden on own pad")
	Launch.adjust("Power", -100)
	assert(Launch.request.Power == MachineConfig.ById.Standard.MinPower, "power clamp")
	Launch.adjust("Angle", 5)
	assert(Launch.request.Angle == Economy.stats({ Upgrades = snapshot.upgrades }).AngleMax, "angle clamp")
	Launch.adjust("Spin", 1)
	assert(Launch.status() == "Ready" or Launch.status() == "Cooldown")
	ClientState.leaderboard = { score = { { userId = alice.UserId, name = "Alice", value = 1200 }, { userId = bob.UserId, name = "Bob", value = 900 } }, distance = {} }
	-- Every menu tab renders.
	local Menu = controllers.MenuController
	for _, tab in ipairs(Menu.TABS) do
		Menu.open(tab)
		Menu.render()
	end
	for _, cat in ipairs(UpgradeConfig.Categories) do
		Menu.setTab("Upgrades")
		Menu.setCategory(cat)
		Menu.render()
		local cards = 0
		for _, d in ipairs(playerGui.CrashMenu:GetDescendants()) do
			if d:IsA("TextLabel") and string.find(d.Text, "Level ", 1, true) then
				cards += 1
			end
		end
		assert(cards >= 2, cat .. " shows " .. cards .. " cards")
	end
	Menu.showConfirm(DS.snapshot(alice))
	-- Results card renders a real breakdown.
	local result = lastFor("Results", bob).args[1]
	controllers.ResultsController.show(result)
	assert(controllers.ResultsController.isOpen(), "results not shown")
	assert(result.grade and string.find("SABCD", result.grade, 1, true), "results carry no grade")
	local compact = controllers.ResultsController.layout(roblox.Vector2.new(800, 400))
	assert(compact.compact and compact.position.Y.Offset + compact.size.Y <= 400 - 90, "compact results overlap the Jump button row")
	assert(not controllers.ResultsController.layout(roblox.Vector2.new(1920, 1080)).compact, "desktop got the compact card")
	-- (retry() itself fires a remote, which the headless client can't; check its guard.)
	controllers.ResultsController.close()
	assert(not controllers.ResultsController.retry(), "retry with the card closed")
	controllers.ResultsController.show(result)
	-- Juice maths: countdown, combos, speed lines.
	local LC = controllers.LaunchController
	assert(LC.countdownStep(0, 1.5) == 3 and LC.countdownStep(0.75, 1.5) == 2 and LC.countdownStep(1.49, 1.5) == 1, "countdown wrong")
	local J = controllers.JuiceController
	local combo = { count = 0, last = -math.huge }
	assert(J.comboStep(combo, 1) == 1 and J.comboStep(combo, 1.5) == 2 and J.comboStep(combo, 2.2) == 3 and J.comboStep(combo, 9) == 1, "combo chain wrong")
	assert(J.speedLineCount(50) == 0 and J.speedLineCount(1e6) == J.MaxSpeedLines and J.speedLineCount(0 / 0) == 0, "speed lines not capped")
	assert(J.celebrate({ records = { BestScore = 1 } }) and not J.celebrate({ records = {} }), "record celebration")
	-- Machine animation maths: charge cocks back, fire swings through, rest returns.
	local E = controllers.EffectsController
	local restA = E.moverAngle("Standard", "Rest", 0, 1, 45)
	assert(E.moverAngle("Standard", "Charge", 1, 1, 45) > restA, "catapult should cock back")
	assert(E.moverAngle("Standard", "Fire", 0.15, 1, 45) < restA, "catapult should swing forward")
	assert(math.abs(E.moverAngle("Spring", "Charge", 1, 1, 30) - math.rad(-30)) < 1e-6, "barrel should aim at the launch angle")
	-- Fire real machine / run events through the client.
	local pad = registry.PadService.padOf(bob)
	ClientState.MachineFx:Fire(pad.index, "Standard", "Charge", { time = 0.8, elevation = 45 })
	E.step(0.4)
	ClientState.MachineFx:Fire(pad.index, "Standard", "Fire", { elevation = 45, fx = "Confetti" })
	E.step(0.1)
	ClientState.RunEvent:Fire(bob.UserId, "Impact", { tier = "Massive", position = V3.new(0, 2, 50), metal = true })
	ClientState.RunEvent:Fire(bob.UserId, "Ring", { id = "RingLow", position = V3.new(0, 20, 105) })
	ClientState.RunEvent:Fire(0, "Prop", { id = "x", kind = "Wood", position = V3.new(0, 2, 170) })
	ClientState.RunEvent:Fire(bob.UserId, "Target", { id = "Gong", position = V3.new(0, 30, 505) })
	-- Follow camera chases a dummy and stops cleanly.
	local Cam = controllers.CameraController
	local dummy = requireModule(Shared.DummyModel).build("Default", CF.new(0, 10, 40), { ragdoll = false })
	dummy.Parent = workspaceService
	syncPositions(dummy)
	ClientState.applySettings({ FollowCam = true })
	Cam.follow(dummy)
	assert(Cam.following(), "follow cam did not start")
	Cam.step(1 / 60)
	assert(controllers.InputController.handle(roblox.Enum.KeyCode.Space), "space did not skip")
	assert(not Cam.following(), "follow cam did not stop")
	local f = Cam.followFrame(CF.new(0, 50, 0), V3.new(0, 10, 100), 1)
	assert(f.Position.Z < 100 and f.Position.Y > 10, "follow cam not behind / above")
	-- HUD bits.
	local Hud = controllers.HudController
	Hud.tick()
	for _, kind in ipairs({ "Achievement", "Challenge", "Machine", "Facility", "Prestige", "TutorialDone" }) do
		ClientState.PopupRequested:Fire(kind, { name = "X", text = "Y", reward = 10, credits = 1, total = 2, built = false })
	end
	ClientState.PopupRequested:Fire("DuelInvite", { from = "Alice", userId = alice.UserId })
	ClientState.DuelChanged:Fire({ opponent = "Alice", endsIn = 50 })
	ClientState.Notified:Fire("Hello", "good")
	ClientState.Notified:Fire("Nope", "error")
	ClientState.Announced:Fire("Big launch!", { 255, 200, 60 })
	assert(Hud.nextGoal(snapshot) ~= "", "no goal shown")
	controllers.TutorialController.render()
	stubServices.RunService.IsServer = function()
		return true
	end
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
