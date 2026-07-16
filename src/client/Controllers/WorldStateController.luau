--!strict
--[[
	Controllers/WorldStateController.luau
	Client store for world-scope data that isn't part of the player's own nation:
	the ranked directory of all nations (WORLD_SYNC) and the player's trade inbox
	(TRADE_INBOX). Diplomacy and leaderboard panels subscribe here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Signal = require(ReplicatedStorage.Nexus.Signal)

local WorldStateController = {
	Name = "WorldStateController",
	DirectoryChanged = Signal.new() :: any, -- fires (directory)
	InboxChanged = Signal.new() :: any, -- fires (inbox)
}

WorldStateController._directory = {} :: { any }
WorldStateController._inbox = { incoming = {}, outgoing = {} } :: any

function WorldStateController:GetDirectory(): { any }
	return self._directory
end

function WorldStateController:GetInbox(): any
	return self._inbox
end

function WorldStateController:Init()
	Net.onEvent(NetRoutes.WORLD_SYNC, function(list)
		if typeof(list) ~= "table" then
			return
		end
		self._directory = list
		self.DirectoryChanged:Fire(list)
	end)
	Net.onEvent(NetRoutes.TRADE_INBOX, function(data)
		if typeof(data) ~= "table" then
			return
		end
		self._inbox = { incoming = data.incoming or {}, outgoing = data.outgoing or {} }
		self.InboxChanged:Fire(self._inbox)
	end)
end

return WorldStateController
