--[[
	FrameLoop - one RenderStepped pass in a fixed order: your kart (physics + send), the
	remote karts (interpolation), effects, camera, world events, audio, then the HUD and
	the gantry lights. Main.client connects it; the harness calls step() directly.
]]

local KartController = require(script.Parent.KartController)
local RemoteKarts = require(script.Parent.RemoteKarts)
local EffectsController = require(script.Parent.EffectsController)
local CameraController = require(script.Parent.CameraController)
local EventController = require(script.Parent.EventController)
local AudioController = require(script.Parent.AudioController)
local HudController = require(script.Parent.HudController)

local FrameLoop = {}

FrameLoop.ORDER = { "KartController", "RemoteKarts", "EffectsController", "CameraController", "EventController", "AudioController", "HudController" }

local function safe(name, fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		FrameLoop.errors = (FrameLoop.errors or 0) + 1
		if (FrameLoop.errors or 0) < 20 then
			warn("[ChaosKarts] " .. name .. " frame error: " .. tostring(result))
		end
		return nil
	end
	return result
end

function FrameLoop.step(dt)
	dt = math.clamp(dt, 0, 0.1)
	local out = {}
	out.events = safe("KartController", KartController.step, dt)
	safe("RemoteKarts", RemoteKarts.step, dt)
	out.speedLines = safe("EffectsController", EffectsController.step, dt)
	out.camera = safe("CameraController", CameraController.step, dt)
	safe("EventController", EventController.step, dt)
	out.audio = safe("AudioController", AudioController.step, dt)
	safe("HudController", HudController.tick)
	out.lights = safe("HudController", HudController.worldLights)
	return out
end

function FrameLoop.init()
	AudioController.kart = function()
		return KartController.state(), KartController.model()
	end
end

return FrameLoop
