--!strict
--[[
	Controllers/MilitaryController.luau
	The (optional) armed-forces panel: recruit and disband army, navy and air
	units, see their cost, upkeep and your total strength. Hidden entirely when
	ServerSettings.militaryEnabled is false. Higher tiers show as locked until the
	matching military technology is researched.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local MilitaryUnits = require(ReplicatedStorage.Nexus.Config.MilitaryUnits)
local Resources = require(ReplicatedStorage.Nexus.Config.Resources)
local ServerSettings = require(ReplicatedStorage.Nexus.Config.ServerSettings)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Format = require(script.Parent.Parent.UI.Format)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local ORDER = { "army", "navy", "air" }

local MilitaryController = {
	Name = "MilitaryController",
}

MilitaryController._panel = nil :: Frame?
MilitaryController._rows = {} :: { [string]: Frame }
MilitaryController._strengthLabel = nil :: TextLabel?

local function request(route: string, branch: string, count: number)
	task.spawn(function()
		Net.request(route, { branch = branch, count = count })
	end)
end

local function costText(branch: string): string
	local parts = {}
	for id, amount in MilitaryUnits[branch].cost do
		table.insert(parts, Resources[id].symbol .. Format.abbrev(amount))
	end
	return table.concat(parts, " ")
end

function MilitaryController:_row(branch: string, order: number): Frame
	local def = MilitaryUnits[branch]
	local function miniButton(text: string, x: number, color: Color3, onClick: () -> ()): TextButton
		return Create("TextButton", {
			BackgroundColor3 = color,
			Position = UDim2.fromOffset(x, 44),
			Size = UDim2.fromOffset(70, 22),
			Font = Theme.font.bold,
			Text = text,
			TextColor3 = Theme.color.text,
			TextSize = 11,
			[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
			[Create.Event] = { Activated = onClick },
		}) :: TextButton
	end

	local row = Create("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(1, 0, 0, 74),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextLabel", {
				Name = "Title",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 6),
				Size = UDim2.new(1, -20, 0, 18),
				Font = Theme.font.bold,
				Text = def.displayName,
				TextColor3 = Theme.color.text,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextLabel", {
				Name = "Sub",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 24),
				Size = UDim2.new(1, -20, 0, 16),
				Font = Theme.font.regular,
				Text = ("Cost %s · upkeep $%d · str %d"):format(costText(branch), def.upkeep, def.strength),
				TextColor3 = Theme.color.textDim,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextLabel", {
				Name = "Count",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 6),
				Size = UDim2.fromOffset(60, 18),
				Font = Theme.font.black,
				Text = "0",
				TextColor3 = Theme.color.accent,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			miniButton("＋1", 10, Theme.color.accentDim, function()
				request(NetRoutes.RECRUIT_UNITS, branch, 1)
			end),
			miniButton("＋5", 86, Theme.color.accentDim, function()
				request(NetRoutes.RECRUIT_UNITS, branch, 5)
			end),
			miniButton("－1", 162, Color3.fromRGB(120, 50, 50), function()
				request(NetRoutes.DISBAND_UNITS, branch, 1)
			end),
		},
	}) :: Frame
	return row
end

function MilitaryController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local content = Create("Frame", {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 0, 240),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	})
	for i, branch in ORDER do
		local row = self:_row(branch, i)
		row.Parent = content
		self._rows[branch] = row
	end

	self._strengthLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 0, 22),
		Font = Theme.font.bold,
		Text = "Total strength: 0",
		TextColor3 = Theme.color.accent2,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel

	local panel = Create("Frame", {
		Name = "MilitaryPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 336),
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
				Text = "⚔ Armed Forces",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			self._strengthLabel,
			content,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function MilitaryController:_refresh()
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	local strength = 0
	for branch, row in self._rows do
		local def = MilitaryUnits[branch]
		local count = nation.military[branch] or 0
		strength += count * def.strength
		local countLabel = row:FindFirstChild("Count") :: TextLabel
		countLabel.Text = tostring(count)
		local sub = row:FindFirstChild("Sub") :: TextLabel
		if def.requiresTech and not nation.research.unlocked[def.requiresTech] then
			sub.Text = "🔒 Requires " .. def.requiresTech
			sub.TextColor3 = Theme.color.bad
		else
			sub.Text = ("Cost %s · upkeep $%d · str %d"):format(costText(branch), def.upkeep, def.strength)
			sub.TextColor3 = Theme.color.textDim
		end
	end
	if self._strengthLabel then
		self._strengthLabel.Text = "Total strength: " .. strength
	end
end

function MilitaryController:Start()
	if not ServerSettings.militaryEnabled then
		return -- military disabled on this server: no panel, no button
	end
	local HudController = require(script.Parent.HudController)
	local StateController = require(script.Parent.StateController)

	self:_build()
	HudController:AddButton("⚔ Military", function()
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

return MilitaryController
