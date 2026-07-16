--!strict
--[[
	Config/Governments.luau
	Government archetypes. Each one reshapes the game through a bundle of
	multipliers and switches that the economy, citizen and politics services
	read. Switching government is a meaningful strategic pivot, not cosmetic.
]]

local Types = require(script.Parent.Parent.Types)

type GovernmentId = Types.GovernmentId

export type GovernmentDef = {
	id: GovernmentId,
	displayName: string,
	description: string,
	holdsElections: boolean,
	modifiers: {
		taxCeiling: number, -- highest tax rate the government may set
		taxEfficiency: number, -- multiplier on collected revenue
		happiness: number, -- flat happiness offset
		corruptionCreep: number, -- multiplier on corruption growth
		researchBonus: number, -- multiplier on research output
		influenceBonus: number, -- multiplier on influence generation
		stability: number, -- flat stability offset
	},
}

local Governments: { [GovernmentId]: GovernmentDef } = {
	democracy = {
		id = "democracy",
		displayName = "Democracy",
		description = "Elections keep you accountable. High happiness, capped taxes.",
		holdsElections = true,
		modifiers = {
			taxCeiling = 0.45,
			taxEfficiency = 1.0,
			happiness = 6,
			corruptionCreep = 0.8,
			researchBonus = 1.1,
			influenceBonus = 1.15,
			stability = 5,
		},
	},
	republic = {
		id = "republic",
		displayName = "Republic",
		description = "Balanced representative rule. A dependable all-rounder.",
		holdsElections = true,
		modifiers = {
			taxCeiling = 0.5,
			taxEfficiency = 1.05,
			happiness = 3,
			corruptionCreep = 1.0,
			researchBonus = 1.05,
			influenceBonus = 1.05,
			stability = 3,
		},
	},
	monarchy = {
		id = "monarchy",
		displayName = "Monarchy",
		description = "Tradition and stability, but slower to modernise.",
		holdsElections = false,
		modifiers = {
			taxCeiling = 0.55,
			taxEfficiency = 1.0,
			happiness = 2,
			corruptionCreep = 1.1,
			researchBonus = 0.9,
			influenceBonus = 1.1,
			stability = 8,
		},
	},
	socialist = {
		id = "socialist",
		displayName = "Socialist State",
		description = "High services and equality; taxes can run very high.",
		holdsElections = true,
		modifiers = {
			taxCeiling = 0.7,
			taxEfficiency = 0.95,
			happiness = 4,
			corruptionCreep = 1.0,
			researchBonus = 1.0,
			influenceBonus = 0.95,
			stability = 2,
		},
	},
	technocracy = {
		id = "technocracy",
		displayName = "Technocracy",
		description = "Rule by experts. Powerful research, modest happiness.",
		holdsElections = false,
		modifiers = {
			taxCeiling = 0.5,
			taxEfficiency = 1.1,
			happiness = 0,
			corruptionCreep = 0.6,
			researchBonus = 1.35,
			influenceBonus = 1.0,
			stability = 4,
		},
	},
	military = {
		id = "military",
		displayName = "Military Government",
		description = "Order through force. Very stable, unhappy, high taxes.",
		holdsElections = false,
		modifiers = {
			taxCeiling = 0.6,
			taxEfficiency = 1.1,
			happiness = -6,
			corruptionCreep = 1.2,
			researchBonus = 0.95,
			influenceBonus = 0.9,
			stability = 12,
		},
	},
	authoritarian = {
		id = "authoritarian",
		displayName = "Authoritarian State",
		description = "Total control: maximum taxes, high corruption, low joy.",
		holdsElections = false,
		modifiers = {
			taxCeiling = 0.8,
			taxEfficiency = 1.15,
			happiness = -8,
			corruptionCreep = 1.5,
			researchBonus = 0.9,
			influenceBonus = 0.85,
			stability = 10,
		},
	},
}

return Governments
