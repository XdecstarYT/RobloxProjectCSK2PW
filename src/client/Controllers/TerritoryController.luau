--!strict
--[[
	Controllers/TerritoryController.luau
	The world map: a grid of claimable regions laid out from the Regions config
	and coloured by who holds each (you, an ally, an AI, another player, or
	unclaimed). Click a region to spend influence and claim it — the server
	enforces adjacency, cost and ownership.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Regions = require(ReplicatedStorage.Nexus.Config.Regions)
local Resources = require(ReplicatedStorage.Nexus.Config.Resources)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Format = require(script.Parent.Parent.UI.Format)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local CELL = 82
local GAP = 6

local TerritoryController = {
	Name = "TerritoryController",
}

TerritoryController._panel = nil :: Frame?
TerritoryController._cells = {} :: { [string]: Frame }

local function bonusSummary(bonus: any): string
	local parts = {}
	for id, amount in bonus do
		table.insert(parts, Resources[id].symbol .. Format.abbrev(amount))
	end
	return table.concat(parts, " ")
end

function TerritoryController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local board = Create("Frame", {
		Position = UDim2.fromOffset(12, 44),
		Size = UDim2.fromOffset(4 * CELL + 3 * GAP, 3 * CELL + 2 * GAP),
		BackgroundTransparency = 1,
	})

	for regionId, def in Regions do
		local cell = Create("TextButton", {
			Name = regionId,
			AutoButtonColor = true,
			BackgroundColor3 = Theme.color.panelLight,
			Position = UDim2.fromOffset(def.col * (CELL + GAP), def.row * (CELL + GAP)),
			Size = UDim2.fromOffset(CELL, CELL),
			Text = "",
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(6, 5),
					Size = UDim2.new(1, -12, 0, 24),
					Font = Theme.font.bold,
					Text = def.displayName,
					TextColor3 = Theme.color.text,
					TextSize = 11,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(6, 34),
					Size = UDim2.new(1, -12, 0, 14),
					Font = Theme.font.medium,
					Text = bonusSummary(def.bonus),
					TextColor3 = Theme.color.good,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					Name = "Owner",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 6, 1, -5),
					Size = UDim2.new(1, -12, 0, 24),
					Font = Theme.font.regular,
					Text = ("◆%d to claim"):format(def.cost),
					TextColor3 = Theme.color.textDim,
					TextSize = 10,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Bottom,
				}),
			},
			[Create.Event] = { Activated = function()
				-- Cinematic travel to the region, then attempt to claim/expand.
				local WorldController = require(script.Parent.WorldController)
				WorldController:FlyToRegion(regionId)
				if self._panel then
					Motion.hide(self._panel)
				end
				task.spawn(function()
					Net.request(NetRoutes.CLAIM_REGION, { regionId = regionId })
				end)
			end },
		}) :: Frame
		cell.Parent = board
		self._cells[regionId] = cell
	end

	local panel = Create("Frame", {
		Name = "TerritoryPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4 * CELL + 3 * GAP + 24, 3 * CELL + 2 * GAP + 60),
		BackgroundColor3 = Theme.color.panel,
		Visible = false,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -140, 0, 24),
				Font = Theme.font.bold,
				Text = "🗺 World Map",
				TextColor3 = Theme.color.text,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 8),
				Size = UDim2.fromOffset(112, 28),
				BackgroundColor3 = Theme.color.accentDim,
				Font = Theme.font.bold,
				Text = "🏙 Capital",
				TextColor3 = Theme.color.text,
				TextSize = 13,
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 8) }) },
				[Create.Event] = { Activated = function()
					local WorldController = require(script.Parent.WorldController)
					WorldController:FlyToCapital()
					if self._panel then
						Motion.hide(self._panel)
					end
				end },
			}),
			board,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function TerritoryController:_refresh()
	local WorldStateController = require(script.Parent.WorldStateController)
	local StateController = require(script.Parent.StateController)
	local map = WorldStateController:GetTerritory()
	local myId = Players.LocalPlayer.UserId
	local nation = StateController:GetNation()
	local allies = nation and nation.diplomacy and nation.diplomacy.allies or {}

	local ownerById: { [string]: any } = {}
	for _, entry in map do
		ownerById[entry.id] = entry
	end

	for regionId, cell in self._cells do
		local entry = ownerById[regionId]
		local ownerLabel = cell:FindFirstChild("Owner") :: TextLabel
		local def = Regions[regionId]
		if entry and entry.ownerId then
			local ownerId = entry.ownerId
			local color, tag
			if ownerId == myId then
				color, tag = Theme.color.accent, "You"
			elseif allies[tostring(ownerId)] then
				color, tag = Theme.color.good, "Ally: " .. (entry.ownerName or "?")
			elseif ownerId < 0 then
				color, tag = Theme.color.warn, entry.ownerName or "AI"
			else
				color, tag = Color3.fromRGB(170, 130, 230), entry.ownerName or "Rival"
			end
			cell.BackgroundColor3 = color:Lerp(Theme.color.bg, 0.55)
			local stroke = cell:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
			end
			ownerLabel.Text = tag
			ownerLabel.TextColor3 = color
		else
			cell.BackgroundColor3 = Theme.color.panelLight
			local stroke = cell:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Theme.color.stroke
			end
			ownerLabel.Text = ("◆%d to claim"):format(def.cost)
			ownerLabel.TextColor3 = Theme.color.textDim
		end
	end
end

function TerritoryController:Start()
	local HudController = require(script.Parent.HudController)
	local WorldStateController = require(script.Parent.WorldStateController)
	local StateController = require(script.Parent.StateController)

	self:_build()
	HudController:AddButton("🗺 Territory", function()
		if self._panel then
			Motion.toggle(self._panel)
		end
	end)

	WorldStateController.TerritoryChanged:Connect(function()
		self:_refresh()
	end)
	StateController.Changed:Connect(function()
		self:_refresh()
	end)
	self:_refresh()
end

return TerritoryController
