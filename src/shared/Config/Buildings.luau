--!strict
--[[
	Config/Buildings.luau
	The catalogue every construction decision reads from. Each entry is a pure
	data record (Types.BuildingDef). Costs scale per upgrade level via `scale`,
	which keeps the tables terse while remaining fully data-driven.

	Balance intent:
	  * Level 1 is affordable early; upgrades cost geometrically more.
	  * Producers need power and jobs, so growth forces power + housing first.
	  * Every category has a clear role in the economy/citizen loop.
]]

local Types = require(script.Parent.Parent.Types)

type BuildingDef = Types.BuildingDef
type ResourceBag = Types.ResourceBag

-- Build a per-level cost table from a base cost and a geometric growth factor.
local function scale(base: ResourceBag, maxLevel: number, growth: number): { [number]: ResourceBag }
	local out: { [number]: ResourceBag } = {}
	for level = 1, maxLevel do
		local factor = growth ^ (level - 1)
		local bag: ResourceBag = {}
		for resource, amount in base do
			bag[resource :: any] = math.floor(amount * factor + 0.5)
		end
		out[level] = bag
	end
	return out
end

local Buildings: { [string]: BuildingDef } = {}

local function define(def: BuildingDef)
	Buildings[def.kind] = def
end

-- ---- Housing --------------------------------------------------------------

define({
	kind = "house",
	displayName = "Housing Block",
	category = "Housing",
	description = "Homes for citizens. More housing raises your population cap.",
	footprint = { w = 2, h = 2 },
	requiresTech = nil,
	maxLevel = 5,
	cost = scale({ money = 1200, materials = 40 }, 5, 1.8),
	upkeep = { money = 20 },
	produces = {},
	jobs = 0,
	powerDraw = 4,
	powerSupply = 0,
	happiness = 1,
	housing = 25,
})

define({
	kind = "apartments",
	displayName = "Apartment Tower",
	category = "Housing",
	description = "Dense vertical housing. Efficient land use, higher upkeep.",
	footprint = { w = 2, h = 2 },
	requiresTech = "construction_1",
	maxLevel = 5,
	cost = scale({ money = 6000, materials = 180 }, 5, 1.7),
	upkeep = { money = 90 },
	produces = {},
	jobs = 0,
	powerDraw = 14,
	powerSupply = 0,
	happiness = 0,
	housing = 120,
})

-- ---- Power ----------------------------------------------------------------

define({
	kind = "coal_plant",
	displayName = "Coal Power Plant",
	category = "Power",
	description = "Cheap, reliable power. Pollutes: a small happiness penalty.",
	footprint = { w = 3, h = 3 },
	requiresTech = nil,
	maxLevel = 4,
	cost = scale({ money = 4000, materials = 120 }, 4, 1.9),
	upkeep = { money = 120, materials = 5 },
	produces = {},
	jobs = 12,
	powerDraw = 0,
	powerSupply = 120,
	happiness = -2,
})

define({
	kind = "solar_farm",
	displayName = "Solar Array",
	category = "Power",
	description = "Clean power with no material upkeep. Unlocked by research.",
	footprint = { w = 3, h = 3 },
	requiresTech = "energy_2",
	maxLevel = 4,
	cost = scale({ money = 9000, materials = 200 }, 4, 1.8),
	upkeep = { money = 60 },
	produces = {},
	jobs = 6,
	powerDraw = 0,
	powerSupply = 150,
	happiness = 1,
})

-- ---- Food -----------------------------------------------------------------

define({
	kind = "farm",
	displayName = "Farm",
	category = "Food",
	description = "Produces food each tick to feed your population.",
	footprint = { w = 3, h = 3 },
	requiresTech = nil,
	maxLevel = 4,
	cost = scale({ money = 2000, materials = 60 }, 4, 1.7),
	upkeep = { money = 30 },
	produces = { food = 40 },
	jobs = 10,
	powerDraw = 6,
	powerSupply = 0,
	happiness = 0,
})

-- ---- Industry -------------------------------------------------------------

