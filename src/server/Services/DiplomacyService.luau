--!strict
--[[
	Services/DiplomacyService.luau
	Player-to-player (and player-to-AI) diplomacy: escrowed resource trades and
	alliances.

	Trades are safe by construction: the moment an offer is made, the proposer's
	`give` is withdrawn into escrow, so it cannot be double-spent or duplicated. A
	trade only completes if the recipient can actually afford `receive`; declines,
	cancels and expiries refund the escrow. Alliances are mutual and lift both
	sides' influence generation (see Util/Modifiers).

	AI-targeted offers are auto-resolved here on a timer using a simple resource
	valuation, so AIService stays focused on running its economies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Logger = require(ReplicatedStorage.Nexus.Logger)
local Net = require(ReplicatedStorage.Nexus.Net)
local NetRoutes = require(ReplicatedStorage.Nexus.NetRoutes)
local ResourceMath = require(ReplicatedStorage.Nexus.ResourceMath)
local Types = require(ReplicatedStorage.Nexus.Types)

local NotificationService = require(script.Parent.NotificationService)
local ReplicationService = require(script.Parent.ReplicationService)
local WorldService = require(script.Parent.WorldService)

type Nation = Types.Nation
type ResourceBag = Types.ResourceBag

type Offer = {
	id: string,
	kind: string, -- "trade" | "alliance"
	fromId: number,
	toId: number,
	give: ResourceBag, -- escrowed from proposer (trade only)
	receive: ResourceBag, -- demanded from recipient (trade only)
	createdAt: number,
	expiresAt: number,
}

local log = Logger.new("DiplomacyService")

-- Rough barter values used only for AI trade judgement.
local RESOURCE_VALUE: { [string]: number } = {
	money = 1,
	materials = 8,
	energy = 4,
	food = 3,
	research = 15,
	influence = 12,
}

local OFFER_TTL = 120
local MAX_TRADE_AMOUNT = 10_000_000

local DiplomacyService = {
	Name = "DiplomacyService",
}

DiplomacyService._offers = {} :: { [string]: Offer }
DiplomacyService._counter = 0

-- ---- Helpers --------------------------------------------------------------

local VALID_RESOURCE: { [string]: boolean } = {}
for _, id in Constants.RESOURCE_ORDER do
	VALID_RESOURCE[id] = true
end

-- Sanitise a client-supplied resource bag: valid ids, non-negative integers,
-- capped. Returns the cleaned bag and whether it held anything.
local function sanitizeBag(payload: any): (ResourceBag, boolean)
	local out: ResourceBag = {}
	local any = false
	if typeof(payload) == "table" then
		for key, value in payload do
			if VALID_RESOURCE[key] and typeof(value) == "number" and value == value then
				local amount = math.floor(math.clamp(value, 0, MAX_TRADE_AMOUNT))
				if amount > 0 then
					out[key :: any] = amount
					any = true
				end
			end
		end
	end
	return out, any
end

local function valueOf(bag: ResourceBag): number
	local total = 0
	for resource, amount in bag do
		total += amount * (RESOURCE_VALUE[resource] or 1)
	end
	return total
end

local function nextId(self): string
	self._counter += 1
	return "offer_" .. self._counter
end

local function markDirty(player: Player?)
	if player then
		ReplicationService:MarkDirty(player)
	end
end

-- ---- Inbox replication ----------------------------------------------------

local function serialize(offer: Offer): any
	local fromNation = select(1, WorldService:GetNationById(offer.fromId))
	local toNation = select(1, WorldService:GetNationById(offer.toId))
	return {
		id = offer.id,
		kind = offer.kind,
		fromId = offer.fromId,
		toId = offer.toId,
		fromName = fromNation and fromNation.name or "Unknown",
		toName = toNation and toNation.name or "Unknown",
		give = offer.give,
		receive = offer.receive,
		expiresAt = offer.expiresAt,
	}
end

function DiplomacyService:_pushInbox(playerId: number)
	if playerId <= 0 then
		return
	end
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	local incoming, outgoing = {}, {}
	for _, offer in self._offers do
		if offer.toId == playerId then
			table.insert(incoming, serialize(offer))
		elseif offer.fromId == playerId then
			table.insert(outgoing, serialize(offer))
		end
	end
	Net.fireClient(player, NetRoutes.TRADE_INBOX, { incoming = incoming, outgoing = outgoing })
end

function DiplomacyService:_pushBoth(offer: Offer)
	self:_pushInbox(offer.fromId)
	self:_pushInbox(offer.toId)
end

-- ---- Core offer lifecycle -------------------------------------------------

--- Create an offer. Escrows `give` for trades. Returns (offer?, reason?).
function DiplomacyService:CreateOffer(
	fromId: number,
	toId: number,
	kind: string,
	give: ResourceBag,
	receive: ResourceBag
): (Offer?, string?)
	if fromId == toId then
		return nil, "self"
	end
	local fromNation, fromPlayer = WorldService:GetNationById(fromId)
	local toNation = WorldService:GetNationById(toId)
	if not fromNation or not toNation then
		return nil, "no_nation"
	end

	if kind == "alliance" then
		if fromNation.diplomacy.allies[tostring(toId)] then
			return nil, "already_allied"
		end
	else
		if not ResourceMath.canAfford(fromNation.resources, give) then
			return nil, "cannot_afford"
		end
		-- Escrow the offered resources immediately.
		ResourceMath.spend(fromNation.resources, give)
		markDirty(fromPlayer)
	end

	local offer: Offer = {
		id = nextId(self),
		kind = kind,
		fromId = fromId,
		toId = toId,
		give = give,
		receive = receive,
		createdAt = os.time(),
		expiresAt = os.time() + OFFER_TTL,
	}
	self._offers[offer.id] = offer
	self:_pushBoth(offer)
	return offer, nil
end

function DiplomacyService:_refund(offer: Offer)
	if offer.kind == "trade" then
		local fromNation, fromPlayer = WorldService:GetNationById(offer.fromId)
		if fromNation then
			ResourceMath.grant(fromNation.resources, offer.give)
			markDirty(fromPlayer)
		end
	end
end

function DiplomacyService:_settle(offer: Offer): boolean
	local fromNation, fromPlayer = WorldService:GetNationById(offer.fromId)
	local toNation, toPlayer = WorldService:GetNationById(offer.toId)
	if not fromNation or not toNation then
		self:_refund(offer)
		return false
	end

	if offer.kind == "alliance" then
		fromNation.diplomacy.allies[tostring(offer.toId)] = true
		toNation.diplomacy.allies[tostring(offer.fromId)] = true
		if fromPlayer then
			NotificationService:Send(fromPlayer, "success", "Alliance formed", "You are now allied with " .. toNation.name)
		end
		if toPlayer then
			NotificationService:Send(toPlayer, "success", "Alliance formed", "You are now allied with " .. fromNation.name)
		end
	else
		-- Recipient must afford the demanded resources.
		if not ResourceMath.canAfford(toNation.resources, offer.receive) then
			self:_refund(offer)
			if fromPlayer then
				NotificationService:Send(fromPlayer, "warning", "Trade fell through", toNation.name .. " could not pay.")
			end
			return false
		end
		ResourceMath.spend(toNation.resources, offer.receive)
		ResourceMath.grant(toNation.resources, offer.give) -- escrowed goods delivered
		ResourceMath.grant(fromNation.resources, offer.receive)
		if fromPlayer then
			NotificationService:Send(fromPlayer, "success", "Trade accepted", toNation.name .. " accepted your offer.")
		end
		if toPlayer then
			NotificationService:Send(toPlayer, "success", "Trade complete", "Traded with " .. fromNation.name)
		end
	end

	markDirty(fromPlayer)
	markDirty(toPlayer)
	return true
end

function DiplomacyService:_remove(offer: Offer)
	self._offers[offer.id] = nil
	self:_pushBoth(offer)
end

-- ---- Player request handlers ----------------------------------------------

function DiplomacyService:_onPropose(player: Player, payload: any): any
	if typeof(payload) ~= "table" or typeof(payload.toId) ~= "number" then
		return { success = false, reason = "bad_request" }
	end
	local give, giveAny = sanitizeBag(payload.give)
	local receive = select(1, sanitizeBag(payload.receive))
	if not giveAny then
		return { success = false, reason = "empty_offer" }
	end
	local offer, reason = self:CreateOffer(player.UserId, payload.toId, "trade", give, receive)
	if not offer then
		return { success = false, reason = reason }
	end
	NotificationService:Send(player, "info", "Trade offer sent")
	return { success = true, id = offer.id }
end

function DiplomacyService:_onRespond(player: Player, payload: any): any
	if typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local offer = self._offers[payload.id]
	if not offer then
		return { success = false, reason = "not_found" }
	end
	if offer.toId ~= player.UserId then
		return { success = false, reason = "not_yours" }
	end
	if payload.accept then
		self:_settle(offer)
	else
		self:_refund(offer)
		local _, fromPlayer = WorldService:GetNationById(offer.fromId)
		if fromPlayer then
			NotificationService:Send(fromPlayer, "info", "Offer declined")
		end
	end
	self:_remove(offer)
	return { success = true }
end

function DiplomacyService:_onCancel(player: Player, payload: any): any
	if typeof(payload) ~= "table" then
		return { success = false, reason = "bad_request" }
	end
	local offer = self._offers[payload.id]
	if not offer or offer.fromId ~= player.UserId then
		return { success = false, reason = "not_found" }
	end
	self:_refund(offer)
	self:_remove(offer)
	return { success = true }
end

function DiplomacyService:_onAlliance(player: Player, payload: any): any
	if typeof(payload) ~= "table" or typeof(payload.toId) ~= "number" then
		return { success = false, reason = "bad_request" }
	end
	local offer, reason = self:CreateOffer(player.UserId, payload.toId, "alliance", {}, {})
	if not offer then
		return { success = false, reason = reason }
	end
	NotificationService:Send(player, "info", "Alliance proposed")
	return { success = true, id = offer.id }
end

function DiplomacyService:_onBreakAlliance(player: Player, payload: any): any
	local nation = select(1, WorldService:GetNationById(player.UserId))
	if not nation or typeof(payload) ~= "table" or typeof(payload.otherId) ~= "number" then
		return { success = false, reason = "bad_request" }
	end
	nation.diplomacy.allies[tostring(payload.otherId)] = nil
	local otherNation, otherPlayer = WorldService:GetNationById(payload.otherId)
	if otherNation then
		otherNation.diplomacy.allies[tostring(player.UserId)] = nil
		markDirty(otherPlayer)
	end
	markDirty(player)
	return { success = true }
end

-- ---- AI + housekeeping ----------------------------------------------------

-- Decide an AI's response to an offer targeting it.
function DiplomacyService:_resolveAIOffer(offer: Offer)
	local nation = select(1, WorldService:GetNationById(offer.toId))
	if not nation then
		self:_refund(offer)
		self:_remove(offer)
		return
	end
	local accept = false
	if offer.kind == "alliance" then
		local allies = 0
		for _, a in nation.diplomacy.allies do
			if a then
				allies += 1
			end
		end
		accept = allies < 3 and math.random() < 0.6
	else
		local receivedValue = valueOf(offer.give)
		local givenValue = valueOf(offer.receive)
		accept = ResourceMath.canAfford(nation.resources, offer.receive)
			and receivedValue >= givenValue * 0.9
	end
	if accept then
		self:_settle(offer)
	else
		self:_refund(offer)
	end
	self:_remove(offer)
end

function DiplomacyService:Start()
	Net.handleRequest(NetRoutes.PROPOSE_TRADE, function(player, payload)
		return self:_onPropose(player, payload)
	end, { rate = 5, per = 1 })
	Net.handleRequest(NetRoutes.RESPOND_TRADE, function(player, payload)
		return self:_onRespond(player, payload)
	end, { rate = 10, per = 1 })
	Net.handleRequest(NetRoutes.CANCEL_TRADE, function(player, payload)
		return self:_onCancel(player, payload)
	end, { rate = 10, per = 1 })
	Net.handleRequest(NetRoutes.PROPOSE_ALLIANCE, function(player, payload)
		return self:_onAlliance(player, payload)
	end, { rate = 5, per = 1 })
	Net.handleRequest(NetRoutes.BREAK_ALLIANCE, function(player, payload)
		return self:_onBreakAlliance(player, payload)
	end, { rate = 5, per = 1 })

	DataService.Loaded:Connect(function(player: Player)
		self:_pushInbox(player.UserId)
	end)

	-- Housekeeping: expire stale offers and auto-resolve AI-targeted ones.
	task.spawn(function()
		while true do
			task.wait(3)
			local now = os.time()
			for _, offer in table.clone(self._offers) do
				if not self._offers[offer.id] then
					continue
				end
				if offer.toId < 0 then
					self:_resolveAIOffer(offer)
				elseif now >= offer.expiresAt then
					self:_refund(offer)
					self:_remove(offer)
				end
			end
		end
	end)

	log:Info("diplomacy handlers ready")
end

return DiplomacyService
