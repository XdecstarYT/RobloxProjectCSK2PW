--!strict
--[[
	Controllers/DiplomacyController.luau
	The diplomacy screen: pick another nation, compose a resource-for-resource
	trade (or propose an alliance), and act on incoming offers. Reads the world
	directory and trade inbox from WorldStateController; every action is a
	validated server request.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Resources = require(ReplicatedStorage.Nexus.Config.Resources)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Format = require(script.Parent.Parent.UI.Format)
local Motion = require(script.Parent.Parent.UI.Motion)
local Theme = require(script.Parent.Parent.UI.Theme)

local ORDER = Constants.RESOURCE_ORDER

local DiplomacyController = {
	Name = "DiplomacyController",
}

DiplomacyController._panel = nil :: Frame?
DiplomacyController._targetId = nil :: number?
DiplomacyController._targetName = "—"
DiplomacyController._give = { idx = 1, amt = 1000 }
DiplomacyController._recv = { idx = 2, amt = 100 }
DiplomacyController._refs = {} :: any

local function request(route: string, payload: any)
	task.spawn(function()
		Net.request(route, payload)
	end)
end

local function stepFor(resource: string): number
	if resource == "money" then
		return 1000
	elseif resource == "materials" or resource == "food" then
		return 50
	end
	return 20
end

local function bagSummary(bag: any): string
	local parts = {}
	for _, id in ORDER do
		local amt = bag and bag[id]
		if amt and amt > 0 then
			table.insert(parts, (Resources[id].symbol) .. Format.abbrev(amt))
		end
	end
	return #parts > 0 and table.concat(parts, " ") or "—"
end

-- ---- Resource+amount stepper -----------------------------------------------

function DiplomacyController:_stepper(label: string, state: any, order: number): Frame
	local resLabel: TextLabel
	local amtLabel: TextLabel

	local function refresh()
		local res = ORDER[state.idx]
		resLabel.Text = Resources[res].symbol .. " " .. Resources[res].displayName
		amtLabel.Text = Format.abbrev(state.amt)
	end

	local frame = Create("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Theme.color.panelLight,
		Size = UDim2.new(1, 0, 0, 56),
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -20, 0, 14),
				Font = Theme.font.regular,
				Text = label,
				TextColor3 = Theme.color.textDim,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextButton", {
				Name = "Res",
				BackgroundColor3 = Theme.color.bg,
				Position = UDim2.fromOffset(10, 20),
				Size = UDim2.fromOffset(150, 28),
				Font = Theme.font.bold,
				Text = "",
				TextColor3 = Theme.color.text,
				TextSize = 12,
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
				[Create.Event] = { Activated = function()
					state.idx = (state.idx % #ORDER) + 1
					state.amt = stepFor(ORDER[state.idx])
					refresh()
				end },
			}),
			Create("TextButton", {
				BackgroundColor3 = Theme.color.accentDim,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -84, 0, 20),
				Size = UDim2.fromOffset(28, 28),
				Font = Theme.font.bold,
				Text = "−",
				TextColor3 = Theme.color.text,
				TextSize = 18,
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
				[Create.Event] = { Activated = function()
					state.amt = math.max(0, state.amt - stepFor(ORDER[state.idx]))
					refresh()
				end },
			}),
			Create("TextLabel", {
				Name = "Amt",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -46, 0, 20),
				Size = UDim2.fromOffset(40, 28),
				Font = Theme.font.bold,
				Text = "0",
				TextColor3 = Theme.color.text,
				TextSize = 13,
			}),
			Create("TextButton", {
				BackgroundColor3 = Theme.color.accentDim,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 20),
				Size = UDim2.fromOffset(28, 28),
				Font = Theme.font.bold,
				Text = "+",
				TextColor3 = Theme.color.text,
				TextSize = 18,
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
				[Create.Event] = { Activated = function()
					state.amt += stepFor(ORDER[state.idx])
					refresh()
				end },
			}),
		},
	}) :: Frame
	resLabel = frame:FindFirstChild("Res") :: TextLabel
	amtLabel = frame:FindFirstChild("Amt") :: TextLabel
	refresh()
	return frame
end

-- ---- Panel -----------------------------------------------------------------

function DiplomacyController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local targetList = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 0, 130),
		BackgroundColor3 = Theme.color.bg,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
			Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
		},
	}) :: ScrollingFrame

	local targetLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 176),
		Size = UDim2.new(1, -20, 0, 18),
		Font = Theme.font.bold,
		Text = "Select a nation above",
		TextColor3 = Theme.color.accent,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel

	local composer = Create("Frame", {
		Position = UDim2.fromOffset(10, 198),
		Size = UDim2.new(1, -20, 0, 128),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	})
	self:_stepper("You give", self._give, 1).Parent = composer
	self:_stepper("You receive", self._recv, 2).Parent = composer

	local buttons = Create("Frame", {
		Position = UDim2.fromOffset(10, 332),
		Size = UDim2.new(1, -20, 0, 34),
		BackgroundTransparency = 1,
		[Create.Children] = {
			Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Create("TextButton", {
				BackgroundColor3 = Theme.color.accentDim,
				Size = UDim2.fromOffset(150, 34),
				Font = Theme.font.bold,
				Text = "Send Trade",
				TextColor3 = Theme.color.text,
				TextSize = 14,
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 8) }) },
				[Create.Event] = { Activated = function()
					self:_sendTrade()
				end },
			}),
			Create("TextButton", {
				BackgroundColor3 = Theme.color.panelLight,
				Size = UDim2.fromOffset(150, 34),
				Font = Theme.font.bold,
				Text = "Propose Alliance",
				TextColor3 = Theme.color.text,
				TextSize = 14,
				[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 8) }) },
				[Create.Event] = { Activated = function()
					if self._targetId then
						request(NetRoutes.PROPOSE_ALLIANCE, { toId = self._targetId })
					end
				end },
			}),
		},
	})

	local inbox = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 396),
		Size = UDim2.new(1, -20, 1, -406),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		},
	}) :: ScrollingFrame

	local panel = Create("Frame", {
		Name = "DiplomacyPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 560),
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
				Text = "🤝 Diplomacy",
				TextColor3 = Theme.color.text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 374),
				Size = UDim2.new(1, -28, 0, 18),
				Font = Theme.font.bold,
				Text = "Incoming offers",
				TextColor3 = Theme.color.accent2,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			targetList,
			targetLabel,
			composer,
			buttons,
			inbox,
		},
	}) :: Frame
	Decor.gradient(panel, Theme.gradient.panel)
	panel.Parent = gui
	self._panel = panel
	self._refs = { targetList = targetList, targetLabel = targetLabel, inbox = inbox }
