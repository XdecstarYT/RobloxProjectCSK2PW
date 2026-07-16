--!strict
--[[
	Config/Objectives.luau
	Milestone objectives that give the game direction and reward progress. Each is
	a pure predicate over a nation's state plus a one-time resource reward, so the
	server can evaluate them cheaply on a loop and grant the reward the moment a
	milestone is reached. Order defines display order.
]]

local Types = require(script.Parent.Parent.Types)

type Nation = Types.Nation

export type ObjectiveDef = {
	id: string,
	title: string,
	desc: string,
	reward: Types.ResourceBag,
	check: (Nation) -> boolean,
}

local function buildingCount(n: Nation): number
	local c = 0
	for _ in n.buildings do
		c += 1
	end
	return c
end

local function techCount(n: Nation): number
	local c = 0
	for _, u in n.research.unlocked do
		if u then
			c += 1
		end
	end
	return c
end

local function mapRegions(n: Nation): number
	local c = 0
	for _, r in n.territory.regions do
		if r ~= "capital" then
			c += 1
		end
	end
	return c
end

local function allyCount(n: Nation): number
	local c = 0
	for _, a in n.diplomacy.allies do
		if a then
			c += 1
		end
	end
	return c
end

local function units(n: Nation): number
	return n.military.army + n.military.navy + n.military.air
end

local Objectives: { ObjectiveDef } = {
	{ id = "first_steps", title = "First Steps", desc = "Construct your first 3 buildings.", reward = { money = 3000 }, check = function(n)
		return buildingCount(n) >= 3
	end },
	{ id = "growing_town", title = "Growing Town", desc = "Reach a population of 100.", reward = { money = 5000, influence = 10 }, check = function(n)
		return n.population.total >= 100
	end },
	{ id = "metropolis", title = "Metropolis", desc = "Reach a population of 500.", reward = { influence = 40 }, check = function(n)
		return n.population.total >= 500
	end },
	{ id = "productive", title = "Productive Nation", desc = "Reach a GDP of 5,000 per tick.", reward = { money = 8000 }, check = function(n)
		return n.economy.gdp >= 5000
	end },
	{ id = "treasury", title = "Full Coffers", desc = "Hold a treasury of 100,000.", reward = { influence = 30 }, check = function(n)
		return n.resources.money >= 100000
	end },
	{ id = "content", title = "Content Citizens", desc = "Reach 80% happiness.", reward = { influence = 25 }, check = function(n)
		return n.population.happiness >= 80
	end },
	{ id = "scholars", title = "Age of Science", desc = "Unlock 3 technologies.", reward = { research = 60 }, check = function(n)
		return techCount(n) >= 3
	end },
	{ id = "lawmaker", title = "Lawmaker", desc = "Enact 2 laws at once.", reward = { money = 4000 }, check = function(n)
		local c = 0
		for _, a in n.politics.activeLaws do
			if a then
				c += 1
			end
		end
		return c >= 2
	end },
	{ id = "first_land", title = "Expansion", desc = "Claim your first region.", reward = { influence = 25 }, check = function(n)
		return mapRegions(n) >= 1
	end },
	{ id = "empire", title = "Empire", desc = "Control 5 regions.", reward = { money = 15000 }, check = function(n)
		return mapRegions(n) >= 5
	end },
	{ id = "diplomat", title = "Diplomat", desc = "Form an alliance.", reward = { influence = 40 }, check = function(n)
		return allyCount(n) >= 1
	end },
	{ id = "defender", title = "Standing Army", desc = "Field 10 military units.", reward = { money = 6000 }, check = function(n)
		return units(n) >= 10
	end },
}

return Objectives
