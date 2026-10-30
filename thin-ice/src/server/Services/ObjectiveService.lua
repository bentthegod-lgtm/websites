--[[
	ObjectiveService - the frozen cores.

	  * Each core is sealed in a block of ice out on the lake. Hold the prompt to chip it
	    out - chipping is LOUD (the Antlered hears it from far away), so friends should
	    keep watch or throw a snowball lure first.
	  * The carrier holds the glowing shard over their head (a little slower, a little
	    heavier on the ice). Falling in, freezing or leaving drops it where they were;
	    anyone can pick it back up.
	  * Walk it to the beacon on the shore to deliver it. When every core is in, the
	    rescue sled gets ready (RoundService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local LakeGen = require(Shared.LakeGen)
local Models = require(Shared.Models)

local ObjectiveService = {}

local services
local world
local run
local cores = {}
local byId = {}

local R = GameConfig.Round
local L = GameConfig.Lake

function ObjectiveService.init(registry)
	services = registry
end

function ObjectiveService.setWorld(newWorld)
	world = newWorld
end

local function flat(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function prompt(parent, action, hold, distance)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = "Frozen core"
	p.HoldDuration = hold
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = parent
	return p
end

local function setBeacon()
	if not world or not world.beacon then
		return
	end
	local fraction = if run and run.total > 0 then run.delivered / run.total else 0
	local light = world.beacon.light
	if light then
		light.Brightness = 0.2 + 3 * fraction
		light.Range = 40 + 20 * fraction
	end
	world.beacon.flame.Transparency = 0.7 - 0.6 * fraction
end

local function canAct(player)
	local rec = services.SurvivalService.record(player)
	return rec ~= nil and rec.state == "Active" and not rec.inWater, rec
end

-- A core lying (or sealed) at a world position, with its prompt wired up.
local function placeCore(core, position, sealed)
	if core.model then
		core.model:Destroy()
	end
	local base = CFrame.new(position.X, L.IceTop, position.Z)
	if sealed then
		local m, glow = Models.frozenCore(base, run.folder)
		core.model = m
		core.glow = glow
		local p = prompt(m:FindFirstChild("Shell"), "Chip out", R.ChipTime, 9)
		p.PromptButtonHoldBegan:Connect(function(player)
			-- Chipping starts making noise the moment you start hammering.
			if canAct(player) and core.state == "Sealed" then
				services.NoiseService.emit("Chip", position, player)
			end
		end)
		p.Triggered:Connect(function(player)
			ObjectiveService.take(player, core.id)
		end)
		core.prompt = p
	else
		local m = Models.carriedShard(base * CFrame.new(0, 1.4, 0), run.folder)
		m.Name = "DroppedCore"
		core.model = m
		local p = prompt(m:FindFirstChild("Shard"), "Pick up", R.PickupTime, 8)
		p.Triggered:Connect(function(player)
			ObjectiveService.take(player, core.id)
		end)
		core.prompt = p
	end
	core.position = position
end

function ObjectiveService.startRun(newRun)
	run = newRun
	cores, byId = {}, {}
	for _, def in ipairs(run.layout.cores) do
		local x, z = LakeGen.cellToWorld(def.c, def.r)
		local core = { id = def.id, state = "Sealed", zone = def.zone }
		placeCore(core, Vector3.new(x, L.IceTop, z), true)
		table.insert(cores, core)
		byId[core.id] = core
	end
	run.total = #cores
	run.delivered = 0
	setBeacon()
end

function ObjectiveService.stopRun()
	for _, core in ipairs(cores) do
		if core.model then
			core.model:Destroy()
		end
		if core.shard then
			core.shard:Destroy()
		end
	end
	cores, byId = {}, {}
	run = nil
	setBeacon()
end

function ObjectiveService.cores()
	return cores
end

function ObjectiveService.core(id)
	return byId[id]
end

-- Chip a sealed core out, or pick up a dropped one.
function ObjectiveService.take(player, id)
	local core = byId[id]
	local ok, rec = canAct(player)
	if not core or not ok or rec.carrying or (core.state ~= "Sealed" and core.state ~= "Dropped") then
		return false
	end
	local root = rootOf(player)
	if not root or flat(root.Position, core.position) > 12 then
		return false
	end
	local wasSealed = core.state == "Sealed"
	if core.model then
		core.model:Destroy()
		core.model = nil
	end
	core.state = "Carried"
	core.carrier = player
	rec.carrying = core
	-- The shard rides over the carrier's head (welded, so it moves smoothly with them).
	local shard = Models.carriedShard(root.CFrame * CFrame.new(0, 4.6, 0), run.folder)
	shard.Name = "Carried_" .. player.Name
	for _, d in ipairs(shard:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = d
			weld.Part1 = root
			weld.Parent = d
		end
	end
	core.shard = shard
	if wasSealed then
		services.NoiseService.emit("Chip", core.position, player)
		for other in pairs(run.players) do
			services.Remotes.Notify:FireClient(other, player.DisplayName .. " chipped out a core! Get it to the beacon.", "good")
		end
	else
		services.Remotes.Notify:FireClient(player, "Got the core! Get it to the beacon.", "good")
	end
	return true
end

-- Drops whatever the player carries where they stand (onto the nearest ice).
function ObjectiveService.drop(player)
	local rec = services.SurvivalService.record(player)
	local core = rec and rec.carrying
	if not core then
		return false
	end
	rec.carrying = nil
	core.carrier = nil
	if core.shard then
		core.shard:Destroy()
		core.shard = nil
	end
	local root = rootOf(player)
	local where = if root then root.Position else core.position
	if where.Z >= L.ShoreZ then
		where = services.SurvivalService.nearestIce(where) or where
	end
	core.state = "Dropped"
	placeCore(core, where, false)
	return true
end

function ObjectiveService.deliver(player)
	local rec = services.SurvivalService.record(player)
	local core = rec and rec.carrying
	if not core or not run then
		return false
	end
	rec.carrying = nil
	rec.cores += 1
	core.state = "Delivered"
	core.carrier = nil
	if core.shard then
		core.shard:Destroy()
		core.shard = nil
	end
	run.delivered += 1
	setBeacon()
	services.DataService.bump(player, "Cores", 1)
	services.NoiseService.emit("Deliver", world.beacon.position, player)
	services.Remotes.Announce:FireAllClients(string.format("Core delivered! %d / %d", run.delivered, run.total), { 120, 230, 255 })
	if run.delivered >= run.total and services.RoundService then
		services.RoundService.allCoresIn()
	end
	return true
end

function ObjectiveService.step()
	if not run or not world then
		return
	end
	for _, core in ipairs(cores) do
		if core.state == "Carried" and core.carrier then
			local root = rootOf(core.carrier)
			if root and flat(root.Position, world.beacon.position) <= R.BeaconRadius then
				ObjectiveService.deliver(core.carrier)
			end
		end
	end
end

function ObjectiveService.onPlayerRemoving(player)
	ObjectiveService.drop(player)
end

return ObjectiveService
