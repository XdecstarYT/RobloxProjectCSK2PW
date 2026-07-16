--!strict
--[[
	Controllers/TutorialController.luau
	A guided first-session card. It shows one step at a time and auto-advances
	when the game state satisfies that step (e.g. a Coal Plant now exists), with
	Next/Skip for steps that aren't state-detectable. Shown once for new players
	(persisted via the tutorialDone flag) and replayable from Settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local ServerSettings = require(ReplicatedStorage.Nexus.Config.ServerSettings)

local Create = require(script.Parent.Parent.UI.Create)
local Decor = require(script.Parent.Parent.UI.Decor)
local Theme = require(script.Parent.Parent.UI.Theme)

local TutorialController = {
	Name = "TutorialController",
}

TutorialController._card = nil :: Frame?
TutorialController._text = nil :: TextLabel?
TutorialController._counter = nil :: TextLabel?
TutorialController._step = 1
TutorialController._active = false
TutorialController._started = false

local function hasBuilding(nation: any, kind: string): boolean
	for _, b in nation.buildings do
		if b.kind == kind then
			return true
		end
	end
	return false
end

-- `check` returns true when the step is satisfied by game state (nil = manual).
local STEPS: { { text: string, check: ((any) -> boolean)? } } = {
	{ text = "Welcome to Nexus! Open 🏗 Build and place a Coal Power Plant to power your city.", check = function(n)
		return hasBuilding(n, "coal_plant")
	end },
	{ text = "Now place a Farm to feed your growing population.", check = function(n)
		return hasBuilding(n, "farm")
	end },
	{ text = "Add a Housing Block so more citizens can move in.", check = function(n)
		return hasBuilding(n, "house")
	end },
	{ text = "Open 🔬 Research and start your first technology.", check = function(n)
		if n.research.current then
			return true
		end
		for _, u in n.research.unlocked do
			if u then
				return true
			end
		end
		return false
	end },
	{ text = "Open 🎯 Goals to see objectives that reward you as you grow.", check = nil },
	{ text = "You're ready! Trade in 💱 Market, expand in 🗺 Territory, and climb 🏆 Ranks. Good luck, leader!", check = nil },
}

function TutorialController:_build()
	local HudController = require(script.Parent.HudController)
	local gui = HudController:GetGui()

	local text = Create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 44),
		Font = Theme.font.medium,
		Text = "",
		TextColor3 = Theme.color.text,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}) :: TextLabel

	local counter = Create("TextLabel", {
		Name = "Counter",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 56),
		Size = UDim2.fromOffset(80, 22),
		Font = Theme.font.bold,
		Text = "Step 1/6",
		TextColor3 = Theme.color.accent,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}) :: TextLabel

	local function actionBtn(label: string, x: number, color: Color3, onClick: () -> ()): TextButton
		return Create("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, x, 1, -8),
			Size = UDim2.fromOffset(84, 28),
			BackgroundColor3 = color,
			Font = Theme.font.bold,
			Text = label,
			TextColor3 = Theme.color.text,
			TextSize = 13,
			[Create.Children] = { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) },
			[Create.Event] = { Activated = onClick },
		}) :: TextButton
	end

	local card = Create("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -128),
		Size = UDim2.fromOffset(440, 92),
		BackgroundColor3 = Theme.color.panel,
		Visible = false,
		[Create.Children] = {
			Create("UICorner", { CornerRadius = Theme.corner }),
			Create("UIStroke", { Color = Theme.color.accent, Thickness = 1.5, Transparency = 0.2 }),
			text,
			counter,
			actionBtn("Next →", -10, Theme.color.accentDim, function()
				self:_advance()
			end),
			actionBtn("Skip", -102, Color3.fromRGB(70, 74, 90), function()
				self:_finish()
			end),
		},
	}) :: Frame
	Decor.gradient(card, Theme.gradient.panel)
	card.Parent = gui

	self._card = card
	self._text = text
	self._counter = counter
end

function TutorialController:_render()
	local step = STEPS[self._step]
	if self._text then
		self._text.Text = step.text
	end
	if self._counter then
		self._counter.Text = ("Step %d/%d"):format(self._step, #STEPS)
	end
end

function TutorialController:_show()
	self._active = true
	self:_render()
	if self._card then
		self._card.Visible = true
	end
end

function TutorialController:_advance()
	if self._step >= #STEPS then
		self:_finish()
		return
	end
	self._step += 1
	self:_render()
end

function TutorialController:_finish()
	self._active = false
	if self._card then
		self._card.Visible = false
	end
	task.spawn(function()
		Net.request(NetRoutes.TUTORIAL_DONE)
	end)
end

--- Replay from the beginning (used by the Settings panel).
function TutorialController:Restart()
	self._step = 1
	self:_show()
end

function TutorialController:Start()
	local StateController = require(script.Parent.StateController)
	self:_build()

	StateController.Changed:Connect(function(snapshot)
		local nation = snapshot.nation
		-- Auto-start once for a new nation.
		if not self._started then
			self._started = true
			if ServerSettings.showStartingHints and not nation.flags.tutorialDone then
				self:_show()
			end
		end
		-- Auto-advance when the current step's condition is met.
		if self._active then
			local step = STEPS[self._step]
			if step.check and step.check(nation) then
				self:_advance()
			end
		end
	end)
end

return TutorialController
