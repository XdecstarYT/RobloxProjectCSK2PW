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

local Players = game:GetService("Players")

local Buildings = require(ReplicatedStorage.Nexus.Config.Buildings)
local Regions = require(ReplicatedStorage.Nexus.Config.Regions)
local Resources = require(ReplicatedStorage.Nexus.Config.Resources)
local WorldGrid = require(ReplicatedStorage.Nexus.WorldGrid)

local Theme = require(script.Parent.Parent.UI.Theme)

-- How far apart region zones sit in the world, and how far the camera may roam.
local REGION_SPACING = 820
local WORLD_RADIUS = 1500

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
WorldController._regionPads = {} :: { [string]: any }

-- Camera state.
WorldController._focus = Vector3.new(0, 0, 0)
WorldController._distance = 190
WorldController._pitch = math.rad(56)
WorldController._flying = false
WorldController._flyToken = 0
WorldController._gamepadPan = Vector2.zero
WorldController._gamepadZoom = 0
WorldController._pinchStartDist = nil :: number?

-- World-space centre of a region zone, spread out around the central city.
local function regionWorldPos(def: any): Vector3
	return Vector3.new((def.col - 1.5) * REGION_SPACING, 0, (def.row - 1) * REGION_SPACING)
end

local function bonusText(bonus: any): string
	local parts = {}
	for id, amount in bonus do
		table.insert(parts, Resources[id].symbol .. tostring(amount))
	end
	return table.concat(parts, "  ")
end

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

-- Shortest distance from point p to segment a-b, all on the XZ plane.
local function pointSegDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
	return (p - (a + ab * t)).Magnitude
end

-- A simple low-poly tree from primitives (no external assets).
local function makeTree(pos: Vector3, parent: Instance)
	local scale = 0.8 + math.random() * 0.7
	local trunk = makeAnchored("Trunk")
	trunk.Size = Vector3.new(1.6 * scale, 7 * scale, 1.6 * scale)
	trunk.Position = pos + Vector3.new(0, 3.5 * scale, 0)
	trunk.Color = Color3.fromRGB(96, 66, 44)
	trunk.Material = Enum.Material.Wood
	trunk.CanQuery = false
	trunk.Parent = parent

	local canopy = makeAnchored("Canopy")
	canopy.Shape = Enum.PartType.Ball
	canopy.Size = Vector3.new(9 * scale, 9 * scale, 9 * scale)
	canopy.Position = pos + Vector3.new(0, 9 * scale, 0)
	canopy.Color = Color3.fromRGB(70 + math.random(0, 40), 120 + math.random(0, 50), 60)
	canopy.Material = Enum.Material.Grass
	canopy.CanQuery = false
	canopy.Parent = parent
end

local function makeRock(pos: Vector3, parent: Instance)
	local rock = makeAnchored("Rock")
	rock.Shape = Enum.PartType.Ball
	local s = 4 + math.random() * 7
	rock.Size = Vector3.new(s, s * 0.6, s)
	rock.Position = pos + Vector3.new(0, s * 0.2, 0)
	rock.Orientation = Vector3.new(math.random(-20, 20), math.random(0, 360), math.random(-20, 20))
	rock.Color = Color3.fromRGB(110, 112, 118)
	rock.Material = Enum.Material.Rock
	rock.CanQuery = false
	rock.Parent = parent
end

function WorldController:_buildWorld()
	-- Water is real Terrain now (see _buildTerrain), so no ocean part here.

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

	self:_buildRegionZones()
end

