--!strict
--[[
	Controllers/LeaderboardController.luau
	A ranked table of every nation in the world (players and AI) by power score.
	Rebuilds from the WORLD_SYNC directory; the local player's row is highlighted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(script.Parent.Parent.UI.Format)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local LeaderboardController = {
	Name = "LeaderboardController",
}

LeaderboardController._panel = nil :: Frame?
LeaderboardController._list = nil :: ScrollingFrame?

function LeaderboardController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local list = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	}) :: ScrollingFrame
	self._list = list

	local panel = Create("Frame", {
		Name = "LeaderboardPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 460),
		BackgroundColor3 = Theme.color.panel,
		Visible = false,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 0, 22),
				Font = Theme.font.bold,
				Text = "🏆 Global Leaderboard",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			list,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function LeaderboardController:_refresh(directory: { any })
	local list = self._list
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	local myId = Players.LocalPlayer.UserId
	for _, row in directory do
		local mine = row.id == myId
		local rowFrame = Create("Frame", {
			LayoutOrder = row.rank,
			BackgroundColor3 = mine and Theme.color.accentDim or Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 40),
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.fromOffset(34, 40),
					Font = Theme.font.black,
					Text = "#" .. row.rank,
					TextColor3 = row.rank <= 3 and Theme.color.accent2 or Theme.color.textDim,
					TextSize = 15,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(48, 4),
					Size = UDim2.new(1, -140, 0, 18),
					Font = Theme.font.bold,
					Text = row.name .. (row.isAI and "  🤖" or ""),
					TextColor3 = Theme.color.text,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(48, 22),
					Size = UDim2.new(1, -140, 0, 14),
					Font = Theme.font.regular,
					Text = ("Pop %s · GDP %s"):format(Format.abbrev(row.population), Format.abbrev(row.gdp)),
					TextColor3 = Theme.color.textDim,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.fromOffset(80, 40),
					Font = Theme.font.bold,
					Text = "⚙ " .. Format.abbrev(row.power),
					TextColor3 = Theme.color.accent,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
			},
		})
		rowFrame.Parent = list
	end
end

function LeaderboardController:Start()
	local HudController = require(script.Parent.HudController)
	local WorldStateController = require(script.Parent.WorldStateController)

	self:_build()
	HudController:AddButton("🏆 Ranks", function()
		if self._panel then
			Motion.toggle(self._panel)
		end
	end)

	WorldStateController.DirectoryChanged:Connect(function(directory)
		self:_refresh(directory)
	end)
	self:_refresh(WorldStateController:GetDirectory())
end

return LeaderboardController
