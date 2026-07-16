--!strict
--[[
	Config/Technologies.luau
	The research tree. Each tech gates buildings and/or applies named modifiers
	that services look up (e.g. EconomyService reads "taxBonus"). Prerequisites
	form a DAG validated by ResearchService before anything can be unlocked.
]]

local Types = require(script.Parent.Parent.Types)

type TechDef = Types.TechDef

local Technologies: { [string]: TechDef } = {}

local function define(def: TechDef)
	Technologies[def.id] = def
end

-- ---- Construction branch --------------------------------------------------

define({
	id = "construction_1",
	displayName = "Reinforced Concrete",
	branch = "Construction",
	description = "Unlocks dense apartment towers and cuts material costs 5%.",
	cost = 40,
	requires = {},
	unlocksBuildings = { "apartments" },
	modifiers = { materialCost = -0.05 },
})

-- ---- Energy branch --------------------------------------------------------

define({
	id = "energy_1",
	displayName = "Grid Efficiency",
	branch = "Energy",
	description = "Power plants supply 10% more energy.",
	cost = 30,
	requires = {},
	unlocksBuildings = {},
	modifiers = { powerSupply = 0.10 },
})

define({
	id = "energy_2",
	displayName = "Photovoltaics",
	branch = "Energy",
	description = "Unlocks clean solar arrays.",
	cost = 80,
	requires = { "energy_1" },
	unlocksBuildings = { "solar_farm" },
	modifiers = {},
})

-- ---- Industry branch ------------------------------------------------------

define({
	id = "industry_1",
	displayName = "Assembly Lines",
	branch = "Industry",
	description = "Unlocks factories for high tax revenue.",
	cost = 60,
	requires = {},
	unlocksBuildings = { "factory" },
	modifiers = {},
})

define({
	id = "industry_2",
	displayName = "Automation",
	branch = "Industry",
	description = "Industry buildings need 15% fewer workers.",
	cost = 120,
	requires = { "industry_1", "computing_1" },
	unlocksBuildings = {},
	modifiers = { industryJobs = -0.15 },
})

-- ---- Computing branch -----------------------------------------------------

define({
	id = "computing_1",
	displayName = "Digital Records",
	branch = "Computing",
	description = "Unlocks research labs and reduces corruption growth.",
	cost = 50,
	requires = {},
	unlocksBuildings = { "lab" },
	modifiers = { corruptionCreep = -0.30 },
})

-- ---- Medicine branch ------------------------------------------------------

define({
	id = "medicine_1",
	displayName = "Public Health",
	branch = "Medicine",
	description = "Unlocks hospitals and lifts baseline citizen health.",
	cost = 70,
	requires = {},
	unlocksBuildings = { "hospital" },
	modifiers = { baseHealth = 10 },
})

-- ---- Agriculture branch ---------------------------------------------------

define({
	id = "agriculture_1",
	displayName = "Crop Rotation",
	branch = "Agriculture",
	description = "Farms produce 25% more food.",
	cost = 45,
	requires = {},
	unlocksBuildings = {},
	modifiers = { foodProduction = 0.25 },
})

-- ---- Government branch -----------------------------------------------------

define({
	id = "government_1",
	displayName = "Civil Service",
	branch = "Government",
	description = "Tax collection is 8% more efficient.",
	cost = 90,
	requires = { "computing_1" },
	unlocksBuildings = {},
	modifiers = { taxEfficiency = 0.08 },
})

define({
	id = "government_2",
	displayName = "Diplomatic Corps",
	branch = "Government",
	description = "Generates extra influence and unlocks advanced diplomacy.",
	cost = 150,
	requires = { "government_1" },
	unlocksBuildings = {},
	modifiers = { influenceBonus = 0.20 },
})

return Technologies
