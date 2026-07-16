--!strict
--[[
	Config/Regions.luau
	The shared world map of claimable regions. Regions sit on a grid; two regions
	are adjacent when they share an edge (computed from col/row in TerritoryService).
	Each owned region grants its `bonus` to the owner every economy tick and adds
	to national power. `cost` is the base influence to claim it (scaled by how many
	the claimant already holds).
]]

local Types = require(script.Parent.Parent.Types)

export type RegionDef = {
	id: string,
	displayName: string,
	col: number,
	row: number,
	cost: number, -- base influence
	value: number, -- strategic value (power score weight, display)
	bonus: Types.ResourceBag, -- per economy tick to the owner
}

local Regions: { [string]: RegionDef } = {}

local function define(def: RegionDef)
	Regions[def.id] = def
end

-- Row 0
define({ id = "harbor_flats", displayName = "Harbor Flats", col = 0, row = 0, cost = 40, value = 3, bonus = { money = 90 } })
define({ id = "iron_hills", displayName = "Iron Hills", col = 1, row = 0, cost = 45, value = 3, bonus = { materials = 10 } })
define({ id = "green_valley", displayName = "Green Valley", col = 2, row = 0, cost = 40, value = 2, bonus = { food = 30 } })
define({ id = "silver_coast", displayName = "Silver Coast", col = 3, row = 0, cost = 55, value = 4, bonus = { money = 70, influence = 2 } })
-- Row 1
define({ id = "emberworks", displayName = "Emberworks", col = 0, row = 1, cost = 50, value = 3, bonus = { materials = 8, money = 40 } })
define({ id = "central_basin", displayName = "Central Basin", col = 1, row = 1, cost = 60, value = 4, bonus = { money = 60, food = 15 } })
define({ id = "lumen_fields", displayName = "Lumen Fields", col = 2, row = 1, cost = 65, value = 4, bonus = { research = 6 } })
define({ id = "trade_nexus", displayName = "Trade Nexus", col = 3, row = 1, cost = 70, value = 5, bonus = { influence = 5, money = 50 } })
-- Row 2
define({ id = "frostmark", displayName = "Frostmark", col = 0, row = 2, cost = 50, value = 3, bonus = { materials = 6, research = 3 } })
define({ id = "highland_reach", displayName = "Highland Reach", col = 1, row = 2, cost = 55, value = 3, bonus = { food = 20, materials = 4 } })
define({ id = "aurora_steppe", displayName = "Aurora Steppe", col = 2, row = 2, cost = 75, value = 5, bonus = { research = 8 } })
define({ id = "meridian_cape", displayName = "Meridian Cape", col = 3, row = 2, cost = 70, value = 5, bonus = { influence = 6 } })

return Regions
