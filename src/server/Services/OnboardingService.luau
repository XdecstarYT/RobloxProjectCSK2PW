--!strict
--[[
	Services/OnboardingService.luau
	Gently teaches a brand-new nation the ropes with a short, staggered sequence
	of HUD tips on first join. Guarded by a persisted flag so returning players
	are never nagged, and by ServerSettings.showStartingHints so an owner can
	switch it off.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local ServerSettings = require(ReplicatedStorage.Nexus.Config.ServerSettings)

local DataService = require(script.Parent.DataService)
local ReplicationService = require(script.Parent.ReplicationService)

local log = Logger.new("OnboardingService")

local OnboardingService = {
	Name = "OnboardingService",
}

function OnboardingService:Start()
	-- The step-by-step guidance now lives in the interactive TutorialController;
	-- this service just persists the "tutorial finished" flag it reports.
	Net.handleRequest(NetRoutes.TUTORIAL_DONE, function(player)
		local nation = DataService:GetNation(player)
		if nation then
			nation.flags.tutorialDone = true
			ReplicationService:MarkDirty(player)
		end
		return { success = true }
	end, { rate = 2, per = 1 })

	if not ServerSettings.showStartingHints then
		return
	end
	log:Info("onboarding ready")
end

return OnboardingService
