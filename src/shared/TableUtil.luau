--!strict
--[[
	TableUtil.luau
	Small, dependency-free helpers used by the data and simulation layers.
]]

local TableUtil = {}

-- Recursive value copy. Used before mutating persisted state and before
-- replicating a snapshot to clients (so the client can never hold a live
-- reference into server-authoritative tables).
function TableUtil.deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value :: any do
		result[k] = TableUtil.deepCopy(v)
	end
	return (result :: any) :: T
end

-- Fill any missing keys in `target` from `template` without overwriting existing
-- values. This is how DataService reconciles an older save against the current
-- schema: new fields appear with their defaults, existing player data is kept.
function TableUtil.reconcile<T>(target: { [any]: any }, template: T): T
	if typeof(template) ~= "table" then
		return target :: any
	end
	for key, templateValue in template :: any do
		if target[key] == nil then
			target[key] = TableUtil.deepCopy(templateValue)
		elseif typeof(templateValue) == "table" and typeof(target[key]) == "table" then
			TableUtil.reconcile(target[key], templateValue)
		end
	end
	return target :: any
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Sum a numeric field across a dictionary of records.
function TableUtil.sumBy<T>(records: { [any]: T }, selector: (T) -> number): number
	local total = 0
	for _, record in records do
		total += selector(record)
	end
	return total
end

function TableUtil.shallowEqual(a: { [any]: any }, b: { [any]: any }): boolean
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in b do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

return TableUtil
