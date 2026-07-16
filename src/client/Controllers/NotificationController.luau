--!strict
--[[
	Controllers/NotificationController.luau
	Renders transient server notifications as stacked toasts in the top-right.
	Each toast is colour-coded by severity, slides in, and dismisses itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Theme = require(script.Parent.Parent.UI.Theme)

local NotificationController = {
	Name = "NotificationController",
}

NotificationController._container = nil :: Frame?

local function buildToast(severity: string, title: string, body: string?): Frame
	local color = Theme.severityColor[severity] or Theme.color.accent

	local toast = Create("Frame", {
		BackgroundColor3 = Theme.color.panel,
		BackgroundTransparency = 0.05,
		Size = UDim2.new(1, 0, 0, body and 58 or 40),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1, Transparency = 0.3 }),
			Create("Frame", {
				BackgroundColor3 = color,
				Size = UDim2.new(0, 4, 1, -12),
				Position = UDim2.fromOffset(8, 6),
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 2) }) },
			}),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 6),
				Size = UDim2.new(1, -28, 0, 18),
				Font = Theme.font.bold,
				Text = title,
				TextColor3 = Theme.color.text,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			body and Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 26),
				Size = UDim2.new(1, -28, 0, 26),
				Font = Theme.font.regular,
				Text = body,
				TextColor3 = Theme.color.textDim,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}) or nil,
		},
	}) :: Frame
	Decor.gradient(toast, Theme.gradient.panel)

	return toast
end

function NotificationController:Show(severity: string, title: string, body: string?)
	local container = self._container
	if not container then
		return
	end
	local ClientPrefs = require(script.Parent.Parent.ClientPrefs)
	if ClientPrefs.get("muteNotifications") then
		return
	end
	pcall(function()
		local sound = require(script.Parent.SoundController)
		sound:PlaySfx(severity == "error" and "error" or (severity == "success" and "success" or "notify"))
	end)
	local toast = buildToast(severity, title, body)
	toast.Position = UDim2.new(1, 20, 0, 0)
	toast.Parent = container

	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()

	task.delay(4, function()
		if not toast.Parent then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.3), {
			Position = UDim2.new(1, 20, 0, 0),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

function NotificationController:Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Create("ScreenGui", {
		Name = "NexusNotifications",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
	})

	self._container = Create("Frame", {
		Name = "Container",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 70),
		Size = UDim2.new(0, 300, 1, -90),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),
		},
	}) :: Frame
	self._container.Parent = gui
	gui.Parent = playerGui
end

function NotificationController:Start()
	Net.onEvent(NetRoutes.NOTIFY, function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		self:Show(payload.severity or "info", tostring(payload.title or ""), payload.body)
	end)
end

return NotificationController
