--[[
	CourseService - the courses' moving and breakable parts, facility unlocks and travel.

	* Moving targets: anchored, moved by the server every Heartbeat (Motion: sine motion
	  from CourseConfig) with a matching AssemblyLinearVelocity, so every client sees the
	  same position the server tests against and contacts push instead of fling.
	* Destructible props (controlled destruction): hitProp() breaks a prop only if the
	  dummy is fast enough AND heavy enough (prop Strength vs dummy class). The prop is
	  hidden (a prebuilt break state: nothing is created or destroyed), a few fragments fly
	  from a REUSED pool that never holds more than MaxActiveDebris parts server-wide,
	  fragments go back to the pool after a few seconds and the prop respawns later.
	  Structural geometry is never destructible.
	* Facilities: a facility becomes available when its requirement is met (checked on
	  the server whenever a stat changes) and is unlocked once by paying its coin price
	  (unlockFacility). Access is saved and survives prestige. Unbuilt facilities say
	  "under construction" honestly.
	* Travel: players move between unlocked facilities (travel) from the hub's transit
	  gate / the Facilities menu and back with each facility's HUB TRANSIT kiosk. The
	  server remembers where each player is (respawns there; anyone who falls off the
	  High-Altitude mesa is put back on the deck).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local Economy = require(Shared.Economy)
local Motion = require(Shared.Motion)
local Progress = require(Shared.Progress)
local Format = require(Shared.Format)

local RateLimit = require(script.Parent.RateLimit)

local CourseService = {}

local services
local world
local clock = 0
local activeDebris = {}
local debrisPool = {} -- free fragments, reused (never more than MaxActiveDebris exist)
local debrisCreated = 0
local rng = Random.new()
local location = {} -- [player] = facility id
local eligibleSeen = {} -- [player] = { [facilityId] = true } (for "now available" popups)
local travelLimiter = RateLimit.new(1, 2)

function CourseService.init(registry)
	services = registry
end

function CourseService.setWorld(newWorld)
	world = newWorld
end

-- Moving targets ----------------------------------------------------------------------

-- World position of a target at time t (its facility origin + the course Motion).
function CourseService.targetPosition(id, t)
	local target = world.targets[id]
	return (target.offset or Vector3.new(0, 0, 0)) + Motion.position(target.def, t or clock)
end

function CourseService.targetVelocity(id, t)
	return Motion.velocity(world.targets[id].def, t or clock)
end

-- Moves the anchored target parts AND gives them the matching velocity, so the solver
-- treats them as really moving (contacts push with the target's speed rather than the
-- part teleporting into the dummy each frame and flinging it).
function CourseService.step(dt)
	clock += dt
	for id, target in pairs(world.targets) do
		if target.def.Motion then
			local p = CourseService.targetPosition(id, clock)
			local v = CourseService.targetVelocity(id, clock)
			local frame = CFrame.new(p)
			for _, m in ipairs(target.movers) do
				m.CFrame = frame * target.base[m]
				m.AssemblyLinearVelocity = v
			end
		end
	end
end

-- Props --------------------------------------------------------------------------------

local function cleanupDebris(entry)
	local i = table.find(activeDebris, entry)
	if i then
		table.remove(activeDebris, i)
	end
	for _, p in ipairs(entry.parts) do
		-- Back to the pool: out of the world, ready for the next break.
		p.Anchored = true
		p.Parent = nil
		table.insert(debrisPool, p)
	end
	table.clear(entry.parts)
end

local function debrisParts()
	local n = 0
	for _, e in ipairs(activeDebris) do
		n += #e.parts
	end
	return n
end

local function takeFragment()
	local d = table.remove(debrisPool)
	if d then
		return d
	end
	if debrisCreated >= PerformanceConfig.MaxActiveDebris then
		return nil
	end
	debrisCreated += 1
	d = Instance.new("Part")
	d.Name = "Debris"
	d.CanQuery = false
	d.CanTouch = false
	d.TopSurface = Enum.SurfaceType.Smooth
	d.BottomSurface = Enum.SurfaceType.Smooth
	d.CollisionGroup = services.CrashService.Groups.Debris
	return d
end

local function spawnDebris(prop, kind)
	-- The cap counts loose PARTS server-wide, not bursts.
	local count = math.min(kind.Debris, PerformanceConfig.MaxActiveDebris - debrisParts())
	if count <= 0 then
		return 0
	end
	local entry = { parts = {} }
	local base = prop.part
	for _ = 1, count do
		local d = takeFragment()
		if not d then
			break
		end
		d.Size = Vector3.new(prop.size.X * rng:NextNumber(0.25, 0.45), prop.size.Y * rng:NextNumber(0.2, 0.4), math.max(0.3, prop.size.Z * rng:NextNumber(0.25, 0.5)))
		d.CFrame = prop.cframe * CFrame.new(rng:NextNumber(-0.3, 0.3) * prop.size.X, rng:NextNumber(-0.3, 0.3) * prop.size.Y, 0) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		d.Color = base.Color
		d.Material = base.Material
		-- (the prop itself is already hidden: fragments use its normal look)
		d.Transparency = prop.transparency or 0
		d.Anchored = false
		d.Parent = world.debrisFolder
		pcall(function()
			d:SetNetworkOwner(nil)
		end)
		d.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-18, 18), rng:NextNumber(10, 30), rng:NextNumber(8, 30))
		table.insert(entry.parts, d)
	end
	if #entry.parts == 0 then
		return 0
	end
	table.insert(activeDebris, entry)
	task.delay(PerformanceConfig.DebrisLifetime, function()
		cleanupDebris(entry)
	end)
	return #entry.parts
