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
	TUTORIAL_DONE = "nation/tutorialDone",

	-- Diplomacy.
	PROPOSE_TRADE = "diplomacy/propose",
	RESPOND_TRADE = "diplomacy/respond",
	CANCEL_TRADE = "diplomacy/cancel",
	PROPOSE_ALLIANCE = "diplomacy/ally",
	BREAK_ALLIANCE = "diplomacy/breakAlly",

	-- Territory.
	CLAIM_REGION = "territory/claim",

	-- Military.
	RECRUIT_UNITS = "military/recruit",
	DISBAND_UNITS = "military/disband",

	-- Market.
	MARKET_BUY = "market/buy",
	MARKET_SELL = "market/sell",

	-- Server -> client pushes.
	STATE_SYNC = "state/sync",
	NOTIFY = "state/notify",
	TRADE_INBOX = "diplomacy/inbox",
	WORLD_SYNC = "world/sync",
	TERRITORY_SYNC = "territory/sync",
	MARKET_SYNC = "market/sync",
}

return NetRoutes
