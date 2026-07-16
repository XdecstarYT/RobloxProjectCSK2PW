--!strict
--[[
	Controllers/StateController.luau
	The client's single source of truth for replicated nation state. It listens
	for STATE_SYNC snapshots, stores the latest, and fires a Changed signal that
	every panel subscribes to. No other controller talks to the sync route
	directly, so there is exactly one place the UI's data model updates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Signal = require(ReplicatedStorage.Nexus.Signal)
local Types = require(ReplicatedStorage.Nexus.Types)

type Nation = Types.Nation

local log = Logger.new("StateController")

local StateController = {
	Name = "StateController",
	Changed = Signal.new() :: any, -- fires (snapshot)
}

StateController._snapshot = nil :: any

function StateController:GetSnapshot(): any
	return self._snapshot
end

function StateController:GetNation(): Nation?
	return self._snapshot and self._snapshot.nation or nil
end

function StateController:GetStats(): any
	return self._snapshot and self._snapshot.stats or {}
end

--- True once the first snapshot has arrived (used to gate UI construction).
function StateController:IsReady(): boolean
	return self._snapshot ~= nil
end

function StateController:Init()
	Net.onEvent(NetRoutes.STATE_SYNC, function(snapshot)
		if typeof(snapshot) ~= "table" or typeof(snapshot.nation) ~= "table" then
			return
		end
		local first = self._snapshot == nil
		self._snapshot = snapshot
		self.Changed:Fire(snapshot)
		if first then
			log:Info("received first nation snapshot")
		end
	end)
end

return StateController
