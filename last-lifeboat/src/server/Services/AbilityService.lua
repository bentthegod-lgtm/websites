--[[
	AbilityService - the Grapple Hook (game pass) and the Rescue Flare (consumable product).

	Grapple: the client aims (Q / L1 / button) and sends a target point. The server checks
	the pass, the 12 s cooldown, that the player is free to move (not downed / out), that the
	point is finite and within 40 studs, and that a raycast from the player really hits a
	surface there. Only then does the client get GrappleOk and pull itself over.
	Rescue Flare: F / DPad-up / the FLARE button during a round. Uses one flare: every downed
	teammate within Flare.Radius is revived and everyone in the round gets a route arrow to
	the lifeboat for 15 s.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local RateLimit = require(script.Parent.RateLimit)

local AbilityService = {}

local services
local cooldowns = {}
local limit = RateLimit.new(2, 3)

local G = GameConfig.Grapple

function AbilityService.init(registry)
	services = registry
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function serverTime(t)
	return workspace:GetServerTimeNow() + (t - os.clock())
end

function AbilityService.grapple(player, target)
	if not services.ShopService.ownsPass(player, "Grapple") then
		return false, "no pass"
	end
	target = Net.vector(target, 1e5)
	local root = rootOf(player)
	if not target or not root then
		return false, "bad target"
	end
	local rec = services.SurvivalService.record(player)
	if rec and rec.state ~= "Alive" then
		return false, "not alive"
	end
	local now = os.clock()
	if cooldowns[player] and now < cooldowns[player] then
		return false, "cooldown"
	end
	local offset = target - root.CFrame.Position
	if offset.Magnitude > G.Range or offset.Magnitude < 2 then
		return false, "range"
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local ok, hit = pcall(function()
		return workspace:Raycast(root.CFrame.Position, offset.Unit * (offset.Magnitude + 2), params)
	end)
	if not ok or not hit or (hit.Position - target).Magnitude > 3 then
		return false, "no surface"
	end
	cooldowns[player] = now + G.Cooldown
	player:SetAttribute("LL_GrappleReady", serverTime(now + G.Cooldown))
	services.Remotes.GrappleOk:FireClient(player, hit.Position)
	services.Remotes.WorldSound:FireAllClients("Grapple", hit.Position)
	return true
end

function AbilityService.flare(player)
	local profile = services.DataService.getProfile(player)
	local rec = services.SurvivalService.record(player)
	if not profile or not rec or rec.state ~= "Alive" then
		return false, "not in a round"
	end
	if profile.Boosts.Flare <= 0 then
		services.Remotes.Notify:FireClient(player, "No Rescue Flares left (Shop).", "error")
		return false, "none"
	end
	local root = rootOf(player)
	local ship = services.ShipService.record()
	if not root or not ship then
		return false, "no ship"
	end
	profile.Boosts.Flare -= 1
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	player:SetAttribute("LL_Flares", profile.Boosts.Flare)
	local revived = 0
	local round = services.RoundService.run()
	for other in pairs(round and round.players or {}) do
		local orec = services.SurvivalService.record(other)
		local oroot = rootOf(other)
		if other ~= player and orec and orec.state == "Downed" and oroot and (oroot.CFrame.Position - root.CFrame.Position).Magnitude <= GameConfig.Flare.Radius then
			if services.SurvivalService.revive(other, nil, "flare") then
				revived += 1
				services.Remotes.Notify:FireClient(other, player.DisplayName .. "'s Rescue Flare revived you!", "good")
			end
		end
	end
	local boatPos = ship.lifeboat.root.CFrame.Position
	for other in pairs(round and round.players or {}) do
		if other.Parent then
			services.Remotes.FlareArrow:FireClient(other, GameConfig.Flare.ArrowTime, boatPos)
		end
	end
	services.Remotes.WorldSound:FireAllClients("Flare", root.CFrame.Position)
	services.Remotes.Announce:FireAllClients(string.format("%s fired a Rescue Flare!%s", player.DisplayName, if revived > 0 then string.format(" %d revived.", revived) else ""), { 255, 120, 90 })
	return true, revived
end

function AbilityService.onPlayerRemoving(player)
	cooldowns[player] = nil
	limit:forget(player)
end

function AbilityService.start()
	services.Remotes.Grapple.OnServerEvent:Connect(function(player, target)
		if limit:allow(player) then
			AbilityService.grapple(player, target)
		end
	end)
	services.Remotes.UseFlare.OnServerEvent:Connect(function(player)
		if limit:allow(player) then
			AbilityService.flare(player)
		end
	end)
end

return AbilityService
