--!strict
--[[
	Controllers/PoliticsController.luau
	The governance panel: adjust the tax rate, switch government type, and
	enact/repeal laws. Reads the live snapshot to reflect the current regime and
	which laws are active or unavailable, and sends validated requests to the
	server for every change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Governments = require(ReplicatedStorage.Nexus.Config.Governments)
local Laws = require(ReplicatedStorage.Nexus.Config.Laws)

local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)

local PoliticsController = {
	Name = "PoliticsController",
}

PoliticsController._panel = nil :: Frame?
PoliticsController._taxLabel = nil :: TextLabel?
PoliticsController._govButtons = {} :: { [string]: TextButton }
PoliticsController._lawButtons = {} :: { [string]: TextButton }

local function request(route: string, payload: any)
	task.spawn(function()
		Net.request(route, payload)
	end)
end

local function sectionLabel(text: string, order: number): TextLabel
	return Create("TextLabel", {
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.font.bold,
		Text = text,
		TextColor3 = Theme.color.accent,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
end

function PoliticsController:_adjustTax(delta: number)
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	local rate = math.clamp(nation.politics.taxRate + delta, 0, 1)
	request(NetRoutes.SET_TAX_RATE, { rate = rate })
end

function PoliticsController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local content = Create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	}) :: ScrollingFrame

	-- Tax section.
	sectionLabel("Taxation", 1).Parent = content
	local taxRow = Create("Frame", {
		LayoutOrder = 2,
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(1, 0, 0, 44),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextButton", {
				Text = "−",
				Font = Theme.font.bold,
				TextSize = 22,
				TextColor3 = Theme.color.text,
				BackgroundColor3 = Theme.color.accentDim,
				Size = UDim2.fromOffset(40, 32),
				Position = UDim2.fromOffset(8, 6),
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
				[Create.Event] = { Activated = function()
					self:_adjustTax(-0.05)
				end },
			}),
			Create("TextButton", {
				Text = "+",
				Font = Theme.font.bold,
				TextSize = 22,
				TextColor3 = Theme.color.text,
				BackgroundColor3 = Theme.color.accentDim,
				Size = UDim2.fromOffset(40, 32),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 6),
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
				[Create.Event] = { Activated = function()
					self:_adjustTax(0.05)
				end },
			}),
			Create("TextLabel", {
				Name = "TaxValue",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -100, 1, 0),
				Position = UDim2.fromOffset(50, 0),
				Font = Theme.font.bold,
				Text = "Tax: 15%",
				TextColor3 = Theme.color.text,
				TextSize = 16,
			}),
		},
	}) :: Frame
	taxRow.Parent = content
	self._taxLabel = taxRow:FindFirstChild("TaxValue") :: TextLabel

	-- Government section.
	sectionLabel("Government", 3).Parent = content
	local govOrder = 4
	for id, def in Governments do
		local btn = Create("TextButton", {
			LayoutOrder = govOrder,
			BackgroundColor3 = Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 40),
			Text = "",
			AutoButtonColor = true,
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.new(1, -16, 1, 0),
					Font = Theme.font.medium,
					Text = def.displayName,
					TextColor3 = Theme.color.text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			},
			[Create.Event] = { Activated = function()
				request(NetRoutes.SET_GOVERNMENT, { government = id })
			end },
		}) :: TextButton
		btn.Parent = content
		self._govButtons[id] = btn
		govOrder += 1
	end

	-- Laws section.
	sectionLabel("Laws", 100).Parent = content
	local lawOrder = 101
	for id, def in Laws do
		local btn = Create("TextButton", {
			LayoutOrder = lawOrder,
			BackgroundColor3 = Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 46),
			Text = "",
			AutoButtonColor = true,
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 5),
					Size = UDim2.new(1, -16, 0, 18),
					Font = Theme.font.medium,
					Text = def.displayName,
					TextColor3 = Theme.color.text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 24),
					Size = UDim2.new(1, -16, 0, 16),
					Font = Theme.font.regular,
					Text = def.description,
					TextColor3 = Theme.color.textDim,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
			},
			[Create.Event] = { Activated = function()
				request(NetRoutes.TOGGLE_LAW, { id = id })
			end },
		}) :: TextButton
		btn.Parent = content
		self._lawButtons[id] = btn
		lawOrder += 1
	end

	local panel = Create("Frame", {
		Name = "PoliticsPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.fromOffset(280, 460),
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
				Text = "Government",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			content,
		},
	}) :: Frame
	-- Anchor the panel vertically centred but below the stats panel visually.
	panel.Position = UDim2.new(0, 16, 0.5, 20)
	panel.Parent = gui
	self._panel = panel
end

function PoliticsController:_refresh()
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	if self._taxLabel then
		self._taxLabel.Text = ("Tax: %d%%"):format(math.floor(nation.politics.taxRate * 100 + 0.5))
	end
	for id, btn in self._govButtons do
		local current = nation.politics.government == id
		btn.BackgroundColor3 = current and Theme.color.accentDim or Theme.color.panelLight
	end
	for id, btn in self._lawButtons do
		local active = nation.politics.activeLaws[id] == true
		local def = Laws[id]
		local locked = def.requiresTech ~= nil and not nation.research.unlocked[def.requiresTech]
		local forbidden = table.find(def.forbiddenGovernments, nation.politics.government) ~= nil
		if active then
			btn.BackgroundColor3 = Theme.color.accentDim
		elseif locked or forbidden then
			btn.BackgroundColor3 = Theme.color.bg
		else
			btn.BackgroundColor3 = Theme.color.panelLight
		end
	end
end

function PoliticsController:Start()
	local HudController = require(script.Parent.HudController)
	local StateController = require(script.Parent.StateController)

	self:_build()
	HudController:AddButton("🏛 Politics", function()
		if self._panel then
			self._panel.Visible = not self._panel.Visible
		end
	end)

	StateController.Changed:Connect(function()
		self:_refresh()
	end)
	if StateController:IsReady() then
		self:_refresh()
	end
end

return PoliticsController
