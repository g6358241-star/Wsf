# Balance simulation — 24 runs × 6h per scenario, 48 stands

All parameters are PROPOSALS from src/server/Config. Times are simulated, not promises to players.

## random tier (80/17/3)

| Listing | Donations/h | Median gap (min) | Passers before 1st donation (p10/median/p90) | Avg gift | NPC→NPC/h | Requests/h | Peak NPCs |
|---|---|---|---|---|---|---|---|
| Only 100 | 1.62 | 20.7 | 4 / 37 / 136 | 100 | 138.1 | 10.7 | 84 |
| Only 1,000 | 0.21 | 124.6 | 12 / 221 / none | 1000 | 140.2 | 10.6 | 88 |
| Only 10,000 | 0.02 | – | 353 / none / none | 10000 | 138.8 | 10.8 | 85 |
| Small ladder 5–100 | 4.33 | 8.7 | 3 / 19 / 36 | 37 | 137.8 | 10.6 | 83 |
| Wide 10–10,000 | 3.63 | 10.4 | 4 / 16 / 44 | 102 | 138.1 | 10.6 | 85 |

## Ordinary server

| Listing | Donations/h | Median gap (min) | Passers before 1st donation (p10/median/p90) | Avg gift | NPC→NPC/h | Requests/h | Peak NPCs |
|---|---|---|---|---|---|---|---|
| Only 100 | 1.33 | 28.7 | 3 / 24 / 111 | 100 | 139.6 | 10.6 | 87 |
| Only 1,000 | 0.16 | 120.4 | 50 / 299 / none | 1000 | 136.0 | 10.6 | 81 |
| Only 10,000 | 0.01 | – | none / none / none | 10000 | 137.4 | 10.5 | 83 |
| Small ladder 5–100 | 3.92 | 10.2 | 2 / 12 / 56 | 31 | 141.4 | 10.7 | 83 |
| Wide 10–10,000 | 3.60 | 11.1 | 5 / 16 / 48 | 105 | 139.5 | 10.7 | 90 |

Conservation check passed for every run (no NPC currency created or lost).

## Reading the results against the brief's references (§3.5, §4.3)
| Reference | Result with current proposals |
|---|---|
| ~10–15 passers before the first donation (ordinary traffic) | Median 12–19 for typical multi-button listings; wide spread (p10 2–5, p90 36–56), so players can be lucky or wait |
| 100 roughly every 10–30 min | Median gap 21–29 min |
| 1,000 roughly every 30 min–2 h | Median gap ~120 min; on the slow edge — raise generosity or budgets if the owner wants it faster |
| 10,000 rare, luck-driven | ~0.01–0.02 per hour; mostly from rare NPCs or wealthy servers |
| Up to 100 NPCs | Arrival rate 7/min gives 80–90 concurrent at peak, under the 100 cap |

**Open item:** NPC requests to the player run about 10/hour, limited by the 4-minute cooldown. Request frequency
is an open owner decision (§10). If that feels too frequent, lower `Request.chancePerCheck` or raise `playerCooldownSeconds`.

Listing several amounts converts better than one large amount because each NPC picks the listed amount closest to
what it comfortably gives. Presentation (appeal) moves visit odds by at most ±12.5% and donation odds by at most ±10%, so
plain stands remain viable (§3.4).

## Secondary-currency reward examples (proposal)
`reward = clamp(floor(amount × 0.10 × tier + 1), 1, 5000)` with tier ×1.0 / ×1.1 (≥100) / ×1.2 (≥1,000) / ×1.3 (≥10,000).

| Donation | 5 | 10 | 50 | 99 | 100 | 500 | 1,000 | 5,000 | 10,000 | 100,000 |
|---|---|---|---|---|---|---|---|---|---|---|
| Secondary | 1 | 2 | 6 | 10 | 12 | 56 | 121 | 601 | 1,301 | 5,000 (cap) |

Reproduce with `lune run sim/balance 6 24` (seeded and deterministic).
