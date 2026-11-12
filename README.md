# NPC Donation Simulator

A Roblox donation game built on the existing **CloudHarbor** map, where autonomous NPCs with wallets,
personalities and opinions are the main source of activity. The design brief is the source of truth.

- `docs/AUDIT.md`: Phase 1 audit of `MyGame.rbxlx`: inventory, status against the brief, risks
- `docs/ARCHITECTURE.md`: how the new NPC core plugs into the existing `HarborServer` systems, save schema, phases
- `docs/SIMULATION.md`: balance simulation results against the brief's reference targets

## Layout
| Path | Contents |
|---|---|
| `src/server/Config` | Every tunable value (economy, NPCs, offline, luck, persistence). All values are **proposals** until the owner approves them |
| `src/server/Logic` | Pure Luau: NPC brain, NPC factory/offers, ledger and transactions, secondary reward, offline earnings, statistics, relationships, luck |
| `tests/run.luau` | Unit tests (Lune) |
| `sim/balance.luau` | Headless market simulation using the same logic as the game |
| `tools/` | Place-file audit and script extraction |
| `legacy/place-scripts` | Snapshot of the scripts inside `MyGame.rbxlx` at audit time (reference only, not synced) |

## Commands
Tools are pinned in `mise.toml` (`mise install`).
```
lune run tests/run                                   # unit tests
lune run sim/balance 6 24                            # 24 runs × 6 simulated hours per scenario
luau-analyze src/server/Logic/*.luau src/server/Config/*.luau
rojo build default.project.json -o build/NpcCore.rbxlx
rojo serve                                           # syncs into ServerScriptService.NpcCore only
```
The Rojo project maps only `ServerScriptService.NpcCore`, so syncing never touches the map or the existing scripts.
