--!strict
--[[
	Config/ServerSettings.luau
	Server-wide toggles a place owner can flip before shipping. Read by both the
	server (authority) and client (to hide disabled UI). Military is optional by
	design, and player-vs-player aggression is off by default so peaceful servers
	stay peaceful; expansion by force only ever targets AI regions.
]]

local ServerSettings = {
	militaryEnabled = true,
	pvpEnabled = false, -- reserved: forceful claims only target AI regions
	showStartingHints = true,
}

return ServerSettings