-- Physical region zones you can travel to, arranged around the capital.
function WorldController:_buildRegionZones()
	local zones = Instance.new("Folder")
	zones.Name = "NexusRegions"
	zones.Parent = Workspace

	for regionId, def in Regions do
		local center = regionWorldPos(def)

		local pad = makeAnchored("Region_" .. regionId)
		pad.Size = Vector3.new(300, 8, 300)
		pad.Position = center + Vector3.new(0, -4, 0)
		pad.Material = Enum.Material.SmoothPlastic
		pad.Color = Theme.color.panelLight
		pad.CanQuery = false
		pad.Parent = zones

		local box = Instance.new("SelectionBox")
		box.Adornee = pad
		box.LineThickness = 0.4
		box.Color3 = Theme.color.stroke
		box.SurfaceTransparency = 0.85
		box.Parent = pad

		-- Floating label so the region reads clearly from the overhead camera.
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(220, 96)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 26, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 4000
		billboard.Adornee = pad
		billboard.Parent = pad

		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Theme.color.panel
		card.BackgroundTransparency = 0.1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.color.stroke
		stroke.Thickness = 1.5
		stroke.Parent = card
		card.Parent = billboard

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.fromOffset(8, 6)
		nameLabel.Size = UDim2.new(1, -16, 0, 24)
		nameLabel.Font = Theme.font.bold
		nameLabel.Text = def.displayName
		nameLabel.TextColor3 = Theme.color.text
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local bonusLabel = Instance.new("TextLabel")
		bonusLabel.BackgroundTransparency = 1
		bonusLabel.Position = UDim2.fromOffset(8, 34)
		bonusLabel.Size = UDim2.new(1, -16, 0, 22)
		bonusLabel.Font = Theme.font.medium
		bonusLabel.Text = bonusText(def.bonus)
		bonusLabel.TextColor3 = Theme.color.good
		bonusLabel.TextScaled = true
		bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
		bonusLabel.Parent = card

		local ownerLabel = Instance.new("TextLabel")
		ownerLabel.Name = "Owner"
		ownerLabel.BackgroundTransparency = 1
		ownerLabel.Position = UDim2.fromOffset(8, 60)
		ownerLabel.Size = UDim2.new(1, -16, 0, 28)
		ownerLabel.Font = Theme.font.regular
		ownerLabel.Text = "Unclaimed"
		ownerLabel.TextColor3 = Theme.color.textDim
		ownerLabel.TextScaled = true
		ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
		ownerLabel.Parent = card

		self._regionPads[regionId] = { pad = pad, box = box, owner = ownerLabel }
	end
end

-- Generate a real terrain continent: ocean, land, region flats, hills, a rough
-- coastline, roads to each region, and scattered trees/rocks. All client-side.
function WorldController:_buildTerrain()
	local Terrain = Workspace.Terrain
	pcall(function()
		Terrain:Clear()
	end)

	local LAND_HX, LAND_HZ = 1520, 1160

	-- Ocean (surface at y = -2) then the continent slab (top at y = -1).
	Terrain:FillBlock(CFrame.new(0, -12, 0), Vector3.new(LAND_HX * 2 + 900, 20, LAND_HZ * 2 + 900), Enum.Material.Water)
	Terrain:FillBlock(CFrame.new(0, -5, 0), Vector3.new(LAND_HX * 2, 8, LAND_HZ * 2), Enum.Material.Grass)

	-- Flatten the land beneath each region, and remember the centres + roads.
	local centers = {}
	for _, def in Regions do
		local c = regionWorldPos(def)
		table.insert(centers, c)
		Terrain:FillBlock(CFrame.new(c.X, -4, c.Z), Vector3.new(320, 8, 320), Enum.Material.Grass)
	end

	local roads = {}
	for _, c in centers do
		local dir = Vector3.new(c.X, 0, c.Z)
		if dir.Magnitude > 1 then
			table.insert(roads, { a = dir.Unit * 300, b = c })
		end
	end
	local function roadDist(x: number, z: number): number
		local p = Vector3.new(x, 0, z)
		local best = math.huge
		for _, seg in roads do
			best = math.min(best, pointSegDist(p, seg.a, seg.b))
		end
		return best
	end
	local function nearRegion(x: number, z: number, pad: number): boolean
		for _, c in centers do
			if (Vector3.new(x, 0, z) - Vector3.new(c.X, 0, c.Z)).Magnitude < pad then
				return true
			end
		end
		return false
	end
	local function nearCity(x: number, z: number): boolean
		return (x * x + z * z) < 340 * 340
	end

	-- Rolling hills that avoid the city, regions and roads.
	for _ = 1, 48 do
		local x = math.random(-LAND_HX + 120, LAND_HX - 120)
		local z = math.random(-LAND_HZ + 120, LAND_HZ - 120)
		if not nearCity(x, z) and not nearRegion(x, z, 210) and roadDist(x, z) > 44 then
			local mat = math.random() < 0.22 and Enum.Material.Rock or Enum.Material.Grass
			Terrain:FillBall(Vector3.new(x, math.random(2, 12), z), math.random(28, 66), mat)
		end
	end

	-- Rough up the coastline with a few bays (water) and peninsulas (land).
	for _ = 1, 14 do
		local onX = math.random() < 0.5
		local x = onX and (math.random() < 0.5 and -LAND_HX or LAND_HX) or math.random(-LAND_HX, LAND_HX)
		local z = onX and math.random(-LAND_HZ, LAND_HZ) or (math.random() < 0.5 and -LAND_HZ or LAND_HZ)
		local water = math.random() < 0.5
		Terrain:FillBall(Vector3.new(x, water and -3 or -4, z), math.random(70, 150), water and Enum.Material.Water or Enum.Material.Grass)
	end

	self:_buildRoads(roads)
	self:_buildScenery(roadDist, nearCity, nearRegion)
