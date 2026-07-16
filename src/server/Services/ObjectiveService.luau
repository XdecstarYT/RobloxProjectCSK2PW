--!strict
--[[
	Services/ObjectiveService.luau
	Evaluates milestone objectives for each player's nation and grants a one-time
	reward the moment one is met. Objectives give the game direction; completion
	is persisted in nation.objectives so it survives rejoins and never pays twice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local ResourceMath = require(ReplicatedStorage.Nexus.ResourceMath)
local Objectives = require(ReplicatedStorage.Nexus.Config.Objectives)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)

local log = Logger.new("ObjectiveService")

local ObjectiveService = {
	Name = "ObjectiveService",
}

local function rewardText(reward): string
	local parts = {}
	for res, amount in reward do
		table.insert(parts, ("+%d %s"):format(amount, res))
	end
	return table.concat(parts, ", ")
end

function ObjectiveService:Evaluate(player: Player, nation)
	for _, obj in Objectives do
		if not nation.objectives[obj.id] then
			local ok, met = pcall(obj.check, nation)
			if ok and met then
				nation.objectives[obj.id] = true
				ResourceMath.grant(nation.resources, obj.reward)
				NotificationService:Send(
					player,
					"success",
					"🎯 " .. obj.title,
					obj.desc .. "  (" .. rewardText(obj.reward) .. ")"
				)
				ReplicationService:MarkDirty(player)
			end
		end
	end
end

function ObjectiveService:Start()
	task.spawn(function()
		while true do
			task.wait(5)
			DataService:ForEachNation(function(player, nation)
				pcall(function()
					self:Evaluate(player, nation)
				end)
			end)
		end
	end)
	log:Info("objective service ready")
end

return ObjectiveService
