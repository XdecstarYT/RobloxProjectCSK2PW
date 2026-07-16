--!strict
--[[
	Services/AIService.luau
	Server-owned AI nations that share the exact same Nation shape as players, so
	the leaderboard, diplomacy and territory systems treat them uniformly (no
	special-casing anywhere else). Each AI has a strategy profile that biases how
	it grows and what it trades for.

	AI economies are simulated with a lightweight aggregate growth model rather
	than the full grid builder — enough to make them living rivals on the
	leaderboard and credible trade/alliance partners, without a second economy
	engine to maintain.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local ResourceMath = require(ReplicatedStorage.Nexus.ResourceMath)
local Types = require(ReplicatedStorage.Nexus.Types)
local Technologies = require(ReplicatedStorage.Nexus.Config.Technologies)

local DiplomacyService = require(script.Parent.DiplomacyService)
local WorldService = require(script.Parent.WorldService)

type Nation = Types.Nation

local log = Logger.new("AIService")

local AIService = {
	Name = "AIService",
}

AIService._nations = {} :: { [number]: Nation }
AIService._profiles = {} :: { [number]: any }
AIService._age = {} :: { [number]: number }

-- Strategy archetypes bias the growth weights.
type Profile = {
	label: string,
	gov: Types.GovernmentId,
	gdp: number,
	pop: number,
	research: number,
	diplo: number,
	military: number,
}

local ARCHETYPES: { [string]: Profile } = {
	economic = { label = "economic", gov = "republic", gdp = 1.25, pop = 1.1, research = 0.9, diplo = 1.0, military = 0.6 },
	technological = { label = "technological", gov = "technocracy", gdp = 1.0, pop = 0.95, research = 1.6, diplo = 0.9, military = 0.7 },
	diplomatic = { label = "diplomatic", gov = "democracy", gdp = 1.05, pop = 1.05, research = 1.0, diplo = 1.6, military = 0.5 },
	militarist = { label = "militarist", gov = "military", gdp = 0.95, pop = 1.0, research = 0.85, diplo = 0.7, military = 1.8 },
	balanced = { label = "balanced", gov = "monarchy", gdp = 1.1, pop = 1.05, research = 1.05, diplo = 1.05, military = 1.0 },
}

local ROSTER = {
	{ name = "Veltoria", profile = "economic" },
	{ name = "Auronia", profile = "technological" },
	{ name = "Solmara Union", profile = "diplomatic" },
	{ name = "Kravok Dominion", profile = "militarist" },
	{ name = "Cindral Republic", profile = "balanced" },
}

-- ---- Construction ---------------------------------------------------------

local function makeNation(id: number, name: string, profile: Profile): Nation
	local resources = ResourceMath.zero()
	resources.money = 30000
	resources.materials = 800
	resources.food = 600
	resources.influence = 60
	return {
		ownerId = id,
		name = name,
		founded = os.time(),
		resources = resources,
		buildings = {},
		population = {
			total = 60,
			employed = 40,
			happiness = 62,
			education = 30,
			health = 45,
			unrest = 5,
		},
		politics = {
			government = profile.gov,
			approval = 60,
			stability = 65,
			corruption = 8,
			taxRate = 0.2,
			activeLaws = {},
			nextElection = 0,
		},
		economy = {
			gdp = 800,
			gdpHistory = {},
			treasury = resources.money,
			debt = 0,
			inflation = 2,
			interestRate = 4,
			lastTickIncome = 0,
			lastTickExpense = 0,
		},
		research = { unlocked = {}, current = nil, progress = 0, points = 0 },
		military = { army = 0, navy = 0, air = 0 },
		diplomacy = { allies = {} },
		territory = { regions = {} },
		flags = { ai = true },
	}
end

-- ---- Growth simulation ----------------------------------------------------

local function availableTech(nation: Nation): string?
	local candidates = {}
	for id, def in Technologies do
		if not nation.research.unlocked[id] then
			local ok = true
			for _, req in def.requires do
				if not nation.research.unlocked[req] then
					ok = false
					break
				end
			end
			if ok then
				table.insert(candidates, id)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

function AIService:_grow(id: number, nation: Nation, profile: Profile)
	self._age[id] += 1
	local age = self._age[id]

	-- Population drifts toward a slowly rising cap.
	local popCap = 60 + age * 6 * profile.pop
	nation.population.total = math.floor(nation.population.total + (popCap - nation.population.total) * 0.1 + 0.5)

	-- GDP scales with population and the economic bias, with mild noise.
	local gdp = nation.population.total * 12 * profile.gdp * (0.9 + math.random() * 0.2)
	nation.economy.gdp = gdp
	local income = gdp * nation.politics.taxRate * 0.85
	nation.resources.money += income
	nation.economy.treasury = nation.resources.money
	nation.economy.lastTickIncome = income

	-- Materials and food accumulate; surplus fuels trade.
	nation.resources.materials += 12 * profile.gdp
	nation.resources.food += 6
	nation.resources.influence += 2 * profile.diplo

	-- Research: accumulate and occasionally unlock an available technology.
	nation.resources.research += nation.population.total * 0.03 * profile.research
	if math.random() < 0.05 * profile.research then
		local tech = availableTech(nation)
		if tech then
			nation.research.unlocked[tech] = true
		end
	end

	-- Militarists build a standing force out of their treasury.
	if math.random() < 0.15 * profile.military and nation.resources.money > 8000 then
		nation.resources.money -= 4000
		local branch = ({ "army", "navy", "air" })[math.random(1, 3)]
		nation.military[branch] += 1
	end

	-- Gentle political drift keeps their stats lively.
	nation.politics.approval = math.clamp(nation.politics.approval + (math.random() - 0.5) * 4, 30, 95)
	nation.politics.stability = math.clamp(nation.politics.stability + (math.random() - 0.5) * 3, 25, 95)
end

-- ---- Diplomacy behaviour --------------------------------------------------

function AIService:_maybeTrade()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	-- Pick a random AI and a random human target.
	local ids = {}
	for id in self._nations do
		table.insert(ids, id)
	end
	if #ids == 0 then
		return
	end
	local aiId = ids[math.random(1, #ids)]
	local nation = self._nations[aiId]
	local profile = self._profiles[aiId]
	local target = players[math.random(1, #players)]

	if math.random() < 0.15 * profile.diplo then
		-- Offer an alliance instead of a trade.
		DiplomacyService:CreateOffer(aiId, target.UserId, "alliance", {}, {})
		return
	end

	-- Give a surplus resource, ask for something the profile values.
	local give: Types.ResourceBag = {}
	local receive: Types.ResourceBag = {}
	if nation.resources.money > 12000 then
		give.money = 4000
	elseif nation.resources.materials > 300 then
		give.materials = 150
	else
		return
	end
	if profile.research > 1.1 then
		receive.research = 60
	elseif profile.military > 1.1 then
		receive.materials = 120
	else
		receive.influence = 25
	end
	DiplomacyService:CreateOffer(aiId, target.UserId, "trade", give, receive)
end

-- ---- Lifecycle ------------------------------------------------------------

function AIService:GetNation(id: number): Nation?
	return self._nations[id]
end

function AIService:Start()
	for i, spec in ROSTER do
		local id = -i
		local profile = ARCHETYPES[spec.profile]
		local nation = makeNation(id, spec.name, profile)
		self._nations[id] = nation
		self._profiles[id] = profile
		self._age[id] = 0
		WorldService:RegisterAI(id, nation)
	end
	log:Info(("spawned %d AI nations"):format(#ROSTER))

	-- Growth loop.
	task.spawn(function()
		while true do
			task.wait(6)
			for id, nation in self._nations do
				pcall(function()
					self:_grow(id, nation, self._profiles[id])
				end)
			end
		end
	end)

	-- Occasional diplomacy toward human players.
	task.spawn(function()
		while true do
			task.wait(20)
			pcall(function()
				self:_maybeTrade()
			end)
		end
	end)
end

return AIService
