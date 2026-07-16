# Architecture

Project Nexus is a **server-authoritative** simulation. The server owns every
number; clients render a filtered copy and send requests that the server is free
to reject. This document explains how the pieces fit.

## Layers

### Shared (`ReplicatedStorage.Nexus`)
Pure, side-effect-light modules usable from both sides:

- **Types** — every cross-boundary shape (`Nation`, `Building`, `Profile`, …).
- **Constants** — schema version, tick cadences, grid size, DataStore names.
- **Config/** — the game as data: `Buildings`, `Technologies`, `Governments`,
  `Laws`, `Resources`, and `Balance` (all tunable numbers).
- **Net** — the single guarded client↔server gateway (see below).
- **NetRoutes** — canonical route-name constants shared by both sides.
- **Signal / TableUtil / ResourceMath / Logger / WorldGrid** — primitives.

### Server (`ServerScriptService.Nexus`)
A `Framework` service locator with a two-phase lifecycle:

1. **Init** — each service builds its own state; services must not touch each
   other (order is undefined).
2. **Start** — the simulation begins; every service is registered, so a service
   may `Framework.get(...)` (or directly require) any other.

Services reference each other lazily, keeping the load-time dependency graph
acyclic. Each `Start` runs in its own thread, so a service owning a `while` loop
never blocks another.

### Client (`StarterPlayerScripts.Nexus`)
A mirror `ClientFramework` with the same Init/Start contract. `StateController`
is the single sink for replicated state; every panel subscribes to its `Changed`
signal rather than touching the network.

## The network gateway (`Net`)

Everything crosses the wire through **one `RemoteFunction` (`Request`)** and
**one `RemoteEvent` (`Push`)**, multiplexed by a string `route`. Benefits:

- Adding a message never adds an Instance an exploiter can probe.
- One choke point enforces **per-player, per-route token-bucket rate limiting**.
- Payloads are shape/size-checked before any handler runs.
- Handlers are wrapped so a thrown error becomes a clean `{ ok = false }`
  envelope, never a leaked traceback or a dropped invocation.

`Net` detects server vs client via `RunService` and exposes only the safe API for
that side (`handleRequest`/`fireClient` on the server; `request`/`onEvent` on the
client).

## Tick order (the heartbeat)

`EconomyService` is the **master tick** (`Constants.ECONOMY_TICK`, 5s). For each
live nation, in a fixed order:

1. `Modifiers.resolve(nation)` — merge government + techs + laws into one table.
2. `CityService:ComputeStats` — aggregate production, upkeep, power, jobs,
   housing and services from every building (never trusts stored derived values).
3. Employment, GDP, taxation, enterprise income.
4. Move resources: money (deficits → debt, surpluses repay debt), materials,
   food (shortfall reported), research, influence, net power. Update inflation.
5. `CitizenService:Tick` — education/health/happiness/unrest, then migration.
6. `ResearchService:Tick` — accrue points, advance the active tech.
7. `CityService:TickCondition` — buildings decay if maintenance was unaffordable.
8. Package derived flows and hand them to `ReplicationService`.

`PoliticsService` runs on its own slower cadence (`POLITICS_TICK`, 30s) for
approval, stability, corruption drift and elections.

Because Luau is cooperative and none of the per-tick math yields, a tick is
atomic with respect to request handlers — no locks needed.

## Replication

Services never call `Net` for state. They mutate the authoritative nation and
call `ReplicationService:MarkDirty(player)`. A 0.5s flush deep-copies each dirty
nation (plus the latest derived stats) and pushes it, so a burst of ten
placements replicates once. The client can never hold a live reference into
server tables.

## Persistence (`DataService`)

An original, session-safe profile store:

- **Session locking** via `UpdateAsync` — one live server owns a profile; a stale
  lock (older than `SESSION_LOCK_STALE_AFTER`) is reclaimable, a fresh foreign
  lock makes the join retry with backoff.
- **Reconciliation** merges an old save against the current default template, so
  new fields appear with defaults without wiping player progress.
- **Migration** — `schemaVersion` drives ordered upgrade steps.
- **Retry + exponential backoff** on every DataStore op; **backups** mirrored to a
  second store; **autosave** plus a `BindToClose` flush.
- Saves deep-copy the profile first so a concurrent tick can't mutate a table
  mid-serialisation.
- A Studio **in-memory mock** activates when the DataStore API is unavailable.

## Security model

- Client requests are suggestions; the server proves each field valid
  (`Util/Validation`) and re-checks affordability, tech gating, grid bounds and
  overlaps before mutating anything.
- Resources only change through `ResourceMath` on server-owned tables.
- Rate limits bound request spam per route.
- No client-authored value (money, buildings, tech, votes) is ever trusted.
