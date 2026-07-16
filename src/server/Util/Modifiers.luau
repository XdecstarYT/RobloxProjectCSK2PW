--!strict
--[[
	Util/Modifiers.luau
	Resolves a nation's active government, unlocked technologies, and enacted
	laws into a single normalised modifier table. Every service reads from this
	one resolver so the stacking rules live in exactly one place.

	Convention:
	  * `*Mult` fields are multipliers applied to a base value (1.0 = neutral).
	  * `*Flat` fields are added directly to a base value.
	  Government multipliers are the anchor; tech and law contributions stack on
	  top as additive fractions, e.g. taxEfficiencyMult = govTaxEff + Σ fractions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Governments = require(ReplicatedStorage.Nexus.Config.Governments)
local Laws = require(ReplicatedStorage.Nexus.Config.Laws)
local Technologies = require(ReplicatedStorage.Nexus.Config.Technologies)
local Types = require(ReplicatedStorage.Nexus.Types)

type Nation = Types.Nation

export type Resolved = {
	taxCeiling: number,
	taxEfficiencyMult: number,
	upkeepMult: number,
	happinessFlat: number,
	stabilityFlat: number,
	corruptionFlat: number,
	corruptionCreepMult: number,
	researchBonusMult: number,
	foodProductionMult: number,
	powerSupplyMult: number,
	materialCostMult: number,
	industryJobsMult: number,
	influenceBonusMult: number,
	baseHealthFlat: number,
}

local Modifiers = {}

function Modifiers.resolve(nation: Nation): Resolved
	local gov = Governments[nation.politics.government] or Governments.democracy
	local g = gov.modifiers

	local r: Resolved = {
		taxCeiling = g.taxCeiling,
		taxEfficiencyMult = g.taxEfficiency,
		upkeepMult = 1.0,
		happinessFlat = g.happiness,
		stabilityFlat = g.stability,
		corruptionFlat = 0,
		corruptionCreepMult = g.corruptionCreep,
		researchBonusMult = g.researchBonus,
		foodProductionMult = 1.0,
		powerSupplyMult = 1.0,
		materialCostMult = 1.0,
		industryJobsMult = 1.0,
		influenceBonusMult = g.influenceBonus,
		baseHealthFlat = 0,
	}

	-- Accumulate additive fractions from technologies.
	local techCreep = 0
	local techResearch = 0
	local techFood = 0
	local techInfluence = 0
	for techId in nation.research.unlocked do
		local def = Technologies[techId]
		if not def then
			continue
		end
		local m = def.modifiers
		r.taxEfficiencyMult += m.taxEfficiency or 0
		r.materialCostMult += m.materialCost or 0
		r.powerSupplyMult += m.powerSupply or 0
		r.industryJobsMult += m.industryJobs or 0
		r.baseHealthFlat += m.baseHealth or 0
		techCreep += m.corruptionCreep or 0
		techFood += m.foodProduction or 0
		techInfluence += m.influenceBonus or 0
	end

	-- Accumulate law contributions.
	local lawResearch = 0
	local lawFood = 0
	local lawUpkeep = 0
	for lawId, active in nation.politics.activeLaws do
		if not active then
			continue
		end
		local def = Laws[lawId]
		if not def then
			continue
		end
		local m = def.modifiers
		r.happinessFlat += m.happiness or 0
		r.stabilityFlat += m.stability or 0
		r.corruptionFlat += m.corruption or 0
		r.taxEfficiencyMult += m.taxEfficiency or 0
		lawResearch += m.researchBonus or 0
		lawFood += m.foodProduction or 0
		lawUpkeep += m.upkeep or 0
	end

	-- Each ally lifts influence generation; alliances are a diplomatic engine.
	local allyCount = 0
	if nation.diplomacy and nation.diplomacy.allies then
		for _, active in nation.diplomacy.allies do
			if active then
				allyCount += 1
			end
		end
	end

	r.corruptionCreepMult *= (1 + techCreep)
	r.researchBonusMult *= (1 + techResearch + lawResearch)
	r.foodProductionMult += techFood + lawFood
	r.influenceBonusMult *= (1 + techInfluence + allyCount * 0.05)
	r.upkeepMult += lawUpkeep

	return r
end

return Modifiers
