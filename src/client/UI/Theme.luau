--!strict
--[[
	UI/Theme.luau
	Design tokens for the whole interface. One place to restyle the game. Colours
	are chosen for a dark, modern strategy dashboard with strong contrast so the
	HUD stays legible on PC, mobile and console.
]]

local Theme = {}

Theme.color = {
	bg = Color3.fromRGB(18, 21, 28),
	panel = Color3.fromRGB(26, 30, 40),
	panelLight = Color3.fromRGB(36, 42, 55),
	stroke = Color3.fromRGB(52, 60, 78),
	accent = Color3.fromRGB(90, 150, 255),
	accentDim = Color3.fromRGB(58, 96, 168),
	text = Color3.fromRGB(232, 238, 248),
	textDim = Color3.fromRGB(150, 160, 178),
	good = Color3.fromRGB(92, 210, 116),
	warn = Color3.fromRGB(240, 190, 70),
	bad = Color3.fromRGB(238, 96, 96),
}

Theme.font = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

Theme.severityColor = {
	info = Theme.color.accent,
	success = Theme.color.good,
	warning = Theme.color.warn,
	error = Theme.color.bad,
}

Theme.corner = UDim.new(0, 10)
Theme.pad = 10

return Theme
