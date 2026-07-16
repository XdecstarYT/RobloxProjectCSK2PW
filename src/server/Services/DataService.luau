--!strict
--[[
	Services/DataService.luau
	Original, session-safe persistence for player profiles.

	Design goals (all implemented here, no external dependency):
	  * Session locking  — one live server owns a profile at a time, so a player
	    hopping servers can never fork or roll back their own save.
	  * Reconciliation   — an old save is merged against the current default
	    template, so new fields appear without wiping player progress.
	  * Migration        — schemaVersion drives ordered upgrade steps.
	  * Retry + backoff  — every DataStore op is retried with exponential backoff.
	  * Backups          — the last-known-good record is mirrored to a second
	    store before each risky write.
	  * Autosave         — periodic saves plus a BindToClose flush on shutdown.
	  * Studio fallback   — if the DataStore API is unreachable (API access off),
	    an in-memory mock keeps the whole game playable for testing.

	Other services never call DataStores; they read and mutate `profile.nation`
	and rely on this service to persist it.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Nexus.Constants)
local Logger = require(ReplicatedStorage.Nexus.Logger)
local Signal = require(ReplicatedStorage.Nexus.Signal)
local TableUtil = require(ReplicatedStorage.Nexus.TableUtil)
local Types = require(ReplicatedStorage.Nexus.Types)
local Balance = require(ReplicatedStorage.Nexus.Config.Balance)

type Profile = Types.Profile
type Nation = Types.Nation

-- A stored record wraps the profile with an ownership lock.
type SessionLock = { jobId: string, placeId: number, time: number }
type Record = { profile: Profile?, lock: SessionLock? }

local log = Logger.new("DataService")

-- ---------------------------------------------------------------------------
-- Store abstraction: real DataStore or in-memory mock (Studio without API).
-- ---------------------------------------------------------------------------

type StoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
	GetAsync: (self: any, key: string) -> any,
	SetAsync: (self: any, key: string, value: any) -> (),
}

local MockStore = {}
MockStore.__index = MockStore
function MockStore.new(): StoreLike
	return (setmetatable({ _data = {} }, MockStore) :: any) :: StoreLike
end
function MockStore:UpdateAsync(key: string, transform: (any) -> any): any
	local current = self._data[key]
	local updated = transform(current)
	if updated ~= nil then
		self._data[key] = TableUtil.deepCopy(updated)
	end
	return updated
end
function MockStore:GetAsync(key: string): any
	return TableUtil.deepCopy(self._data[key])
end
function MockStore:SetAsync(key: string, value: any)
	self._data[key] = TableUtil.deepCopy(value)
end

-- ---------------------------------------------------------------------------
-- Service
-- ---------------------------------------------------------------------------

local DataService = {
	Name = "DataService",
	Loaded = Signal.new() :: any, -- fires (player, profile)
	Released = Signal.new() :: any, -- fires (player)
}

DataService._profiles = {} :: { [number]: Profile }
DataService._loading = {} :: { [number]: boolean }
DataService._store = nil :: StoreLike?
DataService._backupStore = nil :: StoreLike?
DataService._useMock = false

-- Migration steps: index N upgrades a vN profile to v(N+1) in place. Reconcile
-- also backfills missing fields, but explicit migrations document the change and
-- let us transform (not just default) data when a shape genuinely changes.
local MIGRATIONS: { [number]: (Profile) -> () } = {
	-- v1 -> v2: nations gained military, diplomacy and objectives.
	[1] = function(profile)
		local nation = profile.nation
		if typeof(nation.military) ~= "table" then
			nation.military = { army = 0, navy = 0, air = 0 }
		end
		if typeof(nation.diplomacy) ~= "table" then
			nation.diplomacy = { allies = {} }
		end
		if typeof((nation :: any).objectives) ~= "table" then
			(nation :: any).objectives = {}
		end
	end,
}

-- ---- Default profile ------------------------------------------------------

