--!strict
--[[
	Services/EventService.luau
	Keeps the world unpredictable: periodic national events hit a random nation,
	and rarer global events touch everyone at once. Every effect flows through the
	same authoritative nation state and fires a HUD notification, so events feel
	consequential without a separate rules engine.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Types = require(ReplicatedStorage.Nexus.Types)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)

type Nation = Types.Nation

local log = Logger.new("EventService")

local EventService = {
	Name = "EventService",
}

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- Each national event returns (severity, title, body) after mutating the nation.
type Event = { weight: number, apply: (Nation) -> (string, string, string) }

local NATIONAL: { Event } = {
	{
		weight = 3,
		apply = function(n)
			local gain = math.max(2000, n.economy.gdp * 2)
			n.resources.money += gain
			return "success", "Economic boom", ("Exports surge — treasury +%d."):format(math.floor(gain))
		end,
	},
	{
		weight = 2,
		apply = function(n)
			local loss = math.min(n.resources.money * 0.15, math.max(1500, n.economy.gdp))
			n.resources.money = math.max(0, n.resources.money - loss)
			return "warning", "Recession", ("A downturn costs the treasury %d."):format(math.floor(loss))
		end,
	},
	{
		weight = 2,
		apply = function(n)
			n.resources.research += 40
			return "success", "Research breakthrough", "Your scientists gift +40 research."
		end,
	},
	{
		weight = 2,
		apply = function(n)
			n.resources.materials += 200
			return "success", "Resource windfall", "A rich seam yields +200 materials."
		end,
	},
	{
		weight = 2,
		apply = function(n)
			local damaged = 0
			for _, b in n.buildings do
				if math.random() < 0.4 then
					b.condition = clamp(b.condition - 0.3, 0, 1)
					damaged += 1
				end
			end
			n.population.total = math.max(5, math.floor(n.population.total * 0.96))
			return "error", "Natural disaster", ("A storm damages %d buildings."):format(damaged)
		end,
	},
	{
		weight = 2,
		apply = function(n)
			n.population.unrest = clamp(n.population.unrest + 15, 0, 100)
			return "warning", "Civil unrest", "Protests erupt — unrest is climbing."
		end,
	},
	{
		weight = 2,
		apply = function(n)
			n.population.total = math.floor(n.population.total * 1.08) + 3
			return "info", "Migration wave", "New arrivals swell your population."
		end,
	},
}

local GLOBAL = {
	{
		title = "Global market surge",
		body = "Materials flow freely worldwide — everyone gains materials.",
		severity = "success",
		apply = function(n: Nation)
			n.resources.materials += 120
		end,
	},
	{
		title = "World research summit",
		body = "Shared breakthroughs boost every nation's research.",
		severity = "success",
		apply = function(n: Nation)
			n.resources.research += 25
		end,
	},
	{
		title = "Energy crisis",
		body = "Fuel shortages strain every treasury.",
		severity = "warning",
		apply = function(n: Nation)
			n.resources.money = math.max(0, n.resources.money - 2500)
		end,
	},
}

local function pickNational(): Event
	local total = 0
	for _, e in NATIONAL do
		total += e.weight
	end
	local roll = math.random() * total
	for _, e in NATIONAL do
		roll -= e.weight
		if roll <= 0 then
			return e
		end
	end
	return NATIONAL[1]
end

function EventService:_fireNational()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	local player = players[math.random(1, #players)]
	local nation = DataService:GetNation(player)
	if not nation then
		return
	end
	local event = pickNational()
	local severity, title, body = event.apply(nation)
	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, severity, title, body)
end

function EventService:_fireGlobal()
	local event = GLOBAL[math.random(1, #GLOBAL)]
	DataService:ForEachNation(function(player, nation)
		event.apply(nation)
		ReplicationService:MarkDirty(player)
	end)
	NotificationService:Broadcast(event.severity, event.title, event.body)
end

function EventService:Start()
	task.spawn(function()
		while true do
			task.wait(45 + math.random() * 30)
			pcall(function()
				self:_fireNational()
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(120 + math.random() * 60)
			pcall(function()
				self:_fireGlobal()
			end)
		end
	end)
	log:Info("event service ready")
end

return EventService
