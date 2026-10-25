--[[
	PhoneService - each student's phone: up / down state, hide delay, the ANSWER SCANNER
	(the cheat), the smart watch, noise and the phone model on the desk.

	The client sends ONLY: Phone(up) and PhoneAction("snap" | "watch" | "peek"). Every timer
	runs here:
	  snap:    phone fully out -> aim (AimSeconds) -> shutter (noise + flash) -> scan
	           (Scanner seconds; hiding the phone cancels it) -> TestService.reveal(N)
	  watch:   glance (watch seconds, dim wrist glow) -> 1 answer -> long cooldown
	  peek:    Answer Key Peek token -> 1 answer (TestService.usePeek)
	There is no other path to an answer, so a modified client can't skip the risk.

	Phone states: down -> raising (RaiseSeconds) -> up -> hiding (hide seconds) -> down
	Detection sees raising / up / hiding, and a short glow "linger" after it's down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local PhoneConfig = require(Shared.Config.PhoneConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Detection = require(Shared.Detection)
local Economy = require(Shared.Economy)
local CrateRoll = require(Shared.CrateRoll)
local Props = require(Shared.Props)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local PhoneService = {}

local services
local phones = {} -- [player] = state
local rng = Rng.new(os.time() % 99991 + 3)

function PhoneService.init(registry)
	services = registry
end

function PhoneService.get(player)
	return phones[player]
end

local function statsFor(player)
	local profile = services.DataService.getProfile(player)
	local passes = services.ShopService.passesFor(player)
	return Economy.phoneStats(profile and profile.Upgrades, passes, UpgradeConfig), passes
end

function PhoneService.refreshStats(player)
	local p = phones[player]
	if p then
		p.stats = statsFor(player)
		PhoneService.rebuildModel(player)
	end
end

-- (Re)builds the phone model on the student's desk with their phone tier and skin.
function PhoneService.rebuildModel(player)
	local p = phones[player]
	if not p or not p.desk then
		return
	end
	if p.model then
		p.model:Destroy()
		p.model = nil
	end
	if p.confiscated then
		return
	end
	local profile = services.DataService.getProfile(player)
	local passes = services.ShopService.passesFor(player)
	local tier = if passes.ProPhone then UpgradeConfig.ProPhone else Economy.tierDef(UpgradeConfig, "Phone", profile and profile.Upgrades.Phone)
	local skin = profile and CrateRoll.find(CosmeticConfig, "Skin", profile.Equipped.Skin)
	local model = Props.phone(tier, if skin and not skin.Default then skin else nil, p.desk.phoneDown)
	model.Name = "Phone_" .. player.UserId
	model.Parent = services.World.props
	p.model = model
	PhoneService.placeModel(player)
end

function PhoneService.placeModel(player)
	local p = phones[player]
	if not p or not p.model or not p.desk then
		return
	end
	local out = p.state ~= "down"
	p.model:PivotTo(if out then p.desk.phoneUp else p.desk.phoneDown)
	Props.setPhoneGlow(p.model, out, p.stats.glow)
end

-- Called by RoundService when the student sits down for class.
function PhoneService.setup(player, desk)
	local now = Clock.now()
	phones[player] = {
		desk = desk,
		state = "down",
		changedAt = now,
		hiddenAt = -math.huge,
		scan = nil, -- { stage = "aim" | "process", untilT, nextBeep }
		watchUntil = nil,
		watchCooldownUntil = 0,
		snaps = 0,
		noise = 0,
		flash = false,
		confiscated = false,
		cooldownUntil = 0,
		lastToggle = 0,
		toggles = 0,
		actionTokens = PhoneConfig.ActionsPerSecond,
		actionAt = now,
		stats = (statsFor(player)),
		quizDistracted = false,
	}
	PhoneService.rebuildModel(player)
	PhoneService.sendState(player)
end

function PhoneService.teardown(player)
	local p = phones[player]
	if p and p.model then
		p.model:Destroy()
	end
	if p and p.confiscatedModel then
		p.confiscatedModel:Destroy()
	end
	phones[player] = nil
	if player.Parent then
		player:SetAttribute("PA_PhoneUp", false)
	end
end

function PhoneService.sendState(player)
	local p = phones[player]
	if not p or not player.Parent then
		return
	end
	services.Remotes.PhoneState:FireClient(player, {
		state = p.state,
		confiscated = p.confiscated,
		cooldownUntil = p.cooldownUntil,
		hide = p.stats.hide,
		answersPerSnap = p.stats.answers,
		scanSeconds = p.stats.scan,
		scan = p.scan and { stage = p.scan.stage, untilT = p.scan.untilT } or nil,
		watch = if p.stats.watch then { untilT = p.watchUntil, cooldownUntil = p.watchCooldownUntil, cooldown = p.stats.watch.cooldown, glance = p.stats.watch.glance } else nil,
		revealed = services.TestService.revealedList(player), -- only this player's own
		remaining = services.TestService.remaining(player),
	})
end

local function setState(player, p, state, now)
	p.state = state
	p.changedAt = now
	if state == "down" then
		p.hiddenAt = now
	end
	player:SetAttribute("PA_PhoneUp", state ~= "down")
	PhoneService.placeModel(player)
end

-- Phone up / down request from the client.
function PhoneService.request(player, up, now)
	now = now or Clock.now()
	local p = phones[player]
	if type(up) ~= "boolean" or not p then
		return false
	end
	-- Toggle spam protection: 6 phone-UP requests per second max. "Down" is never dropped:
	-- the client has already hidden its phone, so a dropped hide would leave it out on the
	-- server (and visible to the teacher) while the player thinks it's away.
	if up then
		if now - p.lastToggle > 1 then
			p.toggles = 0
			p.lastToggle = now
		end
		p.toggles += 1
		if p.toggles > 6 then
			return false
		end
	end
	if up then
		if p.confiscated or now < p.cooldownUntil or not services.RoundService.canUsePhone(player) then
			return false
		end
		if p.state == "down" or p.state == "hiding" then
			setState(player, p, "raising", now)
			if services.RoundService.isQuiz() then
				p.quizDistracted = true
			end
			return true
		end
	else
		if p.state == "raising" then
			-- Barely out: goes straight back.
			setState(player, p, "hiding", now)
			p.hideUntil = now + p.stats.hide * 0.5
			return true
		elseif p.state == "up" then
			setState(player, p, "hiding", now)
			p.hideUntil = now + p.stats.hide
			return true
		end
	end
	return false
end

-- Forces the phone down instantly (bell, detention).
function PhoneService.forceDown(player)
	local p = phones[player]
	if p and p.state ~= "down" then
		setState(player, p, "down", Clock.now())
		p.hiddenAt = -math.huge
		PhoneService.sendState(player)
	end
end

function PhoneService.confiscate(player)
	local p = phones[player]
	if not p then
		return
	end
	p.scan = nil
	p.watchUntil = nil
	PhoneService.forceDown(player)
	p.confiscated = true
	if p.model then
		-- Into the CONFISCATED basket on the teacher's desk.
		local basket = services.World.basket
		local offset = CFrame.new((rng:next() - 0.5) * 1.4, 0.45, (rng:next() - 0.5) * 0.8) * CFrame.Angles(math.rad(-80), rng:next() * 3, 0)
		p.model:PivotTo(basket.CFrame * offset)
		Props.setPhoneGlow(p.model, false, 1)
		p.model.Parent = services.World.props
		p.confiscatedModel = p.model
		p.model = nil
	end
	PhoneService.sendState(player)
end

function PhoneService.returnPhone(player, cooldown)
	local p = phones[player]
	if not p then
		return
	end
	p.confiscated = false
	p.cooldownUntil = Clock.now() + (cooldown or 0)
	if p.confiscatedModel then
		p.confiscatedModel:Destroy()
		p.confiscatedModel = nil
	end
	PhoneService.rebuildModel(player)
	PhoneService.sendState(player)
end

-- The student table for Detection.gain.
function PhoneService.detectState(player, now)
	local p = phones[player]
	if not p or not p.desk then
		return nil
	end
	return {
		x = p.desk.x,
		z = p.desk.z,
		phone = p.state,
		sinceHidden = now - p.hiddenAt,
		linger = p.stats.linger,
		glow = p.stats.glow,
		cover = p.stats.cover,
		noise = p.noise,
		flash = p.flash,
		flashMultiplier = PhoneConfig.Snap.FlashMultiplier,
		flashNoise = 0, -- the shutter's noise is added to p.noise (Silent Shutter applies)
		watch = p.watchUntil ~= nil and now < p.watchUntil,
		watchVisibility = PhoneConfig.Watch.Visibility,
	}
end

function PhoneService.isOut(player)
	local p = phones[player]
	return p ~= nil and p.state ~= "down"
end

function PhoneService.isFullyUp(player)
	local p = phones[player]
	return p ~= nil and p.state == "up"
end

local function result(player, kind, data)
	services.Remotes.PhoneResult:FireClient(player, kind, data)
end

-- Per-tick update from RoundService (state transitions, scanner / watch timers, noise).
function PhoneService.update(player, dt, now)
	local p = phones[player]
	if not p then
		return
	end
	p.flash = p.flashUntil ~= nil and now < p.flashUntil
	if p.state == "raising" and now - p.changedAt >= PhoneConfig.RaiseSeconds then
		setState(player, p, "up", now)
		PhoneService.sendState(player)
	elseif p.state == "hiding" and now >= (p.hideUntil or 0) then
		setState(player, p, "down", now)
		PhoneService.sendState(player)
	end
	p.noise = Detection.decayNoise(p.noise, dt, TeacherConfig.Hearing)
	local scan = p.scan
	if scan then
		if p.state ~= "up" or p.confiscated or not services.RoundService.canUsePhone(player) then
			-- The phone went away mid-scan: the screenshot is lost.
			p.scan = nil
			result(player, "scanFailed", {})
			PhoneService.sendState(player)
		elseif scan.stage == "aim" and now >= scan.untilT then
			-- Shutter: click + flash, then the scanner app starts processing.
			p.flashUntil = now + PhoneConfig.Snap.FlashSeconds
			p.flash = true
			p.noise = Detection.addNoise(p.noise, PhoneConfig.Snap.ShutterNoise / TeacherConfig.Hearing.NoisePerTap, p.stats.noise, TeacherConfig.Hearing)
			scan.stage = "process"
			scan.untilT = now + p.stats.scan
			scan.nextBeep = now + 1
			p.snaps += 1
			services.RoundService.onSnap(player)
			if p.model then
				local flash = p.model.PrimaryPart and p.model.PrimaryPart:FindFirstChild("Flash")
				if flash then
					flash.Enabled = true
					task.delay(PhoneConfig.Snap.FlashSeconds, function()
						if flash.Parent then
							flash.Enabled = false
						end
					end)
				end
			end
			result(player, "shutter", { untilT = scan.untilT })
			PhoneService.sendState(player)
		elseif scan.stage == "process" then
			if now >= scan.nextBeep then
				scan.nextBeep = now + 1
				p.noise = Detection.addNoise(p.noise, PhoneConfig.Snap.ScanTapNoise / TeacherConfig.Hearing.NoisePerTap, p.stats.noise, TeacherConfig.Hearing)
			end
			if now >= scan.untilT then
				p.scan = nil
				local answers = services.TestService.reveal(player, p.stats.answers, "snap")
				result(player, "reveal", { answers = answers, source = "snap", all = services.TestService.revealedList(player) })
				PhoneService.sendState(player)
			end
		end
	end
	if p.watchUntil and now >= p.watchUntil then
		p.watchUntil = nil
		if services.RoundService.canUsePhone(player) then
			local answers = services.TestService.reveal(player, 1, "watch")
			result(player, "reveal", { answers = answers, source = "watch", all = services.TestService.revealedList(player) })
		end
		PhoneService.sendState(player)
	end
end

-- Phone action from the client. Returns ok, reason.
function PhoneService.action(player, kind, now)
	now = now or Clock.now()
	local p = phones[player]
	if not p or type(kind) ~= "string" or p.confiscated or not services.RoundService.canUsePhone(player) then
		return false, "unavailable"
	end
	-- Global action budget (token bucket).
	p.actionTokens = math.min(PhoneConfig.ActionsPerSecond, p.actionTokens + (now - p.actionAt) * PhoneConfig.ActionsPerSecond)
	p.actionAt = now
	if p.actionTokens < 1 then
		return false, "rate"
	end
	p.actionTokens -= 1
	if kind == "snap" then
		if p.state ~= "up" then
			return false, "notup"
		elseif p.scan then
			return false, "busy"
		elseif services.TestService.remaining(player) <= 0 then
			return false, "nothing"
		end
		p.scan = { stage = "aim", untilT = now + PhoneConfig.Snap.AimSeconds }
		result(player, "aim", { untilT = p.scan.untilT })
		PhoneService.sendState(player)
		return true
	elseif kind == "watch" then
		local watch = p.stats.watch
		if not watch then
			return false, "nowatch"
		elseif p.watchUntil or now < p.watchCooldownUntil then
			return false, "cooldown"
		elseif services.TestService.remaining(player) <= 0 then
			return false, "nothing"
		end
		p.watchUntil = now + watch.glance
		p.watchCooldownUntil = now + watch.glance + watch.cooldown
		p.noise = Detection.addNoise(p.noise, PhoneConfig.Watch.Noise / TeacherConfig.Hearing.NoisePerTap, p.stats.noise, TeacherConfig.Hearing)
		result(player, "watch", { untilT = p.watchUntil })
		PhoneService.sendState(player)
		return true
	elseif kind == "peek" then
		local ok, message = services.TestService.usePeek(player)
		if not ok and message then
			services.Remotes.Notify:FireClient(player, message, "warn")
		end
		return ok, message
	end
	return false, "badkind"
end

function PhoneService.snapCount(player)
	local p = phones[player]
	return p and p.snaps or 0
end

function PhoneService.markQuizStart()
	for player, p in pairs(phones) do
		p.quizDistracted = p.state ~= "down"
		if not player.Parent then
			phones[player] = nil
		end
	end
end

function PhoneService.quizDistracted(player)
	local p = phones[player]
	return p ~= nil and p.quizDistracted
end

function PhoneService.onPlayerRemoving(player)
	PhoneService.teardown(player)
end

function PhoneService.clearAll()
	for player in pairs(phones) do
		PhoneService.teardown(player)
	end
	for _, child in ipairs(services.World.props:GetChildren()) do
		child:Destroy()
	end
end

function PhoneService.start()
	local remotes = services.Remotes
	remotes.Phone.OnServerEvent:Connect(function(player, up)
		PhoneService.request(player, up)
	end)
	remotes.PhoneAction.OnServerEvent:Connect(function(player, kind)
		if type(kind) ~= "string" or #kind > 12 then
			return
		end
		PhoneService.action(player, kind)
	end)
end

return PhoneService
