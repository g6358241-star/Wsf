# Architecture & phased plan (proposal)

## Principle
Keep the existing `HarborServer` systems (profiles, booths, NPC locomotion, purchases) and the CloudHarbor map.
Add the missing simulation as **`ServerScriptService.NpcCore`**: pure, engine-agnostic Luau modules
(`src/server/Logic`, `src/server/Config`). The game and the headless simulator run the same code, so balance
numbers measured offline are the numbers players get.

```
HarborServer (existing, extended)            NpcCore (new, pure logic)
───────────────────────────────              ─────────────────────────
NPCService   movement/pathfinding  ◄──────── NpcBrain      decisions: pass → inspect → donate/decline,
NpcDirector* spawns, schedules     ────────►                refill, claim stand, request, depart
Booths       stands + offers list  ────────► NpcFactory    wealth tier, archetype, traits, wallet, offers
Profiles     persistence/receipts  ◄──────── Ledger / Transactions  atomic transfers, mint allow-list
Economy      player money ops      ◄──────── SecondaryCurrency, OfflineEarnings, IncomeStats,
Requests*    ask → follow → donate ◄────────   Relationships, Luck
Leaderboard* per-server TAB        ◄──────── NpcBrain.donated/raised
(* = new HarborServer module)               Config/*  every tunable value, all marked PROPOSAL
```

### Money rules (enforced in code)
- Currency is created only through the allow-list in `Config/Economy.MintReasons`: secondary reward, Robux purchase,
  offline earnings, starting grant, NPC starting wallet. NPCs cannot mint anything after they spawn.
- Every transfer validates integer > 0, sufficient balance and a fresh transaction id. Replays return `Duplicate` with no effect.
- Player-side operations run inside `Profiles.mutate` (non-yielding draft), so they are all-or-nothing and saved under the existing lease.
- The client only sends intent (stand id, offer index). Amounts, owners, budgets and rewards are always looked up server-side.

### Save schema v2 (proposal, extends the existing profile)
```
Primary, Secondary            -- integers (mapping from DCoins/Coins/Pearls: owner decision)
Stand = { Offers = {int} }    -- last preset list, restored on the next claim
Stats = { hourly = {[hour]=n}, daily = {[YYYY-MM-DD]=n}, history = {<=200 records}, nextId }
Offline = { lastSeenAt, avgHourlySnapshot, lastCreditedAt, lastResult }
Memories = { [npcId] = { s, t, n, e = {<=4 codes} } }   -- <=300 NPCs, expire 3 days after t
Reputation = { score, log = {<=20 reasons} }
Vip, Receipts, Inventory, Equipped  -- existing fields kept
```

## Phases (brief §9.2) and status
| # | Phase | Status |
|---|---|---|
| 1 | Project audit | **Done**: `docs/AUDIT.md` |
| 2 | Visual direction: 2–3 UI concepts | Next; needs owner choice before UI work |
| 3 | Core foundation | **Logic done and tested** (this commit); game wiring pending decisions below |
| 4 | Player & NPC stands | Booths: preset offer list editor, NPC ownership, appeal attribute |
| 5 | NPC world simulation | `NpcDirector` + `NPCService` dynamic pool; replace the timer loop in `Donations` |
| 6 | NPC→NPC economy | Logic done (`Transactions.npcDonate`); needs world wiring |
| 7 | Requests & social | Logic done (request chance, persistence, decline reactions, memory); needs `Requests` + camera |
| 8 | Statistics & offline | Logic done (`IncomeStats`, `OfflineEarnings`); needs profile v2 + UI |
| 9 | UI & progression | After concept selection |
| 10 | Monetization | VIP pass, primary packs, luck cap (`Luck` done) |
| 11 | QA & balancing | `sim/balance` exists; Studio profiling of 100 NPCs still to do |
