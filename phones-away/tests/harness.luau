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
			if string.match(key, "Added$") or string.match(key, "Removing$") or string.match(key, "Finished$") or string.match(key, "Released$") or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" or key == "InputBegan" or key == "InputChanged" or key == "InputEnded" then
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
-- Seats: Seat:Sit welds the character to the (anchored) seat like Roblox does, and a pivot
-- of a character that is still welded drags the seat along (one rigid assembly).
local seatOf = {} -- [humanoid] = { seat, weld }
local NO_SEAT = roblox.Instance.new("Part")
roblox.implementMethod("Seat", "Sit", function(seat, humanoid)
	local character = humanoid.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, entry in pairs(seatOf) do
		-- Occupied (a destroyed character frees its seat, like a respawn does in Roblox).
		if entry.seat == seat and entry.weld.Parent and entry.weld.Part1 and entry.weld.Part1:IsDescendantOf(workspaceService) then
			return
		end
	end
	local weld = roblox.Instance.new("Weld")
	weld.Name = "SeatWeld"
	weld.Part0 = seat
	weld.Part1 = root
	weld.Parent = seat
	seatOf[humanoid] = { seat = seat, weld = weld }
	humanoid.SeatPart = seat -- (Lune can't clear it when the weld goes: tests use seatedIn)
end)
-- The seat a humanoid is really welded to right now (nil once its SeatWeld is gone).
local function seatedIn(humanoid)
	local entry = seatOf[humanoid]
	return if entry and entry.weld.Parent then entry.seat else nil
end
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	if self.PrimaryPart then
		local humanoid = self:FindFirstChildOfClass("Humanoid")
		local entry = humanoid and seatOf[humanoid]
		if entry and entry.weld.Parent then
			entry.seat.CFrame = cf * (self.PrimaryPart.CFrame:Inverse() * entry.seat.CFrame)
		elseif entry then
			humanoid.SeatPart = NO_SEAT -- the weld is gone: no longer seated (Lune can't set nil)
		end
		self.PrimaryPart.CFrame = cf
	end
	self:SetAttribute("HarnessPivot", cf.Position)
end)
roblox.implementMethod("Model", "GetPivot", function(self)
	return if self.PrimaryPart then self.PrimaryPart.CFrame else CFrame.new()
end)
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
	assert(#world.detentionSeats == 6 and world.detentionSeats[1]:IsA("Seat"))
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
	assert(Props.testPaper(CFrame.new(), "B").PrimaryPart and countParts(Props.rippedPaper(CFrame.new())) >= 4, "test paper props")
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
local ORDER = { "DataService", "ShopService", "CosmeticService", "PhoneService", "TestService", "TeacherService", "ClassmateService", "RewardService", "RoundService", "LeaderboardService" }
local DS, RS_, PS, TS, CS, SS, TestS
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
	for _, name in ipairs({ "ShopService", "CosmeticService", "PhoneService", "TestService", "ClassmateService", "RewardService", "RoundService", "LeaderboardService", "DataService" }) do
		registry[name].start()
	end
	DS, RS_, PS, TS, CS, SS, TestS = registry.DataService, registry.RoundService, registry.PhoneService, registry.TeacherService, registry.ClassmateService, registry.ShopService, registry.TestService
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
	if player.Character then
		player.Character:Destroy() -- Roblox removes a leaving player's character
	end
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

local alice, bob, carol, dave, eve
check("players join: default profiles (memory), leaderstats, 'saving unavailable' notice", function()
	alice = makePlayer("Alice")
	bob = makePlayer("Bob")
	carol = makePlayer("Carol")
	dave = makePlayer("Dave")
	eve = makePlayer("Eve")
	friendPairs[alice.UserId .. ":" .. bob.UserId] = true
	for _, p in ipairs({ alice, bob, carol, dave, eve }) do
		local profile = DS.getProfile(p)
		assert(profile and profile.Clout == 0 and profile.Level == 1, "no default profile")
		assert(not DS.isPersistent(p))
		assert(p.leaderstats.Clout.Value == 0 and p.leaderstats.Rank.Value == "Freshman")
		assert(p:GetAttribute("PA_Status") == "Hallway")
	end
	assert(count("Notify", "saving is unavailable") >= 5)
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
local Bank = requireModule(SSS:FindFirstChild("PhonesAwayServer"):FindFirstChild("Data"):FindFirstChild("QuestionBank"))
local TestPaper = requireModule(Shared.TestPaper)
local LEAK_KEYS = { correct = true, answer = true, answers = true, perms = true, order = true, revealed = true }

-- Recursively makes sure a payload has no answer key in it.
local function assertNoAnswerKey(value, path, allowAnswers)
	if type(value) ~= "table" then
		return
	end
	for k, v in pairs(value) do
		local key = string.lower(tostring(k))
		if LEAK_KEYS[key] and not (allowAnswers and key == "answers") then
			error("answer key leaked at " .. path .. "." .. tostring(k))
		end
		assertNoAnswerKey(v, path .. "." .. tostring(k), allowAnswers)
	end
end

local function holdPhoneUp(player)
	PS.request(player, true, simTime)
	run(0.4)
	assert(PS.isFullyUp(player), player.Name .. "'s phone never came up")
end

check("test: every student gets a version (friends share one), payload has NO answers", function()
	class = RS_.beginClass({ event = "None", seed = 7, lesson = only("Board"), duration = 2000 })
	assert(RS_.state() == "Class" and RS_.currentPhase() == "Board")
	assert(TestS.active())
	for _, p in ipairs({ alice, bob, carol, dave, eve }) do
		local view = TestS.viewFor(p)
		assert(view and #view.questions == 10 and (view.version == "A" or view.version == "B"), p.Name .. " has no test")
		assert(p:GetAttribute("PA_Version") == view.version)
	end
	assert(TestS.paper(alice).version == TestS.paper(bob).version, "friends got different versions")
	-- Every "view" ever sent to a client: questions + options only.
	local sent = 0
	for _, entry in ipairs(log.Test or {}) do
		if entry.args[1] == "view" then
			sent += 1
			local data = entry.args[2]
			for _, q in ipairs(data.questions) do
				assert(#q.options == 4 and type(q.text) == "string")
				for k in pairs(q) do
					assert(k == "slot" or k == "subject" or k == "tier" or k == "text" or k == "options", "unexpected field " .. tostring(k))
				end
			end
			-- `answers` here are the student's OWN picks (empty at the start), never the key.
			assert(next(data.answers) == nil, "answers pre-filled")
			assertNoAnswerKey(data.questions, "view.questions")
		end
	end
	assert(sent >= 5, "views sent: " .. sent)
	-- The bank lives in ServerScriptService only.
	assert(not RS:FindFirstChild("QuestionBank", true), "question bank replicated to clients")
	-- A desk paper with the version letter.
	assert(world.props:FindFirstChild("Paper_" .. dave.UserId), "no test paper on the desk")
	-- Nothing revealed yet: no PhoneResult "reveal" has been sent.
	assert(count("PhoneResult", "reveal") == 0)
	assert(#TestS.revealedList(dave) == 0)
end)

check("board phase: snap -> scan -> 2 answers revealed -> answered correctly (almost no suspicion)", function()
	TS.brain().nextGlance = math.huge -- no surprise glances for this comparison
	assert(PS.request(dave, true, simTime), "phone up refused")
	assert(not PS.isFullyUp(dave), "phone was instantly up (no raise time)")
	assert(not PS.action(dave, "snap", simTime), "snapped before the phone was fully out")
	run(0.4)
	assert(PS.isFullyUp(dave))
	local st = RS_.student(dave)
	local before = st.susp.value
	assert(PS.action(dave, "snap", simTime), "snap refused")
	assert(not PS.action(dave, "snap", simTime), "second snap while scanning")
	-- Aim -> shutter -> scan: the server runs the clock; nothing is revealed until it's done.
	local stats = PS.get(dave).stats
	assert(stats.answers == 2, "default phone should reveal 2")
	run(PhoneConfig.Snap.AimSeconds + 0.15)
	assert(PS.get(dave).scan and PS.get(dave).scan.stage == "process", "no shutter")
	assert(count("PhoneResult", "shutter", dave) >= 1 and count("Effect", "Flash") >= 1)
	run(stats.scan - 0.5)
	assert(count("PhoneResult", "reveal", dave) == 0, "answers before the scan finished")
	run(0.8)
	local res = lastFor("PhoneResult", dave)
	assert(res and res[1] == "reveal", "no reveal")
	local revealed = res[2].answers
	assert(#revealed == 2, "revealed " .. #revealed)
	-- The reveal went ONLY to Dave.
	for _, entry in ipairs(log.PhoneResult) do
		if entry.args[1] == "reveal" then
			assert(entry.player == dave and not entry.all, "reveal broadcast")
		end
	end
	-- And they are right.
	local version = TestS.version(dave)
	for _, r in ipairs(revealed) do
		assert(r.option == TestPaper.correctOption(Bank, version, r.slot), "revealed a wrong answer")
	end
	-- Put the phone away, then answer (answering is safe).
	PS.request(dave, false, simTime)
	run(1)
	for _, r in ipairs(revealed) do
		assert(TestS.answer(dave, r.slot, r.option, simTime), "answer refused")
	end
	local correct = TestPaper.grade(Bank, version, TestS.paper(dave).answers)
	assert(correct == 2, "graded " .. correct)
	assert(count("Test", "ack", dave) >= 2)
	boardRate = (st.susp.value - before) / 10
	assert(st.susp.value < TeacherConfig.Suspicion.Question, "suspicious while she faces the board: " .. st.susp.value)
	assert(not st.detention)
	-- Hiding mid-scan loses the screenshot.
	holdPhoneUp(dave)
	assert(PS.action(dave, "snap", simTime))
	run(PhoneConfig.Snap.AimSeconds + 0.3)
	PS.request(dave, false, simTime)
	run(0.3)
	assert(PS.get(dave).scan == nil and count("PhoneResult", "scanFailed", dave) >= 1, "hidden scan still finished")
	assert(#TestS.revealedList(dave) == 2, "a cancelled scan revealed answers")
	run(1)
end)

check("walking the rows: a snap during the walk gets her CAUGHT -> test ripped -> detention", function()
	forcePhase("Walk")
	local st = RS_.student(alice)
	-- Alice answers 3 questions honestly first, so there's something to rip up.
	for slot = 1, 3 do
		assert(TestS.answer(alice, slot, 1, simTime))
	end
	local before = st.susp.value
	local caughtAt
	local t0 = simTime
	PS.request(alice, true, simTime)
	run(45, function()
		if not caughtAt and st.detention then
			caughtAt = simTime
		end
		local p = PS.get(alice)
		if p and p.state == "up" and not p.scan then
			PS.action(alice, "snap", simTime)
		end
	end)
	assert(caughtAt, "never caught during a 45 s walk (suspicion " .. st.susp.value .. ")")
	walkRate = (1 - before) / (caughtAt - t0)
	print(string.format("        suspicion/s: board %.4f vs walk %.3f, caught after %.1fs", boardRate, walkRate, caughtAt - t0))
	assert(walkRate > boardRate * 10, "walking isn't riskier than the board phase")
	assert(alice:GetAttribute("PA_Status") == "Detention" and RS_.inDetention(alice))
	assert(PS.get(alice).confiscated and not PS.isOut(alice))
	assert(PS.get(alice).confiscatedModel and (PS.get(alice).confiscatedModel.PrimaryPart.CFrame.Position - world.basket.CFrame.Position).Magnitude < 3, "phone not in the CONFISCATED basket")
	-- The test is ripped up: no answers, no revealed answers, graded F / 0.
	local paper = TestS.paper(alice)
	assert(paper.ripped and next(paper.answers) == nil and next(paper.revealed) == nil, "test not zeroed")
	local grade = TestS.grade(alice, { multiplier = 1 })
	assert(grade.letter == "F" and grade.clout == 0 and grade.percent == 0, "ripped test still scores")
	assert(count("Test", "ripped", alice) >= 1)
	assert(world.props:FindFirstChild("Paper_" .. alice.UserId).Name == "Paper_" .. alice.UserId)
	assert(not TestS.answer(alice, 4, 1, simTime), "answered from detention")
	assert(count("Effect", "Caught") >= 1 and count("Chat", nil) >= 1)
	assert(DS.getProfile(alice).Stats.Caught == 1)
	assert(not PS.request(alice, true, simTime), "phone came back out in detention")
	assert(RS_.deskOf(alice) == nil)
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
	assert(not TestS.paper(alice).ripped, "no fresh test copy after escaping")
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

check("remote validation: phone + answer inputs are type-checked and rate limited; no answers without a scan", function()
	local onPhone = remotes.Phone.OnServerEvent
	local onAction = remotes.PhoneAction.OnServerEvent
	local onAnswer = remotes.Answer.OnServerEvent
	onPhone:Fire(bob, "yes")
	onPhone:Fire(bob, 1)
	assert(not PS.isOut(bob), "non-boolean accepted")
	-- Answers: slot / option must be integers in range on the student's own paper.
	local paper = TestS.paper(bob)
	paper.tokens = 100
	onAnswer:Fire(bob, 0 / 0, 1)
	onAnswer:Fire(bob, 1, 0 / 0)
	onAnswer:Fire(bob, 11, 1)
	onAnswer:Fire(bob, 1, 5)
	onAnswer:Fire(bob, 1.5, 2)
	onAnswer:Fire(bob, "1", "2")
	onAnswer:Fire(bob, { 1 }, 2)
	assert(next(paper.answers) == nil, "invalid answer stored")
	onAnswer:Fire(bob, 2, 3)
	assert(paper.answers[2] == 3)
	-- Answer clicks are rate limited.
	paper.tokens = GameConfig.Test.AnswerRate
	local accepted = 0
	for i = 1, 40 do
		if TestS.answer(bob, (i % 10) + 1, 1, simTime) then
			accepted += 1
		end
	end
	assert(accepted <= GameConfig.Test.AnswerRate, "answer rate limit: " .. accepted)
	-- Phone actions: unknown kinds and junk args do nothing; a snap needs the phone OUT.
	local reveals = count("PhoneResult", "reveal")
	onAction:Fire(bob, "reveal")
	onAction:Fire(bob, "answers")
	onAction:Fire(bob, { "snap" })
	onAction:Fire(bob, string.rep("x", 200))
	onAction:Fire(bob, "snap")
	assert(PS.get(bob).scan == nil, "snap with the phone down")
	onAction:Fire(bob, "watch")
	assert(PS.get(bob).watchUntil == nil, "watch without the upgrade")
	onAction:Fire(bob, "peek")
	assert(count("PhoneResult", "reveal") == reveals, "an answer leaked without a server-side scan")
	-- Burst: at most ActionsPerSecond actions in the same instant.
	onPhone:Fire(bob, true)
	run(0.4)
	assert(PS.isFullyUp(bob))
	local p = PS.get(bob)
	p.actionTokens = PhoneConfig.ActionsPerSecond
	local okCount = 0
	for _ = 1, 30 do
		local _, reason = PS.action(bob, "watch", simTime)
		if reason ~= "rate" then
			okCount += 1
		end
	end
	assert(okCount <= PhoneConfig.ActionsPerSecond, "action rate limit: " .. okCount)
	PS.request(bob, false, simTime)
	run(1)
	-- No answers once the test is over (checked again after the bell below).
end)

check("smart watch: 1 answer with the phone AWAY, then a long cooldown", function()
	local profile = DS.getProfile(carol)
	-- carol is in detention: use eve instead
	profile = DS.getProfile(eve)
	profile.Upgrades.Watch = 1
	PS.refreshStats(eve)
	local p = PS.get(eve)
	assert(p.stats.watch, "watch stats missing")
	assert(not PS.isOut(eve))
	assert(PS.action(eve, "watch", simTime), "watch refused")
	assert(not PS.action(eve, "watch", simTime + 0.1), "watch spam allowed")
	run(p.stats.watch.glance + 0.2)
	local res = lastFor("PhoneResult", eve)
	assert(res and res[1] == "reveal" and #res[2].answers == 1 and res[2].source == "watch", "watch did not reveal 1")
	simTime += 2
	assert(not PS.action(eve, "watch", simTime), "watch ignored its cooldown")
	assert(TestS.paper(eve).cheated, "watch use should count as cheating (Ghost)")
end)

check("Answer Key Peek receipt (twice): 1 answer, max 1 per test, then saved", function()
	local before = #TestS.revealedList(eve)
	assert(receipt(eve, "AnswerPeek", "peek-1") == Decision.PurchaseGranted)
	assert(receipt(eve, "AnswerPeek", "peek-1") == Decision.PurchaseGranted)
	assert(#TestS.revealedList(eve) == before + 1, "peek did not reveal exactly 1")
	assert(TestS.paper(eve).peekUsed and DS.getProfile(eve).Tokens.Peek == 0)
	assert(receipt(eve, "AnswerPeek", "peek-2") == Decision.PurchaseGranted)
	assert(#TestS.revealedList(eve) == before + 1, "second peek in one test")
	assert(DS.getProfile(eve).Tokens.Peek == 1, "second peek not saved")
end)

check("screenshot flash she can see = instant suspicion", function()
	forcePhase("Lecture")
	run(0.5)
	holdPhoneUp(eve)
	local st = RS_.student(eve)
	st.susp.value = 0
	-- Point her straight at Eve.
	local b = TS.brain()
	local Detection = requireModule(Shared.Detection)
	b.heading = Detection.headingTo(b.x, b.z, st.desk.x, st.desk.z)
	b.distractUntil = nil
	assert(PS.action(eve, "snap", simTime))
	run(PhoneConfig.Snap.AimSeconds + 0.1)
	assert(st.susp.value >= PhoneConfig.Snap.FlashInstant or st.detention, "flash not noticed: " .. st.susp.value)
	PS.request(eve, false, simTime)
	run(2)
end)

check("an honest + cheating student: all 10 right = A+", function()
	forcePhase("Board")
	TS.brain().nextGlance = math.huge
	local version = TestS.version(dave)
	local paper = TestS.paper(dave)
	paper.tokens = 100
	for slot = 1, #version.order do
		-- (Dave studied: he knows the rest.)
		assert(TestS.answer(dave, slot, TestPaper.correctOption(Bank, version, slot), simTime))
	end
	local grade = TestS.grade(dave, { multiplier = 1 })
	assert(grade.correct == 10 and grade.letter == "A+" and grade.aplus == GameConfig.Test.APlusBonus)
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
	assert(res and res[1].caught == true and res[1].grade and res[1].grade.letter == "F" and res[1].grade.clout == 0, "caught student not zeroed")
	local daveRes = lastFor("Results", dave)
	local dg = daveRes and daveRes[1].grade
	assert(dg and dg.letter == "A+" and dg.correct == 10, "dave's A+ missing")
	assert(dg.clout >= GameConfig.Test.Grades[1].Clout + GameConfig.Test.APlusBonus, "A+ not paid")
	assert(DS.getProfile(dave).Stats.APlus == 1 and DS.getProfile(dave).Stats.Tests == 1)
	-- After the bell no more answers count.
	assert(not TestS.answer(dave, 1, 1, simTime), "answered after the bell")
	assert(DS.getProfile(dave).Stats.Classes == 1)
	assert(DS.getProfile(bob).Stats.CleanClasses == 0, "bob was caught")
	assert(DS.getProfile(dave).Stats.CleanClasses == (if stD.caught then 0 else 1))
	banked = true
	simTime += GameConfig.ResultsSeconds + 1
	RS_.step(0.1)
	assert(RS_.state() == "Hallway")
	for _, p in ipairs({ alice, bob, carol, dave, eve }) do
		assert(p:GetAttribute("PA_Status") == "Hallway" and RS_.deskOf(p) == nil and PS.get(p) == nil)
	end
	assert(not TestS.active() and count("Test", "clear") >= 5, "test not cleared")
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
	-- Everyone (not just the buyer) gets double Clout for their grade: Carol aces it.
	local version = TestS.version(carol)
	TestS.paper(carol).tokens = 100
	for slot = 1, #version.order do
		TestS.answer(carol, slot, TestPaper.correctOption(Bank, version, slot), simTime)
	end
	local carolPizzaGrade = TestS.grade(carol, { multiplier = SS.cloutMultiplier(carol) * GameConfig.PizzaCloutMultiplier })
	local carolPlainGrade = TestS.grade(carol, { multiplier = SS.cloutMultiplier(carol) })
	assert(carolPizzaGrade.clout >= carolPlainGrade.clout * 2 - 1, "pizza 2x not applied")
	-- Bought during class: starts right away; queue is capped.
	RS_.round().pizza = false
	assert(RS_.startPizza(alice) == true and RS_.round().pizza)
	for _ = 1, 5 do
		RS_.startPizza(alice)
	end
	assert(workspaceService:GetAttribute("PA_PizzaQueued") == GameConfig.PizzaMaxQueued)
	-- Queue full: not sold, and a late receipt isn't granted for a party that never happens.
	assert(not SS.buy(alice, "PizzaParty"), "pizza sold with a full queue")
	assert(receipt(alice, "PizzaParty", "pizza-full") == Decision.NotProcessedYet, "pizza receipt granted with a full queue")
	workspaceService:SetAttribute("PA_PizzaQueued", 0)
	-- The bell pays Carol's A+ at 2x (pizza class).
	local carolBefore = DS.getProfile(carol).Clout
	local pendingCarol = math.floor(RS_.student(carol).pending)
	RS_.endClass(simTime)
	local res = lastFor("Results", carol)
	assert(res and res[1].pizza and res[1].grade.letter == "A+", "pizza results")
	assert(res[1].grade.clout == carolPizzaGrade.clout, string.format("pizza grade paid %d, expected %d", res[1].grade.clout, carolPizzaGrade.clout))
	assert(DS.getProfile(carol).Clout >= carolBefore + pendingCarol + carolPizzaGrade.clout)
	simTime += GameConfig.ResultsSeconds + 1
	RS_.step(0.1)
	assert(RS_.beginBell())
	simTime += GameConfig.BellSeconds
	RS_.beginClass({ event = "None", seed = 5, lesson = only("Lecture") })
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

check("seating: seats never move, reset mid-class reseats, nobody stuck seated in the hallway", function()
	local seatCFrames = {}
	for _, desk in ipairs(world.desks) do
		seatCFrames[desk.seat] = desk.seat.CFrame
	end
	for _, seat in ipairs(world.detentionSeats) do
		seatCFrames[seat] = seat.CFrame
	end
	local function seatsUnmoved()
		for seat, cf in pairs(seatCFrames) do
			assert((seat.CFrame.Position - cf.Position).Magnitude < 1e-3, seat:GetFullName() .. " was dragged along with a player")
		end
	end
	assert(RS_.beginBell())
	simTime += GameConfig.BellSeconds
	RS_.beginClass({ event = "None", seed = 5, lesson = only("Board") })
	TS.brain().nextGlance = math.huge
	for _, p in ipairs({ alice, bob, carol }) do
		local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
		assert(seatedIn(humanoid) == RS_.deskOf(p).seat, p.Name .. " not in their desk seat")
		assert(humanoid.JumpPower == 0, "jump not locked")
	end
	-- Caught: desk seat -> detention stool. Released: back again.
	local aliceDesk = RS_.deskOf(alice)
	DS.getProfile(alice).Tokens.HallPass = 0
	RS_.addSuspicion(alice, 1)
	assert(RS_.inDetention(alice))
	local aliceHumanoid = alice.Character:FindFirstChildOfClass("Humanoid")
	assert(seatedIn(aliceHumanoid) == RS_.student(alice).detentionSeat, "not on a detention stool")
	assert(not aliceDesk.seat:FindFirstChild("SeatWeld"), "still welded to the desk seat")
	seatsUnmoved()
	DS.addClout(alice, 1000, false)
	assert(RS_.bail(alice))
	assert(seatedIn(aliceHumanoid) == aliceDesk.seat)
	seatsUnmoved()
	-- Phone mashing: a hide request is never dropped by the toggle limit.
	simTime += 2
	assert(PS.request(bob, true, simTime))
	run(0.5)
	for _ = 1, 3 do
		PS.request(bob, false, simTime)
		PS.request(bob, true, simTime)
	end
	assert(PS.request(bob, false, simTime), "hide request dropped by the toggle limit")
	run(1)
	assert(not PS.isOut(bob), "phone stuck out after mashing")
	-- Reset mid-class: the new character goes straight back to the desk, jump locked.
	local old = bob.Character
	local character = roblox.Instance.new("Model")
	character.Name = "Bob"
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	character.PrimaryPart = root
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.JumpPower = 50
	humanoid.Parent = character
	old:Destroy()
	character.Parent = workspaceService
	bob.Character = character
	bob.CharacterAdded:Fire(character)
	assert(seatedIn(humanoid) == RS_.deskOf(bob).seat and humanoid.JumpPower == 0, "respawned student not reseated")
	seatsUnmoved()
	-- Bell -> hallway: everyone unwelded, jump restored, seats where they were.
	RS_.endClass(simTime)
	simTime += GameConfig.ResultsSeconds + 1
	RS_.step(0.1)
	assert(RS_.state() == "Hallway")
	for _, p in ipairs({ alice, bob, carol }) do
		local h = p.Character:FindFirstChildOfClass("Humanoid")
		assert(seatedIn(h) == nil and h.JumpPower > 0, p.Name .. " stuck seated / frozen in the hallway")
	end
	for seat in pairs(seatCFrames) do
		local weld = seat:FindFirstChild("SeatWeld")
		assert(not (weld and weld.Part1 and weld.Part1:IsDescendantOf(workspaceService)), "a SeatWeld survived the bell: " .. (weld and weld.Part1 and weld.Part1.Parent.Name or ""))
	end
	seatsUnmoved()
	-- Everyone in detention with their escape used: the bell rings early (no soft-lock).
	assert(RS_.beginBell())
	simTime += GameConfig.BellSeconds
	RS_.beginClass({ event = "None", seed = 6, lesson = only("Board") })
	for _, p in ipairs({ alice, bob, carol, eve }) do
		local st = RS_.student(p)
		DS.getProfile(p).Tokens.HallPass = 0
		st.escapeUsed = true
		RS_.addSuspicion(p, 1)
		assert(st.detention)
	end
	run(0.2)
	assert(RS_.state() == "Results", "class kept going with nobody able to play")
	simTime += GameConfig.ResultsSeconds + 1
	RS_.step(0.1)
	assert(RS_.state() == "Hallway")
	seatsUnmoved()
end)

check("Clout upgrades and cosmetics: buy, equip, maxed, not enough Clout", function()
	local CSv = registry.CosmeticService
	local profile = DS.getProfile(alice)
	profile.Clout = 700
	assert(CSv.buyUpgrade(alice, "Phone"))
	assert(profile.Upgrades.Phone == 2 and profile.Clout == 100)
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
	-- No policy answer yet (fresh player): fail safe, no paid random items.
	local stranger = roblox.Instance.new("Player")
	assert(not SS.randomItemsAllowed(stranger), "paid random items allowed before the policy lookup")
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
			if p and p.state == "up" and not p.scan then
				PS.action(bob, "snap", simTime)
			elseif p and p.state == "down" and not p.confiscated then
				PS.request(bob, true, simTime)
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
	assert((DS.getProfile(bob).Stats.Revealed or 0) > 0, "bob never revealed anything in 5 classes")
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
	for _, name in ipairs({ "ClientState", "HudController", "PhoneController", "TeacherController", "TestController", "MenuController", "EffectsController" }) do
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
	-- Test paper UI with a real server-made view.
	local Rng = requireModule(Shared.Rng)
	local built = TestPaper.build(Bank, GameConfig.Test, Rng.new(5))
	local view = TestPaper.clientView(Bank, built.versions.B, 200)
	view.answers = {}
	CSt.test = view
	CSt.TestChanged:Fire("view", view)
	local Test = controllers.TestController
	Test.select(3)
	Test.answer(2)
	assert(view.answers[3] == 2, "answer not recorded locally")
	CSt.TestChanged:Fire("ack", view)
	-- Phone scanner: idle, aiming, scanning, revealed, failed.
	CSt.phone = { state = "down", confiscated = false, cooldownUntil = 0, hide = 0.4, answersPerSnap = 2, scanSeconds = 6, revealed = {}, remaining = 10, watch = { cooldownUntil = 0, cooldown = 45, glance = 3 } }
	CSt.PhoneChanged:Fire(CSt.phone)
	local Phone = controllers.PhoneController
	Phone.press()
	assert(Phone.isUp(), "phone did not come up")
	Phone._primary()
	CSt.phone.scan = { stage = "aim", untilT = Clock.now() + 0.6 }
	CSt.PhoneResult:Fire("aim", { untilT = Clock.now() + 0.6 })
	CSt.phone.scan = { stage = "process", untilT = Clock.now() + 5 }
	CSt.PhoneResult:Fire("shutter", { untilT = Clock.now() + 5 })
	stubServices.RunService.RenderStepped:Fire(1 / 60)
	CSt.phone.scan = nil
	CSt.PhoneResult:Fire("reveal", { answers = { { slot = 1, option = 3 }, { slot = 4, option = 1 } }, source = "snap", all = { { slot = 1, option = 3 }, { slot = 4, option = 1 } } })
	CSt.PhoneResult:Fire("scanFailed", {})
	CSt.PhoneResult:Fire("watch", { untilT = Clock.now() + 3 })
	Phone.watch()
	Phone.release()
	assert(not Phone.isUp())
	CSt.TestChanged:Fire("ripped", view)
	CSt.TestChanged:Fire("clear", nil)
	-- HUD
	local Hud = controllers.HudController
	CSt.QuizChanged:Fire({ question = "7 x 8 = ?", options = { "54", "56", "64", "48" }, seconds = 9, endsAt = Clock.now() + 9 })
	CSt.QuizResult:Fire({ correct = false, distracted = true, answer = "56", reward = 0 })
	CSt.QuizChanged:Fire(nil)
	CSt.Chat:Fire("front_row_fiona", "rip Alice's phone (2024-2024)", { 255, 120, 120 })
	for i = 1, 8 do
		CSt.Chat:Fire("kev_the_legend", "msg " .. i)
	end
	CSt.Notified:Fire("Hello class", "good")
	CSt.Announced:Fire("Bob bought a PIZZA PARTY!", { 255, 150, 60 })
	CSt.Results:Fire({ clout = 123, lost = 20, caught = true, quiz = "phone", walkSecs = 12, snaps = 3, pizza = true, legend = "Bob", grade = { correct = 0, count = 10, percent = 0, letter = "F", base = 0, aplus = 0, ghost = 0, clout = 0, ripped = true, version = "A" }, top = { { name = "Bob", clout = 300, caught = false, letter = "A+" }, { name = "Alice", clout = 123, caught = true, letter = "F" } } })
	CSt.Results:Fire({ clout = 400, lost = 0, caught = false, snaps = 2, grade = { correct = 10, count = 10, percent = 100, letter = "A+", base = 150, aplus = 50, ghost = 60, clout = 260, ripped = false, version = "B" }, top = {} })
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
	for _, name in ipairs({ "PA_HUD", "PA_Phone", "PA_Test", "PA_Menu", "PA_FX" }) do
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
