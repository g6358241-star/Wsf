# Pearls — audit and removal proposal

Decision (2026-11-12): Pearls must not be sold for Robux. Remove or replace them safely, without deleting player data.

## Where Pearls exist today
| Kind | Location | Amount |
|---|---|---|
| Robux sale | `Config.Products` SupportSmall/Large (+2 / +10) | **Removed** in this update: packs grant Coins only |
| Daily reward | `Rules.daily`, `Config.DailyPearls` | 5 per UTC day |
| Quests | `Config.Quests` Welcome/Explorer/Collector | 1 / 3 / 5 |
| Playtime | `Rules.tick` | 1 per 5 minutes played |
| Spending | `Config.Shop` Captain title (30), Golden booth trim (20), 2× coin boost (10) | |
| Storage | profile field `Pearls`, `leaderstats.Pearls` | kept untouched |

No Pearls are shown in the current HUD, so most players likely don't know their balance.

## Options
1. **Freeze (recommended first step, fully reversible).** Stop new Pearl grants from daily, quests and playtime. Keep
   balances and the three Pearl items purchasable with existing Pearls. Code change: three config values to 0.
2. **Convert to Coins (recommended second step).** One-time, idempotent conversion at a fixed rate (e.g. 1 Pearl = 10 Coins,
   rate OPEN). The profile keeps `LegacyPearls` (the original amount) and a receipt `convert:pearls:v1` so it can never run
   twice; the Pearl items are repriced in Coins. **Not into DCoins**, which would break decision 1.
3. **Keep Pearls as a third earn-only currency.** Possible, but adds a currency the brief does not ask for and overlaps with DCoins.

Nothing in options 1–2 deletes data: the original amounts stay in each save. Pick a conversion rate and whether to run
step 2 immediately or after a notice period.