end

function DiplomacyController:_sendTrade()
	if not self._targetId then
		return
	end
	local giveRes = ORDER[self._give.idx]
	local recvRes = ORDER[self._recv.idx]
	local give = self._give.amt > 0 and { [giveRes] = self._give.amt } or {}
	local receive = self._recv.amt > 0 and { [recvRes] = self._recv.amt } or {}
	request(NetRoutes.PROPOSE_TRADE, { toId = self._targetId, give = give, receive = receive })
end

function DiplomacyController:_selectTarget(id: number, name: string)
	self._targetId = id
	self._targetName = name
	if self._refs.targetLabel then
		self._refs.targetLabel.Text = "Trading with: " .. name
	end
	self:_refreshTargets(nil)
end

function DiplomacyController:_refreshTargets(directory: { any }?)
	local WorldStateController = require(script.Parent.WorldStateController)
	directory = directory or WorldStateController:GetDirectory()
	local list = self._refs.targetList
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local myId = Players.LocalPlayer.UserId
	for _, row in directory :: { any } do
		if row.id == myId then
			continue
		end
		local selected = row.id == self._targetId
		local btn = Create("TextButton", {
			LayoutOrder = row.rank,
			BackgroundColor3 = selected and Theme.color.accentDim or Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 30),
			Font = Theme.font.medium,
			Text = "",
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(8, 0),
					Size = UDim2.new(1, -80, 1, 0),
					Font = Theme.font.medium,
					Text = row.name .. (row.isAI and "  🤖" or ""),
					TextColor3 = Theme.color.text,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(64, 30),
					Font = Theme.font.bold,
					Text = "⚙" .. Format.abbrev(row.power),
					TextColor3 = Theme.color.accent,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
			},
			[Create.Event] = { Activated = function()
				self:_selectTarget(row.id, row.name)
			end },
		})
		btn.Parent = list
	end
end

function DiplomacyController:_refreshInbox(inbox: any)
	local list = self._refs.inbox
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, offer in inbox.incoming do
		local isAlliance = offer.kind == "alliance"
		local desc = isAlliance and "Proposes an alliance"
			or ("Gives " .. bagSummary(offer.give) .. "  for  " .. bagSummary(offer.receive))
		local card = Create("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = Theme.color.panelLight,
			Size = UDim2.new(1, 0, 0, 58),
			[Create.Children] = {
				Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 5),
					Size = UDim2.new(1, -20, 0, 16),
					Font = Theme.font.bold,
					Text = offer.fromName,
					TextColor3 = Theme.color.text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 22),
					Size = UDim2.new(1, -20, 0, 14),
					Font = Theme.font.regular,
					Text = desc,
					TextColor3 = Theme.color.textDim,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
				Create("TextButton", {
					BackgroundColor3 = Theme.color.good,
					Position = UDim2.fromOffset(10, 38),
					Size = UDim2.fromOffset(70, 16),
					Font = Theme.font.bold,
					Text = "Accept",
					TextColor3 = Theme.color.bg,
					TextSize = 11,
					[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 5) }) },
					[Create.Event] = { Activated = function()
						request(NetRoutes.RESPOND_TRADE, { id = offer.id, accept = true })
					end },
				}),
				Create("TextButton", {
					BackgroundColor3 = Theme.color.bad,
					Position = UDim2.fromOffset(88, 38),
					Size = UDim2.fromOffset(70, 16),
					Font = Theme.font.bold,
					Text = "Decline",
					TextColor3 = Theme.color.bg,
					TextSize = 11,
					[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 5) }) },
					[Create.Event] = { Activated = function()
						request(NetRoutes.RESPOND_TRADE, { id = offer.id, accept = false })
					end },
				}),
			},
		})
		card.Parent = list
	end
end

function DiplomacyController:Start()
	local HudController = require(script.Parent.HudController)
	local WorldStateController = require(script.Parent.WorldStateController)

	self:_build()
	HudController:AddButton("🤝 Diplomacy", function()
		if self._panel then
			Motion.toggle(self._panel)
		end
	end)

	WorldStateController.DirectoryChanged:Connect(function(dir)
		self:_refreshTargets(dir)
	end)
	WorldStateController.InboxChanged:Connect(function(inbox)
		self:_refreshInbox(inbox)
	end)
	self:_refreshTargets(nil)
	self:_refreshInbox(WorldStateController:GetInbox())
end

return DiplomacyController
