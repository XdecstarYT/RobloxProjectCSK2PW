--!strict
--[[
	Controllers/BuildController.luau
	Everything the player touches to shape their city:
	  * a categorised build menu (locked entries reveal as tech unlocks),
	  * grid placement with a live ghost that turns red when a spot is invalid,
	    rotates with R and cancels with Escape,
	  * click-to-select an existing building for upgrade / repair / demolish.

	Client-side validity (bounds, overlap, affordability) only drives the ghost
	colour and button states — every action is re-validated by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local ResourceMath = require(ReplicatedStorage.Nexus.ResourceMath)
local WorldGrid = require(ReplicatedStorage.Nexus.WorldGrid)
local Buildings = require(ReplicatedStorage.Nexus.Config.Buildings)

local Create = require(script.Parent.Parent.UI.Create)
local Format = require(script.Parent.Parent.UI.Format)
local Theme = require(script.Parent.Parent.UI.Theme)

local BuildController = {
	Name = "BuildController",
}

BuildController._panel = nil :: Frame?
BuildController._selectionPanel = nil :: Frame?
BuildController._selectedId = nil :: string?
BuildController._placingKind = nil :: string?
BuildController._placingRotation = 0
BuildController._ghost = nil :: BasePart?
BuildController._buttons = {} :: { { button: TextButton, kind: string } }

-- ---- Helpers --------------------------------------------------------------

local function orientedFootprint(kind: string, rotation: number): (number, number)
	local def = Buildings[kind]
	local w, h = def.footprint.w, def.footprint.h
	if rotation == 90 or rotation == 270 then
		return h, w
	end
	return w, h
end

local function occupancy(nation: any, excludeId: string?): { [string]: boolean }
	local occ = {}
	for id, b in nation.buildings do
		if id == excludeId then
			continue
		end
		local def = Buildings[b.kind]
		if not def then
			continue
		end
		local w, h = orientedFootprint(b.kind, b.rotation)
		for dx = 0, w - 1 do
			for dz = 0, h - 1 do
				occ[(b.position.x + dx) .. "," .. (b.position.z + dz)] = true
			end
		end
	end
	return occ
end

local function costSummary(kind: string, level: number): string
	local cost = Buildings[kind].cost[level] or {}
	local parts = {}
	if cost.money then
		table.insert(parts, "$" .. Format.abbrev(cost.money))
	end
	if cost.materials then
		table.insert(parts, "▣" .. Format.abbrev(cost.materials))
	end
	return table.concat(parts, "  ")
end

local function fireAction(route: string, payload: any)
	task.spawn(function()
		Net.request(route, payload)
	end)
end

-- ---- Build menu -----------------------------------------------------------

function BuildController:_buildMenu()
	local StateController = require(script.Parent.StateController)
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local panel = Create("Frame", {
		Name = "BuildMenu",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(260, 420),
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 0, 22),
				Font = Theme.font.bold,
				Text = "Construction",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("ScrollingFrame", {
				Name = "List",
				Position = UDim2.fromOffset(8, 40),
				Size = UDim2.new(1, -16, 1, -48),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				[Create.Children] = {
					Create("UIListLayout", {
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				},
			}),
		},
	}) :: Frame

	local list = panel:FindFirstChild("List") :: ScrollingFrame

	-- Stable order: by category then display name.
	local order = {}
	for kind in Buildings do
		table.insert(order, kind)
	end
	table.sort(order, function(a, b)
		local da, db = Buildings[a], Buildings[b]
		if da.category ~= db.category then
			return da.category < db.category
		end
		return da.displayName < db.displayName
	end)

	for i, kind in order do
		local def = Buildings[kind]
		local button = Create("TextButton", {
			LayoutOrder = i,
			BackgroundColor3 = Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 52),
			AutoButtonColor = true,
			Text = "",
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 6),
					Size = UDim2.new(1, -16, 0, 18),
					Font = Theme.font.bold,
					Text = def.displayName,
					TextColor3 = Theme.color.text,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					Name = "Sub",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 26),
					Size = UDim2.new(1, -16, 0, 18),
					Font = Theme.font.regular,
					Text = def.category .. "   " .. costSummary(kind, 1),
					TextColor3 = Theme.color.textDim,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			},
			[Create.Event] = {
				Activated = function()
					self:_onPickBuilding(kind)
				end,
			},
		}) :: TextButton
		button.Parent = list
		table.insert(self._buttons, { button = button, kind = kind })
	end

	panel.Parent = gui
	self._panel = panel

	-- Refresh lock state as tech changes.
	StateController.Changed:Connect(function()
		self:_refreshLocks()
	end)
	self:_refreshLocks()
