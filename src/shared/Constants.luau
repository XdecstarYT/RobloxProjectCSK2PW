--!strict
--[[
	Constants.luau
	Immutable, project-wide constants. No gameplay balance numbers live here —
	those belong in Config/Balance.luau so designers can tune them separately.
]]

local Constants = {}

-- Schema version of the persisted profile. Bump this whenever the shape of
-- Types.Profile changes, and add a matching migration in DataService.
Constants.PROFILE_SCHEMA_VERSION = 1

-- DataStore names. Suffixing with an environment tag lets us keep test saves
-- isolated from production ones.
Constants.DATASTORE_NAME = "NexusProfiles_v1"
Constants.DATASTORE_BACKUP_NAME = "NexusProfileBackups_v1"

-- Simulation cadence (seconds of real time per simulated tick).
Constants.ECONOMY_TICK = 5
Constants.CITIZEN_TICK = 10
Constants.POLITICS_TICK = 30

-- Autosave cadence and session-lock behaviour.
Constants.AUTOSAVE_INTERVAL = 90
Constants.SESSION_LOCK_STALE_AFTER = 60 * 30 -- a lock older than this is reclaimable
Constants.DATASTORE_MAX_RETRIES = 5

-- World grid. The buildable map is a square grid of this many tiles per side,
-- each tile STUDS_PER_TILE studs wide.
Constants.GRID_SIZE = 64
Constants.STUDS_PER_TILE = 8

-- Networking guardrails.
Constants.NET_FOLDER_NAME = "NexusRemotes"
Constants.NET_REQUEST_TIMEOUT = 10

-- How many GDP samples to retain for the economy graph.
Constants.GDP_HISTORY_LENGTH = 60

-- The set of resource ids, in a stable display order.
Constants.RESOURCE_ORDER = { "money", "materials", "energy", "food", "research", "influence" } :: { string }

return Constants
