--!strict
--[[
	Types.luau
	Central typed-Luau definitions shared by server and client.

	Keeping every cross-boundary shape in one module means the network layer,
	the data schema, and the UI all agree on the exact structure of a nation's
	state. When a field changes here, the type checker flags every consumer.
]]

export type ResourceId = "money" | "materials" | "energy" | "food" | "research" | "influence"

-- A player's stockpile of every tradeable/consumable resource.
export type ResourceBag = { [ResourceId]: number }

-- One placed building instance owned by a nation.
export type Building = {
	id: string, -- unique per-nation building uid
	kind: string, -- key into Config.Buildings
	level: number,
	position: { x: number, z: number }, -- grid coordinates
	rotation: number, -- 0, 90, 180, 270
	condition: number, -- 0..1, degrades with age, restored by maintenance
	builtAt: number, -- os.time() when placed
	active: boolean, -- powered + staffed?
}

-- Aggregate, simulated population of a nation.
export type Population = {
	total: number,
	employed: number,
	happiness: number, -- 0..100
	education: number, -- 0..100
	health: number, -- 0..100
	unrest: number, -- 0..100
}

export type GovernmentId =
	"democracy"
	| "republic"
	| "monarchy"
	| "socialist"
	| "technocracy"
	| "military"
	| "authoritarian"

export type Politics = {
	government: GovernmentId,
	approval: number, -- 0..100
	stability: number, -- 0..100
	corruption: number, -- 0..100
	taxRate: number, -- 0..1
	activeLaws: { [string]: boolean },
	nextElection: number, -- os.time(), 0 if not applicable
}

export type Economy = {
	gdp: number,
	gdpHistory: { number }, -- rolling window for graphs
	treasury: number,
	debt: number,
	inflation: number, -- annualised %, e.g. 2.5
	interestRate: number, -- %
	lastTickIncome: number,
	lastTickExpense: number,
}

export type Research = {
	unlocked: { [string]: boolean },
	current: string?, -- tech id in progress
	progress: number, -- points accumulated toward `current`
	points: number, -- unspent research points
}

-- Standing armed forces. Unit counts; strength is derived from them + tech.
export type Military = {
	army: number,
	navy: number,
	air: number,
}

-- Foreign relations. `allies` maps another nation's id (as a string) to true.
export type Diplomacy = {
	allies: { [string]: boolean },
}

-- The full authoritative state for a single nation. This is what the server
-- simulates, saves, and (in a filtered form) replicates to the owning client.
export type Nation = {
	ownerId: number, -- Player.UserId
	name: string,
	founded: number, -- os.time()
	resources: ResourceBag,
	buildings: { [string]: Building },
	population: Population,
	politics: Politics,
	economy: Economy,
	research: Research,
	military: Military,
	diplomacy: Diplomacy,
	territory: { regions: { string } },
	flags: { [string]: boolean }, -- one-time event / tutorial markers
}

-- The persisted profile envelope. `schemaVersion` drives data migration.
export type Profile = {
	schemaVersion: number,
	createdAt: number,
	lastPlayed: number,
	playtime: number,
	nation: Nation,
}

-- Standard result envelope returned across the network boundary.
export type NetResult = {
	ok: boolean,
	error: string?,
	data: any?,
}

-- Building definition (static config, see Config/Buildings.luau).
export type BuildingDef = {
	kind: string,
	displayName: string,
	category: string,
	description: string,
	footprint: { w: number, h: number }, -- grid tiles
	requiresTech: string?,
	maxLevel: number,
	cost: { [number]: ResourceBag }, -- cost per level (1-indexed)
	upkeep: ResourceBag, -- per economic tick, at level 1
	produces: ResourceBag, -- per economic tick, at level 1
	jobs: number, -- staffing demand at level 1
	powerDraw: number, -- energy consumed while active
	powerSupply: number, -- energy produced (for plants)
	happiness: number, -- flat contribution to citizen happiness
	housing: number?, -- residents supported (housing buildings)
	education: number?, -- education service points
	health: number?, -- health service points
}

-- Technology definition (Config/Technologies.luau).
export type TechDef = {
	id: string,
	displayName: string,
	branch: string,
	description: string,
	cost: number, -- research points
	requires: { string }, -- prerequisite tech ids
	unlocksBuildings: { string },
	modifiers: { [string]: number }, -- named economy/politics multipliers
}

return {}
