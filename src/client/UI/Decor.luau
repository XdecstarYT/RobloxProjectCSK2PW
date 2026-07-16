--!strict
--[[
	UI/Decor.luau
	Small cosmetic helpers so every panel, chip and button gets the same finish
	without repeating boilerplate. Purely presentational — safe to apply to any
	GuiObject after it is built.
]]

local Theme = require(script.Parent.Theme)

local Decor = {}

--- Apply a vertical gradient to a GuiObject's background. `pair` is a
--- `{ topColor, bottomColor }` from Theme.gradient.
function Decor.gradient(instance: GuiObject, pair: { Color3 }, rotation: number?)
	local existing = instance:FindFirstChildOfClass("UIGradient")
	local grad = existing or Instance.new("UIGradient")
	grad.Color = ColorSequence.new(pair[1], pair[2])
	grad.Rotation = rotation or 90
	grad.Parent = instance
	return grad
end

--- Standard panel finish: rounded corners, gradient body and a hairline stroke.
--- Idempotent — only adds what is missing.
function Decor.panel(frame: GuiObject)
	if not frame:FindFirstChildOfClass("UICorner") then
		local c = Instance.new("UICorner")
		c.CornerRadius = Theme.corner
		c.Parent = frame
	end
	if not frame:FindFirstChildOfClass("UIStroke") then
		local s = Instance.new("UIStroke")
		s.Color = Theme.color.stroke
		s.Thickness = 1
		s.Transparency = 0.15
		s.Parent = frame
	end
	Decor.gradient(frame, Theme.gradient.panel)
	return frame
end

--- A faux drop shadow: a soft, offset rounded frame placed behind `frame` in the
--- same parent. Cheap and asset-free. Returns the shadow frame.
function Decor.shadow(frame: GuiObject): Frame
	local shadow = Instance.new("Frame")
	shadow.Name = frame.Name .. "_Shadow"
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.AnchorPoint = frame.AnchorPoint
	shadow.Position = frame.Position + UDim2.fromOffset(0, 6)
	shadow.Size = frame.Size + UDim2.fromOffset(10, 12)
	shadow.ZIndex = frame.ZIndex - 1
	local c = Instance.new("UICorner")
	c.CornerRadius = Theme.corner
	c.Parent = shadow
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	grad.Parent = shadow
	shadow.Parent = frame.Parent
	return shadow
end

return Decor
