--[[
	LightingController - per-arena lighting while you are in (or watching) the arena, the
	bright sky look in the lobby, plus lobby / battle music (empty slots until you add audio).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local ArenaConfig = require(Shared.Config.ArenaConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)

local ClientState = require(script.Parent.ClientState)
local SpectateController = require(script.Parent.SpectateController)

local LightingController = {}

local player = Players.LocalPlayer
local applied
local lobbyMusic, battleMusic

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

function LightingController.apply(spec)
	local info = TweenInfo.new(1.2)
	TweenService:Create(Lighting, info, {
		ClockTime = spec.ClockTime,
		Brightness = spec.Brightness,
		Ambient = rgb(spec.Ambient),
		OutdoorAmbient = rgb(spec.Ambient),
		FogColor = rgb(spec.Fog),
		FogEnd = spec.FogEnd,
	}):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = spec.Atmosphere
		atmosphere.Color = rgb(spec.Fog)
	end
end

function LightingController.update()
	local theme = workspace:GetAttribute("RR_Theme")
	local watching = ClientState.status() == "Arena" or SpectateController.active
	local key = if theme and watching and ArenaConfig.Themes[theme] then theme else "Lobby"
	if key ~= applied then
		applied = key
		LightingController.apply(if key == "Lobby" then ArenaConfig.Lobby.Lighting else ArenaConfig.Themes[key].Lighting)
	end
	local battle = ClientState.status() == "Arena"
	if lobbyMusic then
		lobbyMusic.Playing = not battle
	end
	if battleMusic then
		battleMusic.Playing = battle
	end
end

function LightingController.init()
	lobbyMusic = AudioUtil.make(AudioAssets.LobbyMusic)
	battleMusic = AudioUtil.make(AudioAssets.BattleMusic)
	workspace:GetAttributeChangedSignal("RR_Theme"):Connect(LightingController.update)
	player:GetAttributeChangedSignal("RR_Status"):Connect(LightingController.update)
	ClientState.MatchChanged:Connect(LightingController.update)
	-- Cheap poll so starting / stopping spectating switches the look too.
	RunService.Heartbeat:Connect(LightingController.update)
	ClientState.ProfileChanged:Connect(function(profile)
		local music = profile and profile.settings and profile.settings.Music or 0.5
		for _, sound in ipairs({ lobbyMusic, battleMusic }) do
			if sound then
				sound.Volume = AudioAssets.LobbyMusic.Volume * music * 2
			end
		end
	end)
	LightingController.update()
end

return LightingController
