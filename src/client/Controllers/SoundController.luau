--!strict
--[[
	Controllers/SoundController.luau
	Audio plumbing with music/SFX volume buses. Reads sound ids from Config/Audio
	(blank by default, so it's silent until you paste asset ids) and volumes from
	ClientPrefs. Other controllers call PlaySfx / PlayClick; playing a sound with
	no id configured is a safe no-op.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Audio = require(ReplicatedStorage.Nexus.Config.Audio)

local ClientPrefs = require(script.Parent.Parent.ClientPrefs)

local SoundController = {
	Name = "SoundController",
}

SoundController._sfx = {} :: { [string]: Sound }
SoundController._music = nil :: Sound?
SoundController._musicGroup = nil :: SoundGroup?
SoundController._sfxGroup = nil :: SoundGroup?

local function makeGroup(name: string, volume: number): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = volume
	group.Parent = SoundService
	return group
end

function SoundController:Init()
	self._musicGroup = makeGroup("NexusMusic", ClientPrefs.get("musicVolume"))
	self._sfxGroup = makeGroup("NexusSFX", ClientPrefs.get("sfxVolume"))

	for name, id in Audio.sfx do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.SoundGroup = self._sfxGroup
		sound.Parent = SoundService
		self._sfx[name] = sound
	end

	if Audio.music ~= "" then
		local music = Instance.new("Sound")
		music.Name = "NexusTrack"
		music.SoundId = Audio.music
		music.Looped = true
		music.SoundGroup = self._musicGroup
		music.Parent = SoundService
		self._music = music
	end

	ClientPrefs.Changed:Connect(function(key, value)
		if key == "musicVolume" and self._musicGroup then
			self._musicGroup.Volume = value
		elseif key == "sfxVolume" and self._sfxGroup then
			self._sfxGroup.Volume = value
		end
	end)
end

function SoundController:PlaySfx(name: string)
	local sound = self._sfx[name]
	if sound and sound.SoundId ~= "" then
		sound:Play()
	end
end

function SoundController:PlayClick()
	self:PlaySfx("click")
end

function SoundController:Start()
	if self._music then
		self._music:Play()
	end
end

return SoundController
