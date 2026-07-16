--!strict
--[[
	ResourceMath.luau
	Pure helpers for combining ResourceBags. The server uses these to mutate the
	authoritative treasury; the client uses the read-only ones (canAfford) to
	grey out unaffordable options. Keeping the affordability rule in one place
	guarantees the UI and the server never disagree about what a player can buy.
]]

local Types = require(script.Parent.Types)

type ResourceBag = Types.ResourceBag

local ResourceMath = {}

--- A fresh zeroed bag over every known resource.
function ResourceMath.zero(): ResourceBag
	return {
		money = 0,
		materials = 0,
		energy = 0,
		food = 0,
		research = 0,
		influence = 0,
	}
end

--- Non-mutating a + b.
function ResourceMath.add(a: ResourceBag, b: ResourceBag): ResourceBag
	local out = table.clone(a)
	for resource, amount in b do
		out[resource :: any] = (out[resource :: any] or 0) + amount
	end
	return out
end

--- Non-mutating a * scalar.
function ResourceMath.scale(a: ResourceBag, scalar: number): ResourceBag
	local out: ResourceBag = {}
	for resource, amount in a do
		out[resource :: any] = amount * scalar
	end
	return out
end

--- True when `wallet` covers every positive cost in `cost`.
function ResourceMath.canAfford(wallet: ResourceBag, cost: ResourceBag): boolean
	for resource, amount in cost do
		if amount > 0 and (wallet[resource :: any] or 0) < amount then
			return false
		end
	end
	return true
end

--- Mutating: subtract `cost` from `wallet` in place. Callers must have already
--- checked canAfford; this does not guard against going negative.
function ResourceMath.spend(wallet: ResourceBag, cost: ResourceBag)
	for resource, amount in cost do
		wallet[resource :: any] = (wallet[resource :: any] or 0) - amount
	end
end

--- Mutating: add `gain` to `wallet` in place.
function ResourceMath.grant(wallet: ResourceBag, gain: ResourceBag)
	for resource, amount in gain do
		wallet[resource :: any] = (wallet[resource :: any] or 0) + amount
	end
end

return ResourceMath
