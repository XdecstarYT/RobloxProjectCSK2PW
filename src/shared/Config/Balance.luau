--!strict
--[[
	Config/Balance.luau
	Every tunable number that shapes the feel of the game. Isolated from code so
	an economy designer can rebalance without reading a single service.
]]

local Balance = {}

-- Starting state for a brand-new nation.
Balance.START = {
	resources = {
		money = 25000,
		materials = 500,
		energy = 0,
		food = 300,
		research = 0,
		influence = 50,
	},
	population = 20,
	treasury = 25000,
	taxRate = 0.15,
}

-- Economy tuning.
Balance.ECONOMY = {
	-- Each employed citizen contributes this much raw output to GDP per tick.
	gdpPerWorker = 12,
	-- Tax revenue = gdp * taxRate * this efficiency (corruption erodes it).
	taxEfficiency = 1.0,
	-- Above this tax rate, happiness starts to fall each politics tick.
	taxHappinessThreshold = 0.35,
	-- Debt accrues interest each economy tick at interestRate / ticksPerYear.
	baseInterestRate = 4.0, -- percent, annual
	ticksPerYear = 365,
	-- Inflation drifts toward this target based on money-supply pressure.
	inflationTarget = 2.0,
	inflationDrift = 0.02,
	-- Bankruptcy: treasury below this triggers emergency measures.
	bankruptcyFloor = -50000,
	-- Food shortfall converts to unrest at this rate.
	starvationUnrest = 0.5,
	-- Food consumed per citizen per economy tick.
	foodPerCapita = 0.35,
	-- Fraction of a surplus applied to debt repayment each tick.
	debtRepayFraction = 0.10,
}

-- Population / citizen tuning.
Balance.CITIZENS = {
	-- Baseline happiness with no buildings and moderate taxes.
	baseHappiness = 55,
	-- Population grows/shrinks toward capacity by this fraction per citizen tick.
	growthRate = 0.03,
	-- Happiness needed to attract new residents; below it, people leave.
	migrationHappiness = 50,
	-- Each unit of housing capacity supports this many citizens.
	housingMultiplier = 1.0,
	-- Fraction of the population that is working-age and seeking work.
	participation = 0.6,
	-- Unemployment above this fraction erodes happiness.
	unemploymentTolerance = 0.15,
	-- Education and health each nudge happiness toward their own value.
	serviceInfluence = 0.15,
}

-- Politics tuning.
Balance.POLITICS = {
	-- Approval drifts toward a target derived from happiness & economy.
	approvalDrift = 0.1,
	-- Stability = weighted blend; below this, crises can fire.
	crisisStabilityThreshold = 35,
	-- Corruption naturally creeps up; anti-corruption laws push it down.
	corruptionCreep = 0.05,
	-- Term length in seconds of real playtime for elective governments.
	electionTermSeconds = 60 * 20,
}

-- Research tuning.
Balance.RESEARCH = {
	-- Research buildings convert their output into points at this rate.
	pointConversion = 1.0,
	-- Flat passive research from an educated populace.
	passivePerEducation = 0.05,
}

-- Construction tuning.
Balance.CONSTRUCTION = {
	-- Refund fraction when a player demolishes a building.
	demolishRefund = 0.4,
	-- Condition lost per economy tick; maintenance offsets it.
	decayPerTick = 0.002,
	-- Below this condition a building goes offline until repaired.
	offlineCondition = 0.25,
	-- Upgrade cost multiplier growth is defined per-building; this is the cap.
	maxLevel = 5,
}

return Balance
