--[[
	AudioController - every sound on the client.

	* Five SoundGroups (Master > Effects / Ambient / Music / UI) driven by Settings.
	* play(name, position?) plays a 2D or 3D one-shot. Cues with an empty Id are skipped, so
	  missing audio never blocks gameplay.
	* Throttling: each cue has a minimum gap, and a per-window budget stops a pinball run
	  from stacking impacts into noise (light hits share the budget; heavy impacts,
	  objectives and records always get their own sound).
	* Ambient emitters (parts with an "Ambient" attribute) play looped beds or one-shots
	  at random intervals, positioned in 3D, quieter than gameplay.
	* Music: a lobby bed, and a run track while your own dummy is flying (with fades).
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local AudioAssets = require(Shared.Config.AudioAssets)

local ClientState = require(script.Parent.ClientState)

local AudioController = {}

local groups = {}
local lastPlayed = {}
local windowStart, windowCount = 0, 0
local rng = Random.new()
local MIN_GAP = { ImpactLight = 0.06, ImpactMedium = 0.08, ImpactHeavy = 0.12, BoxCrunch = 0.08, ResultsTally = 0.05 }
local WINDOW, WINDOW_BUDGET = 0.15, 5

local function group(name)
	if groups[name] then
		return groups[name]
	end
	local g = Instance.new("SoundGroup")
	g.Name = "CL_" .. name
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

-- Impact sound by tier (soft pads and metal get their own flavour).
function AudioController.impact(tier, position, soft, metal)
	if soft then
		AudioController.play(if tier == "Light" then "SoftLanding" else "Boing", position)
		return
	end
	if tier == "Heavy" or tier == "Massive" then
		AudioController.play("ImpactHeavy", position, true)
		if metal then
			AudioController.play("ImpactMetal", position, true)
		end
	elseif tier == "Medium" then
		AudioController.play(if metal then "ImpactMetal" else "ImpactMedium", position)
	else
		AudioController.play("ImpactLight", position)
	end
end

-- Ambient ------------------------------------------------------------------------------

local function startAmbient()
	local world = workspace:FindFirstChild("CrashLabFacility")
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
function AudioController.setMusic(name)
	if music and music.Name == name then
		return
	end
	if music then
		local old = music
		TweenService:Create(old, TweenInfo.new(1.2), { Volume = 0 }):Play()
		task.delay(1.3, function()
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
		TweenService:Create(music, TweenInfo.new(1.6), { Volume = target }):Play()
	end
end

function AudioController.init()
	for _, name in ipairs({ "Effects", "Ambient", "Music", "UI" }) do
		group(name)
	end
	AudioController.applyVolumes()
	ClientState.SettingsChanged:Connect(AudioController.applyVolumes)
	AudioController.setMusic("MusicLobby")
	local player = ClientState.player()
	ClientState.RunStarted:Connect(function(userId)
		if userId == player.UserId then
			AudioController.setMusic("MusicRun")
			AudioController.play("Whoosh", nil, true)
		end
	end)
	ClientState.RunEnded:Connect(function(userId)
		if userId == player.UserId then
			AudioController.setMusic("MusicLobby")
		end
	end)
	task.defer(startAmbient)
	local Ui = require(script.Parent.Ui)
	Ui.clickHandler = function()
		AudioController.play("Click", nil, true)
	end
end

return AudioController
