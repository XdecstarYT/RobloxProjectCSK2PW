--!strict
--[[
	UI/Format.luau
	Number/text formatting shared by every panel, so "12.3k" and "+4.5%" look the
	same everywhere.
]]

local Format = {}

--- Abbreviate a number: 1500 -> "1.5k", 2_300_000 -> "2.3M".
function Format.abbrev(n: number): string
	local abs = math.abs(n)
	local sign = n < 0 and "-" or ""
	if abs >= 1e9 then
		return ("%s%.2fB"):format(sign, abs / 1e9)
	elseif abs >= 1e6 then
		return ("%s%.2fM"):format(sign, abs / 1e6)
	elseif abs >= 1e3 then
		return ("%s%.1fk"):format(sign, abs / 1e3)
	end
	return ("%s%d"):format(sign, math.floor(abs + 0.5))
end

--- A signed flow value, e.g. "+120" or "-45".
function Format.signed(n: number): string
	local prefix = n >= 0 and "+" or ""
	return prefix .. Format.abbrev(n)
end

function Format.percent(fraction: number): string
	return ("%d%%"):format(math.floor(fraction * 100 + 0.5))
end

function Format.round(n: number): string
	return tostring(math.floor(n + 0.5))
end

return Format
