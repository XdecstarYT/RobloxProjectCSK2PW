--!strict
--[[
	Controllers/EconomyController.luau
	A statistics dashboard: a live GDP graph (from the replicated gdpHistory), a
	compact financial breakdown, and a contextual advisor that reads the current
	snapshot and surfaces the most useful next moves. Everything is derived on the
	client from data it already has — no extra network traffic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Format = require(script.Parent.Parent.UI.Format)
local Graph = require(script.Parent.Parent.UI.Graph)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local EconomyController = {
	Name = "EconomyController",
}

EconomyController._panel = nil :: Frame?
EconomyController._update = nil :: ((values: { number }, color: Color3?) -> ())?
EconomyController._caption = nil :: TextLabel?
EconomyController._cells = {} :: { [string]: TextLabel }
EconomyController._advisor = nil :: ScrollingFrame?

-- ---- Advisor rules ---------------------------------------------------------

local function advise(nation: any, stats: any): { { text: string, color: Color3 } }
	local tips = {}
	local function add(color: Color3, text: string)
		table.insert(tips, { text = text, color = color })
	end

	if (stats.powerNet or 0) < 0 then
		add(Theme.color.bad, "⚡ Power deficit — build a Power Plant; buildings are throttled.")
	end
	if (nation.resources.food or 0) < 120 then
		add(Theme.color.warn, "❖ Food is low — build Farms before your people go hungry.")
	end
	if nation.politics.taxRate > 0.4 then
		add(Theme.color.warn, "💸 Taxes are very high — happiness and approval will slide.")
	end
	if nation.population.happiness < 45 then
		add(Theme.color.warn, "🙁 Citizens are unhappy — add Parks/Services or cut taxes.")
	end
	if (stats.unemployment or 0) > 0.2 then
		add(Theme.color.warn, "🧑‍🏭 High unemployment — build Markets or Factories for jobs.")
	end
	if nation.economy.debt > 0 then
		add(Theme.color.warn, ("🏦 In debt (%s) — interest accrues each tick."):format(Format.abbrev(nation.economy.debt)))
	end
	if nation.politics.stability < 40 then
		add(Theme.color.bad, "⚖ Government unstable — raise approval and cut unrest.")
	end
	if not nation.research.current then
		add(Theme.color.accent, "🔬 No active research — pick a technology to advance.")
	end
	if #nation.territory.regions <= 1 and (nation.resources.influence or 0) >= 40 then
		add(Theme.color.accent, "🗺 Spend influence in Territory to claim a region for income.")
	end

	if #tips == 0 then
		add(Theme.color.good, "✅ Your nation is thriving — expand, ally, or climb the ranks.")
	end
	return tips
end

-- ---- Panel -----------------------------------------------------------------

function EconomyController:_cell(key: string, label: string): Frame
	local value = Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		Font = Theme.font.bold,
		Text = "-",
		TextColor3 = Theme.color.text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}) :: TextLabel
	self._cells[key] = value

	return Create("Frame", {
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(0.5, -4, 0, 26),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				Font = Theme.font.regular,
				Text = label,
				TextColor3 = Theme.color.textDim,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			value,
		},
	}) :: Frame
end

