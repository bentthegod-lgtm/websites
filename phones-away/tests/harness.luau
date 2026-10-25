--[[
	Headless smoke harness for PHONES AWAY!

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation (class / property / enum names are checked against the
	reflection database). Engine services Lune does not simulate (players, data stores,
	marketplace, policy, tweens, input, physics) are stubbed, and time is driven by the
	harness through Shared.Clock so whole classes can be simulated deterministically.

	It builds the school, the teacher rigs, every phone / decor prop, initialises all
	services and simulates: seating (friends / VIP), a class with a fake player using the
	phone during the board phase vs. the walking phase, getting caught, detention + escape,
	Fake Hall Pass, pop quiz, paper airplane, notes, Teacher's Pet reports, remote
	validation, banking at the bell, receipts granted once, Pizza Party (server-wide),
	crates + PolicyService, upgrades, passes, daily / codes, live-game NotProcessedYet, the
	DataStore session lock with Studio store names, and initialises every client controller.

	It does NOT simulate physics, networking or rendering.

	Usage (from phones-away/):
	  rojo build -o build/PhonesAway.rbxlx && lune run tests/harness build/PhonesAway.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/PhonesAway.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

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
			if string.match(key, "Added$") or string.match(key, "Removing$") or string.match(key, "Finished$") or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" or key == "InputBegan" or key == "InputChanged" or key == "InputEnded" then
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

local playerList = {}
local fakePlayers = stubObject("Players", {
	LocalPlayer = nil,
	CharacterAutoLoads = true,
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
local policyRestricted = false
local dataStoreNames = {}
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
		GetDataStore = function(_, name)
			table.insert(dataStoreNames, name)
			error("DataStores are not available in the harness")
		end,
		GetOrderedDataStore = function(_, name)
			table.insert(dataStoreNames, name)
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
	PolicyService = stubObject("PolicyService", {
		GetPolicyInfoForPlayerAsync = function()
			return { ArePaidRandomItemsRestricted = policyRestricted }
		end,
	}),
	SocialService = stubObject("SocialService", {
		CanSendGameInviteAsync = function()
			return true
		end,
	}),
	TextChatService = stubObject("TextChatService"),
	UserInputService = stubObject("UserInputService", {
		TouchEnabled = true,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
	}),
	ContextActionService = stubObject("ContextActionService"),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
	Debris = stubObject("Debris"),
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
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	if self.PrimaryPart then
		self.PrimaryPart.CFrame = cf
	end
	self:SetAttribute("HarnessPivot", cf.Position)
end)
roblox.implementMethod("Model", "GetPivot", function(self)
	return if self.PrimaryPart then self.PrimaryPart.CFrame else CFrame.new()
end)
roblox.implementMethod("Seat", "Sit", function() end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.clock()
end)
local friendPairs = {}
roblox.implementMethod("Player", "IsFriendsWith", function(self, otherId)
	return friendPairs[self.UserId .. ":" .. otherId] == true or friendPairs[otherId .. ":" .. self.UserId] == true
end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("RemoteEvent", "FireServer", function() end)
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
for _, method in ipairs({ "ViewportPointToRay", "ScreenPointToRay" }) do
	roblox.implementMethod("Camera", method, function()
		return { Origin = Vector3.zero, Direction = Vector3.new(0, -1, 0) }
	end)
end

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
fakeEvent("Player", "CharacterAdded")
fakeEvent("Sound", "Ended")
fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
fakeEvent("TextButton", "Activated")
fakeEvent("TextButton", "InputBegan")
fakeEvent("TextButton", "InputEnded")
fakeEvent("TextBox", "FocusLost")
fakeEvent("Folder", "ChildAdded")
local attributeSignals = setmetatable({}, { __mode = "k" })
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
	attributeSignals[self] = attributeSignals[self] or {}
	attributeSignals[self][name] = attributeSignals[self][name] or signal()
	return attributeSignals[self][name]
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return signal()
end)

---------------------------------------------------------------------------------------------
-- Module loader
---------------------------------------------------------------------------------------------

local cache = {}
local env
local delayed = {}
local trackedTask = setmetatable({}, { __index = task })
-- Background loops are parked forever on their first wait: the harness drives time.
trackedTask.wait = function()
	coroutine.yield()
end
trackedTask.delay = function(_seconds, fn, ...)
	table.insert(delayed, { fn = fn, args = { ... } })
end
trackedTask.defer = function(fn, ...)
	return task.spawn(fn, ...)
end
local handlerErrors = 0

local function requireModule(moduleScript)
	if cache[moduleScript] ~= nil then
		return cache[moduleScript]
	end
	local chunk = luau.load(moduleScript.Source, {
		debugName = moduleScript:GetFullName(),
		environment = (function()
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

local RandomShim = {
	new = function()
		return {
			NextInteger = function(_, a, b)
				return math.random(a, b)
			end,
			NextNumber = function(_, a, b)
				return (a or 0) + math.random() * ((b or 1) - (a or 0))
			end,
		}
	end,
}

env = {
	game = game,
	workspace = workspaceService,
	require = requireModule,
	Instance = {
		new = function(className, parent)
			local instance = roblox.Instance.new(className)
			if instance:IsA("BasePart") then
				instance.Position = Vector3.zero
			end
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	},
	Enum = roblox.Enum,
	Vector3 = Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	TweenInfo = stubCtor("TweenInfo"),
	Random = RandomShim,
	task = trackedTask,
	typeof = typeof,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		print("[warn]", message)
		if string.find(message, "handler error", 1, true) or string.find(message, "Failed to start", 1, true) or string.find(message, "failed", 1, true) then
			handlerErrors += 1
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
local Shared = RS:FindFirstChild("PhonesAway")
local Services = SSS:FindFirstChild("PhonesAwayServer"):FindFirstChild("Services")

local simTime = 10000
local Clock = requireModule(Shared.Clock)
Clock.set(function()
	return simTime
end)

local GameConfig = requireModule(Shared.Config.GameConfig)
local TeacherConfig = requireModule(Shared.Config.TeacherConfig)
local PhoneConfig = requireModule(Shared.Config.PhoneConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local UpgradeConfig = requireModule(Shared.Config.UpgradeConfig)
local CosmeticConfig = requireModule(Shared.Config.CosmeticConfig)
local Decision = roblox.Enum.ProductPurchaseDecision

local function countParts(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

check("server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
	for _, m in ipairs(Shared:GetDescendants()) do
		if m:IsA("ModuleScript") then
			requireModule(m)
		end
	end
end)

local world
check("school builds: 12 desks (2 VIP), seats, detention corner, board, clock, hallway, kiosk", function()
	world = requireModule(Services.ClassroomBuilder).build()
	assert(#world.desks == 12, "desks " .. #world.desks)
	local vip = 0
	for i, desk in ipairs(world.desks) do
		assert(desk.index == i and desk.seat:IsA("Seat") and desk.cardLabel and desk.phoneUp and desk.phoneDown and desk.decor)
		if desk.vip then
			vip += 1
			assert(desk.row == 3, "VIP desk not in the back row")
		end
	end
	assert(vip == 2, "vip desks " .. vip)
	assert(#world.detentionSeats == 2 and world.detentionSeats[1]:IsA("Seat"))
	assert(#world.board.rows == 10)
	world.board.setRows({ { rank = 1, name = "Ace", text = "100 Clout" } }, nil)
	assert(string.find(world.board.rows[1].Text, "Ace", 1, true))
	assert(world.shopPrompt:IsA("ProximityPrompt"))
	assert(world.spawn:IsA("SpawnLocation"))
	assert(world.clock:FindFirstChild("HourHand") and world.clock:FindFirstChild("MinuteHand"))
	assert(world.boardText:IsA("TextLabel") and world.basket:IsA("BasePart"))
	assert(world.door and world.doorOpen and world.doorClosed)
	-- Desks don't overlap and the aisles are clear.
	for _, desk in ipairs(world.desks) do
		for _, aisle in ipairs(GameConfig.Classroom.Aisles) do
			assert(math.abs(desk.x - aisle) >= 4, "desk in an aisle")
		end
	end
	local parts = countParts(world.folder)
	assert(parts > 300 and parts < 3000, "school part count " .. parts)
	print("        school parts: " .. parts)
end)

check("teacher rigs: every style has 6 Motor6D joints, non-colliding parts, a name tag", function()
	local TeacherRig = requireModule(Shared.TeacherRig)
	for key, style in pairs(TeacherRig.Styles) do
		local model, joints = TeacherRig.build(style, CFrame.new(0, 0, -19))
		for _, name in ipairs({ "RootJoint", "Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip" }) do
			local j = joints[name]
			assert(j and j:IsA("Motor6D") and j.Part0 and j.Part1, key .. " missing " .. name)
		end
		assert(model.PrimaryPart and model.PrimaryPart.Anchored, key .. " root")
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				assert(not d.CanCollide, key .. "." .. d.Name .. " collides")
				if d ~= model.PrimaryPart then
					assert(not d.Anchored, key .. "." .. d.Name .. " anchored (would not follow the rig)")
				end
			end
		end
		assert(parts >= 30 and parts < 90, key .. " parts " .. parts)
		print(string.format("        %s rig parts: %d", key, parts))
		assert(model:FindFirstChild("Head"):FindFirstChild("NameTag"))
		TeacherRig.place(model, 3, 4, 0, 0)
		assert((model.PrimaryPart.CFrame.Position - Vector3.new(3, model:GetAttribute("LegH"), 4)).Magnitude < 1e-3)
		-- heading 0 = facing +Z (toward the class)
		assert(model.PrimaryPart.CFrame.LookVector.Z > 0.99, "heading convention broken")
		model:Destroy()
	end
end)

check("every phone tier / skin and every desk decoration builds", function()
	local Props = requireModule(Shared.Props)
	for tier = 1, #UpgradeConfig.Phone.Tiers do
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Category == "Skin" then
				local m = Props.phone(UpgradeConfig.Phone.Tiers[tier], if item.Default then nil else item, CFrame.new())
				assert(m.PrimaryPart and m:FindFirstChild("Screen"), "phone")
				Props.setPhoneGlow(m, true, 0.6)
				m:Destroy()
			end
		end
	end
	local pro = Props.phone(UpgradeConfig.ProPhone, nil, CFrame.new())
	assert(pro.PrimaryPart)
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Category == "Decor" and item.Style then
			local m = Props.decor(item.Style, CFrame.new())
			assert(countParts(m) >= 2, item.Id .. " decor is empty")
			m:Destroy()
		end
	end
	assert(Props.plane(CFrame.new()).PrimaryPart)
end)

-- Remote stubs that record traffic.
local log = {}
local function stubRemote(name)
	log[name] = {}
	return {
		FireAllClients = function(_, ...)
			table.insert(log[name], { all = true, args = { ... } })
		end,
		FireClient = function(_, player, ...)
			table.insert(log[name], { player = player, args = { ... } })
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
		local text = tostring(entry.args[1]) .. " " .. tostring(entry.args[2])
		if (not pattern or string.find(text, pattern, 1, true)) and (not player or entry.player == player or entry.all) then
			n += 1
		end
	end
	return n
end
local function lastFor(name, player)
	local list = log[name] or {}
	for i = #list, 1, -1 do
		if list[i].player == player or list[i].all then
			return list[i].args
		end
	end
	return nil
end

local registry
local ORDER = { "DataService", "ShopService", "CosmeticService", "PhoneService", "TeacherService", "ClassmateService", "RewardService", "RoundService", "LeaderboardService" }
local DS, RS_, PS, TS, CS, SS
check("services initialise and start", function()
	registry = { Remotes = remotes, World = world }
	for _, name in ipairs(ORDER) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs(ORDER) do
		registry[name].init(registry)
	end
	registry.TeacherService.setup()
	registry.LeaderboardService.setBoard(world.board)
	for _, name in ipairs({ "ShopService", "CosmeticService", "PhoneService", "ClassmateService", "RewardService", "RoundService", "LeaderboardService", "DataService" }) do
		registry[name].start()
	end
	DS, RS_, PS, TS, CS, SS = registry.DataService, registry.RoundService, registry.PhoneService, registry.TeacherService, registry.ClassmateService, registry.ShopService
	CS.instantPlanes = true
	assert(type(stubServices.MarketplaceService.ProcessReceipt) == "function", "ProcessReceipt not bound")
	assert(RS_.state() == "Hallway")
	assert(workspaceService:GetAttribute("PA_State") == "Hallway")
	assert(world.npcs:FindFirstChild("Teacher") and world.npcs:FindFirstChild("Principal"))
	-- Studio uses separate stores so test grants never reach live data.
	local sawProfiles, sawBoard = false, false
	for _, name in ipairs(dataStoreNames) do
		sawProfiles = sawProfiles or name == GameConfig.DataStoreName .. "_Studio"
		sawBoard = sawBoard or name == GameConfig.LeaderboardStoreName .. "_Studio"
	end
	assert(sawProfiles and sawBoard, "Studio store names: " .. table.concat(dataStoreNames, ", "))
end)

local nextUserId = 1000
local function makePlayer(name)
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
	root.Parent = character
	character.PrimaryPart = root
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Parent = character
	character.Parent = workspaceService
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	return player
end

local function leave(player)
	local i = table.find(playerList, player)
	if i then
		table.remove(playerList, i)
	end
	fakePlayers.PlayerRemoving:Fire(player)
	player.Parent = nil
end

-- Drives class time forward in server ticks.
local function run(seconds, everyTick)
	local dt = 1 / GameConfig.TickRate
	for _ = 1, math.floor(seconds * GameConfig.TickRate + 0.5) do
		simTime += dt
		if everyTick then
			everyTick()
		end
		RS_.step(dt)
	end
end

local function only(phase, length)
	return { phases = { { phase = phase, start = 0, duration = length or 2000 } }, event = nil, duration = length or 2000 }
end

-- Switches the running class to `phase` from now on.
local function forcePhase(phase)
	local round = RS_.round()
	local t = simTime - round.start
	round.lesson = { phases = { { phase = round.phase or "Board", start = 0, duration = t }, { phase = phase, start = t, duration = 5000 } }, duration = round.duration }
	round.phaseIndex = 0 -- the next tick enters the new phase
end

local alice, bob, carol, dave
check("players join: default profiles (memory), leaderstats, 'saving unavailable' notice", function()
	alice = makePlayer("Alice")
	bob = makePlayer("Bob")
	carol = makePlayer("Carol")
	dave = makePlayer("Dave")
	friendPairs[alice.UserId .. ":" .. bob.UserId] = true
	for _, p in ipairs({ alice, bob, carol, dave }) do
		local profile = DS.getProfile(p)
		assert(profile and profile.Clout == 0 and profile.Level == 1, "no default profile")
		assert(not DS.isPersistent(p))
		assert(p.leaderstats.Clout.Value == 0 and p.leaderstats.Rank.Value == "Freshman")
		assert(p:GetAttribute("PA_Status") == "Hallway")
	end
	assert(count("Notify", "saving is unavailable") >= 4)
end)

check("passes (Studio grants): VIP tag + VIP desk, 2x Clout multiplier", function()
	SS.buy(carol, "VIP")
	assert(SS.owns(carol, "VIP") and carol:GetAttribute("PA_VIP") == true)
	local tag = carol.Character.Head:FindFirstChild("PA_Tag")
	assert(tag and string.find(tag.Label.Text, "VIP", 1, true), "no VIP tag")
	assert(SS.cloutMultiplier(carol) == 1 + ShopConfig.VipCloutBonus)
	SS.buy(dave, "DoubleClout")
	assert(SS.cloutMultiplier(dave) == 2)
	assert(not SS.buy(dave, "DoubleClout"), "bought a pass twice")
end)

check("Teacher's Pet can only be switched on in the hallway (applies right away there)", function()
	assert(CS.setPet(bob, true))
	assert(bob:GetAttribute("PA_Pet") == true)
	assert(not CS.setPet(bob, "yes"))
end)

local class
check("bell: everyone seated at distinct desks, friends together, VIP in a VIP desk", function()
	assert(RS_.beginBell())
	assert(RS_.state() == "Bell")
	local used = {}
	for _, p in ipairs({ alice, bob, carol, dave }) do
		assert(p:GetAttribute("PA_Status") == "Seated", p.Name)
		local desk = RS_.deskOf(p)
		assert(desk and not used[desk.index], "desk clash")
		used[desk.index] = true
		assert(desk.cardLabel.Text == p.DisplayName)
		assert(PS.get(p) and PS.get(p).model, "no phone on " .. p.Name .. "'s desk")
	end
	local Seating = requireModule(Shared.Seating)
	assert(Seating.adjacent(RS_.deskOf(alice), RS_.deskOf(bob)), "friends not seated together")
	assert(RS_.deskOf(carol).vip, "VIP not at a VIP desk")
	assert(not RS_.canUsePhone(alice), "phones allowed before class starts")
	assert(world.door.CanCollide, "door open during class")
end)

local boardRate, walkRate
check("board phase: phone out while she writes = Clout, almost no suspicion", function()
	class = RS_.beginClass({ event = "None", seed = 7, lesson = only("Board"), duration = 2000 })
	assert(RS_.state() == "Class" and RS_.currentPhase() == "Board")
	TS.brain().nextGlance = math.huge -- no surprise glances for this comparison
	assert(PS.request(alice, true, simTime), "phone up refused")
	assert(not PS.isFullyUp(alice), "phone was instantly up (no raise time)")
	run(0.5)
	assert(PS.isFullyUp(alice), "phone never came up")
	local st = RS_.student(alice)
	local before = st.susp.value
	-- Scroll the feed: like posts while she writes
	for _ = 1, 20 do
		local p = PS.get(alice)
		PS.action(alice, "like", p.session.post.id, simTime)
		run(0.3)
		PS.action(alice, "scroll", nil, simTime)
		run(0.2)
	end
	run(5)
	boardRate = (st.susp.value - before) / 15
	assert(st.susp.value < TeacherConfig.Suspicion.Question, "suspicious while she faces the board: " .. st.susp.value)
	assert(not st.detention)
	assert(st.pending > 10, "earned only " .. st.pending)
	assert(count("PhoneResult", nil, alice) >= 20)
	-- Goal progress: phone time while she writes on the board.
	assert(st.boardSecs > 10, "board seconds " .. st.boardSecs)
end)

check("walking the rows: same phone use gets her CAUGHT -> confiscated -> detention", function()
	forcePhase("Walk")
	local st = RS_.student(alice)
	local pendingBefore = st.pending
	local before = st.susp.value
	local caughtAt
	local t0 = simTime
	run(45, function()
		if not caughtAt and st.detention then
			caughtAt = simTime
		end
		local p = PS.get(alice)
		if p and p.state == "up" and p.app == "Feed" then
			PS.action(alice, "like", p.session.post.id, simTime)
		end
	end)
	assert(caughtAt, "never caught during a 45 s walk (suspicion " .. st.susp.value .. ")")
	walkRate = (1 - before) / (caughtAt - t0)
	print(string.format("        suspicion/s: board %.4f vs walk %.3f, caught after %.1fs", boardRate, walkRate, caughtAt - t0))
	assert(walkRate > boardRate * 10, "walking isn't riskier than the board phase")
	assert(alice:GetAttribute("PA_Status") == "Detention" and RS_.inDetention(alice))
	assert(PS.get(alice).confiscated and not PS.isOut(alice))
	assert(PS.get(alice).confiscatedModel and (PS.get(alice).confiscatedModel.PrimaryPart.CFrame.Position - world.basket.CFrame.Position).Magnitude < 3, "phone not in the CONFISCATED basket")
	assert(st.lost > 0 and math.abs(st.lost - st.pending) <= 2, string.format("pending not halved (lost %.1f, kept %.1f)", st.lost, st.pending))
	assert(st.pending + st.lost >= pendingBefore, "pending shrank before the catch")
	assert(count("Effect", "Caught") >= 1 and count("Chat", nil) >= 1)
	assert(DS.getProfile(alice).Stats.Caught == 1)
	assert(not PS.request(alice, true, simTime), "phone came back out in detention")
	assert(RS_.deskOf(alice) == nil)
	-- Teacher pointed at her
	assert(TS.model():GetAttribute("Pose") ~= nil)
end)

check("phone down during the walk-by: never caught", function()
	local st = RS_.student(dave)
	assert(not PS.isOut(dave))
	run(20)
	assert(not st.detention and st.susp.value < 0.05, "caught with the phone away: " .. st.susp.value)
end)

check("detention: bail needs Clout, works once, phone back after a cooldown", function()
	local ok, msg = RS_.bail(alice)
	assert(not ok and string.find(msg, "Clout", 1, true), "bailed for free")
	DS.addClout(alice, 500, false)
	assert(RS_.bail(alice), "bail failed")
	assert(alice:GetAttribute("PA_Status") == "Seated" and not RS_.inDetention(alice))
	assert(not PS.get(alice).confiscated)
	assert(not PS.request(alice, true, simTime), "phone allowed during the cooldown")
	assert(RS_.student(alice).susp.value == GameConfig.DetentionReturnSuspicion)
	-- Caught again: no second escape.
	RS_.addSuspicion(alice, 1)
	assert(RS_.inDetention(alice))
	local ok2 = RS_.bail(alice)
	assert(not ok2, "escaped twice")
	assert(count("Effect", "Released") >= 1)
end)

local idsAssigned = false
local function assignIds()
	if not idsAssigned then
		idsAssigned = true
		for i, p in ipairs(ShopConfig.Products) do
			p.ProductId = 900000 + i
		end
		SS.init(registry)
	end
end
local function receipt(player, key, purchaseId)
	assignIds()
	local productId
	for _, p in ipairs(ShopConfig.Products) do
		if p.Key == key then
			productId = p.ProductId
		end
	end
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = productId, PurchaseId = purchaseId })
end

check("Get Out of Detention receipt (sent twice) is granted once and frees the student", function()
	RS_.addSuspicion(bob, 1)
	assert(RS_.inDetention(bob), "bob not caught")
	local first = receipt(bob, "DetentionPass", "det-1")
	local second = receipt(bob, "DetentionPass", "det-1")
	assert(first == Decision.PurchaseGranted and second == Decision.PurchaseGranted)
	assert(not RS_.inDetention(bob), "pass didn't free bob")
	assert(DS.getProfile(bob).Tokens.DetentionPass == 0, "pass not consumed / granted twice")
	assert(DS.getProfile(bob).Receipts["det-1"])
end)

check("Fake Hall Pass (code SKIPCLASS) forgives the first catch only", function()
	local ok = registry.RewardService.redeem(carol, "skipclass")
	assert(ok and DS.getProfile(carol).Tokens.HallPass == 1)
	RS_.addSuspicion(carol, 1)
	assert(not RS_.inDetention(carol), "hall pass didn't save carol")
	assert(DS.getProfile(carol).Tokens.HallPass == 0)
	assert(count("Effect", "Forgiven") >= 1)
	RS_.addSuspicion(carol, 1)
	assert(RS_.inDetention(carol), "second catch forgiven too")
	RS_.useDetentionPass(carol) -- no pass: stays
	assert(RS_.inDetention(carol))
end)

check("pop quiz: phone users get it wrong, honest students get Clout", function()
	forcePhase("Quiz")
	run(0.2)
	assert(RS_.isQuiz(), "quiz phase not active")
	local quiz = RS_.round().quiz
	assert(quiz and count("Quiz", nil, dave) >= 1, "quiz not sent")
	-- Dave: phone out during the quiz, still picks the right answer.
	PS.request(dave, true, simTime)
	run(0.5)
	assert(RS_.answerQuiz(dave, quiz.q.Correct))
	assert(not RS_.answerQuiz(dave, quiz.q.Correct), "answered twice")
	assert(not RS_.answerQuiz(bob, 0 / 0) and not RS_.answerQuiz(bob, 7) and not RS_.answerQuiz(bob, "1"))
	assert(RS_.answerQuiz(bob, quiz.q.Correct))
	assert(not RS_.answerQuiz(carol, quiz.q.Correct), "answered from detention")
	local bobBefore, daveBefore = RS_.student(bob).pending, RS_.student(dave).susp.value
	forcePhase("Board")
	TS.brain().nextGlance = math.huge
	PS.request(dave, false, simTime)
	run(0.2)
	assert(RS_.round().quiz == nil, "quiz not graded")
	assert(RS_.student(bob).pending > bobBefore + GameConfig.Quiz.Reward - 1, "correct answer not rewarded")
	assert(RS_.student(dave).quiz == "phone" and RS_.student(dave).susp.value > daveBefore - 0.01)
	local res = lastFor("QuizResult", dave)
	assert(res and res[1].distracted and not res[1].correct)
end)

check("paper airplane: she turns toward the noise; cooldown, limits and bad args", function()
	forcePhase("Lecture")
	run(3) -- she's done pointing at the last catch
	local target = world.desks[1]
	assert(not CS.throwPlane(bob, 0 / 0) and not CS.throwPlane(bob, 99) and not CS.throwPlane(bob, "3") and not CS.throwPlane(bob, 1.5))
	local ok = CS.throwPlane(bob, 1, simTime)
	assert(ok, "throw failed")
	assert(TS.brain():isDistracted(simTime))
	run(1.5)
	local Detection = requireModule(Shared.Detection)
	local b = TS.brain()
	local want = Detection.headingTo(b.x, b.z, target.x, target.z - 1.5)
	assert(math.abs(Detection.wrap(b.heading - want)) < math.rad(10), "she didn't turn toward the airplane")
	assert(b.pose == "Distracted")
	assert(not CS.throwPlane(bob, 2, simTime), "cooldown ignored")
	assert(not CS.throwPlane(carol, 2, simTime), "thrown from detention")
	assert(count("Effect", "Plane") >= 1)
end)

check("pass a note: only to the desk next to you", function()
	local ok = CS.passNote(alice, bob.UserId, simTime) -- alice is in detention
	assert(not ok)
	local okBob = CS.passNote(bob, carol.UserId, simTime)
	assert(not okBob, "note to a student in detention")
	local Seating = requireModule(Shared.Seating)
	local daveDesk, bobDesk = RS_.deskOf(dave), RS_.deskOf(bob)
	local ok2 = CS.passNote(dave, bob.UserId, simTime)
	assert(ok2 == Seating.adjacent(daveDesk, bobDesk), "adjacency check wrong")
	assert(not CS.passNote(dave, dave.UserId, simTime))
	assert(not CS.passNote(dave, 0 / 0, simTime))
end)

check("Teacher's Pet: a true report raises suspicion, a false one backfires, limited", function()
	forcePhase("Board")
	TS.brain().nextGlance = math.huge
	run(1)
	PS.request(dave, true, simTime)
	run(0.5)
	local before = RS_.student(dave).susp.value
	local ok, result = CS.report(bob, dave.UserId, simTime)
	assert(ok and result == "hit", tostring(result))
	assert(RS_.student(dave).susp.value >= before + GameConfig.Pet.SuspicionAdded - 1e-6)
	assert(not CS.report(bob, dave.UserId, simTime + 1), "cooldown ignored")
	PS.request(dave, false, simTime)
	run(1)
	simTime += GameConfig.Pet.Cooldown
	local bobBefore = RS_.student(bob).susp.value
	local ok2, result2 = CS.report(bob, dave.UserId, simTime)
	assert(ok2 and result2 == "false" and RS_.student(bob).susp.value > bobBefore, "false report not punished")
	simTime += GameConfig.Pet.Cooldown
	CS.report(bob, dave.UserId, simTime)
	simTime += GameConfig.Pet.Cooldown
	assert(not CS.report(bob, dave.UserId, simTime), "more than 3 reports")
	assert(not CS.report(dave, bob.UserId, simTime), "non-pet reported")
	run(0.1)
end)

check("remote validation: phone + minigame inputs are type-checked, rate limited and capped", function()
	local onPhone = remotes.Phone.OnServerEvent
	local onAction = remotes.PhoneAction.OnServerEvent
	local onApp = remotes.PhoneApp.OnServerEvent
	onPhone:Fire(dave, "yes")
	onPhone:Fire(dave, 1)
	assert(not PS.isOut(dave), "non-boolean accepted")
	onApp:Fire(dave, "Hack")
	assert(PS.get(dave).app == "Feed")
	onApp:Fire(dave, "Text")
	assert(PS.get(dave).app == "Text")
	onPhone:Fire(dave, true)
	run(0.5)
	assert(PS.isFullyUp(dave))
	onAction:Fire(dave, "text", string.rep("a", 500))
	onAction:Fire(dave, "text", { "table" })
	onAction:Fire(dave, "like", 0 / 0)
	onAction:Fire(dave, "nuke", 1)
	-- Correct text answer (after a human delay) pays; wrong app actions don't.
	simTime += 1
	local word = PS.get(dave).session.text.word
	local ok, amount = PS.action(dave, "text", word, simTime)
	assert(ok and amount > 0, "valid text reply rejected")
	assert(not PS.action(dave, "like", PS.get(dave).session.post.id, simTime), "feed action while in the text app")
	-- Burst: at most ActionsPerSecond accepted in the same instant.
	PS.setApp(dave, "Game")
	local accepted = 0
	for _ = 1, 50 do
		local okTap, _, info = PS.action(dave, "tap", simTime, simTime)
		if okTap or info ~= "rate" then
			accepted += 1
		end
	end
	assert(accepted <= PhoneConfig.ActionsPerSecond, "rate limit: " .. accepted)
	-- Class cap
	local p = PS.get(dave)
	p.session.total = PhoneConfig.Caps.Total
	PS.setApp(dave, "Selfie")
	simTime += 20
	local okSelfie, amountSelfie = PS.action(dave, "selfie", nil, simTime)
	assert(okSelfie and amountSelfie == 0, "Clout past the class cap")
	PS.request(dave, false, simTime)
	run(1)
end)

check("selfie flash she can see = instant big suspicion", function()
	forcePhase("Lecture")
	run(0.5)
	local p = PS.get(dave)
	p.session.total = 0
	p.session.used.Selfie = 0
	PS.setApp(dave, "Selfie")
	PS.request(dave, true, simTime)
	run(0.4)
	local st = RS_.student(dave)
	st.susp.value = 0
	-- Point her straight at Dave.
	local b = TS.brain()
	local Detection = requireModule(Shared.Detection)
	b.heading = Detection.headingTo(b.x, b.z, st.desk.x, st.desk.z)
	b.distractUntil = nil
	simTime += 20
	PS.action(dave, "selfie", nil, simTime)
	run(0.1)
	assert(st.susp.value >= TeacherConfig.Sight.FlashInstant or st.detention, "flash not noticed: " .. st.susp.value)
	PS.request(dave, false, simTime)
	run(2)
end)

local banked
check("bell: pending Clout is banked, results sent, back to the hallway", function()
	local stA, stD = RS_.student(alice), RS_.student(dave)
	local expectAlice = math.floor(stA.pending)
	local before = DS.getProfile(alice).Clout
	local totalBefore = DS.getProfile(dave).TotalClout
	local davePending = math.floor(stD.pending)
	RS_.endClass(simTime)
	assert(RS_.state() == "Results")
	assert(DS.getProfile(alice).Clout >= before + expectAlice, "not banked")
	assert(DS.getProfile(dave).TotalClout >= totalBefore + davePending)
	local res = lastFor("Results", alice)
	assert(res and res[1].caught == true)
	assert(DS.getProfile(dave).Stats.Classes == 1)
	assert(DS.getProfile(bob).Stats.CleanClasses == 0, "bob was caught")
	assert(DS.getProfile(dave).Stats.CleanClasses == (if stD.caught then 0 else 1))
	banked = true
	simTime += GameConfig.ResultsSeconds + 1
	RS_.step(0.1)
	assert(RS_.state() == "Hallway")
	for _, p in ipairs({ alice, bob, carol, dave }) do
		assert(p:GetAttribute("PA_Status") == "Hallway" and RS_.deskOf(p) == nil and PS.get(p) == nil)
	end
	assert(world.desks[1].cardLabel.Text == "")
	assert(not world.door.CanCollide)
	assert(#world.props:GetChildren() == 0, "props left behind")
end)

check("developer product receipt processed twice is granted once", function()
	local profile = DS.getProfile(alice)
	local before = profile.Clout
	assert(receipt(alice, "Clout500", "r-1") == Decision.PurchaseGranted)
	assert(receipt(alice, "Clout500", "r-1") == Decision.PurchaseGranted)
	assert(profile.Clout == before + 500, "granted " .. (profile.Clout - before))
	assert(profile.TotalClout < before + 500 or profile.TotalClout >= 0, "sanity")
	local unknown = stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 1, ProductId = 123, PurchaseId = "x" })
	assert(unknown == Decision.NotProcessedYet)
end)

check("Pizza Party: queued from the hallway, announced with the buyer, lenient 2x class for EVERYONE", function()
	local announces = count("Announce", "Bob")
	assert(receipt(bob, "PizzaParty", "pizza-1") == Decision.PurchaseGranted)
	assert(receipt(bob, "PizzaParty", "pizza-1") == Decision.PurchaseGranted)
	assert(workspaceService:GetAttribute("PA_PizzaQueued") == 1, "pizza granted twice or not queued")
	assert(count("Announce", "Bob") == announces + 1, "buyer not announced")
	assert(count("Effect", "Pizza") >= 1)
	assert(RS_.beginBell())
	simTime += GameConfig.BellSeconds
	RS_.beginClass({ event = "None", seed = 3, lesson = only("Lecture") })
	local round = RS_.round()
	assert(round.pizza and round.pizzaBy == "Bob")
	assert(workspaceService:GetAttribute("PA_PizzaQueued") == 0)
	assert(RS_.cloutMultiplier() == GameConfig.PizzaCloutMultiplier)
	assert(math.abs(TS.brain().detection - GameConfig.PizzaDetectionMultiplier) < 1e-9, "teacher not lenient")
	-- Everyone (not just the buyer) earns double.
	PS.request(carol, true, simTime)
	run(0.5)
	local p = PS.get(carol)
	local _, amount = PS.action(carol, "like", p.session.post.id, simTime)
	local base = PhoneConfig.Feed.LikeClout * (if p.session.post.viral then PhoneConfig.Feed.ViralMultiplier else 1)
	assert(math.abs(amount - base * 2 * SS.cloutMultiplier(carol)) < 1e-6, "pizza 2x not applied: " .. tostring(amount))
	PS.request(carol, false, simTime)
	-- Bought during class: starts right away; queue is capped.
	RS_.round().pizza = false
	assert(RS_.startPizza(alice) == true and RS_.round().pizza)
	for _ = 1, 5 do
		RS_.startPizza(alice)
	end
	assert(workspaceService:GetAttribute("PA_PizzaQueued") == GameConfig.PizzaMaxQueued)
	workspaceService:SetAttribute("PA_PizzaQueued", 0)
end)

check("principal event: second observer + double detection while in the room", function()
	local round = RS_.round()
	round.pizza = false
	round.event = "Principal"
	round.lesson = { phases = { { phase = "Lecture", start = 0, duration = 5000 } }, event = { name = "Principal", start = simTime - round.start, duration = 10 }, duration = round.duration }
	run(0.3)
	assert(round.principalIn and TS.principalPresent())
	assert(#TS.observers() == 2)
	assert(math.abs(TS.brain().detection - TeacherConfig.Events.Principal.Detection) < 1e-9)
	run(11)
	assert(not round.principalIn and #TS.observers() == 1)
	assert(TS.brain().detection == 1)
end)

check("leaving mid-class banks pending Clout and frees the desk", function()
	local st = RS_.student(dave)
	st.pending += 40
	local before = DS.getProfile(dave).Clout
	local profileRef = DS.getProfile(dave)
	leave(dave)
	assert(profileRef.Clout >= before + 40, "pending lost on leave")
	assert(RS_.student(dave) == nil and DS.getProfile(dave) == nil)
	RS_.endClass(simTime)
	simTime += GameConfig.ResultsSeconds + 1
	RS_.step(0.1)
	assert(RS_.state() == "Hallway")
end)

check("Clout upgrades and cosmetics: buy, equip, maxed, not enough Clout", function()
	local CSv = registry.CosmeticService
	local profile = DS.getProfile(alice)
	profile.Clout = 300
	assert(CSv.buyUpgrade(alice, "Phone"))
	assert(profile.Upgrades.Phone == 2 and profile.Clout == 50)
	assert(not CSv.buyUpgrade(alice, "Phone"), "bought without enough Clout")
	assert(not CSv.buyUpgrade(alice, "Rocket"))
	assert(not CSv.buyUpgrade(alice, 5))
	profile.Clout = 1e7
	for _ = 1, 10 do
		CSv.buyUpgrade(alice, "Phone")
	end
	assert(profile.Upgrades.Phone == #UpgradeConfig.Phone.Tiers)
	local okMax, msg = CSv.buyUpgrade(alice, "Phone")
	assert(not okMax and string.find(msg, "max", 1, true))
	assert(CSv.buyCosmetic(alice, "Skin", "Bubblegum") and profile.Equipped.Skin == "Bubblegum")
	assert(not CSv.buyCosmetic(alice, "Skin", "Gold"), "crate-only item sold")
	assert(CSv.equip(alice, "Skin", "Default"))
	assert(not CSv.equip(alice, "Skin", "Hologram"), "equipped an unowned item")
	assert(not CSv.equip(alice, "Nope", "Default"))
end)

check("crates: Locker Crate for Clout; Robux Skin Crate hidden when PolicyService restricts it", function()
	local CSv = registry.CosmeticService
	local profile = DS.getProfile(alice)
	profile.Clout = 5000
	local ok, result = CSv.openCrate(alice, "Locker")
	assert(ok and result and result.rarity, "locker crate failed")
	assert(profile.Clout <= 5000 - CosmeticConfig.Crates.Locker.CloutPrice + (result.refund or 0))
	assert(count("CrateResult", nil, alice) >= 1)
	-- Restricted region
	policyRestricted = true
	SS._loadPolicy(alice)
	assert(not SS.randomItemsAllowed(alice))
	assert(not SS.buy(alice, "SkinCrate"), "paid random item offered in a restricted region")
	assert(DS.snapshot(alice).randomItemsAllowed == false)
	policyRestricted = false
	SS._loadPolicy(alice)
	assert(SS.randomItemsAllowed(alice))
	-- Robux crate receipt twice: one skin
	local owned = 0
	for _ in pairs(profile.Owned.Skin) do
		owned += 1
	end
	local clout = profile.Clout
	assert(receipt(alice, "SkinCrate", "crate-1") == Decision.PurchaseGranted)
	assert(receipt(alice, "SkinCrate", "crate-1") == Decision.PurchaseGranted)
	local owned2 = 0
	for _ in pairs(profile.Owned.Skin) do
		owned2 += 1
	end
	assert(owned2 == owned + 1 or profile.Clout > clout, "crate granted nothing")
	assert(owned2 <= owned + 1, "crate granted twice")
end)

check("daily streak, codes RELEASE / NOPHONES, invite bonus once", function()
	local RSv = registry.RewardService
	local profile = DS.getProfile(bob)
	local before = profile.Clout
	assert(RSv.claimDaily(bob))
	assert(not RSv.claimDaily(bob), "claimed twice")
	assert(profile.Clout > before)
	assert(RSv.redeem(bob, "RELEASE"))
	assert(RSv.redeem(bob, "nophones"))
	assert(not RSv.redeem(bob, "RELEASE"))
	assert(RSv.invited(bob) and not RSv.invited(bob))
	assert(#RSv.goalsView(bob) == 3)
end)

check("leaderboard shows this server's players when the global store is offline", function()
	registry.LeaderboardService.refresh()
	assert(string.find(world.board.rows[1].Text, "Clout", 1, true), world.board.rows[1].Text)
end)

check("live game: a receipt for a profile that can't be saved is NotProcessedYet", function()
	local profile = DS.getProfile(alice)
	local before = profile.Clout
	isStudio = false
	local decision = receipt(alice, "Clout500", "live-1")
	isStudio = true
	assert(decision == Decision.NotProcessedYet, "granted without persistence")
	assert(profile.Clout == before and profile.Receipts["live-1"] == nil)
	-- Live game: unset ids say "not available" instead of granting for free.
	isStudio = false
	local ok = SS.buy(alice, "VIP")
	isStudio = true
	assert(not ok and not SS.owns(alice, "VIP"))
end)

check("session lock + store names: Studio '_Studio' store, live store, lock, takeover, unlock", function()
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
	local usedName
	local fakeStore = {
		UpdateAsync = function(_, k, fn)
			local new = fn(copy(stored[k]))
			if new ~= nil then
				stored[k] = copy(new)
			end
			return copy(new)
		end,
	}
	stubServices.DataStoreService.GetDataStore = function(_, name)
		usedName = name
		return fakeStore
	end
	isStudio = false
	DS.init(registry)
	assert(usedName == GameConfig.DataStoreName, "live store name " .. tostring(usedName))
	isStudio = true
	DS.init(registry)
	assert(usedName == GameConfig.DataStoreName .. "_Studio", "studio store name " .. tostring(usedName))
	local ok, err = pcall(function()
		stored["player_" .. (nextUserId + 1)] = { Clout = 777 }
		local erin = makePlayer("Erin")
		local key = "player_" .. erin.UserId
		assert(DS.isPersistent(erin) and DS.getProfile(erin).Clout == 777, "saved profile not loaded")
		assert(type(stored[key].Lock) == "table", "profile not locked on load")
		DS.getProfile(erin).Clout = 800
		assert(DS.save(erin) and stored[key].Clout == 800 and stored[key].Lock, "autosave failed")
		-- Receipts on a persistent profile are saved before PurchaseGranted.
		assert(receipt(erin, "Clout500", "lock-r1") == Decision.PurchaseGranted)
		assert(stored[key].Receipts["lock-r1"] and stored[key].Clout == 1300, "receipt not saved first")
		stored[key].Lock = { Session = "other-server", At = os.time() }
		DS.getProfile(erin).Clout = 1
		assert(not DS.save(erin), "saved over another server's lock")
		assert(stored[key].Clout == 1300 and not DS.isPersistent(erin))
		isStudio = false
		local decision = receipt(erin, "Clout500", "lock-r2")
		isStudio = true
		assert(decision == Decision.NotProcessedYet, "granted after losing the lock")
		leave(erin)
		assert(stored[key].Clout == 1300, "left player overwrote the new owner")
		stored["player_" .. (nextUserId + 1)] = { Clout = 55, Lock = { Session = "crashed", At = os.time() - 100000 } }
		local finn = makePlayer("Finn")
		local finnKey = "player_" .. finn.UserId
		assert(DS.isPersistent(finn) and DS.getProfile(finn).Clout == 55, "stale lock blocked the load")
		DS.getProfile(finn).Clout = 99
		leave(finn)
		assert(stored[finnKey].Clout == 99 and stored[finnKey].Lock == nil, "leave save did not persist and unlock")
	end)
	isStudio = true
	stubServices.DataStoreService.GetDataStore = function()
		error("DataStores are not available in the harness")
	end
	DS.init(registry)
	assert(ok, err)
end)

check("a full class runs start to finish on the real schedule (every phase + event types)", function()
	local seen = {}
	for _, event in ipairs({ "None", "Substitute", "Principal", "FireDrill", "LunchBell" }) do
		assert(RS_.beginBell(), "bell")
		simTime += GameConfig.BellSeconds
		RS_.step(0.1)
		assert(RS_.state() == "Class")
		-- Replace the rolled class with a known event (same code path as beginClass).
		RS_.endClass(simTime)
		simTime += GameConfig.ResultsSeconds + 1
		RS_.step(0.1)
		RS_.beginBell()
		simTime += GameConfig.BellSeconds
		RS_.beginClass({ event = event, seed = 11 })
		PS.request(bob, true, simTime)
		run(GameConfig.ClassSeconds + 1, function()
			local phase = RS_.currentPhase()
			if phase then
				seen[phase] = true
			end
			local p = PS.get(bob)
			if p and p.state == "up" and p.app == "Feed" then
				PS.action(bob, "like", p.session.post.id, simTime)
			end
		end)
		assert(RS_.state() == "Results", event .. ": class did not end (" .. RS_.state() .. ")")
		simTime += GameConfig.ResultsSeconds + 1
		RS_.step(0.1)
		assert(RS_.state() == "Hallway")
		simTime += GameConfig.HallwaySeconds + 1
	end
	for _, phase in ipairs({ "Board", "Lecture", "Walk", "Quiz", "FireDrill", "LunchCheck" }) do
		assert(seen[phase], "never saw phase " .. phase)
	end
	assert(DS.getProfile(bob).Stats.Classes >= 5)
	assert(world.boardText.Text ~= "", "nothing written on the board")
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise and render a real profile snapshot", function()
	local snapshot = DS.sendProfileNow(alice)
	assert(snapshot and snapshot.phone and snapshot.goals and snapshot.daily, "snapshot incomplete")
	requireModule(Shared.Net).setup()
	local localPlayer = roblox.Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.DisplayName = "Tester"
	localPlayer.UserId = 1
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = localPlayer
	localPlayer:SetAttribute("PA_Status", "Seated")
	localPlayer:SetAttribute("PA_Desk", 6)
	fakePlayers.LocalPlayer = localPlayer
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera
	-- Seated classmates for the seating chart.
	alice:SetAttribute("PA_Status", "Seated")
	alice:SetAttribute("PA_Desk", 5)
	bob:SetAttribute("PA_Status", "Seated")
	bob:SetAttribute("PA_Desk", 7)

	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("PhonesAwayClient"):FindFirstChild("Controllers")
	local controllers = {}
	for _, name in ipairs({ "ClientState", "HudController", "PhoneController", "TeacherController", "MenuController", "EffectsController" }) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local CSt = controllers.ClientState
	CSt.profile = snapshot
	CSt.ProfileChanged:Fire(snapshot)
	CSt.roundState = "Class"
	CSt.RoundChanged:Fire("Class", {})
	CSt.phase = { phase = "Walk", label = "WALKING THE ROWS", risk = "VERY RISKY", color = { 255, 80, 80 }, endsAt = Clock.now() + 10 }
	CSt.PhaseChanged:Fire(CSt.phase)
	CSt.SuspicionChanged:Fire(0.5, "?", 42)
	CSt.SuspicionChanged:Fire(0.8, "!", 42)
	-- Phone: every app renders with a real server view.
	local Minigames = requireModule(Shared.Minigames)
	local Rng = requireModule(Shared.Rng)
	local session = Minigames.newSession(PhoneConfig, Rng.new(5), Clock.now())
	CSt.phone = { state = "down", app = "Feed", confiscated = false, cooldownUntil = 0, hide = 0.4, view = Minigames.view(session), caps = { used = 0, total = 900 } }
	CSt.PhoneChanged:Fire(CSt.phone)
	local Phone = controllers.PhoneController
	Phone.press()
	assert(Phone.isUp(), "phone did not come up")
	for _, app in ipairs(PhoneConfig.AppOrder) do
		Phone.setApp(app)
		Phone._primary()
	end
	CSt.PhoneResult:Fire("tap", { ok = true, amount = 4, info = "Perfect", view = Minigames.view(session) })
	CSt.PhoneResult:Fire("text", { ok = false, amount = 0, info = "wrong", view = Minigames.view(session), capped = true })
	Phone.release()
	assert(not Phone.isUp())
	-- HUD
	local Hud = controllers.HudController
	CSt.QuizChanged:Fire({ question = "7 x 8 = ?", options = { "54", "56", "64" }, seconds = 9, endsAt = Clock.now() + 9 })
	CSt.QuizResult:Fire({ correct = false, distracted = true, answer = "56", reward = 0 })
	CSt.QuizChanged:Fire(nil)
	CSt.Chat:Fire("front_row_fiona", "rip Alice's phone (2024-2024)", { 255, 120, 120 })
	for i = 1, 8 do
		CSt.Chat:Fire("kev_the_legend", "msg " .. i)
	end
	CSt.Notified:Fire("Hello class", "good")
	CSt.Announced:Fire("Bob bought a PIZZA PARTY!", { 255, 150, 60 })
	CSt.Results:Fire({ clout = 123, lost = 20, caught = true, quiz = "phone", walkSecs = 12, pizza = true, legend = "Bob", top = { { name = "Bob", clout = 300, caught = false }, { name = "Alice", clout = 123, caught = true } } })
	for _, mode in ipairs({ "plane", "note", "report" }) do
		Hud._openChart(mode)
	end
	Hud._closeChart()
	localPlayer:SetAttribute("PA_Status", "Detention")
	Hud.renderProfile(snapshot)
	for _ = 1, 3 do
		stubServices.RunService.RenderStepped:Fire(1 / 60)
	end
	-- Menus: every panel and every tab
	local Menu = controllers.MenuController
	localPlayer:SetAttribute("PA_Status", "Hallway")
	for _, key in ipairs({ "Shop", "Upgrades", "Locker", "Crates", "Daily", "Codes", "Pet" }) do
		Menu.open(key)
		assert(Menu.isOpen(key))
	end
	Menu.close()
	snapshot.randomItemsAllowed = false
	CSt.ProfileChanged:Fire(snapshot)
	Menu.open("Crates")
	Menu.open("Shop")
	Menu._playReveal({ rarity = "Legendary", name = "Solid Gold (fake)", duplicate = false, refund = 0 })
	Menu.close()
	-- Effects
	local Fx = controllers.EffectsController
	for _, e in ipairs({
		{ "Clout", { amount = 500, big = true } },
		{ "Purchase", {} },
		{ "Upgrade", { name = "Flip Classic" } },
		{ "LevelUp", { level = 5, rank = "Sophomore", color = { 90, 180, 255 } } },
		{ "Goal", { text = "Ace a Pop Quiz", clout = 40 } },
		{ "Daily", { streak = 2, clout = 80 } },
		{ "SelfFlash", {} },
		{ "Flash", { userId = 99 } },
		{ "Caught", { userId = 1, name = "Tester", lost = 20 } },
		{ "Caught", { userId = 99, name = "Bob", lost = 0 } },
		{ "Forgiven", { userId = 1 } },
		{ "Released", { userId = 1 } },
		{ "Pizza", { by = "Bob", now = true } },
		{ "FireDrill", { seconds = 16 } },
		{ "FireDrillEnd", {} },
		{ "Bell", { early = true } },
		{ "Plane", { from = 5, to = 1 } },
		{ "PlaneLand", { desk = 1 } },
		{ "Note", {} },
		{ "Principal", { on = true } },
		{ "Door", {} },
		{ "OpenShop", {} },
	}) do
		Fx.handle(e[1], e[2])
	end
	-- Teacher animation: every pose on the real rigs.
	local Teacher = controllers.TeacherController
	local npcs = workspaceService:FindFirstChild("School"):FindFirstChild("NPCs")
	local model = npcs:FindFirstChild("Teacher")
	for pose in pairs(Teacher._poses) do
		model:SetAttribute("Pose", pose)
		Teacher.step(1 / 60)
	end
	local rigCount = 0
	for _ in pairs(Teacher._rigs) do
		rigCount += 1
	end
	assert(rigCount == 2, "rigs tracked: " .. rigCount)
	assert(workspaceService:FindFirstChild("PA_VisionCones") and #workspaceService.PA_VisionCones:GetChildren() == 4, "vision cones missing")
	for _, name in ipairs({ "PA_HUD", "PA_Phone", "PA_Menu", "PA_FX" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
	end
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were swallowed by signal handlers / controller init", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
process.exit(0)
