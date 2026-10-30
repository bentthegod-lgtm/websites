--[[
	AudioController - every sound on the client.

	* SoundGroups: Master > Effects / Ambient / Music / UI, each with a volume setting.
	* play(name, position?) plays a 2D or (with a position) 3D one-shot. A slot may be one Id
	  or several Layers played together (see Config/AudioAssets). Every play gets +-6% pitch
	  variation and a per-slot minimum gap, so nothing machine-guns.
	* World sounds the server reports (cracks, breaks, splashes, chips, deliveries, the sled
	  horn...) play in 3D where they happened. Your own footsteps play locally.
	* The Antlered (Presence cues by distance): a distant call now and then when it's far;
	  breathing (3D, on its body) and crunching steps when it's near; your heartbeat when
	  it's within ~30 studs; the spotted sting + chase layer when it hunts YOU; a tension
	  bed while you're out on the ice.
	* Ambience: wind (with a low hum under it), the whiteout gust over it, brazier crackle
	  in 3D at each fire, lobby music at camp. Loops never sit at full volume.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local AudioAssets = require(Shared.Config.AudioAssets)
local GameConfig = require(Shared.Config.GameConfig)
local Presence = require(Shared.Presence)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local AudioController = {}

AudioController.Groups = { "Effects", "Ambient", "Music", "UI" }

local groups = {}
local lastPlayed = {}
local rng = Random.new()
local loops = {}
local stepTimer = 0
local monsterStepTimer = 0
local lastMonsterPos = nil
local nextCallAt = 0
local wasHuntingMe = false
local braziers = {}
local brazierScanAt = -math.huge
local MIN_GAP = { Step = 0.1, Crack = 0.12, Break = 0.2, Splash = 0.2, Chip = 0.25, UIClick = 0.05, Pickup = 0.15, MonsterStep = 0.25, Horn = 1.5, Spotted = 6 }
local STEP_INTERVAL = { Sneak = 0.7, Walk = 0.45, Sprint = 0.3 }

local function group(name)
	if groups[name] then
		return groups[name]
	end
	local g = Instance.new("SoundGroup")
	g.Name = "TI_" .. name
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
		parent.Name = "TI_Sound"
		parent.WorldPosition = position
		parent.Parent = terrain
	else
		parent = Instance.new("Folder")
		parent.Name = "TI_Sound"
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

local WORLD = {
	Crack = "Crack",
	Break = "Break",
	Splash = "Splash",
	Chip = "Chip",
	Snowball = "Snowball",
	Deliver = "Deliver",
	Thaw = "Thaw",
	Countdown = "Countdown",
	Horn = "Horn",
}

-- Kept for older callers / tests: 0..1 how close the monster is to me.
function AudioController.dread(monsterPos, myPos)
	if not monsterPos or not myPos then
		return 0
	end
	local d = (Vector3.new(monsterPos.X, 0, monsterPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
	return Presence.vignette(d)
end

local function scanBraziers()
	braziers = {}
	local lake = ClientState.lake()
	if lake then
		for _, d in ipairs(lake:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Brazier" and d.PrimaryPart then
				table.insert(braziers, d.PrimaryPart)
			end
		end
	end
	local worldFolder = workspace:FindFirstChild("ThinIceWorld")
	local camp = worldFolder and worldFolder:FindFirstChild("Lobby") and worldFolder.Lobby:FindFirstChild("Campfire")
	if camp and camp.PrimaryPart then
		table.insert(braziers, camp.PrimaryPart)
	end
end

function AudioController.step(dt)
	local root = ClientState.root()
	local me = ClientState.me()
	local now = os.clock()
	local inRound = ClientState.inRound()
	-- Local footsteps on the ice.
	if root and me.state == "Active" and root.Position.Z > GameConfig.Lake.ShoreZ and not me.inWater then
		local v = root.AssemblyLinearVelocity
		if v and Vector3.new(v.X, 0, v.Z).Magnitude > 2 then
			stepTimer += dt
			if stepTimer >= (STEP_INTERVAL[me.mode or "Walk"] or 0.45) then
				stepTimer = 0
				AudioController.play("Step", root.Position, if me.mode == "Sneak" then 0.35 elseif me.mode == "Sprint" then 1.5 else 1)
			end
		end
	end

	-- The Antlered.
	local info = ClientState.monsterInfo()
	local cues = Presence.cues(info and info.distance, info and info.state, info and info.huntingMe)
	local body = info and info.model.PrimaryPart
	if body and cues.breath then
		AudioController.loop("Breath", "MonsterBreath", body)
	else
		AudioController.stopLoop("Breath")
	end
	if info and cues.steps then
		local moved = if lastMonsterPos then (info.position - lastMonsterPos).Magnitude else 0
		if moved > 0.02 then
			monsterStepTimer += dt
			if monsterStepTimer >= 0.55 then
				monsterStepTimer = 0
				AudioController.play("MonsterStep", info.position)
			end
		end
	end
	lastMonsterPos = info and info.position
	if info and cues.call and now >= nextCallAt then
		if nextCallAt > 0 then
			AudioController.play("MonsterCall", info.position)
		end
		nextCallAt = Presence.nextCallAt(now, rng)
	end
	if cues.heartbeat and me.state == "Active" then
		AudioController.loop("Heartbeat", "Heartbeat", SoundService)
		AudioController.loopLevel("Heartbeat", 0.35 + cues.vignette * 0.65, Presence.heartRate(info.distance))
	else
		AudioController.stopLoop("Heartbeat")
	end
	if cues.chase and not wasHuntingMe then
		AudioController.play("Spotted")
	end
	wasHuntingMe = cues.chase
	if cues.chase and me.state == "Active" then
		AudioController.loop("Chase", "Chase", SoundService)
	else
		AudioController.stopLoop("Chase")
	end

	-- Ambience: wind + hum, the whiteout over it, fires.
	local gust = workspace:GetAttribute("TI_Gust") == true
	AudioController.loop("Wind", "Wind", SoundService)
	AudioController.loop("WindHum", "WindHum", SoundService)
	local farOut = if root then math.clamp((root.Position.Z - GameConfig.Lake.ShoreZ) / 300, 0, 1) else 0
	AudioController.loopLevel("Wind", 0.6 + farOut * 0.5)
	if gust and inRound then
		AudioController.loop("Gust", "GustWind", SoundService)
	else
		AudioController.stopLoop("Gust")
	end
	if now - brazierScanAt > 3 then
		brazierScanAt = now
		scanBraziers()
	end
	-- Only the nearest fire crackles (3D) - one loop, not one per brazier.
	local nearest, best = nil, 40
	for _, part in ipairs(braziers) do
		if part.Parent and root then
			local d = (part.CFrame.Position - root.Position).Magnitude
			if d < best then
				nearest, best = part, d
			end
		end
	end
	if nearest then
		AudioController.loop("Fire", "BrazierCrackle", nearest)
	else
		AudioController.stopLoop("Fire")
	end
	-- Music: lobby at camp, the tension bed out on the ice (ducked under the chase layer).
	local music = if inRound then "LakeMusic" else "LobbyMusic"
	AudioController.loop("Music", music, SoundService)
	AudioController.loopLevel("Music", if cues.chase then 0.35 else 1)
	return cues
end

function AudioController.init()
	AudioController.applyVolumes()
	ClientState.SettingsChanged:Connect(AudioController.applyVolumes)
	Ui.clickHandler = function()
		AudioController.play("UIClick")
	end
	ClientState.WorldSound:Connect(function(category, position, extra)
		if category == "Throw" then
			AudioController.play("Snowball", extra or position)
		elseif WORLD[category] then
			AudioController.play(WORLD[category], position)
		end
	end)
	ClientState.MonsterCue:Connect(function(kind, position, userId)
		if kind == "Wake" or (kind == "Catch" and userId ~= ClientState.player().UserId) then
			AudioController.play("MonsterVocal", position)
		elseif kind == "Hunt" then
			AudioController.play("MonsterHunt", position)
		elseif kind == "Listen" then
			AudioController.play("MonsterListen", position)
		elseif kind == "Caught" then
			AudioController.play("Caught", nil, if ClientState.setting("ScareEffects") == false then 0.4 else 1)
		end
	end)
	ClientState.Notified:Connect(function(_, kind)
		if kind == "good" then
			AudioController.play("Pickup") -- a soft chime for good news (refills, thaws, purchases)
		end
	end)
	ClientState.Announced:Connect(function(text)
		if string.find(text, "ALL CORES", 1, true) then
			AudioController.play("AllCores")
		end
	end)
	ClientState.Results:Connect(function(summary)
		AudioController.play(if summary.outcome == "Escaped" then "Escape" else "Fail")
	end)
	RunService.RenderStepped:Connect(AudioController.step)
end

return AudioController