function EconomyController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local graph, update = Graph.new(UDim2.new(1, -24, 0, 130))
	graph.Position = UDim2.fromOffset(12, 60)
	self._update = update

	local caption = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 18),
		Font = Theme.font.medium,
		Text = "GDP over time",
		TextColor3 = Theme.color.textDim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel
	self._caption = caption

	local grid = Create("Frame", {
		Position = UDim2.fromOffset(12, 200),
		Size = UDim2.new(1, -24, 0, 108),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIGridLayout", {
				CellSize = UDim2.new(0.5, -4, 0, 26),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	for _, spec in
		{
			{ "income", "Income" },
			{ "expense", "Expense" },
			{ "net", "Net / tick" },
			{ "treasury", "Treasury" },
			{ "debt", "Debt" },
			{ "inflation", "Inflation" },
			{ "unemployment", "Jobless" },
			{ "power", "Power" },
		}
	do
		self:_cell(spec[1], spec[2]).Parent = grid
	end

	local advisor = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 340),
		Size = UDim2.new(1, -24, 1, -350),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	}) :: ScrollingFrame
	self._advisor = advisor

	local panel = Create("Frame", {
		Name = "EconomyPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 500),
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
				Text = "📊 Economy & Advisor",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 318),
				Size = UDim2.new(1, -28, 0, 18),
				Font = Theme.font.bold,
				Text = "Advisor",
				TextColor3 = Theme.color.accent2,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			caption,
			graph,
			grid,
			advisor,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function EconomyController:_refresh(snapshot: any)
	if not self._panel or not self._panel.Visible then
		return -- only recompute while the panel is open
	end
	if not snapshot or not snapshot.nation then
		return
	end
	local nation = snapshot.nation
	local stats = snapshot.stats or {}

	local history = nation.economy.gdpHistory or {}
	if self._update then
		self._update(history, Theme.color.accent)
	end
	if self._caption then
		local peak = 0
		for _, v in history do
			peak = math.max(peak, v)
		end
		self._caption.Text = ("GDP — now %s · peak %s"):format(
			Format.abbrev(nation.economy.gdp),
			Format.abbrev(peak)
		)
	end

	local set = function(key: string, text: string, color: Color3?)
		local label = self._cells[key]
		if label then
			label.Text = text
			label.TextColor3 = color or Theme.color.text
		end
	end
	local net = stats.net or (nation.economy.lastTickIncome - nation.economy.lastTickExpense)
	set("income", Format.abbrev(stats.income or nation.economy.lastTickIncome), Theme.color.good)
	set("expense", Format.abbrev(stats.expense or nation.economy.lastTickExpense), Theme.color.warn)
	set("net", Format.signed(net), net >= 0 and Theme.color.good or Theme.color.bad)
	set("treasury", Format.abbrev(nation.resources.money))
	set("debt", Format.abbrev(nation.economy.debt), nation.economy.debt > 0 and Theme.color.warn or Theme.color.text)
	set("inflation", ("%.1f%%"):format(nation.economy.inflation))
	set("unemployment", Format.percent(stats.unemployment or 0))
	set("power", Format.signed(stats.powerNet or nation.resources.energy or 0),
		(stats.powerNet or 0) >= 0 and Theme.color.good or Theme.color.bad)

	local advisor = self._advisor
	if advisor then
		for _, child in advisor:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, tip in advise(nation, stats) do
			Create("Frame", {
				LayoutOrder = i,
				BackgroundColor3 = Theme.color.panelLight,
				Size = UDim2.new(1, 0, 0, 34),
				AutomaticSize = Enum.AutomaticSize.Y,
				[Create.Children] = {
					Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
					Create("Frame", {
						BackgroundColor3 = tip.color,
						Size = UDim2.new(0, 3, 1, -8),
						Position = UDim2.fromOffset(6, 4),
						[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 2) }) },
					}),
					Create("TextLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(16, 4),
						Size = UDim2.new(1, -22, 1, -8),
						Font = Theme.font.medium,
						Text = tip.text,
						TextColor3 = Theme.color.text,
						TextSize = 12,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						AutomaticSize = Enum.AutomaticSize.Y,
					}),
				},
			}).Parent = advisor
		end
	end
end

function EconomyController:Start()
	local HudController = require(script.Parent.HudController)
	local StateController = require(script.Parent.StateController)

	self:_build()
	HudController:AddButton("📊 Economy", function()
		if self._panel then
			Motion.toggle(self._panel)
			self:_refresh(StateController:GetSnapshot() or { nation = StateController:GetNation() })
		end
	end)

	StateController.Changed:Connect(function(snapshot)
		self:_refresh(snapshot)
	end)
end

return EconomyController
