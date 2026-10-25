--[[
	PhoneService - each student's phone: up / down state, hide delay, the four phone apps
	(server-validated minigames), passive Clout, noise and the phone model on the desk.

	The client sends ONLY: Phone(up), PhoneApp(appId), PhoneAction(kind, value). Everything
	is validated here (types, NaN, rate limits, state) and rewards are capped per class
	(PhoneConfig.Caps). Clout earned in class goes to RoundService's "pending" pot and is
	banked when the bell rings (half is lost if the teacher catches you).

	Phone states: down -> raising (RaiseSeconds) -> up -> hiding (hide seconds) -> down
	Detection sees raising / up / hiding, and a short glow "linger" after it's down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local PhoneConfig = require(Shared.Config.PhoneConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Minigames = require(Shared.Minigames)
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
local AppIds = {}
for _, id in ipairs(PhoneConfig.AppOrder) do
	AppIds[id] = true
end

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
		app = "Feed",
		session = Minigames.newSession(PhoneConfig, rng, now),
		noise = 0,
		flash = false,
		confiscated = false,
		cooldownUntil = 0,
		lastToggle = 0,
		toggles = 0,
		actionTokens = PhoneConfig.ActionsPerSecond,
		actionAt = now,
		passiveCarry = 0,
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
		app = p.app,
		confiscated = p.confiscated,
		cooldownUntil = p.cooldownUntil,
		hide = p.stats.hide,
		view = Minigames.view(p.session),
		caps = { used = p.session.total, total = PhoneConfig.Caps.Total },
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

local function multiplier(player)
	return services.ShopService.cloutMultiplier(player) * services.RoundService.cloutMultiplier()
end

local function award(player, p, app, base, taps)
	if taps and taps > 0 then
		p.noise = Detection.addNoise(p.noise, taps, p.stats.noise, TeacherConfig.Hearing)
	end
	local granted = Minigames.grant(p.session, app, base, PhoneConfig.Caps)
	if granted <= 0 then
		return 0
	end
	local amount = granted * multiplier(player)
	services.RoundService.addPending(player, amount)
	return amount
end

-- Per-tick update from RoundService (state transitions, passive Clout, noise decay).
function PhoneService.update(player, dt, now)
	local p = phones[player]
	if not p then
		return
	end
	p.flash = false
	if p.flashUntil and now < p.flashUntil then
		p.flash = true
	end
	if p.state == "raising" and now - p.changedAt >= PhoneConfig.RaiseSeconds then
		setState(player, p, "up", now)
		PhoneService.sendState(player)
	elseif p.state == "hiding" and now >= (p.hideUntil or 0) then
		setState(player, p, "down", now)
		PhoneService.sendState(player)
	end
	p.noise = Detection.decayNoise(p.noise, dt, TeacherConfig.Hearing)
	if p.state == "up" then
		p.passiveCarry += PhoneConfig.PassivePerSecond * p.stats.rate * dt
		if p.passiveCarry >= 1 then
			local whole = math.floor(p.passiveCarry)
			p.passiveCarry -= whole
			award(player, p, "Passive", whole)
		end
	end
end

-- Minigame input. Returns ok, amount, info.
function PhoneService.action(player, kind, value, now)
	now = now or Clock.now()
	local p = phones[player]
	if not p or type(kind) ~= "string" or p.state ~= "up" or p.confiscated then
		return false, 0
	end
	-- Global action budget (token bucket).
	p.actionTokens = math.min(PhoneConfig.ActionsPerSecond, p.actionTokens + (now - p.actionAt) * PhoneConfig.ActionsPerSecond)
	p.actionAt = now
	if p.actionTokens < 1 then
		return false, 0, "rate"
	end
	p.actionTokens -= 1
	local s = p.session
	local ok, base, taps, info = false, 0, 0, nil
	local app
	if kind == "like" and p.app == "Feed" then
		app = "Feed"
		ok, base, taps = Minigames.like(s, value, PhoneConfig)
	elseif kind == "scroll" and p.app == "Feed" then
		app = "Feed"
		ok, taps = Minigames.scroll(s, now, PhoneConfig, rng)
	elseif kind == "text" and p.app == "Text" then
		app = "Text"
		ok, base, taps, info = Minigames.submitText(s, value, now, PhoneConfig, rng)
		if ok then
			services.RewardService.track(player, "Texts", 1)
		end
	elseif kind == "tap" and p.app == "Game" then
		app = "Game"
		ok, base, taps, info = Minigames.tap(s, value, now, PhoneConfig)
		if info == "Perfect" then
			services.RewardService.track(player, "Perfects", 1)
		end
	elseif kind == "selfie" and p.app == "Selfie" then
		app = "Selfie"
		ok, base, taps = Minigames.selfie(s, now, PhoneConfig)
		if ok then
			p.flashUntil = now + 0.35
			services.RoundService.selfieFlash(player)
			services.RewardService.track(player, "Selfies", 1)
			if p.model then
				local flash = p.model.PrimaryPart and p.model.PrimaryPart:FindFirstChild("Flash")
				if flash then
					flash.Enabled = true
					task.delay(0.3, function()
						if flash.Parent then
							flash.Enabled = false
						end
					end)
				end
			end
		end
	else
		return false, 0, "badkind"
	end
	local amount = 0
	if base and base > 0 then
		amount = award(player, p, app, base, taps)
	elseif taps and taps > 0 then
		p.noise = Detection.addNoise(p.noise, taps, p.stats.noise, TeacherConfig.Hearing)
	end
	services.Remotes.PhoneResult:FireClient(player, kind, { ok = ok, amount = amount, info = info, view = Minigames.view(s), capped = s.total >= PhoneConfig.Caps.Total })
	return ok, amount, info
end

function PhoneService.setApp(player, appId)
	local p = phones[player]
	if not p or type(appId) ~= "string" or not AppIds[appId] then
		return false
	end
	p.app = appId
	if appId == "Game" then
		Minigames.resetGame(p.session, Clock.now())
	elseif appId == "Text" then
		Minigames.nextText(p.session, PhoneConfig, rng, Clock.now())
	end
	PhoneService.sendState(player)
	return true
end

function PhoneService.sessionStats(player)
	local p = phones[player]
	return p and p.session.stats or nil
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
	remotes.PhoneApp.OnServerEvent:Connect(function(player, appId)
		PhoneService.setApp(player, appId)
	end)
	remotes.PhoneAction.OnServerEvent:Connect(function(player, kind, value)
		if type(value) == "string" and #value > 24 then
			return
		end
		if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
			value = nil
		end
		if type(value) ~= "string" and type(value) ~= "number" and value ~= nil then
			return
		end
		PhoneService.action(player, kind, value)
	end)
end

return PhoneService
