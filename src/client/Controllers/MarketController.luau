--!strict
--[[
	Controllers/MarketController.luau
	The global commodity market screen: live prices with trend arrows and
	buy/sell controls at a chosen quantity. Prices arrive via MARKET_SYNC; every
	trade is a validated server request.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Market = require(ReplicatedStorage.Nexus.Config.Market)
local Resources = require(ReplicatedStorage.Nexus.Config.Resources)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local QUANTITIES = { 10, 50, 200, 1000 }

local MarketController = {
	Name = "MarketController",
}

MarketController._panel = nil :: Frame?
MarketController._rows = {} :: { [string]: any }
MarketController._qtyIndex = 2
MarketController._qtyButton = nil :: TextButton?

local function request(route: string, resource: string, amount: number)
	task.spawn(function()
		Net.request(route, { resource = resource, amount = amount })
	end)
end

function MarketController:_qty(): number
	return QUANTITIES[self._qtyIndex]
end

function MarketController:_row(res: string, order: number): Frame
	local meta = Resources[res]
	local color = Color3.new(meta.color[1], meta.color[2], meta.color[3])

	local price = Create("TextLabel", {
		Name = "Price",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(146, 0),
		Size = UDim2.fromOffset(58, 48),
		Font = Theme.font.bold,
		Text = "$-",
		TextColor3 = Theme.color.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel

	local function tradeButton(text: string, c: Color3, x: number, route: string): TextButton
		return Create("TextButton", {
			BackgroundColor3 = c,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, x, 0.5, 0),
			Size = UDim2.fromOffset(54, 32),
			Font = Theme.font.bold,
			Text = text,
			TextColor3 = Theme.color.bg,
			TextSize = 13,
			[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
			[Create.Event] = { Activated = function()
				request(route, res, self:_qty())
			end },
		}) :: TextButton
	end

	local row = Create("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(1, 0, 0, 48),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.fromOffset(24, 48),
				Font = Theme.font.bold,
				Text = meta.symbol,
				TextColor3 = color,
				TextSize = 18,
			}),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(38, 0),
				Size = UDim2.fromOffset(110, 48),
				Font = Theme.font.medium,
				Text = meta.displayName,
				TextColor3 = Theme.color.text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			price,
			Create("TextLabel", {
				Name = "Trend",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(206, 0),
				Size = UDim2.fromOffset(26, 48),
				Font = Theme.font.bold,
				Text = "–",
				TextColor3 = Theme.color.textDim,
				TextSize = 16,
			}),
			tradeButton("Buy", Theme.color.good, -64, NetRoutes.MARKET_BUY),
			tradeButton("Sell", Theme.color.warn, -6, NetRoutes.MARKET_SELL),
		},
	}) :: Frame

	self._rows[res] = { row = row, price = price, trend = row:FindFirstChild("Trend") }
	return row
end

function MarketController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local list = Create("Frame", {
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 0, 216),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	})
	for i, res in Market.order do
		self:_row(res, i).Parent = list
	end

	self._qtyButton = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 40),
		Size = UDim2.fromOffset(130, 30),
		BackgroundColor3 = Theme.color.accentDim,
		Font = Theme.font.bold,
		Text = "Qty: 50",
		TextColor3 = Theme.color.text,
		TextSize = 14,
		[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 8) }) },
		[Create.Event] = { Activated = function()
			self._qtyIndex = (self._qtyIndex % #QUANTITIES) + 1
			if self._qtyButton then
				self._qtyButton.Text = "Qty: " .. self:_qty()
			end
		end },
	}) :: TextButton

	local panel = Create("Frame", {
		Name = "MarketPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 320),
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
				Text = "💱 Global Market",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 44),
				Size = UDim2.fromOffset(200, 22),
				Font = Theme.font.regular,
				Text = "Prices move with supply & demand",
				TextColor3 = Theme.color.textDim,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			self._qtyButton,
			list,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
end

function MarketController:_refresh(rows: { any })
	for _, entry in rows do
		local ref = self._rows[entry.id]
		if ref then
			ref.price.Text = ("$%.1f"):format(entry.price)
			local trend = ref.trend :: TextLabel
			if entry.price > entry.prev + 0.001 then
				trend.Text = "▲"
				trend.TextColor3 = Theme.color.good
			elseif entry.price < entry.prev - 0.001 then
				trend.Text = "▼"
				trend.TextColor3 = Theme.color.bad
			else
				trend.Text = "–"
				trend.TextColor3 = Theme.color.textDim
			end
			-- Tint the price by how it compares to its baseline.
			ref.price.TextColor3 = entry.price >= entry.base and Theme.color.text or Theme.color.good
		end
	end
end

function MarketController:Start()
	local HudController = require(script.Parent.HudController)

	self:_build()
	HudController:AddButton("💱 Market", function()
		if self._panel then
			Motion.toggle(self._panel)
		end
	end)

	Net.onEvent(NetRoutes.MARKET_SYNC, function(rows)
		if typeof(rows) == "table" then
			self:_refresh(rows)
		end
	end)
end

return MarketController
