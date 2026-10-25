--[[
	Plays AudioAssets entries. Empty ids are skipped so the game runs with no audio.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local AudioUtil = {}

AudioUtil.volumeScale = 1

function AudioUtil.make(def, parent)
	if type(def) ~= "table" or type(def.Id) ~= "string" or def.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = (def.Volume or 0.5) * AudioUtil.volumeScale
	sound.PlaybackSpeed = def.Pitch or 1
	sound.Looped = def.Looped == true
	if def.MaxDistance then
		sound.RollOffMaxDistance = def.MaxDistance
	end
	sound.Parent = parent or SoundService
	return sound
end

-- Fire-and-forget. `pitchJitter` adds a little variety to repeated sounds.
function AudioUtil.play(def, parent, pitchJitter)
	local sound = AudioUtil.make(def, parent)
	if not sound then
		return nil
	end
	if pitchJitter then
		sound.PlaybackSpeed *= 1 + (math.random() * 2 - 1) * pitchJitter
	end
	sound:Play()
	Debris:AddItem(sound, 6)
	return sound
end

return AudioUtil
