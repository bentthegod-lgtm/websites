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
			if instance:IsA("BasePart") then
				instance.Position = roblox.Vector3.zero
			end
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
local Shared = RS:FindFirstChild("DeadAir")
local Services = SSS:FindFirstChild("DeadAirServer"):FindFirstChild("Services")

local Rng = requireModule(Shared.Rng)
local MazeGen = requireModule(Shared.MazeGen)
local MapConfig = requireModule(Shared.Config.MapConfig)
local ObjectiveConfig = requireModule(Shared.Config.ObjectiveConfig)

local MapBuilder, MonsterModel
check("server modules load", function()
	MapBuilder = requireModule(Services.MapBuilder)
	MonsterModel = requireModule(Services.MonsterModel)
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
end)

local maps = {}
check("MapBuilder builds 30 facilities (both chains) without errors", function()
	for seed = 1, 30 do
		local rng = Rng.new(seed * 104729)
		local layout = MazeGen.generate(MapConfig, rng)
		local chainName = if seed % 2 == 0 then "PowerGrid" else "Generator"
		local map = MapBuilder.build(layout, ObjectiveConfig.Chains[chainName], rng, { fuseCount = 3 + seed % 2, runLabel = "TEST" })
		assert(#map.doors > 0, "no doors")
		assert(#map.lockers > 5, "too few lockers: " .. #map.lockers)
		assert(map.elevator and map.elevator.zone, "no elevator")
		assert(#map.startSpawns == 6, "spawns")
		for _, stationName in ipairs({ "Terminal", "ExitPanel" }) do
			assert(map.stations[stationName], "missing station " .. stationName)
		end
		if chainName == "PowerGrid" then
			assert(map.stations.FuseBox and map.stations.Breaker, "missing electrical stations")
			assert(#map.stations.FuseBox.slots == 3 + seed % 2, "fuse slot count")
		else
			assert(map.stations.Generator, "missing generator")
		end
		for index in ipairs(layout.cells) do
			assert(#map.itemSpots[index] > 0 or layout.cells[index].special or layout.cells[index].kind == "Start", "cell without item spot " .. index)
		end
		local special = 0
		for _, door in ipairs(map.doors) do
			if door.special then
				special += 1
			end
			assert(door.panel and door.openCFrame and door.closedCFrame, "door incomplete")
		end
		assert(special == 3, "expected 3 special doors, got " .. special)
		map:setPower(true)
		map:setPower(false)
		table.insert(maps, map)
		if seed > 3 then
			map:destroy()
		end
	end
end)

check("lobby builds with ready pad, boards, specimen and practice locker", function()
	local LobbyBuilder = requireModule(Services.LobbyBuilder)
	local lobby = LobbyBuilder.build()
	assert(lobby.spawnCFrame and lobby.padZone and lobby.statusLabel and lobby.recordLabel)
	assert(lobby.folder:FindFirstChild("SpecimenExhibit"):FindFirstChild("Specimen"), "specimen missing")
	local specimenRoot = lobby.folder.SpecimenExhibit.Specimen:FindFirstChild("HumanoidRootPart")
	assert(specimenRoot.CFrame.Position.Y > lobby.origin.Y, "specimen is not standing in the lobby")
	assert(lobby:isOnPad(lobby.padZone.CFrame.Position), "pad centre should count as on the pad")
	assert(not lobby:isOnPad(lobby.spawnCFrame.Position), "spawn should not be on the pad")
	lobby:setStatus("2 / 3 READY")
	lobby:setRecord("LAST RUN: ESCAPED")
	lobby:wirePracticeLocker({ get = function()
		return nil
	end })
end)

check("flashlight model builds with a lens that switches on and off", function()
	local FlashlightModel = requireModule(Shared.FlashlightModel)
	local model, lens = FlashlightModel.build("Test")
	assert(model.PrimaryPart and lens, "missing parts")
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			assert(not d.CanCollide and d.Massless, "flashlight part would affect physics: " .. d.Name)
		end
	end
	assert(parts >= 8, "too few parts")
	FlashlightModel.setLens(lens, true)
	assert(lens.Material == roblox.Enum.Material.Neon)
	FlashlightModel.setLens(lens, false)
	assert(lens.Material == roblox.Enum.Material.Glass)
end)

check("The Listener model builds with a full Motor6D rig", function()
	local model, root, humanoid, head = MonsterModel.build(roblox.CFrame.new(10, 0, 10))
	assert(model.PrimaryPart == root and humanoid and head)
	local motors = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors += 1
		end
	end
	assert(motors >= 17, "expected >=17 motors, got " .. motors)
	assert(math.abs(humanoid.HipHeight - 5) < 1e-6)
end)

-- Service wiring with stub remotes
local function stubRemote()
	return { FireAllClients = function() end, FireClient = function() end, OnServerEvent = signal() }
end
local remotes = setmetatable({}, {
	__index = function(t, k)
		local r = stubRemote()
		rawset(t, k, r)
		return r
	end,
})

check("services initialise and objectives set up on a built map", function()
	local registry = { Remotes = remotes, SoundConfig = requireModule(Shared.Config.SoundConfig) }
	for _, name in ipairs({ "DataService", "PlayerService", "NoiseService", "DoorService", "HidingService", "ItemService", "ObjectiveService", "MonsterService", "HorrorEventService", "RoundService" }) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs({ "DataService", "PlayerService", "NoiseService", "DoorService", "HidingService", "ItemService", "ObjectiveService", "MonsterService", "HorrorEventService", "RoundService" }) do
		registry[name].init(registry)
	end
	assert(#maps >= 2, "map building failed earlier")
	for i, map in ipairs({ maps[1], maps[2] }) do
		registry.ItemService.setFolder(map.itemsFolder)
		registry.NoiseService.setMap(map)
		registry.DoorService.createFromMap(map)
		registry.HidingService.createFromMap(map)
		local chainName = if i == 1 then "Generator" else "PowerGrid"
		local difficulty = registry.RoundService.difficulty()
		registry.ObjectiveService.begin(map, ObjectiveConfig.Chains[chainName], Rng.new(i), difficulty, {})
		local locked = 0
		for _, door in ipairs(registry.DoorService.all()) do
			if door.locked then
				locked += 1
			end
		end
		assert(locked == 3, "expected 3 locked special doors, got " .. locked)
		local fuses = registry.ItemService.countWorld(if chainName == "PowerGrid" then "Fuse" else "FuelCan")
		local needed = if chainName == "PowerGrid" then 3 else 2
		assert(fuses >= needed + difficulty.ItemSpares, "not enough objective items spawned: " .. fuses)
		assert(registry.ItemService.countWorld("Keycard") == 1, "keycard count")
		assert(registry.ItemService.countWorld("Note") == ObjectiveConfig.LoreNotesPerRun, "notes")
		registry.ObjectiveService.stop()
		registry.ItemService.clear()
	end
end)

check("noise events reach the Listener's brain with an approximate position", function()
	-- No physics in Lune: raycasts report a clear line, so occlusion is 1.
	roblox.implementMethod("Workspace", "Raycast", function()
		return nil
	end)
	local NoiseService = requireModule(Services.NoiseService)
	local MonsterBrain = requireModule(Shared.MonsterBrain)
	local MonsterConfig = requireModule(Shared.Config.MonsterConfig)
	NoiseService.init({ Remotes = remotes })
	NoiseService.setMap(nil)
	local brain = MonsterBrain.new(MonsterConfig, Rng.new(9), {
		patrolPoint = function(from)
			return from
		end,
		searchPoints = function(center)
			return { { position = center } }
		end,
	})
	local ear = roblox.Vector3.new(0, 10, 0)
	local unlisten = NoiseService.addListener({
		getEar = function()
			return ear
		end,
		hearingMultiplier = function()
			return 1
		end,
		exclude = function()
			return {}
		end,
		onHear = function(stimulus)
			brain:hear(stimulus, os.clock())
		end,
	})
	-- A crouched footstep 30 studs away is inaudible.
	NoiseService:emit("FootstepCrouch", roblox.Vector3.new(30, 0, 0), {})
	assert(brain.state == "Patrol", "heard a crouch step at 30 studs")
	-- A dropped metal object at the same spot is heard and investigated.
	local source = roblox.Vector3.new(30, 0, 0)
	NoiseService:emit("MetalDrop", source, {})
	assert(brain.state == "Investigate", "metal drop not investigated: " .. brain.state)
	local offset = (brain.investigatePos - source).Magnitude
	assert(offset <= 9.01, "estimate too far off: " .. offset)
	unlisten()
end)

---------------------------------------------------------------------------------------------
-- Client UI
---------------------------------------------------------------------------------------------

fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
fakeEvent("Player", "CharacterAdded")
fakeEvent("TextButton", "Activated")
roblox.implementMethod("RemoteEvent", "FireServer", function() end)
local attributeSignals = setmetatable({}, { __mode = "k" })
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
	attributeSignals[self] = attributeSignals[self] or {}
	attributeSignals[self][name] = attributeSignals[self][name] or signal()
	return attributeSignals[self][name]
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return signal()
end)

check("client controllers initialise and render sample state", function()
	requireModule(Shared.Net).setup()
	local localPlayer = roblox.Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.UserId = 0
	localPlayer.DisplayName = "Tester"
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = localPlayer
	localPlayer:SetAttribute("DA_Status", "Lobby")
	fakePlayers.LocalPlayer = localPlayer
	stubServices.RunService.IsServer = function()
		return false
	end

	local controllersFolder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("DeadAirClient"):FindFirstChild("Controllers")
	local controllers = {}
	for _, name in ipairs({ "ClientState", "Settings", "InputController", "CameraController", "HudController", "MenuController", "AudioController", "EffectsController", "HorrorController", "MonsterAnimator" }) do
		controllers[name] = requireModule(controllersFolder[name])
		controllers[name].init()
	end
	local ClientState = controllers.ClientState
	ClientState.PartyChanged:Fire({
		members = {
			{ userId = 0, name = "Tester", ready = true, status = "Lobby", level = 3, host = true },
			{ userId = 2, name = "Friend", ready = false, status = "Alive", level = 1, host = false },
		},
		difficulty = "Hard",
		pressure = 2,
		state = "Lobby",
	})
	local chain = requireModule(Shared.ObjectiveChain).new(ObjectiveConfig.Chains.PowerGrid)
	chain:complete("find_keycard")
	ClientState.ObjectiveChanged:Fire(chain:snapshot())
	ClientState.inventory = { "Fuse", "Keycard", "Bottle" }
	ClientState.InventoryChanged:Fire(ClientState.inventory)
	ClientState.setSlot(2)
	local ProgressionConfig = requireModule(Shared.Config.ProgressionConfig)
	local profile = {
		xp = 420, level = 2, levelXp = 250, nextLevelXp = 636,
		stats = { Runs = 3, Escapes = 1, Deaths = 2, ItemsCollected = 9, LoreFound = 2, Revives = 1, BlackBoxes = 0, ObjectivesCompleted = 5 },
		unlocked = { Standard = true }, equipped = "Standard",
		settings = { Master = 0.8, Music = 0.5, Sfx = 1, Sensitivity = 1.2, Fov = 80, Brightness = 0.1, HeadBob = false, ReduceFlicker = true, CameraShake = false, LargeText = true },
		cosmetics = ProgressionConfig.Cosmetics, persistent = false, loreCount = 2,
	}
	ClientState.profile = profile
	ClientState.ProfileChanged:Fire(profile)
	controllers.MenuController.toggleProfile(true)
	controllers.MenuController.toggleSettings(true)
	ClientState.LoreReceived:Fire({ id = "x", title = "TEST NOTE", body = "Body text." })
	ClientState.ResultsReceived:Fire({
		outcome = "Escaped", title = "BLACKOUT PROTOCOL", difficulty = "Hard", seed = 1,
		stepsCompleted = 6, totalSteps = 6, pressureNext = 1,
		players = { { name = "Tester", userId = 0, status = "Escaped", items = 4, revives = 1 } },
		xp = { lines = { { label = "Escaped", amount = 120 } }, total = 168, multiplier = 1.4, levelBefore = 2, levelAfter = 3, unlocks = { "Sodium Amber" } },
	})
	controllers.HudController.notify("Power restored.", "danger")
	localPlayer:SetAttribute("DA_Status", "Alive")
	ClientState.RoundChanged:Fire("Playing", {})
	assert(playerGui:FindFirstChild("DeadAirHUD") and playerGui:FindFirstChild("DeadAirMenu"), "GUIs missing")
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were swallowed by signal handlers / controller init", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
