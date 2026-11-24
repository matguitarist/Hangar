# Architecture review, 2026-11-23 (end of M2)

Survey: 4,400 lines. The biggest files are `HangarKit/Scanner.swift` (336), `Hangar/AppModel+Actions.swift` (303) and `Hangar/AppModel.swift` (294); none is near 600. M2 added `Runners.swift`, `BottleConfig.swift` (cxbottle.conf and registry editing that keeps files byte for byte) and `BottleCopy.swift` in HangarKit, and the Settings tab (`GameSettingsView`, `LaunchOptionsSection`) in the app. Per-game choices live in `GameOptions` on `Game`, kept across scans by `LibraryFile.merge`.

## Moving a game to a copied bottle in HangarKit  [Strong] (done)
`AppModel.giveOwnBottle` carried library rules in the main-actor model: which fields follow the game, how collections are remapped, and which entries leave. Only the self-test could reach them. They are now `LibraryFile.moveGame(from:to:)` with a unit test; the model only copies the bottle, scans and selects.

## A runner protocol  [Worth exploring]
`LaunchPlanner` now has three shapes: Mac (open, Launch Services), CrossOver (wine --bottle, with a Steam and a shortcut branch) and a prefix runner (Wine builds, Game Porting Toolkit). Each reads `GameOptions` its own way. A `Runner` with one adapter per kind would keep each runner's paths, arguments and environment in one place, and M3's recipes (which set a runner) would ask it what applies. Worth doing when a fourth kind (MacRunner) launches games.

## Split the library store from the window state  [Worth exploring]
Unchanged from M1: `AppModel` holds the saved library and the window. M3's snapshots and recipes add stored data again (snapshot lists, applied recipes); a `LibraryStore` owning `LibraryFile`, saving and undo would keep `AppModel` about the window. Do it if M3 adds a second saved file next to library.json.

## GameOptions decoding by hand  [Speculative]
Every new option needs a CodingKey, a default and a `decodeIfPresent` line. A property wrapper for defaults would shorten it; four fields don't justify it yet.
