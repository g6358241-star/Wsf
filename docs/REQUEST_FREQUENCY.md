# NPC request frequency study — 16 runs × 4h per cell, new player (0 starting Coins)

## Engaged player (accepts 70%, follows 90%)

| Setting | Requests/h | Time in requests | Donations/h | Coins spent/h | Coins earned/h (stand + playtime) | Net Coins/h | DCoins/h | Return gifts/h | Ignored after accept/h | Couldn't afford/h |
|---|---|---|---|---|---|---|---|---|---|---|
| A  very frequent (chance 0.050, cooldown 2 min) | 22.4 | 17.7% | 13.0 | 358 | 771 | +427 | 47.8 | 14 | 1.3 | 0.2 |
| B  current draft (chance 0.020, cooldown 4 min) | 10.6 | 8.1% | 5.9 | 138 | 757 | +623 | 18.9 | 4 | 0.7 | 0.0 |
| C  moderate (chance 0.020, cooldown 8 min) | 6.3 | 4.9% | 3.5 | 185 | 793 | +617 | 22.9 | 10 | 0.5 | 0.1 |
| D  occasional (chance 0.010, cooldown 12 min) | 3.9 | 3.2% | 2.3 | 61 | 775 | +717 | 8.2 | 3 | 0.3 | 0.0 |
| E  rare (chance 0.005, cooldown 20 min) | 2.3 | 1.8% | 1.3 | 19 | 788 | +769 | 3.0 | 0 | 0.2 | 0.0 |

## Casual player (accepts 40%, follows 75%)

| Setting | Requests/h | Time in requests | Donations/h | Coins spent/h | Coins earned/h (stand + playtime) | Net Coins/h | DCoins/h | Return gifts/h | Ignored after accept/h | Couldn't afford/h |
|---|---|---|---|---|---|---|---|---|---|---|
| A  very frequent (chance 0.050, cooldown 2 min) | 22.2 | 10.5% | 6.1 | 201 | 805 | +609 | 26.4 | 5 | 2.2 | 0.1 |
| B  current draft (chance 0.020, cooldown 4 min) | 10.5 | 4.7% | 2.7 | 54 | 744 | +692 | 7.7 | 2 | 1.1 | 0.0 |
| C  moderate (chance 0.020, cooldown 8 min) | 6.2 | 2.8% | 1.5 | 65 | 752 | +690 | 8.2 | 3 | 0.6 | 0.0 |
| D  occasional (chance 0.010, cooldown 12 min) | 4.0 | 1.7% | 0.9 | 26 | 762 | +738 | 3.5 | 2 | 0.6 | 0.0 |
| E  rare (chance 0.005, cooldown 20 min) | 2.3 | 1.2% | 0.8 | 24 | 748 | +724 | 3.2 | 1 | 0.2 | 0.0 |

Conservation check passed for every run (Coins and DCoins).

## How to read this
- **Player model is an assumption** (same for every setting): how often players accept, follow and which amount they pick.
  It sets the absolute numbers; the comparison between settings is what matters.
- **Time in requests** counts reading the prompt (5 s) and, after accepting, walking to the NPC's stand and choosing (≈30 s).
- **Net Coins/h** = stand donations + playtime rewards + return gifts − Coins donated to NPCs. It stays positive at every
  setting, so requests never drain a new player; at 0 Coins the player simply cannot afford an offer ("couldn't afford").
- **DCoins/h** grows with frequency because every donation to an NPC grants DCoins; requests are the main DCoins tap,
  so this rate drives how fast secondary progression moves.
- **Ignored after accept** is how often a player agrees and then doesn't follow; each one costs relationship/reputation
  once those systems are wired. Frequent requests multiply these penalties.

## Findings
- **A (≈22/h, one every ~3 min)** takes 10–18% of play time and produces 1.3–2.2 ignored requests per hour. Too intrusive.
- **B (current draft, ≈10/h)** costs 5–8% of play time. Workable for engaged players, likely tiring for casual ones.
- **C (≈6/h, one every ~10 min)** costs 3–5% of play time, earns about the same DCoins per Coin donated as B, and cuts ignored requests by 30–45%.
- **D–E (2–4/h)** barely interrupt but make DCoins progression slow (3–8 DCoins/h).

## Recommendation (not final)
Start playtests with **C: chance 0.02 per 30-second check (scaled by sociability), 8-minute cooldown, about 6 requests per
hour**. B is the upper bound. Decide after the request flow exists in-game, because the real accept/follow rates and how the
camera focus feels will change these numbers. Also decide how DCoins prices are set, since request frequency is their main income.

Reproduce: `lune run sim/requests 4 16`.
