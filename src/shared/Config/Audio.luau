--!strict
--[[
	Config/Audio.luau
	Sound asset ids and default volumes. IDs are intentionally blank — this is the
	"drop-in" point for the audio you add from the Toolbox/Creator Store. Paste a
	`rbxassetid://...` into any field and SoundController will use it; empty fields
	are simply silent, so the game runs fine with no audio configured.
]]

local Audio = {
	volumes = {
		music = 0.4,
		sfx = 0.7,
	},

	-- Looping background track (leave "" for silence).
	music = "",

	-- One-shot sound effects, played by name via SoundController:PlaySfx(name).
	sfx = {
		click = "",
		build = "",
		success = "",
		error = "",
		notify = "",
	},
}

return Audio
