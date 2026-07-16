--!strict
--[[
	Controllers/SettingsController.luau
	The options menu. Drives ClientPrefs, which SoundController, AmbianceController
	and NotificationController react to: music/SFX volume, mute notifications,
	cinematic effects on/off, and a button to replay the tutorial.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local ClientPrefs = require(script.Parent.Parent.ClientPrefs)

local SettingsController = {
	Name = "SettingsController",
}

SettingsController._panel = nil :: Frame?

local function volumeRow(label: string, key: string, order: number): Frame
	local valueLabel: TextLabel
	local function refresh()
		valueLabel.Text = ("%d%%"):format(math.floor(ClientPrefs.get(key) * 100 + 0.5))
	end
	local function step(delta: number)
		ClientPrefs.set(key, math.clamp(ClientPrefs.get(key) + delta, 0, 1))
		refresh()
	end
	local function mini(text: string, x: number, d: number): TextButton
		return Create("TextButton", {
			BackgroundColor3 = Theme.color.accentDim,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, x, 0.5, 0),
			Size = UDim2.fromOffset(30, 28),
			Font = Theme.font.bold,
			Text = text,
			TextColor3 = Theme.color.text,
			TextSize = 18,
			[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
			[Create.Event] = { Activated = function()
				step(d)
			end },
		}) :: TextButton
	end

	valueLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -46, 0.5, 0),
		Size = UDim2.fromOffset(50, 28),
		Font = Theme.font.bold,
		Text = "0%",
		TextColor3 = Theme.color.text,
		TextSize = 14,
	}) :: TextLabel

	local row = Create("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(1, 0, 0, 42),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				Font = Theme.font.medium,
				Text = label,
				TextColor3 = Theme.color.text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			mini("−", -84, -0.1),
			valueLabel,
			mini("+", -10, 0.1),
		},
	}) :: Frame
	refresh()
	return row
end

local function toggleRow(label: string, key: string, order: number): Frame
	local btn: TextButton
	local function refresh()
		local on = ClientPrefs.get(key) == true
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Theme.color.good or Theme.color.panelLight
		btn.TextColor3 = on and Theme.color.bg or Theme.color.textDim
	end
	btn = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(64, 28),
		Font = Theme.font.bold,
		Text = "OFF",
		TextSize = 13,
		BackgroundColor3 = Theme.color.panelLight,
		TextColor3 = Theme.color.textDim,
		[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
		[Create.Event] = { Activated = function()
			ClientPrefs.set(key, not (ClientPrefs.get(key) == true))
			refresh()
		end },
	}) :: TextButton

	local row = Create("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(1, 0, 0, 42),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(0.7, 0, 1, 0),
				Font = Theme.font.medium,
				Text = label,
				TextColor3 = Theme.color.text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			btn,
		},
	}) :: Frame
	refresh()
	return row
end

function SettingsController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local content = Create("Frame", {
		Position = UDim2.fromOffset(12, 44),
		Size = UDim2.new(1, -24, 0, 240),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	})
	volumeRow("Music volume", "musicVolume", 1).Parent = content
	volumeRow("Sound effects", "sfxVolume", 2).Parent = content
	toggleRow("Mute notifications", "muteNotifications", 3).Parent = content
	toggleRow("Cinematic effects", "effectsEnabled", 4).Parent = content

	Create("TextButton", {
		LayoutOrder = 5,
		BackgroundColor3 = Theme.color.accentDim,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.font.bold,
		Text = "↺ Replay tutorial",
		TextColor3 = Theme.color.text,
		TextSize = 14,
		[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 8) }) },
		[Create.Event] = { Activated = function()
			local Tutorial = require(script.Parent.TutorialController)
			Tutorial:Restart()
		end },
	}).Parent = content

	local panel = Create("Frame", {
		Name = "SettingsPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 336),
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
				Text = "⚙ Settings",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			content,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function SettingsController:Start()
	local HudController = require(script.Parent.HudController)
	self:_build()
	HudController:AddButton("⚙ Settings", function()
		if self._panel then
			Motion.toggle(self._panel)
		end
	end)
end

return SettingsController
