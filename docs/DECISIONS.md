# Owner decisions — 2026-11-12 (APPROVED requirements)

These decisions extend the design brief (v0.2) and take priority over earlier proposals in this repository.

| # | Decision | How it is implemented | Verified by |
|---|---|---|---|
| 1 | **Coins = primary** (NPC donations, Robux packs). **DCoins = secondary**, earned ONLY by donating to NPCs; never sold, bundled or granted by unrelated rewards. **Pearls** must not be sold for Robux; propose safe removal. | `HarborShared/Config.Currencies`; `NpcCore/Config/Economy.MintReasons` allows DCoins only for `SecondaryReward`; `Rules.credit` rejects DCoins; Robux packs grant Coins only (`Config.Products`, `Purchases`); new profiles start with 0 DCoins. Pearls: see [PEARLS.md](PEARLS.md). | Unit tests (mint allow-list, Rules), integration World A (no DCoins appear in 2 h) and World B (pack grants Coins only, idempotent) |
| 2 | Remove player-to-player donations and Robux transfers; keep the architecture extensible. | `Donate`/`Transfer` remote actions removed (`Main`), `Profiles.transfer` removed, Robux transfer receipt handlers removed (`Purchases`), client donate buttons unbound. A future P2P service would plug in next to `Economy.receiveNpcDonation` using the same ledger rules. | Integration World A (actions ignored) |
| 3 | Playtime/daily/quest rewards may stay but never grant DCoins; balance separately; no other DCoins sources. | Unchanged reward logic, which only grants Coins (and legacy Pearls, pending the Pearls decision). | Unit test (Rules never touch DCoins), integration (Coins = daily + playtime + NPC donations exactly) |
| 4 | Do not finalise the request frequency; test alternatives and report. | `Config/Npc.Request` marked UNDER EVALUATION; study in [REQUEST_FREQUENCY.md](REQUEST_FREQUENCY.md). The in-game request flow is not built yet. | `lune run sim/requests` |
| 5 | Backups may move to a separate archive file; nothing deleted; restorable; verify no dependencies. | `tools/build-place` writes `MyGame_v2.rbxlx` + `ServerStorageBackups_Archive.rbxmx`; the original file is never modified. See "Backups" below. | Build verification (untouched instances identical; archive read back) |
| 6 | Replace timer-based NPC donations with autonomous behaviour; no currency from nothing or duplicated. | Timer loop removed from `Donations`; `NpcDirector` runs visit → inspect → decide → pay from the NPC's own budget through the ledger. | Integration World A (conservation audit every 30 s, history = CoinsRaised, offers respected), unit tests |
| 7 | Preserve the map and working systems; test integrated systems; evaluate 100 NPCs in Studio; report limits. | Existing scripts edited in place (diff against `legacy/place-scripts`); headless integration harness runs the real server scripts. **Studio profiling still has to be run by the owner** — see [STUDIO_TESTING.md](STUDIO_TESTING.md). | Integration harness; Studio pending |
| 8 | 2–3 original UI concepts with visuals; owner chooses before full UI work. | [UI_CONCEPTS.md](UI_CONCEPTS.md), mockups in `docs/ui-concepts/`. No new in-game UI was built. | Owner review |

## Backups (decision 5)
- Moved: `ServerStorage.OldMap_Backup`, `HarborEnvironmentBackup2026`, `MapCleanup_Backup` (7,683 instances) into
  `ServerStorageBackups_Archive.rbxmx`. The updated place drops from 37.2 MB to 15.6 MB.
- Dependencies checked (`tools/backup-refs`): no runtime script requires the map tools that mention the backups
  (`ReplicatedStorage.Shared.*` are Studio-only helpers), and **0 references** point from the live place into the backups.
- 601 `__CleanupParent` restore pointers inside `MapCleanup_Backup` point to live `Workspace.Map` folders. A model
  file cannot keep references outside itself, so each pointer also carries its target as a `RestoreTargetPath` attribute.
- **Restore:** the original `MyGame.rbxlx` is untouched and remains the full restore point. To bring the backups into
  the new place, right-click ServerStorage → *Insert from File…* → the archive. To repair the cleanup pointers afterwards,
  run in the command bar:
  ```lua
  for _, v in game.ServerStorage.MapCleanup_Backup:GetDescendants() do
      local p = v:IsA("ObjectValue") and v:GetAttribute("RestoreTargetPath")
      if p then local i = game; for n in p:gmatch("[^%.]+") do i = i and i:FindFirstChild(n) end; v.Value = i end
  end
  ```
- Note: the place round-trip was verified for instance names, classes, part position/size/colour/material/transparency and
  script sources. Open the new file in Studio and compare it visually before replacing your working copy.

## Exceptions you should know about
- **Pre-update transfers:** player-to-player DCoins transfers that were already paid before the update are still delivered
  (`Profiles.reconcile`), so no player loses currency they sent. No new transfers can be created.
- **Existing DCoins balances** (old 500 starting grant and test donations) are kept as they are. `Config.Migration.QuarantineTestDCoins`
  can move them to a non-spendable `LegacyDCoins` field instead (tested, off by default). **Owner decision needed.**
