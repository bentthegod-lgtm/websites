--[[
	DuelService - optional head-to-head launch challenges.

	Invite another player in the server -> they accept -> each player's NEXT finished run
	(within the time limit) is their duel score. The higher score wins a bonus scaled to
	the lower of the two scores (so it can't be farmed with a partner who flops), the
	other player gets a small consolation. Scores come from ScoringService (server-side).
	Duels never touch the other player's machine or dummy.
]]

local Players = game:GetService("Players")

local DuelService = {}

local services
local invites = {} -- [target] = { from = player, at = os.clock() }
local duels = {} -- [player] = duel (shared table for both players)
local lastInvite = {}
local DUEL_TIME = 120
local INVITE_TIME = 30
local MAX_BONUS = 2000

function DuelService.init(registry)
	services = registry
end

local function send(duel)
	for _, p in ipairs({ duel.a, duel.b }) do
		if p.Parent then
			local other = if p == duel.a then duel.b else duel.a
			services.Remotes.DuelState:FireClient(p, {
				opponent = other.DisplayName,
				myScore = duel.scores[p],
				theirScore = duel.scores[other],
				endsIn = math.max(0, duel.endsAt - os.clock()),
			})
		end
	end
end

local function close(duel, text)
	for _, p in ipairs({ duel.a, duel.b }) do
		if duels[p] == duel then
			duels[p] = nil
		end
		if p.Parent then
			services.Remotes.DuelState:FireClient(p, nil)
			if text then
				services.Remotes.Notify:FireClient(p, text, "info")
			end
		end
	end
end

local function settle(duel)
	local sa, sb = duel.scores[duel.a] or -1, duel.scores[duel.b] or -1
	if sa < 0 and sb < 0 then
		close(duel, "Duel expired: nobody finished a run.")
		return
	end
	local winner, loser = duel.a, duel.b
	if sb > sa then
		winner, loser = duel.b, duel.a
	end
	if sa == sb then
		close(duel, "Duel tied!")
		return
	end
	local low = math.max(0, math.min(sa, sb))
	local bonus = math.min(MAX_BONUS, math.floor(low * 0.25) + 50)
	services.DataService.addCoins(winner, bonus, true)
	services.DataService.bump(winner, "DuelWins", 1)
	if loser.Parent and (duel.scores[loser] or -1) >= 0 then
		services.DataService.addCoins(loser, 25, true)
	end
	services.Remotes.Announce:FireAllClients(string.format("%s won a crash duel against %s!", winner.DisplayName, loser.DisplayName), { 120, 220, 255 })
	services.DataService.sendProfile(winner)
	if loser.Parent then
		services.DataService.sendProfile(loser)
	end
	close(duel, string.format("Duel over: %s wins (+%d coins).", winner.DisplayName, bonus))
end

function DuelService.invite(player, userId)
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	local t = os.clock()
	if not target or target == player or duels[player] or duels[target] then
		return false, "You can't challenge that player right now."
	end
	if lastInvite[player] and t - lastInvite[player] < 10 then
		return false, "Wait a moment before sending another challenge."
	end
	lastInvite[player] = t
	invites[target] = { from = player, at = t }
	services.Remotes.Popup:FireClient(target, "DuelInvite", { from = player.DisplayName, userId = player.UserId })
	return true, "Challenge sent to " .. target.DisplayName .. "."
end

function DuelService.respond(player, accept)
	local invite = invites[player]
	invites[player] = nil
	if not invite or os.clock() - invite.at > INVITE_TIME or not invite.from.Parent then
		return false, "That challenge has expired."
	end
	local from = invite.from
	if not accept then
		services.Remotes.Notify:FireClient(from, player.DisplayName .. " declined your challenge.", "info")
		return true, "Challenge declined."
	end
	if duels[player] or duels[from] then
		return false, "One of you is already in a duel."
	end
	local duel = { a = from, b = player, scores = {}, endsAt = os.clock() + DUEL_TIME }
	duels[from] = duel
	duels[player] = duel
	send(duel)
	services.Remotes.Notify:FireClient(from, player.DisplayName .. " accepted! Your next run counts.", "good")
	return true, "Duel on! Your next run counts."
end

function DuelService.onRunFinished(player, result)
	local duel = duels[player]
	if not duel or duel.scores[player] ~= nil then
		return
	end
	duel.scores[player] = if result.voided then 0 else result.score
	if duel.scores[duel.a] ~= nil and duel.scores[duel.b] ~= nil then
		settle(duel)
	else
		send(duel)
	end
end

function DuelService.step()
	local now = os.clock()
	local seen = {}
	for _, duel in pairs(duels) do
		if not seen[duel] then
			seen[duel] = true
			if now >= duel.endsAt then
				settle(duel)
			end
		end
	end
end

function DuelService.duelOf(player)
	return duels[player]
end

function DuelService.onPlayerRemoving(player)
	invites[player] = nil
	lastInvite[player] = nil
	local duel = duels[player]
	if duel then
		close(duel, "Duel cancelled: a player left.")
	end
end

function DuelService.start()
	services.Remotes.Duel.OnServerEvent:Connect(function(player, action, userId)
		local ok, message
		if action == "Invite" then
			ok, message = DuelService.invite(player, userId)
		elseif action == "Accept" then
			ok, message = DuelService.respond(player, true)
		elseif action == "Decline" then
			ok, message = DuelService.respond(player, false)
		else
			return
		end
		if message then
			services.Remotes.Notify:FireClient(player, message, if ok then "good" else "error")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			DuelService.step()
		end
	end)
end

return DuelService
