# Testing in Roblox Studio (including 100 NPCs)

The headless tests cover logic and server-script integration, but **not** physics, pathfinding, replication or frame
time. Those can only be measured in Studio, and nobody has run this build in Studio yet. Please run the steps below and
paste the Output lines back.

## Load the build
Either open `MyGame_v2.rbxl` (binary; the XML `.rbxlx` build has identical content), or keep your own file and sync with Rojo (`rojo serve`, then connect from the Rojo plugin).
Rojo only replaces `ServerScriptService.HarborServer`, `ServerScriptService.NpcCore`, `ReplicatedStorage.HarborShared`
and `StarterPlayer.StarterPlayerScripts.HarborClient`; the map is not touched.

## 1. Gameplay check (normal population)
1. Test tab → **Play**. Output shows `[Harbor] Server ready`, `[NPC] Ready: ...` and `[NPC] Director started: serverWealth=...`.
2. NPCs fade in at the map edges, walk between booths, stop at some, and some later claim booths (sign shows their name and offers).
3. Claim a booth (hold E). The sign lists `5 · 10 · 25 · 50 · 100 Coins`.
4. Wait. Donations appear as toasts ("+100 Coins") and the HUD balance rises. Expect long gaps; that is intended.
5. Every 30 s Output prints `[NPC_DIRECTOR] ... conserved=true`. **Any `conserved=false` is a bug — please send it.**

## 2. Performance at 25 / 50 / 100 NPCs
For realistic numbers use Test → **Start** with *Local Server* and 1 player (the server runs separately from the client).
In the server window's command bar:
```lua
workspace:SetAttribute("NpcStressTarget", 25)   -- then 50, then 100; nil returns to normal arrivals
```
Wait 3 minutes at each level, then copy the last two `[NPC_PERF]` and `[NPC_HEALTH]` lines. Also note:
- Developer Console (F9) → *Server* → **Memory** total, and **Network** "Data Send" kB/s.
- MicroProfiler (Ctrl+F6) on the server: anything in `Heartbeat` taking > 4 ms.
- The client's FPS while standing in the plaza with all NPCs visible.

### What the numbers mean (proposed targets, not yet agreed)
| Field | Meaning | Proposed target at 100 NPCs |
|---|---|---|
| `meanFrameMS` / `maxFrameMS` | server frame time | mean ≤ 18 ms (≥ 55 FPS), max ≤ 50 ms |
| `npcTickMeanMS` / `npcTickMaxMS` | time spent in NPC movement updates per tick | mean ≤ 2 ms, max ≤ 8 ms |
| `pathsInFlight` / `queued` | pathfinding pressure (max 4 in flight) | `queued` not growing over time |
| `pathMeanMS` / `pathMaxMS` | path computation time | mean ≤ 30 ms |
| `queueTimeouts`, `lost`, `falls`, `recoveries` | movement failures | rare; `lost` near 0 |
| Network send | replication of 100 humanoids | ≤ 50 kB/s per player |

## Known risks to look for
- **Humanoid cost.** 100 server-simulated R15 humanoids is the most likely bottleneck. If frame time is over target, the
  first options (no change to NPC decisions) are: lower `TickSeconds` work for distant NPCs further, cache routes between
  waypoints, or move animation to the client. Any change that alters behaviour needs your approval.
- **Booth approach side.** Visitors stand on the side away from each booth's sign board. If they stand behind counters, tell me which booths.
- **Waypoints.** The map has no authored NPC waypoints; ~36 are generated from fixed offsets. Authoring `NPCWaypoint`-tagged
  parts along the bridges and market streets will give more natural routes.
