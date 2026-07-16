# Roadmap

Project Nexus was built in phases. **All planned phases are complete** — the
whole game is in this repo. Each phase stayed compatible with everything before
it (save reconciliation covers the new `military`/`diplomacy` state, and every
new system reuses the existing economy, modifier and networking layers).

## ✅ Phase 1 — Foundation & core loop
Engine (framework, guarded networking, session-safe persistence) plus the core
gameplay vertical slice: economy, city building, citizens, politics, research, a
functional HUD and a client-rendered 3D city.

## ✅ Visual pass
Cinematic lighting, atmosphere and post-processing; stylized multi-part buildings
with neon accents; a district-grid ground with surrounding water; UI gradients,
animated panels and selection highlighting.

## ✅ Phase 2 — Diplomacy & multiplayer trade
`WorldService` nation registry + power-ranked directory; `DiplomacyService`
escrowed resource trades and alliances with an inbox and offer expiry; client
diplomacy panel and live leaderboard.

## ✅ Phase 3 — AI nations
`AIService` runs five rival nations with strategy archetypes (economic,
technological, diplomatic, militarist, balanced) that share the exact Nation
shape as players — they grow, research, expand, and propose trades/alliances.

## ✅ Phase 4 — Territory & expansion
Shared world map (`Config/Regions`) with adjacency and per-region income;
`TerritoryService` claim authority with influence cost scaling and persistence
reconciliation; client map panel.

## ✅ Phase 5 — Military (optional per server)
`MilitaryUnits` config + `MilitaryService` recruitment/disband, money upkeep,
and strength; forceful expansion that only ever targets AI regions; entirely
gated behind `ServerSettings.militaryEnabled` (client hides the UI when off).

## ✅ Phase 6 — Events, leaderboard & onboarding
`EventService` national and global events with real consequences; the live
leaderboard UI; `OnboardingService` first-join tutorial tips guarded by a
persisted flag.

---

## Future ideas (not required for a complete game)
- Richer combat resolution and unit types if a server opts into PvP.
- Region terrain art and a 3D world map instead of the 2D grid panel.
- Persisted AI nations and cross-server world state.
- Economy graphs and an advisor system surfacing recommendations.
- Console/gamepad navigation and localization passes.

## Environment & assets (Toolbox usage policy)
Toolbox assets are for **visuals only**, never gameplay logic. Before use:
inspect the asset, strip all scripts, remove stray RemoteEvents/RemoteFunctions
and hidden objects, optimize part/poly counts, and organize it under a clear
folder. Prefer Roblox-made or trusted-creator, optimized models.

Because building rendering is client-side and keyed off building `kind`
(`WorldController`), swapping the placeholder parts for real models is a drop-in
change with no impact on the authoritative simulation. Good early searches:
*"low poly modular building pack"*, *"low poly trees / park props"*, *"flat UI
icon pack"*, *"ambient strategy music loop"*.
