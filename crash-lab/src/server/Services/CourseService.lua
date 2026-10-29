--[[
	CourseService - the course's moving and breakable parts, and facility unlocks.

	* Moving targets: anchored, moved by the server every Heartbeat (Motion: sine motion
	  from CourseConfig) with a matching AssemblyLinearVelocity, so every client sees the
	  same position the server tests against and contacts push instead of fling.
	* Destructible props (controlled destruction): hitProp() breaks a prop only if the
	  dummy is fast enough AND heavy enough (prop Strength vs dummy class). The prop is
	  hidden (not destroyed), a LIMITED number of debris parts spawn (server-wide cap),
	  debris is cleaned up after a few seconds and the prop respawns later. Structural
	  geometry is never destructible.
	* Facilities: requirements are checked on the server whenever a relevant stat
	  changes; access is saved. Unbuilt facilities say "under construction" honestly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local Economy = require(Shared.Economy)
local Motion = require(Shared.Motion)

local CourseService = {}

local services
local world
local clock = 0
local activeDebris = {}
local rng = Random.new()

function CourseService.init(registry)
	services = registry
end

function CourseService.setWorld(newWorld)
	world = newWorld
end

-- Moving targets ----------------------------------------------------------------------

function CourseService.targetPosition(id, t)
	return Motion.position(world.targets[id].def, t or clock)
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
		p:Destroy()
	end
end

local function debrisParts()
	local n = 0
	for _, e in ipairs(activeDebris) do
		n += #e.parts
	end
	return n
end

local function spawnDebris(prop, kind)
	-- The cap counts loose PARTS server-wide, not bursts.
	local count = math.min(kind.Debris, PerformanceConfig.MaxActiveDebris - debrisParts())
	if count <= 0 then
		return 0
	end
	local entry = { parts = {} }
	local base = prop.part
	for i = 1, count do
		local d = Instance.new("Part")
		d.Name = "Debris"
		d.Size = Vector3.new(prop.size.X * rng:NextNumber(0.25, 0.45), prop.size.Y * rng:NextNumber(0.2, 0.4), math.max(0.3, prop.size.Z * rng:NextNumber(0.25, 0.5)))
		d.CFrame = prop.cframe * CFrame.new(rng:NextNumber(-0.3, 0.3) * prop.size.X, rng:NextNumber(-0.3, 0.3) * prop.size.Y, 0) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		d.Color = base.Color
		d.Material = base.Material
		d.Transparency = base.Transparency
		d.CanQuery = false
		d.CanTouch = false
		d.CollisionGroup = services.CrashService.Groups.Debris
		d.Parent = world.debrisFolder
		pcall(function()
			d:SetNetworkOwner(nil)
		end)
		d.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-18, 18), rng:NextNumber(10, 30), rng:NextNumber(8, 30))
		entry.parts[i] = d
	end
	table.insert(activeDebris, entry)
	task.delay(PerformanceConfig.DebrisLifetime, function()
		cleanupDebris(entry)
	end)
	return count
end

function CourseService.activeDebris()
	return debrisParts()
end

local function setBroken(prop, broken)
	prop.broken = broken
	prop.part.Transparency = if broken then 1 else (if prop.kind == "Panel" then 0.35 else 0)
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
	local values = services.UpgradeService.requirementValues(player)
	return values
end

function CourseService.checkFacilities(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return
	end
	local values = CourseService.facilityValues(player)
	for _, f in ipairs(CourseConfig.Facilities) do
		if not data.Facilities[f.Id] and f.Requirement then
			local ok = Economy.meets(f.Requirement, values)
			if ok and f.Requirement.Machine then
				ok = data.Machines[f.Requirement.Machine] == true
			end
			if ok then
				data.Facilities[f.Id] = true
				services.DataService.markDirty(player)
				services.Remotes.Popup:FireClient(player, "Facility", { id = f.Id, name = f.Name, built = f.Built })
				services.DataService.sendProfile(player)
			end
		end
	end
end

function CourseService.onProfileLoaded(player)
	CourseService.checkFacilities(player)
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
end

return CourseService