end

function BuildController:_refreshLocks()
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	for _, entry in self._buttons do
		local def = Buildings[entry.kind]
		local locked = def.requiresTech ~= nil and not nation.research.unlocked[def.requiresTech]
		local sub = entry.button:FindFirstChild("Sub") :: TextLabel?
		if locked then
			entry.button.BackgroundColor3 = Theme.color.bg
			if sub then
				sub.Text = "🔒 Requires research"
				sub.TextColor3 = Theme.color.bad
			end
		else
			entry.button.BackgroundColor3 = Theme.color.panelLight
			if sub then
				sub.Text = def.category .. "   " .. costSummary(entry.kind, 1)
				sub.TextColor3 = Theme.color.textDim
			end
		end
	end
end

function BuildController:_onPickBuilding(kind: string)
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	local def = Buildings[kind]
	if nation and def.requiresTech and not nation.research.unlocked[def.requiresTech] then
		local Notif = require(script.Parent.NotificationController)
		Notif:Show("warning", "Locked", "Research required to build " .. def.displayName)
		return
	end
	self:_beginPlacement(kind)
end

-- ---- Placement ------------------------------------------------------------

function BuildController:_beginPlacement(kind: string)
	self:_clearSelection()
	self._placingKind = kind
	self._placingRotation = 0
	if not self._ghost then
		local ghost = Instance.new("Part")
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.Transparency = 0.4
		ghost.Material = Enum.Material.ForceField
		ghost.Parent = Workspace
		self._ghost = ghost
	end
	if self._panel then
		self._panel.Visible = false
	end
end

function BuildController:_cancelPlacement()
	self._placingKind = nil
	if self._ghost then
		self._ghost:Destroy()
		self._ghost = nil
	end
end

-- Raycast the mouse against the baseplate; returns the corner tile for the
-- current footprint (centred on the cursor), or nil if the cursor is off-map.
function BuildController:_cursorTile(): ({ x: number, z: number })?
	local WorldController = require(script.Parent.WorldController)
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WorldController:GetBaseplate() }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if not result then
		return nil
	end

	local w, h = orientedFootprint(self._placingKind :: string, self._placingRotation)
	local tx, tz = WorldGrid.worldToTile(result.Position)
	local cornerX = math.clamp(tx - math.floor(w / 2), 0, Constants.GRID_SIZE - w)
	local cornerZ = math.clamp(tz - math.floor(h / 2), 0, Constants.GRID_SIZE - h)
	return { x = cornerX, z = cornerZ }
end

function BuildController:_isValid(corner: { x: number, z: number }): boolean
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return false
	end
	local kind = self._placingKind :: string
	local w, h = orientedFootprint(kind, self._placingRotation)
	if corner.x + w > Constants.GRID_SIZE or corner.z + h > Constants.GRID_SIZE then
		return false
	end
	local occ = occupancy(nation)
	for dx = 0, w - 1 do
		for dz = 0, h - 1 do
			if occ[(corner.x + dx) .. "," .. (corner.z + dz)] then
				return false
			end
		end
	end
	local cost = Buildings[kind].cost[1] or {}
	return ResourceMath.canAfford(nation.resources, cost)
end

function BuildController:_updateGhost()
	if not self._placingKind or not self._ghost then
		return
	end
	local corner = self:_cursorTile()
	local ghost = self._ghost
	if not corner then
		ghost.Transparency = 1
		return
	end
	local kind = self._placingKind
	local w, h = orientedFootprint(kind, self._placingRotation)
	local height = 6
	local center = WorldGrid.footprintCenter(corner.x, corner.z, w, h)
	ghost.Size = Vector3.new(w * WorldGrid.STUDS * 0.9, height, h * WorldGrid.STUDS * 0.9)
	ghost.Position = center + Vector3.new(0, height / 2, 0)
	local valid = self:_isValid(corner)
	ghost.Transparency = 0.4
	ghost.Color = valid and Theme.color.good or Theme.color.bad
end

function BuildController:_confirmPlacement()
	local corner = self:_cursorTile()
	if not corner or not self._placingKind then
		return
	end
	if not self:_isValid(corner) then
		local Notif = require(script.Parent.NotificationController)
		Notif:Show("warning", "Can't build here")
		return
	end
	fireAction(NetRoutes.PLACE_BUILDING, {
		kind = self._placingKind,
		x = corner.x,
		z = corner.z,
		rotation = self._placingRotation,
	})
	-- Stay in placement mode for rapid building; Escape exits.
