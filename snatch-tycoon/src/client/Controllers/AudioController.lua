--[[
	AudioController - plays AudioAssets entries by key. Empty ids are skipped, so the game
	runs silently until you fill the slots. Respects the Music / SFX settings.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local AudioAssets = require(Shared.Config.AudioAssets)

local ClientState = require(script.Parent.ClientState)

local AudioController = {}

local sfxOn, musicOn = true, true
local music

local function configured(def)
	return def ~= nil and type(def.Id) == "string" and def.Id ~= ""
end

function AudioController.play(key, position)
	local def = AudioAssets[key]
	if not sfxOn or not configured(def) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = (def.Pitch or 1) * (0.95 + math.random() * 0.1)
	local holder
	if typeof(position) == "Vector3" then
		holder = Instance.new("Part")
		holder.Name = "SfxAt"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(position)
		holder.Parent = workspace
		sound.RollOffMaxDistance = 120
		sound.Parent = holder
	else
		sound.Parent = SoundService
	end
	sound:Play()
	local life = def.Duration or 4
	Debris:AddItem(holder or sound, life)
	if def.Duration and not holder then
		task.delay(def.Duration, function()
			if sound.Parent then
				sound:Stop()
			end
		end)
	end
	return sound
end

function AudioController.applySettings(settings)
	if type(settings) ~= "table" then
		return
	end
	sfxOn = settings.Sfx ~= false
	musicOn = settings.Music ~= false
	if music then
		music.Volume = if musicOn then (AudioAssets.Music.Volume or 0.3) else 0
	end
end

function AudioController.init()
	if configured(AudioAssets.Music) then
		music = Instance.new("Sound")
		music.Name = "Music"
		music.SoundId = AudioAssets.Music.Id
		music.Looped = true
		music.Volume = AudioAssets.Music.Volume or 0.3
		music.Parent = SoundService
		music:Play()
	end
	ClientState.Sfx:Connect(function(key, position)
		AudioController.play(key, position)
	end)
	ClientState.ProfileChanged:Connect(function(profile)
		AudioController.applySettings(profile.settings)
	end)
end

return AudioController
