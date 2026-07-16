--!strict
--[[
	NetRoutes.luau
	The canonical list of network route names. Both sides import these constants
	instead of typing string literals, so a renamed route is a compile-time find,
	not a silent runtime mismatch.
]]

local NetRoutes = {
	-- Client -> server requests (round-trip, return a NetResult).
	PLACE_BUILDING = "city/place",
	UPGRADE_BUILDING = "city/upgrade",
	DEMOLISH_BUILDING = "city/demolish",
	REPAIR_BUILDING = "city/repair",
	SET_TAX_RATE = "politics/setTax",
	SET_GOVERNMENT = "politics/setGovernment",
	TOGGLE_LAW = "politics/toggleLaw",
	START_RESEARCH = "research/start",
	RENAME_NATION = "nation/rename",
	PROPOSE_TRADE = "diplomacy/propose",
	RESPOND_TRADE = "diplomacy/respond",

	-- Server -> client pushes.
	STATE_SYNC = "state/sync",
	NOTIFY = "state/notify",
	TRADE_INBOX = "diplomacy/inbox",
}

return NetRoutes
