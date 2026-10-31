--[[
	RemoteKarts - everyone else's kart (players and bots), smooth.

	The server broadcasts a Karts snapshot ~15 times a second (stamped with the server
	time). Each kart keeps a small buffer of snapshots and is rendered INTERP_DELAY (~100 ms)
	in the past, Hermite-interpolated between the two snapshots around that time (positions
	+ velocities), yaw along the shortest arc. If the buffer runs dry (packet loss) it
	extrapolates briefly from the last velocity, then holds.

	Models are built from each racer's vehicle (cosmetic only) with a name tag; drift sparks,
	boost flames and ghost flicker come from the replicated flags.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartPhysics = require(Shared.KartPhysics)
local VehicleModels = require(Shared.VehicleModels)

local ClientState = require(script.Parent.ClientState)
local KartController = require(script.Parent.KartController)

local RemoteKarts = {}

local INTERP_DELAY = GameConfig.Net.InterpDelay
local MAX_EXTRAPOLATE = 0.25
local karts = {}
local folder
RemoteKarts.onVisuals = nil -- set by EffectsController: function(rig, flags, speed, dt)

local function myId()
	return "p" .. tostring(ClientState.player().UserId)
end

local function ensureFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "CK_RemoteKarts"
		folder.Parent = workspace
	end
	return folder
end

local function build(id)
	local info = ClientState.racerById(id)
	local entry = { id = id, snaps = {}, info = info }
	local name = if info then info.name else id
	entry.model, entry.rig = VehicleModels.build(info and info.vehicle, {
		name = "Kart_" .. id,
		label = name,
		driverColor = info and info.color,
		labelColor = if info and info.kind == "bot" then { 200, 200, 255 } else { 255, 240, 120 },
		parent = ensureFolder(),
	})
	karts[id] = entry
	return entry
end

function RemoteKarts.onSnapshot(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.k) ~= "table" then
		return
	end
	local mine = myId()
	local seen = {}
	for _, k in ipairs(snapshot.k) do
		if k.id ~= mine then
			seen[k.id] = true
			local entry = karts[k.id] or build(k.id)
			table.insert(entry.snaps, { t = snapshot.t, pos = k.p, vel = k.v, yaw = k.y, flags = k.f, ghost = k.g })
			if #entry.snaps > 12 then
				table.remove(entry.snaps, 1)
			end
			entry.lastSeen = snapshot.t
		end
	end
	for id, entry in pairs(karts) do
		if not seen[id] and snapshot.t - (entry.lastSeen or 0) > 2 then
			entry.model:Destroy()
			karts[id] = nil
		end
	end
end

local function hermite(p0, v0, p1, v1, t, span)
	local t2, t3 = t * t, t * t * t
	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = -2 * t3 + 3 * t2
	local h11 = t3 - t2
	return p0 * h00 + v0 * (h10 * span) + p1 * h01 + v1 * (h11 * span)
end

local function lerpAngle(a, b, t)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- The interpolated state of one kart at server time `t`.
function RemoteKarts.sample(entry, t)
	local snaps = entry.snaps
	if #snaps == 0 then
		return nil
	end
	if t <= snaps[1].t then
		local s = snaps[1]
		return s.pos, s.vel, s.yaw, s.flags
	end
	for i = 1, #snaps - 1 do
		local a, b = snaps[i], snaps[i + 1]
		if t >= a.t and t <= b.t then
			local span = math.max(1e-3, b.t - a.t)
			local u = (t - a.t) / span
			local pos = hermite(a.pos, a.vel, b.pos, b.vel, u, span)
			return pos, a.vel:Lerp(b.vel, u), lerpAngle(a.yaw, b.yaw, u), if u < 0.5 then a.flags else b.flags
		end
	end
	local last = snaps[#snaps]
	local ahead = math.min(t - last.t, MAX_EXTRAPOLATE)
	return last.pos + last.vel * ahead, last.vel, last.yaw, last.flags
end

function RemoteKarts.step(dt)
	local t = ClientState.serverNow() - INTERP_DELAY
	for _, entry in pairs(karts) do
		local pos, vel, yaw, flags = RemoteKarts.sample(entry, t)
		if pos and entry.model.PrimaryPart then
			local look = KartPhysics.forward(yaw)
			local slope = if vel.Magnitude > 5 then math.clamp(vel.Y / math.max(1, Vector3.new(vel.X, 0, vel.Z).Magnitude), -0.6, 0.6) else 0
			local fwd = Vector3.new(look.X, slope, look.Z).Unit
			entry.model.PrimaryPart.CFrame = CFrame.lookAt(pos, pos + fwd)
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local yawRate = if entry.lastYaw then ((yaw - entry.lastYaw + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3) else 0
			entry.lastYaw = yaw
			local drift = 0
			if KartPhysics.hasFlag(flags, KartPhysics.Flags.Drifting) then
				drift = if KartPhysics.hasFlag(flags, KartPhysics.Flags.DriftRight) then 1 else -1
			end
			VehicleModels.animate(entry.rig, { speed = speed, steer = math.clamp(-yawRate / 1.5, -1, 1), drift = drift, squash = 0, dt = dt })
			entry.pos, entry.vel, entry.flags = pos, vel, flags
			if RemoteKarts.onVisuals then
				RemoteKarts.onVisuals(entry.rig, flags, speed, dt)
			end
		end
	end
end

function RemoteKarts.positions()
	local list = {}
	for id, entry in pairs(karts) do
		if entry.pos and not KartPhysics.hasFlag(entry.flags or 0, KartPhysics.Flags.Ghost) then
			table.insert(list, { id = id, pos = entry.pos, vel = entry.vel })
		end
	end
	return list
end

function RemoteKarts.get(id)
	return karts[id]
end

function RemoteKarts.count()
	local n = 0
	for _ in pairs(karts) do
		n += 1
	end
	return n
end

function RemoteKarts.clear()
	for id, entry in pairs(karts) do
		entry.model:Destroy()
		karts[id] = nil
	end
end

function RemoteKarts.init()
	ClientState.KartsSnapshot:Connect(RemoteKarts.onSnapshot)
	ClientState.RaceChanged:Connect(function(state)
		if state.phase == "Lobby" then
			RemoteKarts.clear()
		end
	end)
	KartController.remotePositions = RemoteKarts.positions
end

return RemoteKarts
