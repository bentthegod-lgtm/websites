--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Every client->server remote is type-checked, range-checked and rate limited on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "PhonesAwayRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"Phone", -- (up: boolean)
	"PhoneAction", -- (kind: "snap"|"watch"|"peek")  the server runs every timer
	"Answer", -- (slot: number, option: number)  answer a question on your test
	"QuizAnswer", -- (index: number)
	"ThrowPlane", -- (deskIndex: number)
	"PassNote", -- (targetUserId: number)
	"Report", -- (targetUserId: number)  Teacher's Pet
	"SetPet", -- (on: boolean)
	"Bail", -- ()  pay Clout to leave detention
	"UseDetentionPass", -- ()
	"BuyUpgrade", -- (key: string)
	"BuyCosmetic", -- (category: string, id: string)
	"Equip", -- (category: string, id: string)
	"OpenCrate", -- (crateKey: string)
	"ShopBuy", -- (key: string)  developer product or game pass key
	"ClaimDaily", -- ()
	"RedeemCode", -- (code: string)
	"InviteSent", -- ()

	-- server -> client
	"Profile", -- (snapshot)
	"RoundState", -- (state: string, data: table)
	"PhaseChanged", -- (data: table)
	"Suspicion", -- (value: number, mark: string)
	"PhoneState", -- (data: table)  phone + scanner flags, revealed answers (own only)
	"PhoneResult", -- (kind: string, data: table)
	"Test", -- (kind: "view"|"ack"|"ripped"|"clear", data)  questions + options, NO answers
	"Quiz", -- (data: table | nil)  bonus question
	"QuizResult", -- (data: table)
	"Chat", -- (author: string, text: string, color: {r,g,b}?)
	"Results", -- (data: table)
	"CrateResult", -- (data: table)
	"CodeResult", -- (ok: boolean, message: string)
	"Notify", -- (text: string, kind: string?)
	"Announce", -- (text: string, color: {r,g,b}?)
	"Effect", -- (kind: string, data: table)
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
