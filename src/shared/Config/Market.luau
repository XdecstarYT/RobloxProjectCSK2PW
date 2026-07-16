--!strict
--[[
	Config/Market.luau
	Tuning for the global commodity market. Prices are money-per-unit and move
	each market tick from three forces: mean-reversion toward `base`, random
	volatility, and net player demand (buys push up, sells push down). A small
	spread makes the market maker's buy price higher than its sell price, so you
	can't arbitrage instantly.

	Money is the currency and energy is a flow, so neither is marketable; the four
	stockpiled resources are.
]]

local Market = {}

Market.tick = 6 -- seconds between price updates
Market.spread = 0.03 -- buy at +3%, sell at -3%
Market.meanReversion = 0.05 -- pull toward base each tick
Market.impact = 0.0006 -- price move per unit of net demand
Market.demandDecay = 0.5 -- how fast demand pressure fades
Market.floorFactor = 0.4 -- price never below base * this
Market.ceilFactor = 2.5 -- ...nor above base * this

export type Commodity = { base: number, volatility: number }

Market.resources = {
	materials = { base = 8, volatility = 0.06 },
	food = { base = 3, volatility = 0.05 },
	research = { base = 16, volatility = 0.09 },
	influence = { base = 13, volatility = 0.08 },
} :: { [string]: Commodity }

-- Stable display order.
Market.order = { "materials", "food", "research", "influence" }

return Market
