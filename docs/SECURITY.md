# Security model

Project Nexus is **server-authoritative**. The server owns every number; the
client renders a filtered copy and sends requests the server is free to reject.
This document is the checklist the codebase is held to.

## Principles

- **Never trust the client.** Every request is validated server-side before it
  touches authoritative state. Client-side checks (affordability, grid validity)
  only drive UI affordances.
- **One guarded gateway.** All traffic goes through `Net` (one RemoteFunction +
  one RemoteEvent, multiplexed by route). Every route has **per-player,
  per-route token-bucket rate limiting**, payload shape/size guards, and handlers
  wrapped so a thrown error becomes a clean `{ ok = false }` — never a leaked
  traceback or a dropped invocation.
- **Resources change only through `ResourceMath` on server-owned tables**, and
  money is floored at zero (deficits become debt, never negative balances).

## Per-surface guards

| Surface | Validation |
| --- | --- |
| **Build / upgrade / demolish / repair** | building kind exists; tech unlocked; footprint in-bounds and non-overlapping; cost affordable; building id belongs to the caller's nation |
| **Politics** (tax/gov/law/rename) | tax clamped to the government's ceiling; government/law ids validated; law tech + forbidden-government checks; name stripped of control chars and length-capped |
| **Research** | tech id exists; not already unlocked; full prerequisite DAG enforced |
| **Trade** | give/receive bags sanitised (whitelisted resources, non-negative integers, capped); proposer's `give` escrowed on send so it can't be double-spent; only the recipient may accept; only the proposer may cancel; recipient must afford `receive`; offers expire and refund; **max 10 open offers per proposer** |
| **Alliances** | mutual; can't ally yourself or an existing ally |
| **Territory** | region id exists; adjacency + scaling influence cost; forceful annexation only targets **AI** regions, only when military is enabled, and costs strength + units |
| **Military** | gated by `ServerSettings.militaryEnabled`; unit id + tech gate; count bounded; cost affordable |
| **Market** | resource whitelisted; amount a bounded positive integer; buys check funds, sells check the actual stockpile; a buy/sell spread prevents instant arbitrage |
| **Objectives** | evaluated and rewarded **server-side only**; completion persisted so a reward is never paid twice |

## Data safety

- **Session locking** ensures one live server owns a profile at a time (no forks
  or rollbacks from server-hopping).
- Saves **deep-copy** the profile first so a concurrent simulation tick can't
  mutate a table mid-serialisation.
- **Reconciliation + versioned migrations** upgrade old saves without wiping
  progress (`schemaVersion`, `DataService.MIGRATIONS`).
- Retry with exponential backoff on every DataStore op; a backup store mirrors
  the last-good record; autosave plus a `BindToClose` flush.

## Notes / future hardening

- Nation names should additionally pass `TextService:FilterStringAsync` before
  being shown to other players (noted at the call site).
- Consider global DataStore request budgeting under very high concurrency.
- PvP aggression is disabled by default (`ServerSettings.pvpEnabled`); enabling
  it would require its own validation pass.
