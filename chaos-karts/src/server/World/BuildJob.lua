--[[
	BuildJob - FAST STARTUP. Builders don't create parts directly: they append cheap spec
	tables (Parts.new options + extras), and the job turns them into Instances a few
	hundred per frame (Main.server steps it from Heartbeat), so a ~5,000-part world never
	blocks a frame or comes near Roblox's script timeout. The harness times every step.

	Spec extras: Folder ("Track/Ground"...), Attributes = { k = v }, Light = { Color,
	Range, Brightness, Spot = bool, Face }, Text = { Face, Text, Color, Background,
	Font }, Tag (job.tagged[tag] gets the part).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Parts = require(Shared.Parts)

local BuildJob = {}
BuildJob.__index = BuildJob

function BuildJob.new(root)
	return setmetatable({ root = root, specs = {}, index = 1, folders = {}, made = 0, tagged = {}, steps = 0 }, BuildJob)
end

function BuildJob:folder(path)
	local existing = self.folders[path]
	if existing then
		return existing
	end
	local parent = self.root
	local built = ""
	for name in string.gmatch(path, "[^/]+") do
		built = if built == "" then name else built .. "/" .. name
		local f = self.folders[built]
		if not f then
			f = parent:FindFirstChild(name)
			if not f then
				f = Instance.new("Folder")
				f.Name = name
				f.Parent = parent
			end
			self.folders[built] = f
		end
		parent = f
	end
	return parent
end

function BuildJob:add(folder, spec)
	spec.Folder = folder
	table.insert(self.specs, spec)
	return spec
end

function BuildJob:count()
	return #self.specs
end

function BuildJob:done()
	return self.index > #self.specs
end

local function decorate(part, spec)
	if spec.Attributes then
		for k, v in pairs(spec.Attributes) do
			part:SetAttribute(k, v)
		end
	end
	if spec.Light then
		local L = spec.Light
		local light = Instance.new(if L.Spot then "SpotLight" else "PointLight")
		light.Color = L.Color
		light.Range = L.Range or 16
		light.Brightness = L.Brightness or 1
		light.Shadows = false
		if L.Spot then
			light.Face = L.Face or Enum.NormalId.Bottom
			light.Angle = L.Angle or 70
		end
		light.Parent = part
	end
	if spec.Text then
		local T = spec.Text
		local gui = Instance.new("SurfaceGui")
		gui.Face = T.Face or Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = T.PixelsPerStud or 20
		gui.LightInfluence = T.LightInfluence or 0
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = if T.Background then 0 else 1
		label.BackgroundColor3 = T.Background or Color3.new(0, 0, 0)
		label.Text = T.Text
		label.TextScaled = true
		label.Font = T.Font or Enum.Font.GothamBlack
		label.TextColor3 = T.Color or Color3.new(1, 1, 1)
		label.TextStrokeTransparency = T.Stroke or 0.3
		label.Parent = gui
	end
	if spec.Tag then
		local list = spec.__job.tagged[spec.Tag]
		if not list then
			list = {}
			spec.__job.tagged[spec.Tag] = list
		end
		table.insert(list, part)
	end
end

-- Creates up to `n` parts. Returns true when everything is built.
function BuildJob:step(n)
	self.steps += 1
	local last = math.min(#self.specs, self.index + n - 1)
	for i = self.index, last do
		local spec = self.specs[i]
		spec.Parent = self:folder(spec.Folder)
		spec.__job = self
		local part = Parts.new(spec)
		decorate(part, spec)
		spec.__job = nil
		self.specs[i] = part -- drop the spec, keep the part (previews / tests)
		self.made += 1
	end
	self.index = last + 1
	return self.index > #self.specs
end

function BuildJob:finish()
	return self:step(math.huge)
end

return BuildJob
