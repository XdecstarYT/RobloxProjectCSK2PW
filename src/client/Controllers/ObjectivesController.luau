--!strict
--[[
	Controllers/ObjectivesController.luau
	The goals screen: every milestone with its reward and a done/to-do state,
	plus an overall completion count. Reads the replicated nation.objectives set.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Objectives = require(ReplicatedStorage.Nexus.Config.Objectives)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local ObjectivesController = {
	Name = "ObjectivesController",
}

ObjectivesController._panel = nil :: Frame?
ObjectivesController._rows = {} :: { [string]: any }
ObjectivesController._header = nil :: TextLabel?

local function rewardText(reward): string
	local parts = {}
	for res, amount in reward do
		table.insert(parts, ("+%d %s"):format(amount, res))
	end
	return table.concat(parts, ", ")
end

function ObjectivesController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local list = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 66),
		Size = UDim2.new(1, -20, 1, -76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	}) :: ScrollingFrame

	for i, obj in Objectives do
		local check = Create("TextLabel", {
			Name = "Check",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(28, 48),
			Font = Theme.font.black,
			Text = "○",
			TextColor3 = Theme.color.textDim,
			TextSize = 20,
		}) :: TextLabel

		local row = Create("Frame", {
			Name = obj.id,
			LayoutOrder = i,
			BackgroundColor3 = Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 56),
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 6),
					Size = UDim2.new(1, -50, 0, 18),
					Font = Theme.font.bold,
					Text = obj.title,
					TextColor3 = Theme.color.text,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 24),
					Size = UDim2.new(1, -50, 0, 16),
					Font = Theme.font.regular,
					Text = obj.desc,
					TextColor3 = Theme.color.textDim,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(12, 40),
					Size = UDim2.new(1, -50, 0, 14),
					Font = Theme.font.medium,
					Text = rewardText(obj.reward),
					TextColor3 = Theme.color.accent2,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				check,
			},
		}) :: Frame
		row.Parent = list
		self._rows[obj.id] = { row = row, check = check }
	end

	self._header = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 20),
		Font = Theme.font.medium,
		Text = "0 / " .. #Objectives .. " complete",
		TextColor3 = Theme.color.textDim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel

	local panel = Create("Frame", {
		Name = "ObjectivesPanel",
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
				Text = "🎯 Objectives",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			self._header,
			list,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function ObjectivesController:_refresh()
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	local done = 0
	for id, ref in self._rows do
		local complete = nation.objectives and nation.objectives[id] == true
		if complete then
			done += 1
			ref.check.Text = "✓"
			ref.check.TextColor3 = Theme.color.good
			ref.row.BackgroundColor3 = Color3.fromRGB(30, 48, 36)
		else
			ref.check.Text = "○"
			ref.check.TextColor3 = Theme.color.textDim
			ref.row.BackgroundColor3 = Theme.color.panelLight
		end
	end
	if self._header then
		self._header.Text = ("%d / %d complete"):format(done, #Objectives)
	end
end

function ObjectivesController:Start()
	local HudController = require(script.Parent.HudController)
	local StateController = require(script.Parent.StateController)

	self:_build()
	HudController:AddButton("🎯 Goals", function()
		if self._panel then
			Motion.toggle(self._panel)
		end
	end)

	StateController.Changed:Connect(function()
		self:_refresh()
	end)
	if StateController:IsReady() then
		self:_refresh()
	end
end

return ObjectivesController
