--!strict
--[[
	init.client.luau
	Client bootstrap. Registers every controller with the ClientFramework, then
	runs the shared Init/Start lifecycle. Init order is chosen so the HUD's
	chrome exists before the panels that attach buttons to it; Framework still
	guarantees all Inits precede all Starts.

	This is the ONLY LocalScript — every other client file is a ModuleScript, and
	they are children of this script (Rojo turns the folder-with-init into this
	LocalScript), so we address them from `script`.
]]

local Players = game:GetService("Players")

local ClientFramework = require(script.ClientFramework)
local Controllers = script.Controllers

local ORDER = {
	"StateController",
	"WorldStateController",
	"AmbianceController",
	"NotificationController",
	"HudController",
	"WorldController",
	"BuildController",
	"PoliticsController",
	"ResearchController",
	"EconomyController",
	"DiplomacyController",
	"TerritoryController",
	"MilitaryController",
	"LeaderboardController",
}

for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	assert(module, "missing controller module: " .. name)
	ClientFramework.register(require(module))
end

ClientFramework.start()

print("[Nexus] client online for " .. Players.LocalPlayer.Name)
