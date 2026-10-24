--[[
	PlotService - base ownership, laser door lock and base geometry queries.

	Lock: the owner presses the console button (or the HUD LOCK button). The laser door
	closes for 45 s (GameConfig.Lock.Duration), then a 60 s cooldown. While locked:
	  * the blocker part collides (the owner's client turns collision off locally for their
	    own door, so only the owner can walk through),
	  * Blobbies in the base can't be grabbed (checked on the server),
	  * intruders are pushed out to the doorstep, and anyone still carrying a Blobby out of
	    this base gets zapped and drops it.
	The paid "Lock Base Now" product adds a LockToken; a token skips the cooldown (but the
	door always stays open for MinGapAfterPaid seconds between locks).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local Layout = require(Shared.Layout)
local Timers = require(Shared.Timers)
local Format = require(Shared.Format)

local PlotService = {}

local services
local plots = {} -- [index] = runtime
local byPlayer = {} -- [player] = index

local GREEN = Color3.fromRGB(90, 255, 130)
local RED = Color3.fromRGB(255, 60, 70)
local YELLOW = Color3.fromRGB(255, 220, 90)

function PlotService.init(registry)
	services = registry
end

function PlotService.setWorld(world)
	plots = {}
	for index, plot in ipairs(world.plots) do
		plots[index] = { plot = plot, owner = nil, lock = Timers.newLock(), lastStatus = "Ready" }
		plot.lockPrompt.Triggered:Connect(function(player)
			if plots[index].owner == player then
				PlotService.lock(player, false)
			else
				services.Remotes.Notify:FireClient(player, "Only the owner can lock this base.", "warn")
			end
		end)
	end
end

function PlotService.runtime(index)
	return plots[index]
end

function PlotService.plotIndexOf(player)
	return byPlayer[player]
end

function PlotService.plotOf(player)
	local index = byPlayer[player]
	return index and plots[index] and plots[index].plot
end

function PlotService.ownerOf(index)
	return plots[index] and plots[index].owner
end

local function setLaser(rt, on)
	local laser = rt.plot.laser
	laser.blocker.CanCollide = on
	for _, bar in ipairs(laser.bars) do
		bar.Transparency = if on then 0.05 else 1
	end
	for _, strip in ipairs(laser.strips) do
		strip.Color = if on then RED else GREEN
	end
end

function PlotService.applySlots(player)
	local index = byPlayer[player]
	local rt = index and plots[index]
	if not rt then
		return
	end
	local slots = services.PlayerService.slots(player)
	for slot, pedestal in ipairs(rt.plot.pedestals) do
		local open = slot <= slots
		pedestal.column.Transparency = if open then 0 else 0.7
		pedestal.top.Transparency = if open then 0 else 0.7
		pedestal.ring.Transparency = if open then 0 else 0.8
		pedestal.pad.Transparency = if open then 0.15 else 1
		pedestal.lockedGui.Enabled = not open
	end
end

function PlotService.assign(player)
	if byPlayer[player] then
		return byPlayer[player]
	end
	for index, rt in ipairs(plots) do
		if rt.owner == nil then
			rt.owner = player
			rt.lock = Timers.newLock()
			byPlayer[player] = index
			rt.plot.signLabel.Text = string.upper(player.DisplayName) .. "'S BASE"
			rt.plot.laser.blocker:SetAttribute("OwnerId", player.UserId)
			rt.plot.model:SetAttribute("OwnerId", player.UserId)
			player:SetAttribute("PlotIndex", index)
			setLaser(rt, false)
			PlotService.applySlots(player)
			return index
		end
	end
	warn("[SnatchTycoon] No free plot for " .. player.Name)
	return nil
end

function PlotService.release(player)
	local index = byPlayer[player]
	if not index then
		return
	end
	local rt = plots[index]
	rt.owner = nil
	rt.lock = Timers.newLock()
	byPlayer[player] = nil
	rt.plot.signLabel.Text = "EMPTY PLOT"
	rt.plot.statusLabel.Text = ""
	rt.plot.consoleLabel.Text = "LOCK"
	rt.plot.laser.blocker:SetAttribute("OwnerId", nil)
	rt.plot.model:SetAttribute("OwnerId", nil)
	setLaser(rt, false)
	for _, pedestal in ipairs(rt.plot.pedestals) do
		pedestal.column.Transparency = 0
		pedestal.top.Transparency = 0
		pedestal.ring.Transparency = 0
		pedestal.pad.Transparency = 0.15
		pedestal.lockedGui.Enabled = false
		pedestal.cashLabel.Text = ""
	end
	task.defer(PlotService.assignWaiting)
end

-- A player who joined while all bases were taken gets the next one that frees up.
function PlotService.assignWaiting()
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		if player.Parent and not byPlayer[player] and PlotService.assign(player) then
			services.BlobbyService.spawnSaved(player)
			local character = player.Character
			if character and character.Parent then
				character:PivotTo(PlotService.spawnCFrame(player))
			end
			services.Remotes.Notify:FireClient(player, "A base opened up - it's yours now!", "good")
			services.PlayerService.sendProfile(player)
		end
	end
end

function PlotService.spawnCFrame(player)
	local plot = PlotService.plotOf(player)
	return plot and plot.spawnCFrame
end

-- Is a world position inside plot `index` (floor area, below the wall tops)?
function PlotService.insidePlot(index, position, margin)
	local rt = plots[index]
	if not rt then
		return false
	end
	local localPos = rt.plot.cframe:PointToObjectSpace(position)
	return localPos.Y < GameConfig.Plot.WallHeight + 6 and Layout.insideLocal(localPos.X, localPos.Z, GameConfig.Plot, margin or 0)
end

function PlotService.plotAtPosition(position)
	for index in ipairs(plots) do
		if PlotService.insidePlot(index, position) then
			return index
		end
	end
	return nil
end

function PlotService.statusOf(index)
	local rt = plots[index]
	if not rt then
		return "Ready", 0
	end
	return Timers.lockStatus(rt.lock, os.clock())
end

function PlotService.lockStatus(player)
	local index = byPlayer[player]
	if not index then
		return "Ready", 0
	end
	return PlotService.statusOf(index)
end

function PlotService.isLocked(index)
	return (PlotService.statusOf(index)) == "Locked"
end

function PlotService.canPaidLock(player)
	local index = byPlayer[player]
	return index ~= nil and Timers.canPaidLock(plots[index].lock, os.clock(), GameConfig.Lock)
end

local function onLocked(index)
	local rt = plots[index]
	setLaser(rt, true)
	rt.lastStatus = "Locked"
	local owner = rt.owner
	-- zap thieves still inside and push other intruders out
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= owner then
			local character = other.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and PlotService.insidePlot(index, hrp.CFrame.Position) then
				local carry = services.StealService.carryOf(other)
				if carry and carry.fromPlot == index then
					services.StealService.drop(other, "laser")
				end
				character:PivotTo(rt.plot.doorstep * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.pi, 0))
				services.Remotes.Sfx:FireClient(other, "LaserZap")
				services.Remotes.Notify:FireClient(other, "ZAP! The laser door pushed you out.", "warn")
			end
		end
	end
	if owner then
		services.Remotes.Sfx:FireClient(owner, "LockOn")
		services.Remotes.Popup:FireClient(owner, "Locked", { duration = GameConfig.Lock.Duration })
	end
end

-- paid = true skips the cooldown (Lock Base Now product / token)
function PlotService.lock(player, paid)
	local index = byPlayer[player]
	if not index then
		return false, "No base"
	end
	local rt = plots[index]
	local data = services.DataService.getProfile(player)
	local now = os.clock()
	local status = Timers.lockStatus(rt.lock, now)
	-- A saved token makes a cooldown press count as paid.
	local useToken = false
	if not paid and status == "Cooldown" and data and (data.LockTokens or 0) > 0 and Timers.canPaidLock(rt.lock, now, GameConfig.Lock) then
		paid = true
		useToken = true
	end
	local ok, reason = Timers.tryLock(rt.lock, now, GameConfig.Lock, paid)
	if not ok then
		if reason == "Cooldown" then
			local _, left = Timers.lockStatus(rt.lock, now)
			services.Remotes.Notify:FireClient(player, "Lock recharging: " .. Format.time(left) .. " (or buy Lock Base Now in the shop)", "warn")
		elseif reason == "Too soon" then
			services.Remotes.Notify:FireClient(player, "The door just opened - wait a few seconds.", "warn")
		end
		return false, reason
	end
	if useToken then
		data.LockTokens -= 1
		services.DataService.markDirty(player)
	end
	onLocked(index)
	services.RewardService.recordGoal(player, "Lock", 1)
	services.PlayerService.sendProfile(player)
	return true
end

-- Applies one saved LockToken if possible (called after a Lock Base Now purchase).
function PlotService.useLockToken(player)
	local data = services.DataService.getProfile(player)
	local index = byPlayer[player]
	if not data or not index or (data.LockTokens or 0) <= 0 then
		return false
	end
	if not Timers.canPaidLock(plots[index].lock, os.clock(), GameConfig.Lock) then
		services.Remotes.Notify:FireClient(player, "Lock token saved - press LOCK when the door is open.", "info")
		return false
	end
	local ok = Timers.tryLock(plots[index].lock, os.clock(), GameConfig.Lock, true)
	if ok then
		data.LockTokens -= 1
		services.DataService.markDirty(player)
		onLocked(index)
		services.PlayerService.sendProfile(player)
	end
	return ok
end

function PlotService.step()
	local now = os.clock()
	for _, rt in ipairs(plots) do
		local plot = rt.plot
		if rt.owner then
			local status, left = Timers.lockStatus(rt.lock, now)
			if status ~= "Locked" and rt.lastStatus == "Locked" then
				setLaser(rt, false)
				services.Remotes.Sfx:FireClient(rt.owner, "LockOff")
				services.Remotes.Notify:FireClient(rt.owner, "Your laser door is OPEN again!", "warn")
			end
			rt.lastStatus = status
			if status == "Locked" then
				plot.statusLabel.Text = "LOCKED " .. Format.time(left)
				plot.statusLabel.TextColor3 = RED
				plot.consoleLabel.Text = "LOCKED " .. Format.time(left)
			elseif status == "Cooldown" then
				plot.statusLabel.Text = "OPEN"
				plot.statusLabel.TextColor3 = YELLOW
				plot.consoleLabel.Text = "RECHARGING " .. Format.time(left)
			else
				plot.statusLabel.Text = "OPEN"
				plot.statusLabel.TextColor3 = GREEN
				plot.consoleLabel.Text = "PRESS TO LOCK"
			end
		end
	end
end

function PlotService.start()
	services.DataService.Releasing:Connect(function(player)
		PlotService.release(player)
	end)
	services.Remotes.LockBase.OnServerEvent:Connect(function(player)
		local rt = byPlayer[player] and plots[byPlayer[player]]
		local now = os.clock()
		if not rt or (rt.lastPress and now - rt.lastPress < 0.5) then
			return
		end
		rt.lastPress = now
		PlotService.lock(player, false)
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			PlotService.step()
		end
	end)
end

return PlotService
