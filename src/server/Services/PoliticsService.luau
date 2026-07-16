--!strict
--[[
	Services/PoliticsService.luau
	Government, laws and the public's verdict on your rule. Players set the tax
	rate, switch government type (a strategic pivot that costs influence), and
	enact/repeal laws. On its own slower cadence the service settles approval,
	stability and corruption from the state of the nation, and — for elective
	governments — holds elections you can lose.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local Types = require(ReplicatedStorage.Nexus.Types)
local Balance = require(ReplicatedStorage.Nexus.Config.Balance)
local Governments = require(ReplicatedStorage.Nexus.Config.Governments)
local Laws = require(ReplicatedStorage.Nexus.Config.Laws)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)
local Modifiers = require(script.Parent.Parent.Util.Modifiers)

type Nation = Types.Nation

local GOVERNMENT_SWITCH_COST = 100 -- influence

local log = Logger.new("PoliticsService")

local PoliticsService = {
	Name = "PoliticsService",
}

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

local function drift(current: number, target: number, rate: number): number
	return current + (target - current) * rate
end

-- ---- Handlers -------------------------------------------------------------

function PoliticsService:_setTax(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" or typeof(payload.rate) ~= "number" then
		return { success = false, reason = "bad_request" }
	end
	local gov = Governments[nation.politics.government]
	local ceiling = gov and gov.modifiers.taxCeiling or 0.5
	if payload.rate ~= payload.rate then -- NaN guard
		return { success = false, reason = "bad_request" }
	end
	nation.politics.taxRate = clamp(payload.rate, 0, ceiling)
	ReplicationService:MarkDirty(player)
	return { success = true, rate = nation.politics.taxRate }
end

function PoliticsService:_setGovernment(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local target = Governments[payload.government]
	if not target then
		return { success = false, reason = "unknown_government" }
	end
	if nation.politics.government == target.id then
		return { success = false, reason = "no_change" }
	end
	if (nation.resources.influence or 0) < GOVERNMENT_SWITCH_COST then
		NotificationService:Send(player, "warning", "Need influence to change government")
		return { success = false, reason = "insufficient_influence" }
	end

	nation.resources.influence -= GOVERNMENT_SWITCH_COST
	nation.politics.government = target.id

	-- Repeal any laws the new government forbids.
	for lawId, active in nation.politics.activeLaws do
		if active then
			local law = Laws[lawId]
			if law and table.find(law.forbiddenGovernments, target.id) then
				nation.politics.activeLaws[lawId] = nil
			end
		end
	end

	-- Reset the election clock for the new regime.
	if target.holdsElections then
		nation.politics.nextElection = os.time() + Balance.POLITICS.electionTermSeconds
	else
		nation.politics.nextElection = 0
	end

	ReplicationService:MarkDirty(player)
	NotificationService:Send(player, "success", "Government is now " .. target.displayName)
	return { success = true }
end

function PoliticsService:_toggleLaw(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local law = Laws[payload.id]
	if not law then
		return { success = false, reason = "unknown_law" }
	end
	local isActive = nation.politics.activeLaws[payload.id] == true
	if not isActive then
		-- Enacting: check requirements.
		if law.requiresTech and not nation.research.unlocked[law.requiresTech] then
			return { success = false, reason = "tech_locked" }
		end
		if table.find(law.forbiddenGovernments, nation.politics.government) then
			return { success = false, reason = "forbidden_government" }
		end
		nation.politics.activeLaws[payload.id] = true
		NotificationService:Send(player, "success", law.displayName .. " enacted")
	else
		nation.politics.activeLaws[payload.id] = nil
		NotificationService:Send(player, "info", law.displayName .. " repealed")
	end
	ReplicationService:MarkDirty(player)
	return { success = true, active = nation.politics.activeLaws[payload.id] == true }
end

function PoliticsService:_rename(player: Player, payload: any): any
	local nation = DataService:GetNation(player)
	if not nation or typeof(payload) ~= "table" or typeof(payload.name) ~= "string" then
		return { success = false, reason = "bad_request" }
	end
	-- Strip control characters and clamp length. (A shipped build should also
	-- route this through TextService:FilterStringAsync before display.)
	local cleaned = (payload.name:gsub("[%c]", "")):sub(1, 24)
	cleaned = cleaned:match("^%s*(.-)%s*$") or cleaned
	if #cleaned < 1 then
		return { success = false, reason = "empty_name" }
	end
	nation.name = cleaned
	ReplicationService:MarkDirty(player)
	return { success = true, name = cleaned }
end

-- ---- Slow political tick --------------------------------------------------

function PoliticsService:Tick(player: Player, nation: Nation)
	local resolved = Modifiers.resolve(nation)
	local pol = nation.politics
	local pop = nation.population

	-- Corruption creeps upward; strong institutions and laws hold it back.
	pol.corruption += Balance.POLITICS.corruptionCreep * resolved.corruptionCreepMult
	pol.corruption += resolved.corruptionFlat * 0.05
	pol.corruption = clamp(pol.corruption, 0, 100)

	-- Approval follows public happiness, the budget balance and unrest.
	local net = nation.economy.lastTickIncome - nation.economy.lastTickExpense
	local approvalTarget = clamp(
		pop.happiness * 0.6 + (net >= 0 and 10 or -12) + 20 - pop.unrest * 0.3,
		0,
		100
	)
	pol.approval = clamp(drift(pol.approval, approvalTarget, Balance.POLITICS.approvalDrift), 0, 100)

	-- Stability blends approval, unrest, corruption and government backbone.
	local stabilityTarget = clamp(
		50 + resolved.stabilityFlat + (pol.approval - 50) * 0.5 - pop.unrest * 0.5 - pol.corruption * 0.2,
		0,
		100
	)
	pol.stability = clamp(drift(pol.stability, stabilityTarget, 0.2), 0, 100)

	if pol.stability < Balance.POLITICS.crisisStabilityThreshold then
		NotificationService:Send(player, "error", "Government unstable", "Address unrest before it boils over.")
	end

	-- Elections.
	local gov = Governments[pol.government]
	if gov and gov.holdsElections then
		if pol.nextElection == 0 then
			pol.nextElection = os.time() + Balance.POLITICS.electionTermSeconds
		elseif os.time() >= pol.nextElection then
			if pol.approval >= 50 then
				NotificationService:Send(player, "success", "Election won", "The people return you to power.")
				pol.stability = clamp(pol.stability + 5, 0, 100)
			else
				NotificationService:Send(player, "warning", "Election lost", "A rocky term ahead — approval reset.")
				pol.approval = clamp(pol.approval + 15, 0, 100)
				pol.stability = clamp(pol.stability - 10, 0, 100)
			end
			pol.nextElection = os.time() + Balance.POLITICS.electionTermSeconds
		end
	end

	ReplicationService:MarkDirty(player)
end

function PoliticsService:Start()
	local Constants = require(ReplicatedStorage.Nexus.Constants)

	Net.handleRequest(NetRoutes.SET_TAX_RATE, function(player, payload)
		return self:_setTax(player, payload)
	end, { rate = 5, per = 1 })
	Net.handleRequest(NetRoutes.SET_GOVERNMENT, function(player, payload)
		return self:_setGovernment(player, payload)
	end, { rate = 2, per = 1 })
	Net.handleRequest(NetRoutes.TOGGLE_LAW, function(player, payload)
		return self:_toggleLaw(player, payload)
	end, { rate = 5, per = 1 })
	Net.handleRequest(NetRoutes.RENAME_NATION, function(player, payload)
		return self:_rename(player, payload)
	end, { rate = 2, per = 1 })

	task.spawn(function()
		while true do
			task.wait(Constants.POLITICS_TICK)
			DataService:ForEachNation(function(player, nation)
				local ok, err = pcall(function()
					self:Tick(player, nation)
				end)
				if not ok then
					log:Error(("politics tick failed for %s: %s"):format(player.Name, tostring(err)))
				end
			end)
		end
	end)

	log:Info("politics handlers + tick ready")
end

return PoliticsService
