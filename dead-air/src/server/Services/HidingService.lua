--[[
	HidingService - lockers. Hiding reduces detection, it does not guarantee safety:

	* Hidden players are invisible to the Listener's sight checks.
	* If the Listener SAW you get in, it remembers that locker for a while.
	* Hiding while out of breath produces audible panting (PlayerService).
	* Searches check lockers near evidence; the chance of finding you depends on the above.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MonsterConfig = require(Shared.Config.MonsterConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local HidingService = {}

local services
local lockers = {}
local byId = {}
local occupantOf = {}
local sawEntryAt = {}
local lastExit = {}

function HidingService.init(registry)
	services = registry
end

local function animateDoor(locker, openAngle, duration)
	-- Rotate each door panel about the locker's hinge.
	for _, part in ipairs(locker.doorParts) do
		local offset = locker.doorOffsets[part]
		local goal = locker.hinge * CFrame.Angles(0, math.rad(openAngle), 0) * offset
		TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
	end
end

local function blink(locker)
	animateDoor(locker, -70, 0.18)
	task.delay(0.35, function()
		if locker.model.Parent then
			animateDoor(locker, 0, 0.2)
		end
	end)
end

local function updatePrompt(locker)
	local occupant = occupantOf[locker.id]
	locker.prompt.ActionText = if occupant then "Leave" else "Hide"
	locker.prompt.ObjectText = "Locker"
end

function HidingService.createFromMap(map)
	HidingService.clear()
	for _, locker in ipairs(map.lockers) do
		locker.doorOffsets = {}
		for _, part in ipairs(locker.doorParts) do
			locker.doorOffsets[part] = locker.hinge:ToObjectSpace(part.CFrame)
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = locker.promptPart
		locker.prompt = prompt
		updatePrompt(locker)
		prompt.Triggered:Connect(function(player)
			local state = services.PlayerService.get(player)
			if state and state.hiddenIn == locker.id then
				HidingService.exit(player)
			else
				HidingService.enter(player, locker)
			end
		end)
		table.insert(lockers, locker)
		byId[locker.id] = locker
	end
end

function HidingService.clear()
	table.clear(lockers)
	table.clear(byId)
	table.clear(occupantOf)
	table.clear(sawEntryAt)
end

function HidingService.enter(player, locker)
	local ps = services.PlayerService
	local state = ps.get(player)
	if not state or state.hiddenIn then
		return
	end
	if occupantOf[locker.id] then
		services.Remotes.Notify:FireClient(player, "Someone is already hiding in there", "warn")
		return
	end
	if lastExit[player] and os.clock() - lastExit[player] < 1 then
		return
	end
	if not ps:canInteract(player, locker.promptPart.Position) then
		return
	end
	local root = state.root
	-- Did the Listener watch this happen?
	if services.MonsterService.canSee(player) then
		sawEntryAt[locker.id] = os.clock()
	end
	occupantOf[locker.id] = player
	state.hiddenIn = locker.id
	state.sprintHeld = false
	root.Anchored = true
	state.character:PivotTo(locker.insideCFrame)
	state.lastPos = locker.insideCFrame.Position
	blink(locker)
	local crouched = state.crouch
	services.NoiseService:emit("LockerEnter", locker.promptPart.Position, {
		source = player,
		multiplier = if crouched then services.SoundConfig.CrouchInteractionMultiplier else 1,
	})
	if state.stamina < PlayerConfig.Stamina.PantingBelow then
		services.Remotes.Notify:FireClient(player, "You're out of breath - it can hear you", "warn")
	end
	updatePrompt(locker)
	ps.pushAttributes(state, true)
end

local function release(player, locker, makeNoise)
	local state = services.PlayerService.get(player)
	occupantOf[locker.id] = nil
	if state then
		state.hiddenIn = nil
		if state.root and state.root.Parent then
			state.character:PivotTo(locker.exitCFrame)
			state.root.Anchored = false
			state.lastPos = locker.exitCFrame.Position
		end
		services.PlayerService.pushAttributes(state, true)
	end
	lastExit[player] = os.clock()
	if makeNoise then
		blink(locker)
		services.NoiseService:emit("LockerExit", locker.promptPart.Position, {
			source = player,
			multiplier = if state and state.crouch then services.SoundConfig.CrouchInteractionMultiplier else 1,
		})
	end
	updatePrompt(locker)
end

function HidingService.exit(player)
	local state = services.PlayerService.get(player)
	if not state or not state.hiddenIn then
		return
	end
	local locker = byId[state.hiddenIn]
	if not locker then
		state.hiddenIn = nil
		return
	end
	if os.clock() - state.lastInteract < 0.3 then
		return
	end
	state.lastInteract = os.clock()
	release(player, locker, true)
end

function HidingService.forceExit(player)
	local state = services.PlayerService.get(player)
	if not state or not state.hiddenIn then
		return
	end
	local locker = byId[state.hiddenIn]
	if locker then
		release(player, locker, false)
	else
		state.hiddenIn = nil
	end
end

function HidingService.sawEntry(lockerId)
	local at = sawEntryAt[lockerId]
	return at ~= nil and os.clock() - at < MonsterConfig.HidingFind.SawEntryMemory
end

-- The Listener opens a locker. Returns the occupant if it finds them.
function HidingService.check(lockerId, rng)
	local locker = byId[lockerId]
	if not locker then
		return nil
	end
	animateDoor(locker, -100, 0.15)
	task.delay(MonsterConfig.Search.HidingCheckDuration, function()
		if locker.model.Parent then
			animateDoor(locker, 0, 0.35)
		end
	end)
	local occupant = occupantOf[lockerId]
	if not occupant then
		return nil
	end
	local state = services.PlayerService.get(occupant)
	local find = MonsterConfig.HidingFind
	local chance = find.BaseChance
	if HidingService.sawEntry(lockerId) then
		chance = find.SawEntryChance
	elseif state and state.stamina < PlayerConfig.Stamina.PantingBelow then
		chance = find.PantingChance
	end
	if rng:chance(chance) then
		release(occupant, locker, false)
		return occupant
	end
	services.Remotes.Notify:FireClient(occupant, "It looked right at you... and moved on", "info")
	return nil
end

function HidingService.spots()
	return lockers
end

function HidingService.get(lockerId)
	return byId[lockerId]
end

function HidingService.exitRemote(player)
	HidingService.exit(player)
end

return HidingService
