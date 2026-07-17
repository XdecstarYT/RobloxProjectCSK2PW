--!strict
--[[
	Controllers/MinimapController.luau
	A corner minimap: a top-down schematic of the world with the capital at
	centre, a coloured dot per region (by ownership), and a live marker for where
	the camera is looking. Click anywhere on it to cinematically fly there.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Regions = require(ReplicatedStorage.Nexus.Config.Regions)

local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)

local SIZE = 172
local WORLD = 1500 -- half-extent mapped to the minimap edges

local MinimapController = {
	Name = "MinimapController",
}

MinimapController._dots = {} :: { [string]: Frame }
MinimapController._camMarker = nil :: Frame?
MinimapController._map = nil :: TextButton?

local function worldToUV(x: number, z: number): (number, number)
	return math.clamp(x / (2 * WORLD) + 0.5, 0, 1), math.clamp(z / (2 * WORLD) + 0.5, 0, 1)
end

local function dot(color: Color3, sizePx: number): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(sizePx, sizePx),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Create("UIStroke", { Color = Theme.color.bg, Thickness = 1 }),
		},
	}) :: Frame
end

function MinimapController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local map = Create("TextButton", {
		Name = "Minimap",
		Text = "",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -70),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(22, 40, 34),
		AutoButtonColor = false,
		ClipsDescendants = true,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Create("UIStroke", { Color = Theme.color.accent, Thickness = 1.5, Transparency = 0.2 }),
			-- Faint water border ring implied by a darker inset.
			Create("Frame", {
				Name = "Land",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.86, 0.86),
				BackgroundColor3 = Color3.fromRGB(46, 74, 52),
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
			}),
		},
	}) :: TextButton
	self._map = map

	-- Capital marker at centre.
	local capital = dot(Theme.color.accent2, 10)
	capital.Position = UDim2.fromScale(0.5, 0.5)
	capital.Parent = map

	-- Region dots (positions fixed; colours update with ownership).
	for regionId in Regions do
		local WorldController = require(script.Parent.WorldController)
		local pos = WorldController:RegionWorldPos(regionId)
		if pos then
			local u, v = worldToUV(pos.X, pos.Z)
			local d = dot(Theme.color.stroke, 8)
			d.Position = UDim2.fromScale(u, v)
			d.Parent = map
			self._dots[regionId] = d
		end
	end

	-- Camera focus marker.
	self._camMarker = dot(Color3.fromRGB(255, 255, 255), 7)
	local marker = self._camMarker :: Frame
	marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	marker.Parent = map

	map.Parent = gui

	-- Click / tap to fly there.
	map.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local rel = Vector2.new(input.Position.X, input.Position.Y) - map.AbsolutePosition
		local u = math.clamp(rel.X / map.AbsoluteSize.X, 0, 1)
		local v = math.clamp(rel.Y / map.AbsoluteSize.Y, 0, 1)
		local worldX = (u - 0.5) * 2 * WORLD
		local worldZ = (v - 0.5) * 2 * WORLD
		local WorldController = require(script.Parent.WorldController)
		WorldController:FlyTo(Vector3.new(worldX, 0, worldZ), 150)
	end)
end

function MinimapController:_refreshColors()
	local StateController = require(script.Parent.StateController)
	local WorldStateController = require(script.Parent.WorldStateController)
	local myId = Players.LocalPlayer.UserId
	local nation = StateController:GetNation()
	local allies = nation and nation.diplomacy and nation.diplomacy.allies or {}
	local byId: { [string]: any } = {}
	for _, entry in WorldStateController:GetTerritory() do
		byId[entry.id] = entry
	end
	for regionId, d in self._dots do
		local entry = byId[regionId]
		local color = Theme.color.stroke
		if entry and entry.ownerId then
			local o = entry.ownerId
			if o == myId then
				color = Theme.color.accent
			elseif allies[tostring(o)] then
				color = Theme.color.good
			elseif o < 0 then
				color = Theme.color.warn
			else
				color = Color3.fromRGB(170, 130, 230)
			end
		end
		d.BackgroundColor3 = color
	end
end

function MinimapController:Start()
	local WorldStateController = require(script.Parent.WorldStateController)
	local StateController = require(script.Parent.StateController)
	local WorldController = require(script.Parent.WorldController)

	self:_build()
	WorldStateController.TerritoryChanged:Connect(function()
		self:_refreshColors()
	end)
	StateController.Changed:Connect(function()
		self:_refreshColors()
	end)
	self:_refreshColors()

	-- Track the camera focus on the map.
	RunService.RenderStepped:Connect(function()
		local marker = self._camMarker
		if not marker then
			return
		end
		local focus = WorldController:GetFocus()
		local u, v = worldToUV(focus.X, focus.Z)
		marker.Position = UDim2.fromScale(u, v)
	end)
end

return MinimapController
