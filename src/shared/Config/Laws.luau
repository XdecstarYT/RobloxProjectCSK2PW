--!strict
--[[
	Config/Laws.luau
	Toggleable national policies. Each law is a trade-off applied while active,
	so a player crafts an identity by stacking laws that fit their strategy.
	Some laws require a government type or technology to enact.
]]

local Types = require(script.Parent.Parent.Types)

type GovernmentId = Types.GovernmentId

export type LawDef = {
	id: string,
	displayName: string,
	description: string,
	requiresTech: string?,
	forbiddenGovernments: { GovernmentId },
	modifiers: {
		happiness: number?,
		taxEfficiency: number?,
		corruption: number?,
		researchBonus: number?,
		foodProduction: number?,
		stability: number?,
		upkeep: number?, -- multiplier on all building upkeep
	},
}

local Laws: { [string]: LawDef } = {
	free_healthcare = {
		id = "free_healthcare",
		displayName = "Universal Healthcare",
		description = "+happiness and health, but building upkeep rises 8%.",
		requiresTech = "medicine_1",
		forbiddenGovernments = {},
		modifiers = { happiness = 5, upkeep = 0.08 },
	},
	free_education = {
		id = "free_education",
		displayName = "Free Education",
		description = "Boosts research output 15% at the cost of 6% upkeep.",
		requiresTech = nil,
		forbiddenGovernments = {},
		modifiers = { researchBonus = 0.15, upkeep = 0.06 },
	},
	anti_corruption = {
		id = "anti_corruption",
		displayName = "Anti-Corruption Bureau",
		description = "Sharply reduces corruption; slightly lowers stability.",
		requiresTech = "government_1",
		forbiddenGovernments = { "authoritarian" },
		modifiers = { corruption = -12, stability = -2 },
	},
	subsidised_farming = {
		id = "subsidised_farming",
		displayName = "Farm Subsidies",
		description = "+20% food production, funded by lower tax efficiency.",
		requiresTech = nil,
		forbiddenGovernments = {},
		modifiers = { foodProduction = 0.20, taxEfficiency = -0.05 },
	},
	martial_law = {
		id = "martial_law",
		displayName = "Martial Law",
		description = "Large stability gain, heavy happiness cost.",
		requiresTech = nil,
		forbiddenGovernments = { "democracy" },
		modifiers = { stability = 15, happiness = -10 },
	},
	press_freedom = {
		id = "press_freedom",
		displayName = "Press Freedom",
		description = "Happier, less corrupt citizens; a small stability risk.",
		requiresTech = nil,
		forbiddenGovernments = { "authoritarian", "military" },
		modifiers = { happiness = 4, corruption = -5, stability = -3 },
	},
}

return Laws