local function defaultNation(player: Player): Nation
	local start = Balance.START
	return {
		ownerId = player.UserId,
		name = player.DisplayName .. "'s Nation",
		founded = os.time(),
		resources = TableUtil.deepCopy(start.resources),
		buildings = {},
		population = {
			total = start.population,
			employed = 0,
			happiness = 60,
			education = 20,
			health = 40,
			unrest = 0,
		},
		politics = {
			government = "democracy",
			approval = 60,
			stability = 60,
			corruption = 5,
			taxRate = start.taxRate,
			activeLaws = {},
			nextElection = 0,
		},
		economy = {
			gdp = 0,
			gdpHistory = {},
			treasury = start.treasury,
			debt = 0,
			inflation = 2.0,
			interestRate = 4.0,
			lastTickIncome = 0,
			lastTickExpense = 0,
		},
		research = {
			unlocked = {},
			current = nil,
			progress = 0,
			points = 0,
		},
		military = { army = 0, navy = 0, air = 0 },
		diplomacy = { allies = {} },
		territory = { regions = { "capital" } },
		objectives = {},
		flags = {},
	}
end

local function defaultProfile(player: Player): Profile
	return {
		schemaVersion = Constants.PROFILE_SCHEMA_VERSION,
		createdAt = os.time(),
		lastPlayed = os.time(),
		playtime = 0,
		nation = defaultNation(player),
	}
end

-- ---- DataStore helpers with retry + backoff -------------------------------

local function keyFor(userId: number): string
	return "player_" .. userId
end

local function sameSession(lock: SessionLock?): boolean
	return lock ~= nil and lock.jobId == game.JobId and lock.placeId == game.PlaceId
end

local function lockIsStale(lock: SessionLock): boolean
	return (os.time() - lock.time) > Constants.SESSION_LOCK_STALE_AFTER
end

-- Retry any DataStore call with exponential backoff. Returns ok, result.
local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delayTime = 1
	for attempt = 1, Constants.DATASTORE_MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		log:Warn(("%s attempt %d failed: %s"):format(label, attempt, tostring(result)))
		if attempt < Constants.DATASTORE_MAX_RETRIES then
			task.wait(delayTime)
			delayTime = math.min(delayTime * 2, 16)
		end
	end
	return false, nil
end

function DataService:Init()
	if RunService:IsStudio() then
		-- Probe the DataStore API; fall back to an in-memory mock if it is off.
		local probe = DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
		local ok = pcall(function()
			-- Returning nil cancels the write, so this only exercises the API.
			probe:UpdateAsync("__probe__", function()
				return nil
			end)
		end)
		if not ok then
			self._useMock = true
			log:Warn("DataStore API unavailable — using in-memory mock (Studio only)")
		end
	end

	if self._useMock then
		self._store = MockStore.new()
		self._backupStore = MockStore.new()
	else
		self._store = DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
		self._backupStore = DataStoreService:GetDataStore(Constants.DATASTORE_BACKUP_NAME)
	end
end

-- ---- Load -----------------------------------------------------------------

function DataService:_migrate(profile: Profile)
	while profile.schemaVersion < Constants.PROFILE_SCHEMA_VERSION do
		local step = MIGRATIONS[profile.schemaVersion]
		if step then
			step(profile)
		end
		profile.schemaVersion += 1
	end
end

function DataService:_loadAsync(player: Player): Profile?
	local key = keyFor(player.UserId)
	local store = assert(self._store, "store not initialised")

	-- Acquire the session lock. If another live session holds a fresh lock, we
	-- back off and retry; a stale lock is reclaimed.
	local acquired: Record? = nil
	for attempt = 1, Constants.DATASTORE_MAX_RETRIES do
		local ok, record = retry("load:" .. key, function(): Record
			return store:UpdateAsync(key, function(old: Record?): Record?
				local rec: Record = old or { profile = nil, lock = nil }
				local lock = rec.lock
				if lock and not sameSession(lock) and not lockIsStale(lock) then
					-- Owned elsewhere and fresh: abort this write, retry later.
					return nil
				end
				rec.lock = { jobId = game.JobId, placeId = game.PlaceId, time = os.time() }
				return rec
			end)
		end)

		if ok and record and sameSession(record.lock) then
			acquired = record
			break
		end
		log:Warn(("profile %s locked elsewhere, retry %d"):format(key, attempt))
		task.wait(2 ^ attempt)
	end

	if not acquired then
		return nil
	end

	local profile = acquired.profile
	if not profile then
		profile = defaultProfile(player)
	else
		-- Bring an older save up to the current shape and schema.
		self:_migrate(profile)
		TableUtil.reconcile(profile, defaultProfile(player))
		-- Reconcile the nested nation too, so new nation fields get defaults.
		TableUtil.reconcile(profile.nation, defaultNation(player))
	end
	profile.lastPlayed = os.time()
	return profile
