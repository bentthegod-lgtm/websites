--[[
	RoundService - the class period loop and the stealth rules.

	Hallway (intermission, shop, leaderboard) -> Bell (everyone to their desk, party seating,
	VIP desks) -> Class (~3:20: lesson phases, pop quiz, one random event) -> Results ->
	Hallway.

	Every tick in class (GameConfig.TickRate):
	  * the teacher brain moves / turns (TeacherService),
	  * every phone updates (PhoneService),
	  * the SERVER computes what the teacher (and principal) can see and hear for every
	    student (Detection) and raises / lowers each student's suspicion,
	  * at full suspicion: CONFISCATED -> detention corner (unless a Fake Hall Pass saves you).

	Clout earned during class is "pending" and banked at the bell. Getting caught loses
	GameConfig.CatchPendingLoss of it. Detention lasts until the bell, unless you buy your way
	out with Clout or a Get Out of Detention pass (once per class).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local PhoneConfig = require(Shared.Config.PhoneConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Detection = require(Shared.Detection)
local Lesson = require(Shared.Lesson)
local Seating = require(Shared.Seating)
local Economy = require(Shared.Economy)
local CrateRoll = require(Shared.CrateRoll)
local Props = require(Shared.Props)
local Format = require(Shared.Format)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local RoundService = {}

local services
local rng = Rng.new(os.time() % 88883 + 5)
local state = "Hallway"
local stateEndsAt = 0
local round -- current class
local students = {} -- [player] = student state (seated this class)
local friendCache = {}
local decorModels = {}
local lastReseat = 0

local TOPICS = {
	{ "Today: THE WATER CYCLE", "1. Evaporation (water goes up)", "2. Condensation (clouds!)", "3. Precipitation (rain)", "4. Collection", "Quiz may happen. Just saying." },
	{ "Today: FRACTIONS", "1/2 + 1/4 = 3/4", "Pizza = best fraction example", "Simplify! 4/8 = 1/2", "Homework: p. 42", "Phones away please :)" },
	{ "Today: VOLCANOES", "Magma -> Lava", "Ring of Fire", "Shield vs Cone", "Baking soda project Fri", "No, you can't film it." },
	{ "Today: POETRY", "Rhyme & rhythm", "Haiku: 5-7-5", "Similes are LIKE this", "Write 1 poem tonight", "Not about your phone." },
	{ "Today: ANCIENT EGYPT", "Pyramids (old & pointy)", "Hieroglyphs", "The Nile river", "Mummies: not scary", "Test next week!" },
}

function RoundService.init(registry)
	services = registry
end

---------------------------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------------------------

function RoundService.state()
	return state
end

function RoundService.round()
	return round
end

function RoundService.student(player)
	return students[player]
end

function RoundService.inClass(player)
	return students[player] ~= nil and (state == "Class" or state == "Bell")
end

function RoundService.inDetention(player)
	local st = students[player]
	return st ~= nil and st.detention
end

-- The desk of a seated student (nil in detention or outside class).
function RoundService.deskOf(player)
	local st = students[player]
	if not st or st.detention or (state ~= "Class" and state ~= "Bell") then
		return nil
	end
	return st.desk
end

function RoundService.canUsePhone(player)
	local st = students[player]
	return state == "Class" and st ~= nil and not st.detention
end

function RoundService.currentPhase()
	return round and round.phase or nil
end

function RoundService.isQuiz()
	return state == "Class" and round ~= nil and round.phase == "Quiz"
end

function RoundService.cloutMultiplier()
	if not round then
		return 1
	end
	local m = 1
	if round.pizza then
		m *= GameConfig.PizzaCloutMultiplier
	end
	local phaseCfg = round.phase and TeacherConfig.Phases[round.phase]
	if phaseCfg and phaseCfg.Clout then
		m *= phaseCfg.Clout
	end
	return m
end

local function currentDetection()
	if not round then
		return 1
	end
	local d = 1
	if round.event == "Substitute" then
		d *= TeacherConfig.Events.Substitute.Detection
	end
	if round.pizza then
		d *= GameConfig.PizzaDetectionMultiplier
	end
	if round.principalIn then
		d *= TeacherConfig.Events.Principal.Detection
	end
	return d
end
RoundService.currentDetection = currentDetection

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function setWorkspace(key, value)
	workspace:SetAttribute("PA_" .. key, value)
end

local function broadcast(data)
	services.Remotes.RoundState:FireAllClients(state, data or {})
end

local function setState(newState, duration, data)
	state = newState
	stateEndsAt = Clock.now() + (duration or 0)
	setWorkspace("State", newState)
	setWorkspace("StateEnds", stateEndsAt)
	broadcast(data)
end

local function humanoidOf(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Breaks the SeatWeld holding this character. The desk / detention seats are anchored, so
-- pivoting a character that is still welded to one drags the seat along (and the welded
-- character stays frozen wherever it lands). Humanoid.Sit = false alone is not reliable
-- from the server, so the weld itself is destroyed before any move.
local function unseat(player)
	local character = player.Character
	local humanoid = humanoidOf(player)
	local seat = humanoid and humanoid.SeatPart
	if seat and character then
		for _, child in ipairs(seat:GetChildren()) do
			if child.Name == "SeatWeld" and child:IsA("JointInstance") and child.Part1 and child.Part1:IsDescendantOf(character) then
				child:Destroy()
			end
		end
	end
	if humanoid then
		humanoid.Sit = false
	end
end

local function seatPlayer(player, seat)
	local character = player.Character
	if not character or not seat then
		return
	end
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		if humanoid.SeatPart == seat then
			return -- already there (re-pivoting would drag the anchored seat)
		end
	end
	unseat(player)
	pcall(function()
		character:PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0))
	end)
	if humanoid then
		pcall(function()
			seat:Sit(humanoid)
		end)
	end
end

local function freePlayer(player, spot)
	unseat(player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 50
	end
	local character = player.Character
	if character and spot then
		pcall(function()
			character:PivotTo(spot)
		end)
	end
end

local function areFriends(a, b)
	local key = if a.UserId < b.UserId then a.UserId .. ":" .. b.UserId else b.UserId .. ":" .. a.UserId
	if friendCache[key] == nil then
		local ok, result = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		friendCache[key] = ok and result == true
	end
	return friendCache[key]
end

local function sendSuspicion(player, st, force)
	local mark = Detection.mark(st.susp.value, TeacherConfig.Suspicion)
	if force or math.abs(st.susp.value - st.sentValue) >= 0.02 or mark ~= st.sentMark or math.abs(st.pending - st.sentPending) >= 1 then
		st.sentValue, st.sentMark, st.sentPending = st.susp.value, mark, st.pending
		services.Remotes.Suspicion:FireClient(player, st.susp.value, mark, math.floor(st.pending))
	end
end

local function tagFor(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local tag = head:FindFirstChild("PA_Tag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "PA_Tag"
		tag.Size = UDim2.fromOffset(200, 44)
		tag.StudsOffset = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 70
		tag.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextStrokeTransparency = 0.4
		label.RichText = true
		label.Parent = tag
		tag.Parent = head
	end
	return tag
end

function RoundService.refreshTag(player)
	local tag = tagFor(player)
	if not tag then
		return
	end
	local profile = services.DataService.getProfile(player)
	local rank = Economy.rankFor(profile and profile.Level or 1, ProgressionConfig.Ranks)
	local parts = {}
	if services.ShopService.owns(player, "VIP") then
		table.insert(parts, "<font color='#FF8CD2'>[VIP]</font>")
	end
	if player:GetAttribute("PA_Pet") then
		table.insert(parts, "<font color='#FFE066'>[PET]</font>")
	end
	local c = rank.Color
	table.insert(parts, string.format("<font color='#%02X%02X%02X'>%s</font>", c[1], c[2], c[3], rank.Name))
	tag.Label.Text = table.concat(parts, " ")
	tag.Label.TextColor3 = Color3.new(1, 1, 1)
end

-- Desk decoration + phone model for a seated student.
function RoundService.refreshDesk(player)
	local st = students[player]
	if not st then
		return
	end
	if decorModels[player] then
		decorModels[player]:Destroy()
		decorModels[player] = nil
	end
	local profile = services.DataService.getProfile(player)
	local item = profile and CrateRoll.find(CosmeticConfig, "Decor", profile.Equipped.Decor)
	if item and item.Style then
		local m = Props.decor(item.Style, st.desk.decor)
		m.Name = "Decor_" .. player.UserId
		m.Parent = services.World.props
		decorModels[player] = m
	end
	services.PhoneService.rebuildModel(player)
end

---------------------------------------------------------------------------------------------
-- Pending Clout / suspicion
---------------------------------------------------------------------------------------------

function RoundService.addPending(player, amount)
	local st = students[player]
	if not st or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	st.pending += amount
	return amount
end

function RoundService.addSuspicion(player, amount)
	local st = students[player]
	if not st or st.detention or state ~= "Class" then
		return
	end
	Detection.step(st.susp, 0, amount, 0, TeacherConfig.Suspicion)
	if st.susp.value >= TeacherConfig.Suspicion.Catch then
		RoundService.handleCatch(player, Clock.now())
	else
		sendSuspicion(player, st, true)
	end
end

function RoundService.addNoise(player, amount)
	local p = services.PhoneService.get(player)
	if p then
		p.noise = math.min(TeacherConfig.Hearing.MaxNoise, p.noise + amount)
	end
end

function RoundService.selfieFlash(player)
	if rng:chance(0.35) then
		services.ClassmateService.chat("Selfie", player.DisplayName)
	end
	services.Remotes.Effect:FireAllClients("Flash", { userId = player.UserId })
end

---------------------------------------------------------------------------------------------
-- Pizza Party (developer product, server-wide)
---------------------------------------------------------------------------------------------

local PIZZA_COLOR = { 255, 150, 60 }
for _, product in ipairs(ShopConfig.Products) do
	if product.Key == "PizzaParty" then
		PIZZA_COLOR = product.Color
	end
end

-- Can another Pizza Party be bought right now (starts now, or fits in the queue)?
function RoundService.canAddPizza()
	if state == "Class" and round and not round.pizza then
		return true
	end
	return (workspace:GetAttribute("PA_PizzaQueued") or 0) < GameConfig.PizzaMaxQueued
end

-- Returns true when it started right away (bought during class), false when queued.
function RoundService.startPizza(buyer)
	local name = buyer.DisplayName
	local immediate = false
	if state == "Class" and round and not round.pizza then
		round.pizza = true
		round.pizzaBy = name
		services.TeacherService.setDetection(currentDetection())
		setWorkspace("Pizza", true)
		setWorkspace("PizzaBy", name)
		immediate = true
	else
		local queued = math.min(GameConfig.PizzaMaxQueued, (workspace:GetAttribute("PA_PizzaQueued") or 0) + 1)
		setWorkspace("PizzaQueued", queued)
		setWorkspace("PizzaNextBy", name)
	end
	services.Remotes.Announce:FireAllClients(string.format("%s bought a PIZZA PARTY for the whole class! Chill teacher + 2x Clout %s!", name, if immediate then "RIGHT NOW" else "next class"), PIZZA_COLOR)
	services.Remotes.Effect:FireAllClients("Pizza", { by = name, now = immediate })
	services.ClassmateService.chat("Pizza", name)
	return immediate
end

---------------------------------------------------------------------------------------------
-- Catching, detention, escapes
---------------------------------------------------------------------------------------------

local function detentionSeatFor(player)
	local used = {}
	for other, st in pairs(students) do
		if other ~= player and st.detention and st.detentionSeat then
			used[st.detentionSeat] = true
		end
	end
	for _, seat in ipairs(services.World.detentionSeats) do
		if not used[seat] then
			return seat
		end
	end
	return services.World.detentionSeats[1]
end

function RoundService.handleCatch(player, now)
	local st = students[player]
	if not st or st.detention or state ~= "Class" then
		return
	end
	local profile = services.DataService.getProfile(player)
	-- Fake Hall Pass: the first catch of the class is forgiven.
	if profile and profile.Tokens.HallPass > 0 and not st.hallUsed then
		profile.Tokens.HallPass -= 1
		st.hallUsed = true
		st.susp.value = 0.35
		services.PhoneService.forceDown(player)
		services.DataService.markDirty(player)
		services.Remotes.Effect:FireAllClients("Forgiven", { userId = player.UserId, name = player.DisplayName })
		services.Remotes.Notify:FireClient(player, "\"I have a hall pass!\" ...she bought it. (Fake Hall Pass used)", "good")
		services.ClassmateService.chat("Forgiven", player.DisplayName)
		sendSuspicion(player, st, true)
		services.DataService.sendProfile(player)
		return "forgiven"
	end
	st.detention = true
	st.caught = true
	st.catches += 1
	local loss = math.floor(st.pending * GameConfig.CatchPendingLoss)
	st.pending -= loss
	st.lost += loss
	st.susp.value = 0
	if profile then
		profile.Stats.Caught += 1
		services.DataService.markDirty(player)
	end
	services.PhoneService.confiscate(player)
	services.TeacherService.caught(st.desk.x, st.desk.z, now)
	st.detentionSeat = detentionSeatFor(player)
	seatPlayer(player, st.detentionSeat)
	player:SetAttribute("PA_Status", "Detention")
	services.Remotes.Effect:FireAllClients("Caught", { userId = player.UserId, name = player.DisplayName, desk = st.desk.index, lost = loss })
	services.ClassmateService.chat("Caught", player.DisplayName, { 255, 120, 120 })
	sendSuspicion(player, st, true)
	return "caught"
end

local function release(player, how)
	local st = students[player]
	st.detention = false
	st.escapeUsed = true
	st.detentionSeat = nil
	st.susp.value = GameConfig.DetentionReturnSuspicion
	st.susp.quietFor = 0
	seatPlayer(player, st.desk.seat)
	player:SetAttribute("PA_Status", "Seated")
	services.PhoneService.returnPhone(player, GameConfig.DetentionPhoneCooldown)
	services.Remotes.Effect:FireAllClients("Released", { userId = player.UserId, name = player.DisplayName, how = how })
	services.ClassmateService.chat("Bailout", player.DisplayName)
	sendSuspicion(player, st, true)
end

function RoundService.bail(player)
	local st = students[player]
	if state ~= "Class" or not st or not st.detention then
		return false, "You're not in detention."
	end
	if st.escapeUsed then
		return false, "You already escaped once this class!"
	end
	local profile = services.DataService.getProfile(player)
	local cost = Economy.bailCost(profile and profile.Level or 1, GameConfig)
	if not services.DataService.spendClout(player, cost) then
		return false, string.format("You need %d Clout to talk your way out.", cost)
	end
	release(player, "bail")
	services.DataService.sendProfile(player)
	return true
end

function RoundService.useDetentionPass(player)
	local st = students[player]
	local profile = services.DataService.getProfile(player)
	if state ~= "Class" or not st or not st.detention or not profile then
		return false, "You're not in detention."
	end
	if st.escapeUsed then
		return false, "You already escaped once this class! (Your pass is saved.)"
	end
	if profile.Tokens.DetentionPass <= 0 then
		return false, "No Get Out of Detention passes."
	end
	profile.Tokens.DetentionPass -= 1
	services.DataService.markDirty(player)
	release(player, "pass")
	services.DataService.sendProfile(player)
	return true
end

---------------------------------------------------------------------------------------------
-- Pop quiz
---------------------------------------------------------------------------------------------

local function startQuiz(now)
	local q = PhoneConfig.Quiz[rng:integer(1, #PhoneConfig.Quiz)]
	round.quiz = { q = q, answers = {}, endsAt = now + GameConfig.Quiz.Seconds }
	services.PhoneService.markQuizStart()
	for player, st in pairs(students) do
		if not st.detention then
			services.Remotes.Quiz:FireClient(player, { question = q.Q, options = q.A, seconds = GameConfig.Quiz.Seconds, endsAt = round.quiz.endsAt })
		end
	end
	services.ClassmateService.chat("Quiz")
end

function RoundService.answerQuiz(player, index)
	local st = students[player]
	local quiz = round and round.quiz
	if not quiz or not st or st.detention or type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > 3 then
		return false
	end
	if quiz.answers[player] then
		return false
	end
	quiz.answers[player] = index
	return true
end

local function gradeQuiz()
	local quiz = round and round.quiz
	if not quiz then
		return
	end
	round.quiz = nil
	for player, st in pairs(students) do
		if not st.detention and player.Parent then
			local answer = quiz.answers[player]
			local distracted = services.PhoneService.quizDistracted(player)
			local correct = answer == quiz.q.Correct and not distracted
			local reward = 0
			if correct then
				reward = GameConfig.Quiz.Reward * (if player:GetAttribute("PA_Pet") then 1 + GameConfig.Pet.QuizBonus else 1)
				RoundService.addPending(player, reward)
				services.DataService.addXP(player, GameConfig.Quiz.XP)
				local profile = services.DataService.getProfile(player)
				if profile then
					profile.Stats.QuizCorrect += 1
				end
				services.RewardService.track(player, "QuizCorrect", 1)
			else
				RoundService.addSuspicion(player, GameConfig.Quiz.WrongSuspicion)
			end
			st.quiz = if correct then "correct" elseif distracted then "phone" else "wrong"
			services.Remotes.QuizResult:FireClient(player, { correct = correct, distracted = distracted, answered = answer ~= nil, answer = quiz.q.A[quiz.q.Correct], reward = reward })
		end
		services.Remotes.Quiz:FireClient(player, nil)
	end
end
RoundService._gradeQuiz = gradeQuiz

---------------------------------------------------------------------------------------------
-- Phases and events
---------------------------------------------------------------------------------------------

local function writeBoard(lines)
	if services.World.boardText then
		services.World.boardText.Text = table.concat(lines, "\n")
	end
end

local function onPhase(entry, index, now)
	local previous = round.phase
	if previous == "Quiz" then
		gradeQuiz()
	end
	if previous == "FireDrill" then
		services.Remotes.Effect:FireAllClients("FireDrillEnd", {})
	end
	round.phase = entry.phase
	round.phaseIndex = index
	services.TeacherService.setPhase(entry.phase, now)
	local cfg = TeacherConfig.Phases[entry.phase]
	setWorkspace("Phase", entry.phase)
	setWorkspace("PhaseEnds", round.start + entry.start + entry.duration)
	services.Remotes.PhaseChanged:FireAllClients({ phase = entry.phase, label = cfg.Label, risk = cfg.Risk, color = cfg.Color, endsAt = round.start + entry.start + entry.duration })
	if entry.phase == "Board" then
		-- She writes the next line of today's lesson.
		round.boardLines = math.min(#round.topic, (round.boardLines or 1) + 1)
		local lines = {}
		for i = 1, round.boardLines do
			lines[i] = round.topic[i]
		end
		writeBoard(lines)
	elseif entry.phase == "Quiz" then
		startQuiz(now)
	elseif entry.phase == "FireDrill" then
		services.Remotes.Effect:FireAllClients("FireDrill", { seconds = entry.duration })
		services.Remotes.Announce:FireAllClients(TeacherConfig.Events.FireDrill.Text, cfg.Color)
		services.ClassmateService.chat("FireDrill")
	elseif entry.phase == "LunchCheck" then
		services.Remotes.Effect:FireAllClients("Bell", { early = true })
		services.Remotes.Announce:FireAllClients(TeacherConfig.Events.LunchBell.Text, cfg.Color)
		services.ClassmateService.chat("Lunch")
	end
	-- Profile refresh so goal progress on the HUD stays current.
	for player in pairs(students) do
		services.DataService.sendProfile(player)
	end
end

local function updatePrincipal(t, now)
	if round.event ~= "Principal" then
		return
	end
	local active = Lesson.eventActive(round.lesson, t)
	if active and not round.principalIn then
		round.principalIn = true
		services.TeacherService.principalEnter(now)
		services.TeacherService.setDetection(currentDetection())
		setWorkspace("Principal", true)
		services.Remotes.Announce:FireAllClients(TeacherConfig.Events.Principal.Text, { 255, 80, 80 })
		services.Remotes.Effect:FireAllClients("Principal", { on = true })
		services.Remotes.Effect:FireAllClients("Door", {})
		services.ClassmateService.chat("Principal")
	elseif not active and round.principalIn then
		round.principalIn = false
		services.TeacherService.principalLeave()
		services.TeacherService.setDetection(currentDetection())
		setWorkspace("Principal", false)
		services.Remotes.Effect:FireAllClients("Principal", { on = false })
		services.Remotes.Effect:FireAllClients("Door", {})
	end
end

---------------------------------------------------------------------------------------------
-- Round flow
---------------------------------------------------------------------------------------------

local function eligiblePlayers()
	local list = {}
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		if player.Character and #list < GameConfig.MaxPlayers then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function RoundService.beginBell()
	local players = eligiblePlayers()
	if #players == 0 then
		return false
	end
	local list = {}
	for _, player in ipairs(players) do
		local friends = {}
		for _, other in ipairs(players) do
			if other ~= player and areFriends(player, other) then
				friends[other.UserId] = true
			end
		end
		table.insert(list, { id = player.UserId, vip = services.ShopService.owns(player, "VIP"), friends = friends, player = player })
	end
	local assignment = Seating.assign(list, services.World.desks, rng)
	students = {}
	for _, entry in ipairs(list) do
		local player = entry.player
		local desk = services.World.desks[assignment[entry.id]]
		if desk then
			local profile = services.DataService.getProfile(player)
			students[player] = {
				desk = desk,
				susp = { value = 0, quietFor = 0 },
				sentValue = -1,
				sentMark = "",
				sentPending = -1,
				pending = 0,
				lost = 0,
				caught = false,
				catches = 0,
				detention = false,
				hallUsed = false,
				escapeUsed = false,
				walkSecs = 0,
				boardSecs = 0,
			}
			player:SetAttribute("PA_Pet", profile ~= nil and profile.Settings.Pet == true)
			player:SetAttribute("PA_Status", "Seated")
			player:SetAttribute("PA_Desk", desk.index)
			desk.cardLabel.Text = player.DisplayName
			seatPlayer(player, desk.seat)
			services.PhoneService.setup(player, desk)
			RoundService.refreshDesk(player)
			RoundService.refreshTag(player)
		end
	end
	local door = services.World.door
	door.CFrame = services.World.doorClosed
	door.CanCollide = true
	services.Remotes.Effect:FireAllClients("Bell", {})
	setState("Bell", GameConfig.BellSeconds, { students = #players })
	return true
end

--[[
	opts (tests): { event = "None"|"Substitute"|..., seed = number, duration = number,
	                lesson = a prebuilt Lesson table }
]]
function RoundService.beginClass(opts)
	opts = opts or {}
	local now = Clock.now()
	local lessonRng = Rng.new(opts.seed or rng:integer(1, 2 ^ 30))
	local queued = workspace:GetAttribute("PA_PizzaQueued") or 0
	local pizza, pizzaBy = false, nil
	if queued > 0 then
		pizza = true
		pizzaBy = workspace:GetAttribute("PA_PizzaNextBy")
		setWorkspace("PizzaQueued", queued - 1)
	end
	local event = opts.event or Lesson.rollEvent(TeacherConfig, lessonRng, if pizza then { Substitute = true } else nil)
	local duration = opts.duration or GameConfig.ClassSeconds
	local lesson = opts.lesson or Lesson.build(TeacherConfig, duration, lessonRng, event)
	round = {
		start = now,
		duration = duration,
		lesson = lesson,
		event = event,
		pizza = pizza,
		pizzaBy = pizzaBy,
		phase = nil,
		phaseIndex = 0,
		topic = TOPICS[lessonRng:integer(1, #TOPICS)],
		boardLines = 0,
		principalIn = false,
		tickCount = 0,
	}
	services.ClassmateService.resetClass()
	services.TeacherService.startClass({ substitute = event == "Substitute", detection = currentDetection() }, now)
	writeBoard({ round.topic[1] })
	round.boardLines = 1
	setWorkspace("ClassStart", now)
	setWorkspace("ClassDuration", duration)
	setWorkspace("Event", event)
	setWorkspace("Pizza", pizza)
	setWorkspace("PizzaBy", pizzaBy or "")
	setWorkspace("Principal", false)
	setState("Class", duration, { event = event, pizza = pizza })
	if event == "Substitute" then
		services.Remotes.Announce:FireAllClients(TeacherConfig.Events.Substitute.Text, { 140, 200, 255 })
		services.ClassmateService.chat("Sub")
	end
	if pizza then
		services.Remotes.Announce:FireAllClients(string.format("PIZZA PARTY CLASS thanks to %s! Chill teacher + 2x Clout!", pizzaBy or "a legend"), { 255, 150, 60 })
		services.Remotes.Effect:FireAllClients("Pizza", { by = pizzaBy, now = true })
	end
	RoundService.tickClass(0, now)
	return round
end

-- Most suspicious student worth turning toward (stealth "drift").
local function focusTarget()
	local best, bestValue = nil, TeacherConfig.Suspicion.FocusAt
	for _, st in pairs(students) do
		if not st.detention and st.susp.value >= bestValue then
			best, bestValue = st, st.susp.value
		end
	end
	return best and { best.desk.x, best.desk.z } or nil
end

function RoundService.tickClass(dt, now)
	if state ~= "Class" or not round then
		return
	end
	local t = now - round.start
	local entry, index = Lesson.phaseAt(round.lesson, t)
	if index ~= round.phaseIndex then
		onPhase(entry, index, now)
	end
	updatePrincipal(t, now)
	services.TeacherService.update(dt, now, focusTarget())
	local observers = services.TeacherService.observers()
	local cfg = TeacherConfig
	round.tickCount += 1
	local clockText = Lesson.schoolClock(t, round.duration, GameConfig.SchoolClockStart, GameConfig.SchoolClockEnd)
	setWorkspace("Clock", clockText)
	local reseat = now - lastReseat > 1
	if reseat then
		lastReseat = now
	end
	for player, st in pairs(students) do
		if not player.Parent then
			students[player] = nil
		elseif st.detention then
			if reseat and st.detentionSeat then
				local humanoid = humanoidOf(player)
				if humanoid and humanoid.SeatPart ~= st.detentionSeat then
					seatPlayer(player, st.detentionSeat)
				end
			end
		else
			services.PhoneService.update(player, dt, now)
			local ds = services.PhoneService.detectState(player, now)
			if ds then
				local gain, instant = 0, 0
				for _, obs in ipairs(observers) do
					local sightGain, noiseGain, seenFlash = Detection.gain(obs, ds, cfg)
					gain += sightGain + noiseGain
					if seenFlash then
						local p = services.PhoneService.get(player)
						if p and st.flashToken ~= p.flashUntil then
							st.flashToken = p.flashUntil
							instant += cfg.Sight.FlashInstant
						end
					end
				end
				Detection.step(st.susp, gain, instant, dt, cfg.Suspicion)
				if services.PhoneService.isFullyUp(player) and dt > 0 then
					if round.phase == "Walk" then
						st.walkSecs += dt
						services.RewardService.track(player, "WalkPhoneSeconds", dt)
					elseif round.phase == "Board" then
						st.boardSecs += dt
						services.RewardService.track(player, "BoardPhoneSeconds", dt)
					end
				end
				if st.susp.value >= cfg.Suspicion.Catch then
					RoundService.handleCatch(player, now)
				elseif round.tickCount % 2 == 0 or dt == 0 then
					sendSuspicion(player, st, false)
				end
			end
			if reseat then
				local humanoid = humanoidOf(player)
				if humanoid and humanoid.SeatPart ~= st.desk.seat then
					seatPlayer(player, st.desk.seat)
				end
			end
		end
	end
	if services.World.detentionTimer then
		services.World.detentionTimer.Text = Format.clock(round.duration - t)
	end
	-- Nobody left who can still play (everyone left, or everyone is in detention with their
	-- one escape used): ring the bell now instead of making the hallway wait out the clock.
	local anyoneLeft = false
	for player, st in pairs(students) do
		if player.Parent and (not st.detention or not st.escapeUsed) then
			anyoneLeft = true
			break
		end
	end
	if t >= round.duration or not anyoneLeft then
		RoundService.endClass(now)
	end
end

function RoundService.endClass(now)
	if state ~= "Class" or not round then
		return
	end
	if round.quiz then
		gradeQuiz()
	end
	if round.phase == "FireDrill" then
		services.Remotes.Effect:FireAllClients("FireDrillEnd", {})
	end
	local rows = {}
	local legend, legendValue = nil, 0
	for player, st in pairs(students) do
		if player.Parent then
			services.PhoneService.forceDown(player)
			local bank = math.floor(st.pending)
			services.DataService.addClout(player, bank, true)
			services.DataService.addXP(player, ProgressionConfig.XPPerClass)
			local profile = services.DataService.getProfile(player)
			if profile then
				profile.Stats.Classes += 1
				profile.Stats.BestClass = math.max(profile.Stats.BestClass, bank)
				if not st.caught then
					profile.Stats.CleanClasses += 1
				end
			end
			if not st.caught then
				services.RewardService.track(player, "CleanClasses", 1)
			end
			services.RewardService.track(player, "BestClass", bank, true)
			services.LeaderboardService.submit(player)
			table.insert(rows, { name = player.DisplayName, clout = bank, caught = st.caught, userId = player.UserId })
			if not st.caught and bank > legendValue then
				legend, legendValue = player, bank
			end
			st.bank = bank
		end
	end
	table.sort(rows, function(a, b)
		return a.clout > b.clout
	end)
	for player, st in pairs(students) do
		if player.Parent then
			local stats = services.PhoneService.sessionStats(player) or {}
			services.Remotes.Results:FireClient(player, {
				clout = st.bank or 0,
				lost = st.lost,
				caught = st.caught,
				quiz = st.quiz,
				walkSecs = math.floor(st.walkSecs),
				stats = stats,
				pizza = round.pizza,
				legend = legend and legend.DisplayName or nil,
				top = { rows[1], rows[2], rows[3] },
			})
			services.DataService.sendProfile(player)
			task.spawn(services.DataService.save, player)
		end
	end
	if legend then
		services.ClassmateService.chat("Legend", legend.DisplayName, { 255, 210, 80 })
		services.Remotes.Announce:FireAllClients(string.format("%s is the PHONE LEGEND of the period: %s Clout without getting caught!", legend.DisplayName, Format.number(legendValue)), { 255, 210, 80 })
	end
	if round.principalIn then
		round.principalIn = false
		services.TeacherService.principalLeave()
	end
	services.TeacherService.idle(now)
	services.Remotes.Effect:FireAllClients("Bell", { final = true })
	setWorkspace("Phase", "")
	setWorkspace("Pizza", false)
	setWorkspace("Principal", false)
	round.ended = true
	setState("Results", GameConfig.ResultsSeconds, { top = rows })
end

function RoundService.toHallway()
	local spots = services.World.hallSpots
	local i = 0
	for player in pairs(students) do
		i += 1
		services.PhoneService.teardown(player)
		if decorModels[player] then
			decorModels[player]:Destroy()
			decorModels[player] = nil
		end
		if player.Parent then
			player:SetAttribute("PA_Status", "Hallway")
			player:SetAttribute("PA_Desk", 0)
			freePlayer(player, spots[((i - 1) % #spots) + 1])
			local profile = services.DataService.getProfile(player)
			player:SetAttribute("PA_Pet", profile ~= nil and profile.Settings.Pet == true)
			RoundService.refreshTag(player)
		end
	end
	students = {}
	services.PhoneService.clearAll()
	for _, desk in ipairs(services.World.desks) do
		desk.cardLabel.Text = ""
	end
	local door = services.World.door
	door.CFrame = services.World.doorOpen
	door.CanCollide = false
	round = nil
	local solo = #services.DataService.loadedPlayers() <= 1
	setState("Hallway", if solo then GameConfig.HallwaySecondsSolo else GameConfig.HallwaySeconds, {})
end

function RoundService.step(dt)
	local now = Clock.now()
	if state == "Hallway" then
		if now >= stateEndsAt then
			if not RoundService.beginBell() then
				stateEndsAt = now + 3
				setWorkspace("StateEnds", stateEndsAt)
			end
		end
	elseif state == "Bell" then
		if now >= stateEndsAt then
			RoundService.beginClass()
		end
	elseif state == "Class" then
		RoundService.tickClass(dt, now)
	elseif state == "Results" then
		if now >= stateEndsAt then
			RoundService.toHallway()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------------------------

local function onCharacter(player, character)
	task.defer(function()
		RoundService.refreshTag(player)
		local st = students[player]
		if st and character.Parent then
			seatPlayer(player, if st.detention then st.detentionSeat else st.desk.seat)
		end
	end)
end

function RoundService.onProfileLoaded(player)
	player:SetAttribute("PA_Status", "Hallway")
	local profile = services.DataService.getProfile(player)
	player:SetAttribute("PA_Pet", profile ~= nil and profile.Settings.Pet == true)
	RoundService.refreshTag(player)
	if state == "Class" then
		services.Remotes.Notify:FireClient(player, "Class is in session! Hang out in the hallway - you'll join the next class.", "info")
	end
end

function RoundService.onPlayerRemoving(player)
	local st = students[player]
	if st then
		-- Leaving mid-class still banks what you earned (minus nothing: you left, not caught).
		services.DataService.addClout(player, math.floor(st.pending), true)
		st.pending = 0
		students[player] = nil
		if st.desk and st.desk.cardLabel then
			st.desk.cardLabel.Text = ""
		end
	end
	if decorModels[player] then
		decorModels[player]:Destroy()
		decorModels[player] = nil
	end
end

function RoundService.sendStateTo(player)
	services.Remotes.RoundState:FireClient(player, state, { endsAt = stateEndsAt })
	local st = students[player]
	if st then
		sendSuspicion(player, st, true)
		services.PhoneService.sendState(player)
	end
	if round and round.phase then
		local cfg = TeacherConfig.Phases[round.phase]
		services.Remotes.PhaseChanged:FireClient(player, { phase = round.phase, label = cfg.Label, risk = cfg.Risk, color = cfg.Color, endsAt = workspace:GetAttribute("PA_PhaseEnds") })
	end
end

function RoundService.start()
	local remotes = services.Remotes
	setState("Hallway", GameConfig.HallwaySeconds, {})
	local door = services.World.door
	door.CFrame = services.World.doorOpen
	door.CanCollide = false
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	remotes.QuizAnswer.OnServerEvent:Connect(function(player, index)
		RoundService.answerQuiz(player, index)
	end)
	remotes.Bail.OnServerEvent:Connect(function(player)
		local ok, message = RoundService.bail(player)
		if not ok and message then
			remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	remotes.UseDetentionPass.OnServerEvent:Connect(function(player)
		local ok, message = RoundService.useDetentionPass(player)
		if not ok and message then
			remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	remotes.RequestState.OnServerEvent:Connect(function(player)
		services.DataService.sendProfile(player)
		RoundService.sendStateTo(player)
	end)
	task.spawn(function()
		local dt = 1 / GameConfig.TickRate
		while true do
			task.wait(dt)
			local ok, err = pcall(RoundService.step, dt)
			if not ok then
				warn("[PhonesAway] round step failed: " .. tostring(err))
			end
		end
	end)
end

return RoundService
