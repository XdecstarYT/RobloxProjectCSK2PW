--!strict
--[[
	Controllers/WorldController.luau
	Builds the 3D city view: a ground plate, an RTS-style overhead camera you can
	pan and zoom, and one part per building rendered from the replicated snapshot.

	Visuals are intentionally client-side and non-authoritative — the server owns
	the data; this controller only draws it. That keeps the network light and lets
	the world be re-themed (or swapped for Toolbox models) without touching
	gameplay code. Parts are tagged with a `buildingId` attribute so BuildController
	can pick them for selection.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Buildings = require(ReplicatedStorage.Nexus.Config.Buildings)
local WorldGrid = require(ReplicatedStorage.Nexus.WorldGrid)

local Theme = require(script.Parent.Parent.UI.Theme)

local CATEGORY_COLOR: { [string]: Color3 } = {
	Housing = Color3.fromRGB(120, 170, 235),
	Power = Color3.fromRGB(240, 200, 90),
	Food = Color3.fromRGB(140, 200, 110),
	Industry = Color3.fromRGB(200, 140, 90),
	Commerce = Color3.fromRGB(150, 210, 200),
	Research = Color3.fromRGB(150, 130, 235),
	Services = Color3.fromRGB(220, 150, 200),
	Government = Color3.fromRGB(230, 230, 240),
}

local WorldController = {
	Name = "WorldController",
}

WorldController._parts = {} :: { [string]: BasePart }
WorldController._cityFolder = nil :: Folder?
WorldController._baseplate = nil :: BasePart?

-- Camera state.
WorldController._focus = Vector3.new(0, 0, 0)
WorldController._distance = 180
WorldController._pitch = math.rad(58)

function WorldController:GetCityFolder(): Folder
	return assert(self._cityFolder, "city folder not ready")
end

function WorldController:GetBaseplate(): BasePart
	return assert(self._baseplate, "baseplate not ready")
end

-- ---- World construction ---------------------------------------------------

function WorldController:_buildWorld()
	local base = Instance.new("Part")
	base.Name = "NexusGround"
	base.Anchored = true
	base.Size = Vector3.new(WorldGrid.SPAN, 1, WorldGrid.SPAN)
	base.Position = Vector3.new(0, WorldGrid.GROUND_Y - 0.5, 0)
	base.Color = Color3.fromRGB(38, 46, 42)
	base.Material = Enum.Material.Grass
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = Workspace

	-- A subtle border so the buildable area reads as a defined territory.
	local border = Instance.new("SelectionBox")
	border.Adornee = base
	border.Color3 = Theme.color.accentDim
	border.LineThickness = 0.2
	border.Transparency = 0.4
	border.Parent = base

	self._baseplate = base

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
			self._distance = math.clamp(self._distance - input.Position.Z * 18, 60, 400)
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
			-- Screen-drag pans the focus across the ground plane.
			self._focus += Vector3.new(-delta.X * speed, 0, -delta.Y * speed)
		end
	end)

	RunService:BindToRenderStep("NexusCamera", Enum.RenderPriority.Camera.Value, function()
		-- Keyboard panning (PC).
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
		-- Keep the focus over the map.
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

local function makePart(): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	return part
end

function WorldController:_syncBuildings(nation: any)
	local folder = self:GetCityFolder()
	local seen: { [string]: boolean } = {}

	for id, building in nation.buildings do
		local def = Buildings[building.kind]
		if not def then
			continue
		end
		seen[id] = true

		local rot = building.rotation
		local w, h = def.footprint.w, def.footprint.h
		if rot == 90 or rot == 270 then
			w, h = h, w
		end
		local height = 4 + building.level * 2.5
		local center = WorldGrid.footprintCenter(building.position.x, building.position.z, w, h)

		local part = self._parts[id]
		if not part then
			part = makePart()
			part:SetAttribute("buildingId", id)
			part.Parent = folder
			self._parts[id] = part
		end
		part.Size = Vector3.new(w * WorldGrid.STUDS * 0.9, height, h * WorldGrid.STUDS * 0.9)
		part.Position = center + Vector3.new(0, height / 2, 0)
		part.Color = CATEGORY_COLOR[def.category] or Color3.fromRGB(180, 180, 180)
		-- Derelict / offline buildings read as faded.
		part.Transparency = building.active and 0 or 0.5
	end

	for id, part in self._parts do
		if not seen[id] then
			part:Destroy()
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
