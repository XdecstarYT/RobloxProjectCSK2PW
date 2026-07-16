--!strict
--[[
	Controllers/WorldController.luau
	Builds the 3D city view: a stylized ground with a glowing district grid,
	surrounding water, an RTS overhead camera you can pan and zoom, and a
	multi-part model per building rendered from the replicated snapshot.

	Visuals are intentionally client-side and non-authoritative — the server owns
	the data; this controller only draws it. Buildings are Models tagged with a
	`buildingId` attribute so BuildController can pick them for selection. New
	buildings fade in; power-starved ones read as faded and dim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Buildings = require(ReplicatedStorage.Nexus.Config.Buildings)
local WorldGrid = require(ReplicatedStorage.Nexus.WorldGrid)

local Theme = require(script.Parent.Parent.UI.Theme)

-- Per-category look: body colour/material, roof colour, and a neon accent.
type Style = { body: Color3, material: Enum.Material, roof: Color3, accent: Color3 }
local STYLE: { [string]: Style } = {
	Housing = { body = Color3.fromRGB(96, 130, 180), material = Enum.Material.Concrete, roof = Color3.fromRGB(58, 80, 116), accent = Color3.fromRGB(120, 200, 255) },
	Power = { body = Color3.fromRGB(120, 122, 130), material = Enum.Material.Metal, roof = Color3.fromRGB(78, 80, 88), accent = Color3.fromRGB(250, 205, 90) },
	Food = { body = Color3.fromRGB(110, 158, 92), material = Enum.Material.Grass, roof = Color3.fromRGB(78, 116, 64), accent = Color3.fromRGB(150, 220, 120) },
	Industry = { body = Color3.fromRGB(170, 120, 82), material = Enum.Material.Metal, roof = Color3.fromRGB(120, 82, 54), accent = Color3.fromRGB(240, 150, 70) },
	Commerce = { body = Color3.fromRGB(86, 168, 160), material = Enum.Material.Glass, roof = Color3.fromRGB(52, 108, 104), accent = Color3.fromRGB(120, 230, 215) },
	Research = { body = Color3.fromRGB(126, 108, 200), material = Enum.Material.Metal, roof = Color3.fromRGB(84, 70, 140), accent = Color3.fromRGB(170, 140, 255) },
	Services = { body = Color3.fromRGB(196, 132, 176), material = Enum.Material.SmoothPlastic, roof = Color3.fromRGB(140, 90, 124), accent = Color3.fromRGB(240, 160, 210) },
	Government = { body = Color3.fromRGB(216, 220, 230), material = Enum.Material.Marble, roof = Color3.fromRGB(150, 156, 170), accent = Color3.fromRGB(245, 205, 120) },
}
local DEFAULT_STYLE: Style =
	{ body = Color3.fromRGB(170, 176, 188), material = Enum.Material.SmoothPlastic, roof = Color3.fromRGB(120, 126, 138), accent = Color3.fromRGB(200, 210, 230) }

local WorldController = {
	Name = "WorldController",
}

WorldController._parts = {} :: { [string]: Model }
WorldController._cityFolder = nil :: Folder?
WorldController._baseplate = nil :: BasePart?

-- Camera state.
WorldController._focus = Vector3.new(0, 0, 0)
WorldController._distance = 190
WorldController._pitch = math.rad(56)

function WorldController:GetCityFolder(): Folder
	return assert(self._cityFolder, "city folder not ready")
end

function WorldController:GetBaseplate(): BasePart
	return assert(self._baseplate, "baseplate not ready")
end

--- The rendered Model for a building id, if it currently exists.
function WorldController:GetModel(id: string): Model?
	return self._parts[id]
end

-- ---- World construction ---------------------------------------------------

local function makeAnchored(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function WorldController:_buildWorld()
	-- Surrounding water for context and reflection.
	local ocean = makeAnchored("NexusOcean")
	ocean.Size = Vector3.new(WorldGrid.SPAN * 5, 4, WorldGrid.SPAN * 5)
	ocean.Position = Vector3.new(0, -3.2, 0)
	ocean.Material = Enum.Material.Water
	ocean.Color = Color3.fromRGB(30, 58, 92)
	ocean.Transparency = 0.1
	ocean.Parent = Workspace

	-- The buildable land plate.
	local base = makeAnchored("NexusGround")
	base.CanCollide = true
	base.CanQuery = true
	base.Size = Vector3.new(WorldGrid.SPAN, 2, WorldGrid.SPAN)
	base.Position = Vector3.new(0, WorldGrid.GROUND_Y - 1, 0)
	base.Color = Color3.fromRGB(48, 56, 60)
	base.Material = Enum.Material.Slate
	base.Parent = Workspace
	self._baseplate = base

	-- A glowing district grid every few tiles reads as a planned city.
	local step = 8
	local half = WorldGrid.SPAN / 2
	local gridColor = Theme.color.accentDim
	for i = 0, WorldGrid.GRID_SIZE, step do
		local offset = -half + i * WorldGrid.STUDS
		for _, axis in { "x", "z" } do
			local line = makeAnchored("Grid")
			line.Material = Enum.Material.Neon
			line.Color = gridColor
			line.Transparency = 0.62
			line.CanQuery = false
			if axis == "x" then
				line.Size = Vector3.new(0.35, 0.2, WorldGrid.SPAN)
				line.Position = Vector3.new(offset, 0.06, 0)
			else
				line.Size = Vector3.new(WorldGrid.SPAN, 0.2, 0.35)
				line.Position = Vector3.new(0, 0.06, offset)
			end
			line.Parent = base
		end
	end

	-- A brighter neon frame around the whole territory.
	for _, spec in
		{
			{ s = Vector3.new(WorldGrid.SPAN, 0.5, 0.8), p = Vector3.new(0, 0.1, -half) },
			{ s = Vector3.new(WorldGrid.SPAN, 0.5, 0.8), p = Vector3.new(0, 0.1, half) },
			{ s = Vector3.new(0.8, 0.5, WorldGrid.SPAN), p = Vector3.new(-half, 0.1, 0) },
			{ s = Vector3.new(0.8, 0.5, WorldGrid.SPAN), p = Vector3.new(half, 0.1, 0) },
		}
	do
		local edge = makeAnchored("Border")
		edge.Material = Enum.Material.Neon
		edge.Color = Theme.color.accent
		edge.Transparency = 0.25
		edge.CanQuery = false
		edge.Size = spec.s
		edge.Position = spec.p
		edge.Parent = base
	end

	local folder = Instance.new("Folder")
	folder.Name = "NexusCity"
	folder.Parent = Workspace
	self._cityFolder = folder
end

-- ---- Camera ---------------------------------------------------------------

function WorldController:_setupCamera()
	while not Workspace.CurrentCamera do
		task.wait()
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 55

	local dragging = false
	local lastPos: Vector2? = nil

	local function updateCamera()
		local dir = Vector3.new(0, math.sin(self._pitch), math.cos(self._pitch))
		local camPos = self._focus + dir * self._distance
		camera.CFrame = CFrame.lookAt(camPos, self._focus)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			lastPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
			lastPos = nil
		end
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self._distance = math.clamp(self._distance - input.Position.Z * 18, 60, 420)
		elseif dragging and lastPos and
			(input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch)
		then
			if gameProcessed and input.UserInputType == Enum.UserInputType.Touch then
				return
			end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - lastPos
			lastPos = pos
			local speed = self._distance / 600
			self._focus += Vector3.new(-delta.X * speed, 0, -delta.Y * speed)
		end
	end)

	RunService:BindToRenderStep("NexusCamera", Enum.RenderPriority.Camera.Value, function()
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += Vector3.new(0, 0, -1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move += Vector3.new(0, 0, 1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move += Vector3.new(-1, 0, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += Vector3.new(1, 0, 0)
		end
		if move.Magnitude > 0 then
			self._focus += move.Unit * (self._distance * 0.02)
		end
		local lim = WorldGrid.SPAN / 2
		self._focus = Vector3.new(
			math.clamp(self._focus.X, -lim, lim),
			0,
			math.clamp(self._focus.Z, -lim, lim)
		)
		updateCamera()
	end)
end

-- ---- Building rendering ----------------------------------------------------

local function orientedFootprint(def: any, rotation: number): (number, number)
	local w, h = def.footprint.w, def.footprint.h
	if rotation == 90 or rotation == 270 then
		return h, w
	end
	return w, h
end

-- Construct the model for one building at its final transform.
function WorldController:_buildModel(building: any): Model
	local def = Buildings[building.kind]
	local style = STYLE[def.category] or DEFAULT_STYLE
	local w, h = orientedFootprint(def, building.rotation)
	local footW = w * WorldGrid.STUDS
	local footH = h * WorldGrid.STUDS
	local bodyHeight = 4 + building.level * 2.6
	local center = WorldGrid.footprintCenter(building.position.x, building.position.z, w, h)

	local model = Instance.new("Model")
	model.Name = "Building_" .. building.id
	model:SetAttribute("buildingId", building.id)
	model:SetAttribute("level", building.level)
	model:SetAttribute("rot", building.rotation)

	-- Body.
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Material = style.material
	body.Color = style.body
	body.Size = Vector3.new(footW * 0.86, bodyHeight, footH * 0.86)
	body.Position = center + Vector3.new(0, bodyHeight / 2, 0)
	body:SetAttribute("buildingId", building.id)
	body.Parent = model

	-- Roof cap.
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Anchored = true
	roof.CanCollide = false
	roof.TopSurface = Enum.SurfaceType.Smooth
	roof.BottomSurface = Enum.SurfaceType.Smooth
	roof.Material = Enum.Material.Concrete
	roof.Color = style.roof
	roof.Size = Vector3.new(footW * 0.92, 1.2, footH * 0.92)
	roof.Position = center + Vector3.new(0, bodyHeight + 0.6, 0)
	roof:SetAttribute("buildingId", building.id)
	roof.Parent = model

	-- Neon accent ring near the top — glows under bloom.
	local accent = Instance.new("Part")
	accent.Name = "Accent"
	accent.Anchored = true
	accent.CanCollide = false
	accent.CanQuery = false
	accent.Material = Enum.Material.Neon
	accent.Color = style.accent
	accent.Size = Vector3.new(footW * 0.9, 0.5, footH * 0.9)
	accent.Position = center + Vector3.new(0, bodyHeight - 1.2, 0)
	accent.Parent = model

	-- A second accent band for taller buildings.
	if building.level >= 3 then
		local band = accent:Clone()
		band.Name = "Accent2"
		band.Position = center + Vector3.new(0, bodyHeight * 0.55, 0)
		band.Parent = model
	end

	model.PrimaryPart = body
	model.Parent = self:GetCityFolder()

	-- Fade-in.
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local target = part.Transparency
			part.Transparency = 1
			TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
				Transparency = target,
			}):Play()
		end
	end

	return model
end

-- Fade a building for its power/condition state without rebuilding it.
local function setActive(model: Model, active: boolean)
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		if part.Name == "Accent" or part.Name == "Accent2" then
			part.Transparency = active and 0 or 0.8
		else
			part.Transparency = active and 0 or 0.55
		end
	end
end

function WorldController:_syncBuildings(nation: any)
	local seen: { [string]: boolean } = {}

	for id, building in nation.buildings do
		local def = Buildings[building.kind]
		if not def then
			continue
		end
		seen[id] = true

		local model = self._parts[id]
		local fresh = not model
			or model:GetAttribute("level") ~= building.level
			or model:GetAttribute("rot") ~= building.rotation
		if fresh then
			if model then
				model:Destroy()
			end
			model = self:_buildModel(building)
			self._parts[id] = model
		end
		setActive(model, building.active ~= false)
	end

	for id, model in self._parts do
		if not seen[id] then
			model:Destroy()
			self._parts[id] = nil
		end
	end
end

function WorldController:Init()
	self:_buildWorld()
	self:_setupCamera()
end

function WorldController:Start()
	local StateController = require(script.Parent.StateController)
	StateController.Changed:Connect(function(snapshot)
		self:_syncBuildings(snapshot.nation)
	end)
	if StateController:IsReady() then
		self:_syncBuildings(StateController:GetSnapshot().nation)
	end
end

return WorldController
