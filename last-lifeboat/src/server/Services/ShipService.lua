--[[
	ShipService - the ship and the sea.

	* The Terrain ocean is filled a few blocks per frame at startup (OceanBuilder).
	* A ship is always moored at the dock: the Gull is built as soon as the server starts
	  (ShipBuilder job, a few hundred parts per frame) and again after every round. When a
	  round prepares, the voted ship is reused if it is the one waiting (fresh, unsunk);
	  otherwise it is rebuilt over a few dozen frames.
	* LURCHES: every LurchEvery seconds (random in the ship's range, pushed back by valve
	  wheels) the server warns everyone (Brace, BraceTime early: horn, red flash, "BRACE!"),
	  then does ONE PivotTo of the ship model: lower by a few studs and tilt bow-down about
	  the stern (LurchMath). Clients get the old and new pivot and move their own character
	  by the same delta. Loose props are carried along and nudged downhill.
	* Workspace attributes for the HUD: LL_Ship, LL_Tilt, LL_Sink, LL_NextLurch (server
	  time), LL_Lurch, LL_MaxTilt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local ShipGen = require(Shared.ShipGen)
local LurchMath = require(Shared.LurchMath)

local ShipService = {}

local services
local ShipBuilder, LobbyBuilder, OceanBuilder
local folder
local ocean
local job, record, shipKey
local inUse = false
local lurch = nil
local plunge = nil
local seedRng = Random.new()
local rng = Random.new()

local SK = GameConfig.Sinking

function ShipService.init(registry)
	services = registry
	ShipBuilder = require(script.Parent.Parent.World.ShipBuilder)
	LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
	OceanBuilder = require(script.Parent.Parent.World.OceanBuilder)
end

function ShipService.setWorld(_world)
	folder = workspace:FindFirstChild("LastLifeboatShips")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LastLifeboatShips"
		folder.Parent = workspace
	end
	ocean = OceanBuilder.new(workspace:FindFirstChildOfClass("Terrain"))
end

local function serverTime(t)
	return workspace:GetServerTimeNow() + (t - os.clock())
end

local function destroyCurrent()
	if job then
		ShipBuilder.destroy(job.record)
		job = nil
	end
	if record then
		ShipBuilder.destroy(record)
		record = nil
	end
	inUse = false
end

-- Starts building `key` unless a fresh one is already moored. Returns true if it is ready.
function ShipService.request(key, seed)
	assert(GameConfig.Ships[key], "unknown ship " .. tostring(key))
	if shipKey == key and not inUse and (record or job) then
		return record ~= nil and job == nil
	end
	destroyCurrent()
	shipKey = key
	local plan = ShipGen.plan(key, seed or seedRng:NextInteger(1, 2 ^ 30))
	job = ShipBuilder.new(plan, folder, LobbyBuilder.shipBase(key))
	return false
end

-- One frame of world building (ocean blocks, then ship parts). Returns true when idle.
function ShipService.stepBuild()
	if ocean and not ocean.done then
		ocean:step(2)
	end
	if job then
		local t0 = os.clock()
		local done = job:step(GameConfig.Ship.PartsPerStep)
		ShipService.lastStepTime = os.clock() - t0
		if done then
			record = job.record
			job = nil
			for _, entry in ipairs(record.loose) do
				pcall(function()
					entry.part:SetNetworkOwner(nil)
				end)
			end
		end
	end
	return job == nil and (ocean == nil or ocean.done)
end

function ShipService.ready(key)
	return record ~= nil and job == nil and not inUse and (key == nil or shipKey == key) and (ocean == nil or ocean.done)
end

function ShipService.building()
	return job
end

function ShipService.ocean()
	return ocean
end

function ShipService.record()
	return record
end

function ShipService.key()
	return shipKey
end

function ShipService.pivot()
	return record and record.model:GetPivot()
end

-- World CFrame of a ship-local CFrame under the ship's current pivot.
function ShipService.toWorld(localCF)
	return record.model:GetPivot() * localCF
end

function ShipService.toLocal(position)
	return record.model:GetPivot():PointToObjectSpace(position)
end

function ShipService.height()
	if not record then
		return 0
	end
	return record.plan.decks[#record.plan.decks].y + 20
end

function ShipService.aboard(position)
	if not record then
		return false
	end
	return LurchMath.onShip(record.model:GetPivot(), position, record.plan.length, record.plan.beam, ShipService.height())
end

-- Ship-local spawn CFrames on the lowest deck at the bow, spread across the walkway.
function ShipService.spawnCFrame(i, count)
	local spawn = record.plan.spawn
	local y = record.plan.decks[spawn.deck].y + 3
	local spread = math.min(10, (count - 1) * 2)
	local x = -spread / 2 + (if count > 1 then (i - 1) * spread / (count - 1) else 0)
	local z = spawn.z + (if i % 2 == 0 then 2 else -2)
	return ShipService.toWorld(CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(180), 0))
end

local function setAttributes()
	if not lurch then
		return
	end
	workspace:SetAttribute("LL_Tilt", lurch.tilt)
	workspace:SetAttribute("LL_Sink", lurch.sink)
	workspace:SetAttribute("LL_Lurch", lurch.k)
	workspace:SetAttribute("LL_NextLurch", serverTime(lurch.nextAt))
end

function ShipService.startRun(run)
	assert(record, "no ship to sink")
	inUse = true
	local def = record.plan.def
	local now = os.clock()
	lurch = {
		def = def,
		base = record.base,
		n = LurchMath.expectedLurches(def),
		k = 0,
		tilt = 0,
		sink = 0,
		nextAt = now + LurchMath.interval(def, rng),
		braced = false,
	}
	plunge = nil
	run.ship = record
	workspace:SetAttribute("LL_Ship", shipKey)
	workspace:SetAttribute("LL_MaxTilt", def.MaxTilt)
	setAttributes()
end

function ShipService.lurchState()
	return lurch
end

function ShipService.delayNextLurch(seconds)
	if lurch then
		lurch.nextAt += seconds
		lurch.braced = false
		setAttributes()
	end
end

-- Moves the ship (and everything riding on it that the server owns) to a new pivot.
local function moveShip(newPivot)
	local old = record.model:GetPivot()
	record.model:PivotTo(newPivot)
	local delta = LurchMath.delta(old, newPivot)
	local downhill = LurchMath.slide(newPivot, math.max(lurch and lurch.tilt or 0, SK.SlideTilt + 1), lurch and lurch.def.MaxTilt or 25, 1)
	local nudge = if downhill.Magnitude > 0 then downhill.Unit * SK.PropNudge else Vector3.zero
	for _, entry in ipairs(record.loose) do
		local p = entry.part
		if p.Parent then
			p.CFrame = delta * p.CFrame
			p.AssemblyLinearVelocity = nudge
		end
	end
	return old
end

function ShipService.lurchNow()
	if not lurch or not record then
		return nil
	end
	lurch.k += 1
	lurch.tilt = LurchMath.tiltAt(lurch.def, lurch.k, lurch.n)
	lurch.sink = LurchMath.sinkAt(lurch.def, lurch.k, lurch.n)
	local newPivot = LurchMath.pivot(lurch.base, lurch.sink, lurch.tilt)
	local old = moveShip(newPivot)
	lurch.nextAt = os.clock() + LurchMath.interval(lurch.def, rng)
	lurch.braced = false
	setAttributes()
	services.Remotes.Lurch:FireAllClients(old, newPivot, { tilt = lurch.tilt, sink = lurch.sink, k = lurch.k })
	if services.SurvivalService then
		services.SurvivalService.onLurch(old, newPivot)
	end
	if services.ObstacleService then
		services.ObstacleService.onLurch(lurch.k, old)
	end
	return old, newPivot
end

function ShipService.step()
	if not lurch or not record then
		return
	end
	local now = os.clock()
	if not lurch.braced and now >= lurch.nextAt - SK.BraceTime then
		lurch.braced = true
		services.Remotes.Brace:FireAllClients(math.max(0, lurch.nextAt - now))
		if services.ObstacleService then
			services.ObstacleService.onBrace(lurch.k + 1)
		end
	end
	if now >= lurch.nextAt then
		ShipService.lurchNow()
	end
end

-- The final plunge during the launch cinematic: alpha 0..1 eases the ship further down.
function ShipService.beginPlunge()
	if not lurch or not record then
		return
	end
	plunge = {
		from = record.model:GetPivot(),
		to = LurchMath.pivot(lurch.base, lurch.def.MaxSink + 10, math.min(lurch.def.MaxTilt + SK.FinalPlungeTilt, lurch.tilt + SK.FinalPlungeTilt + 6)),
	}
end

function ShipService.stepPlunge(alpha)
	if plunge and record then
		local a = math.clamp(alpha, 0, 1)
		moveShip(plunge.from:Lerp(plunge.to, a * a))
	end
end

function ShipService.stopRun()
	lurch = nil
	plunge = nil
	workspace:SetAttribute("LL_NextLurch", nil)
	workspace:SetAttribute("LL_Tilt", 0)
	workspace:SetAttribute("LL_Sink", 0)
end

-- After a round: scrap the sunk ship and moor a fresh Gull at the dock.
function ShipService.cleanup()
	ShipService.stopRun()
	destroyCurrent()
	shipKey = nil
	ShipService.request(GameConfig.ShipOrder[1])
end

function ShipService.start()
	ShipService.request(GameConfig.ShipOrder[1])
end

return ShipService
