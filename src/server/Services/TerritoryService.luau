--!strict
--[[
	Services/TerritoryService.luau
	Authoritative ownership of the shared world map. Nations spend influence to
	claim regions; a region must be adjacent to one you already hold (your first
	claim is free of that rule). Owned regions grant their per-tick bonus (applied
	by the economy loops from the Regions config) and add to national power.

	`_owner` is the live source of truth for the map; each nation's persisted
	`territory.regions` mirrors it and is reconciled on load — regions taken by
	someone else while you were away are dropped ("use it or lose it").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Types = require(ReplicatedStorage.Nexus.Types)
local Regions = require(ReplicatedStorage.Nexus.Config.Regions)
local MilitaryUnits = require(ReplicatedStorage.Nexus.Config.MilitaryUnits)
local ServerSettings = require(ReplicatedStorage.Nexus.Config.ServerSettings)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)
local WorldService = require(script.Parent.WorldService)

type Nation = Types.Nation

local log = Logger.new("TerritoryService")

local TerritoryService = {
	Name = "TerritoryService",
}

TerritoryService._owner = {} :: { [string]: number }

-- ---- Helpers --------------------------------------------------------------

local function areAdjacent(a: string, b: string): boolean
	local ra, rb = Regions[a], Regions[b]
	if not ra or not rb then
		return false
	end
	return math.abs(ra.col - rb.col) + math.abs(ra.row - rb.row) == 1
end

function TerritoryService:_ownedByNation(nationId: number): { string }
	local owned = {}
	for regionId, owner in self._owner do
		if owner == nationId then
			table.insert(owned, regionId)
		end
	end
	return owned
end

local function listHas(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

local function removeFromList(list: { string }, value: string)
	local i = table.find(list, value)
	if i then
		table.remove(list, i)
	end
end

local function strengthOf(nation: Nation): number
	local total = 0
	for branch, def in MilitaryUnits do
		total += (nation.military[branch] or 0) * def.strength
	end
	return total
end

-- A successful annexation costs the attacker some of its forces.
local function applyLosses(nation: Nation)
	local best, bestBranch = 0, nil
	for branch in MilitaryUnits do
		local count = nation.military[branch] or 0
		if count > best then
			best, bestBranch = count, branch
		end
	end
	if bestBranch then
		nation.military[bestBranch] = math.max(0, best - (math.floor(best * 0.2) + 1))
	end
end

-- ---- Claiming -------------------------------------------------------------

--- Claim (or annex) a region for a nation. An unowned region is claimed with
--- influence; an AI-held adjacent region can be annexed by force when military
--- is enabled. Player-held regions are never takeable. Returns { success, ... }.
function TerritoryService:ClaimForNation(nationId: number, regionId: any): any
	local def = Regions[regionId]
	if not def then
		return { success = false, reason = "unknown_region" }
	end
	local nation, player = WorldService:GetNationById(nationId)
	if not nation then
		return { success = false, reason = "no_nation" }
	end

	local currentOwner = self._owner[regionId]
	if currentOwner == nationId then
		return { success = false, reason = "already_owned" }
	end

	local owned = self:_ownedByNation(nationId)
	local adjacent = #owned == 0
	for _, ownedId in owned do
		if areAdjacent(ownedId, regionId) then
			adjacent = true
			break
		end
	end

	local function grant(cost: number, annexed: boolean)
		nation.resources.influence -= cost
		if not listHas(nation.territory.regions, regionId) then
			table.insert(nation.territory.regions, regionId)
		end
		self._owner[regionId] = nationId
		if player then
			ReplicationService:MarkDirty(player)
			NotificationService:Send(
				player,
				"success",
				annexed and "Region annexed" or "Region claimed",
				def.displayName .. " is yours."
			)
		end
		self:Broadcast()
	end

	if currentOwner then
		-- Occupied. Only AI-held, adjacent regions can be taken, and only by force.
		if currentOwner >= 0 or not ServerSettings.militaryEnabled then
			return { success = false, reason = "occupied" }
		end
		if #owned == 0 or not adjacent then
			return { success = false, reason = "not_adjacent" }
		end
		local required = math.floor(10 + def.value * 8)
		if strengthOf(nation) < required then
			if player then
				NotificationService:Send(player, "warning", "Insufficient military", ("Need strength %d"):format(required))
			end
			return { success = false, reason = "need_military", required = required }
		end
		local cost = math.floor(def.cost * 1.5 + 0.5)
		if (nation.resources.influence or 0) < cost then
			return { success = false, reason = "insufficient_influence", cost = cost }
		end
		-- Take it: pay influence, lose some forces, strip it from the AI owner.
		local aiNation = select(1, WorldService:GetNationById(currentOwner))
		if aiNation then
			removeFromList(aiNation.territory.regions, regionId)
		end
		applyLosses(nation)
		grant(cost, true)
		return { success = true, cost = cost, annexed = true }
	end

	-- Unowned: a normal influence claim (first claim ignores adjacency).
	if #owned > 0 and not adjacent then
		return { success = false, reason = "not_adjacent" }
	end
	local cost = math.floor(def.cost * (1 + #owned * 0.4) + 0.5)
	if (nation.resources.influence or 0) < cost then
		if player then
			NotificationService:Send(player, "warning", "Not enough influence", ("Need %d influence"):format(cost))
		end
		return { success = false, reason = "insufficient_influence", cost = cost }
	end
	grant(cost, false)
	return { success = true, cost = cost }
end

-- ---- Replication ----------------------------------------------------------

function TerritoryService:Broadcast()
	local map = {}
	for regionId in Regions do
		local ownerId = self._owner[regionId]
		local ownerName = nil
		if ownerId then
			local nation = select(1, WorldService:GetNationById(ownerId))
			ownerName = nation and nation.name or nil
		end
		table.insert(map, { id = regionId, ownerId = ownerId, ownerName = ownerName })
	end
	Net.fireAllClients(NetRoutes.TERRITORY_SYNC, map)
end

-- ---- Persistence reconciliation -------------------------------------------

function TerritoryService:_onLoaded(player: Player, nation: Nation)
	local kept = {}
	for _, regionId in nation.territory.regions do
		if not Regions[regionId] then
			table.insert(kept, regionId) -- non-map markers like "capital"
		elseif self._owner[regionId] == nil then
			self._owner[regionId] = player.UserId
			table.insert(kept, regionId)
		elseif self._owner[regionId] == player.UserId then
			table.insert(kept, regionId)
		end
		-- else: taken by another nation while away -> dropped
	end
	nation.territory.regions = kept
	self:Broadcast()
end

function TerritoryService:_onLeaving(userId: number)
	local changed = false
	for regionId, owner in self._owner do
		if owner == userId then
			self._owner[regionId] = nil
			changed = true
		end
	end
	if changed then
		self:Broadcast()
	end
end

-- ---- Lifecycle ------------------------------------------------------------

function TerritoryService:Start()
	Net.handleRequest(NetRoutes.CLAIM_REGION, function(player, payload)
		if typeof(payload) ~= "table" then
			return { success = false, reason = "bad_request" }
		end
		return self:ClaimForNation(player.UserId, payload.regionId)
	end, { rate = 5, per = 1 })

	DataService.Loaded:Connect(function(player, profile)
		self:_onLoaded(player, profile.nation)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_onLeaving(player.UserId)
	end)

	task.spawn(function()
		while true do
			task.wait(6)
			pcall(function()
				self:Broadcast()
			end)
		end
	end)

	log:Info("territory service ready")
end

return TerritoryService
