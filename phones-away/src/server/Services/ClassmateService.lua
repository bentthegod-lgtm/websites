--[[
	ClassmateService - the social side of class:

	  * Paper airplane: throw one at any desk. When it lands she turns toward the noise for a
	    few seconds (cover for your friends!). If she SEES you throw it, you get suspicion.
	  * Pass a note: to the student right next to you. Both get a little Clout, it rustles.
	  * Teacher's Pet mode (opt-in, set in the hallway): you can report a classmate whose
	    phone is out for small points. Limited (3 per class, 20 s cooldown) and a false
	    report gives YOU the stink eye, so it stays a fun twist instead of ruining class.
	  * Class group chat: funny auto messages from invented classmate handles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local ChatLines = require(Shared.Config.ChatLines)
local Detection = require(Shared.Detection)
local Seating = require(Shared.Seating)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local ClassmateService = {}

local services
local rng = Rng.new(os.time() % 55555 + 17)
local perClass = {} -- [player] = { planes, notes, reports, lastPlane, lastNote, lastReport }
local lastChat = {}

function ClassmateService.init(registry)
	services = registry
end

local function stateFor(player)
	local s = perClass[player]
	if not s then
		s = { planes = 0, notes = 0, reports = 0, lastPlane = -math.huge, lastNote = -math.huge, lastReport = -math.huge }
		perClass[player] = s
	end
	return s
end

function ClassmateService.resetClass()
	perClass = {}
end

---------------------------------------------------------------------------------------------
-- Group chat
---------------------------------------------------------------------------------------------

function ClassmateService.chat(category, name, color)
	local list = ChatLines[category]
	if not list or #list == 0 then
		return
	end
	-- Don't spam the same category more than once every 2 s.
	local now = Clock.now()
	if lastChat[category] and now - lastChat[category] < 2 then
		return
	end
	lastChat[category] = now
	local line = list[rng:integer(1, #list)]
	local text = if string.find(line, "%s", 1, true) then string.format(line, name or "someone") else line
	local handle = ChatLines.Handles[rng:integer(1, #ChatLines.Handles)]
	services.Remotes.Chat:FireAllClients(handle, text, color)
	return handle, text
end

---------------------------------------------------------------------------------------------
-- Paper airplane
---------------------------------------------------------------------------------------------

function ClassmateService.throwPlane(player, deskIndex, now)
	now = now or Clock.now()
	local R = services.RoundService
	local cfg = GameConfig.Plane
	if type(deskIndex) ~= "number" or deskIndex ~= deskIndex or deskIndex % 1 ~= 0 then
		return false, "invalid"
	end
	local target = services.World.desks[deskIndex]
	local myDesk = R.deskOf(player)
	if not target or not myDesk or not R.canUsePhone(player) then
		return false, "notseated"
	end
	if target == myDesk then
		-- A zero-length flight (CFrame.lookAt(a, a)) gives every client a NaN plane.
		return false, "invalid"
	end
	local s = stateFor(player)
	if s.planes >= cfg.MaxPerClass then
		return false, "max"
	end
	if now - s.lastPlane < cfg.Cooldown then
		return false, "cooldown"
	end
	s.planes += 1
	s.lastPlane = now
	-- Did she see the throw?
	local seen = false
	for _, obs in ipairs(services.TeacherService.observers()) do
		if (obs.sight or 0) > 0.2 then
			local cone = Detection.cone(obs, myDesk.x, myDesk.z, TeacherConfig.Sight)
			if cone > 0.5 then
				seen = true
			end
		end
	end
	if seen then
		R.addSuspicion(player, cfg.ThrowSeenSuspicion)
	end
	services.Remotes.Effect:FireAllClients("Plane", { from = myDesk.index, to = deskIndex, thrower = player.UserId })
	local land = function()
		services.TeacherService.distract(target.x, target.z - 1.5, Clock.now())
		services.Remotes.Effect:FireAllClients("PlaneLand", { desk = deskIndex })
	end
	-- The airplane flies for ~0.8 s before she hears it land.
	if ClassmateService.instantPlanes then
		land()
	else
		task.delay(0.8, land)
	end
	R.addPending(player, cfg.Reward)
	services.RewardService.track(player, "Planes", 1)
	local profile = services.DataService.getProfile(player)
	if profile then
		profile.Stats.Planes += 1
	end
	ClassmateService.chat("Plane", player.DisplayName)
	return true, seen
end

---------------------------------------------------------------------------------------------
-- Pass a note
---------------------------------------------------------------------------------------------

function ClassmateService.passNote(player, targetUserId, now)
	now = now or Clock.now()
	local R = services.RoundService
	local cfg = GameConfig.Note
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return false, "invalid"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local a, b = R.deskOf(player), target and R.deskOf(target)
	if not target or target == player or not a or not b or not R.canUsePhone(player) or R.inDetention(target) then
		return false, "notseated"
	end
	if not Seating.adjacent(a, b) then
		return false, "toofar"
	end
	local s = stateFor(player)
	if s.notes >= cfg.MaxPerClass or now - s.lastNote < cfg.Cooldown then
		return false, "cooldown"
	end
	s.notes += 1
	s.lastNote = now
	R.addPending(player, cfg.Reward)
	R.addPending(target, cfg.Reward)
	R.addNoise(player, cfg.Noise)
	services.Remotes.Effect:FireAllClients("Note", { from = a.index, to = b.index })
	services.Remotes.Notify:FireClient(target, player.DisplayName .. " passed you a note: \"is she looking??\" (+" .. cfg.Reward .. " Clout)", "info")
	return true
end

---------------------------------------------------------------------------------------------
-- Teacher's Pet
---------------------------------------------------------------------------------------------

function ClassmateService.setPet(player, on)
	if type(on) ~= "boolean" then
		return false
	end
	local profile = services.DataService.getProfile(player)
	if not profile then
		return false
	end
	-- Mid-class switching would let you dodge a false-report penalty; it applies next class.
	profile.Settings.Pet = on
	services.DataService.markDirty(player)
	if not services.RoundService.inClass(player) then
		player:SetAttribute("PA_Pet", on)
		services.RoundService.refreshTag(player)
	end
	services.Remotes.Notify:FireClient(player, if on then "Teacher's Pet mode ON: report phone users for points (3 per class)." else "Teacher's Pet mode OFF.", "info")
	services.DataService.sendProfile(player)
	return true
end

function ClassmateService.report(player, targetUserId, now)
	now = now or Clock.now()
	local R = services.RoundService
	local cfg = GameConfig.Pet
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId then
		return false, "invalid"
	end
	if player:GetAttribute("PA_Pet") ~= true or not R.deskOf(player) or R.inDetention(player) then
		return false, "notpet"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player or not R.deskOf(target) or R.inDetention(target) then
		return false, "badtarget"
	end
	local s = stateFor(player)
	if s.reports >= cfg.MaxReports then
		return false, "max"
	end
	if now - s.lastReport < cfg.Cooldown then
		return false, "cooldown"
	end
	s.reports += 1
	s.lastReport = now
	if services.PhoneService.isOut(target) then
		R.addSuspicion(target, cfg.SuspicionAdded)
		R.addPending(player, cfg.Reward)
		services.Remotes.Notify:FireClient(target, player.DisplayName .. " (Teacher's Pet) told on you! She's suspicious...", "warn")
		services.Remotes.Notify:FireClient(player, "Reported! +" .. cfg.Reward .. " Clout", "good")
		local profile = services.DataService.getProfile(player)
		if profile then
			profile.Stats.Reports += 1
		end
		ClassmateService.chat("Report", player.DisplayName)
		return true, "hit"
	end
	R.addSuspicion(player, cfg.FalseReportPenalty)
	services.Remotes.Notify:FireClient(player, "Their phone was away! Ms. B gives YOU the stink eye.", "warn")
	return true, "false"
end

function ClassmateService.onPlayerRemoving(player)
	perClass[player] = nil
end

function ClassmateService.start()
	local remotes = services.Remotes
	remotes.ThrowPlane.OnServerEvent:Connect(function(player, deskIndex)
		ClassmateService.throwPlane(player, deskIndex)
	end)
	remotes.PassNote.OnServerEvent:Connect(function(player, userId)
		ClassmateService.passNote(player, userId)
	end)
	remotes.Report.OnServerEvent:Connect(function(player, userId)
		ClassmateService.report(player, userId)
	end)
	remotes.SetPet.OnServerEvent:Connect(function(player, on)
		local s = stateFor(player)
		local now = Clock.now()
		if s.lastPet and now - s.lastPet < 1 then
			return
		end
		s.lastPet = now
		ClassmateService.setPet(player, on)
	end)
end

return ClassmateService