end

-- Fragments that exist at all (in flight + waiting in the pool). Never above the cap.
function CourseService.debrisPoolSize()
	return debrisCreated
end

function CourseService.activeDebris()
	return debrisParts()
end

local function setBroken(prop, broken)
	prop.broken = broken
	prop.part.Transparency = if broken then 1 else (prop.transparency or 0)
	prop.part.CanCollide = not broken
	prop.part.CanTouch = not broken
	for _, child in ipairs(prop.part:GetChildren()) do
		if child:IsA("BasePart") then
			child.Transparency = if broken then 1 else 0
		end
	end
end

function CourseService.respawn(propId)
	local prop = world.props[propId]
	if prop and prop.broken then
		setBroken(prop, false)
	end
end

-- Returns "broken" | "bounced" | nil (not a valid hit), and the prop record.
function CourseService.hitProp(propId, speed, breakLevel)
	local prop = world.props[propId]
	if not prop or prop.broken then
		return nil, prop
	end
	local kind = CourseConfig.DestructibleKinds[prop.kind]
	if type(speed) ~= "number" or speed ~= speed or speed < kind.BreakSpeed then
		return nil, prop
	end
	if (breakLevel or 1) < kind.Strength then
		return "bounced", prop
	end
	setBroken(prop, true)
	local pieces = spawnDebris(prop, kind)
	services.Remotes.RunEvent:FireAllClients(0, "Prop", { id = propId, kind = prop.kind, position = prop.cframe.Position, pieces = pieces })
	task.delay(PerformanceConfig.RespawnDelay, function()
		CourseService.respawn(propId)
	end)
	return "broken", prop
end

-- Facilities ---------------------------------------------------------------------------

function CourseService.facilityValues(player)
	return services.UpgradeService.requirementValues(player)
end

local function requirementMet(data, f, values)
	if not f.Requirement then
		return true
	end
	local ok = Economy.meets(f.Requirement, values)
	if ok and f.Requirement.Machine then
		ok = data.Machines[f.Requirement.Machine] == true
	end
	return ok
end

function CourseService.locationOf(player)
	return location[player] or CourseConfig.StartFacility
end

function CourseService.facility(id)
	return world and world.facilities[id]
end

