--!strict
--[[
	ClientFramework.luau
	The client mirror of the server Framework: a controller registry with the
	same two-phase Init/Start lifecycle, so UI controllers can reference each
	other lazily without load-order headaches.
]]

local Logger = require(game:GetService("ReplicatedStorage").Nexus.Logger)

local log = Logger.new("ClientFramework")

export type Controller = {
	Name: string,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	[any]: any,
}

local ClientFramework = {}
local controllers: { [string]: Controller } = {}
local started = false

function ClientFramework.register(controller: Controller): Controller
	assert(not started, "cannot register after start")
	assert(controller.Name, "controller missing Name")
	assert(not controllers[controller.Name], "duplicate controller: " .. controller.Name)
	controllers[controller.Name] = controller
	return controller
end

function ClientFramework.get(name: string): any
	local controller = controllers[name]
	if not controller then
		error(("controller %q not registered"):format(name), 2)
	end
	return controller
end

function ClientFramework.start()
	assert(not started, "already started")
	started = true

	for name, controller in controllers do
		if controller.Init then
			local ok, err = pcall(controller.Init, controller)
			if not ok then
				log:Error(("Init failed for %s: %s"):format(name, tostring(err)))
			end
		end
	end
	for name, controller in controllers do
		if controller.Start then
			task.spawn(function()
				local ok, err = pcall(controller.Start, controller)
				if not ok then
					log:Error(("Start failed for %s: %s"):format(name, tostring(err)))
				end
			end)
		end
	end
	log:Info("controllers started")
end

return ClientFramework
