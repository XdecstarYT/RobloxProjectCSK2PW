--!strict
--[[
	Controllers/ResearchController.luau
	The technology panel. Lists every tech grouped by branch with a live status —
	researched, in-progress (with a progress bar), available, or locked behind
	prerequisites — and lets the player commit research to an available tech.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Technologies = require(ReplicatedStorage.Nexus.Config.Technologies)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Format = require(script.Parent.Parent.UI.Format)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local ResearchController = {
	Name = "ResearchController",
}

ResearchController._panel = nil :: Frame?
ResearchController._rows = {} :: { [string]: Frame }

local function prereqsMet(nation: any, def: any): boolean
	for _, req in def.requires do
		if not nation.research.unlocked[req] then
			return false
		end
	end
	return true
end

function ResearchController:_build()
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

	-- Stable order: branch then cost.
	local order = {}
	for id in Technologies do
		table.insert(order, id)
	end
	table.sort(order, function(a, b)
		local da, db = Technologies[a], Technologies[b]
		if da.branch ~= db.branch then
			return da.branch < db.branch
		end
		return da.cost < db.cost
	end)

	for i, id in order do
		local def = Technologies[id]
		local row = Create("TextButton", {
			LayoutOrder = i,
			BackgroundColor3 = Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 58),
			Text = "",
			AutoButtonColor = true,
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					Name = "Name",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 6),
					Size = UDim2.new(1, -80, 0, 18),
					Font = Theme.font.bold,
					Text = def.displayName,
					TextColor3 = Theme.color.text,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					Name = "Desc",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 24),
					Size = UDim2.new(1, -80, 0, 16),
					Font = Theme.font.regular,
					Text = def.description,
					TextColor3 = Theme.color.textDim,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
				Create("TextLabel", {
					Name = "Status",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 6),
					Size = UDim2.fromOffset(70, 18),
					Font = Theme.font.bold,
					Text = "✦" .. Format.abbrev(def.cost),
					TextColor3 = Theme.color.accent,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
				-- Progress bar (shown only for the active tech).
				Create("Frame", {
					Name = "Bar",
					BackgroundColor3 = Theme.color.bg,
					Position = UDim2.fromOffset(10, 46),
					Size = UDim2.new(1, -20, 0, 5),
					Visible = false,
					[Create.Children] = {
						Create("UICorner", { CornerRadius = UDim.new(0, 3) }),
						Create("Frame", {
							Name = "Fill",
							BackgroundColor3 = Theme.color.accent,
							Size = UDim2.new(0, 0, 1, 0),
							[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 3) }) },
						}),
					},
				}),
			},
			[Create.Event] = { Activated = function()
				self:_onClick(id)
			end },
		}) :: Frame
		row.Parent = content
		self._rows[id] = row
	end

	local panel = Create("Frame", {
		Name = "ResearchPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 20),
		Size = UDim2.fromOffset(300, 460),
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
				Text = "Technology",
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

function ResearchController:_onClick(id: string)
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	local def = Technologies[id]
	if nation.research.unlocked[id] then
		return
	end
	if not prereqsMet(nation, def) then
		local Notif = require(script.Parent.NotificationController)
		Notif:Show("warning", "Locked", "Complete prerequisite research first.")
		return
	end
	task.spawn(function()
		Net.request(NetRoutes.START_RESEARCH, { id = id })
	end)
end

function ResearchController:_refresh()
	local StateController = require(script.Parent.StateController)
	local nation = StateController:GetNation()
	if not nation then
		return
	end
	for id, row in self._rows do
		local def = Technologies[id]
		local status = row:FindFirstChild("Status") :: TextLabel
		local bar = row:FindFirstChild("Bar") :: Frame
		local fill = bar:FindFirstChild("Fill") :: Frame

		if nation.research.unlocked[id] then
			row.BackgroundColor3 = Color3.fromRGB(34, 54, 40)
			status.Text = "✓ Done"
			status.TextColor3 = Theme.color.good
			bar.Visible = false
		elseif nation.research.current == id then
			row.BackgroundColor3 = Theme.color.accentDim
			local pct = math.clamp(nation.research.progress / def.cost, 0, 1)
			status.Text = ("%d%%"):format(math.floor(pct * 100 + 0.5))
			status.TextColor3 = Theme.color.text
			bar.Visible = true
			fill.Size = UDim2.new(pct, 0, 1, 0)
		elseif prereqsMet(nation, def) then
			row.BackgroundColor3 = Theme.color.panelLight
			status.Text = "✦" .. Format.abbrev(def.cost)
			status.TextColor3 = Theme.color.accent
			bar.Visible = false
		else
			row.BackgroundColor3 = Theme.color.bg
			status.Text = "🔒"
			status.TextColor3 = Theme.color.textDim
			bar.Visible = false
		end
	end
end

function ResearchController:Start()
	local HudController = require(script.Parent.HudController)
	local StateController = require(script.Parent.StateController)

	self:_build()
	HudController:AddButton("🔬 Research", function()
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

return ResearchController
