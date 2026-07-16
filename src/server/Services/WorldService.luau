--!strict
--[[
	Services/WorldService.luau
	The registry that ties every nation — human or AI — into one world. It resolves
	a nation by id, ranks them into a leaderboard, and broadcasts a compact world
	directory that powers the diplomacy target list, the leaderboard panel and the
	territory ownership display.

	Id scheme: player nations use their positive Player.UserId; AI nations use
	negative ids and register themselves here (AIService calls RegisterAI), so this
	low-level service never has to depend on AIService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Types = require(ReplicatedStorage.Nexus.Types)

local DataService = require(script.Parent.DataService)

type Nation = Types.Nation

export type Entry = { id: number, nation: Nation, isAI: boolean, player: Player? }

local log = Logger.new("WorldService")

local WorldService = {
	Name = "WorldService",
}

WorldService._ai = {} :: { [number]: Nation }

-- Composite "power" used for ranking and AI decision-making.
function WorldService.powerScore(nation: Nation): number
	local techCount = 0
	for _, unlocked in nation.research.unlocked do
		if unlocked then
			techCount += 1
		end
	end
	local regionCount = #nation.territory.regions
	local mil = nation.military
	local strength = mil.army * 3 + mil.navy * 4 + mil.air * 5
	local allies = 0
	for _, a in nation.diplomacy.allies do
		if a then
			allies += 1
		end
	end
	return nation.economy.gdp * 0.4
		+ nation.population.total * 3
		+ nation.economy.treasury * 0.02
		+ techCount * 40
		+ regionCount * 80
		+ strength * 4
		+ allies * 30
end

--- AIService registers/updates its nations here.
function WorldService:RegisterAI(id: number, nation: Nation)
	self._ai[id] = nation
end

function WorldService:GetAINations(): { [number]: Nation }
	return self._ai
end

--- Resolve a nation by id. Returns (nation?, player?, isAI).
function WorldService:GetNationById(id: number): (Nation?, Player?, boolean)
	if id > 0 then
		local player = Players:GetPlayerByUserId(id)
		if player then
			return DataService:GetNation(player), player, false
		end
		return nil, nil, false
	end
	return self._ai[id], nil, true
end

--- Every live nation as an Entry list.
function WorldService:GetAllEntries(): { Entry }
	local entries: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local nation = DataService:GetNation(player)
		if nation then
			table.insert(entries, { id = player.UserId, nation = nation, isAI = false, player = player })
		end
	end
	for id, nation in self._ai do
		table.insert(entries, { id = id, nation = nation, isAI = true, player = nil })
	end
	return entries
end

--- Compact, replication-safe directory sorted by power (the leaderboard order).
function WorldService:BuildDirectory(): { any }
	local dir = {}
	for _, entry in self:GetAllEntries() do
		local n = entry.nation
		table.insert(dir, {
			id = entry.id,
			name = n.name,
			isAI = entry.isAI,
			government = n.politics.government,
			power = math.floor(WorldService.powerScore(n)),
			gdp = math.floor(n.economy.gdp),
			population = n.population.total,
			treasury = math.floor(n.economy.treasury),
			regions = #n.territory.regions,
			strength = n.military.army * 3 + n.military.navy * 4 + n.military.air * 5,
		})
	end
	table.sort(dir, function(a, b)
		return a.power > b.power
	end)
	for rank, row in dir do
		row.rank = rank
	end
	return dir
end

function WorldService:Broadcast()
	Net.fireAllClients(NetRoutes.WORLD_SYNC, self:BuildDirectory())
end

function WorldService:Start()
	task.spawn(function()
		while true do
			task.wait(4)
			local ok, err = pcall(function()
				self:Broadcast()
			end)
			if not ok then
				log:Warn("world broadcast failed: " .. tostring(err))
			end
		end
	end)
	log:Info("world registry online")
end

return WorldService
