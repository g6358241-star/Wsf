# Phase 1 — Project audit (MyGame.rbxlx)

Audited on 2026-11-12 from the place file the owner supplied (37 MB). Every script was extracted to
`legacy/place-scripts/` (29 scripts, ~3,700 lines) so changes can be reviewed as diffs. The tools used
are in `tools/` (`lune run tools/audit-place <file>`, `tools/audit-map`, `tools/extract-scripts`).

## 1. Inventory

### Map — `Workspace.CloudHarbor` (preserve; refine, don't rebuild)
| Part | Contents |
|---|---|
| Layout | Central **CompassPlaza** at (0,40,0) plus four market islands (Tidal Market, Sunsail Row, Cloud Garden, North Dock) and four terraces, joined by four bridges at ±61 studs on each axis |
| Booths | **48** identical booth models (counter, canopy, sign board, canvas, plaque, ProximityPrompt), 38 parts each, arranged along the four market sides |
| Landmarks | Four market gateways, WelcomeSign, StillwaterFountain (711 parts), The Wayfarer Airship |
| Decor | Compass, benches, trees, 24 lantern models; `HarborEnvironment2026` adds pergolas/foundations |
| Spawn | `HarborArrival` at (0,42,-24) |
| Palette | Teal `#2f9493`, gold `#cca45b`, deep teal `#1d414a`, ivory `#fdf5df`; Plastic / Metal / Marble |
| Lighting | Voxel, brightness 2.2, Atmosphere, Bloom, ColorCorrection, SunRays, DepthOfField, Sky, Clouds |

The map already suits the brief: wide plaza, separate market streets, clear booth rows, bridges as natural
routes. Gaps: **no authored NPC waypoints**. `NPCService` generates ~36 markers from hard-coded offsets
around the plaza, so there are no designed queue/inspection spots in front of booths.

Other content: `Workspace.Map` (213 instances, mostly empty `Stage1–5` folders) and **~10,000 instances of
backups in ServerStorage** (`OldMap_Backup`, `HarborEnvironmentBackup2026`, `MapCleanup_Backup`). These make up most of
the file size; nothing references them at runtime. Recommendation: keep them until the owner confirms, then export to a
separate file.

### Scripts
| Location | Purpose |
|---|---|
| `HarborServer/Main` | Single RemoteEvent `HarborGame.Action`, token-bucket rate limit, action routing |
| `HarborServer/Profiles` | DataStore session lease, all-or-nothing draft mutations, durable receipts, outbox transfers, autosave, BindToClose |
| `HarborServer/Booths` | Claim/release/edit of the 48 booths, one per player, proximity checks, filtered booth text |
| `HarborServer/NPCService` + `NPC` | Pooled 12–16 R15 visitors, PathfindingService with throttled computes, stuck/fall recovery, chat bubbles, `VisitBooth` approach hook |
| `HarborServer/Donations` | Player→player donations; **timer loop that makes NPCs grant 1–5 D** |
| `HarborServer/Economy` | Daily reward, play-time coins, quests, cosmetics shop, leaderstats |
| `HarborServer/Purchases` | `ProcessReceipt`, Supporter pass, Robux Transfers (disabled) |
| `HarborServer/Boards`, `Social` | Global ordered-DataStore leaderboards (players only), announcements/emotes |
| `HarborShared/Config`, `Rules`, `NPCPhrases` | Settings, pure reward rules, chat lines |
| `Shared/*` | Map tooling (redesign, repair, align, cleanup, water level) |
| Client | `NeonSidebar` (visual-only menu), `CurrencyHUD`, donation toast/effects, ambience, fountain |

## 2. Status against the design brief

**Implemented and worth keeping**
- Session-leased, all-or-nothing profile persistence with receipt idempotency (`Profiles`) — meets §8.2.
- Server-validated booth claim/release, one booth per player, release on leave (`Booths`) — §4.1.
- Robust NPC locomotion: pathfinding queue, repath, recovery, pooled rigs (`NPCService`) — the right movement layer.
- Single `ProcessReceipt` owner with durable receipts (`Purchases`) — §8.2.
- Remote rate limiting and input validation (`Main`).

**Partially implemented**
- Stand offers: one free-form number (5–10,000). The brief needs a list of preset buttons with no custom entry in V1 (§4.2, §12.12).
- Leaderboard: global, players only. The brief needs a per-server TAB view with NPC Donated/Raised (§7.1).
- Currencies: `DCoins` (test), `Coins`, `Pearls`. **Their mapping to primary/secondary is not defined.**
- Statistics: running totals only; no history, daily chart or 24 h average.

**Conflicts with the brief (must change)**
1. **NPC donations are a timer.** Every 3–7 s a random occupied booth is picked, the nearest idle NPC walks over and
   1–5 D is created from nothing. This breaks §3.5 (separate stages), §12.2 (no timers or pseudo-NPCs) and §12.3 (no passive currency).
2. **Player→player donations and Robux Transfers** exist (`Donate` action, outbox, `PromptRobuxTransferAsync`). V1 excludes them (§1.2).
3. **Pearls sold for Robux** (`SupportSmall`/`SupportLarge` grant Pearls). If Pearls are the secondary currency, this breaks §2.4.
4. **Time-based currency rewards** (play-time coins, daily, quests) are not in the brief, and they mint Pearls outside NPC interactions.
5. **Fixed pool of 12–16 NPCs** vs a dynamic population of up to 100 (§12.2).
6. `NeonSidebar` uses neon gradients and glow strokes, which §12.13 lists as visual "AI slop". Revisit in the UI-concept phase.

**Missing**
NPC wallets/budgets/personalities/archetypes, server wealth profile, NPC-owned stands, NPC→NPC economy,
NPC donation requests with escort and camera focus, relationships/3-day memory, reputation, transaction history, daily chart,
offline earnings, luck cap, VIP pass, primary-currency packs.

## 3. Risks
- **Performance at 100 NPCs.** `NPCService` allows `MaxConcurrentPaths = 2` and runs ground raycasts plus
  `GetPartBoundsInBox` per waypoint. Fine for 16 agents, but path queueing will bottleneck at 100. This must be profiled in
  Studio; the plan is to reuse cached routes between authored waypoints instead of computing every path.
- **Hard-coded waypoint offsets** tie NPC routes to the plaza's CFrame. Authored `NPCWaypoint`-tagged markers
  (approach and queue spots per booth) are needed.
- **37 MB place file** with mostly unused backups slows saves and loads in Studio.
- The test currency `DCoins` is persisted under `HarborProfiles_TestCurrency_v2`; switching to real currencies needs a schema v2 migration.
