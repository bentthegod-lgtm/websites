--[[
	Exports the classroom (built by the real ClassroomBuilder), the teacher rig (TeacherRig) and a
	phone on a few desks (Props) as a JSON part list for a browser 3D preview
	(tools/render_preview.mjs). Same approach as snatch-tycoon/tools/export_blobbies.luau.
	Usage (from phones-away/):
	  rojo build -o build/PhonesAway.rbxlx
	  lune run tools/export_classroom build/PhonesAway.rbxlx build/classroom.json
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/PhonesAway.rbxlx"))
local outPath = process.args[2] or "build/classroom.json"

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)

local game = {
	GetService = function(_, name)
		return place:GetService(name)
	end,
}
local cache = {}
local env
local function requireModule(m)
	if cache[m] == nil then
		local e = table.clone(env)
		e.script = m
		cache[m] = luau.load(m.Source, { debugName = m:GetFullName(), environment = e })()
	end
	return cache[m]
end
env = {
	game = game,
	require = requireModule,
	Instance = {
		new = function(className)
			local i = roblox.Instance.new(className)
			if i:IsA("BasePart") then
				i.Position = roblox.Vector3.zero
			end
			return i
		end,
	},
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	workspace = place:GetService("Workspace"),
}

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("PhonesAway")
local Services = place:GetService("ServerScriptService"):FindFirstChild("PhonesAwayServer").Services
local GameConfig = requireModule(Shared.Config.GameConfig)
local UpgradeConfig = requireModule(Shared.Config.UpgradeConfig)
local TeacherRig = requireModule(Shared.TeacherRig)
local Props = requireModule(Shared.Props)
local ClassroomBuilder = requireModule(Services.ClassroomBuilder)

local world
-- Parts that only get in the way of a view from above the back of the room.
local SKIP = { Ceiling = true, LightPanel = true }

local function exportParts(root, list)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and not SKIP[d.Name] then
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			local okShape, shape = pcall(function()
				return d.Shape.Name
			end)
			local text
			local gui = d:FindFirstChildOfClass("SurfaceGui")
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			if label and label.Text ~= "" and label ~= world.boardText then
				text = { value = label.Text, face = gui.Face.Name, color = { label.TextColor3.R, label.TextColor3.G, label.TextColor3.B } }
			end
			table.insert(list, {
				name = d.Name,
				shape = if mesh then "Ellipsoid" elseif d:IsA("WedgePart") then "Wedge" elseif okShape then shape else "Block",
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				cf = { d.CFrame:GetComponents() },
				color = { d.Color.R, d.Color.G, d.Color.B },
				material = d.Material.Name,
				transparency = d.Transparency,
				text = text,
			})
		end
	end
	return list
end

world = ClassroomBuilder.build()
-- Something on the board, like the first lesson line of a class.
world.boardText.Text = "Today: FRACTIONS\n1/2 + 1/4 = 3/4\nPizza = best fraction example\nSimplify! 4/8 = 1/2\nHomework: p. 42\nPhones away please :)"
local L = GameConfig.Classroom
local parts = exportParts(world.room, {})
-- The teacher lecturing at the front, facing the class (heading 0 = +Z).
local heading = 0.35
local teacher = TeacherRig.build(TeacherRig.Styles.Teacher, roblox.CFrame.new(L.LectureSpot[1] - 4, 0, L.LectureSpot[2]) * roblox.CFrame.Angles(0, heading + math.pi, 0))
exportParts(teacher, parts)
-- Phones on a few desks (one out, the rest in the desk).
for i, desk in ipairs(world.desks) do
	if i % 3 == 1 then
		local tier = UpgradeConfig.Phone.Tiers[(i % #UpgradeConfig.Phone.Tiers) + 1]
		local phone = Props.phone(tier, nil, if i == 4 then desk.phoneUp else desk.phoneDown)
		exportParts(phone, parts)
	end
end
-- The whiteboard's text lives in a SurfaceGui: export it with the board.
local boardSurface = world.boardText.Parent.Parent
fs.writeFile(outPath, serde.encode("json", {
	parts = parts,
	board = { cf = { boardSurface.CFrame:GetComponents() }, size = { boardSurface.Size.X, boardSurface.Size.Y }, text = world.boardText.Text },
}))
print(string.format("exported classroom with %d visible parts to %s", #parts, outPath))