end

function WorldController:_buildRoads(roads: { any })
	local folder = Instance.new("Folder")
	folder.Name = "NexusRoads"
	folder.Parent = Workspace
	for _, seg in roads do
		local mid = (seg.a + seg.b) / 2
		local length = (seg.b - seg.a).Magnitude
		local road = makeAnchored("Road")
		road.Size = Vector3.new(16, 0.6, length)
		road.CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.2, 0), Vector3.new(seg.b.X, 0.2, seg.b.Z))
		road.Color = Color3.fromRGB(48, 48, 54)
		road.Material = Enum.Material.Asphalt
		road.CanQuery = false
		road.Parent = folder
	end
end

function WorldController:_buildScenery(roadDist, nearCity, nearRegion)
	local folder = Instance.new("Folder")
	folder.Name = "NexusScenery"
	folder.Parent = Workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }

	-- Drop props onto the terrain surface via a downward raycast, skipping the
	-- city, regions, roads and anything underwater.
	local function scatter(count: number, place: (Vector3, Instance) -> ())
		local placed = 0
		local attempts = 0
		while placed < count and attempts < count * 4 do
			attempts += 1
			local x = math.random(-1450, 1450)
			local z = math.random(-1100, 1100)
			if nearCity(x, z) or nearRegion(x, z, 170) or roadDist(x, z) < 22 then
				continue
			end
			local hit = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
			if hit and hit.Material ~= Enum.Material.Water and hit.Position.Y > -1.4 then
				place(hit.Position, folder)
				placed += 1
			end
		end
	end

	scatter(150, makeTree)
	scatter(46, makeRock)
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
		if gameProcessed or self._flying then
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

	-- Two-finger pinch to zoom (touch).
	UserInputService.TouchPinch:Connect(function(_touchPositions, scale, _velocity, state)
		if self._flying then
			return
		end
		if state == Enum.UserInputState.Begin then
			self._pinchStartDist = self._distance
		elseif state == Enum.UserInputState.Change and self._pinchStartDist and scale > 0 then
			self._distance = math.clamp(self._pinchStartDist / scale, 60, 420)
		end
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if self._flying then
			return -- manual control is frozen during a cinematic fly
		end
		-- Gamepad: left stick pans, right stick zooms (stored, applied per frame).
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			self._gamepadPan = Vector2.new(input.Position.X, input.Position.Y)
			return
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			self._gamepadZoom = input.Position.Y
			return
		end
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
		if not self._flying then
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
			-- Gamepad left-stick pan (deadzone) and right-stick zoom.
			if self._gamepadPan.Magnitude > 0.15 then
				self._focus += Vector3.new(self._gamepadPan.X, 0, -self._gamepadPan.Y)
					* (self._distance * 0.03)
			end
			if math.abs(self._gamepadZoom) > 0.15 then
				self._distance = math.clamp(self._distance - self._gamepadZoom * 6, 60, 420)
			end
			self._focus = Vector3.new(
				math.clamp(self._focus.X, -WORLD_RADIUS, WORLD_RADIUS),
				0,
				math.clamp(self._focus.Z, -WORLD_RADIUS, WORLD_RADIUS)
			)
		end
		updateCamera()
	end)
