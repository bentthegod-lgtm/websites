--[[
	LifeboatService - the last lifeboat at the stern of the top deck.

	* "LIFEBOAT LAUNCHES IN m:ss": the boat launches when the ship's RoundTime runs out.
	* Step into the boat (its seat zone) to be ABOARD (LL_Aboard). If every player still in
	  the round (alive or downed) is aboard for FullCrewHold seconds, it launches EARLY with
	  the Full Crew bonus. If nobody is left alive or downed, it launches empty.
	* Launch: everyone alive in the seat zone ESCAPES. The boat swings out past the stern,
	  lowers to the sea and rows away (a short server-driven cinematic, clients get a camera
	  cue) while the ship takes its final plunge. Everyone else is LOST AT SEA.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)

local LifeboatService = {}

local services
local run, ship, boat
local launchAt
local fullSince
local launched = false
local cine = nil

local LB = GameConfig.Lifeboat

function LifeboatService.init(registry)
	services = registry
end

local function serverTime(t)
	return workspace:GetServerTimeNow() + (t - os.clock())
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

function LifeboatService.startRun(newRun, record)
	run, ship, boat = newRun, record, record.lifeboat
	launchAt = os.clock() + record.plan.def.RoundTime
	fullSince = nil
	launched = false
	cine = nil
	run.launchAt = launchAt
	workspace:SetAttribute("LL_LaunchAt", serverTime(launchAt))
end

function LifeboatService.launchAt()
	return launchAt
end

function LifeboatService.setLaunchAt(t)
	launchAt = t
	if run then
		run.launchAt = t
	end
	workspace:SetAttribute("LL_LaunchAt", serverTime(t))
end

function LifeboatService.inZone(position)
	if not boat or not boat.zone then
		return false
	end
	local zone = boat.zone
	local p = zone.CFrame:PointToObjectSpace(position)
	local s = zone.Size
	return math.abs(p.X) <= s.X / 2 and math.abs(p.Y) <= s.Y / 2 + 1 and math.abs(p.Z) <= s.Z / 2
end

function LifeboatService.launched()
	return launched
end

function LifeboatService.launch(fullCrew)
	if launched or not run then
		return nil
	end
	launched = true
	local escaped = {}
	local names = {}
	local from = boat.root.CFrame
	local rel = {}
	for player, rec in pairs(run.players) do
		if type(rec) == "table" and rec.state == "Alive" and rec.aboard and player.Parent then
			services.SurvivalService.escape(player)
			table.insert(escaped, player)
			table.insert(names, player.DisplayName)
			local root = rootOf(player)
			if root then
				root.Anchored = true
				rel[player] = from:ToObjectSpace(root.CFrame)
			end
		end
	end
	run.fullCrew = fullCrew and #escaped > 0
	run.escaped = escaped
	-- the boat leaves the ship: from now on the ship's final plunge doesn't carry it
	boat.model.Parent = ship.model.Parent
	cine = { start = os.clock(), from = from, rel = rel, escaped = escaped }
	services.ShipService.beginPlunge()
	workspace:SetAttribute("LL_LaunchAt", nil)
	services.Remotes.Cinematic:FireAllClients("Launch", { boat = boat.model, fullCrew = run.fullCrew, escaped = names, duration = LB.CinematicTime })
	services.Remotes.WorldSound:FireAllClients("Winch", from.Position)
	if run.fullCrew then
		services.Remotes.Announce:FireAllClients("FULL CREW! The last lifeboat launches early!", { 120, 230, 150 })
	elseif #escaped > 0 then
		services.Remotes.Announce:FireAllClients("The last lifeboat is launching!", { 255, 210, 120 })
	else
		services.Remotes.Announce:FireAllClients("The last lifeboat launched... empty.", { 255, 130, 120 })
	end
	services.RoundService.onLaunch()
	return escaped
end

-- Boat pose along the cinematic: swing out past the stern, lower to the sea, row away.
function LifeboatService.boatAt(from, t)
	local ease = function(x)
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	local out = from * CFrame.new(0, 0, -16 * ease(t / 0.25))
	if t <= 0.25 then
		return out
	end
	local look = out.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local sea = CFrame.lookAt(Vector3.new(out.Position.X, GameConfig.World.SeaLevel + 0.9, out.Position.Z), Vector3.new(out.Position.X, GameConfig.World.SeaLevel + 0.9, out.Position.Z) + flat.Unit)
	if t <= 0.65 then
		return out:Lerp(sea, ease((t - 0.25) / 0.4))
	end
	return sea * CFrame.new(0, 0, -LB.RowDistance * ease((t - 0.65) / 0.35))
end

function LifeboatService.step()
	if not run or not boat then
		return
	end
	local now = os.clock()
	if launched then
		if cine then
			local t = (now - cine.start) / LB.CinematicTime
			local cf = LifeboatService.boatAt(cine.from, math.min(t, 1))
			boat.model:PivotTo(cf)
			for player, offset in pairs(cine.rel) do
				local root = rootOf(player)
				if root and player.Parent then
					root.CFrame = cf * offset
				end
			end
			services.ShipService.stepPlunge(math.min(t, 1))
			if t >= 1 then
				cine = nil
				services.RoundService.finish()
			end
		end
		return
	end
	local needed, aboardCount, present = 0, 0, 0
	for player, rec in pairs(run.players) do
		if type(rec) == "table" and player.Parent and rec.state ~= "Left" then
			present += 1
		end
		if type(rec) == "table" and player.Parent then
			if rec.state == "Alive" then
				needed += 1
				local root = rootOf(player)
				local aboard = root ~= nil and LifeboatService.inZone(root.CFrame.Position)
				if aboard ~= rec.aboard then
					rec.aboard = aboard
					player:SetAttribute("LL_Aboard", aboard)
					if aboard then
						services.Remotes.Notify:FireClient(player, "You're aboard the last lifeboat! Wait for your crew (Full Crew = bonus).", "good")
					end
				end
				if aboard then
					aboardCount += 1
				end
			elseif rec.state == "Downed" then
				needed += 1
			end
		end
	end
	if present == 0 then
		return -- everyone left: RoundService aborts the round
	end
	if needed == 0 then
		LifeboatService.launch(false)
		return
	end
	if aboardCount == needed then
		if not fullSince then
			fullSince = now
			services.Remotes.Announce:FireAllClients(string.format("FULL CREW aboard! Launching in %d...", LB.FullCrewHold), { 120, 230, 150 })
		elseif now - fullSince >= LB.FullCrewHold then
			LifeboatService.launch(true)
			return
		end
	else
		fullSince = nil
	end
	if now >= launchAt then
		LifeboatService.launch(false)
	end
end

function LifeboatService.stopRun()
	if boat and boat.model then
		boat.model:Destroy()
	end
	run, ship, boat, cine = nil, nil, nil, nil
	launched = false
	workspace:SetAttribute("LL_LaunchAt", nil)
end

function LifeboatService.onPlayerRemoving(player)
	if cine then
		cine.rel[player] = nil
	end
end

return LifeboatService
