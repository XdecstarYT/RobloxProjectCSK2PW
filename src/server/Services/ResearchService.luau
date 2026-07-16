--!strict
--[[
	Services/ResearchService.luau
	Drives the technology tree. Research accumulates as the `research` resource
	pool (from labs plus passive output of an educated populace) and is spent into
	whichever technology the player has selected. Completing a tech flips a flag
	the modifier resolver reads, so the effect is applied everywhere at once.

	The prerequisite DAG is enforced here: a client can never start a tech whose
	requirements are not already unlocked, no matter what it sends.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Types = require(ReplicatedStorage.Nexus.Types)
local Balance = require(ReplicatedStorage.Nexus.Config.Balance)
local Technologies = require(ReplicatedStorage.Nexus.Config.Technologies)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)

type Nation = Types.Nation

local log = Logger.new("ResearchService")

local ResearchService = {
	Name = "ResearchService",
}

--- Are every prerequisite of `techId` already unlocked?
local function prereqsMet(nation: Nation, def: Types.TechDef): boolean
	for _, requirement in def.requires do
		if not nation.research.unlocked[requirement] then
			return false
		end
	end
	return true
end

function ResearchService:Tick(player: Player, nation: Nation, _frame: any)
	local r = nation.research

	-- Passive research from an educated population.
	local passive = nation.population.education * Balance.RESEARCH.passivePerEducation
	nation.resources.research += passive * Balance.RESEARCH.pointConversion

	if not r.current then
		return
	end
	local def = Technologies[r.current]
	if not def then
		r.current = nil
		return
	end

	-- Spend from the research pool into the active tech's progress.
	local need = def.cost - r.progress
	local spend = math.min(nation.resources.research, need)
	if spend > 0 then
		r.progress += spend
		nation.resources.research -= spend
	end

	if r.progress >= def.cost then
		r.unlocked[r.current] = true
		local completed = def.displayName
		r.current = nil
		r.progress = 0
		NotificationService:Send(player, "success", "Research complete", completed .. " unlocked.")
		ReplicationService:MarkDirty(player)
	end
end

function ResearchService:_start(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local id = payload.id
	local def = Technologies[id]
	if not def then
		return { success = false, reason = "unknown_tech" }
	end
	if nation.research.unlocked[id] then
		return { success = false, reason = "already_unlocked" }
	end
	if not prereqsMet(nation, def) then
		return { success = false, reason = "prereqs_unmet" }
	end

	-- Switching target forfeits progress on the previous one.
	if nation.research.current ~= id then
		nation.research.current = id
		nation.research.progress = 0
	end
	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, "info", "Researching " .. def.displayName)
	return { success = true }
end

function ResearchService:Start()
	Net.handleRequest(NetRoutes.START_RESEARCH, function(player, payload)
		return self:_start(player, payload)
	end, { rate = 5, per = 1 })
	log:Info("research handlers ready")
end

return ResearchService
