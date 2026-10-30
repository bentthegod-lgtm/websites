--[[
	AudioController - every sound on the client.

	* SoundGroups (Master > Effects / Ambient / Music) driven by Settings.
	* play(name, position?) plays a 2D or 3D one-shot; slots with an empty Id are skipped,
	  so missing audio never blocks gameplay (see Config/AudioAssets).
	* World sounds the server reports (cracks, splashes, chipping, snowballs...) play in 3D.
	* Your own footsteps play locally (the server only tells the monster).
	* The Antlered: a looped breath on its body, a vocal when it starts hunting, a listening
	  click when it stops dead, and a heartbeat that rises as it gets close to you.
	* Ambience: wind (stronger in gusts) and lobby / lake music if you add IDs.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local AudioAssets = require(Shared.Config.AudioAssets)
local GameConfig = require(Shared.Config.GameConfig)

local ClientState = require(script.Parent.ClientState)

local AudioController = {}

local groups = {}
local lastPlayed = {}
local rng = Random.new()
local loops = {}
local stepTimer = 0
local MIN_GAP = { Step = 0.1, Crack = 0.08, Splash = 0.15, Chip = 0.25 }
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
	for _, name in ipairs({ "Effects", "Ambient", "Music" }) do
		group(name).Volume = master * (ClientState.setting(name) or 1)
	end
end

local function configured(def)
	return def ~= nil and type(def.Id) == "string" and def.Id ~= ""
end
AudioController.configured = configured

local function make(def, parent, name, groupName)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = (def.Pitch or 1) * rng:NextNumber(0.94, 1.06)
	sound.Looped = def.Looped == true
	sound.SoundGroup = group(groupName or "Effects")
	sound.RollOffMaxDistance = def.MaxDistance or 140
	sound.RollOffMinDistance = def.MinDistance or 8
	sound.Parent = parent
	return sound
end

function AudioController.play(name, position)
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
	task.delay(5, function()
		if parent:IsA("Attachment") then
			parent:Destroy()
		else
			sound:Destroy()
		end
	end)
	return sound
end

-- A looped sound kept under `key`; replaced if called again with another parent.
function AudioController.loop(key, name, parent, groupName)
	local def = AudioAssets[name]
	local existing = loops[key]
	if existing and existing.Parent == parent then
		return existing
	end
	if existing then
		existing:Destroy()
		loops[key] = nil
	end
	if not configured(def) or not parent then
		return nil
	end
	local sound = make(def, parent, name, groupName)
	sound.Looped = true
	sound:Play()
	loops[key] = sound
	return sound
end

function AudioController.stopLoop(key)
	if loops[key] then
		loops[key]:Destroy()
		loops[key] = nil
	end
end

local WORLD = {
	Crack = "Crack",
	Break = "Splash",
	Splash = "Splash",
	Chip = "Chip",
	Snowball = "Snowball",
	Deliver = "Deliver",
	Thaw = "Thaw",
	Countdown = "Countdown",
}

-- 0..1 how close the monster is to me (1 = right on top of me).
function AudioController.dread(monsterPos, myPos)
	if not monsterPos or not myPos then
		return 0
	end
	local d = (Vector3.new(monsterPos.X, 0, monsterPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
	return math.clamp(1 - (d - 6) / 50, 0, 1)
end

function AudioController.step(dt)
	local root = ClientState.root()
	-- Local footsteps on the ice.
	local me = ClientState.me()
	if root and me.state == "Active" and root.Position.Z > GameConfig.Lake.ShoreZ and not me.inWater then
		local v = root.AssemblyLinearVelocity
		if v and Vector3.new(v.X, 0, v.Z).Magnitude > 2 then
			stepTimer += dt
			if stepTimer >= (STEP_INTERVAL[me.mode or "Walk"] or 0.45) then
				stepTimer = 0
				local def = AudioAssets.Step
				if configured(def) then
					local s = AudioController.play("Step", root.Position)
					if s then
						s.Volume = (def.Volume or 0.25) * (if me.mode == "Sneak" then 0.35 elseif me.mode == "Sprint" then 1.6 else 1)
					end
				end
			end
		end
	end
	-- Monster breath + heartbeat.
	local monster = ClientState.monster()
	local body = monster and monster.PrimaryPart
	local bodyPos = body and monster:GetPivot().Position
	if body then
		AudioController.loop("Breath", "MonsterBreath", body)
	else
		AudioController.stopLoop("Breath")
	end
	local dread = AudioController.dread(bodyPos, root and root.Position)
	if dread > 0.15 and me.state == "Active" then
		local beat = AudioController.loop("Heartbeat", "Heartbeat", SoundService)
		if beat then
			beat.Volume = 0.2 + dread * 0.8
			beat.PlaybackSpeed = 0.9 + dread * 0.6
		end
	else
		AudioController.stopLoop("Heartbeat")
	end
	-- Wind: louder in a gust.
	local wind = AudioController.loop("Wind", "Wind", SoundService, "Ambient")
	if wind then
		wind.Volume = if workspace:GetAttribute("TI_Gust") then 0.8 else 0.3
	end
	local music = if ClientState.inRound() then "LakeMusic" else "LobbyMusic"
	AudioController.loop("Music", music, SoundService, "Music")
end

function AudioController.init()
	AudioController.applyVolumes()
	ClientState.SettingsChanged:Connect(AudioController.applyVolumes)
	ClientState.WorldSound:Connect(function(category, position, extra)
		if category == "Throw" then
			AudioController.play("Snowball", extra or position)
		elseif WORLD[category] then
			AudioController.play(WORLD[category], position)
		end
	end)
	ClientState.MonsterCue:Connect(function(kind, position, userId)
		if kind == "Hunt" or kind == "Wake" then
			AudioController.play("MonsterVocal", position)
			if kind == "Hunt" then
				AudioController.play("MonsterHunt", position)
			end
		elseif kind == "Listen" then
			AudioController.play("MonsterListen", position)
		elseif kind == "Caught" then
			AudioController.play("Caught")
		elseif kind == "Catch" and userId ~= ClientState.player().UserId then
			AudioController.play("MonsterVocal", position)
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
