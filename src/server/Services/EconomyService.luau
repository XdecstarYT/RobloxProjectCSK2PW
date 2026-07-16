--!strict
--[[
	Services/EconomyService.luau
	The master simulation tick. Every ECONOMY_TICK it walks each live nation and,
	in a fixed order, resolves modifiers, aggregates the city, computes finance,
	moves resources, and hands a shared "frame" of derived numbers to the citizen
	and research simulations. Politics runs on its own slower cadence.

	All money is authoritative here. `nation.resources.money` is the single
	treasury; deficits become debt (money never goes negative), surpluses slowly
	repay debt. Everything the HUD shows as a flow is packaged into `frame` and
	handed to ReplicationService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Logger = require(ReplicatedStorage.Nexus.Logger)
local Types = require(ReplicatedStorage.Nexus.Types)
local Balance = require(ReplicatedStorage.Nexus.Config.Balance)

local CityService = require(script.Parent.CityService)
local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)
local Modifiers = require(script.Parent.Parent.Util.Modifiers)

type Nation = Types.Nation

local log = Logger.new("EconomyService")

local EconomyService = {
	Name = "EconomyService",
}

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- Corruption erodes tax efficiency, but never below half.
local function corruptionFactor(corruption: number): number
	return clamp(1 - corruption / 200, 0.5, 1)
end

--- Run one economic tick for a single nation. Returns the derived `frame` so
--- other simulations (and replication) can reuse the same numbers.
function EconomyService:Tick(nation: Nation): any
	local eco = Balance.ECONOMY
	local resolved = Modifiers.resolve(nation)
	local stats = CityService:ComputeStats(nation, resolved)

	-- Employment: a fraction of the population is working-age.
	local workforce = math.floor(nation.population.total * Balance.CITIZENS.participation)
	local employed = math.min(math.floor(stats.jobs), workforce)
	nation.population.employed = employed
	local unemployment = workforce > 0 and (workforce - employed) / workforce or 0

	-- GDP and taxation. Labour income is taxed; state enterprises pay directly.
	local laborGdp = employed * eco.gdpPerWorker
	local enterpriseIncome = stats.production.money
	local gdp = laborGdp + enterpriseIncome
	local taxRevenue = laborGdp
		* nation.politics.taxRate
		* resolved.taxEfficiencyMult
		* eco.taxEfficiency
		* corruptionFactor(nation.politics.corruption)
	local income = taxRevenue + enterpriseIncome

	-- Materials: mines add, factories consume. A shortfall means we could not
	-- fully maintain the city this tick.
	local materialsFlow = stats.production.materials - stats.upkeep.materials
	local res = nation.resources
	local maintainedMaterials = true
	res.materials += materialsFlow
	if res.materials < 0 then
		maintainedMaterials = false
		res.materials = 0
	end

	-- Debt interest and money-denominated upkeep.
	local interest = nation.economy.debt > 0
			and nation.economy.debt * (nation.economy.interestRate / 100) / eco.ticksPerYear
		or 0
	local expense = stats.upkeep.money + interest

	res.money += income
	res.money -= expense
	local maintainedMoney = true
	if res.money < 0 then
		-- Deficit is financed by borrowing.
		maintainedMoney = false
		nation.economy.debt += -res.money
		res.money = 0
	elseif nation.economy.debt > 0 then
		-- Repay a slice of the debt out of any surplus.
		local paydown = math.min(res.money * eco.debtRepayFraction, nation.economy.debt)
		res.money -= paydown
		nation.economy.debt -= paydown
	end

	-- Food: production feeds the population; a shortfall is reported for unrest.
	local consumption = nation.population.total * eco.foodPerCapita
	res.food += stats.production.food - consumption
	local foodShortage = 0
	if res.food < 0 then
		foodShortage = -res.food
		res.food = 0
	end

	-- Research and influence accumulate as resources; energy shows the net flow.
	res.research += stats.production.research
	res.influence += stats.production.influence
	res.energy = stats.powerNet

	-- Inflation drifts toward target under money-supply pressure.
	local pressure = (income - expense) / math.max(gdp, 1)
	nation.economy.inflation += (eco.inflationTarget - nation.economy.inflation) * eco.inflationDrift
		+ pressure * eco.inflationDrift
	nation.economy.inflation = clamp(nation.economy.inflation, -5, 30)

	-- Update the economy mirror + rolling GDP history for graphs.
	nation.economy.gdp = gdp
	nation.economy.treasury = res.money
	nation.economy.lastTickIncome = income
	nation.economy.lastTickExpense = expense
	nation.economy.interestRate = eco.baseInterestRate + nation.economy.inflation * 0.5
	local history = nation.economy.gdpHistory
	table.insert(history, gdp)
	while #history > Constants.GDP_HISTORY_LENGTH do
		table.remove(history, 1)
	end

	local maintained = maintainedMoney and maintainedMaterials

	return {
		stats = stats,
		resolved = resolved,
		gdp = gdp,
		income = income,
		expense = expense,
		net = income - expense,
		taxRevenue = taxRevenue,
		enterpriseIncome = enterpriseIncome,
		employed = employed,
		workforce = workforce,
		unemployment = unemployment,
		foodShortage = foodShortage,
		maintained = maintained,
		debt = nation.economy.debt,
		inflation = nation.economy.inflation,
	}
end

function EconomyService:Start()
	local CitizenService = require(script.Parent.CitizenService)
	local ResearchService = require(script.Parent.ResearchService)

	task.spawn(function()
		while true do
			task.wait(Constants.ECONOMY_TICK)
			DataService:ForEachNation(function(player, nation)
				local ok, frame = pcall(function()
					return self:Tick(nation)
				end)
				if not ok then
					log:Error(("economy tick failed for %s: %s"):format(player.Name, tostring(frame)))
					return
				end

				-- Downstream simulations reuse this tick's derived numbers.
				pcall(function()
					CitizenService:Tick(nation, frame)
				end)
				pcall(function()
					ResearchService:Tick(player, nation, frame)
				end)
				CityService:TickCondition(nation, frame.maintained)

				if frame.foodShortage > 5 then
					NotificationService:Send(player, "warning", "Food shortage", "Citizens are going hungry.")
				end
				if frame.stats.powerNet < 0 then
					NotificationService:Send(player, "warning", "Power shortage", "Build more power plants.")
				end

				-- Package HUD-facing derived stats and schedule a snapshot.
				ReplicationService:SetStats(player, {
					gdp = frame.gdp,
					income = frame.income,
					expense = frame.expense,
					net = frame.net,
					employed = frame.employed,
					workforce = frame.workforce,
					unemployment = frame.unemployment,
					powerNet = frame.stats.powerNet,
					powerSupply = frame.stats.powerSupply,
					powerDraw = frame.stats.powerDraw,
					jobs = frame.stats.jobs,
					housing = frame.stats.housing,
					buildingCount = frame.stats.buildingCount,
					debt = frame.debt,
					inflation = frame.inflation,
				})
				ReplicationService:MarkDirty(player)
			end)
		end
	end)

	log:Info("economy simulation running")
end

return EconomyService
