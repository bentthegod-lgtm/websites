--[[
	AudioController - every sound on the client.

	* SoundGroups: Master > Effects / Ambient / Music / UI, each with a volume setting.
	* play(name, position?) plays a 2D or (with a position) 3D one-shot. A slot may be one Id
	  or several Layers (Config/AudioAssets). Empty slots (Id = "") are skipped. Every play
	  gets +-6% pitch and a per-slot minimum gap.
	* Sinking: BRACE (alarm + the ship's horn), every LURCH (a hull groan and a deep impact,
	  props clattering), random creaks between lurches, the engine hum below decks.
	* You: a heartbeat when your oxygen runs low underwater, a splash going under.
	* Music: harbour music in the lobby, a tension bed in the round, the chase layer in the
	  final minute before the lifeboat launches; stings for ESCAPED / LOST AT SEA.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local AudioAssets = require(Shared.Config.AudioAssets)
local Survival = require(Shared.Survival)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local AudioController = {}

AudioController.Groups = { "Effects", "Ambient", "Music", "UI" }

local groups = {}
local lastPlayed = {}
local rng = Random.new()
local loops = {}
local nextCreak = 0
local wasUnder = false
local MIN_GAP = { Pickup = 0.1, PickupRare = 0.1, UIClick = 0.05, SteamHiss = 0.5, Spark = 0.3, Lever = 0.3, Brace = 1, Horn = 1.5, Lurch = 1, Splash = 0.6 }

local function group(name)
	if groups[name] then
		return groups[name]
	end
	local g = Instance.new("SoundGroup")
	g.Name = "LL_" .. name
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

local function make(id, volume, pitch, def, parent, name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch * rng:NextNumber(0.94, 1.06)
	sound.Looped = def.Looped == true
	sound.SoundGroup = group(def.Group or "Effects")
	sound.RollOffMaxDistance = def.MaxDistance or 140
	sound.RollOffMinDistance = def.MinDistance or 8
	sound.Parent = parent
	return sound
end

-- The sounds a slot is made of: { id, volume, pitch, delay } for each layer.
function AudioController.layers(def)
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

-- One-shot. A position makes it 3D. Returns the first Sound (or nil if throttled / empty).
function AudioController.play(name, position, volumeScale)
	local def = AudioAssets[name]
	if not configured(def) then
		return nil
	end
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < (MIN_GAP[name] or 0.03) then
		return nil
	end
	lastPlayed[name] = now
	local parent
	local terrain = typeof(position) == "Vector3" and workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		parent = Instance.new("Attachment")
		parent.Name = "LL_Sound"
		parent.WorldPosition = position
		parent.Parent = terrain
	else
		parent = Instance.new("Folder")
		parent.Name = "LL_Sound"
		parent.Parent = SoundService
	end
	local first
	for _, layer in ipairs(AudioController.layers(def)) do
		local sound = make(layer.id, layer.volume * (volumeScale or 1), layer.pitch, def, parent, name)
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
	local life = def.Duration or 5
	if def.Fade and def.Fade > 0 then
		task.delay(math.max(0, life - def.Fade), function()
			for _, s in ipairs(parent:GetChildren()) do
				if s:IsA("Sound") then
					s.Volume *= 0.35 -- (a quick step down; TweenService would be smoother but costs a tween per layer)
				end
			end
		end)
	end
	task.delay(life, function()
		parent:Destroy()
	end)
	return first
end

-- A looped slot kept under `key` (all its layers); re-parented if the parent changes.
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
	for _, layer in ipairs(AudioController.layers(def)) do
		local sound = make(layer.id, layer.volume, layer.pitch, def, parent, name)
		sound.Looped = true
		sound:Play()
		table.insert(sounds, sound)
	end
	loops[key] = { parent = parent, name = name, sounds = sounds, base = def.Volume or 0.5 }
	return sounds[1]
end

-- Sets a loop's volume as a fraction of its slot's own volume (so loops never hit 1.0).
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


-- The music that should be playing now.
function AudioController.musicFor(inRound, launchIn)
	if not inRound then
		return "LobbyMusic"
	end
	if launchIn and launchIn <= 60 then
		return "FinalMinute"
	end
	return "RoundMusic"
end

local WORLD_3D = { Downed = true, Revive = true, Grapple = true, Flare = true, Lever = true, Bulkhead = true, Valve = true, SteamHiss = true, SteamBurst = true, Spark = true, ChandelierFall = true, Winch = true }

function AudioController.onWorldSound(name, position)
	if type(name) ~= "string" or not AudioAssets[name] then
		return nil
	end
	return AudioController.play(name, if WORLD_3D[name] then position else nil)
end

function AudioController.step(_dt)
	local now = os.clock()
	local inRound = ClientState.inRound()
	local me = ClientState.me()
	local launchAt = workspace:GetAttribute("LL_LaunchAt")
	local launchIn = if launchAt then launchAt - ClientState.serverNow() else nil
	local music = AudioController.musicFor(inRound, launchIn)
	AudioController.loop("Music", music, SoundService)
	AudioController.loop("Waves", "Waves", SoundService)
	if inRound then
		AudioController.loop("Hum", "ShipHum", SoundService)
		if now >= nextCreak then
			nextCreak = now + rng:NextNumber(8, 15)
			AudioController.play("ShipCreak")
		end
	else
		AudioController.stopLoop("Hum")
	end
	-- breath
	local character = ClientState.player().Character
	local head = character and character:FindFirstChild("Head")
	local under = head ~= nil and Survival.headUnderwater(head.CFrame.Position.Y)
	if under and not wasUnder then
		AudioController.play("Splash", head.CFrame.Position)
	elseif not under and wasUnder then
		AudioController.play("Gasp")
	end
	wasUnder = under
	local low = inRound and me.state == "Alive" and under and me.oxygen / math.max(1, me.oxygenMax) < 0.4
	if low then
		AudioController.loop("LowOxygen", "LowOxygen", SoundService)
	else
		AudioController.stopLoop("LowOxygen")
	end
	return { music = music, low = low, under = under }
end

function AudioController.init()
	AudioController.applyVolumes()
	ClientState.SettingsChanged:Connect(AudioController.applyVolumes)
	Ui.clickHandler = function()
		AudioController.play("UIClick")
	end
	ClientState.WorldSound:Connect(AudioController.onWorldSound)
	ClientState.Braced:Connect(function()
		AudioController.play("Brace")
		AudioController.play("Horn")
	end)
	ClientState.Lurched:Connect(function()
		AudioController.play("Lurch")
		AudioController.play("PropSlide")
	end)
	ClientState.Results:Connect(function()
		AudioController.play("Coins")
	end)
	RunService.Heartbeat:Connect(AudioController.step)
end

return AudioController
