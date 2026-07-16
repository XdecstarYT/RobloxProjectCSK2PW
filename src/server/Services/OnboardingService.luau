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
local ServerSettings = require(ReplicatedStorage.Nexus.Config.ServerSettings)

local DataService = require(script.Parent.DataService)
local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)

local log = Logger.new("OnboardingService")

local OnboardingService = {
	Name = "OnboardingService",
}

-- `delay` is the gap before each tip (waited sequentially).
local TIPS = {
	{ delay = 3, sev = "info", title = "Welcome to Nexus!", body = "Grow your settlement into a superpower. Let's begin." },
	{ delay = 6, sev = "info", title = "Power the city", body = "Open 🏗 Build and place a Coal Plant, then a Farm and Housing." },
	{ delay = 8, sev = "info", title = "Govern wisely", body = "Set taxes, laws and government type in 🏛 Politics." },
	{ delay = 8, sev = "info", title = "Advance", body = "Unlock buildings and bonuses in 🔬 Research." },
	{ delay = 8, sev = "info", title = "Go global", body = "Trade in 🤝 Diplomacy, expand in 🗺 Territory, climb 🏆 Ranks." },
}

function OnboardingService:Start()
	if not ServerSettings.showStartingHints then
		return
	end
	DataService.Loaded:Connect(function(player, profile)
		local nation = profile.nation
		if nation.flags.onboarded then
			return
		end
		-- Mark done up front so a mid-sequence disconnect never repeats it.
		nation.flags.onboarded = true
		ReplicationService:MarkDirty(player)

		task.spawn(function()
			for _, tip in TIPS do
				task.wait(tip.delay)
				if not player.Parent then
					return
				end
				NotificationService:Send(player, tip.sev, tip.title, tip.body)
			end
		end)
	end)
	log:Info("onboarding ready")
end

return OnboardingService
