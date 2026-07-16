--!strict
--[[
	Util/Validation.luau
	Server-side guards for untrusted client payloads. Every request handler runs
	its arguments through these before touching authoritative state. The rule:
	assume the payload was crafted by an exploiter, and prove each field valid.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)

local Validation = {}

function Validation.isTable(v: any): boolean
	return typeof(v) == "table"
end

function Validation.isString(v: any, maxLen: number?): boolean
	return typeof(v) == "string" and #v <= (maxLen or 256)
end

function Validation.isInteger(v: any): boolean
	return typeof(v) == "number" and v == v and v % 1 == 0 and v ~= math.huge and v ~= -math.huge
end

--- A grid coordinate must be an integer inside [0, GRID_SIZE).
function Validation.isGridCoord(v: any): boolean
	return Validation.isInteger(v) and v >= 0 and v < Constants.GRID_SIZE
end

--- Rotation is restricted to the four cardinal orientations.
function Validation.isRotation(v: any): boolean
	return v == 0 or v == 90 or v == 180 or v == 270
end

--- Validate a `{ x, z }` position payload; returns cleaned ints or nil.
function Validation.readPosition(payload: any): ({ x: number, z: number })?
	if not Validation.isTable(payload) then
		return nil
	end
	local x, z = payload.x, payload.z
	if Validation.isGridCoord(x) and Validation.isGridCoord(z) then
		return { x = x, z = z }
	end
	return nil
end

return Validation
