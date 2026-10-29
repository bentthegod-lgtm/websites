--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Every client -> server remote is type-checked, range-checked and rate limited on the
	server. Clients never send scores, distances, prices or rewards - only requests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "CrashLabRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"ClaimPad", -- (padIndex: number)   (also by the pad's ProximityPrompt)
	"LeavePad", -- ()
	"SelectMachine", -- (machineId: string)
	"Launch", -- (request: { Power, Angle, Aim, Spin })
	"BuyUpgrade", -- (key: string)
	"UnlockMachine", -- (machineId: string)
	"BuyCosmetic", -- (kind: string, id: string)   coins cosmetics
	"Equip", -- (kind: string, id: string)
	"Prestige", -- (confirm: string)  must be "CERTIFY"
	"Tutorial", -- (action: "Skip" | "Replay")
	"Duel", -- (action: "Invite" | "Accept" | "Decline", userId: number?)
	"ShopBuy", -- (key: string)   Robux cosmetics
	"RedeemCode", -- (code: string)
	"SaveSettings", -- (settings: table)
	"UnlockFacility", -- (facilityId: string)   requirement + coin price, checked on the server
	"Travel", -- (facilityId: string)   go to an unlocked facility ("IndustrialLab" = the hub)

	-- server -> client
	"Profile", -- (snapshot)
	"PadState", -- (pads: { {index, userId, machineId, state, readyAt} })
	"MachineFx", -- (padIndex, machineId, phase: "Charge" | "Fire" | "Rest", data)
	"RunStarted", -- (userId, padIndex, dummyModel, featuredId)
	"RunEvent", -- (userId, kind, data)  impact / ring / target / prop / objective
	"RunEnded", -- (userId, summary)  (owner also gets "Results")
	"Results", -- (breakdown)
	"Notify", -- (text, kind)
	"Popup", -- (kind, data)  achievement / challenge / machine / record / facility
	"Announce", -- (text, color)
	"Leaderboard", -- (rows)
	"DuelState", -- (state or nil)
}

local folder

function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server-only")
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(Net.Names) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Net.event(name)
	if not folder then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	local remote = folder:FindFirstChild(name) or folder:WaitForChild(name, 10)
	assert(remote, "Unknown remote " .. tostring(name))
	return remote
end

return Net
