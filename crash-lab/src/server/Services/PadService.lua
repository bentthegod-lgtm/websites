--[[
	PadService - the six launch pads on the deck. Clear ownership:
	  * one player per pad, one pad per player;
	  * claim by the pad's ProximityPrompt (E / tap) or the ClaimPad remote (checked for
	    distance), release with LeavePad, by walking far away, or on leaving the game;
	  * a pad can't be released or switched while its owner's launch is charging / running;
	  * the owner's selected machine is built on the pad (MachineModels) and rebuilt when
	    they select another one.
	PadState is broadcast to everyone so pad labels and the launch UI stay in sync.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local MachineConfig = require(Shared.Config.MachineConfig)
local MachineModels = require(Shared.MachineModels)

local PadService = {}

local services
local world
local padOf = {} -- [player] = pad record
local rigs = {} -- [padIndex] = rig from MachineModels
local lastClaim = {}
local CLAIM_RANGE = 30
local AUTO_RELEASE_RANGE = 80

local FREE_COLOR = Color3.fromRGB(80, 210, 120)
local TAKEN_COLOR = Color3.fromRGB(255, 196, 40)

function PadService.init(registry)
	services = registry
end

function PadService.setWorld(newWorld)
	world = newWorld
end

function PadService.padOf(player)
	return padOf[player]
end

function PadService.rig(padIndex)
	return rigs[padIndex]
end

function PadService.pads()
	return world.pads
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function buildMachine(pad, machineId)
	pad.slot:ClearAllChildren()
	local model, rig = MachineModels.build(machineId, pad.cframe)
	model.Parent = pad.slot
	rigs[pad.index] = rig
	pad.machineId = machineId
	return rig
end

function PadService.state()
	local list = {}
	for _, pad in ipairs(world.pads) do
		table.insert(list, {
			index = pad.index,
			userId = pad.owner and pad.owner.UserId or nil,
			name = pad.owner and pad.owner.DisplayName or nil,
			machineId = pad.machineId,
			state = services.LaunchService.padStatus(pad),
			readyAt = pad.owner and services.LaunchService.readyAt(pad.owner) or nil,
		})
	end
	return list
end

function PadService.broadcast()
	services.Remotes.PadState:FireAllClients(PadService.state())
end

local function updateLabel(pad)
	if pad.owner then
		pad.ownerLabel.Text = string.upper(pad.owner.DisplayName) .. "  -  " .. MachineConfig.ById[pad.machineId].Short
		pad.ownerLabel.TextColor3 = TAKEN_COLOR
		pad.glow.Color = TAKEN_COLOR
		pad.prompt.Enabled = false
	else
		pad.ownerLabel.Text = "FREE  -  PRESS E"
		pad.ownerLabel.TextColor3 = FREE_COLOR
		pad.glow.Color = FREE_COLOR
		pad.prompt.Enabled = true
	end
end

function PadService.claim(player, index)
	local data = services.DataService.getProfile(player)
	if not data then
		return false, "Your lab data is still loading."
	end
	local pad = type(index) == "number" and world.pads[math.floor(index)]
	if not pad then
		return false, "Unknown pad."
	end
	if pad.owner == player then
		return true
	end
	if pad.owner then
		return false, "Pad " .. pad.index .. " is in use by " .. pad.owner.DisplayName .. "."
	end
	local root = rootOf(player)
	if not root or (root.Position - pad.cframe.Position).Magnitude > CLAIM_RANGE then
		return false, "Walk up to the pad first."
	end
	if padOf[player] then
		local ok, message = PadService.release(player)
		if not ok then
			return false, message
		end
	end
	pad.owner = player
	padOf[player] = pad
	buildMachine(pad, data.Selected)
	updateLabel(pad)
	-- Stand the owner behind their launcher, facing down the course.
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(pad.stand)
	end
	services.QuestService.tutorialEvent(player, "ClaimPad")
	PadService.broadcast()
	return true, "Pad " .. pad.index .. " is yours. Configure your launch and press LAUNCH!"
end

function PadService.release(player, force)
	local pad = padOf[player]
	if not pad then
		return true
	end
	if not force and services.LaunchService.isBusy(player) then
		return false, "You can't leave the pad during a launch."
	end
	pad.owner = nil
	padOf[player] = nil
	pad.slot:ClearAllChildren()
	rigs[pad.index] = nil
	pad.machineId = nil
	updateLabel(pad)
	PadService.broadcast()
	return true, "You left pad " .. pad.index .. "."
end

function PadService.refreshMachine(player)
	local pad = padOf[player]
	local data = services.DataService.getProfile(player)
	if pad and data then
		buildMachine(pad, data.Selected)
		updateLabel(pad)
		PadService.broadcast()
	end
end

function PadService.onPlayerRemoving(player)
	PadService.release(player, true)
	lastClaim[player] = nil
end

-- Releases pads whose owner wandered far away (and isn't launching).
function PadService.checkDistances()
	for player, pad in pairs(padOf) do
		local root = rootOf(player)
		if not services.LaunchService.isBusy(player) and (not root or (root.Position - pad.cframe.Position).Magnitude > AUTO_RELEASE_RANGE) then
			PadService.release(player)
			services.Remotes.Notify:FireClient(player, "You walked away, so pad " .. pad.index .. " was freed for others.", "info")
		end
	end
end

function PadService.start()
	for _, pad in ipairs(world.pads) do
		updateLabel(pad)
		pad.prompt.Triggered:Connect(function(player)
			local ok, message = PadService.claim(player, pad.index)
			if message then
				services.Remotes.Notify:FireClient(player, message, if ok then "good" else "error")
			end
		end)
	end
	local remotes = services.Remotes
	remotes.ClaimPad.OnServerEvent:Connect(function(player, index)
		local t = os.clock()
		if lastClaim[player] and t - lastClaim[player] < 0.5 then
			return
		end
		lastClaim[player] = t
		local ok, message = PadService.claim(player, index)
		if message then
			remotes.Notify:FireClient(player, message, if ok then "good" else "error")
		end
	end)
	remotes.LeavePad.OnServerEvent:Connect(function(player)
		local ok, message = PadService.release(player)
		if message then
			remotes.Notify:FireClient(player, message, if ok then "info" else "error")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			PadService.checkDistances()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
	end)
end

return PadService
