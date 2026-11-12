# Architecture

The existing `HarborServer` systems and the CloudHarbor map are kept. The NPC simulation is added as pure,
engine-agnostic Luau in `NpcCore`, plus one new server module (`NpcDirector`) that connects it to the existing
movement, booth and profile code. The game, the headless integration test and the balance simulator all run the
same NpcCore code.

```
ServerScriptService.HarborServer (existing, edited)       ServerScriptService.NpcCore (new, pure logic)
──────────────────────────────────────────────            ───────────────────────────────────────────────
Main          remotes, rate limit, action routing          Config/  Economy, Npc, Offline, Luck, Persistence
NPC (script)  starts NPCService + NpcDirector               Logic/   NpcBrain      pass → inspect → donate/decline,
NpcDirector*  NPC population, wallets, decisions  ───────►           refill, claim stand, request, depart
NPCService    pathfinding, booth approach, despawn                    NpcFactory    wealth tier, archetype, traits, offers
Booths        player/NPC stand ownership, preset offers               Ledger        atomic transfers, mint allow-list
Economy       receiveNpcDonation (NPC debit + profile credit)         Transactions  NPC donations, player→NPC donations
Profiles      save v2, migration, history, legacy drain               SecondaryCurrency, OfflineEarnings, IncomeStats,
Donations     toasts and booth effects only                           Relationships, Luck, Rng
Purchases     Robux packs → Coins only
Boards/Social unchanged apart from Coins boards               (* = new module)
```

## Money flow (enforced in code)
- **NPC world ledger** (`NpcDirector`): an NPC's starting wallet is the only way money enters (`MintReasons.NpcSpawnWallet`).
  NPCs move money wallet → budget by their own choice, donate from the budget, and take their funds with them when they leave.
  `NpcDirector:audit()` checks every 30 s that minted = held by NPCs + left with NPCs + received by players.
- **NPC → player:** `Economy.receiveNpcDonation` debits the NPC in the ledger, then credits the profile with
  `Profiles.creditFromNpc` (non-yielding). If the credit fails, the ledger transfer is refunded. The transaction id is
  consumed either way, so it can never be replayed.
- **Player rewards:** playtime, daily, quests and Robux packs go through `HarborShared.Rules.credit`, which accepts only Coins
  and legacy Pearls. DCoins are created only by `Transactions.playerDonateToNpc` (secondary reward), which arrives with the
  NPC request flow.
- The client sends only intent: booth id, sign text, a list of preset amounts. Owners, budgets, amounts and rewards are
  looked up or validated on the server.

## NPC donation requests (Requests module)
1. An NPC that owns a stand checks every 30 s whether it wants to ask a player (`Request.chancePerCheck` × sociability;
   one request per player at a time, then a cooldown).
2. It walks up to the player; the client shows Accept/Decline above it and zooms the camera slightly. No answer within
   20 s closes the prompt with no penalty.
3. Decline: the NPC reacts according to its personality (calm, upset, surprised, joke) and remembers it.
4. Accept: the NPC walks back to its stand and calls the player if they lag. The donation panel opens only when the
   player reaches that stand and lists only that NPC's own amounts. Picking one runs `Economy.playerDonateToNpc`:
   Coins debited, DCoins granted by the fixed formula, an optional return gift, all in one non-yielding step.
5. Accept but never come: after the grace period plus the NPC's patience it gives up, is offended, and remembers it.
   Offended NPCs donate to the player's stand less willingly and give return gifts less often.
The client only sends the request id, accept/decline and an offer index; everything else is checked on the server.

## Save schema v2
New fields on top of v1 (everything from v1 is kept, including legacy `Pearls`, `Donated`, `Received`, `Outbox`):
```
CoinsRaised, CoinsDonated          -- lifetime Coins stats (leaderboard Raised/Donated)
Stand = { Offers = {int} }         -- last listed presets, restored on the next claim
Stats = { hourly, daily, history (<= 200 records), nextId }   -- history, daily chart, 24 h average
LegacyDCoins, MigratedTestDCoins   -- optional quarantine of pre-decision DCoins (off by default)
Memories = { [personaId] = { s, t, n, e } }   -- NPC opinion, last interaction, name, last 4 events; expires after 3 days
Reputation = { score, log }        -- overall reputation and the last 20 reasons it changed
Offline = { lastSeenAt, avgHourly, last }   -- snapshot taken at every save; payout credited inside the load write
```
v1 saves load and are migrated in memory; corrupt economic data still aborts the load instead of being overwritten.

## Phases (brief §9.2)
| # | Phase | Status |
|---|---|---|
| 1 | Project audit | Done: [AUDIT.md](AUDIT.md) |
| 2 | Visual direction | 3 concepts ready: [UI_CONCEPTS.md](UI_CONCEPTS.md). **Waiting for owner choice** |
| 3 | Core foundation | Done: currencies, ledger, save v2, migration |
| 4 | Player & NPC stands | Server done (preset offers, NPC ownership, reserved booths). Editor UI waits for the concept choice |
| 5 | NPC world simulation | Done in code, integration-tested headless. **Studio profiling pending** ([STUDIO_TESTING.md](STUDIO_TESTING.md)) |
| 6 | NPC→NPC economy | Done (same rules, Donated/Raised published for the TAB list) |
| 7 | Requests & social | **Done in code**: request flow (approach → Accept/Decline → follow → donate at the NPC's stand), personality reactions, 3-day memory, reputation with reasons, returning NPCs. Frequency still under evaluation ([REQUEST_FREQUENCY.md](REQUEST_FREQUENCY.md)) |
| 8 | Statistics & offline | History, daily totals and **offline earnings** (credited on join) done; statistics screen waits for the UI concept |
| 9 | UI & progression | After concept selection |
| 10 | Monetization | Packs → Coins only; VIP and luck cap not wired yet |
| 11 | QA & balancing | Unit + integration tests and simulators exist; Studio measurements pending |
