--!strict
--[[
	Services/ReplicationService.luau
	The only place server state reaches a client. Services never call Net
	directly for state; they mutate the authoritative nation and call
	`MarkDirty(player)`. This service batches dirty players and pushes a filtered,
	deep-copied snapshot at a fixed cadence, so a burst of building placements
	replicates once, not ten times.

	The client receives a read-only copy — it can never hold a live reference to
	server tables, and it is free to render the snapshot however it likes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local TableUtil = require(ReplicatedStorage.Nexus.TableUtil)
local Types = require(ReplicatedStorage.Nexus.Types)

type Nation = Types.Nation

local log = Logger.new("ReplicationService")

local ReplicationService = {
	Name = "ReplicationService",
}

ReplicationService._dirty = {} :: { [Player]: boolean }
-- Latest per-tick derived stats (flows the raw nation state does not store).
ReplicationService._stats = {} :: { [Player]: any }

local FLUSH_INTERVAL = 0.5

--- Mark a player's state as changed; it will be pushed on the next flush.
function ReplicationService:MarkDirty(player: Player)
	self._dirty[player] = true
end

--- Attach derived, per-tick statistics to a player's next snapshot.
function ReplicationService:SetStats(player: Player, stats: any)
	self._stats[player] = stats
end

function ReplicationService:_push(player: Player, nation: Nation)
	local snapshot = {
		nation = TableUtil.deepCopy(nation),
		stats = self._stats[player] or {},
		serverTime = os.time(),
	}
	Net.fireClient(player, NetRoutes.STATE_SYNC, snapshot)
end

--- Force an immediate push (used right after a profile loads).
function ReplicationService:PushNow(player: Player)
	local DataService = require(script.Parent.DataService)
	local nation = DataService:GetNation(player)
	if nation then
		self:_push(player, nation)
	end
	self._dirty[player] = nil
end

function ReplicationService:Start()
	local DataService = require(script.Parent.DataService)

	-- Send an immediate snapshot the moment a nation is ready.
	DataService.Loaded:Connect(function(player: Player)
		self:PushNow(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._dirty[player] = nil
		self._stats[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			for player in self._dirty do
				local nation = DataService:GetNation(player)
				if nation then
					self:_push(player, nation)
				end
				self._dirty[player] = nil
			end
		end
	end)

	log:Info("replication loop started")
end

return ReplicationService
