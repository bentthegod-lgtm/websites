--[[
	Headless harness for CHAOS KARTS.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation. Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, rendering) are stubbed, time is a fake clock the tests
	advance, and workspace:Raycast is answered from the analytic TrackQuery (the same track
	data the TrackBuilder builds parts from). Player karts are driven by a "client sim":
	the real KartPhysics + BotBrain feeding KartState to the real server, at 20 Hz.

	Usage (from chaos-karts/):
	  rojo build -o build/ChaosKarts.rbxlx && lune run tests/harness build/ChaosKarts.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/ChaosKarts.rbxlx"
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
local isStudio = true
local heldKeys = {}
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
	SocialService = stubObject("SocialService", {
		PromptGameInvite = function() end,
		CanSendGameInviteAsync = function()
			return true
		end,
	}),
	UserInputService = stubObject("UserInputService", {
		TouchEnabled = true,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
		IsKeyDown = function(_, key)
			return heldKeys[key] == true
		end,
		IsGamepadButtonDown = function(_, _pad, key)
			return heldKeys[key] == true
		end,
		GetGamepadState = function()
			return {}
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetMouseLocation = function()
			return roblox.Vector2.new(640, 360)
		end,
	}),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
	TextChatService = stubObject("TextChatService"),
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
			d.Position = d.CFrame.Position
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
-- Raycasts: tests install a hook (default: nothing is hit).
local raycastHook = nil
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
	if raycastHook then
		return raycastHook(origin, direction, params)
	end
	return nil
end)
-- Terrain: Lune has no voxel engine; FillBlock calls are recorded.
local fills = {}
roblox.implementMethod("Terrain", "FillBlock", function(_, cf, size, material)
	table.insert(fills, { cf = cf, size = size, material = material })
end)
roblox.implementMethod("Terrain", "ReadVoxels", function()
	return {}, {}
end)
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = workspaceService
local clientSent = {}
local serverBridge = nil -- set by the client test: forwards FireServer to the server stubs
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	table.insert(clientSent, { name = self.Name, args = table.pack(...) })
	if serverBridge then
		serverBridge(self.Name, ...)
	end
end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
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
	for _, e in ipairs({ "MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged" }) do
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
	Rect = roblox.Rect,
	TweenInfo = stubCtor("TweenInfo"),
	RaycastParams = stubCtor("RaycastParams"),
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
local Shared = RS:FindFirstChild("ChaosKarts")
local ServerRoot = SSS:FindFirstChild("ChaosKartsServer")
local Services = ServerRoot:FindFirstChild("Services")

