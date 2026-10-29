--[[
	AudioController - every sound on the client.

	* Groups: Effects / Ambient / UI / Music, each scaled by its volume setting and Master.
	* play(key, { position = Vector3 }) plays a one-shot (3D when a position is given) with
	  a little random pitch variation; the same key can't stack more than a few times per
	  fraction of a second (a magnet pulling 8 bills plays a few clinks, not 8 at once).
	* Ambience follows the depth the character is on: 2D beds (ventilation, hum, machinery)
	  from AudioAssets.Ambience, occasional one-shots at random intervals, and 3D loops on
	  the AmbientEmitter parts each theme placed. Music slots are empty until assets are
	  added (see POLISH.md) and simply stay silent.
	Empty Ids are skipped, so missing audio never breaks anything.
]]

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local AudioAssets = require(Shared.Config.AudioAssets)
local DepthConfig = require(Shared.Config.DepthConfig)

local ClientState = require(script.Parent.ClientState)

local AudioController = {}

local folder
local beds = {}
local emitters = {}
local music
local currentDepth
local lastPlay = {}
local recent = {}
local nextOneShot = 0
local rng = Random.new()

local function groupVolume(group)
	local master = ClientState.setting("Master")
	local g = ClientState.setting(group)
	return (if type(master) == "number" then master else 1) * (if type(g) == "number" then g else 1)
end

function AudioController.volumeFor(def, scale)
	return def.Volume * groupVolume(def.Group) * (scale or 1)
end

local function newSound(def, parent)
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = AudioController.volumeFor(def)
	s.PlaybackSpeed = def.Pitch or 1
	s.Looped = def.Looped == true
	s.Parent = parent
	return s
end

-- One-shot. Returns the Sound (or nil when skipped: empty id, throttled).
function AudioController.play(key, opts)
	opts = opts or {}
	local def = AudioAssets.Sounds[key]
	if not def or def.Id == "" then
		return nil
	end
	local now = os.clock()
	recent[key] = recent[key] or {}
	local list = recent[key]
	while #list > 0 and now - list[1] > 0.25 do
		table.remove(list, 1)
	end
	if #list >= (opts.maxStack or 3) or (lastPlay[key] and now - lastPlay[key] < 0.04) then
		return nil
	end
	table.insert(list, now)
	lastPlay[key] = now
	local parent = folder
	local anchor
	if opts.position then
		anchor = Instance.new("Attachment")
		anchor.WorldPosition = opts.position
		anchor.Parent = Workspace.Terrain
		parent = anchor
	end
	local s = newSound(def, parent)
	s.Volume = AudioController.volumeFor(def, opts.volume)
	s.PlaybackSpeed = (def.Pitch or 1) * (opts.pitch or 1) * (1 + (def.PitchVar or 0) * (rng:NextNumber() * 2 - 1))
	if anchor then
		s.RollOffMaxDistance = opts.maxDistance or 90
		s.RollOffMinDistance = 8
	end
	s:Play()
	-- (TimeLength is 0 until a sound has loaded, so one-shots get a fixed lifetime.)
	task.delay(opts.lifetime or 6, function()
		s:Destroy()
		if anchor then
			anchor:Destroy()
		end
	end)
	return s
end

function AudioController.loop(key)
	local def = AudioAssets.Sounds[key]
	if not def or def.Id == "" then
		return nil
	end
	local s = newSound(def, folder)
	s.Looped = true
	s:Play()
	return s
end

local function clearAmbience()
	for _, s in pairs(beds) do
		s:Destroy()
	end
	table.clear(beds)
	for _, s in ipairs(emitters) do
		s:Destroy()
	end
	table.clear(emitters)
	if music then
		music:Destroy()
		music = nil
	end
end

function AudioController.setDepth(depth)
	if depth == currentDepth then
		return
	end
	currentDepth = depth
	clearAmbience()
	local def = DepthConfig.get(depth)
	local profile = def and AudioAssets.Ambience[def.Ambient]
	if not profile then
		return
	end
	for key, scale in pairs(profile.Loops) do
		local s = AudioController.loop(key)
		if s then
			s:SetAttribute("Scale", scale * 0.6)
			s.Volume = AudioController.volumeFor(AudioAssets.Sounds[key], scale * 0.6)
			beds[key] = s
		end
	end
	music = AudioController.loop(profile.Music)
	-- 3D loops on this floor's emitters.
	local vault = Workspace:FindFirstChild("Vault")
	local floorFolder = vault and vault:FindFirstChild(def.Code)
	if floorFolder then
		for _, d in ipairs(floorFolder:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("AmbientSound") then
				local sdef = AudioAssets.Sounds[d:GetAttribute("AmbientSound")]
				if sdef and sdef.Id ~= "" then
					local s = newSound(sdef, d)
					s.Looped = true
					s.RollOffMaxDistance = 70
					s.RollOffMinDistance = 10
					s:Play()
					table.insert(emitters, s)
				end
			end
		end
	end
	nextOneShot = os.clock() + rng:NextNumber(profile.Gap[1], profile.Gap[2])
end

function AudioController.refreshVolumes()
	for key, s in pairs(beds) do
		s.Volume = AudioController.volumeFor(AudioAssets.Sounds[key], s:GetAttribute("Scale") or 1)
	end
	for _, s in ipairs(emitters) do
		local parent = s.Parent
		local key = parent and parent:GetAttribute("AmbientSound")
		if key and AudioAssets.Sounds[key] then
			s.Volume = AudioController.volumeFor(AudioAssets.Sounds[key])
		end
	end
end

-- Called every frame by EffectsController (cheap: one-shot timer only).
function AudioController.step()
	if not currentDepth or os.clock() < nextOneShot then
		return
	end
	local def = DepthConfig.get(currentDepth)
	local profile = AudioAssets.Ambience[def.Ambient]
	local root = ClientState.root()
	if profile and root then
		local key = profile.OneShots[rng:NextInteger(1, #profile.OneShots)]
		local offset = Vector3.new(rng:NextNumber(-40, 40), rng:NextNumber(8, 20), rng:NextNumber(-40, 40))
		AudioController.play(key, { position = root.CFrame.Position + offset, maxDistance = 140 })
		nextOneShot = os.clock() + rng:NextNumber(profile.Gap[1], profile.Gap[2])
	end
end

function AudioController.init()
	folder = Instance.new("Folder")
	folder.Name = "VaultAudio"
	folder.Parent = SoundService
	ClientState.SettingsChanged:Connect(AudioController.refreshVolumes)
	ClientState.DepthChanged:Connect(AudioController.setDepth)
end

return AudioController
