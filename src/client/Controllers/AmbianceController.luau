--!strict
--[[
	Controllers/AmbianceController.luau
	Sets the mood: cinematic lighting, atmospheric depth and post-processing.
	Configured at runtime on the client (lighting is client-rendered anyway), so
	the look ships identically whether the game is opened from the place file or
	synced with Rojo — no hand-authored Lighting in the tree required.

	The target is a clean, warm late-afternoon over a stylized city: soft shadows,
	a little haze for distance, gentle bloom on the neon accents, and a touch of
	colour grading for contrast and life.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DAY_LENGTH = 600 -- real seconds for a full 24-hour cycle

local AmbianceController = {
	Name = "AmbianceController",
}

AmbianceController._effects = nil :: { any }?

-- Fetch-or-create a single instance of `className` under `parent`.
local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

function AmbianceController:Init()
	-- Core lighting: Future technology for the best shadows and light bounce.
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 24
	Lighting.Brightness = 2.6
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(64, 72, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(126, 136, 158)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 205)
	Lighting.ColorShift_Bottom = Color3.fromRGB(120, 140, 170)
	Lighting.ShadowSoftness = 0.5
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000 -- distance handled by Atmosphere, not legacy fog

	-- Atmosphere: haze that fades distant tiles for a sense of scale.
	local atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(202, 212, 227)
	atmosphere.Decay = Color3.fromRGB(104, 112, 128)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.6

	-- Bloom: makes the neon building accents glow.
	local bloom = ensure(Lighting, "BloomEffect", "NexusBloom") :: BloomEffect
	bloom.Intensity = 0.65
	bloom.Size = 24
	bloom.Threshold = 1.05

	-- Sun rays for a hint of golden-hour warmth.
	local sun = ensure(Lighting, "SunRaysEffect", "NexusSunRays") :: SunRaysEffect
	sun.Intensity = 0.09
	sun.Spread = 0.9

	-- Colour grading: gentle contrast, saturation and a warm tint.
	local grade = ensure(Lighting, "ColorCorrectionEffect", "NexusGrade") :: ColorCorrectionEffect
	grade.Brightness = 0.0
	grade.Contrast = 0.1
	grade.Saturation = 0.14
	grade.TintColor = Color3.fromRGB(255, 248, 240)

	-- Only PostEffects have an `Enabled` flag; Atmosphere stays on (it's cheap).
	self._effects = { bloom, sun, grade }
end

--- Toggle the heavier post-processing for lower-end devices.
function AmbianceController:SetEffectsEnabled(enabled: boolean)
	for _, effect in self._effects or {} do
		effect.Enabled = enabled
	end
end

function AmbianceController:Start()
	local ClientPrefs = require(script.Parent.Parent.ClientPrefs)
	self:SetEffectsEnabled(ClientPrefs.get("effectsEnabled"))
	ClientPrefs.Changed:Connect(function(key, value)
		if key == "effectsEnabled" then
			self:SetEffectsEnabled(value)
		end
	end)

	-- Living sky: advance the time of day. Neon building accents glow at night.
	RunService.Heartbeat:Connect(function(dt)
		if ClientPrefs.get("dayNight") then
			Lighting.ClockTime = (Lighting.ClockTime + dt * (24 / DAY_LENGTH)) % 24
		end
	end)
end

return AmbianceController
