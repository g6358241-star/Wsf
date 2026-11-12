# NPC Donation Simulator

A Roblox donation game on the existing **CloudHarbor** map, where autonomous NPCs with wallets, personalities and
opinions are the main source of activity. The design brief (v0.2) plus [docs/DECISIONS.md](docs/DECISIONS.md) are the requirements.

| Doc | Contents |
|---|---|
| [DECISIONS.md](docs/DECISIONS.md) | Owner decisions of 2026-11-12, how each is implemented, backups and restore |
| [AUDIT.md](docs/AUDIT.md) | Phase 1 audit of `MyGame.rbxlx` |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, money flow, save schema v2, phase status |
| [STUDIO_TESTING.md](docs/STUDIO_TESTING.md) | How to test in Studio, including the 100-NPC performance run |
| [SIMULATION.md](docs/SIMULATION.md) | Stand income balance results |
| [REQUEST_FREQUENCY.md](docs/REQUEST_FREQUENCY.md) | NPC request frequency study and recommendation |
| [PEARLS.md](docs/PEARLS.md) | Pearls audit and removal options |
| [UI_CONCEPTS.md](docs/UI_CONCEPTS.md) | Three UI concepts with mockups (`docs/ui-concepts/`) |

## Layout
| Path | In Roblox | Contents |
|---|---|---|
| `src/HarborServer` | `ServerScriptService.HarborServer` | Existing server systems (edited) + `NpcDirector` |
| `src/NpcCore` | `ServerScriptService.NpcCore` | Pure NPC/economy logic and all tunable config (values are proposals unless marked APPROVED) |
| `src/HarborShared` | `ReplicatedStorage.HarborShared` | Shared config and reward rules |
| `src/HarborClient` | `StarterPlayer.StarterPlayerScripts.HarborClient` | Existing client scripts (minor edits) |
| `legacy/place-scripts` | — | Scripts as they were in `MyGame.rbxlx` at audit time, for diffs |
| `tests/` | — | Unit tests and the headless integration harness |
| `sim/` | — | Market simulation: stand income and request frequency |
| `tools/` | — | Place audit, backup reference check, place build/archive |

## Commands
Tools are pinned in `mise.toml` (`mise install`).
```
lune run tests/run                 # unit tests
lune run tests/integration         # real server scripts, mocked engine, 2+ simulated hours
lune run sim/balance 6 24          # stand income per listing
lune run sim/requests 4 16         # NPC request frequency study
lune run tools/build-place MyGame.rbxlx build/MyGame_v2.rbxl build/ServerStorageBackups_Archive.rbxm   # .rbxl = binary, .rbxlx = XML
lune run tools/compare-places MyGame.rbxlx build/MyGame_v2.rbxl   # meshes, text, lights, lighting unchanged
rojo serve                         # sync the four script folders into an open place
```
Rojo maps only the four script folders, so syncing never touches the map.
