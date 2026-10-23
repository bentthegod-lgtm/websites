--[[
	PlayerService - per-player survival state, owned by the server.

	* Movement noise is derived from the character's SERVER-OBSERVED position each tick
	  (distance travelled, vertical motion), never from client claims. Sprinting, crouching
	  and stamina are enforced here (WalkSpeed is set by the server).
	* Footsteps, jumps and landings emit noise with surface modifiers (raycast floor).
	* Flashlight battery, panting while hidden, black-box static.
	* Downed / revive / death / escape, and validation for every client request.

	Statuses: Lobby, Alive, Downed, Dead, Escaped, Spectating (joined mid-run).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local PlayerConfig = require(Shared.Config.PlayerConfig)
local SoundConfig = require(Shared.Config.SoundConfig)
local SoundMath = require(Shared.SoundMath)
local Signal = require(Shared.Signal)
local FlashlightModel = require(Shared.FlashlightModel)

local PlayerService = {}
PlayerService.StatusChanged = Signal.new() -- (player, status, previous)
PlayerService.Removed = Signal.new() -- (player)
PlayerService.Revived = Signal.new() -- (reviver, revived)

local services
local states = {}

local SURFACE_BY_MATERIAL = {
	[Enum.Material.DiamondPlate] = "Metal",
	[Enum.Material.Metal] = "Metal",
	[Enum.Material.CorrodedMetal] = "Metal",
	[Enum.Material.Fabric] = "Carpet",
	[Enum.Material.Concrete] = "Concrete",
	[Enum.Material.Slate] = "Concrete",
}

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude

function PlayerService.init(registry)
	services = registry
end

local function setStatus(state, status)
	local previous = state.status
	if previous == status then
		return
	end
	state.status = status
	state.player:SetAttribute("DA_Status", status)
	PlayerService.StatusChanged:Fire(state.player, status, previous)
end

function PlayerService.get(player)
	return states[player]
end

function PlayerService.all()
	local list = {}
	for _, state in pairs(states) do
		table.insert(list, state)
	end
	return list
end

function PlayerService.inRound()
	local list = {}
	for _, state in pairs(states) do
		if state.inRound then
			table.insert(list, state)
		end
	end
	return list
end

function PlayerService.countStatus(status)
	local n = 0
	for _, state in pairs(states) do
		if state.inRound and state.status == status then
			n += 1
		end
	end
	return n
end

function PlayerService:isCrouching(player)
	local state = states[player]
	return state ~= nil and state.crouch
end

function PlayerService.isAlive(player)
	local state = states[player]
	return state ~= nil and state.inRound and state.status == "Alive"
end

-- Shared validation for prompt-driven interactions.
function PlayerService:canInteract(player, position, opts)
	local state = states[player]
	if not state or not state.inRound or state.status ~= "Alive" then
		return false
	end
	if state.hiddenIn and not (opts and opts.allowHidden) then
		return false
	end
	local root = state.root
	if not root or not root.Parent then
		return false
	end
	if position and (root.Position - position).Magnitude > PlayerConfig.Interaction.MaxDistance + 2 then
		return false
	end
	local now = os.clock()
	if now - state.lastInteract < PlayerConfig.Interaction.MinInterval then
		return false
	end
	state.lastInteract = now
	return true
end

---------------------------------------------------------------------------------------------
-- Character setup
---------------------------------------------------------------------------------------------

local function flashlightColor(player)
	local profile = services.DataService.getProfile(player)
	return services.DataService.cosmeticColor(profile and profile.Equipped)
end

local function setupCharacter(state, character)
	state.character = character
	state.humanoid = character:WaitForChild("Humanoid", 10)
	state.root = character:WaitForChild("HumanoidRootPart", 10)
	local head = character:WaitForChild("Head", 10)
	if not state.humanoid or not state.root then
		return false
	end
	local humanoid = state.humanoid
	humanoid.WalkSpeed = PlayerConfig.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 34
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	-- Damage only comes from the Listener (via this service), never from the environment.
	humanoid.MaxHealth = 100
	humanoid.Health = 100

	-- A real flashlight held at the chest, pointing where the character faces. Other players
	-- see this one; the owner sees a first-person viewmodel instead (EffectsController).
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or head
	if torso then
		local model, lens = FlashlightModel.build("DA_FlashlightModel")
		model:PivotTo(torso.CFrame * CFrame.new(0.65, 0.25, -0.75))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = model.PrimaryPart
		weld.Parent = model.PrimaryPart
		model.Parent = character
		local light = Instance.new("SpotLight")
		light.Name = "DA_Flashlight"
		light.Face = Enum.NormalId.Front
		light.Range = PlayerConfig.Flashlight.Range
		light.Angle = PlayerConfig.Flashlight.Angle
		light.Brightness = PlayerConfig.Flashlight.Brightness
		light.Shadows = true
		light.Color = flashlightColor(state.player)
		light.Enabled = false
		light.Parent = lens
		state.flashlight = light
		state.flashlightLens = lens
	end
	humanoid.Died:Connect(function()
		if state.character == character and state.status == "Alive" then
			-- Fell out of the world or some other unexpected death.
			PlayerService.kill(state.player, "Unknown")
		end
	end)
	state.lastPos = state.root.Position
	state.stepAccum = 0
	state.airborne = false
	floorParams.FilterDescendantsInstances = {}
	return true
end

function PlayerService.spawnAt(player, cframe, status)
	local state = states[player]
	if not state then
		return false
	end
	player:LoadCharacter()
	local character = player.Character
	if not character or not setupCharacter(state, character) then
		warn("[DeadAir] Failed to spawn character for " .. player.Name)
		return false
	end
	character:PivotTo(cframe)
	state.lastPos = cframe.Position
	setStatus(state, status)
	return true
end

function PlayerService.prepareForRound(player, cframe)
	local state = states[player]
	if not state then
		return false
	end
	state.inRound = true
	state.stamina = PlayerConfig.Stamina.Max
	state.exhausted = false
	state.battery = PlayerConfig.Flashlight.MaxBattery
	state.flashlightOn = false
	state.crouch = false
	state.sprintHeld = false
	state.hiddenIn = nil
	state.roundStats = { items = 0, revives = 0, objectives = 0, lore = 0, startedAt = os.clock() }
	state.aliveSince = os.clock()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMaxZoomDistance = 0.5
	local ok = PlayerService.spawnAt(player, cframe, "Alive")
	if not ok then
		-- Failed spawn: retry once, then leave them spectating.
		task.wait(1)
		ok = PlayerService.spawnAt(player, cframe, "Alive")
		if not ok then
			state.inRound = false
			setStatus(state, "Spectating")
		end
	end
	PlayerService.pushAttributes(state, true)
	return ok
end

function PlayerService.sendToLobby(player, cframe)
	local state = states[player]
	if not state then
		return
	end
	state.inRound = false
	state.hiddenIn = nil
	state.flashlightOn = false
	if state.revivePrompt then
		state.revivePrompt:Destroy()
		state.revivePrompt = nil
	end
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 12
	PlayerService.spawnAt(player, cframe, "Lobby")
	if state.humanoid then
		state.humanoid.WalkSpeed = 14
	end
end

---------------------------------------------------------------------------------------------
-- Damage, downed, revive, escape
---------------------------------------------------------------------------------------------

function PlayerService.kill(player, cause)
	local state = states[player]
	if not state or not state.inRound then
		return
	end
	if state.status ~= "Alive" and state.status ~= "Downed" then
		return
	end
	if state.revivePrompt then
		state.revivePrompt:Destroy()
		state.revivePrompt = nil
	end
	if state.hiddenIn then
		services.HidingService.forceExit(player)
	end
	local position = state.root and state.root.Position
	if position then
		services.ItemService.dropAll(player, position)
	end
	state.flashlightOn = false
	state.deathCause = cause
	setStatus(state, "Dead")
	if state.humanoid and state.humanoid.Health > 0 then
		state.humanoid.Health = 0
	end
	PlayerService.pushAttributes(state, true)
end

function PlayerService.down(player)
	local state = states[player]
	if not state or state.status ~= "Alive" then
		return
	end
	local position = state.root and state.root.Position
	if position then
		services.ItemService.dropAll(player, position)
	end
	state.flashlightOn = false
	state.sprintHeld = false
	state.downedAt = os.clock()
	state.bleedOutAt = os.clock() + services.RoundService.difficulty().BleedOutTime
	setStatus(state, "Downed")
	if state.humanoid then
		state.humanoid.WalkSpeed = PlayerConfig.DownedSpeed
		state.humanoid.JumpPower = 0
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Revive"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = PlayerConfig.Downed.ReviveHoldTime
	prompt.MaxActivationDistance = PlayerConfig.Downed.ReviveDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = state.root
	state.revivePrompt = prompt
	local holdStart = {}
	prompt.PromptButtonHoldBegan:Connect(function(reviver)
		holdStart[reviver] = os.clock()
		if reviver ~= player and PlayerService.isAlive(reviver) then
			services.NoiseService:emit("Revive", state.root.Position, { source = reviver })
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(reviver)
		holdStart[reviver] = nil
	end)
	prompt.Triggered:Connect(function(reviver)
		local began = holdStart[reviver]
		holdStart[reviver] = nil
		if reviver == player or not began then
			return
		end
		-- Enforce the hold time server-side.
		if os.clock() - began < PlayerConfig.Downed.ReviveHoldTime * 0.85 then
			return
		end
		if state.status ~= "Downed" then
			return
		end
		if not PlayerService:canInteract(reviver, state.root.Position) then
			return
		end
		PlayerService.revive(player, reviver)
	end)
	PlayerService.pushAttributes(state, true)
	services.Remotes.Notify:FireAllClients(player.DisplayName .. " is down", "danger")
end

function PlayerService.revive(player, reviver)
	local state = states[player]
	if not state or state.status ~= "Downed" then
		return
	end
	if state.revivePrompt then
		state.revivePrompt:Destroy()
		state.revivePrompt = nil
	end
	state.stamina = 30
	state.exhausted = false
	setStatus(state, "Alive")
	if state.humanoid then
		state.humanoid.WalkSpeed = PlayerConfig.WalkSpeed
		state.humanoid.JumpPower = 34
	end
	local rs = states[reviver]
	if rs and rs.roundStats then
		rs.roundStats.revives += 1
	end
	PlayerService.Revived:Fire(reviver, player)
	services.Remotes.Notify:FireAllClients(reviver.DisplayName .. " revived " .. player.DisplayName, "info")
	PlayerService.pushAttributes(state, true)
end

-- Called by the Listener's attack. Returns "Downed", "Dead" or nil.
function PlayerService.catch(player)
	local state = states[player]
	if not state or state.status ~= "Alive" then
		return nil
	end
	if state.hiddenIn then
		services.HidingService.forceExit(player)
	end
	local othersStanding = 0
	for other, s in pairs(states) do
		if other ~= player and s.inRound and s.status == "Alive" then
			othersStanding += 1
		end
	end
	if services.RoundService.difficulty().DownedEnabled and othersStanding > 0 then
		PlayerService.down(player)
		return "Downed"
	end
	PlayerService.kill(player, "Listener")
	return "Dead"
end

function PlayerService.markEscaped(player)
	local state = states[player]
	if not state or state.status ~= "Alive" then
		return false
	end
	services.ItemService.markEscapedWithItems(player)
	setStatus(state, "Escaped")
	state.flashlightOn = false
	if state.character then
		state.character:Destroy()
		state.character = nil
		state.root = nil
		state.humanoid = nil
	end
	PlayerService.pushAttributes(state, true)
	return true
end

-- Joined while a run is in progress: watch from the lobby until the next run.
function PlayerService.setSpectating(player)
	local state = states[player]
	if state then
		state.inRound = false
		setStatus(state, "Spectating")
	end
end

---------------------------------------------------------------------------------------------
-- Attributes (replicated to all clients: HUD, teammate list, spectating)
---------------------------------------------------------------------------------------------

function PlayerService.pushAttributes(state, force)
	local player = state.player
	local stamina = math.floor(state.stamina + 0.5)
	local battery = math.floor(state.battery + 0.5)
	if force or player:GetAttribute("DA_Stamina") ~= stamina then
		player:SetAttribute("DA_Stamina", stamina)
	end
	if force or player:GetAttribute("DA_Battery") ~= battery then
		player:SetAttribute("DA_Battery", battery)
	end
	player:SetAttribute("DA_Exhausted", state.exhausted)
	player:SetAttribute("DA_Crouch", state.crouch)
	player:SetAttribute("DA_Sprinting", state.sprinting == true)
	player:SetAttribute("DA_Hidden", state.hiddenIn ~= nil)
	player:SetAttribute("DA_Flashlight", state.flashlightOn)
	if state.bleedOutAt and state.status == "Downed" then
		player:SetAttribute("DA_BleedOut", math.max(0, math.floor(state.bleedOutAt - os.clock())))
	else
		player:SetAttribute("DA_BleedOut", nil)
	end
	if state.flashlight then
		local lit = state.flashlightOn and state.status == "Alive" and state.hiddenIn == nil
		if state.flashlight.Enabled ~= lit then
			state.flashlight.Enabled = lit
			FlashlightModel.setLens(state.flashlightLens, lit, state.flashlight.Color)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Movement / noise tick
---------------------------------------------------------------------------------------------

local function surfaceUnder(state)
	floorParams.FilterDescendantsInstances = { state.character }
	local result = Workspace:Raycast(state.root.Position, Vector3.new(0, -7, 0), floorParams)
	if not result then
		return "Default"
	end
	return result.Instance:GetAttribute("Surface") or SURFACE_BY_MATERIAL[result.Material] or "Default"
end

local function tickPlayer(state, dt, now)
	local root = state.root
	local humanoid = state.humanoid
	if not root or not root.Parent or not humanoid then
		return
	end
	local stamina = PlayerConfig.Stamina

	-- Flashlight battery
	if state.flashlightOn then
		state.battery = math.max(0, state.battery - PlayerConfig.Flashlight.DrainPerSecond * dt)
		if state.battery <= 0 then
			state.flashlightOn = false
			services.Remotes.Notify:FireClient(state.player, "Flashlight battery dead", "warn")
		end
	end

	if state.status == "Downed" then
		if state.bleedOutAt and now >= state.bleedOutAt then
			PlayerService.kill(state.player, "BledOut")
		end
		PlayerService.pushAttributes(state)
		return
	end
	if state.status ~= "Alive" then
		return
	end

	local position = root.Position
	if state.hiddenIn then
		-- Recover stamina while hidden, but panting is audible.
		state.sprinting = false
		state.stamina = math.min(stamina.Max, state.stamina + stamina.RegenPerSecond * dt)
		if state.stamina < stamina.PantingBelow and now - (state.lastBreath or 0) > 1.6 then
			state.lastBreath = now
			services.NoiseService:emit("Breathing", position, { source = state.player })
		end
		state.lastPos = position
		PlayerService.pushAttributes(state)
		return
	end

	local delta = position - (state.lastPos or position)
	state.lastPos = position
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if horizontal > 30 then
		-- Teleport (spawn, hiding exit) - not movement.
		state.stepAccum = 0
		return
	end
	local speed = horizontal / dt
	local vy = delta.Y / dt

	-- Sprint / stamina (server decides the actual speed).
	local moving = speed > 2
	local canSprint = state.sprintHeld and not state.crouch and not state.exhausted and state.stamina > 0
	if canSprint and moving then
		state.sprinting = true
		state.stamina = math.max(0, state.stamina - stamina.SprintDrainPerSecond * dt)
		state.lastSprintAt = now
		if state.stamina <= 0 then
			state.exhausted = true
		end
	else
		state.sprinting = false
		if now - (state.lastSprintAt or 0) > stamina.RegenDelay then
			state.stamina = math.min(stamina.Max, state.stamina + stamina.RegenPerSecond * dt)
		end
	end
	if state.exhausted and state.stamina >= stamina.ExhaustedRecoverAt then
		state.exhausted = false
	end
	local targetSpeed = PlayerConfig.WalkSpeed
	if state.crouch then
		-- Crouch alone = silent creep; crouch + sprint key = quicker, audible crouch-run.
		targetSpeed = if state.sprintHeld then PlayerConfig.CrouchRunSpeed else PlayerConfig.CrouchSpeed
	elseif state.sprinting or (canSprint and state.sprintHeld) then
		targetSpeed = PlayerConfig.SprintSpeed
	end
	if humanoid.WalkSpeed ~= targetSpeed then
		humanoid.WalkSpeed = targetSpeed
	end

	-- Vertical motion: jumps and landings.
	local airborne = math.abs(vy) > 3
	if airborne then
		if not state.airborne then
			state.airborne = true
			state.peakY = position.Y
			if vy > 8 then
				services.NoiseService:emit("Jump", position, { source = state.player, multiplier = if state.crouch then 0.6 else 1 })
			end
		end
		state.peakY = math.max(state.peakY or position.Y, position.Y)
	elseif state.airborne then
		state.airborne = false
		local fall = (state.peakY or position.Y) - position.Y
		if fall >= SoundConfig.HardLandHeight then
			services.NoiseService:emit("LandHard", position, { source = state.player })
		elseif fall >= SoundConfig.SoftLandHeight then
			services.NoiseService:emit("LandSoft", position, { source = state.player, multiplier = if state.crouch then 0.6 else 1 })
		end
		state.peakY = nil
	end

	-- Footsteps.
	local gait = SoundMath.gait(speed, PlayerConfig, state.crouch)
	if gait and not airborne then
		state.stepAccum = (state.stepAccum or 0) + horizontal
		local stride = SoundConfig.Stride[gait]
		if state.stepAccum >= stride then
			state.stepAccum -= stride
			local surface = surfaceUnder(state)
			local category = "Footstep" .. gait
			local surfaceMult = SoundConfig.Surfaces[surface] or SoundConfig.Surfaces.Default
			-- Moving faster than the server allows (exploit or lag) is extra loud.
			local overspeed = if speed > PlayerConfig.SprintSpeed + 4 then 1.4 else 1
			services.NoiseService:emit(category, position, { source = state.player, surfaceMultiplier = surfaceMult, multiplier = overspeed })
		end
	else
		state.stepAccum = 0
	end

	-- Carrying the black box: intermittent static.
	if services.ItemService.has(state.player, "BlackBox") > 0 and now - (state.lastStatic or 0) > 4.5 then
		state.lastStatic = now + math.random() * 1.5
		services.NoiseService:emit("BlackBoxStatic", position, { source = state.player })
	end

	PlayerService.pushAttributes(state)
end

---------------------------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------------------------

local function connectRemotes(remotes)
	remotes.SetMovement.OnServerEvent:Connect(function(player, sprintHeld, crouch)
		local state = states[player]
		if not state or type(sprintHeld) ~= "boolean" or type(crouch) ~= "boolean" then
			return
		end
		local now = os.clock()
		if now - (state.lastMovementMsg or 0) < 0.03 then
			return
		end
		state.lastMovementMsg = now
		if state.status ~= "Alive" then
			state.sprintHeld = false
			return
		end
		state.sprintHeld = sprintHeld
		state.crouch = crouch
		PlayerService.pushAttributes(state)
	end)

	remotes.ToggleFlashlight.OnServerEvent:Connect(function(player)
		local state = states[player]
		if not state or state.status ~= "Alive" then
			return
		end
		local now = os.clock()
		if now - (state.lastFlashToggle or 0) < 0.25 then
			return
		end
		state.lastFlashToggle = now
		if not state.flashlightOn and state.battery <= 0 then
			services.Remotes.Notify:FireClient(player, "No battery", "warn")
			return
		end
		state.flashlightOn = not state.flashlightOn
		PlayerService.pushAttributes(state, true)
	end)
end

function PlayerService.start()
	connectRemotes(services.Remotes)

	local function onPlayerAdded(player)
		states[player] = {
			player = player,
			status = "Lobby",
			inRound = false,
			stamina = PlayerConfig.Stamina.Max,
			battery = PlayerConfig.Flashlight.MaxBattery,
			exhausted = false,
			crouch = false,
			sprintHeld = false,
			flashlightOn = false,
			lastInteract = 0,
		}
		player:SetAttribute("DA_Status", "Lobby")
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			if state.inRound and state.root and state.root.Parent then
				services.ItemService.dropAll(player, state.root.Position)
			end
			if state.hiddenIn then
				services.HidingService.forceExit(player)
			end
		end
		states[player] = nil
		PlayerService.Removed:Fire(player)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		local tick = PlayerConfig.MovementTick
		if accumulator < tick then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		for _, state in pairs(states) do
			if state.inRound then
				local ok, err = pcall(tickPlayer, state, step, now)
				if not ok then
					warn("[DeadAir] Player tick error: " .. tostring(err))
				end
			end
		end
	end)
end

function PlayerService.setFlashlightColor(player, color)
	local state = states[player]
	if state and state.flashlight then
		state.flashlight.Color = color
		if state.flashlight.Enabled then
			FlashlightModel.setLens(state.flashlightLens, true, color)
		end
	end
end

return PlayerService
