--!strict
--[[
	Net.luau
	The single, guarded gateway between client and server.

	Everything that crosses the wire goes through one RemoteFunction (`Request`,
	for round-trip actions) and one RemoteEvent (`Push`, for fire-and-forget in
	both directions). Traffic is multiplexed by a string `route`, so adding a new
	message never means adding a new Instance a exploiter could probe.

	Server responsibilities baked in here (never trust the client):
	  * per-player, per-route token-bucket rate limiting
	  * payload shape/size guards before a handler ever runs
	  * every handler wrapped so a thrown error becomes a clean NetResult, not a
	    leaked stack trace or a dropped RemoteFunction invocation

	The module detects its context via RunService and only exposes the API that
	is safe for that side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Constants)
local Logger = require(script.Parent.Logger)
local Types = require(script.Parent.Types)

type NetResult = Types.NetResult

local log = Logger.new("Net")
local IS_SERVER = RunService:IsServer()

local Net = {}

-- Default rate budget applied to every route unless a handler overrides it.
local DEFAULT_RATE = { rate = 20, per = 1 } -- 20 requests per second, bursty via bucket

-- ---------------------------------------------------------------------------
-- Remote instances
-- ---------------------------------------------------------------------------

local requestRemote: RemoteFunction
local pushRemote: RemoteEvent

local function buildRemotes()
	local folder = Instance.new("Folder")
	folder.Name = Constants.NET_FOLDER_NAME

	requestRemote = Instance.new("RemoteFunction")
	requestRemote.Name = "Request"
	requestRemote.Parent = folder

	pushRemote = Instance.new("RemoteEvent")
	pushRemote.Name = "Push"
	pushRemote.Parent = folder

	folder.Parent = ReplicatedStorage
end

local function findRemotes()
	local folder = ReplicatedStorage:WaitForChild(Constants.NET_FOLDER_NAME, 20)
	assert(folder, "[Net] remote folder never replicated")
	requestRemote = folder:WaitForChild("Request") :: RemoteFunction
	pushRemote = folder:WaitForChild("Push") :: RemoteEvent
end

-- ---------------------------------------------------------------------------
-- Server implementation
-- ---------------------------------------------------------------------------

if IS_SERVER then
	local Players = game:GetService("Players")

	type RequestHandler = (player: Player, payload: any) -> any
	type EventHandler = (player: Player, payload: any) -> ()
	type RateConfig = { rate: number, per: number }

	local requestHandlers: { [string]: { fn: RequestHandler, rate: RateConfig } } = {}
	local eventHandlers: { [string]: { fn: EventHandler, rate: RateConfig } } = {}

	-- Token buckets keyed by player then route.
	local buckets: { [Player]: { [string]: { tokens: number, updated: number } } } = {}

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	local function consumeToken(player: Player, route: string, cfg: RateConfig): boolean
		local perPlayer = buckets[player]
		if not perPlayer then
			perPlayer = {}
			buckets[player] = perPlayer
		end
		local bucket = perPlayer[route]
		local now = os.clock()
		if not bucket then
			bucket = { tokens = cfg.rate, updated = now }
			perPlayer[route] = bucket
		end
		-- Refill proportionally to elapsed time, capped at capacity.
		local elapsed = now - bucket.updated
		bucket.updated = now
		bucket.tokens = math.min(cfg.rate, bucket.tokens + elapsed * (cfg.rate / cfg.per))
		if bucket.tokens >= 1 then
			bucket.tokens -= 1
			return true
		end
		return false
	end

	-- Reject anything that could be a memory-abuse vector before dispatch.
	local function payloadIsSane(payload: any): boolean
		local t = typeof(payload)
		if t == "nil" or t == "number" or t == "boolean" or t == "string" then
			return t ~= "string" or #payload <= 4096
		end
		if t == "table" then
			return true -- handlers do the deep validation
		end
		return false
	end

	-- Create the remotes before wiring any handler onto them.
	buildRemotes()

	requestRemote.OnServerInvoke = function(player: Player, route: any, payload: any): NetResult
		if typeof(route) ~= "string" then
			return { ok = false, error = "bad_route" }
		end
		local entry = requestHandlers[route]
		if not entry then
			log:Warn(("unknown request route %q from %s"):format(route, player.Name))
			return { ok = false, error = "unknown_route" }
		end
		if not payloadIsSane(payload) then
			return { ok = false, error = "bad_payload" }
		end
		if not consumeToken(player, route, entry.rate) then
			return { ok = false, error = "rate_limited" }
		end

		local ok, result = pcall(entry.fn, player, payload)
		if not ok then
			log:Warn(("handler %q errored: %s"):format(route, tostring(result)))
			return { ok = false, error = "internal" }
		end
		return { ok = true, data = result }
	end

	pushRemote.OnServerEvent:Connect(function(player: Player, route: any, payload: any)
		if typeof(route) ~= "string" then
			return
		end
		local entry = eventHandlers[route]
		if not entry then
			return
		end
		if not payloadIsSane(payload) then
			return
		end
		if not consumeToken(player, route, entry.rate) then
			return
		end
		local ok, err = pcall(entry.fn, player, payload)
		if not ok then
			log:Warn(("event %q errored: %s"):format(route, tostring(err)))
		end
	end)

	--- Register a round-trip handler. `handler(player, payload)` returns the
	--- data to send back; throwing yields `{ ok = false, error = "internal" }`.
	function Net.handleRequest(route: string, handler: RequestHandler, rate: RateConfig?)
		assert(not requestHandlers[route], "duplicate request route: " .. route)
		requestHandlers[route] = { fn = handler, rate = rate or DEFAULT_RATE }
	end

	--- Register a fire-and-forget client -> server handler.
	function Net.onEvent(route: string, handler: EventHandler, rate: RateConfig?)
		assert(not eventHandlers[route], "duplicate event route: " .. route)
		eventHandlers[route] = { fn = handler, rate = rate or DEFAULT_RATE }
	end

	function Net.fireClient(player: Player, route: string, payload: any)
		pushRemote:FireClient(player, route, payload)
	end

	function Net.fireAllClients(route: string, payload: any)
		pushRemote:FireAllClients(route, payload)
	end

	log:Info("server gateway ready")
else
	-- -----------------------------------------------------------------------
	-- Client implementation
	-- -----------------------------------------------------------------------

	local listeners: { [string]: { (payload: any) -> () } } = {}

	findRemotes()

	pushRemote.OnClientEvent:Connect(function(route: any, payload: any)
		if typeof(route) ~= "string" then
			return
		end
		local bucket = listeners[route]
		if not bucket then
			return
		end
		for _, fn in bucket do
			local ok, err = pcall(fn, payload)
			if not ok then
				log:Warn(("client listener %q errored: %s"):format(route, tostring(err)))
			end
		end
	end)

	--- Round-trip request to the server. Always resolves to a NetResult; network
	--- failures are converted into `{ ok = false, error = "network" }`.
	function Net.request(route: string, payload: any?): NetResult
		local ok, result = pcall(function()
			return requestRemote:InvokeServer(route, payload)
		end)
		if not ok then
			log:Warn(("request %q failed: %s"):format(route, tostring(result)))
			return { ok = false, error = "network" }
		end
		if typeof(result) ~= "table" then
			return { ok = false, error = "malformed_response" }
		end
		return result :: NetResult
	end

	function Net.fireServer(route: string, payload: any?)
		pushRemote:FireServer(route, payload)
	end

	--- Subscribe to a server push. Returns an unsubscribe function.
	function Net.onEvent(route: string, handler: (payload: any) -> ()): () -> ()
		local bucket = listeners[route]
		if not bucket then
			bucket = {}
			listeners[route] = bucket
		end
		table.insert(bucket, handler)
		return function()
			local i = table.find(bucket, handler)
			if i then
				table.remove(bucket, i)
			end
		end
	end

	log:Info("client gateway ready")
end

return Net