-- What the Facilities menu shows (built on the server: requirement, price, personal bests).
function CourseService.facilityView(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return {}
	end
	local values = CourseService.facilityValues(player)
	local here = CourseService.locationOf(player)
	local list = {}
	for _, f in ipairs(CourseConfig.Facilities) do
		table.insert(list, {
			id = f.Id,
			name = f.Name,
			built = f.Built,
			owned = data.Facilities[f.Id] == true,
			eligible = requirementMet(data, f, values),
			cost = f.Cost or 0,
			text = f.Text,
			blurb = f.Blurb,
			here = here == f.Id,
			bestScore = Progress.facilityStat(data.Stats, "BestScore", f.Id) or 0,
			bestDistance = Progress.facilityStat(data.Stats, "BestDistance", f.Id) or 0,
		})
	end
	return list
end

local function countFacilities(data)
	local n = 0
	for id in pairs(data.Facilities) do
		local f = CourseConfig.FacilityById[id]
		if f and f.Built then
			n += 1
		end
	end
	return n
end

-- Called whenever a stat changes. Unbuilt facilities are granted for free as before
-- ("access granted - under construction"); built ones with a price announce once that
-- they are now available to unlock.
function CourseService.checkFacilities(player, silent)
	local data = services.DataService.getProfile(player)
	if not data then
		return
	end
	local values = CourseService.facilityValues(player)
	eligibleSeen[player] = eligibleSeen[player] or {}
	for _, f in ipairs(CourseConfig.Facilities) do
		if not data.Facilities[f.Id] and f.Requirement and requirementMet(data, f, values) then
			if not f.Built then
				data.Facilities[f.Id] = true
				services.DataService.markDirty(player)
				services.Remotes.Popup:FireClient(player, "Facility", { id = f.Id, name = f.Name, built = false })
				services.DataService.sendProfile(player)
			elseif not eligibleSeen[player][f.Id] then
				eligibleSeen[player][f.Id] = true
				if not silent then
					services.Remotes.Popup:FireClient(player, "FacilityReady", { id = f.Id, name = f.Name, cost = f.Cost })
					services.DataService.sendProfile(player)
				end
			end
		end
	end
end

-- One-time unlock: the requirement must be met AND the coin price is paid exactly once.
function CourseService.unlockFacility(player, id)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your lab data is still loading."
	end
	local f = type(id) == "string" and CourseConfig.FacilityById[id]
	if not f then
		return false, "Unknown facility."
	end
	if data.Facilities[f.Id] then
		return false, "You already have access to the " .. f.Name .. "."
	end
	if not f.Built then
		return false, f.Name .. " is still under construction."
	end
	if not requirementMet(data, f, CourseService.facilityValues(player)) then
		return false, "Locked: " .. f.Text
	end
	if not services.DataService.spendCoins(player, f.Cost or 0) then
		return false, string.format("The %s costs %s coins.", f.Name, Format.short(f.Cost or 0))
	end
	data.Facilities[f.Id] = true
	services.DataService.setStat(player, "Facilities", countFacilities(data))
	services.DataService.markDirty(player)
	services.Analytics.custom(player, "FacilityUnlocked:" .. f.Id, 1)
	services.Remotes.Popup:FireClient(player, "Facility", { id = f.Id, name = f.Name, built = true })
	services.Remotes.Announce:FireAllClients(player.DisplayName .. " unlocked the " .. f.Name .. "!", { 110, 190, 255 })
	services.DataService.sendProfile(player)
	return true, f.Name .. " unlocked! Open Facilities to travel there."
end

function CourseService.travel(player, id)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your lab data is still loading."
	end
	local f = type(id) == "string" and CourseConfig.FacilityById[id]
	if not f then
		return false, "Unknown facility."
	end
	if not f.Built then
		return false, f.Name .. " is still under construction."
	end
	if not data.Facilities[f.Id] then
		return false, "Unlock the " .. f.Name .. " first."
	end
	if services.LaunchService.isBusy(player) then
		return false, "Wait for your launch to finish first."
	end
	local entry = world.facilities[f.Id]
	local character = player.Character
	if not entry or not character or not character.PrimaryPart then
		return false, "Your character isn't ready yet."
	end
	services.PadService.release(player)
	character:PivotTo(entry.spawn)
	location[player] = f.Id
	services.QuestService.rerollFeatured(player)
	services.DataService.sendProfile(player)
	services.Remotes.Popup:FireClient(player, "Arrived", { id = f.Id, name = f.Name })
	return true, "Welcome to the " .. f.Name .. "!"
end

-- Respawns put the player back in the facility they were in.
function CourseService.onCharacter(player, character)
	local id = CourseService.locationOf(player)
	local entry = world and world.facilities[id]
	if id ~= CourseConfig.StartFacility and entry then
		task.defer(function()
			if character.Parent and character.PrimaryPart then
				character:PivotTo(entry.spawn)
			end
		end)
	end
end

-- Players who fall off a facility (the High-Altitude mesa) go back to its deck.
function CourseService.checkCharacters()
	for player, id in pairs(location) do
		local course = CourseConfig.Courses[id]
		local entry = world.facilities[id]
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if course and entry and rootPart and course.Arena.PlayerFloorY and rootPart.Position.Y - course.Origin.Y < course.Arena.PlayerFloorY then
			character:PivotTo(entry.spawn)
			services.Remotes.Notify:FireClient(player, "Careful near the edge! You're back on the deck.", "info")
		end
	end
end

function CourseService.onProfileLoaded(player)
	CourseService.checkFacilities(player, true)
end

function CourseService.onPlayerRemoving(player)
	location[player] = nil
	eligibleSeen[player] = nil
	travelLimiter:forget(player)
end

function CourseService.start()
	world.gate.prompt.Triggered:Connect(function(player)
		services.Remotes.Popup:FireClient(player, "OpenMenu", { tab = "Facilities" })
	end)
	world.stationPrompt.Triggered:Connect(function(player)
		services.Remotes.Popup:FireClient(player, "OpenMenu", { tab = "Upgrades" })
	end)
	world.lockerPrompt.Triggered:Connect(function(player)
		services.Remotes.Popup:FireClient(player, "OpenMenu", { tab = "Locker" })
	end)
	local remotes = services.Remotes
	local function reply(player, ok, message)
		if message then
			remotes.Notify:FireClient(player, message, if ok then "good" else "error")
		end
	end
	for id, entry in pairs(world.facilities) do
		if entry.returnPrompt then
			entry.returnPrompt.Triggered:Connect(function(player)
				reply(player, CourseService.travel(player, CourseConfig.StartFacility))
			end)
		end
		entry.id = id
	end
	remotes.Travel.OnServerEvent:Connect(function(player, id)
		if travelLimiter:allow(player) then
			reply(player, CourseService.travel(player, id))
		end
	end)
	remotes.UnlockFacility.OnServerEvent:Connect(function(player, id)
		if travelLimiter:allow(player) then
			reply(player, CourseService.unlockFacility(player, id))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			CourseService.checkCharacters()
		end
	end)
end

return CourseService
