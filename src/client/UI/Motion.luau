--!strict
--[[
	UI/Motion.luau
	Tiny animation helpers so panels don't just snap on/off. Uses a UIScale child
	for a subtle pop and a background fade, keeping call sites to one line.
]]

local TweenService = game:GetService("TweenService")

local Motion = {}

local SHOW = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function scaleOf(frame: GuiObject): UIScale
	local s = frame:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = frame
	end
	return s
end

function Motion.show(frame: GuiObject)
	local s = scaleOf(frame)
	s.Scale = 0.92
	frame.Visible = true
	TweenService:Create(s, SHOW, { Scale = 1 }):Play()
end

function Motion.hide(frame: GuiObject)
	local s = scaleOf(frame)
	local tween = TweenService:Create(s, HIDE, { Scale = 0.94 })
	tween:Play()
	tween.Completed:Once(function()
		frame.Visible = false
	end)
end

function Motion.toggle(frame: GuiObject)
	if frame.Visible then
		Motion.hide(frame)
	else
		Motion.show(frame)
	end
end

return Motion