end

function DataService:LoadPlayer(player: Player)
	if self._loading[player.UserId] or self._profiles[player.UserId] then
		return
	end
	self._loading[player.UserId] = true

	local profile = self:_loadAsync(player)
	self._loading[player.UserId] = nil

	if not player.Parent then
		-- Player left mid-load; release the lock we may have taken.
		if profile then
			self:_saveAsync(player.UserId, profile, true)
		end
		return
	end

	if not profile then
		log:Error(("could not load profile for %s; kicking to protect data"):format(player.Name))
		player:Kick("Your save is in use on another server. Please rejoin in a moment.")
		return
	end

	self._profiles[player.UserId] = profile
	log:Info(("loaded profile for %s (v%d)"):format(player.Name, profile.schemaVersion))
	self.Loaded:Fire(player, profile)
end

-- ---- Save -----------------------------------------------------------------

function DataService:_saveAsync(userId: number, profile: Profile, releaseLock: boolean): boolean
	local key = keyFor(userId)
	local store = assert(self._store, "store not initialised")

	-- Snapshot the profile so a concurrent simulation tick cannot mutate the
	-- table while the DataStore is serialising it.
	local snapshot = TableUtil.deepCopy(profile)

	-- Mirror the last-good profile to the backup store first (best effort).
	retry("backup:" .. key, function()
		(assert(self._backupStore) :: any):SetAsync(key, { profile = snapshot, savedAt = os.time() })
	end)

	local ok = retry("save:" .. key, function()
		store:UpdateAsync(key, function(old: Record?): Record?
			local rec: Record = old or {}
			local lock = rec.lock
			-- Refuse to clobber a save owned by a different, still-live session.
			if lock and not sameSession(lock) and not lockIsStale(lock) then
				return nil
			end
			rec.profile = snapshot
			if releaseLock then
				rec.lock = nil
			else
				rec.lock = { jobId = game.JobId, placeId = game.PlaceId, time = os.time() }
			end
			return rec
		end)
	end)
	return ok == true
end

function DataService:SaveNow(player: Player): boolean
	local profile = self._profiles[player.UserId]
	if not profile then
		return false
	end
	return self:_saveAsync(player.UserId, profile, false)
end

function DataService:ReleasePlayer(player: Player)
	local profile = self._profiles[player.UserId]
	if not profile then
		return
	end
	self._profiles[player.UserId] = nil
	self:_saveAsync(player.UserId, profile, true)
	log:Info(("released profile for %s"):format(player.Name))
	self.Released:Fire(player)
end

-- ---- Accessors ------------------------------------------------------------

function DataService:GetProfile(player: Player): Profile?
	return self._profiles[player.UserId]
end

function DataService:GetNation(player: Player): Nation?
	local profile = self._profiles[player.UserId]
	return profile and profile.nation or nil
end

--- Iterate every loaded (player, nation) pair. Used by simulation ticks.
function DataService:ForEachNation(fn: (player: Player, nation: Nation) -> ())
	for _, player in Players:GetPlayers() do
		local nation = self:GetNation(player)
		if nation then
			fn(player, nation)
		end
	end
end

-- ---- Lifecycle ------------------------------------------------------------

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:LoadPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:LoadPlayer(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:ReleasePlayer(player)
	end)

	-- Autosave loop.
	task.spawn(function()
		while true do
			task.wait(Constants.AUTOSAVE_INTERVAL)
			for userId, profile in self._profiles do
				profile.playtime += Constants.AUTOSAVE_INTERVAL
				self:_saveAsync(userId, profile, false)
			end
		end
	end)

	-- Flush everything on shutdown.
	game:BindToClose(function()
		if self._useMock then
			return
		end
		for userId, profile in self._profiles do
			task.spawn(function()
				self:_saveAsync(userId, profile, true)
			end)
		end
		task.wait(3)
	end)
end

return DataService
