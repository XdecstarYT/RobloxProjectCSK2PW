--!strict
--[[
	Services/CityService.luau
	The authoritative city builder. Owns every building a nation places and is
	the single source of the aggregate "city stats" (production, upkeep, power,
	jobs, housing, services) that the economy and citizen simulations consume.

	Security: all four mutations (place/upgrade/demolish/repair) are validated
	end to end on the server — kind exists, tech unlocked, footprint fits and
	does not overlap, resources actually affordable — before any state changes.
	The client's request is a suggestion; this service decides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local ResourceMath = require(ReplicatedStorage.Nexus.ResourceMath)
local Types = require(ReplicatedStorage.Nexus.Types)
local Buildings = require(ReplicatedStorage.Nexus.Config.Buildings)
local Balance = require(ReplicatedStorage.Nexus.Config.Balance)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)
local Modifiers = require(script.Parent.Parent.Util.Modifiers)
local Validation = require(script.Parent.Parent.Util.Validation)

type Nation = Types.Nation
type Building = Types.Building
type BuildingDef = Types.BuildingDef
type ResourceBag = Types.ResourceBag
type Resolved = Modifiers.Resolved

export type CityStats = {
	production: ResourceBag,
	upkeep: ResourceBag,
	powerSupply: number,
	powerDraw: number,
	powerNet: number,
	jobs: number,
	housing: number,
	education: number,
	health: number,
	happinessFromBuildings: number,
	buildingCount: number,
}

local log = Logger.new("CityService")

local CityService = {
	Name = "CityService",
}

-- ---- Level scaling --------------------------------------------------------

local function prodFactor(level: number): number
	return 1 + 0.5 * (level - 1)
end
local function upkeepFactor(level: number): number
	return 1 + 0.4 * (level - 1)
end
local function jobsFactor(level: number): number
	return 1 + 0.5 * (level - 1)
end
local function housingFactor(level: number): number
	return 1 + 0.6 * (level - 1)
end

-- ---- Footprint / grid -----------------------------------------------------

local function orientedFootprint(def: BuildingDef, rotation: number): (number, number)
	if rotation == 90 or rotation == 270 then
		return def.footprint.h, def.footprint.w
	end
	return def.footprint.w, def.footprint.h
end

-- Returns the list of "x,z" tile keys a building would occupy, or nil if it
-- would fall outside the grid.
local function footprintTiles(pos: { x: number, z: number }, w: number, h: number): ({ string })?
	if pos.x + w > Constants.GRID_SIZE or pos.z + h > Constants.GRID_SIZE then
		return nil
	end
	local tiles = {}
	for dx = 0, w - 1 do
		for dz = 0, h - 1 do
			table.insert(tiles, (pos.x + dx) .. "," .. (pos.z + dz))
		end
	end
	return tiles
end

-- Build the set of occupied tiles for a nation, optionally ignoring one uid
-- (used when re-checking during an upgrade in place).
local function occupancy(nation: Nation, excludeId: string?): { [string]: boolean }
	local occupied = {}
	for id, building in nation.buildings do
		if id == excludeId then
			continue
		end
		local def = Buildings[building.kind]
		if not def then
			continue
		end
		local w, h = orientedFootprint(def, building.rotation)
		local tiles = footprintTiles(building.position, w, h)
		if tiles then
			for _, key in tiles do
				occupied[key] = true
			end
		end
	end
	return occupied
end

-- ---- Cost -----------------------------------------------------------------

-- Cost of a building at a given level, with the material-cost modifier applied.
local function effectiveCost(def: BuildingDef, level: number, resolved: Resolved): ResourceBag
	local base = def.cost[level]
	if not base then
		return {}
	end
	local out = table.clone(base)
	if out.materials then
		out.materials = math.max(0, math.floor(out.materials * resolved.materialCostMult + 0.5))
	end
	return out
end

-- ---- Aggregate stats ------------------------------------------------------

--- Recompute the entire city's contribution to the simulation. Called every
--- economy tick and never trusts stored derived values.
function CityService:ComputeStats(nation: Nation, resolved: Resolved): CityStats
	local stats: CityStats = {
		production = ResourceMath.zero(),
		upkeep = ResourceMath.zero(),
		powerSupply = 0,
		powerDraw = 0,
		powerNet = 0,
		jobs = 0,
		housing = 0,
		education = 0,
		health = 0,
		happinessFromBuildings = 0,
		buildingCount = 0,
	}
	local offline = Balance.CONSTRUCTION.offlineCondition

	-- First pass: total power. A plant contributes if its condition is healthy.
	for _, b in nation.buildings do
		local def = Buildings[b.kind]
		if not def or b.condition < offline then
			continue
		end
		stats.powerSupply += def.powerSupply * prodFactor(b.level) * resolved.powerSupplyMult
		stats.powerDraw += def.powerDraw * prodFactor(b.level)
	end
	stats.powerNet = stats.powerSupply - stats.powerDraw
	local powerRatio = 1.0
	if stats.powerDraw > stats.powerSupply and stats.powerDraw > 0 then
		powerRatio = stats.powerSupply / stats.powerDraw
	end

	-- Second pass: production, upkeep, jobs, services.
	for _, b in nation.buildings do
		local def = Buildings[b.kind]
		if not def then
			continue
		end
		stats.buildingCount += 1
		local healthy = b.condition >= offline
		b.active = healthy
		if not healthy then
			-- A derelict building still bleeds a little upkeep but produces nothing.
			continue
		end
		-- Power-consuming producers are throttled by the supply ratio.
		local eff = def.powerDraw > 0 and powerRatio or 1.0

		for resource, amount in def.produces do
			local value = amount * prodFactor(b.level) * eff
			if resource == "food" then
				value *= resolved.foodProductionMult
			elseif resource == "influence" then
				value *= resolved.influenceBonusMult
			end
			stats.production[resource :: any] += value
		end

		for resource, amount in def.upkeep do
			stats.upkeep[resource :: any] += amount * upkeepFactor(b.level) * resolved.upkeepMult
		end

		local jobFactor = jobsFactor(b.level)
		if def.category == "Industry" then
			jobFactor *= resolved.industryJobsMult
		end
		stats.jobs += def.jobs * jobFactor

		stats.housing += (def.housing or 0) * housingFactor(b.level)
		stats.education += (def.education or 0) * prodFactor(b.level) * eff
		stats.health += (def.health or 0) * prodFactor(b.level) * eff
		stats.happinessFromBuildings += def.happiness
	end

	return stats
end

--- Age every building. When the treasury covered maintenance, buildings slowly
--- recover; otherwise they decay and eventually go offline.
function CityService:TickCondition(nation: Nation, maintained: boolean)
	local decay = Balance.CONSTRUCTION.decayPerTick
	for _, b in nation.buildings do
		if maintained then
			b.condition = math.min(1, b.condition + decay * 0.5)
		else
			b.condition = math.max(0, b.condition - decay * 3)
		end
	end
end

-- ---- Mutations ------------------------------------------------------------

local uidCounter = 0
local function newUid(): string
	uidCounter += 1
	return ("b%d_%d"):format(os.time() % 100000, uidCounter)
end

function CityService:_place(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation then
		return { success = false, reason = "no_nation" }
	end
	if typeof(payload) ~= "table" then
		return { success = false, reason = "bad_payload" }
	end

	local def = Buildings[payload.kind]
	if not def then
		return { success = false, reason = "unknown_building" }
	end
	if def.requiresTech and not nation.research.unlocked[def.requiresTech] then
		return { success = false, reason = "tech_locked" }
	end
	local pos = Validation.readPosition(payload)
	if not pos then
		return { success = false, reason = "bad_position" }
	end
	local rotation = payload.rotation
	if not Validation.isRotation(rotation) then
		rotation = 0
	end

	local w, h = orientedFootprint(def, rotation)
	local tiles = footprintTiles(pos, w, h)
	if not tiles then
		return { success = false, reason = "out_of_bounds" }
	end
	local occupied = occupancy(nation)
	for _, key in tiles do
		if occupied[key] then
			return { success = false, reason = "overlap" }
		end
	end

	local resolved = Modifiers.resolve(nation)
	local cost = effectiveCost(def, 1, resolved)
	if not ResourceMath.canAfford(nation.resources, cost) then
		NotificationService:Send(player, "warning", "Cannot afford " .. def.displayName)
		return { success = false, reason = "insufficient_resources" }
	end

	ResourceMath.spend(nation.resources, cost)
	local id = newUid()
	nation.buildings[id] = {
		id = id,
		kind = def.kind,
		level = 1,
		position = pos,
		rotation = rotation,
		condition = 1,
		builtAt = os.time(),
		active = true,
	}

	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, "success", def.displayName .. " built")
	return { success = true, id = id }
end

function CityService:_upgrade(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local building = nation.buildings[payload.id]
	if not building then
		return { success = false, reason = "not_found" }
	end
	local def = Buildings[building.kind]
	if not def then
		return { success = false, reason = "unknown_building" }
	end
	local cap = math.min(def.maxLevel, Balance.CONSTRUCTION.maxLevel)
	if building.level >= cap then
		return { success = false, reason = "max_level" }
	end

	local resolved = Modifiers.resolve(nation)
	local cost = effectiveCost(def, building.level + 1, resolved)
	if not ResourceMath.canAfford(nation.resources, cost) then
		NotificationService:Send(player, "warning", "Cannot afford upgrade")
		return { success = false, reason = "insufficient_resources" }
	end

	ResourceMath.spend(nation.resources, cost)
	building.level += 1
	building.condition = 1
	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, "success", def.displayName .. " upgraded to level " .. building.level)
	return { success = true, level = building.level }
end

function CityService:_demolish(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local building = nation.buildings[payload.id]
	if not building then
		return { success = false, reason = "not_found" }
	end
	local def = Buildings[building.kind]
	if def then
		local resolved = Modifiers.resolve(nation)
		local refund = ResourceMath.scale(
			effectiveCost(def, building.level, resolved),
			Balance.CONSTRUCTION.demolishRefund
		)
		ResourceMath.grant(nation.resources, refund)
	end
	nation.buildings[payload.id] = nil
	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, "info", "Building demolished")
	return { success = true }
end

function CityService:_repair(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local building = nation.buildings[payload.id]
	if not building then
		return { success = false, reason = "not_found" }
	end
	local def = Buildings[building.kind]
	if not def then
		return { success = false, reason = "unknown_building" }
	end
	if building.condition >= 0.99 then
		return { success = false, reason = "already_good" }
	end

	local resolved = Modifiers.resolve(nation)
	-- Repair costs a fifth of the current level's build cost, scaled by damage.
	local damage = 1 - building.condition
	local cost = ResourceMath.scale(effectiveCost(def, building.level, resolved), 0.2 * damage)
	if not ResourceMath.canAfford(nation.resources, cost) then
		return { success = false, reason = "insufficient_resources" }
	end
	ResourceMath.spend(nation.resources, cost)
	building.condition = 1
	ReplicationService:MarkDirty(player)
	return { success = true }
end

function CityService:Start()
	Net.handleRequest(NetRoutes.PLACE_BUILDING, function(player, payload)
		return self:_place(player, payload)
	end, { rate = 10, per = 1 })

	Net.handleRequest(NetRoutes.UPGRADE_BUILDING, function(player, payload)
		return self:_upgrade(player, payload)
	end, { rate = 10, per = 1 })

	Net.handleRequest(NetRoutes.DEMOLISH_BUILDING, function(player, payload)
		return self:_demolish(player, payload)
	end, { rate = 10, per = 1 })

	Net.handleRequest(NetRoutes.REPAIR_BUILDING, function(player, payload)
		return self:_repair(player, payload)
	end, { rate = 10, per = 1 })

	log:Info("construction handlers ready")
end

return CityService
