# Architecture review, 2026-11-24 (end of M4)

Survey: 7,800 lines. The biggest files are `Hangar/AppModel.swift` (358), `HangarKit/Scanner.swift` (340), `Hangar/AppModel+Actions.swift` (334), `HangarKit/Model.swift` (304) and `HangarKit/SaveLocations.swift` (296); none is near 600. M4 added, in HangarKit: `SaveLocations.swift` (PCGamingWiki's save paths, placeholders to Mac paths, a cache), `SaveBackups.swift` (a store per game, ten kept, fingerprint to skip unchanged saves, restore by replace), `CrashReadout.swift` (Wine log lines to reasons, `LaunchPlan.loggingWine`), `WineLog.swift` (LogKit parser) and `GameDetails.swift` (Steam appdetails and TheGamesDB, a cache), each with unit tests. The app side follows M3's shape: one `AppModel` extension per feature (`+Saves`, `+Backups`, `+Crashes`) and one view per section or sheet.

## One web cache for the three sites  [Strong] (done)
`CompatibilityCache` (AppleGamingWiki), `GameDataCache` (PCGamingWiki) and `GameDetailsCache` (Steam, TheGamesDB) each repeated the same 12 lines: read a JSON file, use it while fresh, fetch and save, fall back to the old file offline, and cache "nothing found" as nil. A fix to one (say, a corrupt file) would have missed the other two. They now share `WebCacheFile<Value>` (`value(now:fetch:)`); each cache keeps only its own fetching and naming. Proof: the cache tests of all three (`theCacheKeepsPagesAMonthAndWorksOffline`, `detailsAreKeptAMonthAndOfflineUsesTheCache`, the compatibility cache tests) and the self-test pass unchanged. Files written by 0.3 use the old key name and are fetched again once.

## Split the library store from the window state  [Worth exploring]
M4 added the third store next to library.json (save backups), as its own type (`SaveBackupStore`), so `AppModel` didn't grow much (+36 lines, mostly keys and settings). The trigger from M3 has happened, but the cost of the split is still higher than its benefit. Do it with Undo for library edits, or when `AppModel` passes 400 lines.

## Launch as a pipeline  [Worth exploring]
`play` now runs four steps before the process starts: plan, Wine log, settings snapshot, save backup (async), then `launch`. Each M5 story adds one more (battery profile, S-025). A `LaunchPipeline` of steps, tested in HangarKit with a fake runner, would keep `AppModel+Actions` from growing a step per story. Do it with S-025.

## A runner protocol  [Worth exploring]
Unchanged from M3, with two more readers: `savePathContext` and `crashFix` each repeat "is this a bottle, a prefix, or a Mac app". One `Runner` adapter per kind would answer them, `LaunchPlanner`, `runnerVersion` and recipes. Do it with MacRunner launches.

## Considered, not recommended
- A shared HTTP client: `CoverCache.download` already serves covers and details; PCGamingWiki and AppleGamingWiki need their own status handling (404 is an answer).
- Merging `SavesSection` and `BackupsSheet` state into a model: the sheet reads `backupList` directly and is 120 lines.
