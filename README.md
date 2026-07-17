# Project Nexus — Roblox Nation Simulator

Grow a single settlement into a superpower. **Project Nexus** is an original
grand-strategy / city-builder / nation-simulator for Roblox: build cities, run an
economy, govern a populace, research technology, and steer your nation's politics
— every decision feeding back into the simulation.

This repository contains the **full game**: the engine plus every gameplay
system, all real, non-placeholder Luau that runs and interacts today.

---

## What works right now

| System | Status | Notes |
| --- | --- | --- |
| **Server framework** | ✅ | Two-phase Init/Start service locator, no circular requires |
| **Secure networking** | ✅ | One guarded gateway, per-player/route token-bucket rate limiting, uniform result envelope |
| **Data persistence** | ✅ | Session locking, autosave, reconciliation, migration, retries+backoff, backups, Studio in-memory fallback |
| **Economy** | ✅ | GDP, taxes, treasury, debt & interest, inflation, materials/food/power, military upkeep, region income |
| **City building** | ✅ | Server-authoritative place / upgrade / demolish / repair on a grid, with footprints & power |
| **Citizens** | ✅ | Population, employment, happiness, education, health, unrest, migration |
| **Politics** | ✅ | Tax, 7 government types, toggleable laws, approval/stability/corruption, elections |
| **Research** | ✅ | Prerequisite-gated tech tree (incl. military branch) with global modifiers |
| **Diplomacy & trade** | ✅ | Escrowed resource-for-resource trades, alliances, inbox, offer expiry (players + AI) |
| **AI nations** | ✅ | Five rivals with strategy archetypes; grow, research, expand, trade & ally |
| **Territory** | ✅ | Shared world map; claim regions with influence (adjacency + scaling cost); per-region income |
| **Military (optional)** | ✅ | Recruit army/navy/air, upkeep, strength; forceful expansion vs AI; gated by a server setting |
| **Global market** | ✅ | Dynamic supply/demand prices with a buy/sell spread; buy and sell commodities for money |
| **World events** | ✅ | Periodic national events and rarer global events with real consequences |
| **Objectives** | ✅ | 12 milestone goals evaluated server-side with one-time rewards; persisted, never paid twice |
| **Leaderboard** | ✅ | Live global power ranking of every nation (players + AI) |
| **Client UI** | ✅ | HUD plus panels for build, politics, research, economy, diplomacy, territory, military, market, goals, ranks & settings |
| **3D world & camera** | ✅ | Procedural terrain continent (hills, coastline, Terrain water), roads, trees & rocks, day/night cycle, a buildable neon city, physical region zones, GTA-style fly-to, RTS camera |
| **Cross-platform** | ✅ | Mouse, touch (reticle + Place button, pinch-zoom) and gamepad (stick pan/zoom, A/B/R1) controls |
| **Onboarding & settings** | ✅ | Interactive step-by-step tutorial (persisted flag, replayable) and an options menu (volume, mute, effects) |
| **Audio scaffold** | ✅ | Music/SFX buses wired to clicks & notifications; paste asset ids into `Config/Audio` to enable |

Every important system is original, server-authoritative code. See
[`docs/ROADMAP.md`](docs/ROADMAP.md) for build history and future ideas, and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the data flow and security model.

---

## Getting it into Roblox Studio

### Option A — just open the place file (no Rojo)

Download **[`Nexus.rbxlx`](Nexus.rbxlx)** and **double-click it** (or in Studio:
*File → Open from File…*). That's it — the whole game is inside. To rebuild the
place after editing the source, no toolchain is needed:

```sh
python3 tools/build_place.py     # regenerates Nexus.rbxlx from src/
```

> Enable **Game Settings → Security → Studio Access to API Services** for saving
> to work; otherwise DataService uses an in-memory mock and progress won't persist.

### Option B — live-sync with Rojo (for ongoing development)

The project also syncs with [Rojo](https://rojo.space).

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit):
   ```sh
   rokit install      # installs rojo, stylua, selene per rokit.toml
   ```
   (Or install Rojo directly — any 7.x works.)

2. Serve and connect from the Roblox Studio Rojo plugin:
   ```sh
   rojo serve
   ```
   `default.project.json` maps the tree:
   - `src/shared`  → `ReplicatedStorage.Nexus`
   - `src/server`  → `ServerScriptService.Nexus`
   - `src/client`  → `StarterPlayer.StarterPlayerScripts.Nexus`

3. Press **Play**. On first join your nation is created with a starting treasury,
   population and a blank grid. Open **🏗 Build** and place a Housing Block, a
   Coal Power Plant and a Farm to get your economy turning.

> **DataStores in Studio:** if *Studio Access to API Services* is off, DataService
> automatically falls back to an in-memory mock so the whole game is still
> playable and testable. Turn API access on to exercise real saving/loading.

---

## Playing

- **Pan** the camera: right-mouse drag, WASD/arrows, or one-finger drag (touch).
- **Zoom**: mouse wheel.
- **Build**: open the Build menu, pick a building, move the ghost over the grid
  (green = valid, red = blocked/too poor), **click** to place, **R** to rotate,
  **Esc** to cancel.
- **Manage a building**: click it to Upgrade / Repair / Demolish.
- **Govern**: the **🏛 Politics** panel adjusts taxes, switches government, and
  enacts laws. The **🔬 Research** panel drives the tech tree.

Keep power positive, feed your people, and don't tax them into revolt.

---

## Testing checklist (manual QA)

1. **Join** → nation snapshot arrives, HUD populates (see console `client online`).
2. **Place** a building you can afford → treasury drops, part appears, notification fires.
3. **Place** on an occupied/edge tile → ghost turns red, server refuses.
4. **Overspend** attempt → "Cannot afford" notification, no state change.
5. **Wait a few ticks** → GDP/budget update; build power + food to go net-positive.
6. **Research** a tech → progress bar fills, building unlocks in the Build menu.
7. **Raise tax** past ~35% → happiness and approval slide over the next ticks.
8. **Rejoin** (with API access on) → your city, treasury and tech persist.

---

## Architecture at a glance

```
ReplicatedStorage.Nexus (shared)   ServerScriptService.Nexus (server)
 ├─ Types, Constants, Logger         ├─ Framework (service locator)
 ├─ Signal, TableUtil, ResourceMath  ├─ Services/
 ├─ Net (guarded gateway)            │   DataService  (persistence)
 ├─ NetRoutes, WorldGrid             │   ReplicationService (state → client)
 └─ Config/                          │   EconomyService (master tick)
     Balance, Resources, Buildings   │   CityService / CitizenService
     Technologies, Governments, Laws │   PoliticsService / ResearchService
                                     │   NotificationService
StarterPlayerScripts.Nexus (client)  └─ Util/ Modifiers, Validation
 ├─ ClientFramework
 ├─ Controllers/ State, Hud, Build, World, Politics, Research, Notification
 └─ UI/ Theme, Create, Format
```

The server is the sole authority. Clients send **requests**; the server
validates, mutates the authoritative nation, and pushes filtered snapshots back.
See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the data flow, tick order,
and security model.

---

## Design principles

- **Never trust the client.** Every mutation is re-validated server-side; the
  client's checks only drive UI affordances.
- **Data-driven.** Buildings, tech, governments, laws and all balance numbers
  live in `src/shared/Config` so designers tune without touching systems.
- **Typed Luau + modular services** with a strict Init/Start lifecycle and no
  circular requires.
- **Original gameplay code.** Toolbox assets are welcomed for *visuals* only
  (see the roadmap); every economy/politics/data/network system here is bespoke.
