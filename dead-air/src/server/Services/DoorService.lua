--[[
	DoorService - door behaviour on top of the door models MapBuilder creates.

	* Ordinary doors swing open/closed via a ProximityPrompt. Opening or closing makes noise;
	  doing it crouched is quieter. Closing a metal door is louder.
	* Heavy (special-room) doors slide up and can be locked by reason: an item ("Keycard"),
	  "Power" or "Override". ObjectiveService unlocks them.
	* The Listener bursts through closed doors on its path (loud, fast).
	* Horror events may slam a door somewhere without alerting the monster.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Signal = require(Shared.Signal)

local DoorService = {}
DoorService.DoorUsed = Signal.new() -- (player, door, opened)
DoorService.LockedInteract = Signal.new() -- (player, door) attempt on a locked door

local doors = {}
local services

local SWING_TIME = 0.55
local SLIDE_TIME = 1.6
local LOCK_TEXT = {
	Keycard = "Locked - keycard required",
	Power = "No power",
	Override = "Sealed - exit override required",
}

function DoorService.init(registry)
	services = registry
end

local function setStatusLight(door)
	if door.statusLight then
		door.statusLight.Color = if door.locked then Color3.fromRGB(255, 60, 50) else Color3.fromRGB(80, 255, 120)
	end
end

local function updatePrompt(door)
	local prompt = door.prompt
	if not prompt then
		return
	end
	if door.locked then
		prompt.ActionText = LOCK_TEXT[door.lockReason] and "Use" or "Locked"
		prompt.ObjectText = LOCK_TEXT[door.lockReason] or "Locked"
		prompt.Enabled = true
	else
		prompt.ActionText = if door.open then "Close" else "Open"
		prompt.ObjectText = if door.heavy then "Security Door" else "Door"
		prompt.Enabled = not door.heavy or not door.open
	end
end

function DoorService.setOpen(door, open, opts)
	opts = opts or {}
	if door.open == open or door.moving then
		return false
	end
	door.open = open
	door.moving = true
	local duration = opts.duration or (if door.heavy then SLIDE_TIME else SWING_TIME)
	local goal = if open then door.openCFrame else door.closedCFrame
	local style = if opts.slam then Enum.EasingStyle.Quad else Enum.EasingStyle.Sine
	local tween = TweenService:Create(door.panel, TweenInfo.new(duration, style, Enum.EasingDirection.InOut), { CFrame = goal })
	tween:Play()
	-- Non-heavy doors stop blocking movement as soon as they start opening so players and the
	-- monster are not snagged mid-swing; they collide again once fully closed.
	if open and not door.heavy then
		door.panel.CanCollide = false
	end
	task.delay(duration, function()
		door.moving = false
		-- Closed doors block; an open heavy door is tucked into the ceiling.
		door.panel.CanCollide = not (door.open and door.heavy)
	end)
	updatePrompt(door)
	return true
end

local function noiseCategory(door, opened, slam)
	if door.heavy then
		return "HeavyDoor"
	elseif slam then
		return "DoorSlam"
	elseif opened then
		return "DoorOpen"
	end
	return if door.metal then "DoorSlam" else "DoorClose"
end

local function onTriggered(door, player)
	local ps = services.PlayerService
	if not ps:canInteract(player, door.promptPart.Position) then
		return
	end
	if door.locked then
		DoorService.LockedInteract:Fire(player, door)
		return
	end
	if door.heavy and door.open then
		return
	end
	local opening = not door.open
	if DoorService.setOpen(door, opening) then
		local crouched = ps:isCrouching(player)
		local category = noiseCategory(door, opening, false)
		services.NoiseService:emit(category, door.panel.Position, {
			source = player,
			multiplier = if crouched and not door.heavy then services.SoundConfig.CrouchInteractionMultiplier else 1,
		})
		DoorService.DoorUsed:Fire(player, door, opening)
	end
end

function DoorService.createFromMap(map)
	DoorService.clear()
	for i, door in ipairs(map.doors) do
		door.id = i
		door.open = false
		door.moving = false
		door.locked = false
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Door"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = door.promptPart
		door.prompt = prompt
		prompt.Triggered:Connect(function(player)
			onTriggered(door, player)
		end)
		updatePrompt(door)
		table.insert(doors, door)
	end
	for _, falseDoor in ipairs(map.falseDoors) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Door"
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = falseDoor.panel
		prompt.Triggered:Connect(function(player)
			if not services.PlayerService:canInteract(player, falseDoor.position) or falseDoor.used then
				return
			end
			falseDoor.used = true
			prompt.Enabled = false
			TweenService:Create(falseDoor.panel, TweenInfo.new(0.8), { CFrame = falseDoor.openCFrame }):Play()
			services.NoiseService:emit("DoorOpen", falseDoor.position, { source = player })
			-- Something knocks from the other side of solid concrete. Purely presentational.
			services.Remotes.HorrorEvent:FireClient(player, "Knocks", { position = falseDoor.position })
		end)
	end
end

function DoorService.clear()
	for _, door in ipairs(doors) do
		if door.prompt then
			door.prompt:Destroy()
		end
	end
	table.clear(doors)
end

function DoorService.all()
	return doors
end

function DoorService.lock(door, reason)
	door.locked = true
	door.lockReason = reason
	if door.open then
		DoorService.setOpen(door, false, { duration = 0.1 })
	end
	setStatusLight(door)
	updatePrompt(door)
end

function DoorService.unlock(door, openIt)
	door.locked = false
	door.lockReason = nil
	setStatusLight(door)
	updatePrompt(door)
	if openIt then
		DoorService.setOpen(door, true)
		services.NoiseService:emit("HeavyDoor", door.panel.Position, {})
	end
end

function DoorService.findSpecial(roomName)
	for _, door in ipairs(doors) do
		if door.special == roomName then
			return door
		end
	end
	return nil
end

-- Closed doors within `reach` of a position (used by the Listener to burst through).
function DoorService.closedNear(position, reach)
	local found = {}
	for _, door in ipairs(doors) do
		if not door.open and not door.moving then
			local delta = door.panel.Position - position
			if Vector3.new(delta.X, 0, delta.Z).Magnitude <= reach then
				table.insert(found, door)
			end
		end
	end
	return found
end

-- The monster forces a door. Locked doors spring back shut and stay locked afterwards.
function DoorService.monsterForce(door)
	if door.open or door.moving then
		return false
	end
	local wasLocked = door.locked
	local lockReason = door.lockReason
	DoorService.setOpen(door, true, { duration = if door.heavy then 0.6 else 0.22, slam = true })
	services.Remotes.MonsterCue:FireAllClients("DoorBurst", { position = door.panel.Position })
	if wasLocked then
		task.delay(3.5, function()
			if door.panel.Parent and door.open then
				DoorService.setOpen(door, false, { duration = 0.4 })
				door.locked = true
				door.lockReason = lockReason
				setStatusLight(door)
				updatePrompt(door)
			end
		end)
	end
	return true
end

-- Horror event: slam an open door near (but not on top of) a position.
function DoorService.slamRandom(position, minDistance, maxDistance, rng)
	local candidates = {}
	for _, door in ipairs(doors) do
		if door.open and not door.moving and not door.heavy then
			local d = (door.panel.Position - position).Magnitude
			if d >= minDistance and d <= maxDistance then
				table.insert(candidates, door)
			end
		end
	end
	local door = rng:pick(candidates)
	if door then
		DoorService.setOpen(door, false, { duration = 0.18, slam = true })
		services.Remotes.MonsterCue:FireAllClients("DoorSlam", { position = door.panel.Position })
	end
	return door
end

return DoorService
