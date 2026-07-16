--!strict
--[[
	Config/Resources.luau
	Display metadata for each resource. Simulation math lives elsewhere; this is
	purely how a resource is labelled and coloured in the UI.
]]

export type ResourceMeta = {
	id: string,
	displayName: string,
	symbol: string,
	color: { number }, -- {r, g, b} 0..1
	-- Whether the HUD shows an absolute stockpile or a per-tick flow.
	kind: "stock" | "flow",
	description: string,
}

local Resources: { [string]: ResourceMeta } = {
	money = {
		id = "money",
		displayName = "Treasury",
		symbol = "$",
		color = { 0.36, 0.82, 0.45 },
		kind = "stock",
		description = "Liquid national funds used for construction and services.",
	},
	materials = {
		id = "materials",
		displayName = "Materials",
		symbol = "▣",
		color = { 0.78, 0.6, 0.36 },
		kind = "stock",
		description = "Raw building stock consumed by construction and upgrades.",
	},
	energy = {
		id = "energy",
		displayName = "Power",
		symbol = "⚡",
		color = { 0.98, 0.82, 0.32 },
		kind = "flow",
		description = "Net electrical capacity. Negative power idles buildings.",
	},
	food = {
		id = "food",
		displayName = "Food",
		symbol = "❖",
		color = { 0.55, 0.78, 0.4 },
		kind = "stock",
		description = "Feeds the population. Shortfalls breed unrest.",
	},
	research = {
		id = "research",
		displayName = "Research",
		symbol = "✦",
		color = { 0.45, 0.66, 0.95 },
		kind = "flow",
		description = "Points that advance the technology tree.",
	},
	influence = {
		id = "influence",
		displayName = "Influence",
		symbol = "◆",
		color = { 0.72, 0.5, 0.92 },
		kind = "stock",
		description = "Diplomatic capital spent on treaties and expansion.",
	},
}

return Resources
