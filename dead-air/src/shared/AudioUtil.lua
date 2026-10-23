--[[
	AudioUtil - safe sound creation from AudioAssets entries.
	Entries with an empty Id return nil, so callers never play an unconfigured asset.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AudioUtil = {}

local groups = {}

function AudioUtil.group(name)
	if groups[name] and groups[name].Parent then
		return groups[name]
	end
	local group = SoundService:FindFirstChild("DA_" .. name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = "DA_" .. name
		group.Volume = 1
		group.Parent = SoundService
	end
	groups[name] = group
	return group
end

function AudioUtil.isConfigured(def)
	return def ~= nil and type(def.Id) == "string" and def.Id ~= ""
end

-- Creates (but does not play) a Sound. Returns nil when the entry has no asset.
function AudioUtil.make(def, parent, groupName, overrides)
	if not AudioUtil.isConfigured(def) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = (overrides and overrides.Volume) or def.Volume or 0.5
	sound.PlaybackSpeed = (overrides and overrides.Pitch) or def.Pitch or 1
	sound.Looped = def.Looped == true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = def.MinDistance or 6
	sound.RollOffMaxDistance = def.MaxDistance or 90
	if groupName then
		sound.SoundGroup = AudioUtil.group(groupName)
	end
	sound.Parent = parent
	return sound
end

-- One-shot 3D sound at a world position.
function AudioUtil.playAt(def, position, groupName, overrides)
	if not AudioUtil.isConfigured(def) then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position
	local sound = AudioUtil.make(def, attachment, groupName, overrides)
	sound:Play()
	Debris:AddItem(attachment, 8)
	return sound
end

-- One-shot 2D sound (parented to SoundService plays non-positionally on the client).
function AudioUtil.play2D(def, groupName, overrides)
	if not AudioUtil.isConfigured(def) then
		return nil
	end
	local sound = AudioUtil.make(def, SoundService, groupName, overrides)
	sound:Play()
	Debris:AddItem(sound, 10)
	return sound
end

return AudioUtil