end

-- ---- Selection + context actions ------------------------------------------

function BuildController:_pickBuildingUnderCursor(): string?
	local WorldController = require(script.Parent.WorldController)
	local camera = Workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WorldController:GetCityFolder() }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if result and result.Instance then
		return result.Instance:GetAttribute("buildingId") :: string?
	end
	return nil
end

function BuildController:_clearSelection()
	self._selectedId = nil
	if self._selectionPanel then
		self._selectionPanel.Visible = false
	end
end

function BuildController:_select(id: string)
	self._selectedId = id
	self:_refreshSelectionPanel()
	if self._selectionPanel then
		self._selectionPanel.Visible = true
	end
end

function BuildController:_refreshSelectionPanel()
	local panel = self._selectionPanel
	local id = self._selectedId
	if not panel or not id then
		return
	end
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	local building = nation and nation.buildings[id]
	if not building then
		self:_clearSelection()
		return
	end
	local def = Buildings[building.kind]
	local title = panel:FindFirstChild("Title") :: TextLabel
	local info = panel:FindFirstChild("Info") :: TextLabel
	title.Text = def.displayName .. "  (Lv " .. building.level .. ")"
	info.Text = ("Condition %d%%   %s"):format(
		math.floor(building.condition * 100 + 0.5),
		building.active and "Active" or "Offline"
	)
end

function BuildController:_buildSelectionPanel()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local function actionButton(text: string, color: Color3, onClick: () -> ()): TextButton
		return Create("TextButton", {
			BackgroundColor3 = color,
			Size = UDim2.new(0, 96, 1, 0),
			Font = Theme.font.bold,
			Text = text,
			TextColor3 = Theme.color.text,
			TextSize = 14,
			AutoButtonColor = true,
			[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 8) }) },
			[Create.Event] = { Activated = onClick },
		}) :: TextButton
	end

	local panel = Create("Frame", {
		Name = "Selection",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.fromOffset(340, 96),
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
			Create("TextLabel", {
				Name = "Title",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 8),
				Size = UDim2.new(1, -28, 0, 20),
				Font = Theme.font.bold,
				Text = "",
				TextColor3 = Theme.color.text,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextLabel", {
				Name = "Info",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 30),
				Size = UDim2.new(1, -28, 0, 18),
				Font = Theme.font.regular,
				Text = "",
				TextColor3 = Theme.color.textDim,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 54),
				Size = UDim2.new(1, -28, 0, 34),
				[Create.Children] = {
					Create("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					actionButton("Upgrade", Theme.color.accentDim, function()
						if self._selectedId then
							fireAction(NetRoutes.UPGRADE_BUILDING, { id = self._selectedId })
						end
					end),
					actionButton("Repair", Theme.color.panelLight, function()
						if self._selectedId then
							fireAction(NetRoutes.REPAIR_BUILDING, { id = self._selectedId })
						end
					end),
					actionButton("Demolish", Color3.fromRGB(120, 50, 50), function()
						if self._selectedId then
							fireAction(NetRoutes.DEMOLISH_BUILDING, { id = self._selectedId })
							self:_clearSelection()
						end
					end),
				},
			}),
		},
	}) :: Frame
	panel.Parent = gui
	self._selectionPanel = panel
end

-- ---- Input ----------------------------------------------------------------

function BuildController:_bindInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.R and self._placingKind then
			self._placingRotation = (self._placingRotation + 90) % 360
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			self:_cancelPlacement()
			self:_clearSelection()
			return
		end
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if self._placingKind then
				self:_confirmPlacement()
			else
				local id = self:_pickBuildingUnderCursor()
				if id then
					self:_select(id)
				else
					self:_clearSelection()
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if self._placingKind then
			self:_updateGhost()
		end
	end)
end

-- ---- Lifecycle ------------------------------------------------------------

function BuildController:Start()
	local HudController = require(script.Parent.HudController)
	local StateController = require(script.Parent.StateController)

	self:_buildMenu()
	self:_buildSelectionPanel()
	self:_bindInput()

	HudController:AddButton("🏗 Build", function()
		if self._placingKind then
			self:_cancelPlacement()
			return
		end
		if self._panel then
			self._panel.Visible = not self._panel.Visible
		end
	end)

	StateController.Changed:Connect(function()
		self:_refreshSelectionPanel()
	end)
end

return BuildController
