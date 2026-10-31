--[[
	AudioController - every sound on the client.

	* SoundGroups: Effects / Engine / Music / UI, each with a volume setting under Master.
	* play(name or def, position?) plays a 2D or (with a position) 3D one-shot. Empty slots
	  (Id = "") are skipped - so the code is ready the moment an id is pasted in.
	* ENGINE: the Engine loop's pitch follows your speed (and boost); it only plays once
	  AudioAssets.Engine has an Id.
	* Kart events: hop, landing, wall hits, bumps, mini-turbo levels, boosts, pads.
	* Race: countdown beeps, GO, start boost, laps, final lap sting, finish.
	* Music: lobby music, race music, a hotter track on the final lap.
	* World events play their own sound slots (EventController -> playDef).
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local AudioAssets = require(Shared.Config.AudioAssets)
local KartStats = require(Shared.Config.KartStats)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local AudioController = {}

AudioController.Groups = { "Effects", "Engine", "Music", "UI" }

local groups = {}
local lastPlayed = {}
local rng = Random.new()
local loops = {}
local finalLap = false
local MIN_GAP = { UIClick = 0.05, WallHit = 0.25, Bump = 0.2, Land = 0.2, Hop = 0.1, MiniTurbo = 0.1, CountdownBeep = 0.4 }

local function group(name)
	if groups[name] then
		return groups[name]
	end
	local g = Instance.new("SoundGroup")
	g.Name = "CK_" .. name
	g.Volume = 1
	g.Parent = SoundService
	groups[name] = g
	return g
end

function AudioController.applyVolumes()
	local master = ClientState.setting("Master") or 1
	for _, name in ipairs(AudioController.Groups) do
		group(name).Volume = master * (ClientState.setting(name) or 1)
	end
end

local function configured(def)
	if def == nil then
		return false
	end
	if type(def.Layers) == "table" and #def.Layers > 0 then
		return true
	end
	return type(def.Id) == "string" and def.Id ~= ""
end
AudioController.configured = configured

local function layers(def)
	if not configured(def) then
		return {}
	end
	local base = def.Volume or 0.5
	if def.Layers and #def.Layers > 0 then
		local out = {}
		for _, layer in ipairs(def.Layers) do
			table.insert(out, { id = layer.Id, volume = base * (layer.Volume or 1), pitch = (def.Pitch or 1) * (layer.Pitch or 1), delay = layer.Delay or 0 })
		end
		return out
	end
	return { { id = def.Id, volume = base, pitch = def.Pitch or 1, delay = 0 } }
end

local function make(id, volume, pitch, def, parent, name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch * rng:NextNumber(0.95, 1.05)
	sound.Looped = def.Looped == true
	sound.SoundGroup = group(def.Group or "Effects")
	sound.RollOffMaxDistance = def.MaxDistance or 160
	sound.RollOffMinDistance = def.MinDistance or 10
	sound.Parent = parent
	return sound
end

-- One-shot from a def table (event sound slots use this too). Returns the first Sound.
function AudioController.playDef(def, position, name, volumeScale)
	if not configured(def) then
		return nil
	end
	local key = name or tostring(def)
	local now = os.clock()
	if lastPlayed[key] and now - lastPlayed[key] < (MIN_GAP[key] or 0.03) then
		return nil
	end
	lastPlayed[key] = now
	local parent
	local terrain = typeof(position) == "Vector3" and workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		parent = Instance.new("Attachment")
		parent.Name = "CK_Sound"
		parent.WorldPosition = position
		parent.Parent = terrain
	else
		parent = Instance.new("Folder")
		parent.Name = "CK_Sound"
		parent.Parent = SoundService
	end
	local first
	for _, layer in ipairs(layers(def)) do
		local sound = make(layer.id, layer.volume * (volumeScale or 1), layer.pitch, def, parent, key)
		first = first or sound
		if layer.delay > 0 then
			task.delay(layer.delay, function()
				if sound.Parent then
					sound:Play()
				end
			end)
		else
			sound:Play()
		end
	end
	task.delay(def.Duration or 4, function()
		parent:Destroy()
	end)
	return first
end

function AudioController.play(name, position, volumeScale)
	return AudioController.playDef(AudioAssets[name], position, name, volumeScale)
end

function AudioController.loop(key, name, parent)
	local def = AudioAssets[name]
	local existing = loops[key]
	if existing and existing.parent == parent and existing.name == name then
		return existing.sounds[1]
	end
	AudioController.stopLoop(key)
	if not configured(def) or not parent then
		return nil
	end
	local sounds = {}
	for _, layer in ipairs(layers(def)) do
		local sound = make(layer.id, layer.volume, layer.pitch, def, parent, name)
		sound.Looped = true
		sound:Play()
		table.insert(sounds, sound)
	end
	loops[key] = { parent = parent, name = name, sounds = sounds, base = def.Volume or 0.5 }
	return sounds[1]
end

function AudioController.loopLevel(key, fraction, pitch)
	local entry = loops[key]
	if not entry then
		return
	end
	for _, s in ipairs(entry.sounds) do
		s.Volume = entry.base * math.clamp(fraction, 0, 1.5)
		if pitch then
			s.PlaybackSpeed = pitch
		end
	end
end

function AudioController.stopLoop(key)
	local entry = loops[key]
	if entry then
		for _, s in ipairs(entry.sounds) do
			s:Destroy()
		end
		loops[key] = nil
	end
end

function AudioController.playing(key)
	return loops[key] ~= nil
end

function AudioController.musicFor(phase, final)
	if phase == "Racing" or phase == "Countdown" then
		return if final then "FinalLapMusic" else "RaceMusic"
	end
	return "LobbyMusic"
end

-- Engine pitch tied to speed: 0.7 at rest .. 1.6 at top speed (+ a little on boost).
function AudioController.enginePitch(speed, boosting)
	local f = math.clamp(speed / KartStats.TopSpeed, 0, 1.4)
	return 0.7 + f * 0.9 + (if boosting then 0.12 else 0)
end

AudioController.kart = nil -- set by KartController: function() -> state, model

function AudioController.step(_dt)
	local phase = ClientState.phase()
	local music = AudioController.musicFor(phase, finalLap)
	AudioController.loop("Music", music, SoundService)
	local state, model = nil, nil
	if AudioController.kart then
		state, model = AudioController.kart()
	end
	if state and model and model.PrimaryPart then
		local speed = Vector3.new(state.vel.X, 0, state.vel.Z).Magnitude
		AudioController.loop("Engine", "Engine", model.PrimaryPart)
		AudioController.loopLevel("Engine", 0.5 + math.min(1, speed / KartStats.TopSpeed) * 0.6, AudioController.enginePitch(speed, state.boostT > 0))
		if state.drift ~= 0 then
			AudioController.loop("Skid", "DriftSkid", model.PrimaryPart)
		else
			AudioController.stopLoop("Skid")
		end
	else
		AudioController.stopLoop("Engine")
		AudioController.stopLoop("Skid")
	end
	return { music = music, engine = AudioController.playing("Engine") }
end

local KART_SOUNDS = { hop = "Hop", land = "Land", wall = "WallHit", bump = "Bump", driftLevel = "MiniTurbo", pad = "BoostPad", jump = "BoostPad" }

function AudioController.onKartEvents(events)
	for _, e in ipairs(events) do
		local name = KART_SOUNDS[e.name]
		if e.name == "boost" and type(e.value) == "string" and string.sub(e.value, 1, 5) == "drift" then
			name = "Boost"
		elseif e.name == "boost" and e.value == "start" then
			name = "StartBoost"
		end
		if name then
			AudioController.play(name, nil, if e.name == "wall" then math.clamp((e.value or 10) / 60, 0.3, 1) else nil)
		end
	end
end

function AudioController.init()
	AudioController.applyVolumes()
	ClientState.SettingsChanged:Connect(AudioController.applyVolumes)
	Ui.clickHandler = function()
		AudioController.play("UIClick")
	end
	ClientState.KartEvents:Connect(AudioController.onKartEvents)
	ClientState.RaceEvent:Connect(function(kind, info)
		if kind == "lap" then
			AudioController.play(if info and info.final then "FinalLap" else "Lap")
			finalLap = info ~= nil and info.final == true
		elseif kind == "finish" then
			AudioController.play(if info and info.place and info.place <= 3 then "Finish" else "FinishLose")
		elseif kind == "wrongway" and info and info.on then
			AudioController.play("WrongWay")
		elseif kind == "checkpoint" then
			AudioController.play("Checkpoint")
		end
	end)
	ClientState.RaceChanged:Connect(function(state)
		if state.phase ~= "Racing" then
			finalLap = false
		end
	end)
	ClientState.KartRespawned:Connect(function()
		AudioController.play("Respawn")
	end)
	ClientState.KartEffected:Connect(function(kind)
		AudioController.play(if kind == "spinOut" then "SpinOut" else "Knockback")
	end)
	ClientState.ResultsReceived:Connect(function()
		AudioController.play("Coins")
	end)
	ClientState.EventStarted:Connect(function()
		AudioController.play("EventWarning")
	end)
end

return AudioController
