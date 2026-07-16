--!strict
--[[
	Services/CitizenService.luau
	The populace as a living system. Each tick it moves education and health
	toward what the city's services can support, derives a happiness target from
	services, taxes, jobs, food and housing, and lets happiness drive migration.
	Unhappy, hungry or crowded nations shrink; prosperous ones attract residents.

	Population is what makes the economy turn (workers) and what politics answers
	to (voters), so this service is deliberately the hinge between the two.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Types = require(ReplicatedStorage.Nexus.Types)
local Balance = require(ReplicatedStorage.Nexus.Config.Balance)

type Nation = Types.Nation

local log = Logger.new("CitizenService")

local CitizenService = {
	Name = "CitizenService",
}

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- Ease a value a fraction of the way toward a target (exponential smoothing).
local function drift(current: number, target: number, rate: number): number
	return current + (target - current) * rate
end

function CitizenService:Tick(nation: Nation, frame: any)
	local C = Balance.CITIZENS
	local stats = frame.stats
	local resolved = frame.resolved
	local pop = nation.population
	local total = math.max(pop.total, 1)

	-- Service coverage: points relative to population, capped at full quality.
	local eduTarget = clamp((stats.education / total) * 200, 0, 100)
	local healthTarget = clamp((stats.health / total) * 200 + resolved.baseHealthFlat, 0, 100)
	pop.education = clamp(drift(pop.education, eduTarget, C.serviceInfluence), 0, 100)
	pop.health = clamp(drift(pop.health, healthTarget, C.serviceInfluence), 0, 100)

	-- Happiness target: sum of every push and pull on public mood.
	local happiness = C.baseHappiness
	happiness += stats.happinessFromBuildings
	happiness += resolved.happinessFlat
	happiness += (pop.education - 50) * 0.1
	happiness += (pop.health - 50) * 0.1

	-- Taxes above a comfort threshold sour the public.
	local taxOver = math.max(0, nation.politics.taxRate - 0.2)
	happiness -= taxOver * 80

	-- Unemployment beyond tolerance hurts, but is capped so an empty new nation
	-- (no jobs yet) is a recoverable slump, not an instant collapse.
	if frame.unemployment > C.unemploymentTolerance then
		happiness -= math.min(20, (frame.unemployment - C.unemploymentTolerance) * 50)
	end

	-- Hunger and overcrowding.
	if frame.foodShortage > 0 then
		happiness -= math.min(30, frame.foodShortage * 0.5)
	end
	local capacity = stats.housing * C.housingMultiplier
	if total > capacity and capacity > 0 then
		happiness -= math.min(25, (total - capacity) / capacity * 40)
	end

	happiness -= pop.unrest * 0.2
	local happinessTarget = clamp(happiness, 0, 100)
	pop.happiness = clamp(drift(pop.happiness, happinessTarget, 0.25), 0, 100)

	-- Unrest rises with misery, hunger and corruption; falls otherwise.
	local unrestTarget = clamp(
		(50 - pop.happiness) * 0.8
			+ frame.foodShortage * Balance.ECONOMY.starvationUnrest
			+ (nation.politics.corruption - 20) * 0.3,
		0,
		100
	)
	pop.unrest = clamp(drift(pop.unrest, unrestTarget, 0.2), 0, 100)

	-- Migration: happy nations with spare housing grow; miserable ones shrink.
	local growth = 0
	if pop.happiness >= C.migrationHappiness and total < capacity then
		growth = (capacity - total) * C.growthRate * (pop.happiness / 100)
	elseif pop.happiness < C.migrationHappiness then
		growth = -(total * C.growthRate * ((C.migrationHappiness - pop.happiness) / 100))
	elseif total > capacity then
		growth = -((total - capacity) * C.growthRate)
	end

	-- Starvation causes outright decline on top of migration.
	if frame.foodShortage > 0 then
		growth -= frame.foodShortage * 0.2
	end

	pop.total = math.max(5, math.floor(total + growth + 0.5))
end

function CitizenService:Init()
	log:Debug("citizen simulation ready")
end

return CitizenService
