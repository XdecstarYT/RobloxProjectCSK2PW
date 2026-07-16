--!strict
--[[
	UI/Theme.luau
	Design tokens for the whole interface. One place to restyle the game. Tuned
	for a modern, cinematic strategy dashboard: deep navy chrome, a cyan-blue
	primary, a warm gold secondary, and gradient pairs used across panels, chips
	and buttons so the UI reads as one system.
]]

local Theme = {}

Theme.color = {
	bg = Color3.fromRGB(13, 17, 28),
	panel = Color3.fromRGB(23, 28, 43),
	panelLight = Color3.fromRGB(33, 40, 57),
	stroke = Color3.fromRGB(52, 63, 88),
	accent = Color3.fromRGB(79, 168, 255),
	accent2 = Color3.fromRGB(245, 196, 107),
	accentDim = Color3.fromRGB(46, 92, 153),
	text = Color3.fromRGB(234, 241, 251),
	textDim = Color3.fromRGB(138, 151, 173),
	good = Color3.fromRGB(70, 208, 138),
	warn = Color3.fromRGB(243, 180, 81),
	bad = Color3.fromRGB(240, 101, 95),
}

-- Gradient pairs (top -> bottom) used by UI/Decor.
Theme.gradient = {
	panel = { Color3.fromRGB(30, 38, 56), Color3.fromRGB(19, 24, 37) },
	chip = { Color3.fromRGB(41, 50, 70), Color3.fromRGB(28, 34, 49) },
	accent = { Color3.fromRGB(93, 178, 255), Color3.fromRGB(62, 123, 214) },
	topbar = { Color3.fromRGB(20, 26, 41), Color3.fromRGB(12, 16, 26) },
}

Theme.font = {
	regular = Enum.Font.Gotham,
	medium = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
	black = Enum.Font.GothamBlack,
}

Theme.severityColor = {
	info = Theme.color.accent,
	success = Theme.color.good,
	warning = Theme.color.warn,
	error = Theme.color.bad,
}

Theme.corner = UDim.new(0, 12)
Theme.pad = 10

return Theme
