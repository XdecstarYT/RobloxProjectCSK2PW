--!strict
--[[
	Config/MilitaryUnits.luau
	Unit definitions for the (optional) military layer. Keys match the fields of
	Types.Military (army/navy/air). Units are a strategy-and-logistics investment:
	they cost resources up front, draw money upkeep every tick, and contribute
	strength used for power ranking, region defense, and forceful expansion
	against AI. Higher tiers are gated behind military technology.
]]

local Types = require(script.Parent.Parent.Types)

export type UnitDef = {
	branch: string,
	displayName: string,
	description: string,
	cost: Types.ResourceBag,
	upkeep: number, -- money per economy tick per unit
	strength: number,
	requiresTech: string?,
}

local MilitaryUnits: { [string]: UnitDef } = {
	army = {
		branch = "army",
		displayName = "Army Division",
		description = "Cheap, versatile ground forces. No prerequisites.",
		cost = { money = 1500, materials = 20 },
		upkeep = 15,
		strength = 3,
		requiresTech = nil,
	},
	navy = {
		branch = "navy",
		displayName = "Naval Fleet",
		description = "Projects power along coasts. Needs Naval Command.",
		cost = { money = 4000, materials = 80 },
		upkeep = 40,
		strength = 4,
		requiresTech = "military_1",
	},
	air = {
		branch = "air",
		displayName = "Air Wing",
		description = "Elite strike capability. Needs Air Command.",
		cost = { money = 7000, materials = 140 },
		upkeep = 70,
		strength = 5,
		requiresTech = "military_2",
	},
}

return MilitaryUnits
