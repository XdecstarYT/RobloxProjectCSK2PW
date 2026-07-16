--!strict
--[[
	ClientPrefs.luau
	A tiny in-memory preferences store shared by the client controllers. Settings
	writes it; SoundController, AmbianceController and NotificationController read
	it and react via the Changed signal. Session-local by design (no persistence)
	— it's the wiring the Settings UI drives.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Nexus.Signal)
local Audio = require(ReplicatedStorage.Nexus.Config.Audio)

local ClientPrefs = {
	Changed = Signal.new() :: any, -- fires (key, value)
}

local state: { [string]: any } = {
	musicVolume = Audio.volumes.music,
	sfxVolume = Audio.volumes.sfx,
	muteNotifications = false,
	effectsEnabled = true,
}

function ClientPrefs.get(key: string): any
	return state[key]
end

function ClientPrefs.set(key: string, value: any)
	if state[key] == value then
		return
	end
	state[key] = value
	ClientPrefs.Changed:Fire(key, value)
end

return ClientPrefs
