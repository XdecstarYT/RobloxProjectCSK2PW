--!strict
--[[
	Controllers/HudController.luau
	The persistent HUD: a top resource bar, a compact national-stats panel, and a
	bottom action bar that other controllers hang their panel-toggle buttons on.

	HudController owns the root ScreenGui and exposes it (GetGui) plus AddButton so
	the Build/Politics/Research controllers can attach to a consistent chrome
	without HudController needing to know they exist.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Resources = require(ReplicatedStorage.Nexus.Config.Resources)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Format = require(script.Parent.Parent.UI.Format)
local Theme = require(script.Parent.Parent.UI.Theme)

local HudController = {
	Name = "HudController",
}

HudController._gui = nil :: ScreenGui?
HudController._chips = {} :: { [string]: TextLabel }
HudController._stats = {} :: { [string]: TextLabel }
HudController._nameLabel = nil :: TextLabel?
HudController._buttonBar = nil :: ScrollingFrame?

-- ---- Builders -------------------------------------------------------------

local function resourceChip(resourceId: string): (Frame, TextLabel)
	local meta = Resources[resourceId]
	local color = Color3.new(meta.color[1], meta.color[2], meta.color[3])

	local valueLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(28, 0),
		Font = Theme.font.bold,
		Text = "0",
		TextColor3 = Theme.color.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel

	local chip = Create("Frame", {
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.fromOffset(108, 34),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(24, 34),
				Position = UDim2.fromOffset(6, 0),
				Font = Theme.font.bold,
				Text = meta.symbol,
				TextColor3 = color,
				TextSize = 16,
			}),
			valueLabel,
		},
	}) :: Frame
	Decor.gradient(chip, Theme.gradient.chip)

	return chip, valueLabel
end

local function statRow(label: string): (Frame, TextLabel)
	local valueLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = Theme.font.bold,
		Text = "-",
		TextColor3 = Theme.color.text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}) :: TextLabel

	local row = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		[Create.Children] = {
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0.5, 0, 1, 0),
				Font = Theme.font.regular,
				Text = label,
				TextColor3 = Theme.color.textDim,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			valueLabel,
		},
	}) :: Frame

	return row, valueLabel
end

-- ---- Public API -----------------------------------------------------------

function HudController:GetGui(): ScreenGui
	return assert(self._gui, "HUD gui not built yet")
end

--- Add a toggle button to the bottom action bar. Returns the button.
function HudController:AddButton(text: string, onClick: () -> ()): TextButton
	local bar = assert(self._buttonBar, "button bar not built")
	local button = Create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Theme.color.panelLight,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		Font = Theme.font.bold,
		Text = text,
		TextColor3 = Theme.color.text,
		TextSize = 15,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
			Create("UISizeConstraint", { MinSize = Vector2.new(96, 44) }),
		},
		[Create.Event] = {
			Activated = function()
				pcall(function()
					require(script.Parent.SoundController):PlayClick()
				end)
				onClick()
			end,
		},
	}) :: TextButton
	Decor.gradient(button, Theme.gradient.chip)
	button.Parent = bar
	return button
end

-- ---- Lifecycle ------------------------------------------------------------

function HudController:Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Create("ScreenGui", {
		Name = "NexusHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
	}) :: ScreenGui

	-- Top resource bar.
	local chipRow = Create("Frame", {
		BackgroundColor3 = Theme.color.bg,
		BackgroundTransparency = 0.15,
		Size = UDim2.new(1, 0, 0, 50),
		[Create.Children] = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 96), PaddingRight = UDim.new(0, 8) }),
		},
	})
	Decor.gradient(chipRow, Theme.gradient.topbar)
	Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1, Transparency = 0.4 }).Parent = chipRow
	chipRow.Parent = gui

	-- Wordmark in the top-left corner.
	Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(90, 50),
		Font = Theme.font.black,
		Text = "◆ NEXUS",
		TextColor3 = Theme.color.accent,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	}).Parent = gui

	for _, resourceId in Constants.RESOURCE_ORDER do
		local chip, label = resourceChip(resourceId)
		chip.Parent = chipRow
		self._chips[resourceId] = label
	end

	-- Left stats panel.
	local statsPanel = Create("Frame", {
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = 0.1,
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.fromOffset(224, 252),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1 }),
			Create("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}),
			Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	})
	Decor.gradient(statsPanel, Theme.gradient.panel)

	self._nameLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.font.bold,
		Text = "My Nation",
		TextColor3 = Theme.color.accent,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
	self._nameLabel.Parent = statsPanel

	local statOrder = {
		{ key = "population", label = "Population" },
		{ key = "happiness", label = "Happiness" },
		{ key = "approval", label = "Approval" },
		{ key = "stability", label = "Stability" },
		{ key = "gdp", label = "GDP / tick" },
		{ key = "net", label = "Budget / tick" },
		{ key = "debt", label = "Debt" },
		{ key = "power", label = "Power" },
	}
	for _, entry in statOrder do
		local row, value = statRow(entry.label)
		row.Parent = statsPanel
		self._stats[entry.key] = value
	end
	statsPanel.Parent = gui

	-- Bottom action bar — a horizontal scroller so any number of buttons fits,
	-- even on narrow mobile screens.
	self._buttonBar = Create("ScrollingFrame", {
		Name = "ActionBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -32, 0, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		[Create.Children] = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	}) :: ScrollingFrame
	self._buttonBar.Parent = gui

	gui.Parent = playerGui
	self._gui = gui
end

function HudController:_refresh(snapshot: any)
	local nation = snapshot.nation
	local stats = snapshot.stats or {}
	local res = nation.resources

	for resourceId, label in self._chips do
		local value = res[resourceId] or 0
		if resourceId == "energy" then
			label.Text = Format.signed(value)
			label.TextColor3 = value >= 0 and Theme.color.good or Theme.color.bad
		else
			label.Text = Format.abbrev(value)
		end
	end

	if self._nameLabel then
		self._nameLabel.Text = nation.name
	end

	local set = function(key: string, text: string, color: Color3?)
		local label = self._stats[key]
		if label then
			label.Text = text
			if color then
				label.TextColor3 = color
			end
		end
	end

	set("population", Format.abbrev(nation.population.total))
	set(
		"happiness",
		Format.round(nation.population.happiness) .. "%",
		nation.population.happiness >= 50 and Theme.color.good or Theme.color.warn
	)
	set("approval", Format.round(nation.politics.approval) .. "%")
	set("stability", Format.round(nation.politics.stability) .. "%",
		nation.politics.stability >= 40 and Theme.color.text or Theme.color.bad)
	set("gdp", Format.abbrev(stats.gdp or nation.economy.gdp))
	set(
		"net",
		Format.signed(stats.net or 0),
		(stats.net or 0) >= 0 and Theme.color.good or Theme.color.bad
	)
	set("debt", Format.abbrev(nation.economy.debt), nation.economy.debt > 0 and Theme.color.warn or Theme.color.text)
	set(
		"power",
		Format.signed(stats.powerNet or res.energy or 0),
		(stats.powerNet or 0) >= 0 and Theme.color.good or Theme.color.bad
	)
end

function HudController:Start()
	local StateController = require(script.Parent.StateController)
	StateController.Changed:Connect(function(snapshot)
		self:_refresh(snapshot)
	end)
	if StateController:IsReady() then
		self:_refresh(StateController:GetSnapshot())
	end
end

return HudController
