--[[
	AudioController - every sound on the client.

	* Five SoundGroups (Master > Effects / Ambient / Music / UI) driven by Settings.
	* play(name, position?) plays a 2D or 3D one-shot. Cues with an empty Id are skipped, so
	  missing audio never blocks gameplay.
	* Throttling: each cue has a minimum gap, and a per-window budget stops dozens of
	  simultaneous pickups from stacking into noise (small pickups share a few randomized
	  clinks; heavy and rare ones always get their own sound).
	* Ambient emitters (parts with an "Ambient" attribute) play looped beds near the camera
	  or one-shots at random intervals, positioned in 3D.
	* Music follows the current zone with a fade.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local AudioAssets = require(Shared.Config.AudioAssets)

local ClientState = require(script.Parent.ClientState)

local AudioController = {}

local groups = {}
local lastPlayed = {}
local windowStart, windowCount = 0, 0
local rng = Random.new()
local MIN_GAP = { ClinkLight = 0.05, SnapLight = 0.07, ClunkMedium = 0.09, ShredderCrunch = 0.12 }
local WINDOW, WINDOW_BUDGET = 0.15, 5

local function group(name)
	if groups[name] then
		return groups[name]
	end
	local g = Instance.new("SoundGroup")
	g.Name = "MM_" .. name
	g.Volume = 1
	g.Parent = SoundService
	groups[name] = g
	return g
end

function AudioController.applyVolumes()
	local master = ClientState.setting("Master") or 1
	for _, name in ipairs({ "Effects", "Ambient", "Music", "UI" }) do
		group(name).Volume = master * (ClientState.setting(name) or 1)
	end
end

local function configured(def)
	return def and type(def.Id) == "string" and def.Id ~= ""
end

local function make(def, parent, name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = (def.Pitch or 1) * rng:NextNumber(0.94, 1.06)
	sound.Looped = def.Looped == true
	sound.SoundGroup = group(def.Group or "Effects")
	sound.RollOffMaxDistance = def.MaxDistance or 140
	sound.RollOffMinDistance = def.MinDistance or 10
	sound.Parent = parent
	return sound
end

-- One-shot. `position` (Vector3) makes it 3D. `important` skips the shared budget.
function AudioController.play(name, position, important)
	local def = AudioAssets[name]
	if not configured(def) then
		return nil
	end
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < (MIN_GAP[name] or 0.03) then
		return nil
	end
	if not important then
		if now - windowStart > WINDOW then
			windowStart, windowCount = now, 0
		end
		if windowCount >= WINDOW_BUDGET then
			return nil
		end
		windowCount += 1
	end
	lastPlayed[name] = now
	local parent
	local terrain = position and workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		parent = Instance.new("Attachment")
		parent.WorldPosition = position
		parent.Parent = terrain
	else
		parent = SoundService
	end
	local sound = make(def, parent, name)
	sound:Play()
	task.delay(def.Duration or 4, function()
		if parent:IsA("Attachment") then
			parent:Destroy()
		else
			sound:Destroy()
		end
	end)
	return sound
end

-- A looped sound attached to `parent` (magnet hum, shredder loop). Returns the Sound.
function AudioController.loop(name, parent)
	local def = AudioAssets[name]
	if not configured(def) then
		return nil
	end
	local sound = make(def, parent, name)
	sound.Looped = true
	sound:Play()
	return sound
end

-- Collection sound by weight class (with grouping for floods of small pickups).
function AudioController.collect(audioProfile, position, isLocal)
	if audioProfile == "Light" then
		AudioController.play(if rng:NextNumber() < 0.5 then "ClinkLight" else "SnapLight", if isLocal then nil else position)
	elseif audioProfile == "Medium" then
		AudioController.play("ClunkMedium", if isLocal then nil else position)
		AudioController.play("ChainRattle", if isLocal then nil else position)
	else
		AudioController.play("HeavyImpact", if isLocal then nil else position, true)
		if audioProfile == "Legendary" then
			AudioController.play("RareSting", nil, true)
		end
	end
end

-- Ambient ------------------------------------------------------------------------------

local function startAmbient()
	local world = workspace:FindFirstChild("MagnetMayhemWorld")
	if not world then
		return
	end
	for _, emitter in ipairs(world:GetDescendants()) do
		local name = emitter:IsA("BasePart") and emitter:GetAttribute("Ambient")
		local def = name and AudioAssets[name]
		if configured(def) then
			if def.Looped then
				local sound = make(def, emitter, name)
				sound.RollOffMaxDistance = 160
				sound:Play()
			else
				task.spawn(function()
					while emitter.Parent do
						task.wait(rng:NextNumber(14, 40))
						if emitter.Parent then
							local sound = make(def, emitter, name)
							sound:Play()
							task.delay(6, function()
								sound:Destroy()
							end)
						end
					end
				end)
			end
		end
	end
end

-- Music ----------------------------------------------------------------------------------

local music
local function setMusic(zoneId)
	local name = if zoneId == "MetroWreck" then "MusicMetro" else "MusicRustyard"
	if music and music.Name == name then
		return
	end
	if music then
		local old = music
		TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 }):Play()
		task.delay(1.6, function()
			old:Destroy()
		end)
		music = nil
	end
	local def = AudioAssets[name]
	if configured(def) then
		music = make(def, SoundService, name)
		local target = music.Volume
		music.Volume = 0
		music:Play()
		TweenService:Create(music, TweenInfo.new(2), { Volume = target }):Play()
	end
end

function AudioController.init()
	for _, name in ipairs({ "Effects", "Ambient", "Music", "UI" }) do
		group(name)
	end
	AudioController.applyVolumes()
	ClientState.SettingsChanged:Connect(AudioController.applyVolumes)
	ClientState.ZoneChanged:Connect(setMusic)
	setMusic(ClientState.zone)
	task.defer(startAmbient)
	local Ui = require(script.Parent.Ui)
	Ui.clickHandler = function()
		AudioController.play("Click", nil, true)
	end
end

return AudioController
