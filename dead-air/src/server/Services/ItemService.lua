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
local function color(list)
	return rgb(list[1], list[2], list[3])
end

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

local function buildVisual(kind)
	local def = ItemConfig[kind]
	local part = Instance.new("Part")
	part.Name = kind
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(def.Size[1], def.Size[2], def.Size[3])
	part.Color = color(def.Color)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = def.Transparency or 0
	if kind == "Fuse" or kind == "Bottle" or kind == "Battery" or kind == "Can" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(def.Size[2], def.Size[1], def.Size[3])
	end
	if kind == "Bottle" then
		part.Material = Enum.Material.Glass
	elseif kind == "FuelCan" or kind == "BlackBox" or kind == "Fuse" or kind == "Can" then
		part.Material = Enum.Material.Metal
	end
	if def.Glow then
		local light = Instance.new("PointLight")
		light.Color = color(def.Glow)
		light.Range = 7
		light.Brightness = 0.7
		light.Shadows = false
		light.Parent = part
	end
	return part
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
	local part = buildVisual(kind)
	local cf = CFrame.new(position + Vector3.new(0, part.Size.Y / 2, 0))
	if part.Shape == Enum.PartType.Cylinder then
		-- Cylinders lie along X; stand fuses/bottles upright.
		cf = CFrame.new(position + Vector3.new(0, part.Size.X / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	part.CFrame = cf
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
	prompt.Triggered:Connect(function(player)
		if not pickup.model then
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

	local projectile = buildVisual(kind)
	projectile.CFrame = CFrame.new(origin)
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
-- Searchable containers
---------------------------------------------------------------------------------------------

local SEARCH_TIME = 0.8

-- Wires up "Search" prompts on every cabinet / drawer MapBuilder created. ObjectiveService
-- decides what (if anything) is inside each one by setting container.contents.
function ItemService.setupContainers(map)
	local TweenService = game:GetService("TweenService")
	for _, container in ipairs(map.containers) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Search"
		prompt.ObjectText = container.label
		prompt.HoldDuration = SEARCH_TIME
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = container.promptPart
		local holdStart = {}
		prompt.PromptButtonHoldBegan:Connect(function(player)
			holdStart[player] = os.clock()
		end)
		prompt.PromptButtonHoldEnded:Connect(function(player)
			holdStart[player] = nil
		end)
		prompt.Triggered:Connect(function(player)
			local began = holdStart[player]
			holdStart[player] = nil
			-- The hold time is enforced here, not just by the client prompt.
			if container.opened or not began or os.clock() - began < SEARCH_TIME * 0.8 then
				return
			end
			if not services.PlayerService:canInteract(player, container.promptPart.Position) then
				return
			end
			container.opened = true
			prompt.Enabled = false
			for _, piece in ipairs(container.parts) do
				TweenService:Create(piece.part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = piece.openCFrame }):Play()
			end
			local crouched = services.PlayerService:isCrouching(player)
			services.NoiseService:emit(container.noise, container.position, {
				source = player,
				multiplier = if crouched then services.SoundConfig.CrouchInteractionMultiplier else 1,
			})
			if container.contents then
				local kind = container.contents
				container.contents = nil
				task.delay(0.3, function()
					ItemService.spawn(kind, container.itemSpot)
				end)
				services.Remotes.Notify:FireClient(player, "Found: " .. ItemConfig[kind].DisplayName, "info")
			else
				services.Remotes.Notify:FireClient(player, "Empty.", "info")
			end
		end)
	end
end

-- Hides an item in a random unused container in the given cell. Returns false if none.
function ItemService.hideIn(map, cellIndex, kind, rng)
	local free = {}
	for _, container in ipairs(map.containersByCell[cellIndex] or {}) do
		if not container.contents and not container.opened then
			table.insert(free, container)
		end
	end
	local container = rng:pick(free)
	if not container then
		return false
	end
	container.contents = kind
	return true
end

-- How many of an item kind are still hidden (unopened) in containers.
function ItemService.countHidden(map, kind)
	local n = 0
	for _, container in ipairs(map.containers) do
		if container.contents == kind then
			n += 1
		end
	end
	return n
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
