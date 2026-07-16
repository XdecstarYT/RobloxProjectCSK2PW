--!strict
--[[
	Logger.luau
	Namespaced, level-filtered logging. Every subsystem creates its own logger
	via Logger.new("EconomyService") so output is greppable and can be muted per
	scope in production without touching call sites.
]]

local Logger = {}
Logger.__index = Logger

export type Level = "debug" | "info" | "warn" | "error"

local LEVEL_WEIGHT: { [Level]: number } = {
	debug = 10,
	info = 20,
	warn = 30,
	error = 40,
}

-- Raise this to "info" or "warn" in a shipped build to quiet the console.
local minLevel: Level = "debug"

export type Logger = {
	Debug: (self: Logger, ...any) -> (),
	Info: (self: Logger, ...any) -> (),
	Warn: (self: Logger, ...any) -> (),
	Error: (self: Logger, ...any) -> (),
}

function Logger.setMinLevel(level: Level)
	minLevel = level
end

local function format(scope: string, level: Level, ...: any): string
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	return ("[Nexus/%s][%s] %s"):format(scope, level:upper(), table.concat(parts, " "))
end

function Logger.new(scope: string): Logger
	local self = setmetatable({ _scope = scope }, Logger)
	return (self :: any) :: Logger
end

function Logger:_emit(level: Level, ...: any)
	if LEVEL_WEIGHT[level] < LEVEL_WEIGHT[minLevel] then
		return
	end
	local message = format(self._scope, level, ...)
	if level == "error" then
		warn(message) -- keep the traceback path but never `error()` from logging
	elseif level == "warn" then
		warn(message)
	else
		print(message)
	end
end

function Logger:Debug(...: any)
	self:_emit("debug", ...)
end

function Logger:Info(...: any)
	self:_emit("info", ...)
end

function Logger:Warn(...: any)
	self:_emit("warn", ...)
end

function Logger:Error(...: any)
	self:_emit("error", ...)
end

return Logger
