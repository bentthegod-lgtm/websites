--[[
	LaunchService - validates launch requests and runs the charge -> fire sequence.

	A launch is accepted only if ALL of these hold (checked on the server):
	  * the player's profile is loaded and they own a pad;
	  * the requested machine is the one they own and have selected;
	  * they have no launch charging and no dummy in flight (one run per player);
	  * the machine's cooldown has passed (server clock) and the rate limit allows it;
	  * the server isn't at its active-run cap.
	The request (power / angle / aim / spin) is clamped to what the player has unlocked
	(Economy.sanitise); the velocity is computed here from server-side stats. The client
	never supplies a speed or direction vector.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local MachineConfig = require(Shared.Config.MachineConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local RateLimit = require(script.Parent.RateLimit)

local LaunchService = {}

local services
local charging = {} -- [player] = { fireAt, launch, pad, machine }
local nextReady = {} -- [player] = os.clock() when the launcher is ready again
local limiter = RateLimit.new(2, 3)
local rng = Random.new()

function LaunchService.init(registry)
	services = registry
end

function LaunchService.isCharging(player)
	return charging[player] ~= nil
end

function LaunchService.isBusy(player)
	return charging[player] ~= nil or services.CrashService.isRunning(player)
end

function LaunchService.readyAt(player)
	return nextReady[player]
end

function LaunchService.padStatus(pad)
	local owner = pad.owner
	if not owner then
		return "Free"
	end
	if charging[owner] then
		return "Charging"
	end
	if services.CrashService.isRunning(owner) then
		return "Running"
	end
	if nextReady[owner] and os.clock() < nextReady[owner] then
		return "Cooldown"
	end
	return "Ready"
end

local function refuse(player, text)
	services.Remotes.Notify:FireClient(player, text, "error")
	return false, text
end

function LaunchService.request(player, request)
	local data = services.DataService.getProfile(player)
	if not data then
		return refuse(player, "Your lab data is still loading.")
	end
	if not limiter:allow(player) then
		return false, "rate"
	end
	local pad = services.PadService.padOf(player)
	if not pad then
		return refuse(player, "Claim a launch pad first (walk onto one and press E).")
	end
	if LaunchService.isBusy(player) then
		return refuse(player, "Your dummy is already on its way!")
	end
	local now = os.clock()
	if nextReady[player] and now < nextReady[player] then
		return refuse(player, string.format("Launcher cooling down: %.1fs", nextReady[player] - now))
	end
	local machine = MachineConfig.ById[data.Selected]
	if not machine or not data.Machines[machine.Id] or pad.machineId ~= machine.Id then
		return refuse(player, "That machine isn't ready on your pad.")
	end
	if services.CrashService.activeCount() >= PerformanceConfig.MaxActiveRuns then
		return refuse(player, "The arena is packed - try again in a moment.")
	end
	local stats = services.UpgradeService.statsFor(player)
	local launch = Economy.launch(machine, stats, request, pad.yaw, rng)
	local chargeTime = Economy.chargeTime(machine, stats)
	data.LastLaunch = launch.Request
	services.DataService.markDirty(player)
	charging[player] = { fireAt = now + chargeTime, launch = launch, pad = pad, machine = machine, featured = services.QuestService.featuredId(player) }
	services.Remotes.MachineFx:FireAllClients(pad.index, machine.Id, "Charge", { elevation = launch.Elevation, time = chargeTime, power = launch.Request.Power })
	services.PadService.broadcast()
	return true
end

local function fire(player, entry)
	charging[player] = nil
	local data = services.DataService.getProfile(player)
	local pad = services.PadService.padOf(player)
	if not data or pad ~= entry.pad or not player.Parent then
		services.Remotes.MachineFx:FireAllClients(entry.pad.index, entry.machine.Id, "Rest", {})
		return
	end
	local stats = services.UpgradeService.statsFor(player)
	nextReady[player] = os.clock() + Economy.cooldown(entry.machine, stats)
	services.DataService.bump(player, "Launches", 1)
	services.Analytics.funnel(player, "FirstLaunch")
	local started = services.CrashService.start(player, pad, entry.machine, entry.launch, stats, entry.featured)
	services.Remotes.MachineFx:FireAllClients(pad.index, entry.machine.Id, "Fire", { elevation = entry.launch.Elevation, fx = data.Cosmetics.LaunchFx, speed = entry.launch.Speed })
	if started then
		services.QuestService.tutorialEvent(player, "Launch")
	end
	services.PadService.broadcast()
end

-- Called every Heartbeat.
function LaunchService.step()
	local now = os.clock()
	for player, entry in pairs(charging) do
		if now >= entry.fireAt then
			fire(player, entry)
		end
	end
end

function LaunchService.onPlayerRemoving(player)
	local entry = charging[player]
	if entry then
		services.Remotes.MachineFx:FireAllClients(entry.pad.index, entry.machine.Id, "Rest", {})
	end
	charging[player] = nil
	nextReady[player] = nil
	limiter:forget(player)
end

function LaunchService.cooldownText(player)
	local t = nextReady[player]
	if not t or os.clock() >= t then
		return nil
	end
	return Format.stat(math.ceil((t - os.clock()) * 10) / 10) .. "s"
end

function LaunchService.start()
	services.Remotes.Launch.OnServerEvent:Connect(function(player, request)
		if request ~= nil and type(request) ~= "table" then
			return
		end
		LaunchService.request(player, request)
	end)
end

return LaunchService
