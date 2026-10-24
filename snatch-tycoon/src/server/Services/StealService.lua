--[[
	StealService - the viral hook.

	  1. Walk into someone's base and hold the Steal prompt on a Blobby (1.5 s). Starting the
	     hold already alarms the owner and announces the attempt.
	  2. On success the Blobby is welded above your head; you walk slower (55%, or 75% with
	     the Speedy Snatcher pass) and jump lower.
	  3. Reach your own base to keep it. Anyone can SLAP you (F / R1 / SLAP button) to make
	     you drop it, after which it runs home. Dying, leaving, the carry timeout and the
	     victim's laser door also make you drop it.
	All checks happen here on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local RarityConfig = require(Shared.Config.RarityConfig)

local StealService = {}

local services
local carries = {} -- [thief] = { rec, victim, weld, startedAt, fromPlot }
local robbing = {} -- [victim] = count of their Blobbies being carried
local lastAttempt = {} -- [thief] = os.clock() of the last announced attempt
local lastSlap = {}
local stunnedUntil = {}

local S = GameConfig.Steal

function StealService.init(registry)
	services = registry
end

function StealService.carryOf(player)
	return carries[player]
end

function StealService.isCarrying(player)
	return carries[player] ~= nil
end

function StealService.isBeingRobbed(player)
	return (robbing[player] or 0) > 0
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart"), humanoid, character
end

local function rarityColor(rec)
	return RarityConfig.Tiers[rec.species.Rarity].Color
end

local function describe(rec)
	return string.format("%s %s", string.upper(rec.species.Rarity), services.BlobbyService.displayName(rec))
end

local function canSteal(thief, rec)
	if not rec or rec.state ~= "Placed" or not rec.built then
		return false, nil
	end
	if rec.owner == thief then
		return false, nil
	end
	if carries[thief] then
		return false, "You're already carrying a Blobby!"
	end
	if stunnedUntil[thief] and os.clock() < stunnedUntil[thief] then
		return false, "You're still dizzy from that slap!"
	end
	local victimPlot = services.PlotService.plotIndexOf(rec.owner)
	if not victimPlot or services.PlotService.isLocked(victimPlot) then
		return false, "That base is locked!"
	end
	if not services.PlotService.plotOf(thief) then
		return false, nil
	end
	if not services.BlobbyService.freeSlot(thief) then
		return false, "Your base is full! Sell a Blobby first."
	end
	local hrp = rootOf(thief)
	if not hrp or (hrp.CFrame.Position - rec.built.root.CFrame.Position).Magnitude > S.PromptDistance + 6 then
		return false, nil
	end
	return true
end

-- Hold started: alarm the owner and tell the server (rate limited per thief).
function StealService.attempt(thief, rec)
	local ok = canSteal(thief, rec)
	if not ok then
		return
	end
	local now = os.clock()
	if lastAttempt[thief] and now - lastAttempt[thief] < S.AttemptAnnounceCooldown then
		return
	end
	lastAttempt[thief] = now
	services.Remotes.Alarm:FireClient(rec.owner, thief.DisplayName, services.BlobbyService.displayName(rec))
	services.FeedService.announce(string.format("%s is trying to steal %s's %s!", thief.DisplayName, rec.owner.DisplayName, rec.species.Name), { 255, 170, 80 }, false)
end

function StealService.tryGrab(thief, rec)
	local ok, reason = canSteal(thief, rec)
	if not ok then
		if reason then
			services.Remotes.Notify:FireClient(thief, reason, "warn")
		end
		return false
	end
	local hrp, humanoid, character = rootOf(thief)
	local head = character:FindFirstChild("Head") or hrp
	local root = rec.built.root
	services.BlobbyService.cancelMove(rec)
	rec.state = "Carried"
	rec.built.model:SetAttribute("State", "Carried")
	rec.built.model:SetAttribute("CarrierId", thief.UserId)
	-- Sit on the thief's head, facing the same way.
	root.Anchored = false
	root.CFrame = hrp.CFrame * CFrame.new(0, (head.CFrame.Position.Y - hrp.CFrame.Position.Y) + head.Size.Y / 2 + 0.3, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = hrp
	weld.Part1 = root
	weld.Parent = root
	pcall(function()
		root:SetNetworkOwner(thief)
	end)
	local fast = services.ShopService.owns(thief, "FastCarry")
	humanoid.WalkSpeed = GameConfig.WalkSpeed * (if fast then S.FastCarrySpeedMult else S.CarrySpeedMult)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = S.CarryJumpPower

	local fromPlot = services.PlotService.plotIndexOf(rec.owner)
	carries[thief] = { rec = rec, victim = rec.owner, weld = weld, startedAt = os.clock(), fromPlot = fromPlot }
	robbing[rec.owner] = (robbing[rec.owner] or 0) + 1
	services.BlobbyService.refresh(rec)
	services.Remotes.Carry:FireClient(thief, {
		name = services.BlobbyService.displayName(rec),
		rarity = rec.species.Rarity,
		timeout = S.CarryTimeout,
		victim = rec.owner.DisplayName,
	})
	services.Remotes.Sfx:FireClient(thief, "StealGrab")
	services.Remotes.Alarm:FireClient(rec.owner, thief.DisplayName, services.BlobbyService.displayName(rec))
	services.FeedService.announce(string.format("%s grabbed %s's %s! SLAP THEM!", thief.DisplayName, rec.owner.DisplayName, describe(rec)), rarityColor(rec), true)
	return true
end

local function endCarry(thief)
	local carry = carries[thief]
	if not carry then
		return nil
	end
	carries[thief] = nil
	robbing[carry.victim] = math.max(0, (robbing[carry.victim] or 1) - 1)
	if carry.weld then
		carry.weld:Destroy()
	end
	if thief.Parent then
		services.PlayerService.resetMovement(thief)
		services.Remotes.Carry:FireClient(thief, nil)
	end
	local rec = carry.rec
	if rec.built then
		rec.built.model:SetAttribute("CarrierId", nil)
	end
	return carry
end

-- Drops what `thief` carries; it runs home. reason: "slap" | "laser" | "timeout" | "manual" | "died" | "left"
function StealService.drop(thief, reason, slapper)
	local hrp = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	local carry = endCarry(thief)
	if not carry then
		return false
	end
	local rec = carry.rec
	if not rec.built or not services.BlobbyService.get(rec.uid) then
		return true
	end
	local from = if hrp then Vector3.new(hrp.CFrame.Position.X, 0.3, hrp.CFrame.Position.Z) else rec.built.root.CFrame.Position
	if hrp and services.PlotService.insidePlot(carry.fromPlot, hrp.CFrame.Position) then
		from = Vector3.new(hrp.CFrame.Position.X, 1, hrp.CFrame.Position.Z)
	end
	services.BlobbyService.walkHome(rec, from, S.ReturnSpeed, "Returning")
	services.BlobbyService.refresh(rec)
	services.Remotes.Sfx:FireClient(carry.victim, "Drop")
	if reason == "slap" and slapper then
		local data = services.DataService.getProfile(slapper)
		if data then
			data.Stats.Defended += 1
		end
		services.RewardService.recordGoal(slapper, "Defend", 1)
		local saver = if slapper == carry.victim then "their" else (carry.victim.DisplayName .. "'s")
		services.FeedService.announce(string.format("%s slapped %s and saved %s %s!", slapper.DisplayName, thief.DisplayName, saver, rec.species.Name), { 120, 230, 255 }, true)
	elseif reason == "laser" then
		services.FeedService.announce(string.format("%s got zapped by %s's laser door!", thief.DisplayName, carry.victim.DisplayName), { 255, 80, 80 }, false)
	elseif reason == "timeout" then
		services.Remotes.Notify:FireClient(thief, rec.species.Name .. " wriggled free and ran home!", "warn")
	end
	return true
end

function StealService.onCarrierLost(player, reason)
	if carries[player] then
		StealService.drop(player, reason)
	end
end

-- The victim left: their Blobby vanishes with them, the thief just loses it.
function StealService.onVictimLeaving(victim)
	for thief, carry in pairs(carries) do
		if carry.victim == victim then
			endCarry(thief)
			if thief.Parent then
				services.Remotes.Notify:FireClient(thief, victim.DisplayName .. " left - the Blobby went with them.", "warn")
			end
		end
	end
	robbing[victim] = nil
end

local function deliver(thief, carry)
	local rec = carry.rec
	local hrp = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	endCarry(thief)
	local victim = rec.owner
	local name = describe(rec)
	local color = rarityColor(rec)
	local from = if hrp then Vector3.new(hrp.CFrame.Position.X, 1, hrp.CFrame.Position.Z) else nil
	services.BlobbyService.transfer(rec, thief, from)
	local thiefData = services.DataService.getProfile(thief)
	if thiefData then
		thiefData.Stats.Stolen += 1
	end
	local victimData = services.DataService.getProfile(victim)
	if victimData then
		victimData.Stats.Robbed += 1
	end
	services.RewardService.recordGoal(thief, "Steal", 1)
	services.Remotes.Popup:FireClient(thief, "Stolen", { name = name, rarity = rec.species.Rarity, species = rec.species.Id, mutation = rec.mutation })
	services.Remotes.Sfx:FireClient(thief, "StealSuccess")
	services.Remotes.Notify:FireClient(victim, thief.DisplayName .. " stole your " .. rec.species.Name .. "! Lock your base next time!", "danger")
	services.FeedService.announce(string.format("%s STOLE %s's %s!", thief.DisplayName, victim.DisplayName, name), color, true)
	services.PlayerService.sendProfile(thief)
end

function StealService.step()
	local now = os.clock()
	for thief, carry in pairs(carries) do
		local hrp = rootOf(thief)
		if not thief.Parent or not hrp then
			StealService.drop(thief, "died")
		elseif not services.BlobbyService.get(carry.rec.uid) then
			endCarry(thief)
		elseif now - carry.startedAt > S.CarryTimeout then
			StealService.drop(thief, "timeout")
		else
			local home = services.PlotService.plotIndexOf(thief)
			if home and services.PlotService.insidePlot(home, hrp.CFrame.Position) then
				deliver(thief, carry)
			end
		end
	end
end

-- SLAP: hits the nearest player in range (carriers first). Knocks them back and makes
-- them drop what they carry.
function StealService.slap(slapper)
	local now = os.clock()
	if lastSlap[slapper] and now - lastSlap[slapper] < GameConfig.Slap.Cooldown then
		return false
	end
	local myRoot = rootOf(slapper)
	if not myRoot then
		return false
	end
	lastSlap[slapper] = now
	local best, bestScore
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= slapper then
			local root = rootOf(other)
			if root then
				local dist = (root.CFrame.Position - myRoot.CFrame.Position).Magnitude
				if dist <= GameConfig.Slap.Range then
					local score = dist - (if carries[other] then 100 else 0)
					if not bestScore or score < bestScore then
						best, bestScore = other, score
					end
				end
			end
		end
	end
	if not best then
		services.Remotes.SlapFx:FireAllClients(myRoot.CFrame.Position, myRoot.CFrame.Position + myRoot.CFrame.LookVector * 4, false)
		return false
	end
	local targetRoot = rootOf(best)
	local dir = targetRoot.CFrame.Position - myRoot.CFrame.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else myRoot.CFrame.LookVector
	services.Remotes.Knockback:FireClient(best, dir * GameConfig.Slap.Knockback + Vector3.new(0, 38, 0))
	services.Remotes.SlapFx:FireAllClients(myRoot.CFrame.Position, targetRoot.CFrame.Position, true)
	stunnedUntil[best] = now + S.StunAfterSlap
	local data = services.DataService.getProfile(slapper)
	if data then
		data.Stats.Slaps += 1
	end
	services.RewardService.recordGoal(slapper, "Slap", 1)
	if carries[best] then
		StealService.drop(best, "slap", slapper)
	end
	return true, best
end

function StealService.start()
	local remotes = services.Remotes
	remotes.Slap.OnServerEvent:Connect(function(player)
		StealService.slap(player)
	end)
	remotes.DropCarried.OnServerEvent:Connect(function(player)
		if carries[player] then
			StealService.drop(player, "manual")
		end
	end)
	services.DataService.Releasing:Connect(function(player)
		if carries[player] then
			StealService.drop(player, "left")
		end
		lastAttempt[player] = nil
		lastSlap[player] = nil
		stunnedUntil[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.15)
			StealService.step()
		end
	end)
end

return StealService
