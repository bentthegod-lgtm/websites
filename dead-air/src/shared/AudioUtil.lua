--[[
	AudioUtil - safe sound creation from AudioAssets entries.
	Entries with an empty Id return nil, so callers never play an unconfigured asset.

	cue(): designed sounds. An entry may list Layers - built-in Roblox client sounds, each
	pitched and run through engine effects (distortion, tremolo, reverb, echo, pitch shift,
	EQ) and mixed together. If the entry's own Id is set (your uploaded asset), that single
	sound is used instead of the layers.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
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
		if def and def.Layers then
			return AudioUtil.cueAt(def, position, groupName)
		end
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
		if def and def.Layers then
			return AudioUtil.cue2D(def, groupName)
		end
		return nil
	end
	local sound = AudioUtil.make(def, SoundService, groupName, overrides)
	sound:Play()
	Debris:AddItem(sound, 10)
	return sound
end

---------------------------------------------------------------------------------------------
-- Layered cues
---------------------------------------------------------------------------------------------

local Cue = {}
Cue.__index = Cue

local function addEffects(sound, layer)
	local priority = 10
	local function effect(className, props)
		local e = Instance.new(className)
		for k, v in pairs(props) do
			e[k] = v
		end
		e.Priority = priority
		priority -= 1
		e.Parent = sound
	end
	if layer.Distortion then
		effect("DistortionSoundEffect", { Level = layer.Distortion })
	end
	if layer.Octave then
		effect("PitchShiftSoundEffect", { Octave = layer.Octave })
	end
	if layer.Tremolo then
		effect("TremoloSoundEffect", { Frequency = layer.Tremolo[1], Depth = layer.Tremolo[2], Duty = layer.Tremolo[3] or 0.5 })
	end
	if layer.LowPass then
		effect("EqualizerSoundEffect", { HighGain = -layer.LowPass, MidGain = -layer.LowPass * 0.3, LowGain = 2 })
	end
	if layer.Echo then
		effect("EchoSoundEffect", { Delay = layer.Echo[1], Feedback = layer.Echo[2], WetLevel = layer.Echo[3] or -4, DryLevel = 0 })
	end
	if layer.Reverb then
		effect("ReverbSoundEffect", { DecayTime = layer.Reverb, Density = 1, Diffusion = 1, WetLevel = -2, DryLevel = -1 })
	end
end

-- Creates a cue under `parent` (a BasePart/Attachment for 3D, a Folder in SoundService for
-- 2D). Returns nil when the entry has neither an Id nor Layers.
function AudioUtil.cue(def, parent, groupName)
	if not def then
		return nil
	end
	local custom = AudioUtil.isConfigured(def)
	local layers
	if custom then
		layers = { { Id = def.Id, Volume = 1, Pitch = def.Pitch or 1 } }
	elseif def.Layers then
		layers = def.Layers
	else
		return nil
	end
	local self = setmetatable({ def = def, layers = layers, sounds = {}, scale = 1 }, Cue)
	for _, layer in ipairs(layers) do
		local sound = Instance.new("Sound")
		sound.Name = "Cue"
		sound.SoundId = layer.Id
		sound.PlaybackSpeed = layer.Pitch or 1
		sound.Looped = def.Looped == true
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = def.MinDistance or 8
		sound.RollOffMaxDistance = def.MaxDistance or 90
		sound.Volume = 0
		if groupName then
			sound.SoundGroup = AudioUtil.group(groupName)
		end
		if not custom then
			addEffects(sound, layer)
		end
		-- Sounds must be direct children of a part/attachment to be positional.
		sound.Parent = parent
		table.insert(self.sounds, sound)
	end
	return self
end

function Cue:_volume(i)
	return (self.layers[i].Volume or 1) * (self.def.Volume or 1) * self.scale
end

-- Plays every layer (each from its own start offset / delay); one-shots fade out.
function Cue:Play(scale)
	self.scale = scale or self.scale
	local token = {}
	self.token = token
	for i, sound in ipairs(self.sounds) do
		local layer = self.layers[i]
		local function start()
			if self.token ~= token or not sound.Parent then
				return
			end
			sound.TimePosition = layer.Start or 0
			sound.Volume = self:_volume(i)
			sound:Play()
		end
		if layer.Delay then
			task.delay(layer.Delay, start)
		else
			start()
		end
	end
	local duration = self.def.Duration
	if duration and not self.def.Looped then
		local fade = self.def.Fade or 0.4
		task.delay(math.max(0, duration - fade), function()
			if self.token ~= token then
				return
			end
			for _, sound in ipairs(self.sounds) do
				if sound.Parent then
					TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 }):Play()
				end
			end
			task.delay(fade, function()
				if self.token == token then
					self:Stop()
				end
			end)
		end)
	end
	return self
end

function Cue:Stop()
	self.token = nil
	for _, sound in ipairs(self.sounds) do
		if sound.Parent then
			sound:Stop()
		end
	end
end

-- For looped cues: scale the live volume (0 = silent).
function Cue:SetVolume(scale)
	self.scale = scale
	for i, sound in ipairs(self.sounds) do
		sound.Volume = self:_volume(i)
	end
end

function AudioUtil.cueAt(def, position, groupName, scale)
	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position
	local cue = AudioUtil.cue(def, attachment, groupName)
	if not cue then
		attachment:Destroy()
		return nil
	end
	cue:Play(scale)
	Debris:AddItem(attachment, (def.Duration or 6) + 3)
	return cue
end

function AudioUtil.cue2D(def, groupName, scale)
	local holder = Instance.new("Folder")
	holder.Name = "DA_Cue2D"
	holder.Parent = SoundService
	local cue = AudioUtil.cue(def, holder, groupName)
	if not cue then
		holder:Destroy()
		return nil
	end
	cue:Play(scale)
	Debris:AddItem(holder, (def.Duration or 6) + 3)
	return cue
end

return AudioUtil
