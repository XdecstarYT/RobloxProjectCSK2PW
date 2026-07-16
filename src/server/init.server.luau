--!strict
--[[
	init.server.luau
	Server bootstrap. Requires every service, registers it with the Framework,
	then runs the two-phase Init/Start lifecycle. Order of registration does not
	matter — services reference each other lazily, and Framework guarantees all
	Inits run before any Start.

	This is the ONLY server Script; everything else is a ModuleScript, which keeps
	the execution model explicit and testable.
]]

-- Framework and Services are children of this script (Rojo turns the
-- folder-with-init into this Script), so we address them from `script`.
local Framework = require(script.Framework)
local Services = script.Services

-- Foundational services first (data, transport), then simulation, then I/O.
local ORDER = {
	"DataService",
	"ReplicationService",
	"NotificationService",
	"WorldService",
	"CityService",
	"CitizenService",
	"EconomyService",
	"ResearchService",
	"PoliticsService",
	"DiplomacyService",
	"TerritoryService",
	"MilitaryService",
	"AIService",
	"EventService",
	"OnboardingService",
}

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module, "missing service module: " .. name)
	Framework.register(require(module))
end

Framework.start()

print("[Nexus] server online — Project Nexus nation simulator")