define({
	kind = "mine",
	displayName = "Materials Mine",
	category = "Industry",
	description = "Extracts raw materials used by all construction.",
	footprint = { w = 3, h = 3 },
	requiresTech = nil,
	maxLevel = 5,
	cost = scale({ money = 3500, materials = 50 }, 5, 1.8),
	upkeep = { money = 70 },
	produces = { materials = 18 },
	jobs = 16,
	powerDraw = 18,
	powerSupply = 0,
	happiness = -1,
})

define({
	kind = "factory",
	displayName = "Factory",
	category = "Industry",
	description = "Converts labour and power into strong tax revenue.",
	footprint = { w = 3, h = 3 },
	requiresTech = "industry_1",
	maxLevel = 5,
	cost = scale({ money = 8000, materials = 220 }, 5, 1.75),
	upkeep = { money = 150, materials = 8 },
	produces = { money = 260 },
	jobs = 30,
	powerDraw = 30,
	powerSupply = 0,
	happiness = -1,
})

-- ---- Commerce -------------------------------------------------------------

define({
	kind = "market",
	displayName = "Commercial Market",
	category = "Commerce",
	description = "Employs citizens and generates steady tax income.",
	footprint = { w = 2, h = 2 },
	requiresTech = nil,
	maxLevel = 5,
	cost = scale({ money = 3000, materials = 70 }, 5, 1.7),
	upkeep = { money = 60 },
	produces = { money = 120 },
	jobs = 18,
	powerDraw = 10,
	powerSupply = 0,
	happiness = 1,
})

-- ---- Research -------------------------------------------------------------

define({
	kind = "lab",
	displayName = "Research Lab",
	category = "Research",
	description = "Produces research points to advance your technology tree.",
	footprint = { w = 2, h = 2 },
	requiresTech = "computing_1",
	maxLevel = 5,
	cost = scale({ money = 7000, materials = 150 }, 5, 1.8),
	upkeep = { money = 130 },
	produces = { research = 8 },
	jobs = 20,
	powerDraw = 22,
	powerSupply = 0,
	happiness = 0,
})

-- ---- Public services ------------------------------------------------------

define({
	kind = "school",
	displayName = "School",
	category = "Services",
	description = "Raises the education of your citizens, boosting happiness.",
	footprint = { w = 2, h = 2 },
	requiresTech = nil,
	maxLevel = 4,
	cost = scale({ money = 4500, materials = 100 }, 4, 1.7),
	upkeep = { money = 110 },
	produces = {},
	jobs = 14,
	powerDraw = 10,
	powerSupply = 0,
	happiness = 2,
	education = 20,
})

define({
	kind = "hospital",
	displayName = "Hospital",
	category = "Services",
	description = "Improves citizen health and long-term happiness.",
	footprint = { w = 3, h = 2 },
	requiresTech = "medicine_1",
	maxLevel = 4,
	cost = scale({ money = 6500, materials = 160 }, 4, 1.7),
	upkeep = { money = 160 },
	produces = {},
	jobs = 22,
	powerDraw = 16,
	powerSupply = 0,
	happiness = 3,
	health = 25,
})

define({
	kind = "park",
	displayName = "City Park",
	category = "Services",
	description = "A cheap, cheerful happiness boost with tiny upkeep.",
	footprint = { w = 2, h = 2 },
	requiresTech = nil,
	maxLevel = 3,
	cost = scale({ money = 1500, materials = 30 }, 3, 1.6),
	upkeep = { money = 15 },
	produces = {},
	jobs = 2,
	powerDraw = 2,
	powerSupply = 0,
	happiness = 4,
})

-- ---- Government -----------------------------------------------------------

define({
	kind = "city_hall",
	displayName = "City Hall",
	category = "Government",
	description = "Seat of government. Reduces corruption and boosts influence.",
	footprint = { w = 3, h = 3 },
	requiresTech = nil,
	maxLevel = 3,
	cost = scale({ money = 5000, materials = 120 }, 3, 2.0),
	upkeep = { money = 100 },
	produces = { influence = 3 },
	jobs = 12,
	powerDraw = 12,
	powerSupply = 0,
	happiness = 1,
})

return Buildings
