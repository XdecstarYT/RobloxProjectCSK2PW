# Roadmap

Project Nexus is built in phases. Each phase ships production-ready systems that
stay compatible with everything before it. Phase 1 is complete in this repo.

## ✅ Phase 1 — Foundation & core loop (this repo)
Engine (framework, guarded networking, session-safe persistence) plus the core
gameplay vertical slice: economy, city building, citizens, politics, research,
a functional HUD and a client-rendered 3D city.

**Extension points already reserved** for later phases:
- `NetRoutes` includes `PROPOSE_TRADE`, `RESPOND_TRADE`, `TRADE_INBOX`.
- `Types.Nation` carries a `territory.regions` list.
- `Types.Nation.flags` is a general one-time-event/tutorial marker bag.
- The modifier resolver already supports arbitrary named modifiers, so new
  techs/laws need no code changes.

## Phase 2 — Diplomacy & multiplayer trade
- `DiplomacyService`: player-to-player trade offers (resource-for-resource),
  validated escrow so neither side can duplicate resources.
- Alliance/embassy relationship state on the nation; influence spent on treaties.
- Client `DiplomacyController`: an inbox panel driven by the reserved routes.
- **Security focus:** atomic two-sided trade settlement, offer expiry, anti-spam.

## Phase 3 — AI nations
- `AIService`: server-owned non-player nations that grow, research and trade using
  the same authoritative systems (no special-cased economy).
- Difficulty/strategy profiles (economic, technological, diplomatic).
- AI participation in the Phase 2 trade market and global events.

## Phase 4 — Territory & expansion
- Region graph with population, resources, terrain and strategic value.
- Peaceful expansion via development, influence and agreements; optional,
  server-toggleable conflict resolution.
- Map/minimap UI over the region graph.

## Phase 5 — Military (optional per server)
- Strategy/logistics-first: army/navy/air as supply-and-planning systems rather
  than twitch combat. Recruitment, bases, defense, a military economy.
- Fully gated behind a server setting so peaceful servers are unaffected.

## Phase 6 — Depth, events & polish
- Dynamic crises and world events (economic shocks, disasters, movements).
- Economy graphs, advisor prompts, expanded citizen simulation.
- Console/gamepad navigation pass; accessibility and localization.

## Ongoing — Environment & assets (Toolbox usage policy)
Toolbox assets are used for **visuals only**, never gameplay logic. Before use:
inspect the asset, strip all scripts, remove stray RemoteEvents/RemoteFunctions
and hidden objects, optimize part/poly counts, and organize it under a clear
folder. Prefer Roblox-made or trusted-creator, optimized models.

Good early searches and where they go:
- *"low poly modular building pack"* → swap the placeholder city parts in
  `WorldController` for real models keyed by building `kind`.
- *"low poly tree / park props"* → decorate empty tiles and parks.
- *"UI icon pack (flat)"* → replace the text glyphs in the resource chips.
- *"ambient city / strategy music loop"* → `SoundService` background track.

Because rendering is client-side and keyed off building `kind`, adopting models
is a drop-in change with no impact on the authoritative simulation.
