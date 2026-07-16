--!strict
--[[
	Services/MarketService.luau
	A living global commodity market. Prices update every market tick from
	mean-reversion, volatility and net player demand, then broadcast to all
	clients. Players buy resources with money (pushing the price up) or sell them
	for money (pushing it down). A spread separates buy/sell prices so instant
	round-trips lose value.

	Authoritative and exploit-safe: amounts are validated and bounded, buys check
	money, sells check the actual stockpile, and money never goes negative.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Types = require(ReplicatedStorage.Nexus.Types)
local Market = require(ReplicatedStorage.Nexus.Config.Market)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)

type Nation = Types.Nation

local MAX_AMOUNT = 100000

local log = Logger.new("MarketService")

local MarketService = {
	Name = "MarketService",
}

MarketService._price = {} :: { [string]: number }
MarketService._prev = {} :: { [string]: number }
MarketService._demand = {} :: { [string]: number }

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- ---- Price simulation -----------------------------------------------------

function MarketService:_tickPrices()
	for res, def in Market.resources do
		local price = self._price[res]
		local base = def.base
		local noise = (math.random() * 2 - 1) * def.volatility * base
		local demandDelta = self._demand[res] * base * Market.impact
		local next = price + (base - price) * Market.meanReversion + noise + demandDelta
		next = clamp(next, base * Market.floorFactor, base * Market.ceilFactor)

		self._prev[res] = price
		self._price[res] = next
		self._demand[res] *= Market.demandDecay
	end
end

function MarketService:Broadcast()
	local rows = {}
	for _, res in Market.order do
		table.insert(rows, {
			id = res,
			price = self._price[res],
			prev = self._prev[res],
			base = Market.resources[res].base,
		})
	end
	Net.fireAllClients(NetRoutes.MARKET_SYNC, rows)
end

--- Current mid price for a resource (used by other systems/AI).
function MarketService:PriceOf(res: string): number?
	return self._price[res]
end

-- ---- Trading --------------------------------------------------------------

function MarketService:_buy(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local res = payload.resource
	if not Market.resources[res] then
		return { success = false, reason = "not_traded" }
	end
	local amount = payload.amount
	if typeof(amount) ~= "number" or amount ~= amount or amount < 1 then
		return { success = false, reason = "bad_amount" }
	end
	amount = math.min(math.floor(amount), MAX_AMOUNT)

	local unit = self._price[res] * (1 + Market.spread)
	local cost = math.ceil(amount * unit)
	if (nation.resources.money or 0) < cost then
		NotificationService:Send(player, "warning", "Cannot afford purchase")
		return { success = false, reason = "insufficient_money" }
	end
	nation.resources.money -= cost
	nation.resources[res] = (nation.resources[res] or 0) + amount
	self._demand[res] += amount
	ReplicationService:MarkDirty(player)
	return { success = true, spent = cost }
end

function MarketService:_sell(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local res = payload.resource
	if not Market.resources[res] then
		return { success = false, reason = "not_traded" }
	end
	local amount = payload.amount
	if typeof(amount) ~= "number" or amount ~= amount or amount < 1 then
		return { success = false, reason = "bad_amount" }
	end
	amount = math.min(math.floor(amount), MAX_AMOUNT)
	if (nation.resources[res] or 0) < amount then
		return { success = false, reason = "insufficient_stock" }
	end

	local unit = self._price[res] * (1 - Market.spread)
	local revenue = math.floor(amount * unit)
	nation.resources[res] -= amount
	nation.resources.money += revenue
	self._demand[res] -= amount
	ReplicationService:MarkDirty(player)
	return { success = true, earned = revenue }
end

-- ---- Lifecycle ------------------------------------------------------------

function MarketService:Start()
	for res, def in Market.resources do
		self._price[res] = def.base
		self._prev[res] = def.base
		self._demand[res] = 0
	end

	Net.handleRequest(NetRoutes.MARKET_BUY, function(player, payload)
		return self:_buy(player, payload)
	end, { rate = 8, per = 1 })
	Net.handleRequest(NetRoutes.MARKET_SELL, function(player, payload)
		return self:_sell(player, payload)
	end, { rate = 8, per = 1 })

	DataService.Loaded:Connect(function()
		self:Broadcast()
	end)

	task.spawn(function()
		while true do
			task.wait(Market.tick)
			self:_tickPrices()
			self:Broadcast()
		end
	end)

	log:Info("market service ready")
end

return MarketService