local GameConfig = requireModule(Shared.Config.GameConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local KartStats = requireModule(Shared.Config.KartStats)
local KP = requireModule(Shared.KartPhysics)
local BotBrain = requireModule(Shared.BotBrain)
local RaceMath = requireModule(Shared.RaceMath)
local EventRules = requireModule(Shared.EventRules)
local Registry = requireModule(Shared.Events.Registry)
local ChaosCity = requireModule(Shared.Maps.ChaosCity)
local V3, CF = roblox.Vector3, roblox.CFrame

-- Real product ids so ProcessReceipt can be exercised (config tables are plain tables).
ShopConfig.Products[1].ProductId = 7101 -- 500 coins
ShopConfig.Products[2].ProductId = 7102 -- 1500 coins

local function partsIn(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

check("all server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
	for _, m in ipairs(ServerRoot.World:GetChildren()) do
		requireModule(m)
	end
end)

local World = requireModule(ServerRoot.World.World)
local world
local buildReport = ""
check("fast startup: lobby at once, track + city built in chunks across frames (timed, part budget)", function()
	local t0 = os.clock()
	world = World.new(ChaosCity, workspaceService)
	local setup = os.clock() - t0
	assert(world.lobby.spawn:IsA("SpawnLocation") and world.lobby.portalPosition, "lobby")
	assert(not world.ready and world.plan.total > 1500, "nothing queued: " .. world.plan.total)
	local frames, worst, total = 0, 0, 0
	repeat
		local t1 = os.clock()
		local done = world:step(World.PartsPerStep)
		local dt = os.clock() - t1
		worst = math.max(worst, dt)
		total += dt
		frames += 1
	until done
	local parts = world:partCount()
	assert(world.ready and world.job.made == world.plan.total, "job incomplete")
	assert(parts <= 7000, "part budget: " .. parts)
	assert(frames >= math.floor(world.plan.total / World.PartsPerStep), "built in too few frames: " .. frames)
	assert(worst < 0.25, string.format("worst build frame %.1f ms", worst * 1000))
	assert(setup < 1.5, string.format("synchronous setup took %.2fs", setup))
	local track = world.root.Track
	assert(#track.Ground:GetChildren() > 300 and #track.Walls:GetChildren() > 200, "ground / walls")
	assert(#world.startLights == 5, "start lights")
	for _, folder in ipairs({ "Checkpoints", "ItemSpots", "EventZones" }) do
		assert(track:FindFirstChild(folder) and #track[folder]:GetChildren() > 0, folder)
	end
	local ground = 0
	for _, p in ipairs(track.Ground:GetChildren()) do
		assert(p:GetAttribute("Surface") and p:GetAttribute("Course"), p.Name .. " lacks Surface / Course")
		ground += 1
	end
	assert(world.root:FindFirstChild("City") and partsIn(world.root.City) > 400, "the city is thin: " .. partsIn(world.root.City))
	buildReport = string.format("%d parts total (track %d, city %d, lobby %d); setup %.0f ms, %d build frames, worst %.1f ms, build total %.2fs", parts, world.plan.track, world.plan.city, world.lobby.partCount, setup * 1000, frames, worst * 1000, total)
	print("        " .. buildReport)
end)

check("the built track matches the analytic track (road parts under the racing line, walls at the edges)", function()
	local data = world.data
	local main = data.main
	local roads = 0
	for _, p in ipairs(world.root.Track.Ground:GetChildren()) do
		if p.Name == "Road" and p:GetAttribute("Course") == "main" then
			roads += 1
			local top = p.CFrame * CF.new(0, p.Size.Y / 2, 0)
			local hit = main:project(top.Position)
			assert(hit and math.abs(hit.lateral) < 3 and math.abs(hit.height - top.Position.Y) < 1.2, "road part off the line at " .. tostring(top.Position))
		end
	end
	assert(roads > 150 and roads < 1200, "road segments " .. roads)
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
		if list[i].player == player or (player == nil and list[i].all) then
			return list[i]
		end
	end
	return nil
end

local registry
local ORDER = { "DataService", "ShopService", "RewardService", "PlayerService", "KartEffects", "KartService", "BotService", "EventDirector", "RaceService", "LeaderboardService" }
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
	for _, name in ipairs(registry.DataService.LEAVE_HOOKS) do
		assert(registry[name] and registry[name].onPlayerRemoving, name .. " in LEAVE_HOOKS has no onPlayerRemoving")
	end
	for _, name in ipairs(ORDER) do
		if registry[name].onPlayerRemoving then
			assert(table.find(registry.DataService.LEAVE_HOOKS, name), name .. " missing from LEAVE_HOOKS")
		end
	end
end)

local RSv, KS, BS, ED, KE, DS, RW, SH
local nextUserId = 7000
local function setPos(part, position)
	part.CFrame = CF.new(position)
	part.Position = position
end
local function newCharacter(name, position)
	local character = roblox.Instance.new("Model")
	character.Name = name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3.new(2, 2, 1)
	setPos(root, position)
	root.Anchored = false
	root.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspaceService
	return character, root
end
local function makePlayer(name)
	nextUserId += 1
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = nextUserId
	player.Parent = place:GetService("Players")
	local character = newCharacter(name, world.lobby.spawnCFrame.Position + V3.new(0, 3, 0))
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	player.CharacterAdded:Fire(character)
	flushDeferred()
	return player
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

-- Client sims: a player's kart driven like the real client (KartPhysics + an input
-- source), sending KartState at the client send rate.
local sims = {}
local SEND = 1 / GameConfig.Net.SendRate
local function simFor(player)
	local s = sims[player]
	if not s then
		s = { player = player, acc = 0, sendAcc = 0, seq = 0, mode = "drive", brain = BotBrain.new(player.UserId, 0.98) }
		sims[player] = s
	end
	return s
end
local function simStart(player)
	local s = simFor(player)
	local racer = RSv.racerOf(player)
	s.state = KP.new(world.data.grid[racer.slot])
	s.acc, s.sendAcc, s.mode = 0, 0, "drive"
	s.brain = BotBrain.new(player.UserId, 0.98)
	s.corrections = 0
	return s
end
local function simSend(s)
	s.seq += 1
	local st = s.state
	remotes.KartState.OnServerEvent:Fire(s.player, st.pos, st.vel, st.yaw, KP.flags(st), s.seq)
end
-- apply what the server told this client (respawns, corrections, effects)
local seenIndex = {}
local function simInbox(s)
	for _, name in ipairs({ "KartRespawn", "KartCorrect", "KartEffect" }) do
		local list = log[name] or {}
		local key = name .. tostring(s.player.UserId)
		for i = (seenIndex[key] or 0) + 1, #list do
			local e = list[i]
			if e.player == s.player then
				if name == "KartRespawn" then
					KP.respawn(s.state, e.args[1], e.args[2])
				elseif name == "KartCorrect" then
					s.corrections += 1
					KP.respawn(s.state, e.args[1], 0)
					s.state.vel = e.args[2]
				else
					KP.applyEffect(s.state, e.args[1], e.args[2])
				end
			end
		end
		seenIndex[key] = #list
	end
end
local function simStep(s, dt)
	simInbox(s)
	if not s.state or s.mode == "idle" then
		return
	end
	local phase = RSv.phase()
	s.acc += dt
	while s.acc >= KartStats.FixedStep - 1e-9 do
		s.acc -= KartStats.FixedStep
		local input = {}
		if phase == "Racing" then
			if s.mode == "drive" then
				input = BotBrain.think(s.brain, s.state, world.data.main, KartStats.FixedStep)
			elseif s.mode == "reverse" then
				input = { brake = 1 }
			elseif type(s.mode) == "function" then
				input = s.mode(s) or {}
			end
		end
		if phase == "Countdown" then
			local hold = s.state.pos
			KP.step(s.state, {}, world.query, KartStats.FixedStep)
			s.state.pos = V3.new(hold.X, s.state.pos.Y, hold.Z)
			s.state.vel = V3.new()
		else
			KP.step(s.state, input, world.query, KartStats.FixedStep)
		end
	end
	s.sendAcc += dt
	if s.sendAcc >= SEND then
		s.sendAcc -= SEND
		simSend(s)
	end
end

local DT = 1 / 30
local function tick(seconds, script)
	local t = 0
	while t < seconds - 1e-9 do
		advance(DT)
		t += DT
		for _, s in pairs(sims) do
			if s.player.Parent then
				simStep(s, DT)
			end
		end
		if script then
			script(DT)
		end
		RSv.step(DT)
	end
	flushDeferred()
end
local function untilPhase(name, limit)
	local guard = 0
	while RSv.phase() ~= name do
		tick(DT * 3)
		guard += DT * 3
		assert(guard < (limit or 600), "never reached phase " .. name .. " (at " .. RSv.phase() .. ")")
	end
end
local alice, bob, carl, dan
check("players join: default profile, leaderstats, told saving is off, lobby state sent", function()
	RSv, KS, BS, ED, KE, DS, RW, SH = registry.RaceService, registry.KartService, registry.BotService, registry.EventDirector, registry.KartEffects, registry.DataService, registry.RewardService, registry.ShopService
	alice = makePlayer("Alice")
	bob = makePlayer("Bob")
	local p = DS.getProfile(alice)
	assert(p and p.Coins == 0 and p.XP == 0 and p.Vehicle == "Sparkplug" and next(p.BestLaps) == nil, "bad default profile")
	assert(not DS.isPersistent(alice) and count("Notify", "saving is unavailable", alice) >= 1)
	assert(alice:FindFirstChild("leaderstats") and alice.leaderstats.Wins.Value == 0 and alice.leaderstats.Level.Value == 1)
	assert(count("RaceState", nil, alice) > 0, "race state not sent")
	assert(RSv.phase() == "Lobby")
	registry.PlayerService.prompts.Shop.Triggered:Fire(alice)
	assert(lastFor("OpenMenu", alice).args[1] == "Shop", "shop kiosk")
end)

local race1
local lapReport = ""
check("lobby -> queue (portal pad + READY) -> grid with bots -> countdown -> race", function()
	-- Alice walks onto the portal pad, Bob presses READY
	local root = alice.Character.HumanoidRootPart
	setPos(root, world.lobby.portalPosition + V3.new(2, 3, 0))
	tick(DT * 2)
	assert(RSv.isQueued(alice) and alice:GetAttribute("CK_Queued"), "portal pad didn't queue")
	assert(RSv.phase() == "Lobby", "started with one of two ready")
	assert(RSv.state().queued == 1)
	remotes.SetReady.OnServerEvent:Fire(bob, "yes")
	remotes.SetReady.OnServerEvent:Fire(bob, true)
	tick(DT * 2)
	assert(RSv.phase() == "Countdown", "no countdown when everyone is ready: " .. RSv.phase())
	race1 = RSv.race()
	assert(#race1.racers == GameConfig.Bots.FillTo, "grid size " .. #race1.racers)
	local humansN, botsN = 0, 0
	for i, r in ipairs(race1.racers) do
		assert(r.slot == i, "slots")
		assert((r.kart.pos - world.data.grid[i].Position).Magnitude < 1e-3, "not on the grid")
		if r.kind == "player" then
			humansN += 1
		else
			botsN += 1
		end
	end
	assert(humansN == 2 and botsN == 6, "players / bots")
	assert(alice.Character.HumanoidRootPart.Anchored, "character not parked")
	local state = lastFor("RaceState", nil).args[1]
	assert(state.phase == "Countdown" and #state.racers == 8 and state.goAt > workspaceService:GetServerTimeNow(), "race state")
	simStart(alice)
	simStart(bob)
	-- during the countdown karts are held: a client trying to creep forward is corrected
	tick(1)
	local before = count("KartCorrect", nil, alice)
	remotes.KartState.OnServerEvent:Fire(alice, race1.byPlayer[alice].kart.pos + V3.new(0, 0, -20), V3.new(), 0, 0, 10 ^ 6)
	assert(count("KartCorrect", nil, alice) == before + 1, "creeping off the grid wasn't corrected")
	sims[alice].seq = 10 ^ 6
	untilPhase("Racing", 10)
	assert(math.abs(workspaceService:GetServerTimeNow() - race1.goAt) < 0.1, "GO late")
end)

check("speed hack rejected: an impossible jump is refused and teleported back", function()
	tick(3)
	local racer = race1.byPlayer[alice]
	local good = racer.kart.pos
	local rejected = KS.rejected
	local corrections = count("KartCorrect", "", alice)
	sims[alice].seq += 1
	local ok, why = KS.onState(alice, good + V3.new(0, 0, -400), V3.new(0, 0, -90), 0, 0, sims[alice].seq)
	assert(not ok and why == "speed", "teleport accepted: " .. tostring(why))
	assert(KS.rejected == rejected + 1 and (racer.kart.pos - good).Magnitude < 1e-6, "state changed")
	assert(count("KartCorrect", nil, alice) > corrections - 1 and lastFor("KartCorrect", alice).args[3] == "speed", "no teleport-back")
	-- junk arguments never crash and never move the kart
	for _, args in ipairs({ { "x" }, { V3.new(0 / 0, 0, 0), V3.new(), 0, 0, 1e9 }, { good, V3.new(1e6, 0, 0), 0, 0, 1e9 + 1 }, { good, V3.new(), "yaw", 0, 1e9 + 2 } }) do
		remotes.KartState.OnServerEvent:Fire(alice, table.unpack(args))
	end
	assert((racer.kart.pos - good).Magnitude < 1e-6, "junk moved the kart")
	tick(1)
	assert(sims[alice].corrections >= 1 and (racer.kart.pos - good).Magnitude > 1, "the client didn't recover after the correction")
end)

check("late joiner spectates (queued for the next race), bots + players race 3 laps, DNF timer after the first finisher", function()
	dan = makePlayer("Dan")
	assert(not RSv.racerOf(dan) and RSv.isQueued(dan), "late joiner not spectating + queued")
	assert(count("Notify", "spectating", dan) >= 1)
	local bobIdleAt = nil
	local firstFinishAt = nil
	local guard = 0
	while RSv.phase() == "Racing" do
		tick(1, function()
			local r = race1.byPlayer[bob]
			if r and not bobIdleAt and r.progress.lap >= 2 then
				bobIdleAt = workspaceService:GetServerTimeNow()
				sims[bob].mode = "idle" -- Bob stops after a lap: he will be a DNF
			end
			if race1.dnfAt and not firstFinishAt then
				firstFinishAt = workspaceService:GetServerTimeNow()
			end
		end)
		guard += 1
		assert(guard < 600, "race never ended")
	end
	assert(RSv.phase() == "Results", "phase " .. RSv.phase())
	assert(firstFinishAt and bobIdleAt, "nobody finished / Bob never stopped")
	local summary = RSv.lastResults
	assert(summary.reason == "dnf", "race ended by " .. tostring(summary.reason))
	local ended = workspaceService:GetServerTimeNow()
	assert(ended - firstFinishAt >= GameConfig.Race.DnfTimer - 1.2 and ended - firstFinishAt <= GameConfig.Race.DnfTimer + 1.5, "DNF timer " .. (ended - firstFinishAt))
	-- lap times: every bot / sim that finished did 3 laps in the target window
	local times = {}
	local finishedBots = 0
	local window = ChaosCity.TargetLap
	for _, r in ipairs(race1.racers) do
		if r.progress.finished then
			assert(#r.progress.lapTimes == 3, r.name .. " lap count")
			local sum = 0
			for _, t in ipairs(r.progress.lapTimes) do
				sum += t
			end
			local avg = sum / 3
			table.insert(times, string.format("%s %s", r.name, table.concat((function()
				local s = {}
				for _, t in ipairs(r.progress.lapTimes) do
					table.insert(s, string.format("%.1f", t))
				end
				return s
			end)(), "/")))
			assert(avg >= window[1] and avg <= window[2], string.format("%s average lap %.1f s outside %d-%d", r.name, avg, window[1], window[2]))
			assert(r.progress.best >= window[1] - 2 and r.progress.best <= window[2], string.format("%s best lap %.1f", r.name, r.progress.best))
			if r.kind == "bot" then
				finishedBots += 1
			end
		end
	end
	assert(finishedBots >= 4, "only " .. finishedBots .. " bots finished 3 laps")
	assert(race1.byPlayer[alice].progress.finished, "Alice (client sim) didn't finish")
	lapReport = table.concat(times, "; ")
	print("        laps: " .. lapReport)
	-- Bob is a DNF, placed after every finisher
	local bobRow
	for _, row in ipairs(summary.rows) do
		if row.id == "p" .. bob.UserId then
			bobRow = row
		end
	end
	assert(bobRow and bobRow.dnf and bobRow.place > race1.finished, "Bob not a DNF at the back")
	assert(#summary.rows == 8)
end)

check("results + rewards saved to the profile (coins, XP, races, wins, best lap); leaderboards fed", function()
	local pa, pb = DS.getProfile(alice), DS.getProfile(bob)
	local resA = lastFor("Results", alice).args[1]
	local resB = lastFor("Results", bob).args[1]
	assert(resA.you and resB.you and resB.you.dnf and not resA.you.dnf, "personal results")
	assert(pa.Coins == resA.you.coins and pa.Coins > pb.Coins and pb.Coins == resB.you.coins, string.format("coins %d / %d", pa.Coins, pb.Coins))
	assert(resB.you.coins == GameConfig.Rewards.Participation + (if resB.you.newBest then GameConfig.Rewards.BestLapBonus else 0), "DNF pay")
	assert(pa.XP > 0 and pb.XP == GameConfig.Rewards.ParticipationXP, "xp")
	assert(pa.Stats.Races == 1 and pb.Stats.Races == 1 and pa.Stats.Finishes == 1)
	assert(pa.BestLaps.ChaosCity and math.abs(pa.BestLaps.ChaosCity - race1.byPlayer[alice].progress.best) < 1e-6, "best lap not saved")
	if resA.you.place == 1 then
		assert(pa.Stats.Wins == 1 and alice.leaderstats.Wins.Value == 1)
	end
	assert(lastFor("Profile", alice), "profile not resent")
	-- back to the lobby: characters unparked, then Dan's queued race auto-starts
	tick(GameConfig.Race.ResultsTime + 0.5)
	assert(RSv.phase() == "Lobby" or RSv.phase() == "Countdown", "after results: " .. RSv.phase())
	assert(not alice.Character.HumanoidRootPart.Anchored, "character still parked")
end)

local race2
check("next race: the spectator races; checkpoint skip rejected; respawn (rate-limited, ghosted); wrong way", function()
	carl = makePlayer("Carl")
	remotes.SetReady.OnServerEvent:Fire(carl, true)
	assert(RSv.isQueued(dan) and RSv.isQueued(carl), "queue")
	local st = RSv.state()
	assert(st.queued == 2 and st.autoStartIn, "lobby queue state: " .. tostring(st.queued) .. " " .. tostring(st.autoStartIn) .. " " .. RSv.phase())
	untilPhase("Countdown", GameConfig.Race.AutoStartAfter + 5)
	race2 = RSv.race()
	assert(race2.byPlayer[dan] and race2.byPlayer[carl], "the spectator / new player isn't racing")
	assert(not race2.byPlayer[alice], "Alice raced without readying")
	simStart(dan)
	simStart(carl)
	untilPhase("Racing", 10)
	tick(8)
	-- checkpoint skip: Carl drives (at a legal speed) straight across the city to the line
	local racer = race2.byPlayer[carl]
	local lap, nextCp = racer.progress.lap, racer.progress.nextCp
	assert(lap == 1 and nextCp >= 2, "carl hasn't started properly")
	local from = racer.kart.pos
	local to = world.data.main:point(world.data.main.length - 15, 0) + V3.new(0, 1.4, 0)
	local over = world.data.main:point(25, 0) + V3.new(0, 1.4, 0)
	sims[carl].mode = "idle"
	local function slide(a, b)
		local d = (b - a).Magnitude
		local steps = math.ceil(d / 4)
		for i = 1, steps do
			advance(SEND)
			sims[carl].seq += 1
			local p = a:Lerp(b, i / steps)
			KS.onState(carl, p, (b - a).Unit * 80, 0, 0, sims[carl].seq)
		end
	end
	slide(from, to)
	slide(to, over)
	assert(racer.progress.lap == lap and racer.progress.nextCp == nextCp, "a cut counted: lap " .. racer.progress.lap)
	assert(racer.progress.skips >= 1 and count("RaceEvent", "skip", carl) >= 1, "skip not flagged")
	-- respawn: back to the last checkpoint, facing the track, ghosted; spam is rate-limited
	local respawns = count("KartRespawn", nil, carl)
	remotes.Respawn.OnServerEvent:Fire(carl, "button")
	remotes.Respawn.OnServerEvent:Fire(carl, "button")
	assert(count("KartRespawn", nil, carl) == respawns + 1, "respawn not rate-limited")
	local cf = lastFor("KartRespawn", carl).args[1]
	local gate = race2.gates[nextCp - 1]
	assert((cf.Position - gate.cframe.Position).Magnitude < 4 and cf.LookVector:Dot(gate.cframe.LookVector) > 0.99, "respawn spot / facing")
	assert(workspaceService:GetServerTimeNow() < racer.ghostUntil, "no ghost window")
	assert(not KE.apply(racer, "spinOut", {}, "test"), "ghosted kart was hit")
	sims[carl].state = KP.new(cf)
	sims[carl].mode = "drive"
	tick(4)
	advance(GameConfig.AntiCheat.RespawnCooldown)
	remotes.Respawn.OnServerEvent:Fire(carl, "button")
	assert(count("KartRespawn", nil, carl) == respawns + 2, "second respawn after the cooldown refused")
	sims[carl].state = KP.new(lastFor("KartRespawn", carl).args[1])
	-- wrong way: Dan turns around and drives backwards
	local s = sims[dan]
	s.mode = function(sim)
		local st = sim.state
		local hit = world.data.main:project(st.pos)
		local back = -hit.flat
		local fwd = KP.forward(st.yaw)
		local right = V3.new(-fwd.Z, 0, fwd.X)
		local steer = math.clamp(math.atan2(back:Dot(right), back:Dot(fwd)) * 2, -1, 1)
		return { gas = 0.7, steer = steer }
	end
	local guard = 0
	while not dan:GetAttribute("CK_WrongWay") and guard < 12 do
		tick(0.5)
		guard += 0.5
	end
	assert(dan:GetAttribute("CK_WrongWay") == true and count("RaceEvent", "wrongway", dan) >= 1, "wrong way not detected")
	s.mode = "drive"
	s.brain = BotBrain.new(dan.UserId, 0.98)
	guard = 0
	while dan:GetAttribute("CK_WrongWay") and guard < 15 do
		tick(0.5)
		guard += 0.5
	end
	assert(not dan:GetAttribute("CK_WrongWay"), "wrong way never cleared")
end)

check("the reference event runs end to end: synced start, deterministic path, hits via KartEffects, full cleanup", function()
	ED.stopAll("test")
	local starts = count("EventStart")
	local inst, why = ED.trigger("QuackaroniParade", "NeonPlaza", true, 4242)
	assert(inst, "trigger failed: " .. tostring(why))
	local payload = lastFor("EventStart", nil).args[1]
	assert(count("EventStart") == starts + 1 and payload.id == "QuackaroniParade" and payload.seed == 4242 and payload.zone == "NeonPlaza", "payload")
	assert(payload.serverStartTime == inst.startAt and payload.serverStartTime - payload.warnAt == inst.def.warning, "timing")
	-- the client computes the same path from the payload
	local Quack = Registry.module("QuackaroniParade")
	local clientPath = Quack.path(payload.seed, world.data.zoneById[payload.zone], world.data)
	assert(clientPath.from == inst.ctx.path.from and clientPath.to == inst.ctx.path.to, "client / server paths differ")
	-- park a bot and Dan's kart right where the duck will be mid-walk
	local mid = inst.startAt + (inst.endAt - inst.startAt) * 0.5
	local pos = Quack.positionAt(inst.ctx.path, inst, mid)
	local bot
	for _, r in ipairs(race2.racers) do
		if r.kind == "bot" and not r.progress.finished then
			bot = r
			break
		end
	end
	local hitsBefore = #KE.log
	local danEffects = count("KartEffect", nil, dan)
	local hold = function()
		local spot = pos + V3.new(0, KartStats.RideHeight, 0)
		bot.bot.state.pos = spot
		bot.bot.state.vel = V3.new()
		bot.kart.pos = spot
		bot.ghostUntil = 0
		local dr = race2.byPlayer[dan]
		dr.kart.pos = spot + V3.new(3, 0, 0)
		dr.ghostUntil = 0
	end
	while workspaceService:GetServerTimeNow() < mid - 0.5 do
		tick(DT)
	end
	sims[dan].mode = "idle"
	bot.bot.state.ghostT = 0
	local botKick = 0
	for _ = 1, 30 do
		hold()
		advance(DT)
		ED.step(DT)
		botKick = math.max(botKick, bot.bot.state.vel.Magnitude)
	end
	local hitBot, hitDan = false, false
	for i = hitsBefore + 1, #KE.log do
		if KE.log[i].racer == bot.id and KE.log[i].kind == "knockback" and KE.log[i].source == "QuackaroniParade" then
			hitBot = true
		end
		if KE.log[i].racer == "p" .. dan.UserId then
			hitDan = true
		end
	end
	assert(hitBot and hitDan, "the parade didn't hit (bot " .. tostring(hitBot) .. ", dan " .. tostring(hitDan) .. ")")
	assert(count("KartEffect", nil, dan) == danEffects + 1 and lastFor("KartEffect", dan).args[1] == "knockback", "Dan's client wasn't told")
	assert(botKick > 20, "bot not knocked: " .. botKick)
	assert(inst.ctx.hits >= 2 and inst.ctx.hits <= 4, "hit cooldown not respected: " .. inst.ctx.hits)
	sims[dan].mode = "drive"
	-- it ends on time and everything is cleaned up
	local maid = inst.maid
	while ED.instances()[inst.instanceId] do
		tick(DT * 3)
	end
	assert(maid.cleaned and lastFor("EventStop", nil).args[1] == inst.instanceId, "not stopped / cleaned")
	assert(next(EventRules.newState().active) == nil and ED.state().active[inst.instanceId] == nil)
	-- the hard timeout: an instance whose module never ends is force-cleaned
	local stuck = ED.trigger("QuackaroniParade", "Park", true, 7)
	stuck.endAt = math.huge
	advance(stuck.hardEnd - workspaceService:GetServerTimeNow() + 0.1)
	ED.sweep()
	assert(not ED.instances()[stuck.instanceId] and stuck.maid.cleaned and stuck.stoppedBecause == "timeout", "hard timeout")
end)

check("final lap: the director runs hotter (shorter interval, intensity 3 unlocked) but inside the budget", function()
	local normal = ED.context()
	assert(not EventRules.isFinalLap(normal), "already the final lap?")
	local cfg = GameConfig.Events
	local normalGap = EventRules.interval(cfg, normal)
	-- the leader starts the final lap
	local leader = race2.racers[1]
	leader.progress.lap = GameConfig.Race.Laps
	local final = ED.context()
	assert(EventRules.isFinalLap(final) and final.lap == 3, "final lap not seen")
	assert(EventRules.interval(cfg, final) < normalGap, "final-lap interval not shorter")
	-- the director schedules with the final-lap interval
	ED.state().nextAt = workspaceService:GetServerTimeNow()
	ED.stopAll("test")
	ED.state().cooldowns = {} -- (the earlier tests used the only implemented event)
	ED.step(DT)
	local gap = ED.state().nextAt - workspaceService:GetServerTimeNow()
	assert(gap <= cfg.Interval * cfg.FinalLapIntervalMul * 1.25 + 1e-6, "scheduled gap " .. gap)
	local majors, minors = EventRules.activeCount(ED.state())
	assert(majors <= cfg.MaxMajor and minors <= cfg.MaxMinor)
	local last = ED.log[#ED.log]
	assert(last and last.final, "the final-lap pick wasn't logged as final")
	leader.progress.lap = 1
end)

check("leaving mid-race is clean: positions recomputed; the last human leaving aborts to the lobby", function()
	local before = #race2.racers
	leave(carl)
	assert(race2.racers[1] and #race2.racers == before and race2.byId["p" .. carl.UserId].left, "carl not marked as left")
	assert(RSv.phase() == "Racing", "race stopped with a human still in it")
	tick(1)
	for _, r in ipairs(race2.racers) do
		assert(r.left or r.place, "unranked racer")
	end
	assert(count("Announce", "left the race") >= 1)
	leave(dan)
	tick(DT)
	assert(RSv.phase() == "Lobby" and RSv.race() == nil, "not aborted: " .. RSv.phase())
	assert(next(ED.instances()) == nil, "events left running")
end)

check("daily streak once a day, codes RELEASE / CHAOS once each", function()
	local p = DS.getProfile(bob)
	local coins = p.Coins
	assert(RW.claimDaily(bob) and p.Coins == coins + GameConfig.DailyRewards[1])
	assert(not RW.claimDaily(bob), "claimed twice in a day")
	advance(86400)
	assert(RW.claimDaily(bob) and p.Daily.Streak == 2, "streak")
	local xp = p.XP
	assert(RW.redeem(bob, "release") and not RW.redeem(bob, "RELEASE"), "RELEASE")
	assert(RW.redeem(bob, "chaos") and p.XP == xp + GameConfig.Codes.CHAOS.XP, "CHAOS")
	assert(not RW.redeem(bob, "nope"))
end)

local function receipt(player, id, productId)
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = productId or 7101, PurchaseId = id })
end
check("receipts: granted exactly once when sent twice; refused when the profile can't persist live or is unknown", function()
	local gus = makePlayer("Gus")
	local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	local notYet = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	local p = DS.getProfile(gus)
	assert(receipt(gus, "r-1") == granted and p.Coins == 500 and p.Receipts["r-1"])
	assert(receipt(gus, "r-1") == granted and p.Coins == 500, "granted twice")
	assert(receipt(gus, "r-2", 7102) == granted and p.Coins == 2000)
	isStudio = false
	local hal = makePlayer("Hal")
	local decision = receipt(hal, "r-live")
	isStudio = true
	assert(decision == notYet and DS.getProfile(hal).Coins == 0, "live purchase granted on a non-persistent profile")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 999999, ProductId = 7101, PurchaseId = "x" }) == notYet, "unknown player")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = gus.UserId, ProductId = 4242, PurchaseId = "y" }) == notYet, "unknown product")
	leave(hal)
	isStudio = false
	SH.buy(gus, "NeonTrails")
	isStudio = true
	assert(count("Notify", "isn't available yet", gus) >= 1, "id 0 in a live game")
	leave(gus)
end)

check("settings / vehicle select: only known keys with legal values; vehicles are cosmetic and validated", function()
	local p = DS.getProfile(bob)
	registry.PlayerService.saveSettings(bob, { Music = 0.3, Master = 7, Effects = 0 / 0, CameraShake = "no", ReducedEffects = true, Hack = true })
	assert(p.Settings.Music == 0.3 and p.Settings.Master == 1, "numbers not clamped")
	assert(p.Settings.Effects == 1, "NaN accepted")
	assert(p.Settings.CameraShake == true and p.Settings.ReducedEffects == true and p.Settings.Hack == nil)
	remotes.SelectVehicle.OnServerEvent:Fire(bob, "BubblegumBumper")
	assert(p.Vehicle == "BubblegumBumper" and bob:GetAttribute("CK_Vehicle") == "BubblegumBumper")
	remotes.SelectVehicle.OnServerEvent:Fire(bob, "Batmobile")
	remotes.SelectVehicle.OnServerEvent:Fire(bob, { "x" })
	assert(p.Vehicle == "BubblegumBumper", "unknown vehicle accepted")
end)

check("remote spam and junk arguments are rejected", function()
	for _ = 1, 40 do
		remotes.SetReady.OnServerEvent:Fire(bob, true)
		remotes.Respawn.OnServerEvent:Fire(bob, string.rep("x", 999))
		remotes.KartState.OnServerEvent:Fire(bob, "a", "b")
	end
	remotes.RedeemCode.OnServerEvent:Fire(bob, string.rep("A", 5000))
	remotes.ShopBuy.OnServerEvent:Fire(bob, string.rep("x", 100))
	remotes.SaveSettings.OnServerEvent:Fire(bob, "loud")
	remotes.RequestState.OnServerEvent:Fire(bob)
	remotes.ClaimDaily.OnServerEvent:Fire(bob, 1, 2, 3)
	remotes.UseItem.OnServerEvent:Fire(bob, "x")
	assert(DS.getProfile(bob).Coins >= 0)
	remotes.SetReady.OnServerEvent:Fire(bob, false)
	advance(2)
	remotes.SetReady.OnServerEvent:Fire(bob, false)
	tick(DT)
end)
check("session lock: load locks, migration runs before defaults, a taken-over profile stops saving, leaving unlocks", function()
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
	local holdNext = false
	local fakeStore = {
		UpdateAsync = function(_, k, fn)
			if holdNext then
				holdNext = false
				coroutine.yield() -- a slow DataStore call: the test resumes it later
			end
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
		-- an old profile with no Version: migration must see it as version 1, not "current"
		stored["player_" .. (nextUserId + 1)] = { Coins = 777, XP = 0 / 0, BestLaps = { ChaosCity = -3, Moon = 88 }, Vehicle = "Hovercraft9000", Stats = { Wins = 5, Bad = "x" } }
		local ivy = makePlayer("Ivy")
		local key = "player_" .. ivy.UserId
		local p = DS.getProfile(ivy)
		assert(DS.isPersistent(ivy) and p.Coins == 777, "saved profile not loaded")
		assert(p.Version == GameConfig.SchemaVersion, "not migrated")
		assert(p.XP == 0 and p.BestLaps.ChaosCity == nil and p.BestLaps.Moon == 88 and p.Vehicle == "Sparkplug" and p.Stats.Bad == nil and p.Stats.Wins == 5, "saved data not validated")
		assert(type(stored[key].Lock) == "table", "profile not locked on load")
		p.Coins = 800
		assert(DS.save(ivy) and stored[key].Coins == 800, "save failed")
		stored[key].Lock = { Session = "other-server", At = fakeOs.time() }
		p.Coins = 1
		assert(not DS.save(ivy), "saved over another server's lock")
		assert(stored[key].Coins == 800 and not DS.isPersistent(ivy))
		isStudio = false
		local decision = receipt(ivy, "lock-1")
		isStudio = true
		assert(decision == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "granted after losing the lock")
		leave(ivy)
		assert(stored[key].Coins == 800, "left player overwrote the new owner")
		stored["player_" .. (nextUserId + 1)] = { Coins = 55, Lock = { Session = "crashed", At = fakeOs.time() - 100000 } }
		local jo = makePlayer("Jo")
		local joKey = "player_" .. jo.UserId
		assert(DS.isPersistent(jo) and DS.getProfile(jo).Coins == 55, "stale lock blocked the load")
		-- a purchase on a persistent profile is saved before it's granted
		assert(receipt(jo, "p-1") == roblox.Enum.ProductPurchaseDecision.PurchaseGranted and stored[joKey].Receipts["p-1"], "receipt not saved before granting")
		-- Roblox retries a receipt while the first call is still saving: not acknowledged early
		local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
		local coinsBefore = DS.getProfile(jo).Coins
		holdNext = true
		local slow = coroutine.create(function()
			return receipt(jo, "p-2")
		end)
		assert(coroutine.resume(slow) and coroutine.status(slow) == "suspended", "save didn't yield")
		assert(receipt(jo, "p-2") == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "acknowledged a receipt whose save is still in flight")
		local resumed, first = coroutine.resume(slow)
		assert(resumed and first == granted and stored[joKey].Receipts["p-2"], "slow save not granted")
		assert(receipt(jo, "p-2") == granted and DS.getProfile(jo).Coins == coinsBefore + 500, "granted twice")
		DS.getProfile(jo).Coins = 99
		leave(jo)
		assert(stored[joKey].Coins == 99 and stored[joKey].Lock == nil, "leave save did not persist and unlock")
	end)
	stubServices.DataStoreService.GetDataStore = function()
		error("DataStores are not available in the harness")
	end
	DS.init(registry)
	assert(ok, err)
end)
---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("every client controller initialises and runs a real race against the real server (bridged remotes, raycasts)", function()
	local kim = makePlayer("Kim")
	local Net = requireModule(Shared.Net)
	Net.setup()
	local netFolder = RS:FindFirstChild("ChaosKartsRemotes")
	-- bridge: server stubs -> the local client's real RemoteEvents, and FireServer -> server
	for _, name in ipairs(Net.Names) do
		local stub = remotes[name]
		local real = netFolder:FindFirstChild(name)
		local fireClient, fireAll = stub.FireClient, stub.FireAllClients
		stub.FireClient = function(self, player, ...)
			fireClient(self, player, ...)
			if player == kim then
				real.OnClientEvent:Fire(...)
			end
		end
		stub.FireAllClients = function(self, ...)
			fireAll(self, ...)
			real.OnClientEvent:Fire(...)
		end
	end
	serverBridge = function(name, ...)
		remotes[name].OnServerEvent:Fire(kim, ...)
	end
	-- raycasts answered from the analytic track (what the TrackBuilder built from)
	local fakeParts = {}
	local function fake(surface, course)
		local key = surface .. "/" .. course
		if not fakeParts[key] then
			local part = roblox.Instance.new("Part")
			part.Name = key
			part:SetAttribute("Surface", surface)
			part:SetAttribute("Course", course)
			fakeParts[key] = part
		end
		return fakeParts[key]
	end
	local rays = 0
	raycastHook = function(origin, direction)
		rays += 1
		local len = direction.Magnitude
		if direction.Y < -0.5 * len then
			local h, n, surface, course = world.query:ground(origin)
			if h and origin.Y - h <= len then
				return { Position = V3.new(origin.X, h, origin.Z), Normal = n, Instance = fake(surface, course), Distance = origin.Y - h }
			end
			return nil
		end
		local normal, depth = world.query:walls(origin, len)
		if normal and depth > 0 and direction.Unit:Dot(normal) < -0.3 then
			local d = math.max(0, len - depth)
			return { Position = origin + direction.Unit * d, Normal = normal, Instance = fake("Wall", "main"), Distance = d }
		end
		return nil
	end
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = kim
	fakePlayers.LocalPlayer = kim
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.CFrame = CF.new(0, 20, -900)
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera
	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("ChaosKartsClient"):FindFirstChild("Controllers")
	local names = { "ClientState", "AudioController", "InputController", "KartController", "RemoteKarts", "EffectsController", "SpectateController", "CameraController", "EventController", "HudController", "MenuController", "FrameLoop" }
	local c = {}
	for _, name in ipairs(names) do
		c[name] = requireModule(folder[name])
		c[name].init()
	end
	local CS, Hud, Kart, Remote, Cam, Fx, Ev, Input, Menu, Audio, Spec, Loop = c.ClientState, c.HudController, c.KartController, c.RemoteKarts, c.CameraController, c.EffectsController, c.EventController, c.InputController, c.MenuController, c.AudioController, c.SpectateController, c.FrameLoop
	remotes.RequestState.OnServerEvent:Fire(kim)
	flushDeferred()
	assert(CS.profile and CS.profile.vehicle == "Sparkplug", "profile didn't reach the client")
	assert(CS.race.phase == "Lobby", "race state didn't reach the client")
	for _, name in ipairs({ "KartHUD", "KartMenu", "KartFx", "KartTouch" }) do
		assert(playerGui:FindFirstChild(name) and playerGui[name]:FindFirstChildOfClass("UIScale"), name .. " missing / no UIScale")
	end
	local hud = playerGui.KartHUD
	local function frame(dt)
		return Loop.step(dt or DT)
	end
	local function run(seconds, fn)
		tick(seconds, function(dt)
			if fn then
				fn(dt)
			end
			frame(dt)
		end)
	end
	frame()
	assert(hud.Lobby.Visible and string.find(hud.Lobby.Status.Text, "queued", 1, true), "lobby panel: " .. hud.Lobby.Status.Text)
	assert(Cam.mode() == "lobby")
	-- READY through the real button -> the real server
	for _, p in ipairs(playerList) do
		if p ~= kim then
			RSv.setReady(p, false)
		end
	end
	hud.Lobby.Ready.Activated:Fire()
	assert(RSv.isQueued(kim) and CS.queued(), "READY button didn't queue")
	frame()
	assert(hud.Lobby.Ready.Text == "UNREADY")
	local guard = 0
	while RSv.phase() ~= "Countdown" do
		run(0.5)
		guard += 0.5
		assert(guard < GameConfig.Race.AutoStartAfter + 5, "auto-start never fired")
	end
	local race = RSv.race()
	assert(race.byPlayer[kim] and CS.inRace() and Kart.state() and Kart.model(), "client kart not spawned")
	local slotCF = world.data.grid[race.byPlayer[kim].slot]
	assert((Kart.state().pos - slotCF.Position).Magnitude < 0.5, "client kart not on its grid slot")
	run(0.6)
	assert(Cam.mode() == "intro" and camera.CameraType == roblox.Enum.CameraType.Scriptable, "no grid flyover: " .. Cam.mode())
	assert(Remote.count() == #race.racers - 1, "remote karts " .. Remote.count())
	-- the lights count down; gas in the last moment = a start boost
	while workspaceService:GetServerTimeNow() < race.goAt - 1.6 do
		run(DT)
	end
	assert(hud.Race.Lights.Visible and hud.Race.Countdown.Visible and hud.Race.Countdown.Text == "2", "countdown: " .. hud.Race.Countdown.Text)
	assert(Hud.worldLights() >= 2, "gantry lights")
	while workspaceService:GetServerTimeNow() < race.goAt - 0.2 do
		run(DT)
	end
	heldKeys[roblox.Enum.KeyCode.W] = true
	run(0.25)
	assert(RSv.phase() == "Racing" and hud.Race.Countdown.Text == "GO!", "GO")
	run(0.1)
	assert(Kart.state().boostT > 0, "no start boost")
	-- drive: physics on raycasts, states accepted by the server
	local accepted = KS.accepted
	run(4)
	assert(Kart.queryKind == "raycast" and rays > 1000, "not driving on raycasts")
	local me = race.byPlayer[kim]
	assert(KS.accepted > accepted + 50 and (me.kart.pos - slotCF.Position).Magnitude > 150, "server didn't follow the client kart")
	assert(Cam.mode() == "chase" and Cam.fov() > GameConfig.Camera.BaseFov + 2, "chase cam / FOV kick")
	assert(Fx.speedLineIntensity() > 0.05, "no speed lines at speed")
	frame()
	assert(hud.Race.Visible and hud.Race.Standing.Place.Text:match("%d+%a%a") and hud.Race.Standing.Lap.Text == "LAP 1/3", "race HUD: " .. hud.Race.Standing.Place.Text .. " " .. hud.Race.Standing.Lap.Text)
	assert(tonumber(hud.Race.Speedo.Value.Text) > 60, "speedometer " .. hud.Race.Speedo.Value.Text)
	assert(Hud.dotCount == #race.racers, "minimap dots " .. tostring(Hud.dotCount))
	assert(hud.Race.ItemSlot.Visible, "item slot placeholder")
	-- remote karts move smoothly between snapshots
	local bot = Remote.get("b1")
	local p1 = bot.pos
	run(0.5)
	assert(bot.pos and (bot.pos - p1).Magnitude > 10, "remote kart not interpolating")
	local a = bot.snaps[#bot.snaps - 1]
	local b2 = bot.snaps[#bot.snaps]
	local mid = Remote.sample(bot, (a.t + b2.t) / 2)
	assert((mid - (a.pos + b2.pos) / 2).Magnitude < 3, "interpolation off the path")
	-- drift: hop + steer, charge sparks, tire marks, then the boost on release
	heldKeys[roblox.Enum.KeyCode.LeftShift] = true
	heldKeys[roblox.Enum.KeyCode.D] = true
	run(1.2)
	local s = Kart.state()
	assert(s.drift == 1 and s.driftLevel >= 1, "no drift (" .. s.drift .. ")")
	frame()
	assert(hud.Race.Drift.Visible, "drift bar hidden")
	assert(Kart.rig().fx and Kart.rig().fx.sparks[1].Enabled, "no drift sparks")
	assert(Fx.markCount() > 4, "no tire marks")
	heldKeys[roblox.Enum.KeyCode.LeftShift] = nil
	heldKeys[roblox.Enum.KeyCode.D] = nil
	run(0.1)
	assert(Kart.state().boostT > 0 and Kart.rig().fx.flame.Enabled, "no mini-turbo boost / flame")
	-- respawn with R: server teleport to the last checkpoint, ghost flicker
	run(2)
	assert(Input.handle(roblox.Enum.KeyCode.R, true), "R didn't respawn")
	local respawn = lastFor("KartRespawn", kim)
	assert(respawn and (Kart.state().pos - respawn.args[1].Position).Magnitude < 3 and Kart.state().ghostT > 0, "client not respawned")
	run(1)
	-- the reference event, played on the client in sync with the server
	ED.stopAll("test")
	local inst = ED.trigger("QuackaroniParade", "NeonPlaza", true, 99)
	assert(inst, "trigger")
	local entry = Ev.active()[inst.instanceId]
	assert(entry and entry.ctx.duck and entry.ctx.folder:FindFirstChild("Quackaroni"), "client didn't play the event")
	frame()
	assert(hud.Race.EventBanner.Visible and string.find(hud.Race.EventBanner.Text, "QUACKARONI", 1, true), "no event warning banner")
	while workspaceService:GetServerTimeNow() < inst.startAt + 4 do
		run(DT)
	end
	local Quack = Registry.module("QuackaroniParade")
	local serverPos = Quack.positionAt(inst.ctx.path, inst, workspaceService:GetServerTimeNow())
	local duck = entry.ctx.duck
	assert((duck.PrimaryPart.CFrame.Position - serverPos).Magnitude < 1.5, "client duck out of sync with the server")
	local eventFolder = workspaceService:FindFirstChild("CK_Events")
	while ED.instances()[inst.instanceId] do
		run(DT * 3)
	end
	assert(not Ev.active()[inst.instanceId] and #eventFolder:GetChildren() == 0, "client event not cleaned up")
	-- wrong way + final lap banners
	kim:SetAttribute("CK_WrongWay", true)
	frame()
	assert(hud.Race.WrongWay.Visible, "no WRONG WAY")
	kim:SetAttribute("CK_WrongWay", false)
	remotes.RaceEvent:FireClient(kim, "lap", { lap = 3, lapTime = 86.2, best = 85.9, final = true })
	frame()
	assert(hud.Race.FinalLap.Visible and hud.Race.Popup.Visible and string.find(hud.Race.Standing.Best.Text, "1:25", 1, true), "final lap banner / best lap")
	assert(Audio.step(DT).music == "FinalLapMusic", "final lap music")
	-- engine: the slot is empty (add an id to hear it); pitch follows speed
	assert(not Audio.playing("Engine") and Audio.enginePitch(80, false) > Audio.enginePitch(20, false), "engine pitch / empty slot")
	assert(Audio.play("Lap") ~= nil, "a filled slot didn't play")
	-- mobile controls
	Input.touch.gas = true
	Input.touch.left = true
	local i2 = Input.read()
	assert(i2.gas == 1 and i2.steer == -1, "touch input")
	Input.touch.gas, Input.touch.left = false, false
	Input.refreshTouch()
	assert(playerGui.KartTouch.Controls.Visible and playerGui.KartTouch.Controls.Gas and playerGui.KartTouch.Controls.Drift and playerGui.KartTouch.Controls.Respawn, "touch controls")
	-- spectating (as seen by someone not in the race)
	local saved = CS.race
	local copy = table.clone(saved)
	copy.racers = {}
	for _, r in ipairs(saved.racers) do
		if r.kind == "bot" then
			table.insert(copy.racers, r)
		end
	end
	CS.race = copy
	assert(CS.spectating() and Spec.target(), "spectate target")
	local first = Spec.target().id
	Input.handle(roblox.Enum.KeyCode.E, true)
	assert(Spec.target().id ~= first, "E didn't cycle")
	assert(Cam.step(DT) == "spectate", "spectate camera")
	frame()
	assert(hud.Race.Spectate.Visible and string.find(hud.Race.Spectate.Who.Text, "SPECTATING", 1, true))
	CS.race = saved
	-- results screen from the real server
	RSv.endRace("test")
	frame()
	assert(Hud.resultsShown() and hud.Results.Visible, "results hidden")
	local lines = 0
	for _, d in ipairs(hud.Results.Body:GetChildren()) do
		if d.Name == "Line" then
			lines += 1
		end
	end
	assert(lines == #race.racers and hud.Results.You.Text:find("coins"), "results lines " .. lines)
	assert(Cam.step(DT) == "results")
	-- the menu: every tab renders; garage selects a kart through the server
	local UiModule = requireModule(folder.Ui)
	UiModule.closeAll()
	assert(Input.handle(roblox.Enum.KeyCode.M, true) and UiModule.isOpen("Menu"), "M didn't open the menu")
	for _, tab in ipairs(Menu.TABS) do
		Menu.open(tab)
		local n = 0
		for _, d in ipairs(Menu.content():GetDescendants()) do
			if d:IsA("TextButton") or d:IsA("TextLabel") then
				n += 1
			end
		end
		assert(n >= 3, tab .. " tab is empty")
	end
	Menu.open("Shop")
	local prices = {}
	for _, d in ipairs(Menu.content():GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "Buy" then
			table.insert(prices, d.Text)
		end
	end
	assert(#prices == #ShopConfig.Products + #ShopConfig.Passes and table.find(prices, "R$ 49"), "shop prices " .. table.concat(prices, ", "))
	Menu.open("Garage")
	local select
	for _, d in ipairs(Menu.content():GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "Select" and d.Text == "SELECT" then
			select = d
		end
	end
	select.Activated:Fire()
	flushDeferred()
	assert(DS.getProfile(kim).Vehicle == "BubblegumBumper" and CS.profile.vehicle == "BubblegumBumper", "garage select")
	Input.handle(roblox.Enum.KeyCode.M, true)
	assert(not UiModule.isOpen("Menu"))
	-- back to the lobby
	tick(GameConfig.Race.ResultsTime + 0.5)
	frame()
	assert(RSv.phase() == "Lobby" and not Kart.state() and Remote.count() == 0 and Cam.mode() == "lobby", "client didn't return to the lobby")
	assert((Loop.errors or 0) == 0, "frame errors: " .. tostring(Loop.errors))
	stubServices.RunService.IsServer = function()
		return true
	end
	serverBridge = nil
	raycastHook = nil
	heldKeys[roblox.Enum.KeyCode.W] = nil
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
