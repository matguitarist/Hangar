# Architecture review, 2026-11-24 (end of M3)

Survey: 6,000 lines. The biggest files are `HangarKit/Scanner.swift` (336), `Hangar/AppModel.swift` (322), `Hangar/AppModel+Actions.swift` (306), `HangarKit/Model.swift` (304) and `HangarKit/Recipes.swift` (292); none is near 600. M3 added, in HangarKit: `Snapshots.swift` (a store per game, byte-for-byte restore), `Recipes.swift` (manifest, checks, changes, apply), `RecipeShare.swift`, `RunnerUpdates.swift`, `Compatibility.swift` and `GameLinks.swift`, each with unit tests. The app side is one extension of `AppModel` per feature (`+Snapshots`, `+Recipes`) and one view file per section or sheet.

## One folder for everything a test run writes  [Strong] (done)
Each feature that saved a file next to the store (snapshots, runner versions, the AppleGamingWiki cache, the sample library) added its own `<store>-name` path in `App.swift`, and both scripts had to remember to remove it. One was forgotten and the self-test failed on its second run (FIXLOG, 2026-11-24). They now all go through `Store.runFile(_:)` into `<store>-run/`, and the scripts remove that one folder. Covers stay in `<store>-covers` on purpose, so snapshot runs don't fetch art again.

## Split the library store from the window state  [Worth exploring]
The M2 trigger happened: M3 saves two more things next to library.json. They went into their own types (`SnapshotStore`, `RunnerVersions`), not into `AppModel`, so the pressure is lower than expected. `AppModel` still owns `LibraryFile`, its saving and the window state together; do the split when M4's save backups add a third store or Undo for library edits arrives.

## A runner protocol  [Worth exploring]
Unchanged from M2, with one more reader: recipes apply only to CrossOver bottles (`AppModel.recipe(for:)`), and `runnerVersion` repeats the "which runner runs this game" choice that `LaunchPlanner` makes. A `Runner` adapter per kind would answer both. Do it with MacRunner launches or recipes for Wine prefixes.

## Recipe Undo survives only until quit  [Worth exploring]
`recipeUndo` is in memory. After a restart the "Applied / Undo" row is gone, though the snapshot taken before the recipe is still in the Snapshots sheet ("Before applying …"). Storing the applied recipe id on `GameOptions` would bring the row back; low cost, but no story asks for it yet.

## A bundled manifest with no recipes  [Speculative]
`Recipes/recipes.json` ships empty: no recipe has been tested on a real Mac yet. The brief calls for a fetched and cached manifest; when the first shared recipes arrive, fetching `Recipes/recipes.json` from GitHub with the same cache as AppleGamingWiki is the natural next step.
