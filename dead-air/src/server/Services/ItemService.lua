--[[
	ItemService - pickups, inventories, dropping and throwing.

	* Items exist only on the server; clients receive their own inventory list.
	* Dropping an item makes noise (metal objects are loud). Crouch to set it down gently.
	* Throwables (bottles, tin cans, alarm clocks): the server simulates the arc and the
	  impact becomes a noise event there - a distraction that pulls the Listener away.
	  Bottles shatter; cans can be reused; alarm clocks keep ringing until picked up.
	* Dead/disconnected players drop everything where they fell, so the run stays completable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local ItemConfig = require(Shared.Config.ItemConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local LoreConfig = require(Shared.Config.LoreConfig)
local Signal = require(Shared.Signal)
local ItemModels = require(Shared.ItemModels)

local ItemService = {}
ItemService.PickedUp = Signal.new() -- (player, kind)
ItemService.LoreRead = Signal.new() -- (player, noteId)

local services
local inventories = {}
local pickups = {}
local folder
local lastThrow = {}
local lastDrop = {}

local rgb = Color3.fromRGB

function ItemService.init(registry)
	services = registry
end

function ItemService.setFolder(newFolder)
	folder = newFolder
end

function ItemService.clear()
	for _, pickup in ipairs(pickups) do
		if pickup.model then
			pickup.model:Destroy()
		end
	end
	table.clear(pickups)
	for player in pairs(inventories) do
		inventories[player] = {}
		ItemService.sendInventory(player)
	end
end

function ItemService.inventory(player)
	local inv = inventories[player]
	if not inv then
		inv = {}
		inventories[player] = inv
	end
	return inv
end

function ItemService.sendInventory(player)
	if player.Parent then
		services.Remotes.Inventory:FireClient(player, ItemService.inventory(player))
	end
end

function ItemService.has(player, kind)
	local n = 0
	for _, k in ipairs(ItemService.inventory(player)) do
		if k == kind then
			n += 1
		end
	end
	return n
end

function ItemService.give(player, kind)
	local inv = ItemService.inventory(player)
	if #inv >= PlayerConfig.Inventory.Capacity then
		return false
	end
	table.insert(inv, kind)
	ItemService.sendInventory(player)
	return true
end

function ItemService.take(player, kind, count)
	count = count or 1
	if ItemService.has(player, kind) < count then
		return false
	end
	local inv = ItemService.inventory(player)
	for _ = 1, count do
		table.remove(inv, table.find(inv, kind))
	end
	ItemService.sendInventory(player)
	return true
end

---------------------------------------------------------------------------------------------
-- Pickup models
---------------------------------------------------------------------------------------------

local function buildVisual(kind, cframe)
	return ItemModels.build(kind, cframe)
end

local function removePickup(pickup)
	local i = table.find(pickups, pickup)
	if i then
		table.remove(pickups, i)
	end
	if pickup.model then
		pickup.model:Destroy()
		pickup.model = nil
	end
end

function ItemService.spawn(kind, position)
	local def = ItemConfig[kind]
	if not def then
		warn("[DeadAir] Unknown item " .. tostring(kind))
		return nil
	end
	local part = buildVisual(kind, CFrame.new(position + Vector3.new(0, def.Size[2] / 2, 0)))
	part:SetAttribute("Item", kind)
	part.Parent = folder or Workspace

	local pickup = { kind = kind, model = part, position = part.Position }
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = def.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	pickup.prompt = prompt
	prompt.Triggered:Connect(function(player)
		if not pickup.model then
			return
		end
		-- Items inside a cabinet can only be taken while its doors are open.
		if pickup.container and not pickup.container.open then
			return
		end
		if not services.PlayerService:canInteract(player, part.Position) then
			return
		end
		local state = services.PlayerService.get(player)
		if def.Consumable then
			-- Battery: charge the flashlight now.
			state.battery = math.min(PlayerConfig.Flashlight.MaxBattery, state.battery + PlayerConfig.Flashlight.BatteryPickupAmount)
			services.PlayerService.pushAttributes(state, true)
			services.Remotes.Notify:FireClient(player, "Flashlight recharged", "info")
		elseif not ItemService.give(player, kind) then
			services.Remotes.Notify:FireClient(player, "Your hands are full - drop something first", "warn")
			return
		else
			services.Remotes.Notify:FireClient(player, "Picked up " .. def.DisplayName, "info")
		end
		removePickup(pickup)
		if pickup.container then
			pickup.container.pickup = nil
			pickup.container = nil
		end
		if state.roundStats then
			state.roundStats.items += 1
		end
		services.NoiseService:emit("Pickup", part.Position, { source = player })
		ItemService.PickedUp:Fire(player, kind)
	end)
	table.insert(pickups, pickup)
	return pickup
end

-- Lore notes: readable by everyone, counted once per player per profile.
function ItemService.spawnNote(note, position)
	local part = Instance.new("Part")
	part.Name = "Note"
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(1, 0.05, 1.3)
	part.Color = rgb(236, 230, 206)
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	part.Parent = folder or Workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Read"
	prompt.ObjectText = "Note"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	local readers = {}
	prompt.Triggered:Connect(function(player)
		if not services.PlayerService:canInteract(player, part.Position) then
			return
		end
		services.Remotes.Lore:FireClient(player, { id = note.Id, title = note.Title, body = note.Body })
		services.NoiseService:emit("NoteRead", part.Position, { source = player })
		if not readers[player] then
			readers[player] = true
			ItemService.LoreRead:Fire(player, note.Id)
		end
	end)
	table.insert(pickups, { kind = "Note", model = part, position = part.Position })
end

function ItemService.loreById(id)
	for _, note in ipairs(LoreConfig) do
		if note.Id == id then
			return note
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Dropping / throwing
---------------------------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(position, exclude)
	groundParams.FilterDescendantsInstances = exclude or {}
	local result = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), groundParams)
	if result then
		return result.Position
	end
	return Vector3.new(position.X, 0, position.Z)
end

function ItemService.dropAll(player, position)
	local inv = ItemService.inventory(player)
	if #inv == 0 then
		return
	end
	local state = services.PlayerService.get(player)
	local exclude = {}
	if state and state.character then
		table.insert(exclude, state.character)
	end
	if folder then
		table.insert(exclude, folder)
	end
	for i, kind in ipairs(inv) do
		local angle = (i / #inv) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 1.6, 0, math.sin(angle) * 1.6)
		ItemService.spawn(kind, groundBelow(position + offset, exclude))
	end
	inventories[player] = {}
	ItemService.sendInventory(player)
end

function ItemService.drop(player, slot)
	local state = services.PlayerService.get(player)
	if type(slot) ~= "number" or slot ~= slot or not state or state.status ~= "Alive" or state.hiddenIn then
		return
	end
	local now = os.clock()
	if lastDrop[player] and now - lastDrop[player] < 0.4 then
		return
	end
	lastDrop[player] = now
	local inv = ItemService.inventory(player)
	slot = math.floor(slot)
	local kind = inv[slot]
	if not kind or not state.root then
		return
	end
	table.remove(inv, slot)
	ItemService.sendInventory(player)
	local root = state.root
	local position = groundBelow(root.Position + root.CFrame.LookVector * 2, if folder then { state.character, folder } else { state.character })
	local def = ItemConfig[kind]
	-- Crouching sets it down gently; otherwise it is dropped (and glass shatters).
	local gentle = state.crouch
	local category = def.DropNoise or "ItemDrop"
	if def.Breaks and gentle then
		category = "ItemDrop"
	end
	if not (def.Breaks and not gentle) then
		ItemService.spawn(kind, position)
	end
	services.NoiseService:emit(category, position, { source = player, multiplier = if gentle then 0.3 else 1 })
end

local projectileParams = RaycastParams.new()
projectileParams.FilterType = Enum.RaycastFilterType.Exclude

-- Throws the selected throwable (or the first one carried). Bottles shatter, cans land
-- and can be picked up again, alarm clocks keep ringing where they land.
function ItemService.throw(player, direction, slot)
	local state = services.PlayerService.get(player)
	if not state or state.status ~= "Alive" or state.hiddenIn or not state.root then
		return
	end
	if typeof(direction) ~= "Vector3" or direction.Magnitude ~= direction.Magnitude or direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then
		return
	end
	local now = os.clock()
	if lastThrow[player] and now - lastThrow[player] < PlayerConfig.Throw.Cooldown then
		return
	end
	local inv = ItemService.inventory(player)
	local index
	if type(slot) == "number" and slot == slot then
		local k = inv[math.floor(slot)]
		if k and ItemConfig[k].Throwable then
			index = math.floor(slot)
		end
	end
	if not index then
		for i, k in ipairs(inv) do
			if ItemConfig[k].Throwable then
				index = i
				break
			end
		end
	end
	if not index then
		services.Remotes.Notify:FireClient(player, "Nothing to throw", "warn")
		return
	end
	local kind = table.remove(inv, index)
	ItemService.sendInventory(player)
	local def = ItemConfig[kind]
	lastThrow[player] = now
	direction = direction.Unit
	local head = state.character:FindFirstChild("Head")
	local origin = (if head then head.Position else state.root.Position + Vector3.new(0, 1.5, 0)) + direction * 1.5
	local velocity = direction * PlayerConfig.Throw.Speed + Vector3.new(0, PlayerConfig.Throw.UpBoost, 0)
	local gravity = Vector3.new(0, -Workspace.Gravity * 0.5, 0)

	local projectile = buildVisual(kind, CFrame.new(origin))
	projectile.Parent = folder or Workspace
	local ignore = { state.character, projectile }
	if folder then
		table.insert(ignore, folder)
	end
	if services.MonsterService.model() then
		table.insert(ignore, services.MonsterService.model())
	end
	projectileParams.FilterDescendantsInstances = ignore

	task.spawn(function()
		local position = origin
		local elapsed = 0
		local step = 1 / 30
		local impact
		while elapsed < PlayerConfig.Throw.MaxFlightTime do
			local nextVelocity = velocity + gravity * step
			local move = (velocity + nextVelocity) * 0.5 * step
			local result = Workspace:Raycast(position, move, projectileParams)
			if result then
				-- Stop just short of the surface so the item does not end up inside a wall.
				impact = result.Position + result.Normal * 0.4
				break
			end
			position += move
			velocity = nextVelocity
			projectile.CFrame = CFrame.new(position) * CFrame.Angles(elapsed * 9, elapsed * 5, 0)
			elapsed += step
			task.wait(step)
		end
		impact = impact or position
		projectile:Destroy()
		services.NoiseService:emit(def.ImpactNoise or "ItemDrop", impact, { source = player })
		if def.Breaks then
			return
		end
		local pickup = ItemService.spawn(kind, groundBelow(impact, ignore))
		if pickup and def.Ring then
			for _ = 1, def.Ring.Count do
				task.wait(def.Ring.Interval)
				if not pickup.model then
					break -- someone picked it up
				end
				services.NoiseService:emit(def.Ring.Category, pickup.position, {})
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Cabinets
---------------------------------------------------------------------------------------------

-- Shows or hides a cabinet's contents: items can only be seen glowing and picked up while
-- the doors are open.
local function setContentsReachable(container, open)
	local pickup = container.pickup
	if pickup and pickup.model then
		pickup.prompt.Enabled = open
		local light = pickup.model:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = open
		end
	end
end

-- Wires up Open/Close prompts on every cabinet MapBuilder created.
function ItemService.setupContainers(map)
	local TweenService = game:GetService("TweenService")
	for _, container in ipairs(map.containers) do
		container.open = false
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = container.actionOpen or "Open"
		prompt.ObjectText = container.label
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = container.promptDistance or 7
		prompt.RequiresLineOfSight = false
		-- One prompt per key on screen: Roblox shows the drawer you are facing.
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Parent = container.promptPart
		container.prompt = prompt
		prompt.Triggered:Connect(function(player)
			if container.moving or not services.PlayerService:canInteract(player, container.promptPart.Position) then
				return
			end
			local opening = not container.open
			container.open = opening
			container.moving = true
			for _, piece in ipairs(container.parts) do
				TweenService:Create(piece.part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
					CFrame = if opening then piece.openCFrame else piece.closedCFrame,
				}):Play()
			end
			task.delay(0.35, function()
				container.moving = false
			end)
			prompt.ActionText = if opening then (container.actionClose or "Close") else (container.actionOpen or "Open")
			-- Items in drawers ride out with the drawer.
			local pickup = container.pickup
			if pickup and pickup.model and container.itemShift then
				local goal = if opening then pickup.closedCFrame + container.itemShift else pickup.closedCFrame
				TweenService:Create(pickup.model, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
				pickup.position = goal.Position
			end
			setContentsReachable(container, opening)
			local crouched = services.PlayerService:isCrouching(player)
			local noise = if opening then (container.openNoise or "CabinetOpen") else (container.closeNoise or "CabinetClose")
			services.NoiseService:emit(noise, container.position, {
				source = player,
				multiplier = if crouched then services.SoundConfig.CrouchInteractionMultiplier else 1,
			})
		end)
	end
end

-- Places an item on the shelf of a random empty cabinet in the given cell (hidden behind
-- the closed doors). Returns false if the cell has no free cabinet.
function ItemService.hideIn(map, cellIndex, kind, rng)
	local free = {}
	for _, container in ipairs(map.containersByCell[cellIndex] or {}) do
		if not container.pickup then
			table.insert(free, container)
		end
	end
	local container = rng:pick(free)
	if not container then
		return false
	end
	local pickup = ItemService.spawn(kind, container.itemSpot)
	if not pickup then
		return false
	end
	if container.layFlat then
		-- Lay the item on its side so it fits inside a shallow drawer.
		local part = pickup.model
		local rotation = CFrame.new()
		local height = part.Size.Y
		if part.Size.Y > part.Size.Z then
			rotation = CFrame.Angles(math.rad(90), 0, 0)
			height = part.Size.Z
		end
		part.CFrame = CFrame.new(container.itemSpot + Vector3.new(0, height / 2, 0)) * rotation
		pickup.position = part.Position
	end
	pickup.closedCFrame = pickup.model.CFrame
	pickup.container = container
	container.pickup = pickup
	setContentsReachable(container, container.open == true)
	return true
end

function ItemService.markEscapedWithItems(player)
	local state = services.PlayerService.get(player)
	if state and state.roundStats and ItemService.has(player, "BlackBox") > 0 then
		state.roundStats.blackBox = true
	end
end

function ItemService.start()
	local remotes = services.Remotes
	remotes.DropItem.OnServerEvent:Connect(ItemService.drop)
	remotes.ThrowItem.OnServerEvent:Connect(ItemService.throw)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		lastThrow[player] = nil
		lastDrop[player] = nil
	end)
end

function ItemService.countWorld(kind)
	local n = 0
	for _, pickup in ipairs(pickups) do
		if pickup.kind == kind then
			n += 1
		end
	end
	return n
end

return ItemService
