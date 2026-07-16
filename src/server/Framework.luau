--!strict
--[[
	Framework.luau
	A tiny service locator with a two-phase lifecycle.

	Phase 1 (Init): every service constructs its own state. Services must NOT
	touch each other here — order is undefined.
	Phase 2 (Start): the simulation begins. By now every service is registered,
	so a service may freely `Framework.get("EconomyService")`.

	Services reference one another lazily through `Framework.get`, never via a
	top-level require, which keeps the dependency graph acyclic at load time.
]]

local Logger = require(game:GetService("ReplicatedStorage").Nexus.Logger)

local log = Logger.new("Framework")

export type Service = {
	Name: string,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[any]: any,
}

local Framework = {}
local services: { [string]: Service } = {}
local started = false

--- Register a service table. Its `Name` must be unique.
function Framework.register(service: Service): Service
	assert(not started, "cannot register after Framework.start()")
	assert(service.Name, "service is missing a Name")
	assert(not services[service.Name], "duplicate service: " .. service.Name)
	services[service.Name] = service
	return service
end

--- Retrieve a previously registered service, asserting it exists.
function Framework.get(name: string): any
	local service = services[name]
	if not service then
		error(("service %q is not registered"):format(name), 2)
	end
	return service
end

--- Run Init on every service, then Start on every service. Idempotent-guarded.
function Framework.start()
	assert(not started, "Framework already started")
	started = true

	for name, service in services do
		if service.Init then
			local ok, err = pcall(service.Init, service)
			if not ok then
				log:Error(("Init failed for %s: %s"):format(name, tostring(err)))
			end
		end
	end
	log:Info("all services initialised")

	for name, service in services do
		if service.Start then
			-- Start in its own thread so a long-running loop cannot block the
			-- rest of startup; each service owns its cadence.
			task.spawn(function()
				local ok, err = pcall(service.Start, service)
				if not ok then
					log:Error(("Start failed for %s: %s"):format(name, tostring(err)))
				end
			end)
		end
	end
	log:Info("all services started")
end

return Framework
