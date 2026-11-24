# Architecture review, 2026-11-24 (end of M5)

Survey: the biggest files are `Sources/Hangar/AppModel.swift` (385), `Sources/HangarKit/Scanner.swift` (367), `Sources/Hangar/Snapshot.swift` (356), `Sources/Hangar/AppModel+Actions.swift` (352), `Sources/HangarKit/Model.swift` (317); none is near 600. M5 added Shortcuts actions (`Intents.swift`, App Intents metadata made by `build.sh` with `appintentsmetadataprocessor`, since `swift build` doesn't), Heroic as a source (`HangarKit/Heroic.swift`: a scanner and `HeroicGame`, launched by `heroic://`), and a sign-in check before launch (`SteamScanner.lastSessionSignedOut`).

## A runner protocol  [Worth exploring, trigger close]
Heroic is a fourth answer to "is this a bottle, a prefix, Heroic, or a Mac app", now asked in `LaunchPlanner.basePlan`, `savePathContext`, `runnerVersion`, `GameSettingsView` and `GameTile`'s badge help. One `Runner` adapter per kind would answer them all and give each a test adapter. Not done unattended: it touches launch, saves and settings at once, and each branch is still two to four lines. Do it before a fifth kind (MacRunner launches, Parallels).

## Intents reach the model through a static  [Worth exploring]
`IntentModel.model` is a weak static the model sets in `init`. `AppDependencyManager` is the system's seam for this, and would let a test give intents a model of its own. Today the self-test runs intents against the app's own model, which is enough.

## Launch as a pipeline  [Worth exploring]
Unchanged from M4: `play` gained one more early step (the sign-in check). Still readable at one screen.

## Considered, not recommended
- A Heroic settings editor: Heroic owns `GamesConfig/<app>.json` and rewrites it; Hangar writing it would race Heroic.
