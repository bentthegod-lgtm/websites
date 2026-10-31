--[[
	EventController - plays world events locally, in sync with the server.

	EventStart { instanceId, id, seed, warnAt, serverStartTime, endAt, zone } arrives; the
	client builds a ctx (its own Maid, a folder, the shared map data, the server clock) and
	calls the event module's play(ctx), then step(ctx, dt) every frame. Every position is a
	function of the server time and the seed, so all clients see the same thing. On
	EventStop (or a local hard timeout if that never arrives) cleanup(ctx) runs and the
	Maid destroys every part. Hits are decided by the server (KartEffect).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Registry = require(Shared.Events.Registry)
local Maid = require(Shared.Maid)
local Rng = require(Shared.Rng)
local GameConfig = require(Shared.Config.GameConfig)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local EffectsController = require(script.Parent.EffectsController)
local KartController = require(script.Parent.KartController)

local EventController = {}

local active = {}
local root

local function rootFolder()
	if not root or not root.Parent then
		root = Instance.new("Folder")
		root.Name = "CK_Events"
		root.Parent = workspace
	end
	return root
end

function EventController.active()
	return active
end

function EventController.onStart(payload)
	if type(payload) ~= "table" or active[payload.instanceId] then
		return nil
	end
	local module = Registry.module(payload.id)
	local data = ClientState.mapData()
	local zone = data.zoneById[payload.zone]
	if not module or not module.Def.implemented or not zone then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = payload.id .. "_" .. tostring(payload.instanceId)
	folder.Parent = rootFolder()
	local maid = Maid.new()
	maid:give(folder)
	local ctx = {
		id = payload.id,
		instanceId = payload.instanceId,
		def = module.Def,
		seed = payload.seed,
		rng = Rng.new(payload.seed),
		zone = zone,
		data = data,
		warnAt = payload.warnAt,
		startAt = payload.serverStartTime,
		endAt = payload.endAt,
		now = ClientState.serverNow,
		maid = maid,
		folder = folder,
		sound = function(slot, position)
			return AudioController.playDef(module.Sounds[slot], position, payload.id .. slot)
		end,
		shake = EffectsController.shake,
		localKart = KartController.state,
	}
	local entry = { module = module, ctx = ctx, hardEnd = payload.endAt + GameConfig.Events.HardTimeoutSlack }
	active[payload.instanceId] = entry
	local ok, err = pcall(module.play, ctx)
	if not ok then
		warn("[ChaosKarts] event " .. payload.id .. " play failed: " .. tostring(err))
		EventController.stop(payload.instanceId)
		return nil
	end
	return entry
end

function EventController.stop(instanceId)
	local entry = active[instanceId]
	if not entry then
		return
	end
	active[instanceId] = nil
	pcall(entry.module.cleanup, entry.ctx)
	entry.ctx.maid:clean()
end

function EventController.step(dt)
	local now = ClientState.serverNow()
	for id, entry in pairs(active) do
		if now >= entry.hardEnd then
			EventController.stop(id)
		else
			local ok, err = pcall(entry.module.step, entry.ctx, dt)
			if not ok then
				warn("[ChaosKarts] event " .. entry.ctx.id .. " step failed: " .. tostring(err))
				EventController.stop(id)
			end
		end
	end
end

function EventController.init()
	ClientState.EventStarted:Connect(EventController.onStart)
	ClientState.EventStopped:Connect(EventController.stop)
	ClientState.RaceChanged:Connect(function(state)
		if state.phase == "Lobby" or state.phase == "Results" then
			for id in pairs(active) do
				EventController.stop(id)
			end
		end
	end)
end

return EventController