end

-- ---- Cinematic camera -----------------------------------------------------

--- GTA-style move: zoom out, glide to the target, zoom back in. Manual control
--- is frozen for the duration. Re-calling interrupts the previous fly cleanly.
function WorldController:FlyTo(targetFocus: Vector3, targetDistance: number, duration: number?)
	duration = duration or 1.5
	local startFocus = self._focus
	local startDist = self._distance
	local travel = (targetFocus - startFocus).Magnitude
	-- Bigger journeys pull the camera further out at the midpoint.
	local arc = math.clamp(travel * 0.4, 30, 900)

	self._flyToken += 1
	local token = self._flyToken
	self._flying = true

	task.spawn(function()
		local t0 = os.clock()
		while self._flyToken == token do
			local raw = (os.clock() - t0) / (duration :: number)
			if raw >= 1 then
				break
			end
			local e = raw * raw * (3 - 2 * raw) -- smoothstep ease in/out
			self._focus = startFocus:Lerp(targetFocus, e)
			self._distance = startDist + (targetDistance - startDist) * e + arc * math.sin(math.pi * raw)
			RunService.RenderStepped:Wait()
		end
		if self._flyToken == token then
			self._focus = targetFocus
			self._distance = targetDistance
			self._flying = false
		end
	end)
end

--- Fly to a region zone by id.
function WorldController:FlyToRegion(regionId: string)
	local def = Regions[regionId]
	if def then
		self:FlyTo(regionWorldPos(def), 150)
	end
end

--- Fly back to the capital city.
function WorldController:FlyToCapital()
	self:FlyTo(Vector3.new(0, 0, 0), 190)
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

-- Recolour region zones to match ownership (you / ally / AI / rival / unclaimed).
function WorldController:_updateRegionPads(map: { any }?)
	local StateController = require(script.Parent.StateController)
	local WorldStateController = require(script.Parent.WorldStateController)
	map = map or WorldStateController:GetTerritory()
	local myId = Players.LocalPlayer.UserId
	local nation = StateController:GetNation()
	local allies = nation and nation.diplomacy and nation.diplomacy.allies or {}

	local byId: { [string]: any } = {}
	for _, entry in map :: { any } do
		byId[entry.id] = entry
	end

	for regionId, refs in self._regionPads do
		local entry = byId[regionId]
		local color, tag
		if entry and entry.ownerId then
			local ownerId = entry.ownerId
			if ownerId == myId then
				color, tag = Theme.color.accent, "Your territory"
			elseif allies[tostring(ownerId)] then
				color, tag = Theme.color.good, "Ally: " .. (entry.ownerName or "?")
			elseif ownerId < 0 then
				color, tag = Theme.color.warn, entry.ownerName or "AI"
			else
				color, tag = Color3.fromRGB(170, 130, 230), entry.ownerName or "Rival"
			end
		else
			color, tag = Theme.color.stroke, "Unclaimed"
		end
		refs.pad.Color = color:Lerp(Theme.color.bg, 0.6)
		refs.box.Color3 = color
		refs.owner.Text = tag
		refs.owner.TextColor3 = color
	end
end

function WorldController:Init()
	self:_buildWorld()
	self:_setupCamera()
	-- Terrain is heavier, so generate it just after the city is up.
	task.spawn(function()
		local ok, err = pcall(function()
			self:_buildTerrain()
		end)
		if not ok then
			warn("[Nexus] terrain generation failed: " .. tostring(err))
		end
	end)
end

function WorldController:Start()
	local StateController = require(script.Parent.StateController)
	local WorldStateController = require(script.Parent.WorldStateController)

	StateController.Changed:Connect(function(snapshot)
		self:_syncBuildings(snapshot.nation)
		self:_updateRegionPads(nil)
	end)
	WorldStateController.TerritoryChanged:Connect(function(map)
		self:_updateRegionPads(map)
	end)
	if StateController:IsReady() then
		self:_syncBuildings(StateController:GetSnapshot().nation)
	end
	self:_updateRegionPads(nil)
end

return WorldController
