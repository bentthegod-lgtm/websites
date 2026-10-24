--[[
	Client audio helper. Plays entries from AudioAssets; empty Ids are skipped, so the game
	works silently until sounds are added.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local AudioAssets = require(Shared.Config.AudioAssets)

local Audio = {}

local loops = {}

local function make(def, parent)
	if not def or def.Id == nil or def.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = def.Pitch or 1
	sound.Looped = def.Looped == true
	sound.Parent = parent or SoundService
	return sound
end

function Audio.play(name, pitchJitter, parent)
	local sound = make(AudioAssets[name], parent)
	if not sound then
		return nil
	end
	if pitchJitter then
		sound.PlaybackSpeed *= 1 + (math.random() - 0.5) * pitchJitter
	end
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	return sound
end

function Audio.loop(name, on)
	if on then
		if not loops[name] then
			loops[name] = make(AudioAssets[name])
			if loops[name] then
				loops[name]:Play()
			end
		end
	elseif loops[name] then
		loops[name]:Destroy()
		loops[name] = nil
	end
end

return Audio
