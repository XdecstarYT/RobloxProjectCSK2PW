--!strict
--[[
	UI/Graph.luau
	A tiny, asset-free bar graph. Given a container size it returns the frame plus
	an `update(values)` function that redraws scaled bars. Used by the economy
	panel to visualise replicated GDP history. Bars are recreated on update, which
	is cheap at the economy tick's cadence.
]]

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local Graph = {}

--- Returns (frame, update). `update(values, color?)` redraws the graph.
function Graph.new(size: UDim2): (Frame, (values: { number }, color: Color3?) -> ())
	local plot = Create("Frame", {
		Name = "Plot",
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
	}) :: Frame

	local frame = Create("Frame", {
		Name = "Graph",
		Size = size,
		BackgroundColor3 = Theme.color.bg,
		BackgroundTransparency = 0.25,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("UIStroke", { Color = Theme.color.stroke, Thickness = 1, Transparency = 0.4 }),
			plot,
		},
	}) :: Frame

	local function update(values: { number }, color: Color3?)
		for _, child in plot:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local n = #values
		if n == 0 then
			return
		end
		local maxV = 0
		for _, v in values do
			maxV = math.max(maxV, v)
		end
		if maxV <= 0 then
			maxV = 1
		end
		local barColor = color or Theme.color.accent
		local slot = 1 / n
		for i, v in values do
			local h = math.clamp(v / maxV, 0.02, 1)
			local bar = Create("Frame", {
				Name = "Bar",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new((i - 0.5) * slot, 0, 1, 0),
				Size = UDim2.new(slot, -1, h, 0),
				BackgroundColor3 = barColor,
				BorderSizePixel = 0,
				[Create.Children] = {
					Create("UICorner", { CornerRadius = UDim.new(0, 2) }),
					-- Taller bars glow a little warmer.
					Create("UIGradient", {
						Rotation = 90,
						Color = ColorSequence.new(Theme.color.accent2, barColor),
						Transparency = NumberSequence.new(0.05, 0.35),
					}),
				},
			})
			bar.Parent = plot
		end
	end

	return frame, update
end

return Graph
