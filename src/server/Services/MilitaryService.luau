--!strict
--[[
	Services/MilitaryService.luau
	The optional military layer: recruit and disband units. Gated behind
	ServerSettings.militaryEnabled so peaceful servers never see it. Units cost
	resources up front and money upkeep every tick (charged by EconomyService);
	their strength feeds power ranking and forceful expansion against AI regions
	(handled in TerritoryService). This service owns recruitment; combat is
	deliberately logistics-first and never targets other players.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local ResourceMath = require(ReplicatedStorage.Nexus.ResourceMath)
local MilitaryUnits = require(ReplicatedStorage.Nexus.Config.MilitaryUnits)
local ServerSettings = require(ReplicatedStorage.Nexus.Config.ServerSettings)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)

local MAX_BATCH = 100

local log = Logger.new("MilitaryService")

local MilitaryService = {
	Name = "MilitaryService",
}

function MilitaryService:_recruit(player: Player, payload: any): any
	if not ServerSettings.militaryEnabled then
		return { success = false, reason = "disabled" }
	end
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local def = MilitaryUnits[payload.branch]
	if not def then
		return { success = false, reason = "unknown_unit" }
	end
	local count = payload.count
	if typeof(count) ~= "number" or count ~= count or count < 1 then
		return { success = false, reason = "bad_count" }
	end
	count = math.min(math.floor(count), MAX_BATCH)

	if def.requiresTech and not nation.research.unlocked[def.requiresTech] then
		return { success = false, reason = "tech_locked" }
	end

	local cost = ResourceMath.scale(def.cost, count)
	if not ResourceMath.canAfford(nation.resources, cost) then
		NotificationService:Send(player, "warning", "Cannot afford recruitment")
		return { success = false, reason = "insufficient_resources" }
	end
	ResourceMath.spend(nation.resources, cost)
	nation.military[def.branch] += count
	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, "success", ("Recruited %d %s"):format(count, def.displayName))
	return { success = true }
end

function MilitaryService:_disband(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local def = MilitaryUnits[payload.branch]
	if not def then
		return { success = false, reason = "unknown_unit" }
	end
	local count = math.min(math.floor(tonumber(payload.count) or 0), nation.military[def.branch])
	if count < 1 then
		return { success = false, reason = "none_to_disband" }
	end
	nation.military[def.branch] -= count
	-- Partial refund for disbanding.
	ResourceMath.grant(nation.resources, ResourceMath.scale(def.cost, count * 0.3))
	ReplicationService:MarkDirty(player)
	return { success = true }
end

--- Total combat strength of a nation (also used by WorldService/TerritoryService).
function MilitaryService.strengthOf(nation): number
	local total = 0
	for branch, def in MilitaryUnits do
		total += (nation.military[branch] or 0) * def.strength
	end
	return total
end

function MilitaryService:Start()
	if not ServerSettings.militaryEnabled then
		log:Info("military disabled by server settings")
		return
	end
	Net.handleRequest(NetRoutes.RECRUIT_UNITS, function(player, payload)
		return self:_recruit(player, payload)
	end, { rate = 5, per = 1 })
	Net.handleRequest(NetRoutes.DISBAND_UNITS, function(player, payload)
		return self:_disband(player, payload)
	end, { rate = 5, per = 1 })
	log:Info("military service ready")
end

return MilitaryService
