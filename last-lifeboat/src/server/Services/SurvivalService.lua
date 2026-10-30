--[[
	SurvivalService - oxygen, going DOWN, reviving and bleeding out, for everyone in the
	round. States: Alive -> Downed -> (revived) Alive | Out; Alive -> Escaped; Left.

	* Oxygen: while your head is under the sea (world Y below 0 - the terrain water is
	  static, so a flooded deck is simply below 0) it drains 1/s; above water it refills.
	  Lung Capacity raises the maximum. At 0 you go DOWN.
	* Downed: you float up to the surface (never through a ceiling), can't move, and bleed
	  out after Downed.BleedOut seconds. A teammate holds E for ReviveHold seconds beside you
	  (ProximityPrompt on your body, validated by distance and state) and you're back with
	  50% oxygen. A Life Jacket auto-revives you once per round. Bleeding out = OUT: you're
	  sent to the dock to spectate and your carried loot is lost.
	* Hazards call damage() (steam, chandeliers: knockback + a little health) and zap()
	  (sparking wires in flooded rooms: oxygen loss).
	Values reach the client as attributes: LL_State, LL_Oxygen, LL_OxygenMax,
	LL_BleedEnds and LL_ReviveStart (server times), LL_Aboard.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Survival = require(Shared.Survival)
local LurchMath = require(Shared.LurchMath)

local SurvivalService = {}

local services
local world
local run = nil

local D = GameConfig.Downed

function SurvivalService.init(registry)
	services = registry
end

function SurvivalService.setWorld(newWorld)
	world = newWorld
end

local function serverTime(t)
	return workspace:GetServerTimeNow() + (t - os.clock())
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function humanoidOf(player)
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function headY(player)
	local c = player.Character
	local head = c and c:FindFirstChild("Head")
	if head then
		return head.CFrame.Position.Y
	end
	local root = rootOf(player)
	return root and root.CFrame.Position.Y + 1.5
end

function SurvivalService.record(player)
	local rec = run and run.players[player]
	return if type(rec) == "table" then rec else nil
end

local function setState(player, rec, state)
	rec.state = state
	if player.Parent then
		player:SetAttribute("LL_State", state)
	end
end

function SurvivalService.startRun(newRun)
	run = newRun
	for player in pairs(run.players) do
		local max = services.UpgradeService.effect(player, "Lungs")
		local rec = { state = "Alive", oxygen = max, max = max, jacketsUsed = 0, revives = 0, downs = 0 }
		run.players[player] = rec
		player:SetAttribute("LL_State", "Alive")
		player:SetAttribute("LL_Oxygen", max)
		player:SetAttribute("LL_OxygenMax", max)
		player:SetAttribute("LL_BleedEnds", nil)
		player:SetAttribute("LL_ReviveStart", nil)
		player:SetAttribute("LL_InRound", true)
	end
end

function SurvivalService.counts()
	local c = { Alive = 0, Downed = 0, Out = 0, Escaped = 0, Left = 0, present = 0 }
	if not run then
		return c
	end
	for _, rec in pairs(run.players) do
		if type(rec) == "table" then
			c[rec.state] = (c[rec.state] or 0) + 1
			if rec.state ~= "Left" then
				c.present += 1
			end
		end
	end
	return c
end

local function clearPrompt(rec)
	if rec.prompt then
		rec.prompt:Destroy()
		rec.prompt = nil
	end
end

local function ceilingAbove(player, from)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local ok, hit = pcall(function()
		return workspace:Raycast(from, Vector3.new(0, 40, 0), params)
	end)
	return if ok and hit then hit.Position.Y else nil
end

-- Puts a downed body where it floats: up to the surface (or just under a ceiling), lying back.
local function float(player)
	local root = rootOf(player)
	if not root then
		return
	end
	local pos = root.CFrame.Position
	local y = Survival.floatY(pos.Y, GameConfig.World.SeaLevel, ceilingAbove(player, pos))
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local upright = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + flat.Unit)
	root.Anchored = true
	root.CFrame = upright * CFrame.Angles(math.rad(-75), 0, 0)
end

function SurvivalService.down(player, reason)
	local rec = SurvivalService.record(player)
	if not rec or rec.state ~= "Alive" then
		return false
	end
	local now = os.clock()
	setState(player, rec, "Downed")
	rec.downedAt = now
	rec.downs += 1
	rec.oxygen = 0
	player:SetAttribute("LL_Oxygen", 0)
	player:SetAttribute("LL_BleedEnds", serverTime(now + D.BleedOut))
	player:SetAttribute("LL_ReviveStart", nil)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.PlatformStand = true
	end
	services.PlayerService.applySpeed(player)
	float(player)
	local root = rootOf(player)
	if root then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LL_Revive"
		prompt.ActionText = "Revive"
		prompt.ObjectText = player.DisplayName
		prompt.HoldDuration = D.ReviveHold
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = D.ReviveRange
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.PromptButtonHoldBegan:Connect(function(by)
			if by ~= player and SurvivalService.canRevive(player, by) then
				rec.reviver = by
				player:SetAttribute("LL_ReviveStart", workspace:GetServerTimeNow())
			end
		end)
		prompt.PromptButtonHoldEnded:Connect(function(by)
			if rec.reviver == by then
				rec.reviver = nil
				if player.Parent then
					player:SetAttribute("LL_ReviveStart", nil)
				end
			end
		end)
		prompt.Triggered:Connect(function(by)
			SurvivalService.tryRevive(player, by)
		end)
		rec.prompt = prompt
	end
	local profile = services.DataService.getProfile(player)
	if profile and Survival.jacketAvailable(profile.Boosts.LifeJacket, rec.jacketsUsed) then
		rec.jacketAt = now + D.LifeJacketDelay
		services.Remotes.Notify:FireClient(player, "Your Life Jacket inflates in a moment...", "info")
	else
		services.Remotes.Notify:FireClient(player, "You're DOWN! A teammate can hold E beside you to revive you.", "error")
	end
	for other in pairs(run.players) do
		if other ~= player and other.Parent then
			services.Remotes.Notify:FireClient(other, player.DisplayName .. " is down" .. (if reason == "drowned" then " (out of air)" else "") .. "! Hold E beside them to revive.", "warn")
		end
	end
	services.Remotes.WorldSound:FireAllClients("Downed", root and root.CFrame.Position)
	return true
end

function SurvivalService.canRevive(target, by)
	local rec = SurvivalService.record(target)
	local mine = SurvivalService.record(by)
	if not rec or rec.state ~= "Downed" or not mine or mine.state ~= "Alive" or by == target then
		return false
	end
	local a, b = rootOf(target), rootOf(by)
	return a ~= nil and b ~= nil and (a.CFrame.Position - b.CFrame.Position).Magnitude <= D.ReviveRange + 2
end

-- `by` nil = life jacket / flare (already validated by the caller).
function SurvivalService.revive(player, by, how)
	local rec = SurvivalService.record(player)
	if not rec or rec.state ~= "Downed" then
		return false
	end
	clearPrompt(rec)
	setState(player, rec, "Alive")
	rec.oxygen = Survival.reviveOxygen(rec.max)
	rec.downedAt, rec.jacketAt, rec.reviver = nil, nil, nil
	player:SetAttribute("LL_Oxygen", rec.oxygen)
	player:SetAttribute("LL_BleedEnds", nil)
	player:SetAttribute("LL_ReviveStart", nil)
	local root = rootOf(player)
	if root then
		local pos = root.CFrame.Position
		root.Anchored = false
		root.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
	end
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.PlatformStand = false
	end
	services.PlayerService.applySpeed(player)
	services.Remotes.WorldSound:FireAllClients("Revive", root and root.CFrame.Position)
	if by then
		local mine = SurvivalService.record(by)
		if mine then
			mine.revives += 1
		end
		services.DataService.bump(by, "Revives", 1)
		services.Remotes.Notify:FireClient(player, by.DisplayName .. " revived you!", "good")
		services.Remotes.Notify:FireClient(by, "You revived " .. player.DisplayName .. "!", "good")
	elseif how == "jacket" then
		services.Remotes.Notify:FireClient(player, "Your Life Jacket saved you!", "good")
	end
	return true
end

function SurvivalService.tryRevive(player, by)
	if not SurvivalService.canRevive(player, by) then
		return false
	end
	return SurvivalService.revive(player, by, "hold")
end

function SurvivalService.out(player, reason)
	local rec = SurvivalService.record(player)
	if not rec or (rec.state ~= "Alive" and rec.state ~= "Downed") then
		return false
	end
	clearPrompt(rec)
	setState(player, rec, "Out")
	player:SetAttribute("LL_BleedEnds", nil)
	player:SetAttribute("LL_ReviveStart", nil)
	services.LootService.clear(player)
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.PlatformStand = false
	end
	if world and reason ~= "died" then
		SurvivalService.moveTo(player, world.spawnCFrame)
	end
	services.PlayerService.applySpeed(player)
	services.Remotes.Notify:FireClient(player, "You were lost at sea... Spectating your crew.", "error")
	services.DataService.bump(player, "Drowned", 1)
	return true
end

function SurvivalService.escape(player)
	local rec = SurvivalService.record(player)
	if rec and rec.state == "Alive" then
		setState(player, rec, "Escaped")
		return true
	end
	return false
end

function SurvivalService.damage(player, amount, push)
	local rec = SurvivalService.record(player)
	if not rec or rec.state ~= "Alive" then
		return false
	end
	local humanoid = humanoidOf(player)
	if push and push.Magnitude > 0 then
		services.Remotes.Knockback:FireClient(player, push)
	end
	if humanoid then
		if humanoid.Health - amount <= 1 then
			humanoid.Health = math.max(1, humanoid.MaxHealth * 0.25)
			SurvivalService.down(player, "hurt")
		else
			humanoid.Health -= amount
		end
	end
	return true
end

function SurvivalService.zap(player)
	local rec = SurvivalService.record(player)
	if not rec or rec.state ~= "Alive" then
		return false
	end
	rec.oxygen = Survival.zap(rec.oxygen)
	player:SetAttribute("LL_Oxygen", rec.oxygen)
	services.Remotes.Notify:FireClient(player, "ZAP! Live wires in the water!", "error")
	if rec.oxygen <= 0 then
		SurvivalService.down(player, "drowned")
	end
	return true
end

function SurvivalService.moveTo(player, cf)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	root.Anchored = false
	if character.PrimaryPart then
		character:PivotTo(cf)
	else
		root.CFrame = cf
	end
	root.AssemblyLinearVelocity = Vector3.zero
end

-- Downed bodies are anchored by the server, so the server carries them on a lurch.
function SurvivalService.onLurch(oldPivot, newPivot)
	if not run then
		return
	end
	for player, rec in pairs(run.players) do
		if type(rec) == "table" and rec.state == "Downed" then
			local root = rootOf(player)
			if root then
				root.CFrame = LurchMath.relocate(oldPivot, newPivot, root.CFrame)
				float(player)
			end
		end
	end
end

function SurvivalService.step(dt)
	if not run then
		return
	end
	local now = os.clock()
	for player, rec in pairs(run.players) do
		if type(rec) == "table" and player.Parent then
			if rec.state == "Alive" then
				local y = headY(player)
				if y then
					local before = rec.oxygen
					local ranOut
					rec.oxygen, ranOut = Survival.stepOxygen(rec.oxygen, rec.max, Survival.headUnderwater(y), dt)
					if math.abs(rec.oxygen - before) > 1e-6 then
						player:SetAttribute("LL_Oxygen", rec.oxygen)
					end
					if ranOut then
						SurvivalService.down(player, "drowned")
					end
				end
			elseif rec.state == "Downed" then
				if rec.jacketAt and now >= rec.jacketAt then
					local profile = services.DataService.getProfile(player)
					if profile and Survival.jacketAvailable(profile.Boosts.LifeJacket, rec.jacketsUsed) then
						profile.Boosts.LifeJacket -= 1
						rec.jacketsUsed += 1
						services.DataService.markDirty(player)
						services.DataService.sendProfile(player)
						player:SetAttribute("LL_Jackets", profile.Boosts.LifeJacket)
						SurvivalService.revive(player, nil, "jacket")
					else
						rec.jacketAt = nil
					end
				elseif rec.downedAt and Survival.bledOut(rec.downedAt, now) then
					SurvivalService.out(player, "bled out")
				end
			end
		end
	end
end

-- A participant left: they are gone from the round (no payout).
function SurvivalService.release(player)
	local rec = SurvivalService.record(player)
	if rec then
		clearPrompt(rec)
		rec.state = "Left"
	end
end

function SurvivalService.stopRun()
	if run then
		for player, rec in pairs(run.players) do
			if type(rec) == "table" then
				clearPrompt(rec)
				if player.Parent then
					local root = rootOf(player)
					if root then
						root.Anchored = false
					end
					local humanoid = humanoidOf(player)
					if humanoid then
						humanoid.PlatformStand = false
					end
					player:SetAttribute("LL_State", "Lobby")
					player:SetAttribute("LL_InRound", false)
					player:SetAttribute("LL_Aboard", false)
					player:SetAttribute("LL_BleedEnds", nil)
					player:SetAttribute("LL_ReviveStart", nil)
					player:SetAttribute("LL_Oxygen", rec.max)
				end
			end
		end
	end
	run = nil
end

function SurvivalService.onPlayerRemoving(player)
	SurvivalService.release(player)
end


return SurvivalService
